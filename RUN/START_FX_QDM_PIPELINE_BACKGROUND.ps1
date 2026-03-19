param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_fx_focus_pack.csv",
    [string]$LogRoot = "C:\TRADING_DATA\QDM\logs"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pipelineScript = Join-Path $ProjectRoot "RUN\RUN_FX_QDM_PIPELINE.ps1"
if (-not (Test-Path -LiteralPath $pipelineScript)) {
    throw "FX QDM pipeline script not found: $pipelineScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot "fx_qdm_pipeline_$timestamp.log"
$wrapperPath = Join-Path $env:TEMP "fx_qdm_pipeline_wrapper_$timestamp.ps1"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$pipelineScript' -ProjectRoot '$ProjectRoot' -ProfilePath '$ProfilePath'
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

Write-Host "Background FX QDM pipeline started."
Write-Host "Log: $logPath"
