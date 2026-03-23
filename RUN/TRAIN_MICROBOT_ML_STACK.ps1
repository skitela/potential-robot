param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$paperGateScript = Join-Path $ProjectRoot "RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1"
$perSymbolScript = Join-Path $ProjectRoot "RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODELS_PER_SYMBOL.ps1"
if (-not (Test-Path -LiteralPath $paperGateScript)) {
    throw "Paper gate trainer not found: $paperGateScript"
}
if (-not (Test-Path -LiteralPath $perSymbolScript)) {
    throw "Per-symbol paper gate trainer not found: $perSymbolScript"
}

Write-Host "=== TRAIN PAPER GATE ACCEPTOR ==="
& $paperGateScript -PerfProfile $PerfProfile

Write-Host "=== TRAIN PAPER GATE ACCEPTOR PER SYMBOL ==="
& $perSymbolScript -ProjectRoot $ProjectRoot -PerfProfile $PerfProfile

Write-Host "MicroBot ML stack training finished."
