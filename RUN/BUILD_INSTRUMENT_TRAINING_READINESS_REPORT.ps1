param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$DataReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_data_readiness_latest.json",
    [string]$TechnicalReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_technical_readiness_latest.json",
    [string]$LearningHealthPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_health_registry_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
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

function New-MapByAlias {
    param([object[]]$Items)

    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) { continue }
        $alias = [string]$item.symbol_alias
        if ([string]::IsNullOrWhiteSpace($alias)) { continue }
        $map[$alias.Trim().ToUpperInvariant()] = $item
    }
    return $map
}

function Get-TeacherDependencyLevel {
    param(
        [string]$HealthState,
        [string]$DataState
    )

    if ($DataState -in @("NO_RAW_HISTORY", "EXPORT_PENDING", "CONTRACT_PENDING")) { return "MAXIMAL" }
    if ($HealthState -in @("FALLBACK_GLOBALNY", "MALA_PROBKA")) { return "MAXIMAL" }
    if ($HealthState -in @("WYMAGA_DOSZKOLENIA", "WYMAGA_REGENERACJI")) { return "HIGH" }
    if ($HealthState -eq "GOTOWY_DO_OBSERWACJI") { return "MEDIUM" }
    if ($HealthState -in @("UCZY_SIE_ZDROWO", "GOTOWY_DO_MIEKKIEJ_BRAMKI")) { return "LOW" }
    return "HIGH"
}

function Get-TrainingReadinessState {
    param(
        [object]$DataEntry,
        [object]$TechnicalEntry,
        [object]$HealthEntry
    )

    $dataState = [string]$DataEntry.data_readiness_state
    $technicalReadiness = if ($null -ne $TechnicalEntry) { [string]$TechnicalEntry.technical_readiness } else { "" }
    $healthState = if ($null -ne $HealthEntry) { [string]$HealthEntry.learning_health_state } else { "" }
    $qdmRows = [int]$DataEntry.qdm_contract_rows
    $candidateRows = [int]$DataEntry.candidate_contract_rows
    $learningRows = [int]$DataEntry.learning_contract_rows
    $runtimeRows = [int]$DataEntry.onnx_runtime_rows
    $outcomeRows = [int]$DataEntry.outcome_rows

    if ($dataState -eq "NO_RAW_HISTORY") { return "FALLBACK_ONLY" }
    if ($dataState -eq "EXPORT_PENDING") { return "EXPORT_PENDING" }
    if ($dataState -eq "CONTRACT_PENDING") { return "CONTRACT_PENDING" }
    if ($technicalReadiness -eq "MT5_FALLBACK_ONLY") { return "FALLBACK_ONLY" }

    if (
        $qdmRows -ge 1000 -and
        $candidateRows -ge 5000 -and
        ($learningRows -ge 100 -or $outcomeRows -ge 100) -and
        $healthState -in @("UCZY_SIE_ZDROWO", "GOTOWY_DO_MIEKKIEJ_BRAMKI")
    ) {
        return "LOCAL_TRAINING_READY"
    }

    if (
        $qdmRows -gt 0 -and
        $candidateRows -ge 500 -and
        ($learningRows -ge 25 -or $runtimeRows -ge 25)
    ) {
        return "LOCAL_TRAINING_LIMITED"
    }

    return "TRAINING_SHADOW_READY"
}

function Get-LocalTrainingEligibility {
    param([string]$ReadinessState)

    switch ($ReadinessState) {
        "LOCAL_TRAINING_READY" { return "READY" }
        "LOCAL_TRAINING_LIMITED" { return "LIMITED" }
        "TRAINING_SHADOW_READY" { return "SHADOW_ONLY" }
        default { return "NO" }
    }
}

function Get-NextSafeAction {
    param(
        [string]$ReadinessState,
        [string]$TeacherDependency,
        [string]$HealthState
    )

    switch ($ReadinessState) {
        "FALLBACK_ONLY" { return "Pozostawic fallback globalny i odbudowac dane per instrument." }
        "EXPORT_PENDING" { return "Dokonczyc odzysk aktywnego eksportu QDM z dysku." }
        "CONTRACT_PENDING" { return "Przepuscic eksport przez kontrakt research i potwierdzic rows per symbol." }
        "TRAINING_SHADOW_READY" { return "Budowac shadow dataset per instrument i jeszcze nie startowac lokalnego treningu." }
        "LOCAL_TRAINING_LIMITED" {
            if ($TeacherDependency -eq "MAXIMAL" -or $HealthState -eq "WYMAGA_DOSZKOLENIA") {
                return "Uruchamiac lokalny trening tylko ograniczenie i pod parasolem nauczyciela globalnego."
            }
            return "Mozna uruchomic limitowany trening lokalny z bardzo twardym audytem."
        }
        "LOCAL_TRAINING_READY" { return "Mozna planowac bezpieczny lokalny trening per instrument w malej grupie startowej." }
        default { return "Wymaga recznego przegladu." }
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$dataReadiness = Read-JsonSafe -Path $DataReadinessPath
$technicalReadiness = Read-JsonSafe -Path $TechnicalReadinessPath
$learningHealth = Read-JsonSafe -Path $LearningHealthPath

if ($null -eq $dataReadiness) {
    throw "Missing data readiness report: $DataReadinessPath"
}

$technicalMap = New-MapByAlias -Items @($technicalReadiness.entries)
$healthMap = New-MapByAlias -Items @($learningHealth.items)

$items = New-Object System.Collections.Generic.List[object]

foreach ($dataEntry in @($dataReadiness.items)) {
    $alias = [string]$dataEntry.symbol_alias
    $key = $alias.Trim().ToUpperInvariant()
    $technicalEntry = if ($technicalMap.ContainsKey($key)) { $technicalMap[$key] } else { $null }
    $healthEntry = if ($healthMap.ContainsKey($key)) { $healthMap[$key] } else { $null }

    $trainingReadiness = Get-TrainingReadinessState -DataEntry $dataEntry -TechnicalEntry $technicalEntry -HealthEntry $healthEntry
    $teacherDependency = Get-TeacherDependencyLevel -HealthState $(if ($null -ne $healthEntry) { [string]$healthEntry.learning_health_state } else { "" }) -DataState ([string]$dataEntry.data_readiness_state)
    $eligibility = Get-LocalTrainingEligibility -ReadinessState $trainingReadiness
    $nextSafeAction = Get-NextSafeAction -ReadinessState $trainingReadiness -TeacherDependency $teacherDependency -HealthState $(if ($null -ne $healthEntry) { [string]$healthEntry.learning_health_state } else { "" })

    $items.Add([pscustomobject]@{
        symbol_alias = $alias
        data_readiness_state = [string]$dataEntry.data_readiness_state
        technical_readiness = if ($null -ne $technicalEntry) { [string]$technicalEntry.technical_readiness } else { "" }
        learning_health_state = if ($null -ne $healthEntry) { [string]$healthEntry.learning_health_state } else { "" }
        work_mode = if ($null -ne $healthEntry) { [string]$healthEntry.work_mode } else { "" }
        teacher_dependency_level = $teacherDependency
        local_training_eligibility = $eligibility
        training_readiness_state = $trainingReadiness
        qdm_contract_rows = [int]$dataEntry.qdm_contract_rows
        candidate_contract_rows = [int]$dataEntry.candidate_contract_rows
        learning_contract_rows = [int]$dataEntry.learning_contract_rows
        onnx_runtime_rows = [int]$dataEntry.onnx_runtime_rows
        outcome_rows = [int]$dataEntry.outcome_rows
        next_safe_action = $nextSafeAction
    }) | Out-Null
}

$itemsArray = @(
    $items.ToArray() |
        Sort-Object `
            @{ Expression = {
                switch ([string]$_.training_readiness_state) {
                    "EXPORT_PENDING" { 0 }
                    "CONTRACT_PENDING" { 1 }
                    "TRAINING_SHADOW_READY" { 2 }
                    "LOCAL_TRAINING_LIMITED" { 3 }
                    "LOCAL_TRAINING_READY" { 4 }
                    default { 5 }
                }
            }; Ascending = $true }, `
            symbol_alias
)

$summary = [ordered]@{
    total_symbols = $itemsArray.Count
    fallback_only_count = @($itemsArray | Where-Object { $_.training_readiness_state -eq "FALLBACK_ONLY" }).Count
    export_pending_count = @($itemsArray | Where-Object { $_.training_readiness_state -eq "EXPORT_PENDING" }).Count
    contract_pending_count = @($itemsArray | Where-Object { $_.training_readiness_state -eq "CONTRACT_PENDING" }).Count
    training_shadow_ready_count = @($itemsArray | Where-Object { $_.training_readiness_state -eq "TRAINING_SHADOW_READY" }).Count
    local_training_limited_count = @($itemsArray | Where-Object { $_.training_readiness_state -eq "LOCAL_TRAINING_LIMITED" }).Count
    local_training_ready_count = @($itemsArray | Where-Object { $_.training_readiness_state -eq "LOCAL_TRAINING_READY" }).Count
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    summary = $summary
    top_export_pending = @($itemsArray | Where-Object { $_.training_readiness_state -eq "EXPORT_PENDING" } | Select-Object -First 8)
    top_shadow_ready = @($itemsArray | Where-Object { $_.training_readiness_state -eq "TRAINING_SHADOW_READY" } | Select-Object -First 8)
    top_local_training_ready = @($itemsArray | Where-Object { $_.training_readiness_state -in @("LOCAL_TRAINING_LIMITED", "LOCAL_TRAINING_READY") } | Select-Object -First 8)
    items = $itemsArray
}

$jsonPath = Join-Path $OutputRoot "instrument_training_readiness_latest.json"
$mdPath = Join-Path $OutputRoot "instrument_training_readiness_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Instrument Training Readiness")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
foreach ($prop in $summary.GetEnumerator()) {
    $lines.Add(("- {0}: {1}" -f $prop.Key, $prop.Value))
}
$lines.Add("")
$lines.Add("## Top Export Pending")
$lines.Add("")
if ($report.top_export_pending.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $report.top_export_pending) {
        $lines.Add(("- {0}: teacher_dependency={1}, action={2}" -f $item.symbol_alias, $item.teacher_dependency_level, $item.next_safe_action))
    }
}
$lines.Add("")
$lines.Add("## Top Shadow Ready")
$lines.Add("")
if ($report.top_shadow_ready.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $report.top_shadow_ready) {
        $lines.Add(("- {0}: health={1}, rows={2}/{3}/{4}, action={5}" -f
            $item.symbol_alias,
            $item.learning_health_state,
            $item.qdm_contract_rows,
            $item.candidate_contract_rows,
            $item.learning_contract_rows,
            $item.next_safe_action))
    }
}
$lines.Add("")
$lines.Add("## Top Local Training Ready")
$lines.Add("")
if ($report.top_local_training_ready.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $report.top_local_training_ready) {
        $lines.Add(("- {0}: readiness={1}, teacher_dependency={2}, action={3}" -f
            $item.symbol_alias,
            $item.training_readiness_state,
            $item.teacher_dependency_level,
            $item.next_safe_action))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
