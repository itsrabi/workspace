param(
  [int]$Seconds = 24,
  [int]$Every = 2
)

$i = 0
$steps = [Math]::Ceiling($Seconds / $Every)
for($j=0; $j -lt $steps; $j++){
  tmux ls 2>$null | Out-String
  Start-Sleep -Seconds $Every
}
