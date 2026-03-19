param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$paperGateScript = Join-Path $ProjectRoot "RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.ps1"
if (-not (Test-Path -LiteralPath $paperGateScript)) {
    throw "Paper gate trainer not found: $paperGateScript"
}

Write-Host "=== TRAIN PAPER GATE ACCEPTOR ==="
& $paperGateScript

Write-Host "MicroBot ML stack training finished."
