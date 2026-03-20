param()

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$activePath = Join-Path $root "CONFIG\strategy.json"

if (-not (Test-Path $activePath)) {
    throw "Missing active strategy: $activePath"
}

$active = Get-Content -Path $activePath -Raw | ConvertFrom-Json
$tradeWindows = @($active.trade_windows.PSObject.Properties.Name)
$symbols = @($active.symbols_to_trade)

$report = [ordered]@{
    ok = $true
    active_path = $activePath
    profile_active = [bool]$active.free_window_training_profile_active
    season = [string]$active.free_window_training_profile_season
    schema = [string]$active.free_window_training_profile_schema
    symbols_to_trade = $symbols
    trade_windows = $tradeWindows
    broad_windows_removed = -not (($tradeWindows -contains "FX_AM") -or ($tradeWindows -contains "FX_ASIA") -or ($tradeWindows -contains "INDEX_EU") -or ($tradeWindows -contains "INDEX_US") -or ($tradeWindows -contains "METAL_PM"))
    strict_group_routing = [bool]$active.trade_window_strict_group_routing
    hard_no_mt5_outside_windows = [bool]$active.hard_no_mt5_outside_windows
    symbol_filter_enabled = [bool]$active.trade_window_symbol_filter_enabled
}

if (-not $report.profile_active) { $report.ok = $false }
if (-not $report.broad_windows_removed) { $report.ok = $false }
if (-not $report.strict_group_routing) { $report.ok = $false }
if (-not $report.hard_no_mt5_outside_windows) { $report.ok = $false }
if (-not $report.symbol_filter_enabled) { $report.ok = $false }

$report | ConvertTo-Json -Depth 8
