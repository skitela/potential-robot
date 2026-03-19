param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\RESEARCH\reports"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pipelineScript = Join-Path $ProjectRoot "RUN\REFRESH_AND_TRAIN_MICROBOT_ML.ps1"
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "Pipeline script not found: $pipelineScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "refresh_and_train_ml_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "refresh_and_train_ml_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$pipelineScript'
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

Write-Host "Background refresh+train ML pipeline started."
Write-Host "Log: $logPath"
