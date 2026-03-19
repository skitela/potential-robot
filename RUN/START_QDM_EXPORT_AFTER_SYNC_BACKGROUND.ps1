param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$waitScript = Join-Path $ProjectRoot "RUN\WAIT_QDM_SYNC_AND_EXPORT.ps1"
if (-not (Test-Path -LiteralPath $waitScript)) {
    throw "Wait-and-export script not found: $waitScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "qdm_export_after_sync_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "qdm_export_after_sync_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$waitScript'
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -WorkingDirectory $ProjectRoot `
    -PassThru

try {
    $proc.PriorityClass = "AboveNormal"
}
catch {
}

Write-Host "Background QDM export-after-sync watcher started."
Write-Host "Log: $logPath"
