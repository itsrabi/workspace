param(
  [int]$Seconds = 25,
  [int]$Every = 1
)

$start = Get-Date
while(((Get-Date) - $start).TotalSeconds -lt $Seconds){
  tmux ls 2>$null | ForEach-Object { $_ } | Select-String -Pattern 'subagent-|pi-subagent-' -AllMatches | ForEach-Object { $_.Line }
  Start-Sleep -Seconds $Every
}
