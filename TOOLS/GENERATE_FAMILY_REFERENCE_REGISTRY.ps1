param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1")

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

function Resolve-VariantCanonicalSymbol {
    param([object]$Variant)

    foreach ($candidate in @([string]$Variant.alias_symbol, [string]$Variant.symbol)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $entry = Find-RegistryEntryByAlias -Registry $microbotRegistry -Alias $candidate
        if ($null -ne $entry) {
            $canonical = Get-RegistryCanonicalSymbol -RegistryItem $entry
            if (-not [string]::IsNullOrWhiteSpace($canonical)) {
                return $canonical
            }
        }
    }

    if ($Variant.PSObject.Properties.Name -contains 'alias_symbol' -and -not [string]::IsNullOrWhiteSpace([string]$Variant.alias_symbol)) {
        return [string]$Variant.alias_symbol
    }
    return [string]$Variant.symbol
}

$variantByCanonical = @{}
foreach ($variant in $variantRegistry.variants) {
    $canonical = Resolve-VariantCanonicalSymbol -Variant $variant
    if (-not [string]::IsNullOrWhiteSpace($canonical)) {
        $variantByCanonical[$canonical] = $variant
    }
}

$activeSymbols = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
foreach ($item in $microbotRegistry.symbols) {
    $canonical = Get-RegistryCanonicalSymbol -RegistryItem $item
    if (-not [string]::IsNullOrWhiteSpace($canonical)) {
        [void]$activeSymbols.Add($canonical)
    }
}

$references = @()
foreach ($plan in $matrix.plans) {
    $sourceSymbol = [string]$plan.source_symbol
    if ($sourceSymbol.EndsWith(".pro")) {
        $sourceSymbol = $sourceSymbol.Substring(0, $sourceSymbol.Length - 4)
    }
    $familyName = [string]$plan.family
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

    $sourceVariant = if ($variantByCanonical.ContainsKey($sourceSymbol)) {
        $variantByCanonical[$sourceSymbol]
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
