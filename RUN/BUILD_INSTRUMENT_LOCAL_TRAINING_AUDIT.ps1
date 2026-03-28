param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PlanPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_local_training_plan_latest.json",
    [string]$LanePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_local_training_lane_latest.json",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$TrainingReadinessPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_training_readiness_latest.json",
    [string]$LearningHealthPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\learning_health_registry_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [double]$RollbackMinRocAuc = 0.75,
    [double]$RollbackMinBalancedAccuracy = 0.60,
    [double]$ProbationMinRocAuc = 0.82,
    [double]$ProbationMinBalancedAccuracy = 0.70,
    [int]$RollbackMinRows = 30000,
    [int]$RollbackMinClassRows = 1000,
    [switch]$ApplySafeRollback
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ($null -ne $raw) {
            $raw = $raw.TrimStart([char]0xFEFF)
        }
        return $raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Normalize-SymbolAlias {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return $Value.Trim().ToUpperInvariant()
}

function New-MapByAlias {
    param(
        [object[]]$Items,
        [string[]]$CandidateKeys = @("symbol_alias", "symbol")
    )

    $map = @{}
    foreach ($item in @($Items)) {
        if ($null -eq $item) {
            continue
        }

        foreach ($keyName in $CandidateKeys) {
            if (-not ($item.PSObject.Properties.Name -contains $keyName)) {
                continue
            }

            $alias = Normalize-SymbolAlias -Value ([string]$item.$keyName)
            if ([string]::IsNullOrWhiteSpace($alias)) {
                continue
            }

            if (-not $map.ContainsKey($alias)) {
                $map[$alias] = $item
            }
        }
    }

    return $map
}

function Get-OptionalNumber {
    param(
        [object]$Object,
        [string]$Name,
        [double]$Default = 0
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    $value = $Object.$Name
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $Default
    }

    return [double]$value
}

function Get-OptionalString {
    param(
        [object]$Object,
        [string]$Name,
        [string]$Default = ""
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Name)) {
        return $Default
    }

    return [string]$Object.$Name
}

function Add-CohortItems {
    param(
        [System.Collections.Generic.List[object]]$Target,
        [object[]]$SourceItems,
        [string]$Cohort,
        [hashtable]$Seen
    )

    foreach ($item in @($SourceItems)) {
        if ($null -eq $item) {
            continue
        }

        $alias = Normalize-SymbolAlias -Value ([string]$item.symbol_alias)
        if ([string]::IsNullOrWhiteSpace($alias)) {
            continue
        }

        if ($Seen.ContainsKey($alias)) {
            continue
        }

        $Seen[$alias] = $true
        $Target.Add([pscustomobject]@{
            symbol_alias = $alias
            cohort = $Cohort
            training_readiness_state = if ($item.PSObject.Properties.Name -contains 'training_readiness_state') { [string]$item.training_readiness_state } else { "" }
            teacher_dependency_level = if ($item.PSObject.Properties.Name -contains 'teacher_dependency_level') { [string]$item.teacher_dependency_level } else { "" }
        }) | Out-Null
    }
}

function Resolve-AuditState {
    param(
        [object]$RegistryEntry,
        [object]$ReadinessEntry,
        [object]$HealthEntry,
        [double]$RollbackMinRocAuc,
        [double]$RollbackMinBalancedAccuracy,
        [double]$ProbationMinRocAuc,
        [double]$ProbationMinBalancedAccuracy,
        [int]$RollbackMinRows,
        [int]$RollbackMinClassRows
    )

    $status = Get-OptionalString -Object $RegistryEntry -Name "status" -Default ""
    $rocAuc = Get-OptionalNumber -Object $RegistryEntry -Name "roc_auc" -Default 0
    $balancedAccuracy = Get-OptionalNumber -Object $RegistryEntry -Name "balanced_accuracy" -Default 0
    $rowsTotal = [int](Get-OptionalNumber -Object $RegistryEntry -Name "rows_total" -Default 0)
    $positiveRows = [int](Get-OptionalNumber -Object $RegistryEntry -Name "positive_rows" -Default 0)
    $negativeRows = [int](Get-OptionalNumber -Object $RegistryEntry -Name "negative_rows" -Default 0)
    $trainingState = Get-OptionalString -Object $ReadinessEntry -Name "training_readiness_state" -Default ""
    $healthState = Get-OptionalString -Object $HealthEntry -Name "learning_health_state" -Default ""

    if ($null -eq $RegistryEntry) {
        return [pscustomobject]@{
            audit_state = "ROLLBACK"
            guardrail_state = "FORCED_GLOBAL_FALLBACK"
            reason = "Brak wpisu w rejestrze modelu per instrument dla symbolu monitorowanego."
        }
    }

    if ($status -ne "MODEL_PER_SYMBOL_READY") {
        return [pscustomobject]@{
            audit_state = "ROLLBACK"
            guardrail_state = "FORCED_GLOBAL_FALLBACK"
            reason = "Symbol monitorowany nie ma gotowego modelu per instrument i musi wrocic do nauczyciela globalnego."
        }
    }

    if ($rowsTotal -lt $RollbackMinRows -or $positiveRows -lt $RollbackMinClassRows -or $negativeRows -lt $RollbackMinClassRows) {
        return [pscustomobject]@{
            audit_state = "ROLLBACK"
            guardrail_state = "FORCED_GLOBAL_FALLBACK"
            reason = "Lokalny trening ma zbyt mala probe, by utrzymywac bezpieczny tor per instrument."
        }
    }

    if ($rocAuc -lt $RollbackMinRocAuc -or $balancedAccuracy -lt $RollbackMinBalancedAccuracy) {
        return [pscustomobject]@{
            audit_state = "ROLLBACK"
            guardrail_state = "FORCED_GLOBAL_FALLBACK"
            reason = "Metryki lokalnego modelu spadly ponizej bezpiecznego minimum i symbol musi byc cofnięty do nauczyciela globalnego."
        }
    }

    if (
        $rocAuc -lt $ProbationMinRocAuc -or
        $balancedAccuracy -lt $ProbationMinBalancedAccuracy -or
        $trainingState -eq "LOCAL_TRAINING_LIMITED" -or
        $healthState -in @("WYMAGA_DOSZKOLENIA", "WYMAGA_REGENERACJI")
    ) {
        return [pscustomobject]@{
            audit_state = "PROBATION"
            guardrail_state = "PROBATION_ONLY"
            reason = "Symbol powinien pozostac w ograniczonym torze lokalnym pod twardym audytem i bez awansu."
        }
    }

    return [pscustomobject]@{
        audit_state = "STABLE"
        guardrail_state = "ALLOW"
        reason = "Metryki i stan danych sa wystarczajaco stabilne dla malej lyzki lokalnego toru."
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$plan = Read-JsonSafe -Path $PlanPath
$lane = Read-JsonSafe -Path $LanePath
$registry = Read-JsonSafe -Path $RegistryPath
$trainingReadiness = Read-JsonSafe -Path $TrainingReadinessPath
$learningHealth = Read-JsonSafe -Path $LearningHealthPath

if ($null -eq $plan) {
    throw "Missing local training plan: $PlanPath"
}

$trainingMap = New-MapByAlias -Items @($trainingReadiness.items)
$healthMap = New-MapByAlias -Items @($learningHealth.items)
$registryMap = New-MapByAlias -Items @($registry.items)

$monitorSet = New-Object System.Collections.Generic.List[object]
$seen = @{}
Add-CohortItems -Target $monitorSet -SourceItems @($plan.start_group) -Cohort "START_GROUP" -Seen $seen
Add-CohortItems -Target $monitorSet -SourceItems @($plan.reserve_ready) -Cohort "RESERVE_READY" -Seen $seen
if ($null -ne $lane) {
    $trainedSymbols = @($lane.trained_symbols | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    Add-CohortItems -Target $monitorSet -SourceItems @($trainedSymbols | ForEach-Object {
        [pscustomobject]@{ symbol_alias = [string]$_ }
    }) -Cohort "TRAINED" -Seen $seen
}

$items = New-Object System.Collections.Generic.List[object]
$guardrailItems = New-Object System.Collections.Generic.List[object]

foreach ($entry in @($monitorSet.ToArray())) {
    $alias = Normalize-SymbolAlias -Value ([string]$entry.symbol_alias)
    $registryEntry = if ($registryMap.ContainsKey($alias)) { $registryMap[$alias] } else { $null }
    $trainingEntry = if ($trainingMap.ContainsKey($alias)) { $trainingMap[$alias] } else { $null }
    $healthEntry = if ($healthMap.ContainsKey($alias)) { $healthMap[$alias] } else { $null }
    $auditDecision = Resolve-AuditState `
        -RegistryEntry $registryEntry `
        -ReadinessEntry $trainingEntry `
        -HealthEntry $healthEntry `
        -RollbackMinRocAuc $RollbackMinRocAuc `
        -RollbackMinBalancedAccuracy $RollbackMinBalancedAccuracy `
        -ProbationMinRocAuc $ProbationMinRocAuc `
        -ProbationMinBalancedAccuracy $ProbationMinBalancedAccuracy `
        -RollbackMinRows $RollbackMinRows `
        -RollbackMinClassRows $RollbackMinClassRows

    $item = [pscustomobject]@{
        symbol_alias = $alias
        cohort = [string]$entry.cohort
        training_readiness_state = if ($null -ne $trainingEntry) { [string]$trainingEntry.training_readiness_state } else { [string]$entry.training_readiness_state }
        teacher_dependency_level = if ($null -ne $trainingEntry) { [string]$trainingEntry.teacher_dependency_level } else { [string]$entry.teacher_dependency_level }
        learning_health_state = if ($null -ne $healthEntry) { [string]$healthEntry.learning_health_state } else { "" }
        registry_status = Get-OptionalString -Object $registryEntry -Name "status" -Default "MISSING"
        rows_total = [int](Get-OptionalNumber -Object $registryEntry -Name "rows_total" -Default 0)
        positive_rows = [int](Get-OptionalNumber -Object $registryEntry -Name "positive_rows" -Default 0)
        negative_rows = [int](Get-OptionalNumber -Object $registryEntry -Name "negative_rows" -Default 0)
        roc_auc = [math]::Round((Get-OptionalNumber -Object $registryEntry -Name "roc_auc" -Default 0), 4)
        balanced_accuracy = [math]::Round((Get-OptionalNumber -Object $registryEntry -Name "balanced_accuracy" -Default 0), 4)
        audit_state = [string]$auditDecision.audit_state
        guardrail_state = [string]$auditDecision.guardrail_state
        diagnosis = [string]$auditDecision.reason
    }
    $items.Add($item) | Out-Null

    $guardrailItems.Add([pscustomobject]@{
        symbol_alias = $alias
        guardrail_state = [string]$auditDecision.guardrail_state
        apply_safe_rollback = [bool]$ApplySafeRollback
        source = "instrument_local_training_audit"
        diagnosis = [string]$auditDecision.reason
        cohort = [string]$entry.cohort
        recorded_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }) | Out-Null
}

$itemsArray = @(
    $items.ToArray() |
        Sort-Object `
            @{ Expression = {
                switch ([string]$_.audit_state) {
                    "ROLLBACK" { 0 }
                    "PROBATION" { 1 }
                    "STABLE" { 2 }
                    default { 3 }
                }
            }; Ascending = $true }, `
            @{ Expression = { [string]$_.cohort }; Ascending = $true }, `
            symbol_alias
)

$guardrailArray = @($guardrailItems.ToArray() | Sort-Object symbol_alias)
$rollbackItems = @($itemsArray | Where-Object { $_.audit_state -eq "ROLLBACK" })
$probationItems = @($itemsArray | Where-Object { $_.audit_state -eq "PROBATION" })
$stableItems = @($itemsArray | Where-Object { $_.audit_state -eq "STABLE" })

$auditSummary = [ordered]@{
    monitored_symbols_count = $itemsArray.Count
    stable_count = $stableItems.Count
    probation_count = $probationItems.Count
    rollback_count = $rollbackItems.Count
    repair_applied_count = @($guardrailArray | Where-Object { $_.guardrail_state -ne "ALLOW" }).Count
    guardrail_forced_fallback_count = @($guardrailArray | Where-Object { $_.guardrail_state -eq "FORCED_GLOBAL_FALLBACK" }).Count
    guardrail_probation_count = @($guardrailArray | Where-Object { $_.guardrail_state -eq "PROBATION_ONLY" }).Count
}

$auditVerdict = if ($auditSummary.rollback_count -gt 0) {
    "ROLLBACK_WYMAGANY"
}
elseif ($auditSummary.probation_count -gt 0) {
    "PROBATION_ONLY"
}
else {
    "TOR_STABILNY"
}

$auditReport = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    apply_safe_rollback = [bool]$ApplySafeRollback
    verdict = $auditVerdict
    thresholds = [ordered]@{
        rollback_min_roc_auc = $RollbackMinRocAuc
        rollback_min_balanced_accuracy = $RollbackMinBalancedAccuracy
        probation_min_roc_auc = $ProbationMinRocAuc
        probation_min_balanced_accuracy = $ProbationMinBalancedAccuracy
        rollback_min_rows = $RollbackMinRows
        rollback_min_class_rows = $RollbackMinClassRows
    }
    summary = $auditSummary
    rollback = @($rollbackItems)
    probation = @($probationItems)
    stable = @($stableItems | Select-Object -First 8)
    items = $itemsArray
}

$guardrailReport = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    source_verdict = $auditVerdict
    apply_safe_rollback = [bool]$ApplySafeRollback
    summary = [ordered]@{
        total_symbols = $guardrailArray.Count
        allow_count = @($guardrailArray | Where-Object { $_.guardrail_state -eq "ALLOW" }).Count
        probation_count = @($guardrailArray | Where-Object { $_.guardrail_state -eq "PROBATION_ONLY" }).Count
        forced_global_fallback_count = @($guardrailArray | Where-Object { $_.guardrail_state -eq "FORCED_GLOBAL_FALLBACK" }).Count
    }
    items = $guardrailArray
}

$auditJsonPath = Join-Path $OutputRoot "instrument_local_training_audit_latest.json"
$auditMdPath = Join-Path $OutputRoot "instrument_local_training_audit_latest.md"
$guardrailJsonPath = Join-Path $OutputRoot "instrument_local_training_guardrails_latest.json"
$guardrailMdPath = Join-Path $OutputRoot "instrument_local_training_guardrails_latest.md"

$auditReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $auditJsonPath -Encoding UTF8
$guardrailReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $guardrailJsonPath -Encoding UTF8

$auditLines = New-Object System.Collections.Generic.List[string]
$auditLines.Add("# Instrument Local Training Audit")
$auditLines.Add("")
$auditLines.Add(("- generated_at_local: {0}" -f $auditReport.generated_at_local))
$auditLines.Add(("- verdict: {0}" -f $auditReport.verdict))
$auditLines.Add(("- monitored_symbols_count: {0}" -f $auditReport.summary.monitored_symbols_count))
$auditLines.Add(("- stable_count: {0}" -f $auditReport.summary.stable_count))
$auditLines.Add(("- probation_count: {0}" -f $auditReport.summary.probation_count))
$auditLines.Add(("- rollback_count: {0}" -f $auditReport.summary.rollback_count))
$auditLines.Add("")
$auditLines.Add("## Rollback")
$auditLines.Add("")
if ($auditReport.rollback.Count -eq 0) {
    $auditLines.Add("- none")
}
else {
    foreach ($item in @($auditReport.rollback)) {
        $auditLines.Add(("- {0}: cohort={1}, roc_auc={2}, balanced_accuracy={3}, rows={4}, diagnosis={5}" -f
            $item.symbol_alias,
            $item.cohort,
            $item.roc_auc,
            $item.balanced_accuracy,
            $item.rows_total,
            $item.diagnosis))
    }
}
$auditLines.Add("")
$auditLines.Add("## Probation")
$auditLines.Add("")
if ($auditReport.probation.Count -eq 0) {
    $auditLines.Add("- none")
}
else {
    foreach ($item in @($auditReport.probation)) {
        $auditLines.Add(("- {0}: cohort={1}, roc_auc={2}, balanced_accuracy={3}, diagnosis={4}" -f
            $item.symbol_alias,
            $item.cohort,
            $item.roc_auc,
            $item.balanced_accuracy,
            $item.diagnosis))
    }
}
($auditLines -join "`r`n") | Set-Content -LiteralPath $auditMdPath -Encoding UTF8

$guardrailLines = New-Object System.Collections.Generic.List[string]
$guardrailLines.Add("# Instrument Local Training Guardrails")
$guardrailLines.Add("")
$guardrailLines.Add(("- generated_at_local: {0}" -f $guardrailReport.generated_at_local))
$guardrailLines.Add(("- source_verdict: {0}" -f $guardrailReport.source_verdict))
$guardrailLines.Add(("- forced_global_fallback_count: {0}" -f $guardrailReport.summary.forced_global_fallback_count))
$guardrailLines.Add(("- probation_count: {0}" -f $guardrailReport.summary.probation_count))
$guardrailLines.Add("")
foreach ($item in @($guardrailReport.items | Where-Object { $_.guardrail_state -ne "ALLOW" })) {
    $guardrailLines.Add(("- {0}: state={1}, cohort={2}, diagnosis={3}" -f
        $item.symbol_alias,
        $item.guardrail_state,
        $item.cohort,
        $item.diagnosis))
}
if (@($guardrailReport.items | Where-Object { $_.guardrail_state -ne "ALLOW" }).Count -eq 0) {
    $guardrailLines.Add("- none")
}
($guardrailLines -join "`r`n") | Set-Content -LiteralPath $guardrailMdPath -Encoding UTF8

$auditReport | ConvertTo-Json -Depth 8
