param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$FreshThresholdSeconds = 900,
    [string[]]$Symbols
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-FileProbe {
    param(
        [string]$Path,
        [int]$ThresholdSeconds
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            present = $false
            fresh = $false
            age_seconds = $null
            last_write_local = $null
            size_bytes = 0
        }
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    return [pscustomobject]@{
        present = $true
        fresh = ($ageSeconds -le $ThresholdSeconds)
        age_seconds = $ageSeconds
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        size_bytes = [int64]$item.Length
    }
}

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

function Get-LastDecisionEvent {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $lines = Get-Content -LiteralPath $Path -Tail 16 -ErrorAction SilentlyContinue
    if ($null -eq $lines) {
        return $null
    }

    $orderedLines = @($lines)
    [array]::Reverse($orderedLines)
    foreach ($line in $orderedLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t"
        if ($parts.Count -lt 5) {
            continue
        }

        if ($parts[0] -eq "ts") {
            continue
        }

        return [pscustomobject]@{
            phase = [string]$parts[2]
            reason = [string]$parts[4]
        }
    }

    return $null
}

function Get-GlobalTeacherSymbolsFromContract {
    param([string]$ProjectRoot)

    $contractPath = Join-Path $ProjectRoot "CONFIG\learning_universe_contract.json"
    $contract = Read-JsonSafe -Path $contractPath
    if ($null -eq $contract -or $null -eq $contract.symbols) {
        return @("DE30","GOLD","SILVER","USDJPY","USDCHF","COPPER-US","EURAUD","EURUSD","GBPUSD")
    }

    $resolved = New-Object System.Collections.Generic.List[string]
    foreach ($property in $contract.symbols.PSObject.Properties) {
        $name = [string]$property.Name
        $value = $property.Value
        $cohort = ""
        if ($null -ne $value) {
            $cohort = [string]$value.cohort
        }
        if ($cohort -eq "GLOBAL_TEACHER") {
            $resolved.Add($name) | Out-Null
        }
    }

    if ($resolved.Count -le 0) {
        return @("DE30","GOLD","SILVER","USDJPY","USDCHF","COPPER-US","EURAUD","EURUSD","GBPUSD")
    }

    return @($resolved.ToArray())
}

function Resolve-BlockerClass {
    param(
        [object]$Snapshot,
        [object]$GatePayload,
        [object]$DecisionProbe,
        [object]$OnnxProbe,
        [object]$GateProbe,
        [object]$LearningProbe,
        [object]$KnowledgeProbe
    )

    $lastStage = [string]($Snapshot.last_stage)
    $lastReason = [string]($Snapshot.last_reason_code)
    $lastScanSource = [string]($Snapshot.last_scan_source)
    $setupType = [string]($Snapshot.setup_type)
    $runtimeAlive = [bool]$Snapshot.runtime_heartbeat_alive
    $gateApplied = $false
    $gateReason = ""
    if ($null -ne $GatePayload) {
        $gateApplied = [bool]$GatePayload.gate_applied
        $gateReason = [string]$GatePayload.reason_code
    }
    $paperOpenVisible = [bool]$Snapshot.paper_open_visible
    $paperCloseVisible = [bool]$Snapshot.paper_close_visible
    $lessonVisible = [bool]$Snapshot.lesson_write_visible -or [bool]$LearningProbe.fresh
    $knowledgeVisible = [bool]$Snapshot.knowledge_write_visible -or [bool]$KnowledgeProbe.fresh
    $paperPositionOpen = [bool]$Snapshot.paper_position_open
    $gateVisible = ($gateApplied -or $paperOpenVisible -or $paperCloseVisible -or $lessonVisible -or $knowledgeVisible)

    if ($lessonVisible -and $knowledgeVisible) {
        return "FULL_LEARNING_OK"
    }
    if (($paperOpenVisible -or $paperPositionOpen) -and -not ($paperCloseVisible -or $lessonVisible -or $knowledgeVisible)) {
        return "GATE_VISIBLE_NO_OUTCOME"
    }
    if ($lastReason -like "*FAIL") {
        return "OUTCOME_WRITE_FAIL"
    }
    if ($lastScanSource -eq "TIMER_FALLBACK_SCAN" -and $lastReason -eq "WAIT_NEW_BAR") {
        return "WAIT_NEW_BAR_STARVED"
    }
    if ($lastReason -eq "WAIT_NEW_BAR" -and -not $gateVisible) {
        return "WAIT_NEW_BAR_STARVED"
    }
    if ($lastStage -eq "DIAGNOSTIC" -and $lastReason -eq "TIMER_FALLBACK_SCAN" -and -not $gateVisible -and -not $lessonVisible -and -not $knowledgeVisible) {
        return "WAIT_NEW_BAR_STARVED"
    }
    if ($lastReason -like "NO_SETUP_*" -or $setupType -eq "NONE") {
        return "NO_SETUP_STARVED"
    }
    if ($lastStage -eq "RATE_GUARD" -or $lastReason -in @("BROKER_ORDER_RATE_LIMIT","BROKER_PRICE_RATE_LIMIT")) {
        return "RATE_GUARD_STARVED"
    }
    if ($lastReason -like "*FREEZE*" -or $lastReason -like "*DEFENSIVE*" -or $lastReason -eq "COOL_FLEET") {
        return "TUNING_FREEZE_STARVED"
    }
    if ($lastReason -like "*BLOCK*" -or $lastReason -like "*DIRTY*" -or $lastReason -like "*DAILY_LOSS*" -or $lastReason -like "*PORTFOLIO_HEAT*") {
        return "SYMBOL_POLICY_STARVED"
    }
    if ($lastReason -in @("SCORE_BELOW_TRIGGER","LOW_CONFIDENCE","CONTEXT_LOW_CONFIDENCE")) {
        return "NO_SIGNAL_LOW_SCORE"
    }
    if ($gateVisible -and -not ($paperOpenVisible -or $paperCloseVisible -or $lessonVisible -or $knowledgeVisible)) {
        return "GATE_VISIBLE_NO_OUTCOME"
    }
    if ($runtimeAlive -and $DecisionProbe.fresh -and $OnnxProbe.fresh -and -not $gateVisible -and -not $paperPositionOpen) {
        return "HEARTBEAT_ONLY"
    }
    return "UNCLASSIFIED"
}

if ($null -eq $Symbols -or $Symbols.Count -le 0) {
    $Symbols = Get-GlobalTeacherSymbolsFromContract -ProjectRoot $ProjectRoot
}

$items = New-Object System.Collections.Generic.List[object]
foreach ($symbol in @($Symbols)) {
    $logsRoot = Join-Path $CommonFilesRoot ("logs\{0}" -f $symbol)
    $stateRoot = Join-Path $CommonFilesRoot ("state\{0}" -f $symbol)

    $decisionProbe = New-FileProbe -Path (Join-Path $logsRoot "decision_events.csv") -ThresholdSeconds $FreshThresholdSeconds
    $onnxProbe = New-FileProbe -Path (Join-Path $logsRoot "onnx_observations.csv") -ThresholdSeconds $FreshThresholdSeconds
    $learningProbe = New-FileProbe -Path (Join-Path $logsRoot "learning_observations_v2.csv") -ThresholdSeconds $FreshThresholdSeconds
    $knowledgeProbe = New-FileProbe -Path (Join-Path $logsRoot "broker_net_ledger_runtime.csv") -ThresholdSeconds $FreshThresholdSeconds
    $gatePayload = Read-JsonSafe -Path (Join-Path $stateRoot "student_gate_latest.json")
    $gateProbe = New-FileProbe -Path (Join-Path $stateRoot "student_gate_latest.json") -ThresholdSeconds $FreshThresholdSeconds
    $learningSnapshot = Read-JsonSafe -Path (Join-Path $stateRoot "learning_supervisor_snapshot_latest.json")
    $learningSnapshotProbe = New-FileProbe -Path (Join-Path $stateRoot "learning_supervisor_snapshot_latest.json") -ThresholdSeconds $FreshThresholdSeconds
    $lastDecisionEvent = Get-LastDecisionEvent -Path (Join-Path $logsRoot "decision_events.csv")

    if ($null -eq $learningSnapshot) {
        $learningSnapshot = [pscustomobject]@{
            runtime_heartbeat_alive = ($decisionProbe.fresh -and $onnxProbe.fresh)
            last_stage = if ($null -ne $lastDecisionEvent) { [string]$lastDecisionEvent.phase } else { "" }
            last_reason_code = if ($null -ne $lastDecisionEvent) { [string]$lastDecisionEvent.reason } else { "" }
            last_scan_source = ""
            setup_type = ""
            gate_visible = $false
            paper_open_visible = $false
            paper_close_visible = $false
            lesson_write_visible = $false
            knowledge_write_visible = $false
            local_training_mode = ""
            teacher_score = 0.0
            student_score = 0.0
        }
    }
    elseif ($null -ne $lastDecisionEvent -and ([string]$learningSnapshot.last_stage) -in @("", "BOOTSTRAP", "TIMER")) {
        $learningSnapshot.last_stage = [string]$lastDecisionEvent.phase
        $learningSnapshot.last_reason_code = [string]$lastDecisionEvent.reason
        if ([string]::IsNullOrWhiteSpace([string]$learningSnapshot.last_scan_source) -and [string]$lastDecisionEvent.phase -eq "DIAGNOSTIC" -and [string]$lastDecisionEvent.reason -eq "TIMER_FALLBACK_SCAN") {
            $learningSnapshot.last_scan_source = "TIMER_FALLBACK_SCAN"
        }
    }

    $teacherRuntimeActive = (($decisionProbe.fresh -and $onnxProbe.fresh) -or ($learningSnapshotProbe.fresh -and [bool]$learningSnapshot.runtime_heartbeat_alive))
    $signalPathActive = ($learningSnapshotProbe.fresh -and ([string]$learningSnapshot.last_stage) -notin @("", "BOOTSTRAP", "TIMER"))
    $fullLessonFresh = ($learningProbe.fresh -and $knowledgeProbe.fresh)
    $gateAppliedVisible = $false
    if ($null -ne $gatePayload) {
        $gateAppliedVisible = [bool]$gatePayload.gate_applied
    }
    $effectiveGateVisible = ($gateAppliedVisible -or [bool]$learningSnapshot.paper_open_visible -or [bool]$learningSnapshot.paper_close_visible -or [bool]$learningSnapshot.lesson_write_visible -or [bool]$learningSnapshot.knowledge_write_visible -or [bool]$learningSnapshot.paper_position_open)
    $blockerClass = Resolve-BlockerClass -Snapshot $learningSnapshot -GatePayload $gatePayload -DecisionProbe $decisionProbe -OnnxProbe $onnxProbe -GateProbe $gateProbe -LearningProbe $learningProbe -KnowledgeProbe $knowledgeProbe
    $blockerReason = if ($null -ne $learningSnapshot -and -not [string]::IsNullOrWhiteSpace([string]$learningSnapshot.last_reason_code)) { [string]$learningSnapshot.last_reason_code } else { "" }

    $items.Add([pscustomobject]@{
        symbol_alias = $symbol
        teacher_runtime_active = $teacherRuntimeActive
        signal_path_active = $signalPathActive
        teacher_gate_visible = $effectiveGateVisible
        fresh_full_lesson = $fullLessonFresh
        blocker_class = $blockerClass
        blocker_reason = $blockerReason
        local_training_mode = if ($null -ne $gatePayload) { [string]$gatePayload.local_training_mode } elseif ($null -ne $learningSnapshot) { [string]$learningSnapshot.local_training_mode } else { "" }
        gate_reason_code = if ($null -ne $gatePayload) { [string]$gatePayload.reason_code } else { "" }
        gate_applied = $gateAppliedVisible
        teacher_score = if ($null -ne $gatePayload) { [double]$gatePayload.teacher_score } elseif ($null -ne $learningSnapshot) { [double]$learningSnapshot.teacher_score } else { 0.0 }
        student_score = if ($null -ne $gatePayload) { [double]$gatePayload.student_score } elseif ($null -ne $learningSnapshot) { [double]$learningSnapshot.student_score } else { 0.0 }
        learning_snapshot = $learningSnapshotProbe
        learning_snapshot_payload = $learningSnapshot
        decision_log = $decisionProbe
        onnx_log = $onnxProbe
        learning_log = $learningProbe
        knowledge_log = $knowledgeProbe
        gate_state = $gateProbe
    }) | Out-Null
}

$itemsArray = @($items.ToArray())
$teacherRuntimeCount = @($itemsArray | Where-Object { $_.teacher_runtime_active }).Count
$signalPathActiveCount = @($itemsArray | Where-Object { $_.signal_path_active }).Count
$teacherGateVisibleCount = @($itemsArray | Where-Object { $_.teacher_gate_visible }).Count
$fullLessonCount = @($itemsArray | Where-Object { $_.fresh_full_lesson }).Count
$teacherRuntimeInactive = @($itemsArray | Where-Object { -not $_.teacher_runtime_active })
$preGateStalled = @($itemsArray | Where-Object { $_.blocker_class -in @("WAIT_NEW_BAR_STARVED","NO_SETUP_STARVED","TUNING_FREEZE_STARVED","SYMBOL_POLICY_STARVED","HEARTBEAT_ONLY","NO_SIGNAL_LOW_SCORE") })
$postGateOutcomeGap = @($itemsArray | Where-Object { $_.blocker_class -in @("GATE_VISIBLE_NO_OUTCOME","OUTCOME_WRITE_FAIL") })
$inactiveSymbols = @($teacherRuntimeInactive | ForEach-Object { [string]$_.symbol_alias })
$stalledSymbols = @($itemsArray | Where-Object { -not $_.fresh_full_lesson } | ForEach-Object { [string]$_.symbol_alias })

$verdict = if ($teacherRuntimeCount -eq @($Symbols).Count -and $fullLessonCount -eq @($Symbols).Count) {
    "GLOBAL_TEACHER_COHORT_WSZYSTKIE_UCZA_SIE"
}
elseif ($teacherRuntimeCount -eq @($Symbols).Count) {
    "GLOBAL_TEACHER_COHORT_WSZYSTKIE_OBSERWUJA"
}
elseif ($teacherRuntimeCount -gt 0) {
    "GLOBAL_TEACHER_COHORT_CZESCIOWO_AKTYWNY"
}
else {
    "GLOBAL_TEACHER_COHORT_BRAK_SWIEZEJ_AKTYWNOSCI"
}

$report = [ordered]@{
    schema_version = "2.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    threshold_seconds = $FreshThresholdSeconds
    verdict = $verdict
    summary = [ordered]@{
        target_symbol_count = @($Symbols).Count
        teacher_runtime_active_count = $teacherRuntimeCount
        signal_path_active_count = $signalPathActiveCount
        teacher_gate_visible_count = $teacherGateVisibleCount
        teacher_runtime_inactive_count = $teacherRuntimeInactive.Count
        fresh_full_lesson_count = $fullLessonCount
        pre_gate_stalled_count = $preGateStalled.Count
        post_gate_outcome_gap_count = $postGateOutcomeGap.Count
        learning_stalled_count = @($itemsArray | Where-Object { $_.blocker_class -ne "FULL_LEARNING_OK" }).Count
        symbols_without_teacher_runtime = $inactiveSymbols
        symbols_without_fresh_lessons = $stalledSymbols
    }
    items = $itemsArray
}

$jsonPath = Join-Path $ProjectRoot "EVIDENCE\OPS\global_teacher_cohort_activity_latest.json"
$mdPath = Join-Path $ProjectRoot "EVIDENCE\OPS\global_teacher_cohort_activity_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Global Teacher Cohort Activity")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- target_symbol_count: {0}" -f $report.summary.target_symbol_count))
$lines.Add(("- teacher_runtime_active_count: {0}" -f $report.summary.teacher_runtime_active_count))
$lines.Add(("- signal_path_active_count: {0}" -f $report.summary.signal_path_active_count))
$lines.Add(("- teacher_gate_visible_count: {0}" -f $report.summary.teacher_gate_visible_count))
$lines.Add(("- teacher_runtime_inactive_count: {0}" -f $report.summary.teacher_runtime_inactive_count))
$lines.Add(("- fresh_full_lesson_count: {0}" -f $report.summary.fresh_full_lesson_count))
$lines.Add(("- pre_gate_stalled_count: {0}" -f $report.summary.pre_gate_stalled_count))
$lines.Add(("- post_gate_outcome_gap_count: {0}" -f $report.summary.post_gate_outcome_gap_count))
$lines.Add("")
$lines.Add("## Symbols")
$lines.Add("")
foreach ($item in $itemsArray) {
    $lines.Add(("- {0}: runtime={1}, signal_path={2}, gate={3}, full_lesson={4}, class={5}, reason={6}, mode={7}" -f
        $item.symbol_alias,
        $item.teacher_runtime_active,
        $item.signal_path_active,
        $item.teacher_gate_visible,
        $item.fresh_full_lesson,
        $item.blocker_class,
        $item.blocker_reason,
        $item.local_training_mode))
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
