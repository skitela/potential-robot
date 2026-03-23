param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$familyPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$plansDir = Join-Path $ProjectRoot "EVIDENCE\\PROPAGATION_PLANS"
$summaryJson = Join-Path $ProjectRoot "EVIDENCE\\propagation_plan_matrix.json"
$summaryTxt = Join-Path $ProjectRoot "EVIDENCE\\propagation_plan_matrix.txt"
$planTool = Join-Path $ProjectRoot "TOOLS\\PLAN_STRATEGY_PROPAGATION.ps1"

New-Item -ItemType Directory -Force -Path $plansDir | Out-Null

$familyRegistry = Get-Content -Raw -LiteralPath $familyPath | ConvertFrom-Json
$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json

$preferredSources = @{
    "FX_MAIN"         = "EURUSD"
    "FX_ASIA"         = "USDJPY"
    "FX_CROSS"        = "EURJPY"
    "METALS_SPOT_PM"  = "GOLD.pro"
    "METALS_FUTURES"  = "COPPER-US.pro"
    "INDEX_EU"        = "DE30.pro"
    "INDEX_US"        = "US500.pro"
}

$matrix = @()
foreach ($family in $familyRegistry.families) {
    $familyName = [string]$family.family
    $sourceSymbol = $preferredSources[$familyName]
    if ([string]::IsNullOrWhiteSpace($sourceSymbol)) {
        $sourceSymbol = [string]($family.symbols | Select-Object -First 1)
    }

    $plan = & $planTool -ProjectRoot $ProjectRoot -Scope family -SourceSymbol $sourceSymbol -Family $familyName | ConvertFrom-Json
    $jsonTarget = Join-Path $plansDir ("PLAN_{0}_{1}.json" -f $familyName,$sourceSymbol)
    $txtTarget = Join-Path $plansDir ("PLAN_{0}_{1}.txt" -f $familyName,$sourceSymbol)

    $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonTarget -Encoding UTF8

    $txt = @()
    $txt += ("Family propagation plan: {0}" -f $familyName)
    $txt += ("Source: {0}" -f $sourceSymbol)
    $txt += ""
    $txt += "Targets:"
    foreach ($target in $plan.targets) {
        $txt += ("- {0}" -f $target.symbol)
    }
    $txt += ""
    $txt += "Safe to propagate:"
    foreach ($item in $plan.common_safe_items) {
        $txt += ("- {0}" -f $item)
    }
    $txt += ""
    $txt += "Preserve local genes:"
    foreach ($item in $plan.local_gene_items) {
        $txt += ("- {0}" -f $item)
    }
    $txt | Set-Content -LiteralPath $txtTarget -Encoding UTF8

    $matrix += [ordered]@{
        family = $familyName
        source_symbol = $sourceSymbol
        target_count = @($plan.targets).Count
        json_plan = $jsonTarget
        txt_plan = $txtTarget
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    plans_dir = $plansDir
    plans = @($matrix)
}

$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryJson -Encoding UTF8

$lines = @()
$lines += "Propagation plan matrix"
$lines += ""
foreach ($item in $matrix) {
    $lines += ("- {0}: source={1}, targets={2}" -f $item.family,$item.source_symbol,$item.target_count)
}
$lines | Set-Content -LiteralPath $summaryTxt -Encoding UTF8

$report | ConvertTo-Json -Depth 6
