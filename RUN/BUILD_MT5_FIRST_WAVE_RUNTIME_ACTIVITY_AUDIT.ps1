param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$FreshThresholdSeconds = 1800,
    [int]$RecentDecisionSampleSize = 400
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop)
}

function Get-SafeObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }

    return $Default
}

function Get-FileState {
    param(
        [string]$Path,
        [int]$ThresholdSeconds
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            exists = $false
            fresh = $false
            age_seconds = $null
            last_write_local = $null
            path = $Path
        }
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)

    return [pscustomobject]@{
        exists = $true
        fresh = ($ageSeconds -le $ThresholdSeconds)
        age_seconds = $ageSeconds
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        path = $Path
    }
}

function Convert-ToStorageToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value -replace '[^A-Za-z0-9_-]', '_').Trim('_'))
}

function Get-CsvDataRowCount {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    $lineCount = @(Get-Content -LiteralPath $Path -Encoding UTF8).Count
    if ($lineCount -le 1) {
        return 0
    }

    return ($lineCount - 1)
}

function Get-RecentDecisionStats {
    param(
        [string]$Path,
        [int]$TailCount
    )

    $empty = [ordered]@{
        total_rows = 0
        paper_open_ok_count = 0
        exec_precheck_ready_count = 0
        exec_precheck_block_count = 0
        score_below_trigger_count = 0
        outside_trade_window_bypass_count = 0
        tuning_family_freeze_count = 0
        tuning_fleet_freeze_count = 0
        last_phase = ""
        last_action = ""
        last_reason = ""
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$empty
    }

    $lines = @(Get-Content -LiteralPath $Path -Tail $TailCount -Encoding UTF8)
    if ($lines.Count -eq 0) {
        return [pscustomobject]$empty
    }

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t"
        if ($parts.Count -lt 5) {
            continue
        }

        $empty.total_rows++
        $phase = [string]$parts[2]
        $action = [string]$parts[3]
        $reason = [string]$parts[4]

        $empty.last_phase = $phase
        $empty.last_action = $action
        $empty.last_reason = $reason

        if ($phase -eq "PAPER_OPEN" -and $action -eq "OK") {
            $empty.paper_open_ok_count++
        }
        elseif ($phase -eq "EXEC_PRECHECK" -and $action -eq "READY") {
            $empty.exec_precheck_ready_count++
        }
        elseif ($phase -eq "EXEC_PRECHECK" -and $action -eq "BLOCK") {
            $empty.exec_precheck_block_count++
        }
        elseif ($phase -eq "SCAN" -and $action -eq "SKIP" -and $reason -eq "SCORE_BELOW_TRIGGER") {
            $empty.score_below_trigger_count++
        }
        elseif ($phase -eq "MARKET" -and $action -eq "BYPASS" -and $reason -eq "PAPER_IGNORE_OUTSIDE_TRADE_WINDOW") {
            $empty.outside_trade_window_bypass_count++
        }
        elseif ($phase -eq "TUNING_FAMILY" -and $reason -eq "FREEZE_FAMILY") {
            $empty.tuning_family_freeze_count++
        }
        elseif ($phase -eq "TUNING_FLEET" -and ($reason -eq "FREEZE_FLEET" -or $reason -eq "DEFENSIVE_FLEET")) {
            $empty.tuning_fleet_freeze_count++
        }
    }

    return [pscustomobject]$empty
}

$jsonPath = Join-Path $OutputRoot "mt5_first_wave_runtime_activity_latest.json"
$mdPath = Join-Path $OutputRoot "mt5_first_wave_runtime_activity_latest.md"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$plan = Read-JsonFile -Path $UniversePlanPath
if ($null -eq $plan) {
    throw "Universe plan missing: $UniversePlanPath"
}

$selectedSymbols = @($plan.paper_live_first_wave | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$logsRoot = Join-Path $CommonRoot "logs"
$stateRoot = Join-Path $CommonRoot "state"
$pretradeSpoolRoot = Join-Path $CommonRoot "spool\pretrade_truth"
$executionSpoolRoot = Join-Path $CommonRoot "spool\execution_truth"

$results = New-Object System.Collections.Generic.List[object]

foreach ($symbol in $selectedSymbols) {
    $symbolUpper = $symbol.ToUpperInvariant()
    $token = Convert-ToStorageToken -Value $symbol
    $decisionPath = Join-Path $logsRoot "$symbol\decision_events.csv"
    $candidatePath = Join-Path $logsRoot "$symbol\candidate_signals.csv"
    $onnxPath = Join-Path $logsRoot "$symbol\onnx_observations.csv"
    $runtimeStatusPath = Join-Path $stateRoot "$symbol\runtime_status.json"
    $executionSummaryPath = Join-Path $stateRoot "$symbol\execution_summary.json"
    $pretradeSpoolPath = Join-Path $pretradeSpoolRoot ("pretrade_truth_{0}.csv" -f $token)
    $executionSpoolPath = Join-Path $executionSpoolRoot ("execution_truth_{0}.csv" -f $token)

    $decisionState = Get-FileState -Path $decisionPath -ThresholdSeconds $FreshThresholdSeconds
    $candidateState = Get-FileState -Path $candidatePath -ThresholdSeconds $FreshThresholdSeconds
    $onnxState = Get-FileState -Path $onnxPath -ThresholdSeconds $FreshThresholdSeconds
    $runtimeStatusState = Get-FileState -Path $runtimeStatusPath -ThresholdSeconds $FreshThresholdSeconds
    $executionSummaryState = Get-FileState -Path $executionSummaryPath -ThresholdSeconds $FreshThresholdSeconds
    $recentDecisionStats = Get-RecentDecisionStats -Path $decisionPath -TailCount $RecentDecisionSampleSize

    $runtimeStatus = Read-JsonFile -Path $runtimeStatusPath
    $executionSummary = Read-JsonFile -Path $executionSummaryPath

    $pretradeRows = Get-CsvDataRowCount -Path $pretradeSpoolPath
    $executionRows = Get-CsvDataRowCount -Path $executionSpoolPath
    $truthLive = ($pretradeRows -gt 0 -or $executionRows -gt 0)
    $liveLogFresh = ($decisionState.fresh -or $onnxState.fresh -or $runtimeStatusState.fresh -or $executionSummaryState.fresh)
    $recentPaperOpen = ($recentDecisionStats.paper_open_ok_count -gt 0)
    $recentPrecheckReady = ($recentDecisionStats.exec_precheck_ready_count -gt 0)
    $recentPrecheckBlocked = ($recentDecisionStats.exec_precheck_block_count -gt 0)
    $recentScoreBelow = ($recentDecisionStats.score_below_trigger_count -gt 0)
    $recentOutsideWindow = ($recentDecisionStats.outside_trade_window_bypass_count -gt 0)
    $recentFreeze = (($recentDecisionStats.tuning_family_freeze_count + $recentDecisionStats.tuning_fleet_freeze_count) -gt 0)

    $runtimeMode = [string](Get-SafeObjectValue -Object $runtimeStatus -PropertyName "runtime_mode" -Default "")
    $paperRights = [bool](Get-SafeObjectValue -Object $runtimeStatus -PropertyName "paper_rights" -Default $false)
    $observationRights = [bool](Get-SafeObjectValue -Object $runtimeStatus -PropertyName "observation_rights" -Default $false)
    $reasonCode = [string](Get-SafeObjectValue -Object $executionSummary -PropertyName "reason_code" -Default (Get-SafeObjectValue -Object $runtimeStatus -PropertyName "reason_code" -Default ""))
    $spreadPoints = [double](Get-SafeObjectValue -Object $executionSummary -PropertyName "spread_points" -Default 0.0)

    $activityState = if ($truthLive) {
        "ZYWA_PRAWDA_AKTYWNA"
    }
    elseif ($recentPaperOpen) {
        "PAPER_OTWARCIA_BEZ_ZAPISU_PRAWDA"
    }
    elseif ($recentPrecheckReady) {
        "DOCHODZI_DO_SPRAWDZENIA_PRZED_WYSLANIEM"
    }
    elseif ($recentOutsideWindow) {
        "POZA_OKNEM_HANDLU"
    }
    elseif ($recentFreeze) {
        "ZAMROZENIE_STROJENIA"
    }
    elseif ($recentScoreBelow -and $onnxState.fresh) {
        "ZA_SLABY_SYGNAL"
    }
    elseif ($liveLogFresh) {
        "AKTYWNY_BEZ_WEJSCIA"
    }
    else {
        "MARTWY_DZIENNIK"
    }

    $results.Add([pscustomobject]@{
        symbol_alias = $symbolUpper
        runtime_mode = $runtimeMode
        paper_rights = $paperRights
        observation_rights = $observationRights
        reason_code = $reasonCode
        spread_points = [math]::Round($spreadPoints, 2)
        activity_state = $activityState
        live_log_fresh = $liveLogFresh
        truth_live = $truthLive
        decision_log = $decisionState
        candidate_log = $candidateState
        onnx_log = $onnxState
        runtime_status = $runtimeStatusState
        execution_summary = $executionSummaryState
        pretrade_truth_rows = $pretradeRows
        execution_truth_rows = $executionRows
        recent = [pscustomobject]@{
            decision_rows = $recentDecisionStats.total_rows
            paper_open_ok_count = $recentDecisionStats.paper_open_ok_count
            exec_precheck_ready_count = $recentDecisionStats.exec_precheck_ready_count
            exec_precheck_block_count = $recentDecisionStats.exec_precheck_block_count
            score_below_trigger_count = $recentDecisionStats.score_below_trigger_count
            outside_trade_window_bypass_count = $recentDecisionStats.outside_trade_window_bypass_count
            tuning_family_freeze_count = $recentDecisionStats.tuning_family_freeze_count
            tuning_fleet_freeze_count = $recentDecisionStats.tuning_fleet_freeze_count
            last_phase = $recentDecisionStats.last_phase
            last_action = $recentDecisionStats.last_action
            last_reason = $recentDecisionStats.last_reason
        }
    }) | Out-Null
}

$resultArray = $results.ToArray()
$liveLogFreshCount = @($resultArray | Where-Object { $_.live_log_fresh }).Count
$truthLiveCount = @($resultArray | Where-Object { $_.truth_live }).Count
$outsideWindowCount = @($resultArray | Where-Object { $_.activity_state -eq "POZA_OKNEM_HANDLU" }).Count
$freezeCount = @($resultArray | Where-Object { $_.activity_state -eq "ZAMROZENIE_STROJENIA" }).Count
$weakSignalCount = @($resultArray | Where-Object { $_.activity_state -eq "ZA_SLABY_SYGNAL" }).Count
$deadLogCount = @($resultArray | Where-Object { $_.activity_state -eq "MARTWY_DZIENNIK" }).Count
$recentPaperOpenCount = 0
foreach ($item in $resultArray) {
    $recentPaperOpenCount += [int](0 + $item.recent.paper_open_ok_count)
}

$verdict = if ($truthLiveCount -eq $selectedSymbols.Count -and $selectedSymbols.Count -gt 0) {
    "PIERWSZA_FALA_AKTYWNA_Z_PRAWDA"
}
elseif ($liveLogFreshCount -gt 0) {
    "PIERWSZA_FALA_AKTYWNA_BEZ_PRAWDY"
}
else {
    "PIERWSZA_FALA_MARTWA"
}

$report = [pscustomobject]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbol_scope = "paper_live_first_wave"
    freshness_threshold_seconds = $FreshThresholdSeconds
    verdict = $verdict
    summary = [pscustomobject]@{
        target_symbol_count = $selectedSymbols.Count
        live_log_fresh_count = $liveLogFreshCount
        truth_live_symbol_count = $truthLiveCount
        outside_trade_window_count = $outsideWindowCount
        tuning_freeze_count = $freezeCount
        weak_signal_count = $weakSignalCount
        dead_log_count = $deadLogCount
        recent_paper_open_count = [int](0 + $recentPaperOpenCount)
        total_pretrade_truth_rows = [int](($resultArray | Measure-Object -Property pretrade_truth_rows -Sum).Sum)
        total_execution_truth_rows = [int](($resultArray | Measure-Object -Property execution_truth_rows -Sum).Sum)
    }
    results = $resultArray
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Audyt Aktywnosci Pierwszej Fali")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- target_symbol_count: {0}" -f $report.summary.target_symbol_count))
$lines.Add(("- live_log_fresh_count: {0}" -f $report.summary.live_log_fresh_count))
$lines.Add(("- truth_live_symbol_count: {0}" -f $report.summary.truth_live_symbol_count))
$lines.Add(("- outside_trade_window_count: {0}" -f $report.summary.outside_trade_window_count))
$lines.Add(("- tuning_freeze_count: {0}" -f $report.summary.tuning_freeze_count))
$lines.Add(("- weak_signal_count: {0}" -f $report.summary.weak_signal_count))
$lines.Add(("- dead_log_count: {0}" -f $report.summary.dead_log_count))
$lines.Add(("- recent_paper_open_count: {0}" -f $report.summary.recent_paper_open_count))
$lines.Add(("- total_pretrade_truth_rows: {0}" -f $report.summary.total_pretrade_truth_rows))
$lines.Add(("- total_execution_truth_rows: {0}" -f $report.summary.total_execution_truth_rows))
$lines.Add("")

foreach ($item in $resultArray) {
    $lines.Add(("## {0}" -f $item.symbol_alias))
    $lines.Add("")
    $lines.Add(("- activity_state: {0}" -f $item.activity_state))
    $lines.Add(("- runtime_mode: {0}" -f $item.runtime_mode))
    $lines.Add(("- paper_rights: {0}" -f ([string]$item.paper_rights).ToLowerInvariant()))
    $lines.Add(("- observation_rights: {0}" -f ([string]$item.observation_rights).ToLowerInvariant()))
    $lines.Add(("- reason_code: {0}" -f $item.reason_code))
    $lines.Add(("- spread_points: {0}" -f $item.spread_points))
    $lines.Add(("- live_log_fresh: {0}" -f ([string]$item.live_log_fresh).ToLowerInvariant()))
    $lines.Add(("- truth_live: {0}" -f ([string]$item.truth_live).ToLowerInvariant()))
    $lines.Add(("- decision_log_last_write_local: {0}" -f $item.decision_log.last_write_local))
    $lines.Add(("- onnx_log_last_write_local: {0}" -f $item.onnx_log.last_write_local))
    $lines.Add(("- runtime_status_last_write_local: {0}" -f $item.runtime_status.last_write_local))
    $lines.Add(("- execution_summary_last_write_local: {0}" -f $item.execution_summary.last_write_local))
    $lines.Add(("- pretrade_truth_rows: {0}" -f $item.pretrade_truth_rows))
    $lines.Add(("- execution_truth_rows: {0}" -f $item.execution_truth_rows))
    $lines.Add(("- recent_paper_open_ok_count: {0}" -f $item.recent.paper_open_ok_count))
    $lines.Add(("- recent_exec_precheck_ready_count: {0}" -f $item.recent.exec_precheck_ready_count))
    $lines.Add(("- recent_exec_precheck_block_count: {0}" -f $item.recent.exec_precheck_block_count))
    $lines.Add(("- recent_score_below_trigger_count: {0}" -f $item.recent.score_below_trigger_count))
    $lines.Add(("- recent_outside_trade_window_bypass_count: {0}" -f $item.recent.outside_trade_window_bypass_count))
    $lines.Add(("- recent_tuning_family_freeze_count: {0}" -f $item.recent.tuning_family_freeze_count))
    $lines.Add(("- recent_tuning_fleet_freeze_count: {0}" -f $item.recent.tuning_fleet_freeze_count))
    $lines.Add(("- recent_last_phase: {0}" -f $item.recent.last_phase))
    $lines.Add(("- recent_last_action: {0}" -f $item.recent.last_action))
    $lines.Add(("- recent_last_reason: {0}" -f $item.recent.last_reason))
    $lines.Add("")
}

$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 -Compress
