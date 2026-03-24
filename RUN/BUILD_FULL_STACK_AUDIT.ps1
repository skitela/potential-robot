param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$PaperLiveFeedbackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json",
    [string]$HostingHealthPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_hosting_daily_report_latest.json",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
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
$repoHygieneScript = Join-Path $ProjectRoot "RUN\BUILD_REPO_HYGIENE_REPORT.ps1"
$nearProfitQueueStatusScript = Join-Path $ProjectRoot "RUN\SYNC_NEAR_PROFIT_OPTIMIZATION_QUEUE_STATUS.ps1"

foreach ($path in @(
    $runtimeArtifactAuditScript,
    $runtimePersistenceAuditScript,
    $runtimeLogRotationScript,
    $repoHygieneScript,
    $nearProfitQueueStatusScript
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

function Get-LatestFileByPattern {
    param(
        [string]$DirectoryPath,
        [string]$Filter
    )

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        return $null
    }

    return Get-ChildItem -LiteralPath $DirectoryPath -File -Filter $Filter -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
}

function Get-SafeObjectValue {
    param(
        [object]$Object,
        [string]$PropertyName,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }
    if ($Object.PSObject.Properties.Name -contains $PropertyName) {
        return $Object.$PropertyName
    }
    return $Default
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
Invoke-JsonAuditTool -ScriptPath $repoHygieneScript -Parameters @{
    ProjectRoot = $ProjectRoot
    OutputRoot = $opsRoot
}
Invoke-JsonAuditTool -ScriptPath $nearProfitQueueStatusScript -Parameters @{
    ProjectRoot = $ProjectRoot
    UseDedicatedPortableLabLane = $true
    DedicatedLabTerminalRoot = "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB"
}

$runtimeArtifactAudit = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\runtime_artifact_audit_report.json")
$runtimePersistenceAudit = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\runtime_persistence_audit_report.json")
$runtimeLogRotation = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\runtime_log_rotation_report.json")
$repoHygiene = Read-JsonFile -Path (Join-Path $opsRoot "repo_hygiene_latest.json")

$freshness = @(
    Get-FileFreshness -Label "local_operator_snapshot" -Path (Join-Path $opsRoot "local_operator_snapshot_latest.json") -ThresholdSeconds 600
    Get-FileFreshness -Label "mt5_tester_status" -Path (Join-Path $opsRoot "mt5_tester_status_latest.json") -ThresholdSeconds 600
    Get-FileFreshness -Label "autonomous_90p" -Path (Join-Path $opsRoot "autonomous_90p_latest.json") -ThresholdSeconds 600
    Get-FileFreshness -Label "trust_but_verify" -Path (Join-Path $opsRoot "trust_but_verify_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "tuning_priority" -Path (Join-Path $opsRoot "tuning_priority_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "mt5_retest_queue" -Path (Join-Path $opsRoot "mt5_retest_queue_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "near_profit_optimization_queue" -Path (Join-Path $opsRoot "near_profit_optimization_queue_latest.json") -ThresholdSeconds 900
    Get-FileFreshness -Label "ml_tuning_hints" -Path (Join-Path $opsRoot "ml_tuning_hints_latest.json") -ThresholdSeconds 1200
    Get-FileFreshness -Label "qdm_missing_only_profile" -Path (Join-Path $opsRoot "qdm_missing_only_profile_latest.json") -ThresholdSeconds 1200
    Get-FileFreshness -Label "qdm_missing_supported_sync" -Path (Join-Path $opsRoot "qdm_missing_supported_sync_latest.json") -ThresholdSeconds 1200
    Get-FileFreshness -Label "qdm_weakest_profile" -Path (Join-Path $opsRoot "qdm_weakest_profile_latest.json") -ThresholdSeconds 1200
    Get-FileFreshness -Label "qdm_custom_symbol_pilot" -Path (Join-Path $ProjectRoot "EVIDENCE\QDM_PILOT\qdm_import_custom_symbol_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "qdm_custom_symbol_smoke" -Path (Join-Path $opsRoot "qdm_custom_symbol_smoke_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "qdm_custom_symbol_pilot_registry" -Path (Join-Path $opsRoot "qdm_custom_symbol_pilot_registry_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "qdm_custom_symbol_pilot_batch" -Path (Join-Path $opsRoot "qdm_custom_symbol_pilot_batch_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "profit_tracking" -Path (Join-Path $opsRoot "profit_tracking_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "research_export_manifest" -Path (Join-Path $ResearchRoot "reports\research_export_manifest_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "daily_system_report" -Path (Join-Path $ProjectRoot "EVIDENCE\DAILY\raport_dzienny_latest.json") -ThresholdSeconds 5400
    Get-FileFreshness -Label "paper_live_feedback" -Path $PaperLiveFeedbackPath -ThresholdSeconds 1800
    Get-FileFreshness -Label "mt5_hosting_health" -Path $HostingHealthPath -ThresholdSeconds 1800
)

$mt5TesterStatus = Read-JsonFile -Path (Join-Path $opsRoot "mt5_tester_status_latest.json")
$mt5RetestQueue = Read-JsonFile -Path (Join-Path $opsRoot "mt5_retest_queue_latest.json")
$localSnapshot = Read-JsonFile -Path (Join-Path $opsRoot "local_operator_snapshot_latest.json")
$autonomousStatus = Read-JsonFile -Path (Join-Path $opsRoot "autonomous_90p_latest.json")
$trustButVerify = Read-JsonFile -Path (Join-Path $opsRoot "trust_but_verify_latest.json")
$profitTracking = Read-JsonFile -Path (Join-Path $opsRoot "profit_tracking_latest.json")
$nearProfitQueue = Read-JsonFile -Path (Join-Path $opsRoot "near_profit_optimization_queue_latest.json")
$qdmMissingOnlyProfile = Read-JsonFile -Path (Join-Path $opsRoot "qdm_missing_only_profile_latest.json")
$qdmMissingSupportedSync = Read-JsonFile -Path (Join-Path $opsRoot "qdm_missing_supported_sync_latest.json")
$researchManifest = Read-JsonFile -Path (Join-Path $ResearchRoot "reports\research_export_manifest_latest.json")
$qdmCustomPilot = Read-JsonFile -Path (Join-Path $ProjectRoot "EVIDENCE\QDM_PILOT\qdm_import_custom_symbol_latest.json")
$qdmCustomSmokeLatest = Read-JsonFile -Path (Join-Path $opsRoot "qdm_custom_symbol_smoke_latest.json")
$qdmCustomPilotRegistry = Read-JsonFile -Path (Join-Path $opsRoot "qdm_custom_symbol_pilot_registry_latest.json")
$qdmCustomPilotBatch = Read-JsonFile -Path (Join-Path $opsRoot "qdm_custom_symbol_pilot_batch_latest.json")
$qdmCustomSmokeDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\qdm_custom_symbol_smoke"
$qdmCustomSmokeSummaryFile = Get-LatestFileByPattern -DirectoryPath $qdmCustomSmokeDir -Filter "*_summary.json"
$qdmCustomSmokeSummary = if ($null -ne $qdmCustomSmokeSummaryFile) { Read-JsonFile -Path $qdmCustomSmokeSummaryFile.FullName } else { $null }
$qdmCustomSmokeRun = $null
if ($null -ne $qdmCustomSmokeSummaryFile) {
    $runJsonName = [System.IO.Path]::GetFileNameWithoutExtension($qdmCustomSmokeSummaryFile.Name) -replace "_summary$",""
    $runJsonPath = Join-Path $qdmCustomSmokeDir ($runJsonName + ".json")
    $qdmCustomSmokeRun = Read-JsonFile -Path $runJsonPath
}

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
    near_profit_optimization = (
        (Get-WrapperCount -Pattern "*near_profit_optimization_after_idle_wrapper_*") -gt 0 -or
        ($null -ne $nearProfitQueue -and (
            [string]$nearProfitQueue.state -eq "running" -or
            [int](Get-SafeObjectValue -Object $nearProfitQueue -PropertyName 'dedicated_lab_terminal_count' -Default 0) -gt 0 -or
            [int](Get-SafeObjectValue -Object $nearProfitQueue -PropertyName 'dedicated_lab_metatester_count' -Default 0) -gt 0
        ))
    )
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
$paperLiveFeedbackFresh = (
    @($freshness | Where-Object { $_.label -eq "daily_system_report" -and $_.fresh }).Count -eq 1 -and
    @($freshness | Where-Object { $_.label -eq "paper_live_feedback" -and $_.fresh }).Count -eq 1 -and
    @($freshness | Where-Object { $_.label -eq "mt5_hosting_health" -and $_.fresh }).Count -eq 1
)
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
$nearProfitQueueFresh = @($freshness | Where-Object { $_.label -eq "near_profit_optimization_queue" }).Count -gt 0 -and (@($freshness | Where-Object { $_.label -eq "near_profit_optimization_queue" })[0].fresh)
$researchExportFresh = @($freshness | Where-Object { $_.label -eq "research_export_manifest" }).Count -gt 0 -and (@($freshness | Where-Object { $_.label -eq "research_export_manifest" })[0].fresh)
$mt5QueueConsistency = $true
if ($mt5QueueFresh -and $null -ne $mt5TesterStatus -and $null -ne $mt5RetestQueue) {
    $queueSymbol = [string]$mt5RetestQueue.current_symbol
    $queueState = [string]$mt5RetestQueue.state
    $testerSymbol = [string]$mt5TesterStatus.current_symbol
    $testerState = [string]$mt5TesterStatus.state

    if ($testerState -eq "running" -and
        $queueState -eq "running" -and
        [string]::IsNullOrWhiteSpace($queueSymbol)) {
        $mt5QueueConsistency = $false
    }
    elseif (-not [string]::IsNullOrWhiteSpace($queueSymbol) -and
        -not [string]::IsNullOrWhiteSpace($testerSymbol) -and
        $queueSymbol -ne $testerSymbol) {
        $mt5QueueConsistency = $false
    }
}

$researchTesterTelemetryRows = 0
$researchTesterPassFrameRows = 0
$researchTesterSummaryRows = 0
$researchTesterKnowledgeRows = 0
$researchOptimizationTelemetryVisible = $false
if ($null -ne $researchManifest -and $researchManifest.PSObject.Properties.Name -contains "datasets") {
    $datasets = $researchManifest.datasets
    $researchTesterTelemetryRows = [int](Get-SafeObjectValue -Object (Get-SafeObjectValue -Object $datasets -PropertyName 'tester_telemetry' -Default $null) -PropertyName 'rows' -Default 0)
    $researchTesterPassFrameRows = [int](Get-SafeObjectValue -Object (Get-SafeObjectValue -Object $datasets -PropertyName 'tester_pass_frames' -Default $null) -PropertyName 'rows' -Default 0)
    $researchTesterSummaryRows = [int](Get-SafeObjectValue -Object (Get-SafeObjectValue -Object $datasets -PropertyName 'tester_summary' -Default $null) -PropertyName 'rows' -Default 0)
    $researchTesterKnowledgeRows = [int](Get-SafeObjectValue -Object (Get-SafeObjectValue -Object $datasets -PropertyName 'tester_knowledge' -Default $null) -PropertyName 'rows' -Default 0)
    $researchOptimizationTelemetryVisible = ($researchTesterPassFrameRows -gt 0)
}

$syncAllowed = (
    $paperLiveFeedbackFresh -and
    $localFresh -and
    ($runtimeUnexpectedTotal -eq 0) -and
    ($rotationCandidateCount -eq 0) -and
    ($gitDirtyCount -eq 0) -and
    $verificationClean -and
    -not $labBusy
)

$releaseVerdict = "READY_FOR_RELEASE"
if (-not $paperLiveFeedbackFresh) {
    $releaseVerdict = "REFRESH_PAPER_LIVE_FEEDBACK_FIRST"
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
    paper_live_paths = [ordered]@{
        feedback = $PaperLiveFeedbackPath
        hosting_health = $HostingHealthPath
    }
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
        near_profit_optimization = if ($null -ne $nearProfitQueue) {
            [ordered]@{
                state = $nearProfitQueue.state
                current_symbol = $nearProfitQueue.current_symbol
                selected_symbols = @($nearProfitQueue.selected_symbols)
                pending = @($nearProfitQueue.pending)
                risk_guard_running = $nearProfitQueue.near_profit_risk_guard_running
                risk_guard_count = $nearProfitQueue.near_profit_risk_guard_count
                risk_guard_rejected_events = $nearProfitQueue.near_profit_risk_guard_rejected_events
                active_sandbox = if ($nearProfitQueue.PSObject.Properties.Name -contains "active_sandbox") { $nearProfitQueue.active_sandbox } else { $null }
                positive_pass_visible = (
                    $nearProfitQueue.PSObject.Properties.Name -contains "active_sandbox" -and
                    $null -ne $nearProfitQueue.active_sandbox -and
                    [double](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'best_tester_pass_realized_pnl' -Default 0.0) -gt 0
                )
                sandbox_progress_visible = (
                    $nearProfitQueue.PSObject.Properties.Name -contains "active_sandbox" -and
                    $null -ne $nearProfitQueue.active_sandbox -and
                    (
                        [int](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'candidate_signal_rows' -Default 0) -gt 0 -or
                        [int](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'decision_event_rows' -Default 0) -gt 0 -or
                        [int](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'tester_pass_rows' -Default 0) -gt 0 -or
                        [long](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'candidate_signal_bytes' -Default 0) -gt 0 -or
                        [long](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'decision_event_bytes' -Default 0) -gt 0 -or
                        [long](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'tuning_experiment_bytes' -Default 0) -gt 0 -or
                        (
                            [bool](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'heartbeat_fresh' -Default $false) -and
                            [int](Get-SafeObjectValue -Object $nearProfitQueue.active_sandbox -PropertyName 'timer_cycles' -Default 0) -gt 0
                        )
                    )
                )
            }
        } else { $null }
        qdm_missing_supported_sync = if ($null -ne $qdmMissingSupportedSync -or $null -ne $qdmMissingOnlyProfile) {
            $profileMissingSymbols = if ($null -ne $qdmMissingOnlyProfile) { @($qdmMissingOnlyProfile.missing | ForEach-Object { [string]$_.symbol_alias }) } else { @() }
            $profileUnsupportedSymbols = if ($null -ne $qdmMissingOnlyProfile) { @($qdmMissingOnlyProfile.unsupported | ForEach-Object { [string]$_.symbol_alias }) } else { @() }
            $resolvedMissingSymbols = if ($null -ne $qdmMissingOnlyProfile) {
                @($profileMissingSymbols)
            }
            elseif ($null -ne $qdmMissingSupportedSync) {
                @((Get-SafeObjectValue -Object $qdmMissingSupportedSync -PropertyName 'missing_symbols' -Default @()))
            }
            else {
                @()
            }
            $resolvedUnsupportedSymbols = if ($null -ne $qdmMissingOnlyProfile) {
                @($profileUnsupportedSymbols)
            }
            elseif ($null -ne $qdmMissingSupportedSync) {
                @((Get-SafeObjectValue -Object $qdmMissingSupportedSync -PropertyName 'unsupported_symbols' -Default @()))
            }
            else {
                @()
            }
            [ordered]@{
                state = $(if ($null -ne $qdmMissingSupportedSync) { Get-SafeObjectValue -Object $qdmMissingSupportedSync -PropertyName 'state' -Default $null } else { $null })
                sync_started = $(if ($null -ne $qdmMissingSupportedSync) { [bool](Get-SafeObjectValue -Object $qdmMissingSupportedSync -PropertyName 'sync_started' -Default $false) } else { $false })
                missing_count = $(if ($null -ne $qdmMissingOnlyProfile) { [int](Get-SafeObjectValue -Object $qdmMissingOnlyProfile -PropertyName 'qdm_missing_count' -Default 0) } else { 0 })
                blocked_count = $(if ($null -ne $qdmMissingOnlyProfile) { [int](Get-SafeObjectValue -Object $qdmMissingOnlyProfile -PropertyName 'qdm_blocked_count' -Default 0) } else { 0 })
                unsupported_count = $(if ($null -ne $qdmMissingOnlyProfile) { [int](Get-SafeObjectValue -Object $qdmMissingOnlyProfile -PropertyName 'qdm_unsupported_count' -Default 0) } else { 0 })
                missing_symbols = @($resolvedMissingSymbols)
                unsupported_symbols = @($resolvedUnsupportedSymbols)
                current_focus = $(if ($null -ne $qdmMissingSupportedSync) { Get-SafeObjectValue -Object $qdmMissingSupportedSync -PropertyName 'current_focus' -Default $null } else { $null })
                note = $(if ($null -ne $qdmMissingSupportedSync) { Get-SafeObjectValue -Object $qdmMissingSupportedSync -PropertyName 'note' -Default $null } else { $null })
            }
        } else { $null }
        qdm_custom_symbol_pilot = if ($null -ne $qdmCustomPilot) {
            [ordered]@{
                run_status = $qdmCustomPilot.run_status
                import_succeeded = $qdmCustomPilot.import_succeeded
                custom_symbol = $qdmCustomPilot.custom_symbol
                broker_template_symbol = $qdmCustomPilot.broker_template_symbol
                portable_terminal = $qdmCustomPilot.portable_terminal
                terminal_origin = $qdmCustomPilot.terminal_origin
                import_message = $qdmCustomPilot.import_message
                terminal_log_copy_path = $qdmCustomPilot.terminal_log_copy_path
                mql_log_copy_path = $(if ($qdmCustomPilot.PSObject.Properties.Name -contains "mql_log_copy_path") { $qdmCustomPilot.mql_log_copy_path } else { $null })
            }
        } else { $null }
        qdm_custom_symbol_smoke = if ($null -ne $qdmCustomSmokeLatest) {
            [ordered]@{
                summary_path = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'summary_path' -Default $null)
                last_write_local = $(if (Test-Path -LiteralPath (Join-Path $opsRoot "qdm_custom_symbol_smoke_latest.json")) { (Get-Item -LiteralPath (Join-Path $opsRoot "qdm_custom_symbol_smoke_latest.json")).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null })
                run_id = $qdmCustomSmokeLatest.tester_run_id
                symbol = $qdmCustomSmokeLatest.custom_symbol
                result_label = $qdmCustomSmokeLatest.result_label
                final_balance = $qdmCustomSmokeLatest.final_balance
                test_duration = $qdmCustomSmokeLatest.test_duration
                learning_sample_count = $null
                requested_model = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'requested_model' -Default $null)
                model = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'model' -Default $null)
                model_normalized_for_qdm_custom_symbol = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'model_normalized_for_qdm_custom_symbol' -Default $false)
            }
        } elseif ($null -ne $qdmCustomSmokeSummaryFile -and $null -ne $qdmCustomSmokeSummary) {
            [ordered]@{
                summary_path = $qdmCustomSmokeSummaryFile.FullName
                last_write_local = $qdmCustomSmokeSummaryFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                run_id = $qdmCustomSmokeSummary.run_id
                symbol = $qdmCustomSmokeSummary.symbol
                result_label = $qdmCustomSmokeSummary.result_label
                final_balance = $qdmCustomSmokeSummary.final_balance
                test_duration = $qdmCustomSmokeSummary.test_duration
                learning_sample_count = $qdmCustomSmokeSummary.learning_sample_count
                requested_model = $(if ($null -ne $qdmCustomSmokeRun) { Get-SafeObjectValue -Object $qdmCustomSmokeRun -PropertyName 'requested_model' -Default $null } else { $null })
                model = $(if ($null -ne $qdmCustomSmokeRun) { Get-SafeObjectValue -Object $qdmCustomSmokeRun -PropertyName 'model' -Default $null } else { $null })
                model_normalized_for_qdm_custom_symbol = $(if ($null -ne $qdmCustomSmokeRun) { Get-SafeObjectValue -Object $qdmCustomSmokeRun -PropertyName 'model_normalized_for_qdm_custom_symbol' -Default $false } else { $false })
            }
        } else { $null }
        qdm_custom_symbol_pilot_registry = if ($null -ne $qdmCustomPilotRegistry) {
            [ordered]@{
                total_symbols = $qdmCustomPilotRegistry.total_symbols
                successful_smokes = $qdmCustomPilotRegistry.successful_smokes
                normalized_models = $qdmCustomPilotRegistry.normalized_models
                symbols = @($qdmCustomPilotRegistry.symbols)
            }
        } else { $null }
        qdm_custom_symbol_pilot_batch = if ($null -ne $qdmCustomPilotBatch) {
            [ordered]@{
                state = $qdmCustomPilotBatch.state
                successful_count = $qdmCustomPilotBatch.successful_count
                failed_count = $qdmCustomPilotBatch.failed_count
                selected_symbol_source = $(Get-SafeObjectValue -Object $qdmCustomPilotBatch -PropertyName 'selected_symbol_source' -Default $null)
                selected_symbols = @($qdmCustomPilotBatch.selected_symbols)
            }
        } else { $null }
    }
    freshness = @($freshness)
    cleanliness = [ordered]@{
        git_dirty_count = $gitDirtyCount
        git_tracked_count = $gitTrackedCount
        git_untracked_count = $gitUntrackedCount
        git_dirty_head = @($gitStatusLines | Select-Object -First 20)
        repo_hygiene_verdict = $(if ($null -ne $repoHygiene) { $repoHygiene.verdict } else { $null })
        git_code_dirty_count = $(if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'code_or_logic' -Default 0) } else { 0 })
        git_generated_timestamp_only_count = $(if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'generated_timestamp_only' -Default 0) } else { 0 })
        git_generated_other_count = $(if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'generated_other' -Default 0) } else { 0 })
        runtime_unexpected_dir_count = $runtimeUnexpectedTotal
        rotation_candidate_count = $rotationCandidateCount
        rotation_applied_count = $rotationAppliedCount
        persistence_overgrowth_count = $persistenceOvergrowthCount
    }
    runtime_audits = [ordered]@{
        artifact_audit = $runtimeArtifactAudit
        persistence_audit = $runtimePersistenceAudit
        log_rotation = $runtimeLogRotation
        repo_hygiene = $repoHygiene
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
        near_profit_optimization_queue_fresh = $nearProfitQueueFresh
        research_export_manifest_fresh = $researchExportFresh
    }
    research_pipeline = [ordered]@{
        manifest_present = ($null -ne $researchManifest)
        export_fresh = $researchExportFresh
        tester_telemetry_rows = $researchTesterTelemetryRows
        tester_pass_frame_rows = $researchTesterPassFrameRows
        tester_summary_rows = $researchTesterSummaryRows
        tester_knowledge_rows = $researchTesterKnowledgeRows
        optimization_telemetry_visible = $researchOptimizationTelemetryVisible
    }
    verification = if ($null -ne $trustButVerify) {
        [ordered]@{
            verdict = $trustButVerify.verdict
            needs_manual_eye = $trustButVerify.needs_manual_eye
            findings = @($trustButVerify.findings)
        }
    } else { $null }
    release_gate = [ordered]@{
        paper_live_feedback_fresh = $paperLiveFeedbackFresh
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
$lines.Add(("- paper_live_feedback_fresh: {0}" -f $report.release_gate.paper_live_feedback_fresh))
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
$lines.Add(("- repo_hygiene_verdict: {0}" -f $report.cleanliness.repo_hygiene_verdict))
$lines.Add(("- git_code_dirty_count: {0}" -f $report.cleanliness.git_code_dirty_count))
$lines.Add(("- git_generated_timestamp_only_count: {0}" -f $report.cleanliness.git_generated_timestamp_only_count))
$lines.Add(("- git_generated_other_count: {0}" -f $report.cleanliness.git_generated_other_count))
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
$lines.Add("## Near Profit Lane")
$lines.Add("")
if ($null -ne $report.lab_health.near_profit_optimization) {
    $lines.Add(("- state: {0}" -f $report.lab_health.near_profit_optimization.state))
    $lines.Add(("- current_symbol: {0}" -f $report.lab_health.near_profit_optimization.current_symbol))
    $lines.Add(("- risk_guard_running: {0}" -f $report.lab_health.near_profit_optimization.risk_guard_running))
    $lines.Add(("- risk_guard_rejected_events: {0}" -f $report.lab_health.near_profit_optimization.risk_guard_rejected_events))
    $lines.Add(("- sandbox_progress_visible: {0}" -f $report.lab_health.near_profit_optimization.sandbox_progress_visible))
    $lines.Add(("- positive_pass_visible: {0}" -f $report.lab_health.near_profit_optimization.positive_pass_visible))
    if ($null -ne $report.lab_health.near_profit_optimization.active_sandbox) {
        $lines.Add(("- storage_contract_complete: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.storage_contract_complete))
        $lines.Add(("- run_dir_present: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.run_dir_present))
        $lines.Add(("- key_dir_present: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.key_dir_present))
        $lines.Add(("- heartbeat_fresh: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.heartbeat_fresh))
        $lines.Add(("- heartbeat_age_sec: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.heartbeat_age_sec))
        $lines.Add(("- ticks_seen: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.ticks_seen))
        $lines.Add(("- learning_sample_count: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.learning_sample_count))
        $lines.Add(("- realized_pnl_lifetime: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.realized_pnl_lifetime))
        $lines.Add(("- candidate_signal_rows: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.candidate_signal_rows))
        $lines.Add(("- decision_event_rows: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.decision_event_rows))
        $lines.Add(("- tuning_experiment_rows: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.tuning_experiment_rows))
        $lines.Add(("- tester_pass_rows: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.tester_pass_rows))
        $lines.Add(("- tester_positive_pass_count: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.tester_positive_pass_count))
        $lines.Add(("- best_tester_pass_realized_pnl: {0}" -f $report.lab_health.near_profit_optimization.active_sandbox.best_tester_pass_realized_pnl))
        if (@($report.lab_health.near_profit_optimization.active_sandbox.best_tester_pass_inputs).Count -gt 0) {
            $lines.Add(("- best_tester_pass_inputs: {0}" -f ((@($report.lab_health.near_profit_optimization.active_sandbox.best_tester_pass_inputs) -join "; "))))
        }
    }
}
else {
    $lines.Add("- near-profit lane status not available")
}
$lines.Add("")
$lines.Add("## QDM Custom Pilot")
$lines.Add("")
if ($null -ne $report.lab_health.qdm_missing_supported_sync) {
    $lines.Add(("- missing_sync_state: {0}" -f $report.lab_health.qdm_missing_supported_sync.state))
    $lines.Add(("- missing_sync_started: {0}" -f $report.lab_health.qdm_missing_supported_sync.sync_started))
    $lines.Add(("- missing_sync_missing_count: {0}" -f $report.lab_health.qdm_missing_supported_sync.missing_count))
    $lines.Add(("- missing_sync_blocked_count: {0}" -f $report.lab_health.qdm_missing_supported_sync.blocked_count))
    $lines.Add(("- missing_sync_unsupported_count: {0}" -f $report.lab_health.qdm_missing_supported_sync.unsupported_count))
    $lines.Add(("- missing_sync_symbols: {0}" -f ($report.lab_health.qdm_missing_supported_sync.missing_symbols -join ", ")))
    $lines.Add(("- missing_sync_current_focus: {0}" -f $report.lab_health.qdm_missing_supported_sync.current_focus))
}
else {
    $lines.Add("- qdm missing-supported sync status not available")
}
if ($null -ne $report.lab_health.qdm_custom_symbol_pilot) {
    $lines.Add(("- import_status: {0}" -f $report.lab_health.qdm_custom_symbol_pilot.run_status))
    $lines.Add(("- import_succeeded: {0}" -f $report.lab_health.qdm_custom_symbol_pilot.import_succeeded))
    $lines.Add(("- custom_symbol: {0}" -f $report.lab_health.qdm_custom_symbol_pilot.custom_symbol))
    $lines.Add(("- import_message: {0}" -f $report.lab_health.qdm_custom_symbol_pilot.import_message))
}
else {
    $lines.Add("- qdm custom-symbol import status not available")
}
if ($null -ne $report.lab_health.qdm_custom_symbol_smoke) {
    $lines.Add(("- smoke_run_id: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.run_id))
    $lines.Add(("- smoke_result_label: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.result_label))
    $lines.Add(("- smoke_requested_model: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.requested_model))
    $lines.Add(("- smoke_model: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.model))
    $lines.Add(("- smoke_model_normalized_for_qdm_custom_symbol: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.model_normalized_for_qdm_custom_symbol))
    $lines.Add(("- smoke_final_balance: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.final_balance))
    $lines.Add(("- smoke_duration: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.test_duration))
}
else {
    $lines.Add("- qdm custom-symbol smoke status not available")
}
if ($null -ne $report.lab_health.qdm_custom_symbol_pilot_registry) {
    $lines.Add(("- registry_total_symbols: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_registry.total_symbols))
    $lines.Add(("- registry_successful_smokes: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_registry.successful_smokes))
    $lines.Add(("- registry_normalized_models: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_registry.normalized_models))
    $lines.Add(("- registry_symbols: {0}" -f ($report.lab_health.qdm_custom_symbol_pilot_registry.symbols -join ", ")))
}
else {
    $lines.Add("- qdm custom-symbol pilot registry not available")
}
if ($null -ne $report.lab_health.qdm_custom_symbol_pilot_batch) {
    $lines.Add(("- batch_state: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_batch.state))
    $lines.Add(("- batch_successful_count: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_batch.successful_count))
    $lines.Add(("- batch_failed_count: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_batch.failed_count))
    $lines.Add(("- batch_selected_symbol_source: {0}" -f $report.lab_health.qdm_custom_symbol_pilot_batch.selected_symbol_source))
    $lines.Add(("- batch_symbols: {0}" -f ($report.lab_health.qdm_custom_symbol_pilot_batch.selected_symbols -join ", ")))
}
else {
    $lines.Add("- qdm custom-symbol pilot batch not available")
}
$lines.Add("")
$lines.Add("## Consistency")
$lines.Add("")
$lines.Add(("- mt5_retest_queue_fresh: {0}" -f $report.consistency.mt5_retest_queue_fresh))
$lines.Add(("- mt5_retest_queue_consistent_with_tester: {0}" -f $report.consistency.mt5_retest_queue_consistent_with_tester))
$lines.Add(("- near_profit_optimization_queue_fresh: {0}" -f $report.consistency.near_profit_optimization_queue_fresh))
$lines.Add(("- research_export_manifest_fresh: {0}" -f $report.consistency.research_export_manifest_fresh))
$lines.Add("")
$lines.Add("## Research Pipeline")
$lines.Add("")
$lines.Add(("- manifest_present: {0}" -f $report.research_pipeline.manifest_present))
$lines.Add(("- export_fresh: {0}" -f $report.research_pipeline.export_fresh))
$lines.Add(("- tester_telemetry_rows: {0}" -f $report.research_pipeline.tester_telemetry_rows))
$lines.Add(("- tester_pass_frame_rows: {0}" -f $report.research_pipeline.tester_pass_frame_rows))
$lines.Add(("- tester_summary_rows: {0}" -f $report.research_pipeline.tester_summary_rows))
$lines.Add(("- tester_knowledge_rows: {0}" -f $report.research_pipeline.tester_knowledge_rows))
$lines.Add(("- optimization_telemetry_visible: {0}" -f $report.research_pipeline.optimization_telemetry_visible))
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
