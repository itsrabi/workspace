param(
  [string]$Label = 'SLEPT_DONE',
  [int]$Seconds = 20
)

Start-Sleep -Seconds $Seconds
Write-Output $Label
