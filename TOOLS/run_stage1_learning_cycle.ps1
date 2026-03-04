param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [int]$LookbackHours = 24,
    [string]$FocusGroup = "FX",
    [int]$RetentionDays = 14,
    [int]$MinTotalPerSymbol = 30,
    [int]$MinNoTradePerSymbol = 10,
    [int]$MinTradePathPerSymbol = 1,
    [int]$MinBucketsPerSymbol = 2
)

$ErrorActionPreference = "Stop"

function Invoke-Python {
    param([string[]]$CommandArgs)
    & py -3.12 -B @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $($CommandArgs -join ' ')"
    }
}

$startTs = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "STAGE1_LEARNING_CYCLE start_utc=$startTs root=$Root lab_data_root=$LabDataRoot focus=$FocusGroup lookback_h=$LookbackHours"

Invoke-Python @(
    "$Root\TOOLS\rejected_coverage_report.py",
    "--root", $Root,
    "--lookback-hours", "$LookbackHours"
)

Invoke-Python @(
    "$Root\TOOLS\rejected_coverage_gate.py",
    "--root", $Root,
    "--focus-group", $FocusGroup,
    "--lookback-hours", "$LookbackHours"
)

Invoke-Python @(
    "$Root\TOOLS\build_stage1_learning_dataset.py",
    "--root", $Root,
    "--lookback-hours", "$LookbackHours"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_counterfactual_from_snapshots.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--horizon-minutes", "15",
    "--max-no-trade-samples", "1000"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_counterfactual_summary.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot
)

Invoke-Python @(
    "$Root\TOOLS\stage1_profile_pack.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--min-samples", "30"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_dataset_quality.py",
    "--root", $Root,
    "--min-total-per-symbol", "$MinTotalPerSymbol",
    "--min-no-trade-per-symbol", "$MinNoTradePerSymbol",
    "--min-trade-path-per-symbol", "$MinTradePathPerSymbol",
    "--min-buckets-per-symbol", "$MinBucketsPerSymbol"
)

$cutoff = (Get-Date).AddDays(-[Math]::Abs($RetentionDays))
$removed = 0

$cleanupPlan = @(
    @{
        Dir = (Join-Path $Root "EVIDENCE\learning_coverage")
        Patterns = @(
            "rejected_coverage_*.json",
            "rejected_coverage_*.txt",
            "rejected_coverage_gate_*.json",
            "rejected_coverage_gate_*.txt"
        )
    },
    @{
        Dir = (Join-Path $Root "EVIDENCE\learning_dataset")
        Patterns = @(
            "stage1_learning_*.jsonl",
            "stage1_learning_*.meta.json"
        )
    },
    @{
        Dir = (Join-Path $Root "EVIDENCE\learning_dataset_quality")
        Patterns = @(
            "stage1_dataset_quality_*.json",
            "stage1_dataset_quality_*.txt"
        )
    },
    @{
        Dir = (Join-Path $LabDataRoot "reports\stage1")
        Patterns = @(
            "stage1_counterfactual_rows_*.jsonl",
            "stage1_counterfactual_report_*.json",
            "stage1_counterfactual_report_*.txt",
            "stage1_counterfactual_summary_*.json",
            "stage1_counterfactual_summary_*.txt",
            "stage1_profile_pack_*.json",
            "stage1_profile_pack_*.txt"
        )
    }
)

foreach ($item in $cleanupPlan) {
    $dir = [string]$item.Dir
    if (!(Test-Path $dir)) { continue }
    foreach ($pat in @($item.Patterns)) {
        Get-ChildItem -Path $dir -Filter $pat -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
                $removed++
            }
    }
}
Write-Host "STAGE1_LEARNING_CYCLE cleanup_removed=$removed retention_days=$RetentionDays"

$endTs = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "STAGE1_LEARNING_CYCLE done_utc=$endTs"
