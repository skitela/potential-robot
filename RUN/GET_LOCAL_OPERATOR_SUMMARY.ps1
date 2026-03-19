Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("=== LOCAL OPERATOR SUMMARY ===")
$lines.Add("")

$fxProcesses = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -in @("terminal64", "metatester64", "qdmcli", "python") })
if ($fxProcesses.Count -gt 0) {
    $lines.Add("Active lab processes:")
    foreach ($proc in $fxProcesses | Sort-Object ProcessName, Id) {
        $lines.Add(("- {0} #{1} priority={2} ram_mb={3}" -f $proc.ProcessName, $proc.Id, $proc.PriorityClass, [math]::Round($proc.WorkingSet64 / 1MB, 1)))
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
    foreach ($run in $report.runs | Select-Object -First 6) {
        $lines.Add(("- {0}: {1}, balance={2}, duration={3}" -f $run.symbol_alias, $run.result_label, $run.final_balance, $run.test_duration))
    }
    $lines.Add("")
}

$lines.Add("Use this local summary before asking AI for routine status.")
$lines -join "`r`n"
