param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pipelineScript = Join-Path $ProjectRoot "RUN\RUN_QDM_FOCUS_PIPELINE.ps1"
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "Pipeline script not found: $pipelineScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "qdm_focus_pipeline_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "qdm_focus_pipeline_wrapper_$timestamp.ps1"

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
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Hidden

Write-Host "Background QDM focus pipeline started."
Write-Host "Log: $logPath"
