Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("=== LOCAL OPERATOR SUMMARY ===")
$lines.Add("")

$secondaryMt5LogPath = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\logs\20260319.log"
$mt5TesterStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_tester_status_latest.json"
$mt5RetestQueuePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_retest_queue_latest.json"

$fxProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @("terminal64", "metatester64", "qdmcli", "python") })
if ($fxProcesses.Count -gt 0) {
    $lines.Add("Active lab processes:")
    foreach ($proc in $fxProcesses | Sort-Object ProcessName, Id) {
        $lines.Add(("- {0} #{1} priority={2} ram_mb={3}" -f $proc.ProcessName, $proc.Id, $proc.PriorityClass, [math]::Round($proc.WorkingSet64 / 1MB, 1)))
    }
    $lines.Add("")
}

$mt5TesterStatus = $null
if (Test-Path -LiteralPath $mt5TesterStatusPath) {
    $mt5TesterStatus = Get-Content -LiteralPath $mt5TesterStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$currentTesterSymbol = $null
$currentTesterState = $null
$currentTesterProgressPct = $null
$passLine = @()
$progressLine = @()

if ($null -ne $mt5TesterStatus) {
    $currentTesterSymbol = [string]$mt5TesterStatus.current_symbol
    $currentTesterState = [string]$mt5TesterStatus.state
    $currentTesterProgressPct = $mt5TesterStatus.latest_progress_pct
}

if (Test-Path -LiteralPath $secondaryMt5LogPath) {
    $testerTail = @(Get-Content -LiteralPath $secondaryMt5LogPath -Tail 80 -ErrorAction SilentlyContinue)
    $launchLine = @(
        $testerTail |
            Where-Object { $_ -match 'launched with .+\\strategy_tester\\([a-z0-9_]+)_strategy_tester_[0-9_]+\.ini' } |
            Select-Object -Last 1
    )
    $progressLine = @(
        $testerTail |
            Where-Object { $_ -match 'AutoTesting\s+processing\s+[0-9]+\s*%' } |
            Select-Object -Last 1
    )
    $passLine = @(
        $testerTail |
            Where-Object { $_ -match 'last test passed with result' } |
            Select-Object -Last 1
    )

    if ([string]::IsNullOrWhiteSpace($currentTesterSymbol) -and $launchLine.Count -gt 0) {
        $currentTesterSymbol = ([regex]::Match($launchLine[0], 'launched with .+\\strategy_tester\\([a-z0-9_]+)_strategy_tester_[0-9_]+\.ini')).Groups[1].Value.ToUpperInvariant()
    }
}

if (-not [string]::IsNullOrWhiteSpace($currentTesterSymbol) -or
    -not [string]::IsNullOrWhiteSpace($currentTesterState) -or
    $null -ne $currentTesterProgressPct -or
    $progressLine.Count -gt 0 -or
    $passLine.Count -gt 0) {
        $lines.Add("Secondary MT5 tester:")
        if (-not [string]::IsNullOrWhiteSpace($currentTesterState)) {
            $lines.Add(("- state: {0}" -f $currentTesterState))
        }
        if (-not [string]::IsNullOrWhiteSpace($currentTesterSymbol)) {
            $lines.Add(("- current_symbol: {0}" -f $currentTesterSymbol))
        }
        if ($null -ne $currentTesterProgressPct) {
            $lines.Add(("- latest_progress_pct: {0}" -f $currentTesterProgressPct))
        }
        if ($progressLine.Count -gt 0) {
            $lines.Add(("- latest_progress: {0}" -f $progressLine[0].Trim()))
        }
        if ($passLine.Count -gt 0) {
            $lines.Add(("- latest_result: {0}" -f $passLine[0].Trim()))
        }
        $lines.Add("")
}

$metricsPath = "C:\TRADING_DATA\RESEARCH\models\paper_gate_acceptor\paper_gate_acceptor_metrics_latest.json"
if (Test-Path -LiteralPath $metricsPath) {
    $metrics = Get-Content -LiteralPath $metricsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $metricValues = if ($metrics.PSObject.Properties.Name -contains 'metrics') { $metrics.metrics } else { $metrics }
    $lines.Add("Latest ML metrics:")
    $lines.Add(("- accuracy={0} balanced_accuracy={1} roc_auc={2}" -f
        ([math]::Round([double]$metricValues.accuracy, 4)),
        ([math]::Round([double]$metricValues.balanced_accuracy, 4)),
        ([math]::Round([double]$metricValues.roc_auc, 4))))
    $lines.Add("")
}

$priorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json"
if (Test-Path -LiteralPath $priorityPath) {
    $priority = Get-Content -LiteralPath $priorityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $priorityItems = @($priority.ranked_instruments)
    if ($priorityItems.Count -gt 0) {
        $lines.Add("Current weakest-first tuning queue:")
        foreach ($item in $priorityItems | Select-Object -First 6) {
            $lines.Add(("- #{0} {1}: score={2} trust={3} cost={4} sample={5} live_net_24h={6} action={7}" -f
                $item.rank,
                $item.symbol_alias,
                $item.priority_score,
                $item.trust_state,
                $item.cost_state,
                $item.learning_sample_count,
                $item.live_net_24h,
                $item.recommended_action))
        }
        $lines.Add("")
    }
}

$mlHintsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\ml_tuning_hints_latest.json"
if (Test-Path -LiteralPath $mlHintsPath) {
    $mlHints = Get-Content -LiteralPath $mlHintsPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $hintItems = @($mlHints.items)
    if ($hintItems.Count -gt 0) {
        $lines.Add("Latest ML tuning hints:")
        foreach ($item in $hintItems | Select-Object -First 4) {
            $firstHint = if (@($item.hints).Count -gt 0) { [string]$item.hints[0] } else { "brak" }
            $lines.Add(("- #{0} {1}: ml_risk_score={2} hint={3}" -f
                $item.rank,
                $item.symbol_alias,
                $item.ml_risk_score,
                $firstHint))
        }
        $lines.Add("")
    }
}

$qdmProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_weakest_profile_latest.json"
if (Test-Path -LiteralPath $qdmProfilePath) {
    $qdmProfile = Get-Content -LiteralPath $qdmProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $qdmItems = @($qdmProfile.included)
    if ($qdmItems.Count -gt 0) {
        $lines.Add("Current QDM weakest data profile:")
        foreach ($item in $qdmItems | Select-Object -First 4) {
            $lines.Add(("- #{0} {1}: qdm_symbol={2} datasource={3} export={4}" -f
                $item.rank,
                $item.symbol_alias,
                $item.qdm_symbol,
                $item.datasource,
                $item.mt5_export_name))
        }
        $lines.Add("")
    }
}

$mt5Queue = $null
if (Test-Path -LiteralPath $mt5RetestQueuePath) {
    $mt5Queue = Get-Content -LiteralPath $mt5RetestQueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $queueAgeSeconds = [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $mt5RetestQueuePath).LastWriteTime).TotalSeconds)
    $lines.Add("Current MT5 retest queue:")
    $lines.Add(("- state={0} current_symbol={1}" -f $mt5Queue.state, $mt5Queue.current_symbol))
    $lines.Add(("- freshness={0} age_s={1}" -f $(if ($queueAgeSeconds -le 900) { "fresh" } else { "stale" }), $queueAgeSeconds))
    if (@($mt5Queue.completed).Count -gt 0) {
        $lines.Add(("- completed: {0}" -f ((@($mt5Queue.completed)) -join ", ")))
    }
    if (@($mt5Queue.pending).Count -gt 0) {
        $lines.Add(("- pending: {0}" -f ((@($mt5Queue.pending)) -join ", ")))
    }
    $lines.Add("")
}

$fullStackAuditPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\full_stack_audit_latest.json"
if (Test-Path -LiteralPath $fullStackAuditPath) {
    $fullAudit = Get-Content -LiteralPath $fullStackAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lines.Add("Latest full-stack audit:")
    $lines.Add(("- verdict={0} sync_allowed={1}" -f $fullAudit.release_gate.verdict, $fullAudit.release_gate.sync_allowed))
    $lines.Add(("- git_dirty_count={0} runtime_unexpected_dir_count={1} rotation_candidate_count={2}" -f
        $fullAudit.cleanliness.git_dirty_count,
        $fullAudit.cleanliness.runtime_unexpected_dir_count,
        $fullAudit.cleanliness.rotation_candidate_count))
    $lines.Add("")
}

$reportCandidates = @(@(
    "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\fx_lab\primary\fx_mt5_primary_batch_latest.json",
    "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\fx_lab\secondary\fx_mt5_secondary_batch_latest.json",
    "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\weakest_lab\primary\weakest_mt5_batch_latest.json",
    "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\strategy_tester_batch_latest.json"
) | Where-Object { Test-Path -LiteralPath $_ })

if ($reportCandidates.Count -gt 0) {
    $reportPath = $reportCandidates[0]
    $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $lines.Add(("Latest tester batch report: {0}" -f $reportPath))
    $completedRuns = @(
        @($report.runs) |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace([string]$_.result_label) -or
                -not [string]::IsNullOrWhiteSpace([string]$_.test_duration) -or
                -not [string]::IsNullOrWhiteSpace([string]$_.final_balance)
            } |
            Select-Object -First 6
    )
    if ($completedRuns.Count -gt 0) {
        foreach ($run in $completedRuns) {
            $lines.Add(("- {0}: {1}, balance={2}, duration={3}" -f $run.symbol_alias, $run.result_label, $run.final_balance, $run.test_duration))
        }
    }
    else {
        $lines.Add("- batch is running or no completed runs are available yet")
    }
    $lines.Add("")
}

$lines.Add("Use this local summary before asking AI for routine status.")
$lines -join "`r`n"
