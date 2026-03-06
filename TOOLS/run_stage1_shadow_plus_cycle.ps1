param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_LAB_DATA",
    [int]$LookbackHours = 24,
    [string]$FocusGroup = "FX",
    [ValidateSet("strategy", "active")]
    [string]$CoverageScope = "active",
    [int]$RetentionDays = 14,
    [int]$MinTotalPerSymbol = 30,
    [int]$MinNoTradePerSymbol = 10,
    [int]$MinTradePathPerSymbol = 1,
    [int]$MinBucketsPerSymbol = 2,
    [int]$ShadowLookbackDays = 14,
    [int]$ShadowHorizonMinutes = 60,
    [int]$ReadinessHours = 24,
    [switch]$DisableAutoApprove,
    [string]$ApprovalTicket = "",
    [string]$ApprovalComment = "Shadow+ auto approval (shadow-only, no live mutation).",
    [switch]$UseGuiDecision,
    [switch]$ShadowDryRun,
    [switch]$FailOnAllStaleCounterfactual
)

$ErrorActionPreference = "Stop"

function Invoke-Python {
    param([string[]]$CommandArgs)
    & py -3.12 -B @CommandArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Python command failed: $($CommandArgs -join ' ')"
    }
}

function Copy-Latest {
    param(
        [string]$SourcePath,
        [string]$LatestPath
    )
    if (Test-Path -LiteralPath $SourcePath) {
        Copy-Item -LiteralPath $SourcePath -Destination $LatestPath -Force
    }
}

$startUtc = (Get-Date).ToUniversalTime()
$stamp = $startUtc.ToString("yyyyMMddTHHmmssZ")
Write-Host "STAGE1_SHADOW_PLUS start_utc=$($startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')) root=$Root lab_data_root=$LabDataRoot"

if (-not $DisableAutoApprove.IsPresent) {
    $ticket = $ApprovalTicket
    if ([string]::IsNullOrWhiteSpace($ticket)) {
        $ticket = "AUTO-SHADOWPLUS-$stamp"
    }
    Invoke-Python @(
        "$Root\TOOLS\stage1_approve.py",
        "--root", $Root,
        "--lab-data-root", $LabDataRoot,
        "--approved", "true",
        "--ticket", $ticket,
        "--comment", $ApprovalComment
    )
}

$learningArgs = @{
    Root                   = $Root
    LabDataRoot            = $LabDataRoot
    LookbackHours          = $LookbackHours
    FocusGroup             = $FocusGroup
    CoverageScope          = $CoverageScope
    RetentionDays          = $RetentionDays
    MinTotalPerSymbol      = $MinTotalPerSymbol
    MinNoTradePerSymbol    = $MinNoTradePerSymbol
    MinTradePathPerSymbol  = $MinTradePathPerSymbol
    MinBucketsPerSymbol    = $MinBucketsPerSymbol
    GoNoGoDatasetQualityHoldMode = "warn"
    ShadowDryRun           = [bool]$ShadowDryRun.IsPresent
    SoftFailGoNoGo         = $true
}
if ($FailOnAllStaleCounterfactual.IsPresent) {
    $learningArgs["FailOnAllStaleCounterfactual"] = $true
}

& "$Root\TOOLS\run_stage1_learning_cycle.ps1" @learningArgs

$shadowDir = Join-Path $LabDataRoot "reports\shadow_policy"
New-Item -ItemType Directory -Force -Path $shadowDir | Out-Null
$shadowJson = Join-Path $shadowDir "shadow_policy_baseline_$stamp.json"

Invoke-Python @(
    "$Root\TOOLS\shadow_policy_daily_report.py",
    "--root", $Root,
    "--lookback-days", "$ShadowLookbackDays",
    "--horizon-minutes", "$ShadowHorizonMinutes",
    "--strategy-profile", "BASELINE",
    "--daily-guard",
    "--out", $shadowJson
)

Copy-Latest -SourcePath $shadowJson -LatestPath (Join-Path $shadowDir "shadow_policy_baseline_latest.json")
Copy-Latest -SourcePath ($shadowJson -replace "\.json$", ".txt") -LatestPath (Join-Path $shadowDir "shadow_policy_baseline_latest.txt")
Copy-Latest -SourcePath ($shadowJson -replace "\.json$", "_operator.txt") -LatestPath (Join-Path $shadowDir "shadow_policy_baseline_latest_operator.txt")

$readinessJson = Join-Path $shadowDir "shadow_signal_readiness_$stamp.json"
Invoke-Python @(
    "$Root\TOOLS\shadow_signal_readiness.py",
    "--root", $Root,
    "--hours", "$ReadinessHours",
    "--out", $readinessJson
)
Copy-Latest -SourcePath $readinessJson -LatestPath (Join-Path $shadowDir "shadow_signal_readiness_latest.json")

$popupArgs = @(
    "$Root\TOOLS\stage1_operator_popup.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot
)
if (-not $UseGuiDecision.IsPresent) {
    $popupArgs += "--no-gui"
}
Invoke-Python $popupArgs

$stage1Dir = Join-Path $LabDataRoot "reports\stage1"
New-Item -ItemType Directory -Force -Path $stage1Dir | Out-Null
$summaryPath = Join-Path $stage1Dir "stage1_shadow_plus_cycle_$stamp.json"
$summaryLatest = Join-Path $stage1Dir "stage1_shadow_plus_cycle_latest.json"

$summary = [ordered]@{
    schema = "oanda.mt5.stage1.shadow_plus_cycle.v1"
    generated_at_utc = $startUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
    root = $Root
    lab_data_root = $LabDataRoot
    mode = if ($ShadowDryRun.IsPresent) { "SHADOW_DRY_RUN" } else { "SHADOW_PLUS" }
    auto_approve = [bool](-not $DisableAutoApprove.IsPresent)
    coverage_scope = $CoverageScope
    lookback_hours = [int]$LookbackHours
    focus_group = $FocusGroup
    outputs = [ordered]@{
        stage1_gonogo = (Join-Path $stage1Dir "stage1_shadow_gonogo_latest.json")
        stage1_iteration_audit = (Join-Path $stage1Dir "stage1_iteration_audit_latest.json")
        shadow_policy_baseline = (Join-Path $shadowDir "shadow_policy_baseline_latest.json")
        shadow_signal_readiness = (Join-Path $shadowDir "shadow_signal_readiness_latest.json")
        operator_decision = (Join-Path $LabDataRoot "run\operator_decisions\stage1_operator_decision_latest.json")
    }
    status = "PASS"
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryLatest -Encoding UTF8

$endUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "STAGE1_SHADOW_PLUS done_utc=$endUtc summary=$summaryPath"
