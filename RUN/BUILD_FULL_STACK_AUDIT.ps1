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
$supervisorScopeAuditScript = Join-Path $ProjectRoot "RUN\BUILD_SUPERVISOR_SCOPE_AUDIT.ps1"
$learningArtifactInventoryScript = Join-Path $ProjectRoot "RUN\BUILD_LEARNING_ARTIFACT_INVENTORY.ps1"
$mt5FirstWaveServerParityAuditScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_SERVER_PARITY_AUDIT.ps1"
$mt5FirstWaveRuntimeActivityAuditScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1"
$nearProfitQueueStatusScript = Join-Path $ProjectRoot "RUN\SYNC_NEAR_PROFIT_OPTIMIZATION_QUEUE_STATUS.ps1"
$learningHotPathPath = Join-Path $opsRoot "learning_hot_path_latest.json"

foreach ($path in @(
    $runtimeArtifactAuditScript,
    $runtimePersistenceAuditScript,
    $runtimeLogRotationScript,
    $repoHygieneScript,
    $supervisorScopeAuditScript,
    $learningArtifactInventoryScript,
    $mt5FirstWaveServerParityAuditScript,
    $mt5FirstWaveRuntimeActivityAuditScript,
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
function Invoke-GitStatusSafe {
    param([string]$RepoRoot)

    $command = 'git -c core.safecrlf=false -C "' + $RepoRoot + '" status --short 2>nul'
    return @(
        & cmd.exe /d /c $command |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                ($_ -notmatch 'could not open directory .+\.pytest_cache')
            }
    )
}
try {
    $gitStatusLines = @(Invoke-GitStatusSafe -RepoRoot $ProjectRoot)
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
Invoke-JsonAuditTool -ScriptPath $supervisorScopeAuditScript -Parameters @{
    ProjectRoot = $ProjectRoot
    OutputRoot = $opsRoot
}
Invoke-JsonAuditTool -ScriptPath $learningArtifactInventoryScript -Parameters @{
    ProjectRoot = $ProjectRoot
    ResearchRoot = $ResearchRoot
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
$supervisorScopeAudit = Read-JsonFile -Path (Join-Path $opsRoot "supervisor_scope_audit_latest.json")
$learningArtifactInventory = Read-JsonFile -Path (Join-Path $opsRoot "learning_artifact_inventory_latest.json")
$learningHotPath = Read-JsonFile -Path $learningHotPathPath

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
    Get-FileFreshness -Label "qdm_custom_symbol_first_wave" -Path (Join-Path $opsRoot "qdm_custom_symbol_first_wave_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "qdm_custom_symbol_realism_audit" -Path (Join-Path $opsRoot "qdm_custom_symbol_realism_audit_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "mt5_first_wave_server_parity" -Path (Join-Path $opsRoot "mt5_first_wave_server_parity_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "mt5_first_wave_runtime_activity" -Path (Join-Path $opsRoot "mt5_first_wave_runtime_activity_latest.json") -ThresholdSeconds 1800
    Get-FileFreshness -Label "learning_artifact_inventory" -Path (Join-Path $opsRoot "learning_artifact_inventory_latest.json") -ThresholdSeconds 1800
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
$qdmCustomFirstWave = Read-JsonFile -Path (Join-Path $opsRoot "qdm_custom_symbol_first_wave_latest.json")
$qdmCustomRealismAuditScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_CUSTOM_SYMBOL_REALISM_AUDIT.ps1"
if (Test-Path -LiteralPath $qdmCustomRealismAuditScript) {
    Invoke-JsonAuditTool -ScriptPath $qdmCustomRealismAuditScript -Parameters @{ ProjectRoot = $ProjectRoot }
}
$qdmCustomRealismAudit = Read-JsonFile -Path (Join-Path $opsRoot "qdm_custom_symbol_realism_audit_latest.json")
if (Test-Path -LiteralPath $mt5FirstWaveServerParityAuditScript) {
    Invoke-JsonAuditTool -ScriptPath $mt5FirstWaveServerParityAuditScript -Parameters @{ ProjectRoot = $ProjectRoot }
}
$mt5FirstWaveServerParityAudit = Read-JsonFile -Path (Join-Path $opsRoot "mt5_first_wave_server_parity_latest.json")
if (Test-Path -LiteralPath $mt5FirstWaveRuntimeActivityAuditScript) {
    Invoke-JsonAuditTool -ScriptPath $mt5FirstWaveRuntimeActivityAuditScript -Parameters @{ ProjectRoot = $ProjectRoot }
}
$mt5FirstWaveRuntimeActivityAudit = Read-JsonFile -Path (Join-Path $opsRoot "mt5_first_wave_runtime_activity_latest.json")
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

$learningHotPathVerdict = [string](Get-SafeObjectValue -Object $learningHotPath -PropertyName "verdict" -Default "")
$learningHotPathSummary = Get-SafeObjectValue -Object $learningHotPath -PropertyName "summary" -Default $null
$learningHotWaitingCount = [int](Get-SafeObjectValue -Object $learningHotPathSummary -PropertyName "waiting_hot_count" -Default 0)
$learningHotOversizedCount = [int](Get-SafeObjectValue -Object $learningHotPathSummary -PropertyName "oversized_count" -Default 0)
$runtimeLogsUnderControl = (
    ($rotationCandidateCount -eq 0) -and (
        ($persistenceOvergrowthCount -eq 0) -or
        (
            $learningHotPathVerdict -eq "GORACY_SZLAK_AKTYWNY" -and
            $learningHotWaitingCount -gt 0 -and
            $learningHotOversizedCount -eq $learningHotWaitingCount
        )
    )
)

$wrapperState = [ordered]@{
    supervisor = ((Get-WrapperCount -Pattern "*autonomous_90p_supervisor_wrapper_*") -gt 0)
    archiver = ((Get-WrapperCount -Pattern "*local_operator_archiver_wrapper_*") -gt 0)
    qdm_weakest = ((Get-WrapperCount -Pattern "*qdm_weakest_sync_wrapper_*") -gt 0)
    ml = (
        ((Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0) -or
        (@($freshness | Where-Object { $_.label -eq "ml_tuning_hints" -and $_.fresh }).Count -gt 0)
    )
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

$gitSystemDirtyCount = if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'system_core' -Default 0) } else { $gitDirtyCount }
$gitAuxiliaryDirtyCount = if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'auxiliary_bridge' -Default 0) } else { 0 }
$systemBoundaryClean = ($null -ne $supervisorScopeAudit -and [string](Get-SafeObjectValue -Object $supervisorScopeAudit -PropertyName 'verdict' -Default "") -eq "SUPERVISOR_SCOPE_BOUNDARY_OK")
$learningArtifactInventoryVerdict = if ($null -ne $learningArtifactInventory) { [string](Get-SafeObjectValue -Object $learningArtifactInventory -PropertyName 'verdict' -Default "") } else { "" }
$learningArtifactCriticalMissingCount = if ($null -ne $learningArtifactInventory) { [int](Get-SafeObjectValue -Object $learningArtifactInventory.summary -PropertyName 'critical_missing_count' -Default 0) } else { 0 }
$learningArtifactCriticalStaleCount = if ($null -ne $learningArtifactInventory) { [int](Get-SafeObjectValue -Object $learningArtifactInventory.summary -PropertyName 'critical_stale_count' -Default 0) } else { 0 }
$learningArtifactRetentionPendingCount = if ($null -ne $learningArtifactInventory) { [int](Get-SafeObjectValue -Object $learningArtifactInventory.summary -PropertyName 'retention_pending_count' -Default 0) } else { 0 }
$learningArtifactLiveLogStaleSymbolCount = if ($null -ne $learningArtifactInventory) { [int](Get-SafeObjectValue -Object $learningArtifactInventory.summary -PropertyName 'live_log_stale_symbol_count' -Default 0) } else { 0 }

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
    $runtimeLogsUnderControl -and
    ($gitSystemDirtyCount -eq 0) -and
    $systemBoundaryClean -and
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
elseif (-not $runtimeLogsUnderControl) {
    $releaseVerdict = "ROTATE_RUNTIME_LOGS_FIRST"
}
elseif ($gitSystemDirtyCount -gt 0) {
    $releaseVerdict = "CHECKPOINT_CODE_FIRST"
}
elseif ($learningArtifactCriticalMissingCount -gt 0 -or $learningArtifactCriticalStaleCount -gt 0) {
    $releaseVerdict = "REFRESH_LEARNING_ARTIFACTS_FIRST"
}
elseif (-not $systemBoundaryClean) {
    $releaseVerdict = "SEPARATE_SYSTEM_AND_BRIDGE_FIRST"
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
                property_mirror_message = $(if ($qdmCustomPilot.PSObject.Properties.Name -contains "property_mirror_message") { $qdmCustomPilot.property_mirror_message } else { $null })
                session_mirror_message = $(if ($qdmCustomPilot.PSObject.Properties.Name -contains "session_mirror_message") { $qdmCustomPilot.session_mirror_message } else { $null })
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
                learning_sample_count = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'learning_sample_count' -Default $null)
                requested_model = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'requested_model' -Default $null)
                model = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'model' -Default $null)
                model_normalized_for_qdm_custom_symbol = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'model_normalized_for_qdm_custom_symbol' -Default $false)
                property_mirror_message = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'property_mirror_message' -Default $null)
                session_mirror_message = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'session_mirror_message' -Default $null)
                trust_state = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'trust_state' -Default $null)
                trust_reason = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'trust_reason' -Default $null)
                observation_data_state = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'observation_data_state' -Default $null)
                paper_learning_state = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'paper_learning_state' -Default $null)
                paper_open_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'paper_open_rows' -Default $null)
                paper_score_gate_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'paper_score_gate_rows' -Default $null)
                candidate_signal_rows_total = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'candidate_signal_rows_total' -Default $null)
                onnx_observation_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'onnx_observation_rows' -Default $null)
                learning_observation_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeLatest -PropertyName 'learning_observation_rows' -Default $null)
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
                property_mirror_message = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'property_mirror_message' -Default $null)
                session_mirror_message = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'session_mirror_message' -Default $null)
                trust_state = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'trust_state' -Default $null)
                trust_reason = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'trust_reason' -Default $null)
                observation_data_state = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'observation_data_state' -Default $null)
                paper_learning_state = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'paper_learning_state' -Default $null)
                paper_open_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'paper_open_rows' -Default $null)
                paper_score_gate_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'paper_score_gate_rows' -Default $null)
                candidate_signal_rows_total = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'candidate_signal_rows_total' -Default $null)
                onnx_observation_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'onnx_observation_rows' -Default $null)
                learning_observation_rows = $(Get-SafeObjectValue -Object $qdmCustomSmokeSummary -PropertyName 'learning_observation_rows' -Default $null)
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
        qdm_custom_symbol_first_wave = if ($null -ne $qdmCustomFirstWave) {
            [ordered]@{
                state = $qdmCustomFirstWave.state
                universe_version = $(Get-SafeObjectValue -Object $qdmCustomFirstWave -PropertyName 'universe_version' -Default $null)
                symbol_scope = $(Get-SafeObjectValue -Object $qdmCustomFirstWave -PropertyName 'symbol_scope' -Default $null)
                successful_count = $qdmCustomFirstWave.successful_count
                failed_count = $qdmCustomFirstWave.failed_count
                selected_symbols = @($qdmCustomFirstWave.selected_symbols)
            }
        } else { $null }
        qdm_custom_symbol_realism = if ($null -ne $qdmCustomRealismAudit) {
            [ordered]@{
                verdict = $qdmCustomRealismAudit.verdict
                selected_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'selected_count' -Default 0)
                realism_ready_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'realism_ready_count' -Default 0)
                broker_mirror_ready_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'broker_mirror_ready_count' -Default 0)
                property_mirror_ready_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'property_mirror_ready_count' -Default 0)
                session_mirror_ready_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'session_mirror_ready_count' -Default 0)
                smoke_ready_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'smoke_ready_count' -Default 0)
                learning_ready_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'learning_ready_count' -Default 0)
                current_run_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'current_run_count' -Default 0)
                backfilled_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'backfilled_count' -Default 0)
                partial_count = $(Get-SafeObjectValue -Object $qdmCustomRealismAudit.summary -PropertyName 'partial_count' -Default 0)
            }
        } else { $null }
        mt5_first_wave_server_parity = if ($null -ne $mt5FirstWaveServerParityAudit) {
            [ordered]@{
                verdict = $mt5FirstWaveServerParityAudit.verdict
                near_server_count = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'near_server_count' -Default 0)
                partial_count = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'partial_count' -Default 0)
                blocked_count = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'blocked_count' -Default 0)
                truth_hook_ready_count = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'truth_hook_ready_count' -Default 0)
                live_truth_ready_count = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'live_truth_ready_count' -Default 0)
                local_model_ready_count = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'local_model_ready_count' -Default 0)
                migration_confirmed = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'migration_confirmed' -Default $false)
                paper_live_sync_ok = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'paper_live_sync_ok' -Default $false)
                runtime_profile_observed = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'runtime_profile_observed' -Default $null)
                runtime_profile_target = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'runtime_profile_target' -Default $null)
                runtime_profile_match = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'runtime_profile_match' -Default $false)
                capital_isolation_ready = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'capital_isolation_ready' -Default $false)
                truth_chain_live_ready = $(Get-SafeObjectValue -Object $mt5FirstWaveServerParityAudit.summary -PropertyName 'truth_chain_live_ready' -Default $false)
            }
        } else { $null }
        mt5_first_wave_runtime_activity = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) {
            [ordered]@{
                verdict = $mt5FirstWaveRuntimeActivityAudit.verdict
                live_log_fresh_count = $(Get-SafeObjectValue -Object $mt5FirstWaveRuntimeActivityAudit.summary -PropertyName 'live_log_fresh_count' -Default 0)
                truth_live_symbol_count = $(Get-SafeObjectValue -Object $mt5FirstWaveRuntimeActivityAudit.summary -PropertyName 'truth_live_symbol_count' -Default 0)
                outside_trade_window_count = $(Get-SafeObjectValue -Object $mt5FirstWaveRuntimeActivityAudit.summary -PropertyName 'outside_trade_window_count' -Default 0)
                tuning_freeze_count = $(Get-SafeObjectValue -Object $mt5FirstWaveRuntimeActivityAudit.summary -PropertyName 'tuning_freeze_count' -Default 0)
                weak_signal_count = $(Get-SafeObjectValue -Object $mt5FirstWaveRuntimeActivityAudit.summary -PropertyName 'weak_signal_count' -Default 0)
                recent_paper_open_count = $(Get-SafeObjectValue -Object $mt5FirstWaveRuntimeActivityAudit.summary -PropertyName 'recent_paper_open_count' -Default 0)
            }
        } else { $null }
        learning_artifact_inventory = if ($null -ne $learningArtifactInventory) {
            [ordered]@{
                verdict = $learningArtifactInventoryVerdict
                critical_missing_count = $learningArtifactCriticalMissingCount
                critical_stale_count = $learningArtifactCriticalStaleCount
                retention_pending_count = $learningArtifactRetentionPendingCount
                live_log_stale_symbol_count = $learningArtifactLiveLogStaleSymbolCount
            }
        } else { $null }
    }
    freshness = @($freshness)
    cleanliness = [ordered]@{
        git_dirty_count = $gitDirtyCount
        git_tracked_count = $gitTrackedCount
        git_untracked_count = $gitUntrackedCount
        git_system_core_dirty_count = $gitSystemDirtyCount
        git_auxiliary_bridge_dirty_count = $gitAuxiliaryDirtyCount
        git_dirty_head = @($gitStatusLines | Select-Object -First 20)
        repo_hygiene_verdict = $(if ($null -ne $repoHygiene) { $repoHygiene.verdict } else { $null })
        git_code_dirty_count = $(if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'code_or_logic' -Default 0) } else { 0 })
        git_generated_timestamp_only_count = $(if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'generated_timestamp_only' -Default 0) } else { 0 })
        git_generated_other_count = $(if ($null -ne $repoHygiene) { [int](Get-SafeObjectValue -Object $repoHygiene.counts -PropertyName 'generated_other' -Default 0) } else { 0 })
        runtime_unexpected_dir_count = $runtimeUnexpectedTotal
        rotation_candidate_count = $rotationCandidateCount
        rotation_applied_count = $rotationAppliedCount
        persistence_overgrowth_count = $persistenceOvergrowthCount
        learning_hot_path_verdict = $learningHotPathVerdict
        learning_hot_waiting_count = $learningHotWaitingCount
        runtime_logs_under_control = $runtimeLogsUnderControl
        learning_artifact_inventory_verdict = $learningArtifactInventoryVerdict
        learning_artifact_critical_missing_count = $learningArtifactCriticalMissingCount
        learning_artifact_critical_stale_count = $learningArtifactCriticalStaleCount
        learning_artifact_retention_pending_count = $learningArtifactRetentionPendingCount
        learning_artifact_live_log_stale_symbol_count = $learningArtifactLiveLogStaleSymbolCount
        supervisor_scope_verdict = $(if ($null -ne $supervisorScopeAudit) { $supervisorScopeAudit.verdict } else { $null })
        supervisor_scope_contaminated_count = $(if ($null -ne $supervisorScopeAudit) { [int](Get-SafeObjectValue -Object $supervisorScopeAudit.summary -PropertyName 'contaminated_count' -Default 0) } else { 0 })
    }
    runtime_audits = [ordered]@{
        artifact_audit = $runtimeArtifactAudit
        persistence_audit = $runtimePersistenceAudit
        log_rotation = $runtimeLogRotation
        learning_hot_path = $learningHotPath
        repo_hygiene = $repoHygiene
        supervisor_scope = $supervisorScopeAudit
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
        runtime_logs_rotated = $runtimeLogsUnderControl
        runtime_logs_under_control = $runtimeLogsUnderControl
        code_checkpoint_clean = ($gitSystemDirtyCount -eq 0)
        system_aux_boundary_clean = $systemBoundaryClean
        verification_clean = $verificationClean
        lab_busy = $labBusy
        first_wave_server_parity_verdict = $(if ($null -ne $mt5FirstWaveServerParityAudit) { $mt5FirstWaveServerParityAudit.verdict } else { $null })
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
$lines.Add(("- system_aux_boundary_clean: {0}" -f $report.release_gate.system_aux_boundary_clean))
$lines.Add(("- verification_clean: {0}" -f $report.release_gate.verification_clean))
$lines.Add(("- lab_busy: {0}" -f $report.release_gate.lab_busy))
$lines.Add("")
$lines.Add("## Cleanliness")
$lines.Add("")
$lines.Add(("- git_dirty_count: {0}" -f $report.cleanliness.git_dirty_count))
$lines.Add(("- git_system_core_dirty_count: {0}" -f $report.cleanliness.git_system_core_dirty_count))
$lines.Add(("- git_auxiliary_bridge_dirty_count: {0}" -f $report.cleanliness.git_auxiliary_bridge_dirty_count))
$lines.Add(("- repo_hygiene_verdict: {0}" -f $report.cleanliness.repo_hygiene_verdict))
$lines.Add(("- git_code_dirty_count: {0}" -f $report.cleanliness.git_code_dirty_count))
$lines.Add(("- git_generated_timestamp_only_count: {0}" -f $report.cleanliness.git_generated_timestamp_only_count))
$lines.Add(("- git_generated_other_count: {0}" -f $report.cleanliness.git_generated_other_count))
$lines.Add(("- learning_artifact_inventory_verdict: {0}" -f $report.cleanliness.learning_artifact_inventory_verdict))
$lines.Add(("- learning_artifact_critical_missing_count: {0}" -f $report.cleanliness.learning_artifact_critical_missing_count))
$lines.Add(("- learning_artifact_critical_stale_count: {0}" -f $report.cleanliness.learning_artifact_critical_stale_count))
$lines.Add(("- learning_artifact_retention_pending_count: {0}" -f $report.cleanliness.learning_artifact_retention_pending_count))
$lines.Add(("- learning_artifact_live_log_stale_symbol_count: {0}" -f $report.cleanliness.learning_artifact_live_log_stale_symbol_count))
$lines.Add(("- supervisor_scope_verdict: {0}" -f $report.cleanliness.supervisor_scope_verdict))
$lines.Add(("- supervisor_scope_contaminated_count: {0}" -f $report.cleanliness.supervisor_scope_contaminated_count))
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
    if (-not [string]::IsNullOrWhiteSpace([string]$report.lab_health.qdm_custom_symbol_pilot.property_mirror_message)) {
        $lines.Add(("- property_mirror_message: {0}" -f $report.lab_health.qdm_custom_symbol_pilot.property_mirror_message))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$report.lab_health.qdm_custom_symbol_pilot.session_mirror_message)) {
        $lines.Add(("- session_mirror_message: {0}" -f $report.lab_health.qdm_custom_symbol_pilot.session_mirror_message))
    }
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
    if (-not [string]::IsNullOrWhiteSpace([string]$report.lab_health.qdm_custom_symbol_smoke.property_mirror_message)) {
        $lines.Add(("- smoke_property_mirror_message: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.property_mirror_message))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$report.lab_health.qdm_custom_symbol_smoke.session_mirror_message)) {
        $lines.Add(("- smoke_session_mirror_message: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.session_mirror_message))
    }
    $lines.Add(("- smoke_final_balance: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.final_balance))
    $lines.Add(("- smoke_duration: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.test_duration))
    $lines.Add(("- smoke_trust: {0} / {1}" -f $report.lab_health.qdm_custom_symbol_smoke.trust_state, $report.lab_health.qdm_custom_symbol_smoke.trust_reason))
    $lines.Add(("- smoke_observation_data_state: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.observation_data_state))
    $lines.Add(("- smoke_paper_learning_state: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.paper_learning_state))
    $lines.Add(("- smoke_learning_sample_count: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.learning_sample_count))
    $lines.Add(("- smoke_paper_open_rows: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.paper_open_rows))
    $lines.Add(("- smoke_paper_score_gate_rows: {0}" -f $report.lab_health.qdm_custom_symbol_smoke.paper_score_gate_rows))
    $lines.Add(("- smoke_observation_rows candidate/onnx/learning: {0}/{1}/{2}" -f $report.lab_health.qdm_custom_symbol_smoke.candidate_signal_rows_total, $report.lab_health.qdm_custom_symbol_smoke.onnx_observation_rows, $report.lab_health.qdm_custom_symbol_smoke.learning_observation_rows))
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
if ($null -ne $report.lab_health.qdm_custom_symbol_first_wave) {
    $lines.Add(("- first_wave_state: {0}" -f $report.lab_health.qdm_custom_symbol_first_wave.state))
    $lines.Add(("- first_wave_universe_version: {0}" -f $report.lab_health.qdm_custom_symbol_first_wave.universe_version))
    $lines.Add(("- first_wave_successful_count: {0}" -f $report.lab_health.qdm_custom_symbol_first_wave.successful_count))
    $lines.Add(("- first_wave_failed_count: {0}" -f $report.lab_health.qdm_custom_symbol_first_wave.failed_count))
    $lines.Add(("- first_wave_symbols: {0}" -f ($report.lab_health.qdm_custom_symbol_first_wave.selected_symbols -join ", ")))
}
else {
    $lines.Add("- qdm custom-symbol first-wave status not available")
}
if ($null -ne $report.lab_health.qdm_custom_symbol_realism) {
    $lines.Add(("- realism_verdict: {0}" -f $report.lab_health.qdm_custom_symbol_realism.verdict))
    $lines.Add(("- realism_ready_count: {0}/{1}" -f $report.lab_health.qdm_custom_symbol_realism.realism_ready_count, $report.lab_health.qdm_custom_symbol_realism.selected_count))
    $lines.Add(("- realism_broker_mirror_ready_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.broker_mirror_ready_count))
    $lines.Add(("- realism_property_mirror_ready_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.property_mirror_ready_count))
    $lines.Add(("- realism_session_mirror_ready_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.session_mirror_ready_count))
    $lines.Add(("- realism_smoke_ready_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.smoke_ready_count))
    $lines.Add(("- realism_learning_ready_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.learning_ready_count))
    $lines.Add(("- realism_current_run_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.current_run_count))
    $lines.Add(("- realism_backfilled_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.backfilled_count))
    $lines.Add(("- realism_partial_count: {0}" -f $report.lab_health.qdm_custom_symbol_realism.partial_count))
}
else {
    $lines.Add("- qdm custom-symbol realism audit not available")
}
if ($null -ne $report.lab_health.mt5_first_wave_server_parity) {
    $lines.Add(("- first_wave_server_parity_verdict: {0}" -f $report.lab_health.mt5_first_wave_server_parity.verdict))
    $lines.Add(("- first_wave_near_server_count: {0}" -f $report.lab_health.mt5_first_wave_server_parity.near_server_count))
    $lines.Add(("- first_wave_partial_count: {0}" -f $report.lab_health.mt5_first_wave_server_parity.partial_count))
    $lines.Add(("- first_wave_blocked_count: {0}" -f $report.lab_health.mt5_first_wave_server_parity.blocked_count))
    $lines.Add(("- first_wave_truth_hook_ready_count: {0}" -f $report.lab_health.mt5_first_wave_server_parity.truth_hook_ready_count))
    $lines.Add(("- first_wave_live_truth_ready_count: {0}" -f $report.lab_health.mt5_first_wave_server_parity.live_truth_ready_count))
    $lines.Add(("- first_wave_local_model_ready_count: {0}" -f $report.lab_health.mt5_first_wave_server_parity.local_model_ready_count))
    $lines.Add(("- first_wave_migration_confirmed: {0}" -f $report.lab_health.mt5_first_wave_server_parity.migration_confirmed))
    $lines.Add(("- first_wave_paper_live_sync_ok: {0}" -f $report.lab_health.mt5_first_wave_server_parity.paper_live_sync_ok))
    $lines.Add(("- first_wave_runtime_profile_observed: {0}" -f $report.lab_health.mt5_first_wave_server_parity.runtime_profile_observed))
    $lines.Add(("- first_wave_runtime_profile_target: {0}" -f $report.lab_health.mt5_first_wave_server_parity.runtime_profile_target))
    $lines.Add(("- first_wave_runtime_profile_match: {0}" -f $report.lab_health.mt5_first_wave_server_parity.runtime_profile_match))
    $lines.Add(("- first_wave_capital_isolation_ready: {0}" -f $report.lab_health.mt5_first_wave_server_parity.capital_isolation_ready))
    $lines.Add(("- first_wave_truth_chain_live_ready: {0}" -f $report.lab_health.mt5_first_wave_server_parity.truth_chain_live_ready))
}
else {
    $lines.Add("- first-wave server parity audit not available")
}
if ($null -ne $report.lab_health.mt5_first_wave_runtime_activity) {
    $lines.Add(("- first_wave_runtime_activity_verdict: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.verdict))
    $lines.Add(("- first_wave_runtime_live_log_fresh_count: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.live_log_fresh_count))
    $lines.Add(("- first_wave_runtime_truth_live_symbol_count: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.truth_live_symbol_count))
    $lines.Add(("- first_wave_runtime_outside_trade_window_count: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.outside_trade_window_count))
    $lines.Add(("- first_wave_runtime_tuning_freeze_count: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.tuning_freeze_count))
    $lines.Add(("- first_wave_runtime_weak_signal_count: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.weak_signal_count))
    $lines.Add(("- first_wave_runtime_recent_paper_open_count: {0}" -f $report.lab_health.mt5_first_wave_runtime_activity.recent_paper_open_count))
}
else {
    $lines.Add("- first-wave runtime activity audit not available")
}
$lines.Add("")
$lines.Add("## Learning Artifact Inventory")
$lines.Add("")
if ($null -ne $report.lab_health.learning_artifact_inventory) {
    $lines.Add(("- verdict: {0}" -f $report.lab_health.learning_artifact_inventory.verdict))
    $lines.Add(("- critical_missing_count: {0}" -f $report.lab_health.learning_artifact_inventory.critical_missing_count))
    $lines.Add(("- critical_stale_count: {0}" -f $report.lab_health.learning_artifact_inventory.critical_stale_count))
    $lines.Add(("- retention_pending_count: {0}" -f $report.lab_health.learning_artifact_inventory.retention_pending_count))
    $lines.Add(("- live_log_stale_symbol_count: {0}" -f $report.lab_health.learning_artifact_inventory.live_log_stale_symbol_count))
}
else {
    $lines.Add("- learning artifact inventory not available")
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
