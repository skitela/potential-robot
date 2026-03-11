param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet(0, 1, 2)]
    [int]$SecurityLayer = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$helper = Join-Path $runtimeRoot "TOOLS\vps_enable_rdp.ps1"
if (-not (Test-Path -LiteralPath $helper)) {
    throw "Brak helpera: $helper"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $helper -DisableNla -SecurityLayer $SecurityLayer
Write-Output ("REPAIR_VPS_RDP_AUTH_OK security_layer={0}" -f [int]$SecurityLayer)
exit 0
