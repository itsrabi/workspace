param(
  [switch]$DryRun
)

function Test-Podman {
  try {
    $null = Get-Command podman -ErrorAction Stop
    return $true
  } catch {
    return $false
  }
}

if (Test-Podman) {
  Write-Host "Podman already installed."
  exit 0
}

if ($DryRun) {
  Write-Host "[dry-run] Would attempt Podman installation on Windows."
  exit 0
}

# Try Winget first.
$winget = Get-Command winget -ErrorAction SilentlyContinue
if ($null -ne $winget) {
  # ID can vary; try common one first.
  Write-Host "Attempting to install Podman via winget..."
  $installOk = $false

  $candidates = @(
    "RedHat.Podman",
    "Podman.Podman"
  )

  foreach ($id in $candidates) {
    try {
      # --silent may not be supported by all manifests; keep it best-effort.
      & winget install --id $id --exact --silent --accept-package-agreements --accept-source-agreements
      $installOk = $true
      break
    } catch {
      # continue
    }
  }

  if ($installOk -and (Test-Podman)) {
    Write-Host "Podman installation complete via winget."
    exit 0
  }
}

Write-Host "Automatic install failed or winget not available."
Write-Host "Please install Podman manually, then re-run make install."
Write-Host "Download: https://podman.io/getting-started/installation"
exit 1
