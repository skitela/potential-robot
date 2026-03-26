param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PlanScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_INSTRUMENT_LOCAL_TRAINING_PLAN.ps1",
    [string]$TrainerScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\TRAIN_PAPER_GATE_ACCEPTOR_MODELS_PER_SYMBOL.ps1",
    [string]$OnnxReviewScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_ONNX_MICRO_REVIEW_REPORT.ps1",
    [string]$HealthRegistryScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1",
    [string]$LocalTrainingAuditScriptPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_INSTRUMENT_LOCAL_TRAINING_AUDIT.ps1",
    [string]$PlanPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\instrument_local_training_plan_latest.json",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\onnx_symbol_registry_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$MaxStartGroupSize = 2,
    [int]$CooldownMinutes = 180,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function ConvertTo-SymbolSet {
    param([object[]]$Items)

    return @(
        @($Items) |
            ForEach-Object { [string]$_.symbol_alias } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            ForEach-Object { $_.Trim().ToUpperInvariant() }
    )
}

foreach ($path in @($PlanScriptPath, $TrainerScriptPath, $OnnxReviewScriptPath, $HealthRegistryScriptPath, $LocalTrainingAuditScriptPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$latestPath = Join-Path $OutputRoot "instrument_local_training_lane_latest.json"
$mdPath = Join-Path $OutputRoot "instrument_local_training_lane_latest.md"

$null = & $PlanScriptPath -ProjectRoot $ProjectRoot -MaxStartGroupSize $MaxStartGroupSize
$plan = Read-JsonSafe -Path $PlanPath
if ($null -eq $plan) {
    throw "Local training plan missing after build: $PlanPath"
}

$selectedEntries = @($plan.start_group)
$selectedSymbols = ConvertTo-SymbolSet -Items @($plan.start_group)
$selectedTrainingStates = @(
    @($selectedEntries) |
        ForEach-Object { [string]$_.training_readiness_state } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Sort-Object -Unique
)
$allowedTrainingStates = if (@($selectedTrainingStates).Count -gt 0) {
    @($selectedTrainingStates)
}
else {
    @("LOCAL_TRAINING_READY")
}
$trainerMinRows = 30000
$trainerMinPositiveRows = 1000
$trainerMinNegativeRows = 1000
$limitedOnlyStartGroup = (@($selectedTrainingStates).Count -gt 0 -and (@($selectedTrainingStates | Where-Object { $_ -ne "LOCAL_TRAINING_LIMITED" }).Count -eq 0))
if ($limitedOnlyStartGroup) {
    # Limitowany tor dostaje mniejsza lyzke i pozostaje pod probation, a nie pelnym awansem.
    $trainerMinRows = 20000
    $trainerMinPositiveRows = 500
    $trainerMinNegativeRows = 500
}

$previous = Read-JsonSafe -Path $latestPath
$now = Get-Date
$cooldownActive = $false
$cooldownMinutesLeft = 0

if ($null -ne $previous -and @($selectedSymbols).Count -gt 0) {
    $previousSelected = ConvertTo-SymbolSet -Items @($previous.start_group)
    $previousAt = $null
    if ($previous.generated_at_local) {
        try {
            $previousAt = [datetime]::ParseExact([string]$previous.generated_at_local, "yyyy-MM-dd HH:mm:ss", $null)
        }
        catch {
            $previousAt = $null
        }
    }

    if ($null -ne $previousAt -and (@($previousSelected) -join '|') -eq (@($selectedSymbols) -join '|')) {
        $elapsedMinutes = ((Get-Date) - $previousAt).TotalMinutes
        if ($elapsedMinutes -lt $CooldownMinutes -and [string]$previous.state -in @("completed", "cooldown_active")) {
            $cooldownActive = $true
            $cooldownMinutesLeft = [Math]::Ceiling($CooldownMinutes - $elapsedMinutes)
        }
    }
}

$state = "completed"
$trainedSymbols = @()
$registryReadyCount = 0
$registryFallbackCount = 0
$localTrainingAudit = $null
$notes = New-Object System.Collections.Generic.List[string]

if (@($selectedSymbols).Count -eq 0) {
    $state = "no_ready_symbols"
    $notes.Add("Brak symboli gotowych do bezpiecznej malej grupy lokalnego treningu.") | Out-Null
}
elseif ($cooldownActive) {
    $state = "cooldown_active"
    $notes.Add(("Obowiazuje cooldown dla tej samej grupy startowej: {0} minut." -f $cooldownMinutesLeft)) | Out-Null
}
else {
    $null = & $TrainerScriptPath `
        -ProjectRoot $ProjectRoot `
        -TrainingReadinessPath (Join-Path $OutputRoot "instrument_training_readiness_latest.json") `
        -AllowedTrainingStates $allowedTrainingStates `
        -SymbolAllowList $selectedSymbols `
        -MaxSymbols @($selectedSymbols).Count `
        -MinRows $trainerMinRows `
        -MinPositiveRows $trainerMinPositiveRows `
        -MinNegativeRows $trainerMinNegativeRows `
        -PerfProfile $PerfProfile

    & $OnnxReviewScriptPath | Out-Null
    & $HealthRegistryScriptPath -ProjectRoot $ProjectRoot | Out-Null

    $registry = Read-JsonSafe -Path $RegistryPath
    if ($null -ne $registry) {
        $selectedMap = @{}
        foreach ($symbol in @($selectedSymbols)) {
            $selectedMap[$symbol] = $true
        }
        foreach ($item in @($registry.items)) {
            $symbol = ""
            if ($item.PSObject.Properties['symbol']) {
                $symbol = [string]$item.symbol
            }
            if ([string]::IsNullOrWhiteSpace($symbol)) {
                continue
            }
            $symbol = $symbol.Trim().ToUpperInvariant()
            if (-not $selectedMap.ContainsKey($symbol)) {
                continue
            }

            if ([string]$item.status -eq "MODEL_PER_SYMBOL_READY") {
                $trainedSymbols += $symbol
            }
        }

    }
}

$registry = Read-JsonSafe -Path $RegistryPath
if ($null -ne $registry) {
    $registryReadyCount = @($registry.items | Where-Object { [string]$_.status -eq "MODEL_PER_SYMBOL_READY" }).Count
    $registryFallbackCount = @($registry.items | Where-Object { [string]$_.status -ne "MODEL_PER_SYMBOL_READY" }).Count
    $selectedMap = @{}
    foreach ($symbol in @($selectedSymbols)) {
        $selectedMap[$symbol] = $true
    }
    $matchedReadySymbols = @(
        $registry.items | Where-Object {
            $symbol = ""
            if ($_.PSObject.Properties['symbol']) {
                $symbol = [string]$_.symbol
            }
            if ([string]::IsNullOrWhiteSpace($symbol)) {
                return $false
            }
            $selectedMap.ContainsKey($symbol.Trim().ToUpperInvariant()) -and ([string]$_.status -eq "MODEL_PER_SYMBOL_READY")
        } | ForEach-Object {
            [string]$_.symbol
        }
    )
    $trainedSymbols = @($matchedReadySymbols | Sort-Object -Unique)
}

$localTrainingAudit = (& $LocalTrainingAuditScriptPath -ProjectRoot $ProjectRoot -ApplySafeRollback:$true | ConvertFrom-Json)

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = $now.ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = $now.ToUniversalTime().ToString("o")
    state = $state
    perf_profile = $PerfProfile
    max_start_group_size = $MaxStartGroupSize
    cooldown_minutes = $CooldownMinutes
    cooldown_minutes_left = $cooldownMinutesLeft
    allowed_training_states = @($allowedTrainingStates)
    trainer_min_rows = $trainerMinRows
    trainer_min_positive_rows = $trainerMinPositiveRows
    trainer_min_negative_rows = $trainerMinNegativeRows
    next_action = [string]$plan.next_action
    start_group = @($plan.start_group)
    trained_symbols = @($trainedSymbols | Sort-Object -Unique)
    local_training_audit = if ($null -ne $localTrainingAudit) {
        [ordered]@{
            verdict = [string]$localTrainingAudit.verdict
            rollback_count = [int]$localTrainingAudit.summary.rollback_count
            probation_count = [int]$localTrainingAudit.summary.probation_count
            repair_applied_count = [int]$localTrainingAudit.summary.repair_applied_count
        }
    } else { $null }
    summary = [ordered]@{
        start_group_count = @($selectedSymbols).Count
        trained_symbols_count = @($trainedSymbols | Sort-Object -Unique).Count
        registry_ready_count = $registryReadyCount
        registry_fallback_count = $registryFallbackCount
        audit_rollback_count = if ($null -ne $localTrainingAudit) { [int]$localTrainingAudit.summary.rollback_count } else { 0 }
        audit_probation_count = if ($null -ne $localTrainingAudit) { [int]$localTrainingAudit.summary.probation_count } else { 0 }
    }
    notes = @($notes.ToArray())
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Instrument Local Training Lane")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- state: {0}" -f $report.state))
$lines.Add(("- perf_profile: {0}" -f $report.perf_profile))
$lines.Add(("- allowed_training_states: {0}" -f ((@($report.allowed_training_states) -join ", "))))
$lines.Add(("- trainer_min_rows: {0}" -f $report.trainer_min_rows))
$lines.Add(("- trainer_min_positive_rows: {0}" -f $report.trainer_min_positive_rows))
$lines.Add(("- trainer_min_negative_rows: {0}" -f $report.trainer_min_negative_rows))
$lines.Add(("- next_action: {0}" -f $report.next_action))
$lines.Add(("- start_group_count: {0}" -f $report.summary.start_group_count))
$lines.Add(("- trained_symbols_count: {0}" -f $report.summary.trained_symbols_count))
$lines.Add(("- registry_ready_count: {0}" -f $report.summary.registry_ready_count))
$lines.Add(("- registry_fallback_count: {0}" -f $report.summary.registry_fallback_count))
$lines.Add(("- audit_rollback_count: {0}" -f $report.summary.audit_rollback_count))
$lines.Add(("- audit_probation_count: {0}" -f $report.summary.audit_probation_count))
$lines.Add("")
$lines.Add("## Start Group")
$lines.Add("")
if (@($report.start_group).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in @($report.start_group)) {
        $lines.Add(("- {0}: readiness={1}, teacher_dependency={2}, outcome_rows={3}" -f
            $item.symbol_alias,
            $item.training_readiness_state,
            $item.teacher_dependency_level,
            $item.outcome_rows))
    }
}
$lines.Add("")
$lines.Add("## Trained Symbols")
$lines.Add("")
if (@($report.trained_symbols).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($symbol in @($report.trained_symbols)) {
        $lines.Add(("- {0}" -f $symbol))
    }
}
$lines.Add("")
$lines.Add("## Notes")
$lines.Add("")
if (@($report.notes).Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($note in @($report.notes)) {
        $lines.Add(("- {0}" -f $note))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
