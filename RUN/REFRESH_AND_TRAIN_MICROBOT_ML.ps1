param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$refreshScript = Join-Path $ProjectRoot "RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1"
$trainScript = Join-Path $ProjectRoot "RUN\TRAIN_MICROBOT_ML_STACK.ps1"
$onnxFeedbackScript = Join-Path $ProjectRoot "RUN\BUILD_ONNX_FEEDBACK_LOOP_REPORT.ps1"
$tuningScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"

if (-not (Test-Path -LiteralPath $refreshScript)) {
    throw "Research refresh script not found: $refreshScript"
}
if (-not (Test-Path -LiteralPath $trainScript)) {
    throw "ML training script not found: $trainScript"
}
if (-not (Test-Path -LiteralPath $onnxFeedbackScript)) {
    throw "ONNX feedback report script not found: $onnxFeedbackScript"
}
if (-not (Test-Path -LiteralPath $tuningScript)) {
    throw "Workstation tuning script not found: $tuningScript"
}

& $tuningScript -ThrottleInteractiveApps -MlPerfProfile $PerfProfile | Out-Host

Write-Host "=== REFRESH RESEARCH DATA ==="
& $refreshScript -ProjectRoot $ProjectRoot -PerfProfile $PerfProfile

Write-Host "=== REBUILD ONNX FEEDBACK LOOP ==="
& $onnxFeedbackScript -ProjectRoot $ProjectRoot

Write-Host "=== TRAIN MICROBOTS ML STACK ==="
& $trainScript -ProjectRoot $ProjectRoot -PerfProfile $PerfProfile

Write-Host "Refresh + train pipeline finished."
