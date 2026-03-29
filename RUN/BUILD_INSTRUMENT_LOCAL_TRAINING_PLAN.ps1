param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TrainingReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\local_model_readiness_latest.json",
    [string]$LocalTrainingGuardrailsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_local_training_guardrails_latest.json",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
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

function Get-PropertyValue {
    param(
        [object]$Item,
        [string[]]$Names,
        $Default = $null
    )

    if ($null -eq $Item) {
        return $Default
    }

    foreach ($name in $Names) {
        if ($Item.PSObject.Properties.Name -contains $name) {
            $value = $Item.$name
            if ($null -ne $value -and -not ([string]::IsNullOrWhiteSpace([string]$value) -and $value -is [string])) {
                return $value
            }
        }
    }

    return $Default
}

function Normalize-TrainingItems {
    param([object]$Payload)

    if ($null -eq $Payload) {
        return @()
    }

    $rawItems = @()
    if ($Payload.PSObject.Properties.Name -contains "items") {
        $rawItems = @($Payload.items)
    }
    elseif ($Payload.PSObject.Properties.Name -contains "symbols") {
        foreach ($property in $Payload.symbols.PSObject.Properties) {
            $record = $property.Value
            $rawItems += [pscustomobject]@{
                symbol_alias = $property.Name
                training_state = Get-PropertyValue -Item $record -Names @("training_state", "training_mode") -Default "FALLBACK_ONLY"
                teacher_dependency_level = "MAXIMAL"
                outcome_rows = 0
                onnx_runtime_rows = 0
                candidate_rows = 0
                guardrail_state = ""
                next_safe_action = "Brak pelnego raportu gotowosci lokalnej; pozostawic symbol przy nauczycielu globalnym."
            }
        }
    }

    $normalized = foreach ($item in @($rawItems)) {
        [pscustomobject]@{
            symbol_alias = [string](Get-PropertyValue -Item $item -Names @("symbol_alias", "symbol") -Default "")
            training_readiness_state = [string](Get-PropertyValue -Item $item -Names @("training_readiness_state", "training_state", "training_mode") -Default "FALLBACK_ONLY")
            teacher_dependency_level = [string](Get-PropertyValue -Item $item -Names @("teacher_dependency_level") -Default "MAXIMAL")
            outcome_rows = [int](0 + (Get-PropertyValue -Item $item -Names @("outcome_rows") -Default 0))
            onnx_runtime_rows = [int](0 + (Get-PropertyValue -Item $item -Names @("onnx_runtime_rows") -Default 0))
            candidate_contract_rows = [int](0 + (Get-PropertyValue -Item $item -Names @("candidate_contract_rows", "candidate_rows") -Default 0))
            guardrail_state = [string](Get-PropertyValue -Item $item -Names @("guardrail_state") -Default "")
            next_safe_action = [string](Get-PropertyValue -Item $item -Names @("next_safe_action") -Default "")
            local_training_eligibility = [string](Get-PropertyValue -Item $item -Names @("local_training_eligibility") -Default "")
        }
    }

    return @($normalized | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.symbol_alias) })
}

function New-UniversePriorityMap {
    param([object]$UniversePlan)

    $map = @{}
    if ($null -eq $UniversePlan) {
        return $map
    }

    foreach ($symbol in @($UniversePlan.paper_live_first_wave)) {
        $alias = ([string]$symbol).Trim().ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($alias)) { $map[$alias] = "FIRST_WAVE" }
    }
    foreach ($symbol in @($UniversePlan.paper_live_second_wave)) {
        $alias = ([string]$symbol).Trim().ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($alias) -and -not $map.ContainsKey($alias)) { $map[$alias] = "SECOND_WAVE" }
    }
    foreach ($symbol in @($UniversePlan.paper_live_hold)) {
        $alias = ([string]$symbol).Trim().ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($alias) -and -not $map.ContainsKey($alias)) { $map[$alias] = "HOLD" }
    }
    foreach ($symbol in @($UniversePlan.global_teacher_only)) {
        $alias = ([string]$symbol).Trim().ToUpperInvariant()
        if (-not [string]::IsNullOrWhiteSpace($alias) -and -not $map.ContainsKey($alias)) { $map[$alias] = "GLOBAL_TEACHER_ONLY" }
    }

    return $map
}

function Get-UniversePriority {
    param(
        [string]$SymbolAlias,
        [hashtable]$UniversePriorityMap
    )

    $alias = ([string]$SymbolAlias).Trim().ToUpperInvariant()
    if ($UniversePriorityMap.ContainsKey($alias)) {
        switch ($UniversePriorityMap[$alias]) {
            "FIRST_WAVE" { return 0 }
            "SECOND_WAVE" { return 1 }
            "HOLD" { return 2 }
            "GLOBAL_TEACHER_ONLY" { return 3 }
            default { return 4 }
        }
    }

    return 5
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$trainingReadiness = Read-JsonSafe -Path $TrainingReadinessPath
if ($null -eq $trainingReadiness) {
    throw "Missing training readiness report: $TrainingReadinessPath"
}

$guardrails = Read-JsonSafe -Path $LocalTrainingGuardrailsPath
$guardrailMap = New-GuardrailMap -Items @($guardrails.items)
$universePlan = Read-JsonSafe -Path $UniversePlanPath
$universePriorityMap = New-UniversePriorityMap -UniversePlan $universePlan

$items = Normalize-TrainingItems -Payload $trainingReadiness
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

$readyCandidates = @(
    $readyCandidates |
        Sort-Object `
            @{ Expression = { Get-UniversePriority -SymbolAlias ([string]$_.symbol_alias) -UniversePriorityMap $universePriorityMap }; Ascending = $true }, `
            @{ Expression = { Get-TeacherPriority -Value ([string]$_.teacher_dependency_level) }; Ascending = $true }, `
            @{ Expression = { -1 * [int](0 + $_.outcome_rows) }; Ascending = $true }, `
            @{ Expression = { -1 * [int](0 + $_.onnx_runtime_rows) }; Ascending = $true }, `
            @{ Expression = { -1 * [int](0 + $_.candidate_contract_rows) }; Ascending = $true }, `
            symbol_alias
)
$limitedCandidates = @(
    $limitedCandidates |
        Sort-Object `
            @{ Expression = { Get-UniversePriority -SymbolAlias ([string]$_.symbol_alias) -UniversePriorityMap $universePriorityMap }; Ascending = $true }, `
            @{ Expression = { Get-TeacherPriority -Value ([string]$_.teacher_dependency_level) }; Ascending = $true }, `
            @{ Expression = { -1 * [int](0 + $_.outcome_rows) }; Ascending = $true }, `
            @{ Expression = { -1 * [int](0 + $_.onnx_runtime_rows) }; Ascending = $true }, `
            @{ Expression = { -1 * [int](0 + $_.candidate_contract_rows) }; Ascending = $true }, `
            symbol_alias
)

$limitedStartGroupSize = [Math]::Min([Math]::Max($MaxStartGroupSize, 1), 1)
$startGroup = @(
    if (@($readyCandidates).Count -gt 0) {
        @($readyCandidates | Select-Object -First $MaxStartGroupSize)
    }
    else {
        @($limitedCandidates | Select-Object -First $limitedStartGroupSize)
    }
)
$reserveReady = @($readyCandidates | Select-Object -Skip $MaxStartGroupSize)
$limitedWatchlist = @(
    if (@($readyCandidates).Count -gt 0) {
        @($limitedCandidates | Select-Object -First $MaxLimitedWatchlistSize)
    }
    else {
        @($limitedCandidates | Select-Object -Skip $limitedStartGroupSize | Select-Object -First $MaxLimitedWatchlistSize)
    }
)

$startGroupMode = if (@($readyCandidates).Count -gt 0) {
    "READY"
}
elseif (@($startGroup).Count -gt 0) {
    "LIMITED"
}
else {
    "NONE"
}

$nextAction = if (@($startGroup).Count -gt 0) {
    if ($startGroupMode -eq "READY") { "START_READY_GROUP" } else { "START_LIMITED_GROUP" }
}
elseif (@($limitedWatchlist).Count -gt 0) {
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
    universe_priority_mode = "SCALPING_FIRST_WAVE_FIRST"
    max_start_group_size = $MaxStartGroupSize
    max_limited_watchlist_size = $MaxLimitedWatchlistSize
    start_group_mode = $startGroupMode
    next_action = $nextAction
    summary = [ordered]@{
        total_symbols = @($items).Count
        ready_candidates_count = @($readyCandidates).Count
        limited_candidates_count = @($limitedCandidates).Count
        shadow_candidates_count = @($shadowCandidates).Count
        prioritized_first_wave_candidates_count = @(
            $items | Where-Object {
                $alias = ([string]$_.symbol_alias).Trim().ToUpperInvariant()
                $universePriorityMap.ContainsKey($alias) -and $universePriorityMap[$alias] -eq "FIRST_WAVE"
            }
        ).Count
        start_group_count = @($startGroup).Count
        limited_start_group_count = if ($startGroupMode -eq "LIMITED") { @($startGroup).Count } else { 0 }
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
$lines.Add(("- universe_priority_mode: {0}" -f $report.universe_priority_mode))
$lines.Add(("- start_group_mode: {0}" -f $report.start_group_mode))
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
