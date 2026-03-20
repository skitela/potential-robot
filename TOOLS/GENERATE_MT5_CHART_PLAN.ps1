param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json

$rows = @()
$index = 1
foreach ($item in $registry.symbols) {
    $canonicalSymbol = Get-RegistryCanonicalSymbol -RegistryItem $item
    $brokerSymbol = Get-RegistryBrokerSymbol -RegistryItem $item
    $rows += [PSCustomObject]@{
        chart_no = $index
        symbol = $canonicalSymbol
        broker_symbol = $brokerSymbol
        expert = [string]$item.expert
        preset = [string]$item.preset
        magic = [string]$item.magic
        chart_tf = [string]$item.chart_tf
        session_profile = [string]$item.session_profile
        status = [string]$item.status
    }
    $index++
}

$txtPath = Join-Path $ProjectRoot "DOCS\\06_MT5_CHART_ATTACHMENT_PLAN.txt"
$jsonPath = Join-Path $ProjectRoot "DOCS\\06_MT5_CHART_ATTACHMENT_PLAN.json"

$lines = @()
$lines += "MT5 CHART ATTACHMENT PLAN"
$lines += ""
foreach ($row in $rows) {
    $lines += ("Chart {0}: {1} [{2}] -> {3} -> {4} -> Magic={5} -> TF={6} -> Session={7} -> Status={8}" -f $row.chart_no,$row.symbol,$row.broker_symbol,$row.expert,$row.preset,$row.magic,$row.chart_tf,$row.session_profile,$row.status)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$rows | Format-Table -AutoSize
