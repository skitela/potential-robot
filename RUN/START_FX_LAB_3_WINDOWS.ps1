param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$fxMt5Batch = Join-Path $ProjectRoot "RUN\START_FX_MT5_BATCH_BACKGROUND.ps1"
$fxMl = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"
$tuningScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"
$opsArchiver = Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1"
$mt5Watcher = Join-Path $ProjectRoot "RUN\START_MT5_TESTER_STATUS_WATCHER_BACKGROUND.ps1"

if (-not (Test-Path -LiteralPath $fxMt5Batch)) {
    throw "FX MT5 launcher not found: $fxMt5Batch"
}
if (-not (Test-Path -LiteralPath $fxMl)) {
    throw "FX ML launcher not found: $fxMl"
}
if (-not (Test-Path -LiteralPath $tuningScript)) {
    throw "Workstation tuning script not found: $tuningScript"
}
if (-not (Test-Path -LiteralPath $opsArchiver)) {
    throw "Operator archiver launcher not found: $opsArchiver"
}
if (-not (Test-Path -LiteralPath $mt5Watcher)) {
    throw "MT5 tester watcher launcher not found: $mt5Watcher"
}

Write-Host "Applying workstation tuning for FX lab..."
& $tuningScript -ThrottleInteractiveApps -MlPerfProfile "ConcurrentLab" | Out-Host

Write-Host "Starting local operator archiver..."
& $opsArchiver

Write-Host "Starting MT5 tester status watcher..."
& $mt5Watcher

Write-Host "Starting FX window 1: MT5 tester batch..."
& $fxMt5Batch

Write-Host "FX window 2: current QDM sync/export lane stays active if already running."
Write-Host "If needed later, start dedicated FX QDM lane with START_FX_QDM_PIPELINE_BACKGROUND.ps1."

Write-Host "Starting FX window 3: ML refresh+train..."
& $fxMl

Write-Host "FX 3-window lab launch finished."
