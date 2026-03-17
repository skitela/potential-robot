param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$BaseSummaryPath = "",
    [string]$CurrentSummaryPath = ""
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

function Get-Delta($a, $b) {
    return [math]::Round(([double]$b - [double]$a), 4)
}

$delta = [ordered]@{
    generated_at_utc           = (Get-Date).ToUniversalTime().ToString("o")
    symbol_alias               = $SymbolAlias
    base_run_id                = $base.run_id
    current_run_id             = $current.run_id
    final_balance_delta        = Get-Delta $base.final_balance $current.final_balance
    learning_sample_delta      = Get-Delta $base.learning_sample_count $current.learning_sample_count
    learning_win_delta         = Get-Delta $base.learning_win_count $current.learning_win_count
    learning_loss_delta        = Get-Delta $base.learning_loss_count $current.learning_loss_count
    paper_open_delta           = Get-Delta $base.paper_open_rows $current.paper_open_rows
    paper_score_gate_delta     = Get-Delta $base.paper_score_gate_rows $current.paper_score_gate_rows
    score_below_trigger_delta  = Get-Delta $base.score_below_trigger_rows $current.score_below_trigger_rows
    paper_conversion_delta     = Get-Delta $base.paper_conversion_ratio $current.paper_conversion_ratio
    trust_state_before         = $base.trust_state
    trust_state_after          = $current.trust_state
    trust_reason_before        = $base.trust_reason
    trust_reason_after         = $current.trust_reason
    worst_buckets_before       = $base.worst_buckets
    worst_buckets_after        = $current.worst_buckets
}

$jsonPath = Join-Path $evidenceDir ("{0}_strategy_tester_delta_latest.json" -f $SymbolAlias.ToLowerInvariant())
$mdPath = Join-Path $evidenceDir ("{0}_strategy_tester_delta_latest.md" -f $SymbolAlias.ToLowerInvariant())
$delta | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$mdLines = @(
    "# Strategy Tester Delta $SymbolAlias",
    "",
    ("- base: {0}" -f $base.run_id),
    ("- current: {0}" -f $current.run_id),
    ("- final_balance_delta: {0}" -f $delta.final_balance_delta),
    ("- learning_sample_delta: {0}" -f $delta.learning_sample_delta),
    ("- wins_delta: {0}" -f $delta.learning_win_delta),
    ("- losses_delta: {0}" -f $delta.learning_loss_delta),
    ("- paper_open_delta: {0}" -f $delta.paper_open_delta),
    ("- paper_score_gate_delta: {0}" -f $delta.paper_score_gate_delta),
    ("- score_below_trigger_delta: {0}" -f $delta.score_below_trigger_delta),
    ("- paper_conversion_delta: {0}" -f $delta.paper_conversion_delta),
    ("- trust_before: {0} / {1}" -f $delta.trust_state_before, $delta.trust_reason_before),
    ("- trust_after: {0} / {1}" -f $delta.trust_state_after, $delta.trust_reason_after)
)
$md = $mdLines -join "`r`n"
$md | Set-Content -LiteralPath $mdPath -Encoding UTF8

$delta
