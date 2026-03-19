param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$refreshScript = Join-Path $ProjectRoot "RUN\REFRESH_MICROBOT_RESEARCH_DATA.ps1"
$trainScript = Join-Path $ProjectRoot "RUN\TRAIN_MICROBOT_ML_STACK.ps1"

if (-not (Test-Path -LiteralPath $refreshScript)) {
    throw "Research refresh script not found: $refreshScript"
}
if (-not (Test-Path -LiteralPath $trainScript)) {
    throw "ML training script not found: $trainScript"
}

Write-Host "=== REFRESH RESEARCH DATA ==="
& $refreshScript

Write-Host "=== TRAIN MICROBOTS ML STACK ==="
& $trainScript

Write-Host "Refresh + train pipeline finished."
