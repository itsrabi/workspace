param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('Workspace', 'Sandbox')]
  [string]$Action,

  [Parameter(Mandatory = $false)]
  [string]$WorkspaceImage = 'fedora-workspace:latest',

  [Parameter(Mandatory = $false)]
  [string]$WorkspaceContainer = 'fedora-workspace',

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

  # Drop "X:\" or "X:/" prefix.
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

function Require-WorkspaceContainerRunning {
  param(
    [Parameter(Mandatory = $true)]
    [string]$Name
  )

  $status = (podman inspect --format '{{.State.Status}}' $Name 2>$null).Trim()
  if ([string]::IsNullOrWhiteSpace($status) -or $status.ToLowerInvariant() -ne 'running') {
    Write-Host "Workspace container '$Name' is not running. Run make workspace first."
    exit 1
  }
}

# Compute RepoRoot from the script location.
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if ($Action -eq 'Workspace') {
  $repoContainerPath = $null
  try {
    $repoContainerPath = Convert-WindowsPathToContainerPath -WindowsPath $RepoRoot
  } catch {
    # Translation failure should fail make workspace immediately.
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

  foreach ($letter in $driveLetters) {
    $hostRoot = "${letter}:\\"
    $podmanRunArgs += @('-v', "${hostRoot}:/mnt/${letter}")
  }

  if ($null -ne $containerHostEnv) {
    # sandbox creation from inside the workspace relies on talking to the
    # host Podman socket (/run/podman/podman.sock). The socket is owned by
    # root:root with mode 660, so we must run as the image's non-root UID
    # (developer:1000) *and* be in gid 0 (root) to get group permissions.
    $podmanRunArgs += @(
      '--user', '1000:0',
      '--group-add', '10',
      '--env', ('CONTAINER_HOST=' + $containerHostEnv)
    )
     $podmanRunArgs += $socketMountArgs
  }

  $podmanRunArgs += @(
    '--env', ('SANDBOX_IMAGE=' + $WorkspaceImage),
    $WorkspaceImage,
    'sleep',
    'infinity'
  )

  & podman @podmanRunArgs

  # After the container starts, run the repo-owned smoke-check script from the mounted repo path.
  $smokeScriptPath = "$repoContainerPath/scripts/smoke-check.sh"
  $smokeScriptPathEsc = Escape-BashSingleQuotes $smokeScriptPath

  podman exec $WorkspaceContainer bash -lc "test -f '$smokeScriptPathEsc'" 1>$null
  if ($LASTEXITCODE -ne 0) {
    throw "Smoke script missing at mounted path: $smokeScriptPath"
  }

  & podman exec $WorkspaceContainer bash -lc "bash '$smokeScriptPathEsc'"
  $smokeExit = $LASTEXITCODE
  if ($smokeExit -ne 0) {
    # Propagate failure but leave the container running.
    exit $smokeExit
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
