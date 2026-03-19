param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$fxMt5Batch = Join-Path $ProjectRoot "RUN\START_FX_MT5_BATCH_BACKGROUND.ps1"
$fxMl = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"

if (-not (Test-Path -LiteralPath $fxMt5Batch)) {
    throw "FX MT5 launcher not found: $fxMt5Batch"
}
if (-not (Test-Path -LiteralPath $fxMl)) {
    throw "FX ML launcher not found: $fxMl"
}

Write-Host "Starting FX window 1: MT5 tester batch..."
& $fxMt5Batch

Write-Host "FX window 2: current QDM sync/export lane stays active if already running."
Write-Host "If needed later, start dedicated FX QDM lane with START_FX_QDM_PIPELINE_BACKGROUND.ps1."

Write-Host "Starting FX window 3: ML refresh+train..."
& $fxMl

Write-Host "FX 3-window lab launch finished."
