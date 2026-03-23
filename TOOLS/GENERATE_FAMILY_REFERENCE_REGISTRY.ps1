param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$familyPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$registryPath = Join-Path $ProjectRoot "CONFIG\\microbots_registry.json"
$matrixPath = Join-Path $ProjectRoot "EVIDENCE\\propagation_plan_matrix.json"
$configPath = Join-Path $ProjectRoot "CONFIG\\family_reference_registry.json"
$reportPath = Join-Path $ProjectRoot "EVIDENCE\\family_reference_registry_report.json"

$familyRegistry = Get-Content -Raw -LiteralPath $familyPath | ConvertFrom-Json
$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json
$microbotRegistry = Get-Content -Raw -LiteralPath $registryPath | ConvertFrom-Json
$matrix = Get-Content -Raw -LiteralPath $matrixPath | ConvertFrom-Json

$variantBySymbol = @{}
$variantByAlias = @{}
foreach ($variant in $variantRegistry.variants) {
    $variantBySymbol[$variant.symbol] = $variant
    if ($variant.PSObject.Properties.Name -contains 'alias_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$variant.alias_symbol)) {
        $variantByAlias[[string]$variant.alias_symbol] = $variant
    }
}

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

    if ($null -eq $familySummary) {
        continue
    }

    $activeTargets = @($familySummary.symbols | Where-Object { $activeSymbols.Contains([string]$_) })
    if ($activeTargets.Count -eq 0) {
        continue
    }

    if (-not $activeSymbols.Contains($sourceSymbol)) {
        $sourceSymbol = [string]$activeTargets[0]
    }

    $sourceVariant = if ($variantBySymbol.ContainsKey($sourceSymbol)) {
        $variantBySymbol[$sourceSymbol]
    } elseif ($variantByAlias.ContainsKey($sourceSymbol)) {
        $variantByAlias[$sourceSymbol]
    } else {
        $null
    }

    if ($null -eq $sourceVariant) {
        continue
    }

    $references += [ordered]@{
        family = $familyName
        source_symbol = $sourceSymbol
        source_strategy_file = $sourceVariant.strategy_file
        source_profile_file = $sourceVariant.profile.profile_file
        target_symbols = @($activeTargets)
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
