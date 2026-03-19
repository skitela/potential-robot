param(
    [string]$Code = "",
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$storeScript = Join-Path $ProjectRoot "RUN\STORE_QDM_LICENSE_SECRET.ps1"
$applyScript = Join-Path $ProjectRoot "RUN\APPLY_QDM_LICENSE_FROM_SECRET.ps1"

if (-not (Test-Path -LiteralPath $storeScript)) {
    throw "Store script not found: $storeScript"
}
if (-not (Test-Path -LiteralPath $applyScript)) {
    throw "Apply script not found: $applyScript"
}

if ([string]::IsNullOrWhiteSpace($Code)) {
    $Code = Read-Host "Podaj kod licencji QDM"
}

& $storeScript -Code $Code
& $applyScript
