param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
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

Write-Host "=== QDM FOCUS PIPELINE: SYNC ==="
& $syncScript

Write-Host "=== QDM FOCUS PIPELINE: EXPORT TO MT5 ==="
& $exportScript

Write-Host "QDM focus pipeline finished."
