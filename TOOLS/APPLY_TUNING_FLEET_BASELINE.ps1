param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "",
    [string]$SeedDir = "",
    [switch]$RebuildLogs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Dir {
    param([string]$Path)
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
}

function Write-KeyValueTabFile {
    param(
        [string]$Path,
        [hashtable]$Data
    )

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in $Data.Keys) {
        $lines.Add(([string]::Format("{0}`t{1}", $key, $Data[$key])))
    }
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Write-TabCsv {
    param(
        [string]$Path,
        [string[]]$Header,
        [object[]]$Rows
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(($Header -join "`t"))
    foreach ($row in $Rows) {
        $cells = foreach ($value in $row) { [string]$value }
        $lines.Add(($cells -join "`t"))
    }
    $lines | Set-Content -LiteralPath $Path -Encoding UTF8
}

function BoolInt($Value) {
    if ($Value) { return 1 }
    return 0
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($CommonFilesRoot)) {
    $CommonFilesRoot = Join-Path $env:APPDATA "MetaQuotes\\Terminal\\Common\\Files\\MAKRO_I_MIKRO_BOT"
}
if ([string]::IsNullOrWhiteSpace($SeedDir)) {
    $SeedDir = Join-Path $projectPath "RUN\\TUNING"
}

$registryPath = Join-Path $projectPath "CONFIG\\tuning_fleet_registry.json"
if (-not (Test-Path -LiteralPath $registryPath)) {
    throw "Missing tuning fleet registry: $registryPath"
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$appliedFamilies = @()
$ts = [int][double]::Parse((Get-Date).ToUniversalTime().Subtract([datetime]'1970-01-01').TotalSeconds.ToString([System.Globalization.CultureInfo]::InvariantCulture), [System.Globalization.CultureInfo]::InvariantCulture)

foreach ($family in $registry.families) {
    $seedPath = [string]$family.local_seed_file
    if (-not (Test-Path -LiteralPath $seedPath)) {
        throw "Missing family seed: $seedPath"
    }
    $seed = Get-Content -LiteralPath $seedPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $stateDir = [string]$family.expected_state_dir
    $logDir = [string]$family.expected_log_dir
    Ensure-Dir $stateDir
    Ensure-Dir $logDir

    $policyPath = Join-Path $stateDir "tuning_family_policy.csv"
    $policyData = [ordered]@{
        enabled = 1
        trusted_data = (BoolInt $seed.trusted_data)
        freeze_new_changes = (BoolInt $seed.freeze_new_changes)
        revision = 1
        symbol_count = [int]$seed.symbol_count
        trusted_symbol_count = [int]$seed.trusted_symbol_count
        degraded_symbol_count = [int]$seed.degraded_symbol_count
        chaos_symbol_count = [int]$seed.chaos_symbol_count
        bad_spread_symbol_count = [int]$seed.bad_spread_symbol_count
        min_family_samples = 18
        cooldown_sec = 1800
        last_total_samples = [int]$seed.total_samples
        last_eval_at = $ts
        last_action_at = $ts
        cooldown_until = ($ts + 1800)
        dominant_confidence_cap = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$seed.dominant_confidence_cap))
        dominant_risk_cap = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$seed.dominant_risk_cap))
        breakout_family_tax = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$seed.breakout_family_tax))
        trend_family_tax = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$seed.trend_family_tax))
        rejection_range_boost = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$seed.rejection_range_boost))
        trust_reason = [string]$seed.trust_reason
        last_action_code = [string]$seed.action_code
        last_action_detail = ("symbols={0};trusted={1};degraded={2};samples={3}" -f $seed.symbol_count,$seed.trusted_symbol_count,$seed.degraded_symbol_count,$seed.total_samples)
    }
    Write-KeyValueTabFile -Path $policyPath -Data $policyData

    $actionLogPath = Join-Path $logDir "tuning_family_actions.csv"
    if ($RebuildLogs -or -not (Test-Path -LiteralPath $actionLogPath)) {
        Write-TabCsv -Path $actionLogPath -Header @(
            "ts","family","revision","action_code","action_detail","trusted_data","trust_reason",
            "symbol_count","trusted_symbol_count","degraded_symbol_count","chaos_symbol_count","bad_spread_symbol_count",
            "dominant_confidence_cap","dominant_risk_cap","breakout_family_tax","trend_family_tax","rejection_range_boost","freeze_new_changes"
        ) -Rows @(
            @(
                $ts,
                $seed.family,
                1,
                $seed.action_code,
                ("seed_apply;samples={0};trusted={1};degraded={2}" -f $seed.total_samples,$seed.trusted_symbol_count,$seed.degraded_symbol_count),
                (BoolInt $seed.trusted_data),
                $seed.trust_reason,
                $seed.symbol_count,
                $seed.trusted_symbol_count,
                $seed.degraded_symbol_count,
                $seed.chaos_symbol_count,
                $seed.bad_spread_symbol_count,
                ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$seed.dominant_confidence_cap)),
                ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$seed.dominant_risk_cap)),
                ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$seed.breakout_family_tax)),
                ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$seed.trend_family_tax)),
                ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$seed.rejection_range_boost)),
                (BoolInt $seed.freeze_new_changes)
            )
        )
    }

    $appliedFamilies += [pscustomobject]@{
        family = $seed.family
        policy_path = $policyPath
        action_log_path = $actionLogPath
    }
}

$coordinatorSeedPath = [string]$registry.coordinator.local_seed_file
if (-not (Test-Path -LiteralPath $coordinatorSeedPath)) {
    throw "Missing coordinator seed: $coordinatorSeedPath"
}
$coordinatorSeed = Get-Content -LiteralPath $coordinatorSeedPath -Raw -Encoding UTF8 | ConvertFrom-Json

$coordinatorStateDir = [string]$registry.coordinator.expected_state_dir
$coordinatorLogDir = [string]$registry.coordinator.expected_log_dir
Ensure-Dir $coordinatorStateDir
Ensure-Dir $coordinatorLogDir

$coordinatorStatePath = Join-Path $coordinatorStateDir "tuning_coordinator_state.csv"
$coordinatorData = [ordered]@{
    enabled = 1
    trusted_data = (BoolInt $coordinatorSeed.trusted_data)
    freeze_new_changes = (BoolInt $coordinatorSeed.freeze_new_changes)
    revision = 1
    family_count = [int]$coordinatorSeed.family_count
    trusted_family_count = [int]$coordinatorSeed.trusted_family_count
    degraded_family_count = [int]$coordinatorSeed.degraded_family_count
    max_local_changes_per_cycle = [int]$coordinatorSeed.max_local_changes_per_cycle
    cooldown_sec = 1800
    last_eval_at = $ts
    last_action_at = $ts
    cooldown_until = ($ts + 1800)
    global_confidence_cap = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$coordinatorSeed.global_confidence_cap))
    global_risk_cap = ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F6}", [double]$coordinatorSeed.global_risk_cap))
    trust_reason = [string]$coordinatorSeed.trust_reason
    last_action_code = [string]$coordinatorSeed.action_code
    last_action_detail = ("seed_apply;families={0};trusted={1};degraded={2}" -f $coordinatorSeed.family_count,$coordinatorSeed.trusted_family_count,$coordinatorSeed.degraded_family_count)
}
Write-KeyValueTabFile -Path $coordinatorStatePath -Data $coordinatorData

$coordinatorActionLogPath = Join-Path $coordinatorLogDir "tuning_coordinator_actions.csv"
if ($RebuildLogs -or -not (Test-Path -LiteralPath $coordinatorActionLogPath)) {
    Write-TabCsv -Path $coordinatorActionLogPath -Header @(
        "ts","revision","action_code","action_detail","trusted_data","trust_reason","family_count","trusted_family_count","degraded_family_count","global_confidence_cap","global_risk_cap","max_local_changes_per_cycle","freeze_new_changes"
    ) -Rows @(
        @(
            $ts,
            1,
            $coordinatorSeed.action_code,
            ("seed_apply;families={0};trusted={1};degraded={2}" -f $coordinatorSeed.family_count,$coordinatorSeed.trusted_family_count,$coordinatorSeed.degraded_family_count),
            (BoolInt $coordinatorSeed.trusted_data),
            $coordinatorSeed.trust_reason,
            $coordinatorSeed.family_count,
            $coordinatorSeed.trusted_family_count,
            $coordinatorSeed.degraded_family_count,
            ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$coordinatorSeed.global_confidence_cap)),
            ([string]::Format([System.Globalization.CultureInfo]::InvariantCulture, "{0:F4}", [double]$coordinatorSeed.global_risk_cap)),
            $coordinatorSeed.max_local_changes_per_cycle,
            (BoolInt $coordinatorSeed.freeze_new_changes)
        )
    )
}

$reportDir = Join-Path $projectPath "EVIDENCE"
Ensure-Dir $reportDir
$reportPath = Join-Path $reportDir ("APPLY_TUNING_FLEET_BASELINE_{0}.json" -f ((Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")))

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectPath
    common_files_root = $CommonFilesRoot
    families_applied = @($appliedFamilies)
    coordinator_state_path = $coordinatorStatePath
    coordinator_action_log_path = $coordinatorActionLogPath
}

$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6
