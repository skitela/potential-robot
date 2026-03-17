param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$registry = Get-Content -LiteralPath $registryPath -Encoding UTF8 | ConvertFrom-Json

$rows = @()
$index = 1
foreach ($item in $registry.symbols) {
    $rows += [PSCustomObject]@{
        chart_no = $index
        symbol = [string]$item.symbol
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
    $lines += ("Chart {0}: {1} -> {2} -> {3} -> Magic={4} -> TF={5} -> Session={6} -> Status={7}" -f $row.chart_no,$row.symbol,$row.expert,$row.preset,$row.magic,$row.chart_tf,$row.session_profile,$row.status)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$rows | Format-Table -AutoSize
