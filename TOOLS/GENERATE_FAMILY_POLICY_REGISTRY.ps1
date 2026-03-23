param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$configPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$evidencePath = Join-Path $ProjectRoot "EVIDENCE\\family_policy_registry_report.json"

$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json
$microbotRegistry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json

$activeSymbols = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in $microbotRegistry.symbols) {
    if ($item.PSObject.Properties.Name -contains 'symbol' -and -not [string]::IsNullOrWhiteSpace([string]$item.symbol)) {
        [void]$activeSymbols.Add([string]$item.symbol)
    }
    if ($item.PSObject.Properties.Name -contains 'broker_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$item.broker_symbol)) {
        [void]$activeSymbols.Add([string]$item.broker_symbol)
    }
    if ($item.PSObject.Properties.Name -contains 'code_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$item.code_symbol)) {
        [void]$activeSymbols.Add([string]$item.code_symbol)
    }
}

$activeVariants = @(
    $variantRegistry.variants | Where-Object {
        $alias = if ($_.PSObject.Properties.Name -contains 'alias_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$_.alias_symbol)) {
            [string]$_.alias_symbol
        } else {
            [string]$_.symbol
        }

        $activeSymbols.Contains([string]$_.symbol) -or $activeSymbols.Contains($alias)
    }
)

$families = @()
foreach ($group in ($activeVariants | Group-Object { $_.profile.session_profile } | Sort-Object Name)) {
    $starts = @($group.Group | ForEach-Object { [int]$_.profile.trade_window_start_hour } | Sort-Object -Unique)
    $ends = @($group.Group | ForEach-Object { [int]$_.profile.trade_window_end_hour } | Sort-Object -Unique)
    $spreads = @($group.Group | ForEach-Object { [int]$_.profile.max_spread_points } | Sort-Object -Unique)
    $cautionTriggers = @($group.Group | ForEach-Object { [double]$_.decision.caution_trigger_abs } | Sort-Object -Unique)
    $readyTriggers = @($group.Group | ForEach-Object { [double]$_.decision.ready_trigger_abs } | Sort-Object -Unique)
    $setups = @($group.Group | ForEach-Object { $_.decision.setup_labels } | ForEach-Object { $_ } | Sort-Object -Unique)
    $symbols = @($group.Group | ForEach-Object { $_.symbol } | Sort-Object)

    $families += [ordered]@{
        family = $group.Name
        symbols = $symbols
        invariants = [ordered]@{
            trade_tf = (($group.Group | ForEach-Object { $_.profile.trade_tf } | Sort-Object -Unique) -join ",")
            atr_period = (($group.Group | ForEach-Object { $_.indicators.atr_period } | Sort-Object -Unique) -join ",")
            rsi_period = (($group.Group | ForEach-Object { $_.indicators.rsi_period } | Sort-Object -Unique) -join ",")
            uses_new_bar_gate = (($group.Group | ForEach-Object { $_.model.uses_new_bar_gate } | Sort-Object -Unique) -join ",")
            has_live_manage_position = (($group.Group | ForEach-Object { $_.model.has_live_manage_position } | Sort-Object -Unique) -join ",")
        }
        allowed_ranges = [ordered]@{
            trade_window_start_hour = @{ min = ($starts | Measure-Object -Minimum).Minimum; max = ($starts | Measure-Object -Maximum).Maximum }
            trade_window_end_hour = @{ min = ($ends | Measure-Object -Minimum).Minimum; max = ($ends | Measure-Object -Maximum).Maximum }
            max_spread_points = @{ min = ($spreads | Measure-Object -Minimum).Minimum; max = ($spreads | Measure-Object -Maximum).Maximum }
            caution_trigger_abs = @{ min = ($cautionTriggers | Measure-Object -Minimum).Minimum; max = ($cautionTriggers | Measure-Object -Maximum).Maximum }
            ready_trigger_abs = @{ min = ($readyTriggers | Measure-Object -Minimum).Minimum; max = ($readyTriggers | Measure-Object -Maximum).Maximum }
        }
        allowed_setup_labels = $setups
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    family_count = $families.Count
    families = $families
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
