param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfilePath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\qdm_fx_focus_pack.csv"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$syncScript = Join-Path $ProjectRoot "RUN\SYNC_QDM_FOCUS_PACK.ps1"
$exportScript = Join-Path $ProjectRoot "RUN\EXPORT_QDM_FOCUS_PACK_TO_MT5.ps1"

if (-not (Test-Path -LiteralPath $syncScript)) {
    throw "Sync script not found: $syncScript"
}
if (-not (Test-Path -LiteralPath $exportScript)) {
    throw "Export script not found: $exportScript"
}
if (-not (Test-Path -LiteralPath $ProfilePath)) {
    throw "FX QDM profile not found: $ProfilePath"
}

Write-Host "=== FX QDM PIPELINE: SYNC ==="
& $syncScript -ProfilePath $ProfilePath

Write-Host "=== FX QDM PIPELINE: EXPORT TO MT5 ==="
& $exportScript -ProfilePath $ProfilePath

Write-Host "FX QDM pipeline finished."
