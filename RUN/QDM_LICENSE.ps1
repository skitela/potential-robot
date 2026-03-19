param(
    [ValidateSet("info", "update")]
    [string]$Action = "info",
    [string]$Code = "",
    [string]$QdmRoot = "C:\TRADING_TOOLS\QuantDataManager"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$qdmCli = Join-Path $QdmRoot "qdmcli.exe"
if (-not (Test-Path -LiteralPath $qdmCli)) {
    throw "QDM CLI not found: $qdmCli"
}

$arguments = @("-license", "action=$Action")

if ($Action -eq "update") {
    if ([string]::IsNullOrWhiteSpace($Code)) {
        throw "For action=update you must provide -Code."
    }

    $arguments += "code=$Code"
}

& $qdmCli @arguments
