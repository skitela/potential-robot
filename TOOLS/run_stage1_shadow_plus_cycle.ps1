param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$LabDataRoot = "C:\OANDA_MT5_SYSTEM\LAB_DATA",
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
    [switch]$RequireIdle,
    [int]$IdleThresholdSec = 900,
    [switch]$RequireOutsideActive,
    [switch]$Force,
    [switch]$DisableAutoApprove,
    [string]$ApprovalTicket = "",
    [string]$ApprovalComment = "Shadow+ auto approval (shadow-only, no live mutation).",
    [switch]$UseGuiDecision,
    [switch]$ShadowDryRun,
    [switch]$FailOnAllStaleCounterfactual
)

$ErrorActionPreference = "Stop"

function Get-WindowPhase {
    param([string]$RuntimeRoot)
    $logPath = Join-Path $RuntimeRoot "LOGS\safetybot.log"
    if (-not (Test-Path -LiteralPath $logPath)) {
        return "UNKNOWN"
    }
    $lines = Get-Content -LiteralPath $logPath -Tail 3000 -ErrorAction SilentlyContinue
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $ln = [string]$lines[$i]
        if ($ln -match "WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)") {
            return [string]$Matches[1]
        }
    }
    return "UNKNOWN"
}

function Get-IdleSecondsBestEffort {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class OandaIdleProbe {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref lii)) { return 0; }
        return (uint)Environment.TickCount - lii.dwTime;
    }
}
"@ -ErrorAction SilentlyContinue | Out-Null
        $idleMs = [uint32][OandaIdleProbe]::GetIdleMilliseconds()
        return [int][Math]::Floor([double]$idleMs / 1000.0)
    } catch {
        return -1
    }
}

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

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }
    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        return $null
    }
}

$startUtc = (Get-Date).ToUniversalTime()
$stamp = $startUtc.ToString("yyyyMMddTHHmmssZ")
Write-Host "STAGE1_SHADOW_PLUS start_utc=$($startUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')) root=$Root lab_data_root=$LabDataRoot"

$idleSec = Get-IdleSecondsBestEffort
$phase = Get-WindowPhase -RuntimeRoot $Root
$needIdle = $RequireIdle.IsPresent -and (-not $Force.IsPresent)
$needOutside = $RequireOutsideActive.IsPresent -and (-not $Force.IsPresent)

if ($needIdle -and $idleSec -ge 0 -and $idleSec -lt [Math]::Max(10, [int]$IdleThresholdSec)) {
    Write-Host "STAGE1_SHADOW_PLUS skip reason=OPERATOR_ACTIVE idle_sec=$idleSec threshold_sec=$IdleThresholdSec"
    exit 0
}
if ($needOutside -and ([string]$phase).ToUpperInvariant() -eq "ACTIVE") {
    Write-Host "STAGE1_SHADOW_PLUS skip reason=ACTIVE_WINDOW phase=$phase"
    exit 0
}

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

$stage1Dir = Join-Path $LabDataRoot "reports\stage1"
New-Item -ItemType Directory -Force -Path $stage1Dir | Out-Null
$progressJson = Join-Path $stage1Dir "shadow_plus_progression_$stamp.json"
Invoke-Python @(
    "$Root\TOOLS\shadow_plus_progression.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot,
    "--out-report", $progressJson
)
Copy-Latest -SourcePath $progressJson -LatestPath (Join-Path $stage1Dir "shadow_plus_progression_latest.json")

$progress = Read-JsonFile -Path (Join-Path $stage1Dir "shadow_plus_progression_latest.json")
$ff = $null
if ($null -ne $progress) {
    $ff = $progress.feature_flags
}
$enableExtended = $false
$enableAdvisory = $false
$enableSoftGuard = $false
if ($null -ne $ff) {
    try { $enableExtended = [bool]$ff.enable_extended_shadow_profiles } catch { $enableExtended = $false }
    try { $enableAdvisory = [bool]$ff.enable_live_advisory_pack } catch { $enableAdvisory = $false }
    try { $enableSoftGuard = [bool]$ff.enable_soft_guard_candidate_pack } catch { $enableSoftGuard = $false }
}

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

$extendedProfileOutputs = @()
if ($enableExtended) {
    $profiles = @("CANDLE_ONLY", "RENKO_ONLY", "CANDLE_RENKO_CONFLUENCE")
    foreach ($p in $profiles) {
        $pLower = $p.ToLowerInvariant()
        $pJson = Join-Path $shadowDir ("shadow_policy_" + $pLower + "_" + $stamp + ".json")
        $pState = Join-Path $LabDataRoot ("run\\shadow_policy_daily_state_" + $pLower + ".json")
        Invoke-Python @(
            "$Root\TOOLS\shadow_policy_daily_report.py",
            "--root", $Root,
            "--lookback-days", "$ShadowLookbackDays",
            "--horizon-minutes", "$ShadowHorizonMinutes",
            "--strategy-profile", $p,
            "--daily-guard",
            "--state-file", $pState,
            "--out", $pJson
        )
        Copy-Latest -SourcePath $pJson -LatestPath (Join-Path $shadowDir ("shadow_policy_" + $pLower + "_latest.json"))
        Copy-Latest -SourcePath ($pJson -replace "\.json$", ".txt") -LatestPath (Join-Path $shadowDir ("shadow_policy_" + $pLower + "_latest.txt"))
        Copy-Latest -SourcePath ($pJson -replace "\.json$", "_operator.txt") -LatestPath (Join-Path $shadowDir ("shadow_policy_" + $pLower + "_latest_operator.txt"))
        $extendedProfileOutputs += (Join-Path $shadowDir ("shadow_policy_" + $pLower + "_latest.json"))
    }
}

$readinessJson = Join-Path $shadowDir "shadow_signal_readiness_$stamp.json"
Invoke-Python @(
    "$Root\TOOLS\shadow_signal_readiness.py",
    "--root", $Root,
    "--hours", "$ReadinessHours",
    "--out", $readinessJson
)
Copy-Latest -SourcePath $readinessJson -LatestPath (Join-Path $shadowDir "shadow_signal_readiness_latest.json")

$advisoryLatest = ""
if ($enableAdvisory) {
    $advisoryJson = Join-Path $stage1Dir "shadow_live_advisory_$stamp.json"
    Invoke-Python @(
        "$Root\TOOLS\shadow_live_advisory_pack.py",
        "--root", $Root,
        "--lab-data-root", $LabDataRoot,
        "--out-report", $advisoryJson
    )
    $advisoryLatest = (Join-Path $stage1Dir "shadow_live_advisory_latest.json")
    Copy-Latest -SourcePath $advisoryJson -LatestPath $advisoryLatest
}

$softGuardLatest = ""
if ($enableSoftGuard) {
    $softGuardJson = Join-Path $stage1Dir "shadow_soft_guard_candidate_$stamp.json"
    Invoke-Python @(
        "$Root\TOOLS\shadow_soft_guard_candidate.py",
        "--root", $Root,
        "--lab-data-root", $LabDataRoot,
        "--out-report", $softGuardJson
    )
    $softGuardLatest = (Join-Path $stage1Dir "shadow_soft_guard_candidate_latest.json")
    Copy-Latest -SourcePath $softGuardJson -LatestPath $softGuardLatest
}

$popupArgs = @(
    "$Root\TOOLS\stage1_operator_popup.py",
    "--root", $Root,
    "--lab-data-root", $LabDataRoot
)
if (-not $UseGuiDecision.IsPresent) {
    $popupArgs += "--no-gui"
}
Invoke-Python $popupArgs

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
    progression = [ordered]@{
        stage = if ($null -ne $progress -and $null -ne $progress.progress) { [string]$progress.progress.stage } else { "UNKNOWN" }
        stable_streak_days = if ($null -ne $progress -and $null -ne $progress.progress) { [int]$progress.progress.stable_streak_days } else { 0 }
        feature_flags = [ordered]@{
            enable_extended_shadow_profiles = [bool]$enableExtended
            enable_live_advisory_pack = [bool]$enableAdvisory
            enable_soft_guard_candidate_pack = [bool]$enableSoftGuard
        }
    }
    outputs = [ordered]@{
        stage1_gonogo = (Join-Path $stage1Dir "stage1_shadow_gonogo_latest.json")
        stage1_iteration_audit = (Join-Path $stage1Dir "stage1_iteration_audit_latest.json")
        shadow_plus_progression = (Join-Path $stage1Dir "shadow_plus_progression_latest.json")
        shadow_policy_baseline = (Join-Path $shadowDir "shadow_policy_baseline_latest.json")
        shadow_policy_extended = $extendedProfileOutputs
        shadow_signal_readiness = (Join-Path $shadowDir "shadow_signal_readiness_latest.json")
        shadow_live_advisory = $advisoryLatest
        shadow_soft_guard_candidate = $softGuardLatest
        operator_decision = (Join-Path $LabDataRoot "run\operator_decisions\stage1_operator_decision_latest.json")
    }
    status = "PASS"
}
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryLatest -Encoding UTF8

$endUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
Write-Host "STAGE1_SHADOW_PLUS done_utc=$endUtc summary=$summaryPath"
