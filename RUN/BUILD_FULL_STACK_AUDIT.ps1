param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$LegacyRoot = "C:\OANDA_MT5_SYSTEM",
    [switch]$ApplyRuntimeCleanup,
    [switch]$ApplyLogRotation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$runtimeArtifactAuditScript = Join-Path $ProjectRoot "TOOLS\AUDIT_AND_CLEAN_RUNTIME_ARTIFACTS.ps1"
$runtimePersistenceAuditScript = Join-Path $ProjectRoot "TOOLS\AUDIT_RUNTIME_PERSISTENCE.ps1"
$runtimeLogRotationScript = Join-Path $ProjectRoot "TOOLS\ROTATE_RUNTIME_LOGS.ps1"

foreach ($path in @(
    $runtimeArtifactAuditScript,
    $runtimePersistenceAuditScript,
    $runtimeLogRotationScript
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required audit tool not found: $path"
    }
}

function Get-WrapperCount {
    param([string]$Pattern)

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like $Pattern
            }
    ).Count
}

function Get-FileFreshness {
    param(
        [string]$Label,
        [string]$Path,
        [int]$ThresholdSeconds
    )

    $exists = Test-Path -LiteralPath $Path
    if (-not $exists) {
        return [pscustomobject]@{
            label = $Label
            path = $Path
            exists = $false
            fresh = $false
            last_write_local = $null
            age_seconds = $null
            threshold_seconds = $ThresholdSeconds
        }
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)

    return [pscustomobject]@{
        label = $Label
        path = $Path
        exists = $true
        fresh = ($ageSeconds -le $ThresholdSeconds)
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        age_seconds = $ageSeconds
        threshold_seconds = $ThresholdSeconds
    }
}

function Invoke-JsonAuditTool {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    $null = & $ScriptPath @Parameters | Out-Null
}

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

$gitStatusLines = @()
$gitDirtyCount = 0
$gitTrackedCount = 0
$gitUntrackedCount = 0
try {
    $gitStatusLines = @(
        & git -C $ProjectRoot status --short 2>$null |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
    $gitDirtyCount = $gitStatusLines.Count
    $gitTrackedCount = @($gitStatusLines | Where-Object { $_ -notmatch '^\?\?' }).Count
    $gitUntrackedCount = @($gitStatusLines | Where-Object { $_ -match '^\?\?' }).Count
}
catch {
    $gitStatusLines = @()
}

Invoke-JsonAuditTool -ScriptPath $runtimeArtifactAuditScript -Parameters @{
    ProjectRoot = $ProjectRoot
    Apply = [bool]$ApplyRuntimeCleanup
}
Invoke-JsonAuditTool -ScriptPath $runtimePersistenceAuditScript -Parameters @{
    ProjectRoot = $ProjectRoot
}
Invoke-JsonAuditTool -ScriptPath $runtimeLogRotationScript -Parameters @{
    ProjectRoot = $ProjectRoot
    Apply = [bool]$ApplyLogRotation
}

$runtimeArtifactAudit = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\runtime_artifact_audit_report.json")
$runtimePersistenceAudit = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\runtime_persistence_audit_report.json")
$runtimeLogRotation = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\runtime_log_rotation_report.json")

$freshness = @(
    Get-FileFreshness -Label "local_operator_snapshot" -Path (Join-Path $opsRoot "local_operator_snapshot_latest.json") -ThresholdSeconds 600
    Get-FileFreshness -Label "mt5_tester_status" -Path (Join-Path $opsRoot "mt5_tester_status_latest.json") -ThresholdSeconds 600
    Get-FileFreshness -Label "autonomous_90p" -Path (Join-Path $opsRoot "autonomous_90p_latest.json") -ThresholdSeconds 600
    Get-FileFreshness -Label "trust_but_verify" -Path (Join-Path $opsRoot "trust_but_verify_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "tuning_priority" -Path (Join-Path $opsRoot "tuning_priority_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "mt5_retest_queue" -Path (Join-Path $opsRoot "mt5_retest_queue_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "ml_tuning_hints" -Path (Join-Path $opsRoot "ml_tuning_hints_latest.json") -ThresholdSeconds 1200
    Get-FileFreshness -Label "qdm_weakest_profile" -Path (Join-Path $opsRoot "qdm_weakest_profile_latest.json") -ThresholdSeconds 1200
    Get-FileFreshness -Label "profit_tracking" -Path (Join-Path $opsRoot "profit_tracking_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "vps_runtime_review" -Path (Join-Path $LegacyRoot "EVIDENCE\vps_sync\mt5_virtual_hosting_runtime_review_24h_compact_latest.json") -ThresholdSeconds (30 * 3600)
    Get-FileFreshness -Label "vps_sync" -Path (Join-Path $LegacyRoot "EVIDENCE\vps_sync\mt5_virtual_hosting_sync_latest.json") -ThresholdSeconds (36 * 3600)
)

$mt5TesterStatus = Read-JsonFile -Path (Join-Path $opsRoot "mt5_tester_status_latest.json")
$mt5RetestQueue = Read-JsonFile -Path (Join-Path $opsRoot "mt5_retest_queue_latest.json")
$localSnapshot = Read-JsonFile -Path (Join-Path $opsRoot "local_operator_snapshot_latest.json")
$autonomousStatus = Read-JsonFile -Path (Join-Path $opsRoot "autonomous_90p_latest.json")
$trustButVerify = Read-JsonFile -Path (Join-Path $opsRoot "trust_but_verify_latest.json")
$profitTracking = Read-JsonFile -Path (Join-Path $opsRoot "profit_tracking_latest.json")

$runtimeUnexpectedTotal = 0
if ($null -ne $runtimeArtifactAudit) {
    foreach ($bucket in @($runtimeArtifactAudit.unexpected_by_root)) {
        $runtimeUnexpectedTotal += @($bucket.unexpected).Count
    }
}

$rotationCandidateCount = if ($null -ne $runtimeLogRotation) { @($runtimeLogRotation.candidates).Count } else { 0 }
$rotationAppliedCount = if ($null -ne $runtimeLogRotation) { @($runtimeLogRotation.rotated).Count } else { 0 }
$persistenceOvergrowthCount = 0
if ($null -ne $runtimePersistenceAudit) {
    $rotatableBucket = @($runtimePersistenceAudit.buckets | Where-Object { $_.category -eq "rotatable_journal" } | Select-Object -First 1)
    if ($rotatableBucket.Count -gt 0) {
        $persistenceOvergrowthCount = @($rotatableBucket[0].top_files | Where-Object { $_.over_threshold -eq $true }).Count
    }
}

$wrapperState = [ordered]@{
    supervisor = ((Get-WrapperCount -Pattern "*autonomous_90p_supervisor_wrapper_*") -gt 0)
    archiver = ((Get-WrapperCount -Pattern "*local_operator_archiver_wrapper_*") -gt 0)
    qdm_weakest = ((Get-WrapperCount -Pattern "*qdm_weakest_sync_wrapper_*") -gt 0)
    ml = ((Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0)
    weakest_mt5 = ((Get-WrapperCount -Pattern "*weakest_mt5_batch_wrapper_*") -gt 0 -or (Get-WrapperCount -Pattern "*mt5_retest_queue_wrapper_*") -gt 0)
    mt5_status_watcher = ((Get-WrapperCount -Pattern "*mt5_tester_status_watcher_wrapper_*") -gt 0)
}

$processCounts = [ordered]@{
    terminal64 = @(Get-Process terminal64 -ErrorAction SilentlyContinue).Count
    metatester64 = @(Get-Process metatester64 -ErrorAction SilentlyContinue).Count
    qdmcli = @(Get-Process qdmcli -ErrorAction SilentlyContinue).Count
    python = @(Get-Process python -ErrorAction SilentlyContinue).Count
}

$essentialLocalLabels = @(
    "local_operator_snapshot",
    "mt5_tester_status",
    "autonomous_90p",
    "trust_but_verify",
    "tuning_priority",
    "ml_tuning_hints",
    "qdm_weakest_profile",
    "profit_tracking"
)
$localFresh = (@($freshness | Where-Object { $essentialLocalLabels -contains $_.label -and $_.fresh }).Count -eq $essentialLocalLabels.Count)
$vpsFeedbackFresh = (@($freshness | Where-Object { $_.label -eq "vps_runtime_review" -and $_.fresh }).Count -eq 1)
$verificationClean = ($null -ne $trustButVerify -and [string]$trustButVerify.verdict -eq "OK")

$mt5Running = ($null -ne $mt5TesterStatus -and [string]$mt5TesterStatus.state -eq "running")
$mlRunning = $wrapperState.ml
$labBusy = (
    $mt5Running -or
    $processCounts.metatester64 -gt 0 -or
    $processCounts.qdmcli -gt 0 -or
    $mlRunning
)

$mt5QueueFresh = @($freshness | Where-Object { $_.label -eq "mt5_retest_queue" }).Count -gt 0 -and (@($freshness | Where-Object { $_.label -eq "mt5_retest_queue" })[0].fresh)
$mt5QueueConsistency = $true
if ($mt5QueueFresh -and $null -ne $mt5TesterStatus -and $null -ne $mt5RetestQueue) {
    $queueSymbol = [string]$mt5RetestQueue.current_symbol
    $testerSymbol = [string]$mt5TesterStatus.current_symbol
    if (-not [string]::IsNullOrWhiteSpace($queueSymbol) -and
        -not [string]::IsNullOrWhiteSpace($testerSymbol) -and
        $queueSymbol -ne $testerSymbol) {
        $mt5QueueConsistency = $false
    }
}

$syncAllowed = (
    $vpsFeedbackFresh -and
    $localFresh -and
    ($runtimeUnexpectedTotal -eq 0) -and
    ($rotationCandidateCount -eq 0) -and
    ($gitDirtyCount -eq 0) -and
    $verificationClean -and
    -not $labBusy
)

$releaseVerdict = "READY_FOR_RELEASE"
if (-not $vpsFeedbackFresh) {
    $releaseVerdict = "PULL_SERVER_FEEDBACK_FIRST"
}
elseif (-not $localFresh) {
    $releaseVerdict = "FIX_LOCAL_LAB_FIRST"
}
elseif ($runtimeUnexpectedTotal -gt 0) {
    $releaseVerdict = "CLEAN_RUNTIME_ARTIFACTS_FIRST"
}
elseif ($rotationCandidateCount -gt 0) {
    $releaseVerdict = "ROTATE_RUNTIME_LOGS_FIRST"
}
elseif ($gitDirtyCount -gt 0) {
    $releaseVerdict = "CHECKPOINT_CODE_FIRST"
}
elseif (-not $verificationClean) {
    $releaseVerdict = "TRUST_BUT_VERIFY_RECHECK_FIRST"
}
elseif ($labBusy) {
    $releaseVerdict = "WAIT_FOR_ACTIVE_CYCLES"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    legacy_root = $LegacyRoot
    cadence_policy = [ordered]@{
        pull_before_push = $true
        standard_feedback_cycle_hours = 24
        accelerated_feedback_cycle_hours = 6
        sync_only_after_feedback = $true
    }
    lab_health = [ordered]@{
        wrappers = $wrapperState
        process_counts = $processCounts
        mt5_tester = if ($null -ne $mt5TesterStatus) {
            [ordered]@{
                state = $mt5TesterStatus.state
                current_symbol = $mt5TesterStatus.current_symbol
                latest_progress_pct = $mt5TesterStatus.latest_progress_pct
                run_stamp = $mt5TesterStatus.run_stamp
            }
        } else { $null }
    }
    freshness = @($freshness)
    cleanliness = [ordered]@{
        git_dirty_count = $gitDirtyCount
        git_tracked_count = $gitTrackedCount
        git_untracked_count = $gitUntrackedCount
        git_dirty_head = @($gitStatusLines | Select-Object -First 20)
        runtime_unexpected_dir_count = $runtimeUnexpectedTotal
        rotation_candidate_count = $rotationCandidateCount
        rotation_applied_count = $rotationAppliedCount
        persistence_overgrowth_count = $persistenceOvergrowthCount
    }
    runtime_audits = [ordered]@{
        artifact_audit = $runtimeArtifactAudit
        persistence_audit = $runtimePersistenceAudit
        log_rotation = $runtimeLogRotation
    }
    market_context = if ($null -ne $profitTracking) {
        [ordered]@{
            live_positive_count = $profitTracking.live_positive_count
            tester_positive_count = $profitTracking.tester_positive_count
            near_profit_count = $profitTracking.near_profit_count
        }
    } else { $null }
    consistency = [ordered]@{
        mt5_retest_queue_fresh = $mt5QueueFresh
        mt5_retest_queue_consistent_with_tester = $mt5QueueConsistency
    }
    verification = if ($null -ne $trustButVerify) {
        [ordered]@{
            verdict = $trustButVerify.verdict
            needs_manual_eye = $trustButVerify.needs_manual_eye
            findings = @($trustButVerify.findings)
        }
    } else { $null }
    release_gate = [ordered]@{
        vps_feedback_fresh = $vpsFeedbackFresh
        local_lab_fresh = $localFresh
        runtime_artifacts_clean = ($runtimeUnexpectedTotal -eq 0)
        runtime_logs_rotated = ($rotationCandidateCount -eq 0)
        code_checkpoint_clean = ($gitDirtyCount -eq 0)
        verification_clean = $verificationClean
        lab_busy = $labBusy
        sync_allowed = $syncAllowed
        verdict = $releaseVerdict
    }
}

$jsonLatest = Join-Path $opsRoot "full_stack_audit_latest.json"
$mdLatest = Join-Path $opsRoot "full_stack_audit_latest.md"
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Full Stack Audit")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.release_gate.verdict))
$lines.Add(("- sync_allowed: {0}" -f $report.release_gate.sync_allowed))
$lines.Add("")
$lines.Add("## Release Gate")
$lines.Add("")
$lines.Add(("- vps_feedback_fresh: {0}" -f $report.release_gate.vps_feedback_fresh))
$lines.Add(("- local_lab_fresh: {0}" -f $report.release_gate.local_lab_fresh))
$lines.Add(("- runtime_artifacts_clean: {0}" -f $report.release_gate.runtime_artifacts_clean))
$lines.Add(("- runtime_logs_rotated: {0}" -f $report.release_gate.runtime_logs_rotated))
$lines.Add(("- code_checkpoint_clean: {0}" -f $report.release_gate.code_checkpoint_clean))
$lines.Add(("- verification_clean: {0}" -f $report.release_gate.verification_clean))
$lines.Add(("- lab_busy: {0}" -f $report.release_gate.lab_busy))
$lines.Add("")
$lines.Add("## Cleanliness")
$lines.Add("")
$lines.Add(("- git_dirty_count: {0}" -f $report.cleanliness.git_dirty_count))
$lines.Add(("- runtime_unexpected_dir_count: {0}" -f $report.cleanliness.runtime_unexpected_dir_count))
$lines.Add(("- rotation_candidate_count: {0}" -f $report.cleanliness.rotation_candidate_count))
$lines.Add(("- persistence_overgrowth_count: {0}" -f $report.cleanliness.persistence_overgrowth_count))
$lines.Add("")
$lines.Add("## MT5 Tester")
$lines.Add("")
if ($null -ne $report.lab_health.mt5_tester) {
    $lines.Add(("- state: {0}" -f $report.lab_health.mt5_tester.state))
    $lines.Add(("- current_symbol: {0}" -f $report.lab_health.mt5_tester.current_symbol))
    $lines.Add(("- latest_progress_pct: {0}" -f $report.lab_health.mt5_tester.latest_progress_pct))
    $lines.Add(("- run_stamp: {0}" -f $report.lab_health.mt5_tester.run_stamp))
}
else {
    $lines.Add("- mt5 tester status not available")
}
$lines.Add("")
$lines.Add("## Consistency")
$lines.Add("")
$lines.Add(("- mt5_retest_queue_fresh: {0}" -f $report.consistency.mt5_retest_queue_fresh))
$lines.Add(("- mt5_retest_queue_consistent_with_tester: {0}" -f $report.consistency.mt5_retest_queue_consistent_with_tester))
$lines.Add("")
$lines.Add("## Trust But Verify")
$lines.Add("")
if ($null -ne $report.verification) {
    $lines.Add(("- verdict: {0}" -f $report.verification.verdict))
    $lines.Add(("- needs_manual_eye: {0}" -f $report.verification.needs_manual_eye))
    foreach ($finding in @($report.verification.findings | Select-Object -First 5)) {
        $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
    }
}
else {
    $lines.Add("- verification report not available")
}
$lines.Add("")
$lines.Add("## Freshness")
$lines.Add("")
foreach ($item in $freshness) {
    $lines.Add(("- {0}: fresh={1}, age_s={2}, path={3}" -f $item.label, $item.fresh, $item.age_seconds, $item.path))
}
$lines.Add("")
$lines.Add("## Git Dirty Head")
$lines.Add("")
if ($gitDirtyCount -eq 0) {
    $lines.Add("- clean")
}
else {
    foreach ($line in @($gitStatusLines | Select-Object -First 20)) {
        $lines.Add(("- {0}" -f $line))
    }
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8

$report
