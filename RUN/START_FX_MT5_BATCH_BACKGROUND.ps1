param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\fx_lab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$batchScript = Join-Path $ProjectRoot "RUN\RUN_FX_MT5_BATCH.ps1"
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "FX MT5 batch script not found: $batchScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "fx_mt5_batch_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "fx_mt5_batch_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$batchScript' -ProjectRoot '$ProjectRoot'
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -WorkingDirectory $ProjectRoot

Write-Host "Background FX MT5 batch started."
Write-Host "Log: $logPath"
