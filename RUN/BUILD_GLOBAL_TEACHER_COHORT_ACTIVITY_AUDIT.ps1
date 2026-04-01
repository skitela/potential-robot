param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$FreshThresholdSeconds = 900,
    [string[]]$Symbols = @("DE30","GOLD","SILVER","USDJPY","USDCHF","COPPER-US","EURAUD","EURUSD","GBPUSD")
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

    $teacherRuntimeActive = ($decisionProbe.fresh -and $onnxProbe.fresh)
    $fullLessonFresh = ($learningProbe.fresh -and $knowledgeProbe.fresh)

    $items.Add([pscustomobject]@{
        symbol_alias = $symbol
        teacher_runtime_active = $teacherRuntimeActive
        teacher_gate_visible = $gateProbe.fresh
        fresh_full_lesson = $fullLessonFresh
        local_training_mode = if ($null -ne $gatePayload) { [string]$gatePayload.local_training_mode } else { "" }
        gate_reason_code = if ($null -ne $gatePayload) { [string]$gatePayload.reason_code } else { "" }
        teacher_score = if ($null -ne $gatePayload) { [double]$gatePayload.teacher_score } else { 0.0 }
        student_score = if ($null -ne $gatePayload) { [double]$gatePayload.student_score } else { 0.0 }
        decision_log = $decisionProbe
        onnx_log = $onnxProbe
        learning_log = $learningProbe
        knowledge_log = $knowledgeProbe
        gate_state = $gateProbe
    }) | Out-Null
}

$itemsArray = @($items.ToArray())
$teacherRuntimeCount = @($itemsArray | Where-Object { $_.teacher_runtime_active }).Count
$teacherGateVisibleCount = @($itemsArray | Where-Object { $_.teacher_gate_visible }).Count
$fullLessonCount = @($itemsArray | Where-Object { $_.fresh_full_lesson }).Count
$teacherRuntimeInactive = @($itemsArray | Where-Object { -not $_.teacher_runtime_active })
$stalledLearning = @($itemsArray | Where-Object { $_.decision_log.fresh -and $_.onnx_log.fresh -and -not $_.fresh_full_lesson })
$inactiveSymbols = @($teacherRuntimeInactive | ForEach-Object { [string]$_.symbol_alias })
$stalledSymbols = @($stalledLearning | ForEach-Object { [string]$_.symbol_alias })

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
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    threshold_seconds = $FreshThresholdSeconds
    verdict = $verdict
    summary = [ordered]@{
        target_symbol_count = @($Symbols).Count
        teacher_runtime_active_count = $teacherRuntimeCount
        teacher_gate_visible_count = $teacherGateVisibleCount
        teacher_runtime_inactive_count = $teacherRuntimeInactive.Count
        fresh_full_lesson_count = $fullLessonCount
        learning_stalled_count = $stalledLearning.Count
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
$lines.Add(("- teacher_gate_visible_count: {0}" -f $report.summary.teacher_gate_visible_count))
$lines.Add(("- teacher_runtime_inactive_count: {0}" -f $report.summary.teacher_runtime_inactive_count))
$lines.Add(("- fresh_full_lesson_count: {0}" -f $report.summary.fresh_full_lesson_count))
$lines.Add(("- learning_stalled_count: {0}" -f $report.summary.learning_stalled_count))
$lines.Add(("- symbols_without_teacher_runtime: {0}" -f $(if ($report.summary.symbols_without_teacher_runtime.Count -gt 0) { ($report.summary.symbols_without_teacher_runtime -join ", ") } else { "BRAK" })))
$lines.Add(("- symbols_without_fresh_lessons: {0}" -f $(if ($report.summary.symbols_without_fresh_lessons.Count -gt 0) { ($report.summary.symbols_without_fresh_lessons -join ", ") } else { "BRAK" })))
$lines.Add("")
$lines.Add("## Symbols")
$lines.Add("")
foreach ($item in $itemsArray) {
    $lines.Add(("- {0}: teacher_runtime_active={1}, teacher_gate_visible={2}, fresh_full_lesson={3}, mode={4}, reason={5}, teacher_score={6}, student_score={7}" -f
        $item.symbol_alias,
        $item.teacher_runtime_active,
        $item.teacher_gate_visible,
        $item.fresh_full_lesson,
        $item.local_training_mode,
        $item.gate_reason_code,
        ([math]::Round([double]$item.teacher_score, 6)),
        ([math]::Round([double]$item.student_score, 6))))
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
