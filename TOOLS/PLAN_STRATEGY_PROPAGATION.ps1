param(
    [string]$ProjectRoot = "C:\\MAKRO_I_MIKRO_BOT",
    [ValidateSet("common","family","symbol")]
    [string]$Scope = "family",
    [string]$SourceSymbol = "EURUSD",
    [string]$Family = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$variantPath = Join-Path $ProjectRoot "CONFIG\\strategy_variant_registry.json"
$familyPath = Join-Path $ProjectRoot "CONFIG\\family_policy_registry.json"
$outJson = Join-Path $ProjectRoot "EVIDENCE\\strategy_propagation_plan.json"
$outTxt = Join-Path $ProjectRoot "EVIDENCE\\strategy_propagation_plan.txt"

$variantRegistry = Get-Content -Raw -LiteralPath $variantPath | ConvertFrom-Json
$familyRegistry = Get-Content -Raw -LiteralPath $familyPath | ConvertFrom-Json

$variantBySymbol = @{}
foreach ($variant in $variantRegistry.variants) {
    $variantBySymbol[$variant.symbol] = $variant
}

if (-not $variantBySymbol.ContainsKey($SourceSymbol)) {
    throw "Unknown source symbol: $SourceSymbol"
}

$source = $variantBySymbol[$SourceSymbol]
$sourceFamily = [string]$source.profile.session_profile
if ([string]::IsNullOrWhiteSpace($Family)) {
    $Family = $sourceFamily
}

switch ($Scope) {
    "common" { $targets = @($variantRegistry.variants | Sort-Object symbol) }
    "family" { $targets = @($variantRegistry.variants | Where-Object { $_.profile.session_profile -eq $Family } | Sort-Object symbol) }
    "symbol" { $targets = @($variantRegistry.variants | Where-Object { $_.symbol -eq $SourceSymbol }) }
}

$commonSafeItems = @(
    "indicator init/deinit helper",
    "indicator copy helper",
    "new-bar gate helper",
    "risk-plan builder helper",
    "setup ranking helper",
    "trigger gate helper",
    "trailing helper mechanics",
    "runtime journaling hooks",
    "deployment and rollout scripts"
)

$localGenes = @(
    "session_profile",
    "trade windows",
    "setup labels",
    "scoring formulas",
    "trigger thresholds",
    "risk model values",
    "SL/TP multipliers",
    "trail multipliers"
)

$familySummary = $null
foreach ($familyEntry in $familyRegistry.families) {
    if ($familyEntry.family -eq $Family) {
        $familySummary = $familyEntry
        break
    }
}

$targetRows = @()
foreach ($target in $targets) {
    $targetRows += [ordered]@{
        symbol = $target.symbol
        family = $target.profile.session_profile
        same_symbol = ($target.symbol -eq $source.symbol)
        same_family = ($target.profile.session_profile -eq $source.profile.session_profile)
        strategy_file = $target.strategy_file
        safe_to_propagate = @($commonSafeItems)
        preserve_local = @($localGenes)
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    scope = $Scope
    source_symbol = $SourceSymbol
    source_family = $sourceFamily
    target_family = $Family
    source_strategy_file = $source.strategy_file
    common_safe_items = @($commonSafeItems)
    local_gene_items = @($localGenes)
    family_summary = $familySummary
    targets = @($targetRows)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outJson -Encoding UTF8

$lines = @()
$lines += "Strategy propagation plan"
$lines += ("scope={0}" -f $Scope)
$lines += ("source_symbol={0}" -f $SourceSymbol)
$lines += ("source_family={0}" -f $sourceFamily)
$lines += ("target_family={0}" -f $Family)
$lines += ""
$lines += "Safe to propagate:"
$commonSafeItems | ForEach-Object { $lines += ("- {0}" -f $_) }
$lines += ""
$lines += "Preserve local genes:"
$localGenes | ForEach-Object { $lines += ("- {0}" -f $_) }
$lines += ""
$lines += "Targets:"
foreach ($row in $targetRows) {
    $lines += ("- {0} | family={1} | same_family={2} | same_symbol={3}" -f $row.symbol,$row.family,$row.same_family,$row.same_symbol)
}
$lines | Set-Content -LiteralPath $outTxt -Encoding UTF8

$report | ConvertTo-Json -Depth 8
