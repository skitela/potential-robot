param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$waitScript = Join-Path $ProjectRoot "RUN\WAIT_QDM_IDLE_AND_START_FX_FULL_SYNC.ps1"
if (-not (Test-Path -LiteralPath $waitScript)) {
    throw "FX full QDM idle watcher not found: $waitScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "qdm_fx_full_after_idle_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "qdm_fx_full_after_idle_wrapper_$timestamp.ps1"

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

Write-Host "Background QDM FX-full-after-idle watcher started."
Write-Host "Log: $logPath"
