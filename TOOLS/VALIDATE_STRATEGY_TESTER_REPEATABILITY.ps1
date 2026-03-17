param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$BaseSummaryPath = "",
    [string]$CurrentSummaryPath = "",
    [double]$MaxSampleDeltaRatio = 0.20,
    [double]$MaxPnlPerSampleDelta = 0.05
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER"

if ([string]::IsNullOrWhiteSpace($BaseSummaryPath) -or [string]::IsNullOrWhiteSpace($CurrentSummaryPath)) {
    $pattern = ("{0}_strategy_tester_*_summary.json" -f $SymbolAlias.ToLowerInvariant())
    $summaries = @(Get-ChildItem -LiteralPath $evidenceDir -Filter $pattern -File -Recurse | Sort-Object LastWriteTimeUtc -Descending)
    if ($summaries.Count -lt 2) {
        throw "Need at least two summary files for SymbolAlias=$SymbolAlias"
    }
    if ([string]::IsNullOrWhiteSpace($CurrentSummaryPath)) {
        $CurrentSummaryPath = $summaries[0].FullName
    }
    if ([string]::IsNullOrWhiteSpace($BaseSummaryPath)) {
        $BaseSummaryPath = $summaries[1].FullName
    }
}

$base = Get-Content -LiteralPath $BaseSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$current = Get-Content -LiteralPath $CurrentSummaryPath -Raw -Encoding UTF8 | ConvertFrom-Json

$baseSamples = [double]$base.learning_sample_count
$currentSamples = [double]$current.learning_sample_count
$sampleDelta = ($currentSamples - $baseSamples)
$sampleDeltaRatio = if ($baseSamples -gt 0) { [math]::Abs($sampleDelta / $baseSamples) } else { 0.0 }

$basePnlPerSample = if ($baseSamples -gt 0) { [math]::Round(([double]$base.realized_pnl_lifetime / $baseSamples), 4) } else { 0.0 }
$currentPnlPerSample = if ($currentSamples -gt 0) { [math]::Round(([double]$current.realized_pnl_lifetime / $currentSamples), 4) } else { 0.0 }
$pnlPerSampleDelta = [math]::Round(($currentPnlPerSample - $basePnlPerSample), 4)

$stable = ($sampleDeltaRatio -le $MaxSampleDeltaRatio -and [math]::Abs($pnlPerSampleDelta) -le $MaxPnlPerSampleDelta)

$report = [ordered]@{
    generated_at_utc      = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias          = $SymbolAlias
    base_run_id           = $base.run_id
    current_run_id        = $current.run_id
    base_summary_path     = $BaseSummaryPath
    current_summary_path  = $CurrentSummaryPath
    base_samples          = [int]$baseSamples
    current_samples       = [int]$currentSamples
    sample_delta          = [int]$sampleDelta
    sample_delta_ratio    = [math]::Round($sampleDeltaRatio, 4)
    base_pnl_per_sample   = $basePnlPerSample
    current_pnl_per_sample= $currentPnlPerSample
    pnl_per_sample_delta  = $pnlPerSampleDelta
    repeatability_status  = $(if ($stable) { "STABLE" } else { "UNSTABLE" })
    thresholds            = [ordered]@{
        max_sample_delta_ratio = $MaxSampleDeltaRatio
        max_pnl_per_sample_delta = $MaxPnlPerSampleDelta
    }
}

$jsonPath = Join-Path $evidenceDir ("{0}_repeatability_latest.json" -f $SymbolAlias.ToLowerInvariant())
$mdPath = Join-Path $evidenceDir ("{0}_repeatability_latest.md" -f $SymbolAlias.ToLowerInvariant())
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$mdLines = @(
    "# Strategy Tester Repeatability $SymbolAlias",
    "",
    ("- base: {0}" -f $report.base_run_id),
    ("- current: {0}" -f $report.current_run_id),
    ("- base_samples: {0}" -f $report.base_samples),
    ("- current_samples: {0}" -f $report.current_samples),
    ("- sample_delta_ratio: {0}" -f $report.sample_delta_ratio),
    ("- base_pnl_per_sample: {0}" -f $report.base_pnl_per_sample),
    ("- current_pnl_per_sample: {0}" -f $report.current_pnl_per_sample),
    ("- pnl_per_sample_delta: {0}" -f $report.pnl_per_sample_delta),
    ("- repeatability_status: {0}" -f $report.repeatability_status)
)
($mdLines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
