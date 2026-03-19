param(
    [string]$InstallRoot = "C:\TRADING_TOOLS\QuantDataManager"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$exePath = Join-Path $InstallRoot "QuantDataManager.exe"
if (-not (Test-Path -LiteralPath $exePath)) {
    throw "QuantDataManager.exe not found: $exePath"
}

Start-Process -FilePath $exePath -WorkingDirectory $InstallRoot
