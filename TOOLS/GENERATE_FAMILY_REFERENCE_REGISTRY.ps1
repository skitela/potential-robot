param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$familyPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$matrixPath = Join-Path $ProjectRoot "EVIDENCE\\propagation_plan_matrix.json"
$configPath = Join-Path $ProjectRoot "CONFIG\\family_reference_registry.json"
$reportPath = Join-Path $ProjectRoot "EVIDENCE\\family_reference_registry_report.json"

$familyRegistry = Get-Content -Raw -LiteralPath $familyPath | ConvertFrom-Json
$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json
$matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json

$variantBySymbol = @{}
foreach ($variant in $variantRegistry.variants) {
    $variantBySymbol[$variant.symbol] = $variant
}

$references = @()
foreach ($plan in $matrix.plans) {
    $sourceSymbol = [string]$plan.source_symbol
    $familyName = [string]$plan.family
    $sourceVariant = $variantBySymbol[$sourceSymbol]
    $familySummary = $null
    foreach ($family in $familyRegistry.families) {
        if ($family.family -eq $familyName) {
            $familySummary = $family
            break
        }
    }

    $references += [ordered]@{
        family = $familyName
        source_symbol = $sourceSymbol
        source_strategy_file = $sourceVariant.strategy_file
        source_profile_file = $sourceVariant.profile.profile_file
        target_symbols = @($familySummary.symbols)
        family_invariants = $familySummary.invariants
        family_allowed_ranges = $familySummary.allowed_ranges
        family_allowed_setup_labels = $familySummary.allowed_setup_labels
        propagation_scope = "family"
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    references = @($references)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
