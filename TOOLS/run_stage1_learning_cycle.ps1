param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [int]$LookbackHours = 24,
    [string]$FocusGroup = "FX",
    [ValidateSet("strategy", "active")]
    [string]$CoverageScope = "strategy",
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
Write-Host "STAGE1_LEARNING_CYCLE start_utc=$startTs root=$Root lab_data_root=$LabDataRoot focus=$FocusGroup lookback_h=$LookbackHours coverage_scope=$CoverageScope"

Invoke-Python @(
    "$Root\TOOLS\rejected_coverage_report.py",
    "--root", $Root,
    "--lookback-hours", "$LookbackHours"
)

Invoke-Python @(
    "$Root\TOOLS\rejected_coverage_gate.py",
    "--root", $Root,
    "--focus-group", $FocusGroup,
    "--symbol-scope", $CoverageScope,
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
    "$Root\TOOLS\stage1_profile_pack_evaluate.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--min-shadow-trades", "3"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_shadow_deployer.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--cooldown-minutes", "60",
    "--dry-run"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_shadow_apply_plan.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--dry-run"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_dataset_quality.py",
    "--root", $Root,
    "--min-total-per-symbol", "$MinTotalPerSymbol",
    "--min-no-trade-per-symbol", "$MinNoTradePerSymbol",
    "--min-trade-path-per-symbol", "$MinTradePathPerSymbol",
    "--min-buckets-per-symbol", "$MinBucketsPerSymbol"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_shadow_gonogo.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot
)

Invoke-Python @(
    "$Root\TOOLS\stage1_iteration_audit.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--focus-group", $FocusGroup,
    "--lookback-hours", "$LookbackHours"
)

Invoke-Python @(
    "$Root\TOOLS\stage1_coverage_recovery_plan.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--focus-group", $FocusGroup,
    "--lookback-hours", "$LookbackHours"
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
            "stage1_profile_pack_*.txt",
            "stage1_profile_pack_eval_*.json",
            "stage1_profile_pack_eval_*.txt",
            "stage1_shadow_deployer_*.json",
            "stage1_shadow_deployer_*.txt",
            "stage1_shadow_deployer_audit*.jsonl",
            "stage1_shadow_apply_plan_*.json",
            "stage1_shadow_apply_plan_*.txt",
            "stage1_shadow_apply_audit*.jsonl",
            "stage1_shadow_gonogo_*.json",
            "stage1_shadow_gonogo_*.txt",
            "stage1_iteration_audit_*.json",
            "stage1_iteration_audit_*.txt",
            "stage1_coverage_recovery_*.json",
            "stage1_coverage_recovery_*.txt"
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
