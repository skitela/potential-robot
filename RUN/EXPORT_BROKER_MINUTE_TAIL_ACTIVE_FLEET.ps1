param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalOrigin = "C:\Program Files\OANDA TMS MT5 Terminal",
    [int]$HoursBack = 96,
    [int]$TimeoutSec = 480,
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\broker_minute_tail_active_fleet_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$inventoryPath = "C:\TRADING_DATA\RESEARCH\datasets\qdm_tick_inventory_latest.csv"
$exportScript = Join-Path $ProjectRoot "RUN\EXPORT_BROKER_MINUTE_TAIL.ps1"

if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Registry file not found: $registryPath"
}
if (-not (Test-Path -LiteralPath $inventoryPath)) {
    throw "QDM inventory not found: $inventoryPath"
}
if (-not (Test-Path -LiteralPath $exportScript)) {
    throw "Broker tail export script not found: $exportScript"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$inventoryRows = Import-Csv -LiteralPath $inventoryPath

$exportNames = New-Object System.Collections.Generic.List[string]
$symbolAliases = New-Object System.Collections.Generic.List[string]
$brokerSymbols = New-Object System.Collections.Generic.List[string]
$mapping = New-Object System.Collections.Generic.List[object]

foreach ($symbol in @($registry.symbols)) {
    $alias = [string]$symbol.symbol
    $brokerSymbol = [string]$symbol.broker_symbol
    $inventoryRow = @($inventoryRows | Where-Object { $_.symbol_alias -eq $alias } | Select-Object -First 1)
    if ($inventoryRow.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$inventoryRow[0].export_name)) {
        throw "Export name not found in qdm inventory for symbol_alias=$alias"
    }

    $exportName = [string]$inventoryRow[0].export_name
    $exportNames.Add($exportName)
    $symbolAliases.Add($alias)
    $brokerSymbols.Add($brokerSymbol)
    $mapping.Add([pscustomobject]@{
        symbol_alias = $alias
        broker_symbol = $brokerSymbol
        export_name = $exportName
    })
}

$result = & $exportScript `
    -ProjectRoot $ProjectRoot `
    -TerminalOrigin $TerminalOrigin `
    -ExportNames $exportNames.ToArray() `
    -SymbolAliases $symbolAliases.ToArray() `
    -BrokerSymbols $brokerSymbols.ToArray() `
    -HoursBack $HoursBack `
    -TimeoutSec $TimeoutSec

$resultObject = if ($result -is [string]) { $result | ConvertFrom-Json } else { $result }
$status = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    terminal_origin = $TerminalOrigin
    hours_back = $HoursBack
    symbol_count = $mapping.Count
    mapping = $mapping
    export_result = $resultObject
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$status | ConvertTo-Json -Depth 8
