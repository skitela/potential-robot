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
$learningHygieneScript = Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_PATH_HYGIENE.ps1"
$learningHotPathScript = Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_SUPERVISOR_HOT_PATH.ps1"

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
if (-not (Test-Path -LiteralPath $learningHygieneScript)) {
    throw "Learning hygiene script not found: $learningHygieneScript"
}
if (-not (Test-Path -LiteralPath $learningHotPathScript)) {
    throw "Learning hot-path script not found: $learningHotPathScript"
}

& $tuningScript -ThrottleInteractiveApps -MlPerfProfile $PerfProfile | Out-Host

Write-Host "=== REFRESH RESEARCH DATA ==="
& $refreshScript -ProjectRoot $ProjectRoot -PerfProfile $PerfProfile

Write-Host "=== REBUILD ONNX FEEDBACK LOOP ==="
& $onnxFeedbackScript -ProjectRoot $ProjectRoot

Write-Host "=== TRAIN MICROBOTS ML STACK ==="
& $trainScript -ProjectRoot $ProjectRoot -PerfProfile $PerfProfile

Write-Host "=== CLEAN LEARNING PATH HYGIENE ==="
& $learningHygieneScript -ProjectRoot $ProjectRoot -Apply | Out-Null

Write-Host "=== CLEAN LEARNING HOT PATH ==="
& $learningHotPathScript -ProjectRoot $ProjectRoot -Apply | Out-Null

Write-Host "Refresh + train pipeline finished."
