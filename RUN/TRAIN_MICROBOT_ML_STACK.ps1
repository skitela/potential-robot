param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$paperGateScript = Join-Path $ProjectRoot "RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1"
$localTrainingLaneScript = Join-Path $ProjectRoot "RUN\RUN_LIMITED_LOCAL_TRAINING_LANE.ps1"
if (-not (Test-Path -LiteralPath $paperGateScript)) {
    throw "Paper gate trainer not found: $paperGateScript"
}
if (-not (Test-Path -LiteralPath $localTrainingLaneScript)) {
    throw "Limited local training lane not found: $localTrainingLaneScript"
}

Write-Host "=== TRAIN PAPER GATE ACCEPTOR ==="
& $paperGateScript -PerfProfile $PerfProfile

Write-Host "=== RUN LIMITED LOCAL TRAINING LANE ==="
& $localTrainingLaneScript -ProjectRoot $ProjectRoot -PerfProfile $PerfProfile

Write-Host "MicroBot ML stack training finished."
