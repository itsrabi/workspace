param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Start', 'Shell', 'Stop', 'Remove', 'Sandbox')]
  [string]$Action,

  [Parameter(Mandatory = $true)]
  [string]$Image,

  [Parameter(Mandatory = $false)]
  [string]$WorkspaceContainer = 'workspace',

  [Parameter(Mandatory = $true)]
  [string]$HostUsername,

  [Parameter(Mandatory = $false)]
  [string]$SourceDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-WindowsPathToContainerPath {
  param(
    [Parameter(Mandatory = $true)]
    [string]$WindowsPath
  )

  if ($WindowsPath -notmatch '^(?<drive>[A-Za-z]):[\\/]') {
    throw "Unsupported path format (expected drive-rooted Windows path like D:\\...): $WindowsPath"
  }

  $driveLetter = $Matches.drive.ToLowerInvariant()

  # Drop "X:\\" or "X:/" prefix.
  $remainder = $WindowsPath -replace '^[A-Za-z]:[\\/]+', ''
  $remainder = $remainder -replace '\\', '/'

  if ([string]::IsNullOrWhiteSpace($remainder)) {
    return "/mnt/$driveLetter"
  }

  return "/mnt/$driveLetter/$remainder"
}

function Escape-BashSingleQuotes {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Value
  )

  # In bash, end single quotes, emit escaped single quote, restart.
  #   'foo'bar'baz' -> 'foo'\''bar'\''baz'
  return $Value.Replace("'", "'\\''")
}

function Get-PodmanRemoteSocketPath {
  $out = (podman info --format '{{.Host.RemoteSocket.Path}}' 2>$null).Trim()
  if ([string]::IsNullOrWhiteSpace($out)) { return $null }
  return $out
}

function Get-DevContainerForwardPorts {
  param(
    [Parameter(Mandatory = $true)]
    [string]$RepoRoot
  )

  $devContainerPath = Join-Path $RepoRoot 'container/devcontainer.json'
  if (-not (Test-Path -LiteralPath $devContainerPath)) {
    return @()
  }

  # Keep parsing narrow and boring: this repo's devcontainer.json uses whole-line
  # JSONC comments, so stripping comment-only lines is sufficient.
  $jsonWithComments = Get-Content -LiteralPath $devContainerPath -Raw
  $json = ($jsonWithComments -split '\r?\n' | Where-Object { $_ -notmatch '^\s*//' }) -join "`n"
  $config = $json | ConvertFrom-Json

  if ($null -eq $config.forwardPorts) {
    return @()
  }

  return @($config.forwardPorts)
}

function Get-PodmanPublishArgsFromForwardPorts {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$ForwardPorts
  )

  $publishArgs = @()
  foreach ($forwardPort in $ForwardPorts) {
    $portSpec = [string]$forwardPort
    if ($portSpec -match '^\d+$') {
      $publishArgs += @('--publish', "${portSpec}:${portSpec}")
      continue
    }

    if ($portSpec -match '^(?<start>\d+)-(?<end>\d+)$') {
      $start = [int]$Matches.start
      $end = [int]$Matches.end
      if ($end -lt $start) {
        throw "Invalid forwardPorts range '$portSpec' in container/devcontainer.json"
      }

      $publishArgs += @('--publish', "${start}-${end}:${start}-${end}")
      continue
    }

    throw "Unsupported forwardPorts entry '$portSpec' in container/devcontainer.json. Expected a port number or start-end range."
  }

  return $publishArgs
}

function Get-ForwardPortSmokePorts {
  param(
    [Parameter(Mandatory = $true)]
    [object[]]$ForwardPorts
  )

  $smokePorts = @()
  foreach ($forwardPort in $ForwardPorts) {
    $portSpec = [string]$forwardPort
    if ($portSpec -match '^\d+$') {
      $smokePorts += [int]$portSpec
      continue
    }

    if ($portSpec -match '^(?<start>\d+)-(?<end>\d+)$') {
      $start = [int]$Matches.start
      $end = [int]$Matches.end
      if ($end -lt $start) {
        throw "Invalid forwardPorts range '$portSpec' in container/devcontainer.json"
      }

      $smokePorts += $start
      if ($end -ne $start) {
        $smokePorts += $end
      }
      continue
    }

    throw "Unsupported forwardPorts entry '$portSpec' in container/devcontainer.json. Expected a port number or start-end range."
  }

  return $smokePorts
}

function Start-WorkspacePortSmokeServer {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $true)]
    [int]$Port
  )

  $token = "workspace-port-smoke-$Port"
  $serveDir = "/tmp/workspace-port-smoke-$Port"
  $indexPath = "$serveDir/index.html"
  $logPath = "/tmp/workspace-port-smoke-$Port.log"
  $pidFile = "/tmp/workspace-port-smoke-$Port.pid"

  $cmd = ('rm -rf ''{0}''; mkdir -p ''{0}''; printf ''%s'' ''{1}'' > ''{2}''; python3 -m http.server {3} --bind 0.0.0.0 --directory ''{0}'' > ''{4}'' 2>&1 & echo $! > ''{5}''' -f (Escape-BashSingleQuotes $serveDir), (Escape-BashSingleQuotes $token), (Escape-BashSingleQuotes $indexPath), $Port, (Escape-BashSingleQuotes $logPath), (Escape-BashSingleQuotes $pidFile))

  & podman exec $ContainerName bash -lc $cmd 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to start forwarded-port smoke server on port $Port inside container '$ContainerName'"
  }
}

function Stop-WorkspacePortSmokeServer {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $true)]
    [int]$Port
  )

  $pidFile = "/tmp/workspace-port-smoke-$Port.pid"
  $cmd = ('if [ -f ''{0}'' ]; then kill $(cat ''{0}'') 2>/dev/null || true; rm -f ''{0}''; fi' -f (Escape-BashSingleQuotes $pidFile))

  & podman exec $ContainerName bash -lc $cmd 1>$null 2>$null
}

function Get-WorkspaceHostSmokeCandidates {
  $candidates = @('127.0.0.1')

  try {
    $machineIpLines = & podman machine ssh ip -4 -o addr show scope global 2>$null
    if ($LASTEXITCODE -eq 0) {
      foreach ($line in @($machineIpLines)) {
        if ($line -match '\binet\s+(?<ip>\d+\.\d+\.\d+\.\d+)/') {
          $ip = $Matches.ip
          if (-not [string]::IsNullOrWhiteSpace($ip) -and $ip -ne '127.0.0.1') {
            $candidates += $ip
          }
        }
      }
    }
  } catch {
  }

  return @($candidates | Sort-Object -Unique)
}

function Assert-WorkspaceForwardPortsReachable {
  param(
    [Parameter(Mandatory = $true)]
    [string]$ContainerName,

    [Parameter(Mandatory = $true)]
    [object[]]$ForwardPorts
  )

  $smokePorts = Get-ForwardPortSmokePorts -ForwardPorts $ForwardPorts
  if ($smokePorts.Count -eq 0) {
    return
  }

  $hostCandidates = Get-WorkspaceHostSmokeCandidates

  Write-Host '== Host-side forwarded port smoke =='
  foreach ($port in $smokePorts) {
    Start-WorkspacePortSmokeServer -ContainerName $ContainerName -Port $port
  }

  try {
    foreach ($port in $smokePorts) {
      $expected = "workspace-port-smoke-$port"
      $verified = $false

      foreach ($candidateHost in $hostCandidates) {
        $uri = "http://${candidateHost}:$port/"
        $deadline = (Get-Date).AddSeconds(5)

        while ((Get-Date) -lt $deadline) {
          try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri $uri -TimeoutSec 2
            if ($response.Content -eq $expected) {
              $verified = $true
              Write-Host "[ok] $uri -> $expected"
              break
            }
          } catch {
          }

          Start-Sleep -Milliseconds 500
        }

        if ($verified) {
          break
        }
      }

      if (-not $verified) {
        throw "Forwarded port smoke failed for port $port. Tried hosts: $($hostCandidates -join ', '). Expected body '$expected'."
      }
    }
  } finally {
    foreach ($port in $smokePorts) {
      Stop-WorkspacePortSmokeServer -ContainerName $ContainerName -Port $port
    }
  }
}

function Require-WorkspaceContainerRunning {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $status = (podman inspect --format '{{.State.Status}}' $Name 2>$null).Trim()
  if ([string]::IsNullOrWhiteSpace($status) -or $status.ToLowerInvariant() -ne 'running') {
    Write-Host "Workspace container '$Name' is not running. Run make container-start first."
    exit 1
  }
}

# Compute RepoRoot from the script location.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path

if ($Action -eq 'Start') {
  $repoContainerPath = $null
  try {
    $repoContainerPath = Convert-WindowsPathToContainerPath -WindowsPath $RepoRoot
  } catch {
    # Translation failure should fail make container-start immediately.
    throw
  }

  # Enumerate host drives and bind-mount each drive root.
  $driveLetters = Get-PSDrive -PSProvider FileSystem |
    Where-Object { $_.Name -match '^[A-Za-z]$' } |
    ForEach-Object { $_.Name.ToLowerInvariant() } |
    Sort-Object -Unique

  $socketMountArgs = @()
  $containerHostEnv = $null

  # Discover podman remote socket (for nested sandbox creation).
  $remoteSocketPath = Get-PodmanRemoteSocketPath
  if (-not [string]::IsNullOrWhiteSpace($remoteSocketPath)) {
    # podman may return unix:///absolute/path/to/socket; convert to a filesystem path.
    $remoteSocketFsPath = $remoteSocketPath
    if ($remoteSocketPath -match '^unix://(?<p>.+)$') {
      $remoteSocketFsPath = $Matches.p
    }

    # Mount it even if a filesystem existence check fails; podman/machine backends
    # may expose the socket via a path that appears transient from PowerShell.
    $socketMountArgs = @('-v', "${remoteSocketFsPath}:/run/podman/podman.sock")
    $containerHostEnv = 'unix:///run/podman/podman.sock'
  } else {
    Write-Host "[warn] Podman remote socket unavailable; sandbox creation from inside the workspace will be unavailable."
  }

  # Recreate workspace container deterministically.
  podman rm -f $WorkspaceContainer 2>$null | Out-Null

  $podmanRunArgs = @(
    'run',
    '-d',
    '--name', $WorkspaceContainer,
    '--hostname', $WorkspaceContainer,
    '-w', '/workspaces'
  )

  $forwardPorts = Get-DevContainerForwardPorts -RepoRoot $RepoRoot
  if (@($forwardPorts).Count -gt 0) {
    $podmanRunArgs += Get-PodmanPublishArgsFromForwardPorts -ForwardPorts $forwardPorts
  }

  foreach ($letter in $driveLetters) {
    $hostRoot = "${letter}:\\"
    $podmanRunArgs += @('-v', "${hostRoot}:/mnt/${letter}")
  }

  if ($null -ne $containerHostEnv) {
    # sandbox creation from inside the workspace relies on talking to the
    # host Podman socket (/run/podman/podman.sock).
    $podmanRunArgs += @(
      '--user', '1000:0',
      '--group-add', '10',
      '--env', ('CONTAINER_HOST=' + $containerHostEnv)
    )

    $podmanRunArgs += $socketMountArgs
  }

  $podmanRunArgs += @(
    '--env', ('SANDBOX_IMAGE=' + $Image),
    $Image,
    'sleep',
    'infinity'
  )

  try {
    & podman @podmanRunArgs
  } catch {
    if (@($forwardPorts).Count -gt 0) {
      Write-Host "[warn] Podman failed to publish devcontainer forwardPorts (likely port conflict). Retrying without port publishing."
      $podmanRunArgsNoPorts = @()
      for ($i = 0; $i -lt $podmanRunArgs.Count; $i++) {
        if ($podmanRunArgs[$i] -eq '--publish') {
          # Skip '--publish' and the following value like '3000-3999:3000-3999'.
          $i++
          continue
        }
        $podmanRunArgsNoPorts += $podmanRunArgs[$i]
      }

      & podman @podmanRunArgsNoPorts
    } else {
      throw
    }
  }

  # After the container starts, run the repo-owned smoke-check script from the mounted repo path.
  $smokeScriptPath = "$repoContainerPath/scripts/container/smoke-check.sh"
  $smokeScriptPathEsc = Escape-BashSingleQuotes $smokeScriptPath

  podman exec $WorkspaceContainer bash -lc "test -f '$smokeScriptPathEsc'" 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Smoke script missing at mounted path: $smokeScriptPath"
  }

  & podman exec $WorkspaceContainer bash -lc "EXPECTED_USER='$(Escape-BashSingleQuotes $HostUsername)' bash '$smokeScriptPathEsc'"
  $smokeExit = $LASTEXITCODE
  if ($smokeExit -ne 0) {
    # Propagate failure but leave the container running.
    exit $smokeExit
  }

  if (@($forwardPorts).Count -gt 0) {
    Assert-WorkspaceForwardPortsReachable -ContainerName $WorkspaceContainer -ForwardPorts $forwardPorts
  }

  exit 0
}

if ($Action -eq 'Shell') {
  Require-WorkspaceContainerRunning -Name $WorkspaceContainer
  & podman exec -it $WorkspaceContainer bash
  exit $LASTEXITCODE
}

if ($Action -eq 'Stop') {
  if (podman container exists $WorkspaceContainer 2>$null) {
    & podman stop $WorkspaceContainer >/dev/null
  }
  exit 0
}

if ($Action -eq 'Remove') {
  if (podman container exists $WorkspaceContainer 2>$null) {
    & podman rm -f $WorkspaceContainer >/dev/null
  }
  exit 0
}

if ($Action -eq 'Sandbox') {
  if ([string]::IsNullOrWhiteSpace($SourceDir)) {
    throw 'SourceDir is required for -Action Sandbox'
  }

  Require-WorkspaceContainerRunning -Name $WorkspaceContainer

  $translatedPath = Convert-WindowsPathToContainerPath -WindowsPath $SourceDir
  $translatedPathEsc = Escape-BashSingleQuotes $translatedPath

  & podman exec -it $WorkspaceContainer bash -lc "cd '$translatedPathEsc' && sandbox run"
  exit $LASTEXITCODE
}

throw "Unsupported Action '$Action'"

