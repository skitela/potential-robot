param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$familyPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$jsonReport = Join-Path $ProjectRoot "EVIDENCE\\family_policy_bounds_report.json"
$txtReport = Join-Path $ProjectRoot "EVIDENCE\\family_policy_bounds_report.txt"

$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json
$familyRegistry = Get-Content -Raw -LiteralPath $familyPath | ConvertFrom-Json

$families = @{}
foreach ($family in $familyRegistry.families) {
    $families[$family.family] = $family
}

$checks = @()
$issues = @()

foreach ($variant in $variantRegistry.variants) {
    $familyName = [string]$variant.profile.session_profile
    if (-not $families.ContainsKey($familyName)) {
        $issues += [ordered]@{
            symbol = $variant.symbol
            field = "family"
            actual = $familyName
            expected = "family present in family_policy_registry"
        }
        continue
    }

    $family = $families[$familyName]
    $allowedStart = [int]$family.allowed_ranges.trade_window_start_hour.min
    $allowedStartMax = [int]$family.allowed_ranges.trade_window_start_hour.max
    $allowedEnd = [int]$family.allowed_ranges.trade_window_end_hour.min
    $allowedEndMax = [int]$family.allowed_ranges.trade_window_end_hour.max
    $allowedSpreadMin = [int]$family.allowed_ranges.max_spread_points.min
    $allowedSpreadMax = [int]$family.allowed_ranges.max_spread_points.max
    $allowedReadyMin = [double]$family.allowed_ranges.ready_trigger_abs.min
    $allowedReadyMax = [double]$family.allowed_ranges.ready_trigger_abs.max
    $allowedCautionMin = [double]$family.allowed_ranges.caution_trigger_abs.min
    $allowedCautionMax = [double]$family.allowed_ranges.caution_trigger_abs.max

    $row = [ordered]@{
        symbol = $variant.symbol
        family = $familyName
        trade_window = "{0}-{1}" -f $variant.profile.trade_window_start_hour,$variant.profile.trade_window_end_hour
        max_spread_points = $variant.profile.max_spread_points
        ready_trigger_abs = $variant.decision.ready_trigger_abs
        caution_trigger_abs = $variant.decision.caution_trigger_abs
        ok = $true
    }

    if ($variant.profile.trade_window_start_hour -lt $allowedStart -or $variant.profile.trade_window_start_hour -gt $allowedStartMax) {
        $row.ok = $false
        $issues += [ordered]@{ symbol = $variant.symbol; field = "trade_window_start_hour"; actual = $variant.profile.trade_window_start_hour; expected = "$allowedStart..$allowedStartMax" }
    }
    if ($variant.profile.trade_window_end_hour -lt $allowedEnd -or $variant.profile.trade_window_end_hour -gt $allowedEndMax) {
        $row.ok = $false
        $issues += [ordered]@{ symbol = $variant.symbol; field = "trade_window_end_hour"; actual = $variant.profile.trade_window_end_hour; expected = "$allowedEnd..$allowedEndMax" }
    }
    if ($variant.profile.max_spread_points -lt $allowedSpreadMin -or $variant.profile.max_spread_points -gt $allowedSpreadMax) {
        $row.ok = $false
        $issues += [ordered]@{ symbol = $variant.symbol; field = "max_spread_points"; actual = $variant.profile.max_spread_points; expected = "$allowedSpreadMin..$allowedSpreadMax" }
    }
    if ($variant.decision.ready_trigger_abs -lt $allowedReadyMin -or $variant.decision.ready_trigger_abs -gt $allowedReadyMax) {
        $row.ok = $false
        $issues += [ordered]@{ symbol = $variant.symbol; field = "ready_trigger_abs"; actual = $variant.decision.ready_trigger_abs; expected = "$allowedReadyMin..$allowedReadyMax" }
    }
    if ($variant.decision.caution_trigger_abs -lt $allowedCautionMin -or $variant.decision.caution_trigger_abs -gt $allowedCautionMax) {
        $row.ok = $false
        $issues += [ordered]@{ symbol = $variant.symbol; field = "caution_trigger_abs"; actual = $variant.decision.caution_trigger_abs; expected = "$allowedCautionMin..$allowedCautionMax" }
    }

    foreach ($label in $variant.decision.setup_labels) {
        if ($family.allowed_setup_labels -notcontains $label) {
            $row.ok = $false
            $issues += [ordered]@{ symbol = $variant.symbol; field = "setup_label"; actual = $label; expected = ($family.allowed_setup_labels -join ",") }
        }
    }

    $checks += [pscustomobject]$row
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    ok = ($issues.Count -eq 0)
    checks = @($checks)
    issues = @($issues)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonReport -Encoding UTF8

$lines = @()
$lines += "Family policy bounds report"
$lines += "ok=$($report.ok)"
$lines += ""
foreach ($row in $checks) {
    $lines += ("{0}: family={1}, window={2}, spread={3}, ready={4}, caution={5}, ok={6}" -f $row.symbol,$row.family,$row.trade_window,$row.max_spread_points,$row.ready_trigger_abs,$row.caution_trigger_abs,$row.ok)
}
if ($issues.Count -gt 0) {
    $lines += ""
    $lines += "Issues:"
    foreach ($issue in $issues) {
        $lines += ("- {0} {1}: actual={2}, expected={3}" -f $issue.symbol,$issue.field,$issue.actual,$issue.expected)
    }
}
$lines | Set-Content -LiteralPath $txtReport -Encoding UTF8

$report | ConvertTo-Json -Depth 8

if ($issues.Count -gt 0) {
    exit 1
}
