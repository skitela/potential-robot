param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$FreshThresholdSeconds = 1800,
    [int]$RecentDecisionSampleSize = 800
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
            last_write_ticks = $null
            path = $Path
        }
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)

    return [pscustomobject]@{
        exists = $true
        fresh = ($ageSeconds -le $ThresholdSeconds)
        age_seconds = $ageSeconds
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        last_write_ticks = [int64]$item.LastWriteTimeUtc.Ticks
        path = $Path
    }
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

function Convert-ToStorageToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value -replace '[^A-Za-z0-9_-]', '_').Trim('_'))
}

function Convert-UnixTsToLocalString {
    param([Nullable[long]]$UnixTs)

    if ($null -eq $UnixTs -or $UnixTs -le 0) {
        return $null
    }

    return ([DateTimeOffset]::FromUnixTimeSeconds([long]$UnixTs).ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss"))
}

function Get-RecentDecisionStageStats {
    param(
        [string]$Path,
        [int]$TailCount,
        [int]$ThresholdSeconds
    )

    $stats = [ordered]@{
        total_rows = 0
        paper_close_count = 0
        fresh_paper_close_count = 0
        execution_truth_close_ok_count = 0
        fresh_execution_truth_close_ok_count = 0
        lesson_write_ok_count = 0
        fresh_lesson_write_ok_count = 0
        knowledge_write_ok_count = 0
        fresh_knowledge_write_ok_count = 0
        last_event_ts = $null
        last_event_local = $null
        last_phase = ""
        last_action = ""
        last_reason = ""
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$stats
    }

    $lines = @(Get-Content -LiteralPath $Path -Tail $TailCount -Encoding UTF8)
    if ($lines.Count -eq 0) {
        return [pscustomobject]$stats
    }

    $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $parts = $line -split "`t"
        if ($parts.Count -lt 5) {
            continue
        }

        $stats.total_rows++
        $eventTs = 0L
        [void][long]::TryParse([string]$parts[0], [ref]$eventTs)
        $phase = [string]$parts[2]
        $action = [string]$parts[3]
        $reason = [string]$parts[4]
        $isFresh = ($eventTs -gt 0 -and ($nowUnix - $eventTs) -le $ThresholdSeconds)

        if ($eventTs -gt 0) {
            $stats.last_event_ts = $eventTs
            $stats.last_event_local = Convert-UnixTsToLocalString -UnixTs $eventTs
        }
        $stats.last_phase = $phase
        $stats.last_action = $action
        $stats.last_reason = $reason

        if ($phase -eq "PAPER_CLOSE" -and $action -in @("OK","LOSS")) {
            $stats.paper_close_count++
            if ($isFresh) {
                $stats.fresh_paper_close_count++
            }
        }
        elseif ($phase -eq "EXECUTION_TRUTH_CLOSE" -and $action -eq "OK") {
            $stats.execution_truth_close_ok_count++
            if ($isFresh) {
                $stats.fresh_execution_truth_close_ok_count++
            }
        }
        elseif ($phase -eq "LESSON_WRITE" -and $action -eq "OK") {
            $stats.lesson_write_ok_count++
            if ($isFresh) {
                $stats.fresh_lesson_write_ok_count++
            }
        }
        elseif ($phase -eq "KNOWLEDGE_WRITE" -and $action -eq "OK") {
            $stats.knowledge_write_ok_count++
            if ($isFresh) {
                $stats.fresh_knowledge_write_ok_count++
            }
        }
    }

    return [pscustomobject]$stats
}

$jsonPath = Join-Path $OutputRoot "first_wave_lesson_closure_latest.json"
$mdPath = Join-Path $OutputRoot "first_wave_lesson_closure_latest.md"
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$plan = Read-JsonFile -Path $UniversePlanPath
if ($null -eq $plan) {
    throw "Universe plan missing: $UniversePlanPath"
}

$selectedSymbols = @($plan.paper_live_first_wave | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$logsRoot = Join-Path $CommonRoot "logs"
$executionSpoolRoot = Join-Path $CommonRoot "spool\execution_truth"
$results = New-Object System.Collections.Generic.List[object]

foreach ($symbol in $selectedSymbols) {
    $token = Convert-ToStorageToken -Value $symbol
    $symbolLogsRoot = Join-Path $logsRoot $symbol
    $decisionPath = Join-Path $symbolLogsRoot "decision_events.csv"
    $learningPath = Join-Path $symbolLogsRoot "learning_observations_v2.csv"
    $knowledgePath = Join-Path $symbolLogsRoot "broker_net_ledger_runtime.csv"
    $executionTruthPath = Join-Path $executionSpoolRoot ("execution_truth_{0}.csv" -f $token)

    $decisionState = Get-FileState -Path $decisionPath -ThresholdSeconds $FreshThresholdSeconds
    $learningState = Get-FileState -Path $learningPath -ThresholdSeconds $FreshThresholdSeconds
    $knowledgeState = Get-FileState -Path $knowledgePath -ThresholdSeconds $FreshThresholdSeconds
    $executionTruthState = Get-FileState -Path $executionTruthPath -ThresholdSeconds $FreshThresholdSeconds

    $decisionStats = Get-RecentDecisionStageStats -Path $decisionPath -TailCount $RecentDecisionSampleSize -ThresholdSeconds $FreshThresholdSeconds
    $learningRows = Get-CsvDataRowCount -Path $learningPath
    $knowledgeRows = Get-CsvDataRowCount -Path $knowledgePath
    $executionTruthRows = Get-CsvDataRowCount -Path $executionTruthPath

    $freshChainReady = (
        $decisionStats.fresh_execution_truth_close_ok_count -gt 0 -and
        $decisionStats.fresh_lesson_write_ok_count -gt 0 -and
        $decisionStats.fresh_knowledge_write_ok_count -gt 0 -and
        $learningState.fresh -and
        $knowledgeState.fresh
    )
    $historicalChainReady = (
        $decisionStats.execution_truth_close_ok_count -gt 0 -and
        $decisionStats.lesson_write_ok_count -gt 0 -and
        $decisionStats.knowledge_write_ok_count -gt 0 -and
        $learningRows -gt 0 -and
        $knowledgeRows -gt 0 -and
        $executionTruthRows -gt 0
    )

    $state = if ($freshChainReady) {
        "SWIEZE_DOMKNIECIE_GOTOWE"
    }
    elseif ($historicalChainReady) {
        "HISTORYCZNE_DOMKNIECIE_GOTOWE"
    }
    elseif ($decisionStats.fresh_paper_close_count -gt 0) {
        "SWIEZE_ZAMKNIECIE_BEZ_PELNEGO_LANCUCHA"
    }
    elseif ($decisionState.fresh -or $learningState.fresh -or $knowledgeState.fresh) {
        "AKTYWNE_BEZ_SWIEZEGO_DOMKNIECIA"
    }
    else {
        "BRAK_DOMKNIECIA"
    }

    $results.Add([pscustomobject]@{
        symbol_alias = $symbol
        state = $state
        fresh_chain_ready = $freshChainReady
        historical_chain_ready = $historicalChainReady
        decision_log = $decisionState
        learning_log = $learningState
        knowledge_log = $knowledgeState
        execution_truth_log = $executionTruthState
        learning_rows = $learningRows
        knowledge_rows = $knowledgeRows
        execution_truth_rows = $executionTruthRows
        recent = $decisionStats
    }) | Out-Null
}

$resultsArray = @($results.ToArray())
$freshChainReadyCount = @($resultsArray | Where-Object { $_.fresh_chain_ready }).Count
$historicalChainReadyCount = @($resultsArray | Where-Object { $_.historical_chain_ready }).Count
$freshExecutionTruthCloseSymbolCount = @($resultsArray | Where-Object { $_.recent.fresh_execution_truth_close_ok_count -gt 0 }).Count
$freshLessonWriteSymbolCount = @($resultsArray | Where-Object { $_.recent.fresh_lesson_write_ok_count -gt 0 }).Count
$freshKnowledgeWriteSymbolCount = @($resultsArray | Where-Object { $_.recent.fresh_knowledge_write_ok_count -gt 0 }).Count
$missingChainCount = @($resultsArray | Where-Object { $_.state -eq "BRAK_DOMKNIECIA" }).Count
$partialGapCount = @($resultsArray | Where-Object { $_.state -eq "SWIEZE_ZAMKNIECIE_BEZ_PELNEGO_LANCUCHA" }).Count

$verdict = if ($freshChainReadyCount -eq $selectedSymbols.Count -and $selectedSymbols.Count -gt 0) {
    "PIERWSZA_FALA_DOMYKA_LEKCJE"
}
elseif ($historicalChainReadyCount -eq $selectedSymbols.Count -and $selectedSymbols.Count -gt 0) {
    "PIERWSZA_FALA_HISTORYCZNIE_DOMYKA_LEKCJE"
}
elseif (($freshChainReadyCount + $historicalChainReadyCount) -gt 0) {
    "PIERWSZA_FALA_CZESCIOWO_DOMYKA_LEKCJE"
}
else {
    "PIERWSZA_FALA_BEZ_DOMKNIECIA_LEKCJI"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbol_scope = "paper_live_first_wave"
    freshness_threshold_seconds = $FreshThresholdSeconds
    verdict = $verdict
    summary = [ordered]@{
        target_symbol_count = $selectedSymbols.Count
        fresh_chain_ready_count = $freshChainReadyCount
        historical_chain_ready_count = $historicalChainReadyCount
        fresh_execution_truth_close_symbol_count = $freshExecutionTruthCloseSymbolCount
        fresh_lesson_write_symbol_count = $freshLessonWriteSymbolCount
        fresh_knowledge_write_symbol_count = $freshKnowledgeWriteSymbolCount
        missing_chain_count = $missingChainCount
        partial_gap_count = $partialGapCount
    }
    results = @($resultsArray)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# First Wave Lesson Closure Audit")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- target_symbol_count: {0}" -f $report.summary.target_symbol_count))
$lines.Add(("- fresh_chain_ready_count: {0}" -f $report.summary.fresh_chain_ready_count))
$lines.Add(("- historical_chain_ready_count: {0}" -f $report.summary.historical_chain_ready_count))
$lines.Add(("- fresh_execution_truth_close_symbol_count: {0}" -f $report.summary.fresh_execution_truth_close_symbol_count))
$lines.Add(("- fresh_lesson_write_symbol_count: {0}" -f $report.summary.fresh_lesson_write_symbol_count))
$lines.Add(("- fresh_knowledge_write_symbol_count: {0}" -f $report.summary.fresh_knowledge_write_symbol_count))
$lines.Add(("- missing_chain_count: {0}" -f $report.summary.missing_chain_count))
$lines.Add(("- partial_gap_count: {0}" -f $report.summary.partial_gap_count))
$lines.Add("")
$lines.Add("## Symbols")
$lines.Add("")
foreach ($row in $resultsArray) {
    $lines.Add(("### {0}" -f $row.symbol_alias))
    $lines.Add(("- state: {0}" -f $row.state))
    $lines.Add(("- fresh_chain_ready: {0}" -f ([string]$row.fresh_chain_ready).ToLowerInvariant()))
    $lines.Add(("- historical_chain_ready: {0}" -f ([string]$row.historical_chain_ready).ToLowerInvariant()))
    $lines.Add(("- fresh_execution_truth_close_ok_count: {0}" -f $row.recent.fresh_execution_truth_close_ok_count))
    $lines.Add(("- fresh_lesson_write_ok_count: {0}" -f $row.recent.fresh_lesson_write_ok_count))
    $lines.Add(("- fresh_knowledge_write_ok_count: {0}" -f $row.recent.fresh_knowledge_write_ok_count))
    $lines.Add(("- learning_rows: {0}" -f $row.learning_rows))
    $lines.Add(("- knowledge_rows: {0}" -f $row.knowledge_rows))
    $lines.Add(("- execution_truth_rows: {0}" -f $row.execution_truth_rows))
    $lines.Add("")
}

$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8
