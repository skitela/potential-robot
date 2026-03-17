param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = 'Stop'

$variants = Get-Content (Join-Path $ProjectRoot "CONFIG\strategy_variant_registry.json") -Raw | ConvertFrom-Json
$families = @{}
foreach ($variant in $variants.variants) {
    $family = [string]$variant.profile.session_profile
    if (-not $families.ContainsKey($family)) {
        $families[$family] = @()
    }
    $families[$family] += $variant
}

$results = @()

function Add-ScenarioResult {
    param(
        [string]$Family,
        [string]$Scenario,
        [bool]$Ok,
        [string]$Detail
    )
    $script:results += [pscustomobject]@{
        family = $Family
        scenario = $Scenario
        ok = $Ok
        detail = $Detail
    }
}

foreach ($family in $families.Keys | Sort-Object) {
    $items = @($families[$family])
    $labels = @($items | ForEach-Object { $_.decision.setup_labels } | ForEach-Object { $_ })

    Add-ScenarioResult $family 'trend_support_present' (($labels -contains 'SETUP_TREND') -or ($labels -contains 'SETUP_TREND_ASIA')) 'Family has trend scenario support'
    Add-ScenarioResult $family 'breakout_support_present' (($labels -contains 'SETUP_BREAKOUT') -or ($labels -contains 'SETUP_BREAKOUT_ASIA')) 'Family has breakout scenario support'

    switch ($family) {
        'FX_MAIN' {
            Add-ScenarioResult $family 'rejection_or_reversal_present' (
                ($labels -contains 'SETUP_REJECTION') -or ($labels -contains 'SETUP_REVERSAL')
            ) 'Main family should support at least one mean-reversion style scenario'
        }
        'FX_ASIA' {
            Add-ScenarioResult $family 'asia_specific_labels_present' (
                ($labels -contains 'SETUP_BREAKOUT_ASIA') -and ($labels -contains 'SETUP_PULLBACK_ASIA')
            ) 'Asia family should expose asia-specific labels'
            Add-ScenarioResult $family 'range_support_present' (
                ($labels -contains 'SETUP_RANGE')
            ) 'Asia family should include at least one range-aware variant'
        }
        'FX_CROSS' {
            Add-ScenarioResult $family 'pullback_support_present' (
                ($labels -contains 'SETUP_PULLBACK')
            ) 'Cross family should expose pullback scenario support'
            Add-ScenarioResult $family 'range_support_present' (
                ($labels -contains 'SETUP_RANGE')
            ) 'Cross family should include at least one range-aware variant'
        }
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    ok = ($results.ok -notcontains $false)
    results = $results
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\family_scenario_test_report.json"
$txtPath = Join-Path $ProjectRoot "EVIDENCE\family_scenario_test_report.txt"
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @(
    "FAMILY SCENARIO TEST REPORT",
    ("OK={0}" -f $report.ok),
    ""
)
foreach ($row in $results) {
    $lines += ("{0} | {1} | {2} | {3}" -f $row.family,$row.scenario,$row.ok,$row.detail)
}
$lines | Set-Content -LiteralPath $txtPath -Encoding ASCII

$report | ConvertTo-Json -Depth 6
