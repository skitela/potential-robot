param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TrainingReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_training_readiness_latest.json",
    [string]$LocalTrainingGuardrailsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_local_training_guardrails_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$MaxStartGroupSize = 2,
    [int]$MaxLimitedWatchlistSize = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-TeacherPriority {
    param([string]$Value)

    switch ($Value) {
        "LOW" { return 0 }
        "MEDIUM" { return 1 }
        "HIGH" { return 2 }
        "MAXIMAL" { return 3 }
        default { return 4 }
    }
}

function Sort-TrainingItems {
    param([object[]]$Items)

    return @(
        @($Items) |
            Sort-Object `
                @{ Expression = { Get-TeacherPriority -Value ([string]$_.teacher_dependency_level) }; Ascending = $true }, `
                @{ Expression = { -1 * [int](0 + $_.outcome_rows) }; Ascending = $true }, `
                @{ Expression = { -1 * [int](0 + $_.onnx_runtime_rows) }; Ascending = $true }, `
                @{ Expression = { -1 * [int](0 + $_.candidate_contract_rows) }; Ascending = $true }, `
                symbol_alias
    )
}

function New-GuardrailMap {
    param([object[]]$Items)

    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $alias = [string]$item.symbol_alias
        if ([string]::IsNullOrWhiteSpace($alias)) { continue }
        $map[$alias.Trim().ToUpperInvariant()] = [string]$item.guardrail_state
    }
    return $map
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$trainingReadiness = Read-JsonSafe -Path $TrainingReadinessPath
if ($null -eq $trainingReadiness) {
    throw "Missing training readiness report: $TrainingReadinessPath"
}

$guardrails = Read-JsonSafe -Path $LocalTrainingGuardrailsPath
$guardrailMap = New-GuardrailMap -Items @($guardrails.items)

$items = @($trainingReadiness.items)
$readyCandidates = Sort-TrainingItems -Items @(
    $items | Where-Object {
        $alias = ([string]$_.symbol_alias).Trim().ToUpperInvariant()
        $guardrailState = if ($guardrailMap.ContainsKey($alias)) { $guardrailMap[$alias] } else { [string]$_.guardrail_state }
        $_.training_readiness_state -eq "LOCAL_TRAINING_READY" -and
        $guardrailState -notin @("PROBATION_ONLY", "FORCED_GLOBAL_FALLBACK")
    }
)
$limitedCandidates = Sort-TrainingItems -Items @(
    $items | Where-Object {
        $alias = ([string]$_.symbol_alias).Trim().ToUpperInvariant()
        $guardrailState = if ($guardrailMap.ContainsKey($alias)) { $guardrailMap[$alias] } else { [string]$_.guardrail_state }
        $_.training_readiness_state -eq "LOCAL_TRAINING_LIMITED" -or
        $guardrailState -eq "PROBATION_ONLY"
    }
)
$shadowCandidates = Sort-TrainingItems -Items @($items | Where-Object { $_.training_readiness_state -eq "TRAINING_SHADOW_READY" })

$startGroup = @($readyCandidates | Select-Object -First $MaxStartGroupSize)
$reserveReady = @($readyCandidates | Select-Object -Skip $MaxStartGroupSize)
$limitedWatchlist = @($limitedCandidates | Select-Object -First $MaxLimitedWatchlistSize)

$nextAction = if ($startGroup.Count -gt 0) {
    "START_READY_GROUP"
}
elseif ($limitedWatchlist.Count -gt 0) {
    "OBSERVE_LIMITED_GROUP"
}
else {
    "WAIT_FOR_MORE_SIGNAL"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    execution_mode = "TEACHER_GUARDED_SMALL_SPOON"
    max_start_group_size = $MaxStartGroupSize
    max_limited_watchlist_size = $MaxLimitedWatchlistSize
    next_action = $nextAction
    summary = [ordered]@{
        total_symbols = @($items).Count
        ready_candidates_count = @($readyCandidates).Count
        limited_candidates_count = @($limitedCandidates).Count
        shadow_candidates_count = @($shadowCandidates).Count
        start_group_count = @($startGroup).Count
        reserve_ready_count = @($reserveReady).Count
        probation_excluded_from_start_count = @(
            $items | Where-Object {
                $alias = ([string]$_.symbol_alias).Trim().ToUpperInvariant()
                $guardrailState = if ($guardrailMap.ContainsKey($alias)) { $guardrailMap[$alias] } else { [string]$_.guardrail_state }
                $guardrailState -eq "PROBATION_ONLY"
            }
        ).Count
    }
    start_group = $startGroup
    reserve_ready = $reserveReady
    limited_watchlist = $limitedWatchlist
    shadow_watchlist = @($shadowCandidates | Select-Object -First 5)
}

$jsonPath = Join-Path $OutputRoot "instrument_local_training_plan_latest.json"
$mdPath = Join-Path $OutputRoot "instrument_local_training_plan_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Instrument Local Training Plan")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- execution_mode: {0}" -f $report.execution_mode))
$lines.Add(("- next_action: {0}" -f $report.next_action))
foreach ($property in $report.summary.GetEnumerator()) {
    $lines.Add(("- {0}: {1}" -f $property.Key, $property.Value))
}
$lines.Add("")
$lines.Add("## Start Group")
$lines.Add("")
if ($startGroup.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $startGroup) {
        $lines.Add(("- {0}: readiness={1}, teacher_dependency={2}, outcome_rows={3}, runtime_rows={4}" -f
            $item.symbol_alias,
            $item.training_readiness_state,
            $item.teacher_dependency_level,
            $item.outcome_rows,
            $item.onnx_runtime_rows))
    }
}
$lines.Add("")
$lines.Add("## Limited Watchlist")
$lines.Add("")
if ($limitedWatchlist.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $limitedWatchlist) {
        $lines.Add(("- {0}: readiness={1}, teacher_dependency={2}, action={3}" -f
            $item.symbol_alias,
            $item.training_readiness_state,
            $item.teacher_dependency_level,
            $item.next_safe_action))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
