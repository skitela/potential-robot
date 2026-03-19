param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$syncScript = Join-Path $ProjectRoot "RUN\SYNC_QDM_FOCUS_PACK.ps1"
if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Sync script not found: $syncScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "qdm_focus_sync_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "qdm_focus_sync_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$syncScript'
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -Priority AboveNormal `
    -WorkingDirectory $ProjectRoot

Write-Host "Background QDM focus sync started."
Write-Host "Log: $logPath"
