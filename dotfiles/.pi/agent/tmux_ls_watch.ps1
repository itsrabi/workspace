param(
  [int]$Seconds = 15,
  [int]$Every = 1
)

for($i=0; $i -lt $Seconds; $i += $Every){
  tmux ls 2>$null | Out-String
  Start-Sleep -Seconds $Every
}
