# The "Tests" command in solo.yml: runs tests\run.ps1 once, then keeps running, because Solo only
# watches files while the command is alive. A change to a Lua, TOC or XML file makes Solo restart it.
# Outside Solo, run .\tests\run.ps1 instead.
#   .\tests\watch.ps1         failures and the summary
#   .\tests\watch.ps1 -All    every check
param([switch]$All)

Write-Host ("--- Tests {0:HH:mm:ss}" -f (Get-Date))
$global:LASTEXITCODE = 0
# An error in run.ps1 itself (e.g. the MoonSharp download) must not end the watcher.
try {
    & (Join-Path $PSScriptRoot 'run.ps1') -All:$All
} catch {
    Write-Output "ABORTED: $_"
    $global:LASTEXITCODE = 1
}
if ($LASTEXITCODE -eq 0) {
    Write-Host 'PASSED' -ForegroundColor Green
} else {
    Write-Host 'FAILED' -ForegroundColor Red
}
Write-Host 'Waiting for changes...' -ForegroundColor DarkGray
while ($true) { Start-Sleep -Seconds 3600 }
