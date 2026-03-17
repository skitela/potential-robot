param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-TradeTfToChartTf {
    param([string]$TradeTf)
    switch ($TradeTf) {
        "PERIOD_M5" { return "M5" }
        "PERIOD_M15" { return "M15" }
        "PERIOD_H1" { return "H1" }
        default { return $TradeTf }
    }
}

$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
$jsonReport = Join-Path $evidenceDir "symbol_policy_consistency_report.json"
$txtReport = Join-Path $evidenceDir "symbol_policy_consistency_report.txt"

$registry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json

$variantBySymbol = @{}
foreach ($variant in $variantRegistry.variants) {
    $variantBySymbol[$variant.symbol] = $variant
}

$checks = @()
$mismatches = @()

foreach ($entry in $registry.symbols) {
    $variant = $variantBySymbol[$entry.symbol]
    if ($null -eq $variant) {
        $mismatches += [ordered]@{
            symbol = $entry.symbol
            field = "variant"
            registry = "<missing>"
            expected = "variant entry present"
        }
        continue
    }

    $expectedChartTf = Convert-TradeTfToChartTf $variant.profile.trade_tf
    $row = [ordered]@{
        symbol = $entry.symbol
        registry_session_profile = $entry.session_profile
        variant_session_profile = $variant.profile.session_profile
        registry_chart_tf = $entry.chart_tf
        variant_chart_tf = $expectedChartTf
        trade_window = "{0}-{1}" -f $variant.profile.trade_window_start_hour,$variant.profile.trade_window_end_hour
        setup_labels = @($variant.decision.setup_labels)
        ok = $true
    }

    if ($entry.session_profile -ne $variant.profile.session_profile) {
        $row.ok = $false
        $mismatches += [ordered]@{
            symbol = $entry.symbol
            field = "session_profile"
            registry = $entry.session_profile
            expected = $variant.profile.session_profile
        }
    }

    if ($entry.chart_tf -ne $expectedChartTf) {
        $row.ok = $false
        $mismatches += [ordered]@{
            symbol = $entry.symbol
            field = "chart_tf"
            registry = $entry.chart_tf
            expected = $expectedChartTf
        }
    }

    $checks += [pscustomobject]$row
}

$familySummaries = @()
foreach ($group in ($variantRegistry.variants | Group-Object { $_.profile.session_profile })) {
    $starts = @($group.Group | ForEach-Object { [int]$_.profile.trade_window_start_hour } | Sort-Object -Unique)
    $ends = @($group.Group | ForEach-Object { [int]$_.profile.trade_window_end_hour } | Sort-Object -Unique)
    $setups = @($group.Group | ForEach-Object { $_.decision.setup_labels } | ForEach-Object { $_ } | Sort-Object -Unique)
    $familySummaries += [ordered]@{
        family = $group.Name
        symbols = @($group.Group | ForEach-Object { $_.symbol })
        distinct_window_starts = $starts
        distinct_window_ends = $ends
        distinct_setup_labels = $setups
        shared_trade_tf = (($group.Group | ForEach-Object { $_.profile.trade_tf } | Sort-Object -Unique) -join ",")
        shared_atr_period = (($group.Group | ForEach-Object { $_.indicators.atr_period } | Sort-Object -Unique) -join ",")
        shared_rsi_period = (($group.Group | ForEach-Object { $_.indicators.rsi_period } | Sort-Object -Unique) -join ",")
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    ok = ($mismatches.Count -eq 0)
    checks = @($checks)
    mismatches = @($mismatches)
    family_summaries = @($familySummaries)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReport -Encoding UTF8

$lines = @()
$lines += "Symbol policy consistency report"
$lines += "ok=$($report.ok)"
$lines += ""
foreach ($check in $checks) {
    $lines += ("{0}: family={1}, tf={2}, window={3}, ok={4}" -f $check.symbol,$check.variant_session_profile,$check.variant_chart_tf,$check.trade_window,$check.ok)
}
$lines += ""
$lines += "Family summaries:"
foreach ($family in $familySummaries) {
    $lines += ("- {0}: symbols={1}; starts={2}; ends={3}; setups={4}" -f $family.family,($family.symbols -join ","),($family.distinct_window_starts -join ","),($family.distinct_window_ends -join ","),($family.distinct_setup_labels -join ","))
}
if ($mismatches.Count -gt 0) {
    $lines += ""
    $lines += "Mismatches:"
    foreach ($item in $mismatches) {
        $lines += ("- {0} {1}: registry={2}, expected={3}" -f $item.symbol,$item.field,$item.registry,$item.expected)
    }
}
$lines | Set-Content -LiteralPath $txtReport -Encoding UTF8

$report | ConvertTo-Json -Depth 8

if ($mismatches.Count -gt 0) {
    exit 1
}
