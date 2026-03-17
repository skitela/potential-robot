param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "",
    [string]$OutDir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-KeyValueTabFile {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $parts = $_ -split "`t", 2
        if ($parts.Length -eq 2) {
            $map[$parts[0]] = $parts[1]
        }
    }
    return $map
}

function To-Int {
    param($Value, [int]$Default = 0)
    if ($null -eq $Value -or $Value -eq "") { return $Default }
    try { return [int]$Value } catch { return $Default }
}

function To-Double {
    param($Value, [double]$Default = 0.0)
    if ($null -eq $Value -or $Value -eq "") { return $Default }
    try { return [double]::Parse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture) } catch { return $Default }
}

function Clamp {
    param([double]$Value, [double]$Min, [double]$Max)
    return [Math]::Max($Min, [Math]::Min($Max, $Value))
}

function Get-OrDefault {
    param(
        [hashtable]$Map,
        [string]$Key,
        $Default = ""
    )
    if ($Map.ContainsKey($Key) -and $null -ne $Map[$Key] -and $Map[$Key] -ne "") {
        return $Map[$Key]
    }
    return $Default
}

function Get-SymbolSnapshot {
    param(
        [string]$CommonRoot,
        [string]$Family,
        [string]$Symbol
    )

    $runtimePath = Join-Path $CommonRoot ("state\{0}\runtime_state.csv" -f $Symbol)
    $policyPath = Join-Path $CommonRoot ("state\{0}\tuning_policy.csv" -f $Symbol)
    $runtime = Read-KeyValueTabFile -Path $runtimePath
    $policy = Read-KeyValueTabFile -Path $policyPath

    $runtimePresent = ($runtime.Count -gt 0)
    $policyPresent = ($policy.Count -gt 0)
    $losses = To-Int $runtime["learning_loss_count"]
    $samples = To-Int $runtime["learning_sample_count"]
    $lossRatio = if ($samples -gt 0) { [Math]::Round(($losses / [double]$samples), 4) } else { 0.0 }

    [pscustomobject]@{
        symbol = $Symbol
        family = $Family
        runtime_present = $runtimePresent
        local_policy_present = $policyPresent
        local_policy_trusted = ((To-Int $policy["trusted_data"]) -ne 0)
        learning_sample_count = $samples
        learning_win_count = To-Int $runtime["learning_win_count"]
        learning_loss_count = $losses
        loss_ratio = $lossRatio
        loss_streak = To-Int $runtime["loss_streak"]
        adaptive_risk_scale = To-Double $runtime["adaptive_risk_scale"] 1.0
        market_regime = [string](Get-OrDefault $runtime "market_regime" "UNKNOWN")
        spread_regime = [string](Get-OrDefault $runtime "spread_regime" "UNKNOWN")
        execution_regime = [string](Get-OrDefault $runtime "execution_regime" "UNKNOWN")
        last_setup_type = [string](Get-OrDefault $runtime "last_setup_type" "NONE")
        confidence_cap = To-Double $policy["confidence_cap"] 1.0
        risk_cap = To-Double $policy["risk_cap"] 1.0
        breakout_tax = (
            (To-Double $policy["breakout_global_tax"]) +
            (To-Double $policy["breakout_chaos_tax"]) +
            (To-Double $policy["breakout_range_tax"]) +
            (To-Double $policy["breakout_conflict_tax"])
        )
        trend_tax = (
            (To-Double $policy["trend_breakout_tax"]) +
            (To-Double $policy["trend_chaos_tax"]) +
            (To-Double $policy["trend_caution_tax"]) +
            (To-Double $policy["trend_no_aux_tax"])
        )
        rejection_boost = To-Double $policy["rejection_range_boost"]
        trust_reason = [string](Get-OrDefault $policy "trust_reason" ($(if ($runtimePresent) { "RUNTIME_ONLY" } else { "MISSING" })))
        runtime_path = $runtimePath
        local_policy_path = $policyPath
    }
}

function Build-FamilySeed {
    param(
        [pscustomobject]$FamilyRow,
        [pscustomobject]$ReferenceRow,
        [string]$CommonRoot
    )

    $snapshots = @()
    foreach ($symbol in $FamilyRow.symbols) {
        $snapshots += Get-SymbolSnapshot -CommonRoot $CommonRoot -Family $FamilyRow.family -Symbol $symbol
    }

    $symbolCount = $snapshots.Count
    $majority = [int][Math]::Ceiling($symbolCount / 2.0)
    $trustedSymbols = @($snapshots | Where-Object { $_.runtime_present -and $_.learning_sample_count -ge 6 }).Count
    $degradedSymbols = @($snapshots | Where-Object { $_.loss_ratio -ge 0.70 -or $_.loss_streak -ge 8 -or $_.spread_regime -eq 'BAD' }).Count
    $chaosSymbols = @($snapshots | Where-Object { $_.market_regime -eq 'CHAOS' }).Count
    $badSpreadSymbols = @($snapshots | Where-Object { $_.spread_regime -eq 'BAD' }).Count
    $totalSamples = ($snapshots | Measure-Object -Property learning_sample_count -Sum).Sum
    $trustedPolicyCaps = @($snapshots | Where-Object { $_.local_policy_present -and $_.local_policy_trusted })
    $rejectionSources = @($snapshots | Where-Object { $_.rejection_boost -gt 0.02 })
    $breakoutVotes = @($snapshots | Where-Object { (($_.last_setup_type -eq 'SETUP_BREAKOUT') -and ($_.loss_ratio -ge 0.70 -or $_.loss_streak -ge 8 -or $_.spread_regime -eq 'BAD')) -or $_.breakout_tax -ge 0.05 }).Count
    $trendVotes = @($snapshots | Where-Object { (($_.last_setup_type -eq 'SETUP_TREND') -and ($_.loss_ratio -ge 0.70 -or $_.loss_streak -ge 8 -or $_.spread_regime -eq 'BAD')) -or $_.trend_tax -ge 0.05 -or $_.market_regime -eq 'CHAOS' }).Count

    if ($trustedPolicyCaps.Count -gt 0) {
        $dominantConfidenceCap = Clamp ((($trustedPolicyCaps | Measure-Object -Property confidence_cap -Average).Average)) 0.72 1.0
        $dominantRiskCap = Clamp ((($trustedPolicyCaps | Measure-Object -Property risk_cap -Average).Average)) 0.72 1.0
    } else {
        $dominantConfidenceCap = 1.0
        $dominantRiskCap = Clamp ((($snapshots | Measure-Object -Property adaptive_risk_scale -Average).Average)) 0.75 1.0
    }

    $breakoutFamilyTax = 0.0
    $trendFamilyTax = 0.0
    $rejectionBoost = if ($rejectionSources.Count -gt 0) {
        Clamp ((($rejectionSources | Measure-Object -Property rejection_boost -Average).Average)) 0.0 0.06
    } else {
        0.0
    }

    if ($chaosSymbols -ge $majority -or $breakoutVotes -ge $majority) {
        $breakoutFamilyTax = 0.06
    } elseif ($breakoutVotes -gt 0 -and $degradedSymbols -gt 0) {
        $breakoutFamilyTax = 0.03
    }

    if ($chaosSymbols -ge $majority -or $trendVotes -ge $majority) {
        $trendFamilyTax = 0.05
    } elseif ($trendVotes -gt 0 -and $degradedSymbols -gt 0) {
        $trendFamilyTax = 0.02
    }

    $trustReason = if ($trustedSymbols -le 0) {
        "NO_TRUSTED_SYMBOLS"
    } elseif ($totalSamples -lt [Math]::Max(18, (12 * $symbolCount))) {
        "LOW_FAMILY_SAMPLE"
    } else {
        "TRUSTED"
    }

    $trustedData = ($trustReason -eq "TRUSTED")
    $freezeNewChanges = $false
    if (-not $trustedData -or $badSpreadSymbols -ge $majority -or $degradedSymbols -ge ($symbolCount - 1)) {
        $freezeNewChanges = $true
    }

    if ($degradedSymbols -ge $majority) {
        $dominantConfidenceCap = [Math]::Min($dominantConfidenceCap, 0.86)
        $dominantRiskCap = [Math]::Min($dominantRiskCap, 0.84)
    }
    if ($badSpreadSymbols -ge $majority) {
        $dominantConfidenceCap = [Math]::Min($dominantConfidenceCap, 0.82)
        $dominantRiskCap = [Math]::Min($dominantRiskCap, 0.80)
    }

    $actionCode = if ($freezeNewChanges) {
        "FREEZE_FAMILY"
    } elseif ($breakoutFamilyTax -ge $trendFamilyTax -and $breakoutFamilyTax -ge 0.05) {
        "DAMP_FAMILY_BREAKOUT"
    } elseif ($trendFamilyTax -ge 0.05) {
        "DAMP_FAMILY_TREND"
    } elseif ($rejectionBoost -gt 0.02) {
        "BOOST_FAMILY_REJECTION"
    } else {
        "REBALANCE_FAMILY"
    }

    [pscustomobject]@{
        family = $FamilyRow.family
        source_symbol = $ReferenceRow.source_symbol
        symbols = @($FamilyRow.symbols)
        trusted_data = $trustedData
        trust_reason = $trustReason
        freeze_new_changes = $freezeNewChanges
        symbol_count = $symbolCount
        trusted_symbol_count = $trustedSymbols
        degraded_symbol_count = $degradedSymbols
        chaos_symbol_count = $chaosSymbols
        bad_spread_symbol_count = $badSpreadSymbols
        total_samples = $totalSamples
        dominant_confidence_cap = [Math]::Round($dominantConfidenceCap, 4)
        dominant_risk_cap = [Math]::Round($dominantRiskCap, 4)
        breakout_family_tax = [Math]::Round($breakoutFamilyTax, 4)
        trend_family_tax = [Math]::Round($trendFamilyTax, 4)
        rejection_range_boost = [Math]::Round($rejectionBoost, 4)
        action_code = $actionCode
        family_invariants = $FamilyRow.invariants
        family_allowed_ranges = $FamilyRow.allowed_ranges
        family_allowed_setup_labels = $FamilyRow.allowed_setup_labels
        snapshots = $snapshots
    }
}

function Build-CoordinatorSeed {
    param([object[]]$FamilySeeds)

    $familyCount = $FamilySeeds.Count
    $trusted = @($FamilySeeds | Where-Object { $_.trusted_data }).Count
    $degraded = @($FamilySeeds | Where-Object { $_.freeze_new_changes -or $_.dominant_risk_cap -lt 0.90 -or $_.degraded_symbol_count -ge [Math]::Max(1,($_.symbol_count - 1)) }).Count
    $trustedFamilies = @($FamilySeeds | Where-Object { $_.trusted_data })

    if ($trustedFamilies.Count -gt 0) {
        $globalConfidenceCap = Clamp ((($trustedFamilies | Measure-Object -Property dominant_confidence_cap -Average).Average)) 0.72 1.0
        $globalRiskCap = Clamp ((($trustedFamilies | Measure-Object -Property dominant_risk_cap -Average).Average)) 0.72 1.0
    } else {
        $globalConfidenceCap = 1.0
        $globalRiskCap = 1.0
    }

    $freeze = $false
    $changeBudget = 2
    if ($degraded -ge 2) {
        $globalConfidenceCap = [Math]::Min($globalConfidenceCap, 0.84)
        $globalRiskCap = [Math]::Min($globalRiskCap, 0.82)
        $changeBudget = 1
    }
    if ($degraded -ge $familyCount -and $familyCount -gt 0) {
        $freeze = $true
        $changeBudget = 0
    } elseif ($trusted -lt $familyCount -and $familyCount -gt 1) {
        $changeBudget = [Math]::Min($changeBudget, 1)
    }

    $trustReason = if ($trusted -le 0) {
        "NO_TRUSTED_FAMILIES"
    } elseif ($trusted -lt $familyCount) {
        "PARTIAL_TRUST"
    } else {
        "TRUSTED"
    }

    $actionCode = if ($freeze) {
        "FREEZE_FLEET"
    } elseif ($degraded -ge 2) {
        "COOL_FLEET"
    } elseif ($changeBudget -le 1) {
        "LIMIT_CHANGE_BUDGET"
    } else {
        "REBALANCE_FLEET"
    }

    [pscustomobject]@{
        family_count = $familyCount
        trusted_family_count = $trusted
        degraded_family_count = $degraded
        trusted_data = ($trusted -gt 0)
        trust_reason = $trustReason
        freeze_new_changes = $freeze
        max_local_changes_per_cycle = $changeBudget
        global_confidence_cap = [Math]::Round($globalConfidenceCap, 4)
        global_risk_cap = [Math]::Round($globalRiskCap, 4)
        action_code = $actionCode
    }
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectPath "RUN\\TUNING"
}

$microbotsRegistry = Get-Content -LiteralPath (Join-Path $projectPath "CONFIG\\microbots_registry.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$familyPolicyRegistry = Get-Content -LiteralPath (Join-Path $projectPath "CONFIG\\family_policy_registry.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$familyReferenceRegistry = Get-Content -LiteralPath (Join-Path $projectPath "CONFIG\\family_reference_registry.json") -Raw -Encoding UTF8 | ConvertFrom-Json

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $projectPath "EVIDENCE") | Out-Null

$familySeeds = @()
foreach ($family in $familyPolicyRegistry.families) {
    $reference = @($familyReferenceRegistry.references | Where-Object { $_.family -eq $family.family } | Select-Object -First 1)
    if (-not $reference -or $reference.Count -lt 1) { continue }

    $seed = Build-FamilySeed -FamilyRow $family -ReferenceRow $reference[0] -CommonRoot $CommonFilesRoot
    $familySeeds += $seed

    $familyPath = Join-Path $OutDir ("family_policy_seed_{0}.json" -f $family.family)
    $seed | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $familyPath -Encoding UTF8
}

$coordinatorSeed = Build-CoordinatorSeed -FamilySeeds $familySeeds
$coordinatorPath = Join-Path $OutDir "coordinator_policy_seed.json"
$coordinatorSeed | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $coordinatorPath -Encoding UTF8

$registryOut = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    families = @(
        foreach ($family in $familySeeds) {
            $ref = @($familyReferenceRegistry.references | Where-Object { $_.family -eq $family.family } | Select-Object -First 1)
            [ordered]@{
                family = $family.family
                source_symbol = $family.source_symbol
                symbols = $family.symbols
                trusted_data = $family.trusted_data
                trust_reason = $family.trust_reason
                local_seed_file = (Join-Path $OutDir ("family_policy_seed_{0}.json" -f $family.family))
                expected_state_dir = (Join-Path $CommonFilesRoot ("state\\_families\\{0}" -f $family.family))
                expected_log_dir = (Join-Path $CommonFilesRoot ("logs\\_families\\{0}" -f $family.family))
                family_allowed_setup_labels = $family.family_allowed_setup_labels
                family_allowed_ranges = $family.family_allowed_ranges
            }
        }
    )
    coordinator = [ordered]@{
        trusted_data = $coordinatorSeed.trusted_data
        trust_reason = $coordinatorSeed.trust_reason
        local_seed_file = $coordinatorPath
        expected_state_dir = (Join-Path $CommonFilesRoot "state\\_coordinator")
        expected_log_dir = (Join-Path $CommonFilesRoot "logs\\_coordinator")
    }
}

$registryPath = Join-Path $projectPath "CONFIG\\tuning_fleet_registry.json"
$registryOut | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $registryPath -Encoding UTF8

$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
$reportPath = Join-Path $projectPath ("EVIDENCE\\TUNING_FLEET_BASELINE_{0}.md" -f $stamp)
$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Tuning Fleet Baseline")
$lines.Add("")
$lines.Add("## Families")
$lines.Add("")
foreach ($family in $familySeeds) {
    $familyLine = "- {0}: trusted={1}, degraded={2}, samples={3}, risk_cap={4}, confidence_cap={5}, action={6}" -f `
        $family.family,
        ($(if ($family.trusted_data) { "true" } else { "false" })),
        $family.degraded_symbol_count,
        $family.total_samples,
        $family.dominant_risk_cap,
        $family.dominant_confidence_cap,
        $family.action_code
    $lines.Add($familyLine)
}
$lines.Add("")
$lines.Add("## Coordinator")
$lines.Add("")
$lines.Add(("- trusted={0}" -f ($(if ($coordinatorSeed.trusted_data) { "true" } else { "false" }))))
$lines.Add(("- degraded_families={0}" -f $coordinatorSeed.degraded_family_count))
$lines.Add(("- global_risk_cap={0}" -f $coordinatorSeed.global_risk_cap))
$lines.Add(("- global_confidence_cap={0}" -f $coordinatorSeed.global_confidence_cap))
$lines.Add(("- max_local_changes_per_cycle={0}" -f $coordinatorSeed.max_local_changes_per_cycle))
$lines.Add(("- action={0}" -f $coordinatorSeed.action_code))
$lines | Set-Content -LiteralPath $reportPath -Encoding UTF8

[ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    out_dir = $OutDir
    registry_path = $registryPath
    coordinator_seed_path = $coordinatorPath
    family_seed_count = $familySeeds.Count
    report_path = $reportPath
} | ConvertTo-Json -Depth 6
