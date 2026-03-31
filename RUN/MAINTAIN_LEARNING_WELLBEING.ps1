param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$OpsSnapshotKeepCount = 288,
    [int]$OpsStatusKeepCount = 192,
    [int]$OpsLogKeepCount = 8,
    [int]$OpsRetentionDays = 3,
    [int]$RuntimeArchiveRetentionDays = 4,
    [int]$RuntimeArchiveKeepRecentPerKind = 2,
    [ValidateSet("Off", "Safe", "Controlled")]
    [string]$AutoHealLevel = "Off",
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DirectoryIfMissing {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Force -Path $Path | Out-Null
    }
}

function Read-JsonSafe {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Get-ManifestState {
    param([string]$ManifestPath)

    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        return [pscustomobject]@{
            exists = $false
            age_seconds = $null
            threshold_seconds = 1800
            fresh = $false
        }
    }

    $item = Get-Item -LiteralPath $ManifestPath
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    return [pscustomobject]@{
        exists = $true
        age_seconds = $ageSeconds
        threshold_seconds = 1800
        fresh = ($ageSeconds -le 1800)
    }
}

function Get-NormalizedArchiveLeafName {
    param([string]$Name)

    if ($Name -match '^\d+_(.+)$') {
        return $Matches[1]
    }

    return $Name
}

function Get-SymbolFromArchivePath {
    param(
        [string]$LogsRoot,
        [string]$FullName
    )

    $escaped = [regex]::Escape($LogsRoot.TrimEnd('\'))
    if ($FullName -match ("^{0}\\([^\\]+)\\archive\\" -f $escaped)) {
        return $Matches[1]
    }

    return ""
}

function Remove-EmptyDirectories {
    param([string]$RootPath)

    $removed = 0
    if (-not (Test-Path -LiteralPath $RootPath)) {
        return $removed
    }

    $dirs = @(
        Get-ChildItem -LiteralPath $RootPath -Directory -Recurse -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending
    )
    foreach ($dir in $dirs) {
        $children = @(Get-ChildItem -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue)
        if ($children.Count -eq 0) {
            Remove-Item -LiteralPath $dir.FullName -Force -ErrorAction SilentlyContinue
            $removed++
        }
    }

    return $removed
}

function Invoke-JsonScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    return (& $ScriptPath @Parameters)
}

function Resolve-AutoHealLevel {
    param(
        [string]$ProjectRoot,
        [string]$RequestedLevel,
        [bool]$LegacyApply
    )

    if ($LegacyApply) {
        return "Safe"
    }

    if (-not [string]::IsNullOrWhiteSpace($RequestedLevel) -and $RequestedLevel -ne "Off") {
        return $RequestedLevel
    }

    $policyPath = Join-Path $ProjectRoot "CONFIG\supervisor_autoheal_policy_v1.json"
    if (Test-Path -LiteralPath $policyPath) {
        $policy = Read-JsonSafe -Path $policyPath
        $policyDefault = [string](Get-OptionalValue -Object $policy -Name "default_level" -Default "Off")
        if ($policyDefault -in @("Off", "Safe", "Controlled")) {
            return $policyDefault
        }
    }

    return "Off"
}

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $Default
    }

    try {
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) {
            return $Default
        }

        return $property.Value
    }
    catch {
        return $Default
    }
}

function Get-OptionalNumber {
    param(
        [object]$Object,
        [string]$Name,
        [double]$Default = 0
    )

    $value = Get-OptionalValue -Object $Object -Name $Name -Default $null
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        return $Default
    }

    return [double]$value
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

function Resolve-PythonExecutable {
    param([string]$PreferredPath)

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return $PreferredPath
    }

    $command = Get-Command python -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        return $command.Source
    }

    return $null
}

function Invoke-OptionalPythonHelper {
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string[]]$Arguments = @()
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return
    }

    $pythonExe = Resolve-PythonExecutable -PreferredPath $researchPython
    if ([string]::IsNullOrWhiteSpace($pythonExe)) {
        return
    }

    try {
        & $pythonExe $ScriptPath @Arguments | Out-Null
    }
    catch {
        Write-Verbose ("Optional helper failed: {0} -> {1}" -f $ScriptPath, $_.Exception.Message)
    }
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$logsRoot = Join-Path $CommonRoot "logs"
$reportsRoot = Join-Path $ResearchRoot "reports"
$researchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
$commonStateRoot = Split-Path -Path $CommonRoot -Parent
$manifestPath = Join-Path $reportsRoot "research_export_manifest_latest.json"
$pathHygieneScript = Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_PATH_HYGIENE.ps1"
$hotPathScript = Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_SUPERVISOR_HOT_PATH.ps1"
$pathHygienePath = Join-Path $opsRoot "learning_path_hygiene_latest.json"
$hotPathPath = Join-Path $opsRoot "learning_hot_path_latest.json"
$runtimeLatestScrubScript = Join-Path $ProjectRoot "RUN\SCRUB_STALE_RUNTIME_LATESTS.ps1"
$runtimeLatestScrubPath = Join-Path $opsRoot "runtime_latest_scrub_latest.json"
$learningArtifactInventoryScript = Join-Path $ProjectRoot "RUN\BUILD_LEARNING_ARTIFACT_INVENTORY.ps1"
$learningArtifactInventoryPath = Join-Path $opsRoot "learning_artifact_inventory_latest.json"
$globalTeacherCohortAuditScript = Join-Path $ProjectRoot "RUN\BUILD_GLOBAL_TEACHER_COHORT_ACTIVITY_AUDIT.ps1"
$globalTeacherCohortAuditPath = Join-Path $opsRoot "global_teacher_cohort_activity_latest.json"
$firstWaveLessonClosureAuditPath = Join-Path $opsRoot "first_wave_lesson_closure_latest.json"
$postMigrationStartupAuditPath = Join-Path $opsRoot "post_migration_startup_audit_latest.json"
$normalizeScript = Join-Path $ProjectRoot "RUN\NORMALIZE_LEARNING_ARTIFACT_LAYERS.ps1"
$repoHygieneScript = Join-Path $ProjectRoot "RUN\BUILD_REPO_HYGIENE_REPORT.ps1"
$supervisorScopeAuditScript = Join-Path $ProjectRoot "RUN\BUILD_SUPERVISOR_SCOPE_AUDIT.ps1"
$vpsSpoolWellbeingScript = Join-Path $ProjectRoot "RUN\BUILD_VPS_SPOOL_WELLBEING_AUDIT.ps1"
$qdmMissingProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_MISSING_ONLY_PROFILE.ps1"
$qdmVisibilityRefreshScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_VISIBILITY_REFRESH_PROFILE.ps1"
$globalQdmRetrainScript = Join-Path $ProjectRoot "RUN\BUILD_GLOBAL_QDM_RETRAIN_AUDIT.ps1"
$instrumentDataReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_DATA_READINESS_REPORT.ps1"
$instrumentShadowDatasetsScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_SHADOW_DATASETS_REPORT.ps1"
$instrumentTrainingReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_TRAINING_READINESS_REPORT.ps1"
$candidateGapAuditScript = Join-Path $ProjectRoot "RUN\BUILD_CANDIDATE_GAP_AUDIT.ps1"
$outcomeClosureAuditScript = Join-Path $ProjectRoot "RUN\BUILD_OUTCOME_CLOSURE_AUDIT.ps1"
$localModelReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_LOCAL_MODEL_READINESS_AUDIT.ps1"
$learningSourceAuditScript = Join-Path $ProjectRoot "RUN\BUILD_LEARNING_SOURCE_AUDIT.ps1"
$mlScalpingFitAuditScript = Join-Path $ProjectRoot "RUN\BUILD_ML_SCALPING_FIT_AUDIT.ps1"
$tradeTransitionAuditScript = Join-Path $ProjectRoot "RUN\BUILD_TRADE_TRANSITION_AUDIT.ps1"
$paperLiveActionGapAuditScript = Join-Path $ProjectRoot "RUN\BUILD_PAPER_LIVE_ACTION_GAP_AUDIT.ps1"
$paperLossSourceAuditScript = Join-Path $ProjectRoot "RUN\BUILD_PAPER_LOSS_SOURCE_AUDIT.ps1"
$qdmCustomSymbolRealismAuditScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_CUSTOM_SYMBOL_REALISM_AUDIT.ps1"
$mt5FirstWaveServerParityAuditScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_SERVER_PARITY_AUDIT.ps1"
$mt5FirstWaveRuntimeActivityAuditScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1"
$firstWaveLessonClosureAuditScript = Join-Path $ProjectRoot "RUN\BUILD_FIRST_WAVE_LESSON_CLOSURE_AUDIT.ps1"
$mlOverlayAuditScript = Join-Path $ProjectRoot "RUN\BUILD_ML_OVERLAY_AUDIT.ps1"
$shadowRuntimeBootstrapScript = Join-Path $ProjectRoot "RUN\ENSURE_SHADOW_RUNTIME_BOOTSTRAP.ps1"
$instrumentLocalTrainingPlanScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_LOCAL_TRAINING_PLAN.ps1"
$instrumentLocalTrainingAuditScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_LOCAL_TRAINING_AUDIT.ps1"
$qdmMissingSyncStarterScript = Join-Path $ProjectRoot "RUN\START_QDM_MISSING_SUPPORTED_SYNC_BACKGROUND.ps1"
$qdmMissingSyncStatusPath = Join-Path $opsRoot "qdm_missing_supported_sync_latest.json"
$instrumentLocalTrainingLanePath = Join-Path $opsRoot "instrument_local_training_lane_latest.json"
$instrumentLocalTrainingAuditPath = Join-Path $opsRoot "instrument_local_training_audit_latest.json"
$instrumentLocalTrainingGuardrailsPath = Join-Path $opsRoot "instrument_local_training_guardrails_latest.json"
$candidateGapAuditPath = Join-Path $opsRoot "candidate_gap_audit_latest.json"
$outcomeClosureAuditPath = Join-Path $opsRoot "outcome_closure_latest.json"
$localModelReadinessPath = Join-Path $opsRoot "local_model_readiness_latest.json"
$learningSourceAuditPath = Join-Path $opsRoot "learning_source_audit_latest.json"
$mlScalpingFitAuditPath = Join-Path $opsRoot "ml_scalping_fit_audit_latest.json"
$tradeTransitionAuditPath = Join-Path $opsRoot "trade_transition_audit_latest.json"
$mlOverlayAuditPath = Join-Path $opsRoot "ml_overlay_supervision_latest.json"
$qdmVisibilityRefreshPath = Join-Path $opsRoot "qdm_visibility_refresh_profile_latest.json"
$globalQdmRetrainPath = Join-Path $opsRoot "global_qdm_retrain_audit_latest.json"
$paperLiveActionGapAuditPath = Join-Path $opsRoot "paper_live_action_gap_audit_latest.json"
$paperLossSourceAuditPath = Join-Path $opsRoot "paper_loss_source_audit_latest.json"
$shadowRuntimeBootstrapPath = Join-Path $opsRoot "shadow_runtime_bootstrap_latest.json"
$controlSnapshotScript = Join-Path $ProjectRoot "CONTROL\build_system_snapshot.py"
$controlHealthScript = Join-Path $ProjectRoot "CONTROL\build_symbol_health_matrix.py"
$controlActionPlanScript = Join-Path $ProjectRoot "CONTROL\build_action_plan.py"
$controlWorkbenchScript = Join-Path $ProjectRoot "CONTROL\export_codex_workbench.py"
$jsonPath = Join-Path $opsRoot "learning_wellbeing_latest.json"
$mdPath = Join-Path $opsRoot "learning_wellbeing_latest.md"

foreach ($path in @($runtimeLatestScrubScript, $pathHygieneScript, $hotPathScript, $learningArtifactInventoryScript, $globalTeacherCohortAuditScript, $normalizeScript, $repoHygieneScript, $supervisorScopeAuditScript, $vpsSpoolWellbeingScript, $qdmMissingProfileScript, $qdmVisibilityRefreshScript, $globalQdmRetrainScript, $instrumentDataReadinessScript, $instrumentShadowDatasetsScript, $instrumentTrainingReadinessScript, $candidateGapAuditScript, $outcomeClosureAuditScript, $localModelReadinessScript, $learningSourceAuditScript, $mlScalpingFitAuditScript, $tradeTransitionAuditScript, $paperLiveActionGapAuditScript, $paperLossSourceAuditScript, $qdmCustomSymbolRealismAuditScript, $mt5FirstWaveServerParityAuditScript, $mt5FirstWaveRuntimeActivityAuditScript, $firstWaveLessonClosureAuditScript, $mlOverlayAuditScript, $shadowRuntimeBootstrapScript, $instrumentLocalTrainingPlanScript, $instrumentLocalTrainingAuditScript, $qdmMissingSyncStarterScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-DirectoryIfMissing -Path $opsRoot

$effectiveAutoHealLevel = Resolve-AutoHealLevel -ProjectRoot $ProjectRoot -RequestedLevel $AutoHealLevel -LegacyApply ([bool]$Apply)
$safeAutoHealEnabled = $effectiveAutoHealLevel -in @("Safe", "Controlled")
$controlledAutoHealEnabled = $effectiveAutoHealLevel -eq "Controlled"

$null = & $runtimeLatestScrubScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -CommonRoot $CommonRoot -Apply:$safeAutoHealEnabled | Out-Null
$null = & $pathHygieneScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -Apply:$safeAutoHealEnabled | Out-Null
$null = & $hotPathScript -ProjectRoot $ProjectRoot -CommonRoot $CommonRoot -ResearchRoot $ResearchRoot -Apply:$safeAutoHealEnabled | Out-Null
$null = & $learningArtifactInventoryScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -CommonRoot $CommonRoot -UniversePlanPath (Join-Path $ProjectRoot "CONFIG\scalping_universe_plan.json") -Apply:$safeAutoHealEnabled | Out-Null

$runtimeLatestScrub = Read-JsonSafe -Path $runtimeLatestScrubPath
$pathHygiene = Read-JsonSafe -Path $pathHygienePath
$hotPath = Read-JsonSafe -Path $hotPathPath
$learningArtifactInventory = Read-JsonSafe -Path $learningArtifactInventoryPath
$globalTeacherCohortAudit = Read-JsonSafe -Path $globalTeacherCohortAuditPath
$manifestState = Get-ManifestState -ManifestPath $manifestPath
$null = & $repoHygieneScript -ProjectRoot $ProjectRoot -OutputRoot $opsRoot
$null = & $supervisorScopeAuditScript -ProjectRoot $ProjectRoot -OutputRoot $opsRoot
$repoHygiene = Read-JsonSafe -Path (Join-Path $opsRoot "repo_hygiene_latest.json")
$supervisorScopeAudit = Read-JsonSafe -Path (Join-Path $opsRoot "supervisor_scope_audit_latest.json")
$postMigrationStartupAudit = Read-JsonSafe -Path $postMigrationStartupAuditPath
$null = & $qdmMissingProfileScript
$qdmVisibilityRefresh = (& $qdmVisibilityRefreshScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot | ConvertFrom-Json)
$artifactCleanup = Invoke-JsonScript -ScriptPath $normalizeScript -Parameters @{
    ProjectRoot = $ProjectRoot
    ResearchRoot = $ResearchRoot
}
$vpsSpoolBridge = Invoke-JsonScript -ScriptPath $vpsSpoolWellbeingScript -Parameters @{
    ProjectRoot = $ProjectRoot
    ResearchRoot = $ResearchRoot
    CommonRoot = $CommonRoot
    Apply = $controlledAutoHealEnabled
} | ConvertFrom-Json
$instrumentDataReadiness = (& $instrumentDataReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$instrumentShadowDatasets = (& $instrumentShadowDatasetsScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$instrumentTrainingReadiness = (& $instrumentTrainingReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$candidateGapAudit = (& $candidateGapAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $researchPython | ConvertFrom-Json)
$outcomeClosureAudit = (& $outcomeClosureAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $researchPython -CommonStateRoot $commonStateRoot | ConvertFrom-Json)
$localModelReadiness = (& $localModelReadinessScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $researchPython -CommonStateRoot $commonStateRoot | ConvertFrom-Json)
$learningSourceAudit = (& $learningSourceAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot | ConvertFrom-Json)
$mlScalpingFitAudit = (& $mlScalpingFitAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot | ConvertFrom-Json)
$tradeTransitionAudit = (& $tradeTransitionAuditScript -ProjectRoot $ProjectRoot -CommonRoot $CommonRoot | ConvertFrom-Json)
$paperLiveActionGapAudit = (& $paperLiveActionGapAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$paperLossSourceAudit = (& $paperLossSourceAuditScript -ProjectRoot $ProjectRoot -CommonRoot $CommonRoot | ConvertFrom-Json)
$qdmCustomSymbolRealismAudit = (& $qdmCustomSymbolRealismAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$mt5FirstWaveServerParityAudit = (& $mt5FirstWaveServerParityAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$mt5FirstWaveRuntimeActivityAudit = (& $mt5FirstWaveRuntimeActivityAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$firstWaveLessonClosureAudit = (& $firstWaveLessonClosureAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$globalTeacherCohortAudit = (& $globalTeacherCohortAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
try {
    $mlOverlayAudit = (& $mlOverlayAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $researchPython -CommonStateRoot $commonStateRoot | ConvertFrom-Json)
}
catch {
    Write-Warning ("ML overlay audit failed inside wellbeing: " + $_.Exception.Message)
    $mlOverlayAudit = [pscustomobject]@{
        summary = [pscustomobject]@{
            rollout_blocked = $true
            warnings = @()
            errors = @("ML_OVERLAY_AUDIT_FAILED")
        }
    }
}
$shadowRuntimeBootstrap = (& $shadowRuntimeBootstrapScript -ProjectRoot $ProjectRoot -CommonRoot $CommonRoot -Apply:$safeAutoHealEnabled | ConvertFrom-Json)
if ($safeAutoHealEnabled -and $null -ne $shadowRuntimeBootstrap -and [int]$shadowRuntimeBootstrap.summary.applied_count -gt 0) {
    $instrumentDataReadiness = (& $instrumentDataReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $instrumentShadowDatasets = (& $instrumentShadowDatasetsScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $instrumentTrainingReadiness = (& $instrumentTrainingReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $outcomeClosureAudit = (& $outcomeClosureAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $researchPython -CommonStateRoot $commonStateRoot | ConvertFrom-Json)
    $localModelReadiness = (& $localModelReadinessScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $researchPython -CommonStateRoot $commonStateRoot | ConvertFrom-Json)
    $learningSourceAudit = (& $learningSourceAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot | ConvertFrom-Json)
    $mlScalpingFitAudit = (& $mlScalpingFitAuditScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot | ConvertFrom-Json)
    $tradeTransitionAudit = (& $tradeTransitionAuditScript -ProjectRoot $ProjectRoot -CommonRoot $CommonRoot | ConvertFrom-Json)
    $paperLiveActionGapAudit = (& $paperLiveActionGapAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $paperLossSourceAudit = (& $paperLossSourceAuditScript -ProjectRoot $ProjectRoot -CommonRoot $CommonRoot | ConvertFrom-Json)
    $qdmCustomSymbolRealismAudit = (& $qdmCustomSymbolRealismAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $mt5FirstWaveServerParityAudit = (& $mt5FirstWaveServerParityAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $mt5FirstWaveRuntimeActivityAudit = (& $mt5FirstWaveRuntimeActivityAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
    $firstWaveLessonClosureAudit = (& $firstWaveLessonClosureAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
}
$instrumentLocalTrainingPlan = (& $instrumentLocalTrainingPlanScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
$instrumentLocalTrainingLane = Read-JsonSafe -Path $instrumentLocalTrainingLanePath
$instrumentLocalTrainingAudit = (& $instrumentLocalTrainingAuditScript -ProjectRoot $ProjectRoot -ApplySafeRollback:$safeAutoHealEnabled | ConvertFrom-Json)
$instrumentLocalTrainingGuardrails = Read-JsonSafe -Path $instrumentLocalTrainingGuardrailsPath
$qdmMissingProfile = Read-JsonSafe -Path (Join-Path $opsRoot "qdm_missing_only_profile_latest.json")
$qdmMissingSyncStatus = Read-JsonSafe -Path $qdmMissingSyncStatusPath
$qdmRepairAction = ""
$qdmRecoveryBatchSymbols = if ($null -ne $qdmMissingSyncStatus -and $qdmMissingSyncStatus.PSObject.Properties['batch_symbols']) {
    @($qdmMissingSyncStatus.batch_symbols | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
} else { @() }
$qdmRecoveryRecoveredSymbols = if ($null -ne $qdmMissingSyncStatus -and $qdmMissingSyncStatus.PSObject.Properties['recovered_symbols']) {
    @($qdmMissingSyncStatus.recovered_symbols | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
} else { @() }
$qdmRecoveryResearchRefreshed = if ($null -ne $qdmMissingSyncStatus) { [bool]$qdmMissingSyncStatus.research_refreshed } else { $false }
$globalQdmRetrain = $null

if ($controlledAutoHealEnabled -and $null -ne $qdmMissingProfile) {
    $qdmMissingCount = [int]$qdmMissingProfile.qdm_missing_count
    $qdmRefreshRequiredCount = if ($null -ne $qdmVisibilityRefresh) { [int]$qdmVisibilityRefresh.summary.refresh_required_count } else { 0 }
    $qdmServerTailBridgeRequiredCount = if ($null -ne $qdmVisibilityRefresh -and $null -ne $qdmVisibilityRefresh.summary.PSObject.Properties['server_tail_bridge_required_count']) { [int]$qdmVisibilityRefresh.summary.server_tail_bridge_required_count } else { 0 }
    $syncState = if ($null -ne $qdmMissingSyncStatus) { [string]$qdmMissingSyncStatus.state } else { "" }
    $syncWrapperActive = (Get-WrapperCount -Pattern "*qdm_missing_supported_sync_wrapper_*") -gt 0
    if (($qdmMissingCount -gt 0 -or $qdmRefreshRequiredCount -gt 0) -and -not $syncWrapperActive -and $syncState -notin @("running", "export_in_progress", "queue_waiting_next_batch")) {
        & $qdmMissingSyncStarterScript | Out-Null
        $qdmRepairAction = "started_qdm_missing_supported_sync_background"
        $qdmMissingSyncStatus = Read-JsonSafe -Path $qdmMissingSyncStatusPath
    }
}

$globalQdmRetrain = (& $globalQdmRetrainScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -Apply:$safeAutoHealEnabled | ConvertFrom-Json)

$opsRules = @(
    [pscustomobject]@{ name = "local_operator_snapshot"; regex = '^local_operator_snapshot_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsSnapshotKeepCount; age_days = 2 },
    [pscustomobject]@{ name = "qdm_weakest_profile"; regex = '^qdm_weakest_profile_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "tuning_priority"; regex = '^tuning_priority_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "ml_tuning_hints"; regex = '^ml_tuning_hints_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "qdm_intensive_research_plan"; regex = '^qdm_intensive_research_plan_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "mt5_retest_queue"; regex = '^mt5_retest_queue_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "qdm_missing_only_profile"; regex = '^qdm_missing_only_profile_\d{8}_\d{6}\.(json|md)$'; keep_count = $OpsStatusKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "autonomous_90p_supervisor"; regex = '^autonomous_90p_supervisor_\d{8}_\d{6}\.log$'; keep_count = $OpsLogKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "audit_supervisor"; regex = '^audit_supervisor_\d{8}_\d{6}\.log$'; keep_count = $OpsLogKeepCount; age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "local_operator_archiver"; regex = '^local_operator_archiver_\d{8}_\d{6}\.log$'; keep_count = [Math]::Max(4, [int]($OpsLogKeepCount / 2)); age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "mt5_tester_status_watcher"; regex = '^mt5_tester_status_watcher_\d{8}_\d{6}\.log$'; keep_count = [Math]::Max(4, [int]($OpsLogKeepCount / 2)); age_days = $OpsRetentionDays },
    [pscustomobject]@{ name = "mt5_risk_popup_guard"; regex = '^mt5_risk_popup_guard_\d{8}_\d{6}\.log$'; keep_count = [Math]::Max(4, [int]($OpsLogKeepCount / 2)); age_days = $OpsRetentionDays }
)

$opsDeleted = New-Object System.Collections.Generic.List[object]
$opsPending = New-Object System.Collections.Generic.List[object]
$opsFreedBytes = [int64]0

$opsFiles = @()
if (Test-Path -LiteralPath $opsRoot) {
    $opsFiles = @(Get-ChildItem -LiteralPath $opsRoot -File -ErrorAction SilentlyContinue)
}

foreach ($rule in $opsRules) {
    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs([int]$rule.age_days))
    $files = @($opsFiles | Where-Object { $_.Name -match $rule.regex } | Sort-Object LastWriteTime -Descending)
    if ($files.Count -le $rule.keep_count) {
        continue
    }

    $candidates = @($files | Select-Object -Skip $rule.keep_count | Where-Object { $_.LastWriteTime -lt $cutoff })
    foreach ($file in $candidates) {
        $row = [pscustomobject]@{
            rule = $rule.name
            path = $file.FullName
            size_mb = [math]::Round($file.Length / 1MB, 2)
            last_write_local = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        if ($safeAutoHealEnabled) {
            Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
            $opsDeleted.Add($row) | Out-Null
            $opsFreedBytes += [int64]$file.Length
        }
        else {
            $opsPending.Add($row) | Out-Null
        }
    }
}

$runtimeAllowedLeafNames = @(
    "incident_journal.jsonl",
    "decision_events.csv",
    "candidate_signals.csv",
    "execution_telemetry.csv",
    "latency_profile.csv",
    "trade_transactions.jsonl",
    "tuning_actions.csv",
    "tuning_deckhand.csv",
    "tuning_family_actions.csv",
    "tuning_coordinator_actions.csv"
)

$runtimeDeleted = New-Object System.Collections.Generic.List[object]
$runtimePending = New-Object System.Collections.Generic.List[object]
$runtimeFreedBytes = [int64]0
$runtimeEmptyDirsRemoved = 0
$runtimeArchiveSkippedReason = ""

if (-not $manifestState.fresh) {
    $runtimeArchiveSkippedReason = "research_manifest_not_fresh"
}
elseif (Test-Path -LiteralPath $logsRoot) {
    $archiveFiles = @(
        Get-ChildItem -LiteralPath $logsRoot -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\archive\\' } |
            ForEach-Object {
                $normalizedLeaf = Get-NormalizedArchiveLeafName -Name $_.Name
                if ($runtimeAllowedLeafNames -notcontains $normalizedLeaf) {
                    return
                }

                [pscustomobject]@{
                    file = $_
                    symbol = Get-SymbolFromArchivePath -LogsRoot $logsRoot -FullName $_.FullName
                    normalized_leaf = $normalizedLeaf
                }
            } |
            Where-Object { $null -ne $_ }
    )

    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs($RuntimeArchiveRetentionDays))
    $groups = $archiveFiles | Group-Object { "{0}|{1}" -f $_.symbol, $_.normalized_leaf }
    foreach ($group in $groups) {
        $sorted = @($group.Group | Sort-Object { $_.file.LastWriteTime } -Descending)
        if ($sorted.Count -le $RuntimeArchiveKeepRecentPerKind) {
            continue
        }

        $candidates = @($sorted | Select-Object -Skip $RuntimeArchiveKeepRecentPerKind | Where-Object { $_.file.LastWriteTime -lt $cutoff })
        foreach ($entry in $candidates) {
            $file = $entry.file
            $row = [pscustomobject]@{
                symbol = $entry.symbol
                log_name = $entry.normalized_leaf
                path = $file.FullName
                size_mb = [math]::Round($file.Length / 1MB, 2)
                last_write_local = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            if ($safeAutoHealEnabled) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction SilentlyContinue
                $runtimeDeleted.Add($row) | Out-Null
                $runtimeFreedBytes += [int64]$file.Length
            }
            else {
                $runtimePending.Add($row) | Out-Null
            }
        }
    }

    if ($safeAutoHealEnabled) {
        foreach ($archiveRoot in @(Get-ChildItem -LiteralPath $logsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName "archive" })) {
            $runtimeEmptyDirsRemoved += (Remove-EmptyDirectories -RootPath $archiveRoot)
        }
    }
}

$totalFreedGb = [math]::Round((($opsFreedBytes + $runtimeFreedBytes) / 1GB) + [double]$artifactCleanup.freed_gb_total, 3)
$dataReadinessSummary = if ($null -ne $instrumentDataReadiness) { $instrumentDataReadiness.summary } else { $null }
$trainingReadinessSummary = if ($null -ne $instrumentTrainingReadiness) { $instrumentTrainingReadiness.summary } else { $null }
$outcomeClosureSummary = if ($null -ne $outcomeClosureAudit) { $outcomeClosureAudit.summary } else { $null }
$localModelReadinessSummary = if ($null -ne $localModelReadiness) { $localModelReadiness.summary } else { $null }
$exportPendingCount = if ($null -ne $dataReadinessSummary) { [int]$dataReadinessSummary.export_pending_count } else { 0 }
$contractPendingCount = if ($null -ne $dataReadinessSummary) { [int]$dataReadinessSummary.contract_pending_count } else { 0 }
$instrumentShadowSummary = Get-OptionalValue -Object $instrumentShadowDatasets -Name "summary" -Default $null
$shadowDatasetReadyCount = if ($null -ne $instrumentShadowSummary) {
    [int](Get-OptionalNumber -Object $instrumentShadowSummary -Name "shadow_dataset_ready_count" -Default 0) +
    [int](Get-OptionalNumber -Object $instrumentShadowSummary -Name "shadow_dataset_runtime_ready_count" -Default 0) +
    [int](Get-OptionalNumber -Object $instrumentShadowSummary -Name "shadow_dataset_outcome_ready_count" -Default 0)
} else { 0 }
$learningSourceGapCount = if ($null -ne $learningSourceAudit) { [int]$learningSourceAudit.summary.globalny_model_qdm_visibility_gap_count } else { 0 }
$learningSourceBlockedCount = if ($null -ne $learningSourceAudit) { [int]$learningSourceAudit.summary.blocked_count } else { 0 }
$mlScalpingFitVerdict = if ($null -ne $mlScalpingFitAudit) { [string]$mlScalpingFitAudit.verdict } else { "" }
$mlScalpingBrokerNetReady = if ($null -ne $mlScalpingFitAudit) { [bool]$mlScalpingFitAudit.summary.broker_net_pln_ready } else { $false }
$mlScalpingQdmCoverageRatio = if ($null -ne $mlScalpingFitAudit) { [double]$mlScalpingFitAudit.summary.qdm_coverage_ratio } else { 0.0 }
$mlScalpingCritical = ($mlScalpingFitVerdict -eq "MODEL_WYMAGA_NAPRAWY_POD_SKALPING")
$tradeTransitionActiveChartCount = if ($null -ne $tradeTransitionAudit) { [int]$tradeTransitionAudit.summary.profile_active_chart_count } else { 0 }
$tradeTransitionSafeChartCount = if ($null -ne $tradeTransitionAudit) { [int]$tradeTransitionAudit.summary.profile_safe_chart_count } else { 0 }
$tradeTransitionUsesServerPing = if ($null -ne $tradeTransitionAudit) { [bool]$tradeTransitionAudit.summary.global_model_uses_server_ping } else { $false }
$tradeTransitionUsesServerLatency = if ($null -ne $tradeTransitionAudit) { [bool]$tradeTransitionAudit.summary.global_model_uses_server_latency } else { $false }
$tradeTransitionVerdict = if ($null -ne $tradeTransitionAudit) { [string]$tradeTransitionAudit.verdict } else { "" }
$mlOverlayRolloutBlocked = if ($null -ne $mlOverlayAudit) { [bool]$mlOverlayAudit.summary.rollout_blocked } else { $false }
$mlOverlayWarningCount = if ($null -ne $mlOverlayAudit) { @($mlOverlayAudit.summary.warnings).Count } else { 0 }
$mlOverlayErrorCount = if ($null -ne $mlOverlayAudit) { @($mlOverlayAudit.summary.errors).Count } else { 0 }
$qdmRefreshRequiredCount = if ($null -ne $qdmVisibilityRefresh) { [int]$qdmVisibilityRefresh.summary.refresh_required_count } else { 0 }
$qdmServerTailBridgeRequiredCount = if ($null -ne $qdmVisibilityRefresh -and $null -ne $qdmVisibilityRefresh.summary.PSObject.Properties['server_tail_bridge_required_count']) { [int]$qdmVisibilityRefresh.summary.server_tail_bridge_required_count } else { 0 }
$qdmRetrainRequiredCount = if ($null -ne $qdmVisibilityRefresh) { [int]$qdmVisibilityRefresh.summary.retrain_required_count } else { 0 }
$globalQdmRetrainState = if ($null -ne $globalQdmRetrain) { [string]$globalQdmRetrain.verdict } else { "" }
$globalQdmRetrainAction = if ($null -ne $globalQdmRetrain) { [string]$globalQdmRetrain.summary.retrain_action } else { "" }
$globalQdmRetrainStartAllowed = if ($null -ne $globalQdmRetrain) { [bool]$globalQdmRetrain.summary.start_allowed } else { $false }
$paperLiveIdleCount = if ($null -ne $paperLiveActionGapAudit) { [int]$paperLiveActionGapAudit.summary.fresh_but_idle_count } else { 0 }
$paperLiveActiveTradeCount = if ($null -ne $paperLiveActionGapAudit) { [int]$paperLiveActionGapAudit.summary.active_trade_count } else { 0 }
$paperLossActiveNegativeCount = if ($null -ne $paperLossSourceAudit) { [int]$paperLossSourceAudit.summary.active_negative_symbols_count } else { 0 }
$paperLossCostDrivenCount = if ($null -ne $paperLossSourceAudit) { [int]$paperLossSourceAudit.summary.cost_driven_count } else { 0 }
$paperLossQualityDrivenCount = if ($null -ne $paperLossSourceAudit) { [int]$paperLossSourceAudit.summary.quality_driven_count } else { 0 }
$paperLossTimeoutDrivenCount = if ($null -ne $paperLossSourceAudit) { [int]$paperLossSourceAudit.summary.timeout_driven_count } else { 0 }
$firstWaveServerParityVerdict = if ($null -ne $mt5FirstWaveServerParityAudit) { [string]$mt5FirstWaveServerParityAudit.verdict } else { "" }
$firstWaveServerNearServerCount = if ($null -ne $mt5FirstWaveServerParityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveServerParityAudit.summary -Name "near_server_count" -Default 0) } else { 0 }
$firstWaveServerPartialCount = if ($null -ne $mt5FirstWaveServerParityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveServerParityAudit.summary -Name "partial_count" -Default 0) } else { 0 }
$firstWaveServerBlockedCount = if ($null -ne $mt5FirstWaveServerParityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveServerParityAudit.summary -Name "blocked_count" -Default 0) } else { 0 }
$firstWaveServerLiveTruthReadyCount = if ($null -ne $mt5FirstWaveServerParityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveServerParityAudit.summary -Name "live_truth_ready_count" -Default 0) } else { 0 }
$firstWaveServerRuntimeProfileMatch = if ($null -ne $mt5FirstWaveServerParityAudit) { [bool](Get-OptionalValue -Object $mt5FirstWaveServerParityAudit.summary -Name "runtime_profile_match" -Default $false) } else { $false }
$firstWaveServerCapitalIsolationReady = if ($null -ne $mt5FirstWaveServerParityAudit) { [bool](Get-OptionalValue -Object $mt5FirstWaveServerParityAudit.summary -Name "capital_isolation_ready" -Default $false) } else { $false }
$firstWaveRuntimeActivityVerdict = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) { [string]$mt5FirstWaveRuntimeActivityAudit.verdict } else { "" }
$firstWaveRuntimeLiveLogFreshCount = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveRuntimeActivityAudit.summary -Name "live_log_fresh_count" -Default 0) } else { 0 }
$firstWaveRuntimeTruthLiveCount = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveRuntimeActivityAudit.summary -Name "truth_live_symbol_count" -Default 0) } else { 0 }
$firstWaveRuntimeOutsideWindowCount = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveRuntimeActivityAudit.summary -Name "outside_trade_window_count" -Default 0) } else { 0 }
$firstWaveRuntimeFreezeCount = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveRuntimeActivityAudit.summary -Name "tuning_freeze_count" -Default 0) } else { 0 }
$firstWaveRuntimeWeakSignalCount = if ($null -ne $mt5FirstWaveRuntimeActivityAudit) { [int](Get-OptionalNumber -Object $mt5FirstWaveRuntimeActivityAudit.summary -Name "weak_signal_count" -Default 0) } else { 0 }
$firstWaveLessonClosureVerdict = if ($null -ne $firstWaveLessonClosureAudit) { [string](Get-OptionalValue -Object $firstWaveLessonClosureAudit -Name "verdict" -Default "") } else { "" }
$firstWaveLessonClosureFreshReadyCount = if ($null -ne $firstWaveLessonClosureAudit) { [int](Get-OptionalNumber -Object $firstWaveLessonClosureAudit.summary -Name "fresh_chain_ready_count" -Default 0) } else { 0 }
$firstWaveLessonClosureHistoricalReadyCount = if ($null -ne $firstWaveLessonClosureAudit) { [int](Get-OptionalNumber -Object $firstWaveLessonClosureAudit.summary -Name "historical_chain_ready_count" -Default 0) } else { 0 }
$firstWaveLessonClosureMissingCount = if ($null -ne $firstWaveLessonClosureAudit) { [int](Get-OptionalNumber -Object $firstWaveLessonClosureAudit.summary -Name "missing_chain_count" -Default 0) } else { 0 }
$firstWaveLessonClosurePartialGapCount = if ($null -ne $firstWaveLessonClosureAudit) { [int](Get-OptionalNumber -Object $firstWaveLessonClosureAudit.summary -Name "partial_gap_count" -Default 0) } else { 0 }
$candidateGapFinalZeroCount = if ($null -ne $candidateGapAudit) { [int]$candidateGapAudit.summary.final_zero_count } else { 0 }
$candidateGapStrategyZeroCount = if ($null -ne $candidateGapAudit) { [int]$candidateGapAudit.summary.strategy_zero_count } else { 0 }
$candidateGapRiskZeroCount = if ($null -ne $candidateGapAudit) { [int]$candidateGapAudit.summary.risk_zero_count } else { 0 }
$shadowRuntimeBootstrapAppliedCount = if ($null -ne $shadowRuntimeBootstrap) { [int]$shadowRuntimeBootstrap.summary.applied_count } else { 0 }
$shadowRuntimeBootstrapPendingCount = if ($null -ne $shadowRuntimeBootstrap) { [int]$shadowRuntimeBootstrap.summary.pending_count } else { 0 }
$outcomeClosureReadyCount = if ($null -ne $outcomeClosureSummary) { [int]$outcomeClosureSummary.symbols_with_outcome_count } else { 0 }
$outcomeClosureGapCount = if ($null -ne $outcomeClosureSummary) { [int]$outcomeClosureSummary.outcome_gap_count } else { 0 }
$outcomeClosurePendingPaperTruthCount = if ($null -ne $outcomeClosureSummary) { [int]$outcomeClosureSummary.pending_paper_truth_count } else { 0 }
$outcomeClosureFullLedgerCostCount = if ($null -ne $outcomeClosureSummary) { [int]$outcomeClosureSummary.symbols_with_full_ledger_costs_count } else { 0 }
$outcomeClosureBrokerNetReady = if ($null -ne $outcomeClosureSummary) { [bool]$outcomeClosureSummary.broker_net_pln_ready } else { $false }
$localTrainingReadyCount = if ($null -ne $trainingReadinessSummary) { [int]$trainingReadinessSummary.local_training_ready_count } else { 0 }
$localTrainingLimitedCount = if ($null -ne $trainingReadinessSummary) { [int]$trainingReadinessSummary.local_training_limited_count } else { 0 }
$localModelTrainingReadyCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.training_ready_count } else { 0 }
$localModelRankingPassCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.ranking_pass_count } else { 0 }
$localModelRankingBlockedCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.ranking_blocked_count } else { 0 }
$localModelRankingOnlyCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.ranking_only_count } else { 0 }
$localModelRuntimeReadyCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.runtime_ready_count } else { 0 }
$localModelRuntimeDisabledCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.runtime_package_present_but_disabled_count } else { 0 }
$localModelGlobalOnlyCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.runtime_global_only_count } else { 0 }
$localModelDeploymentPassCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.deployment_pass_count } else { 0 }
$localModelDeploymentBlockedCount = if ($null -ne $localModelReadinessSummary) { [int]$localModelReadinessSummary.deployment_blocked_count } else { 0 }
$localModelCostTruthGapCount = if ($null -ne $localModelReadinessSummary -and $null -ne $localModelReadinessSummary.reason_counts) {
    [int](Get-OptionalNumber -Object $localModelReadinessSummary.reason_counts -Name "COST_TRUTH_GAP" -Default 0)
} else { 0 }
$localModelMissingCount = if ($null -ne $localModelReadinessSummary -and $null -ne $localModelReadinessSummary.reason_counts) {
    [int](Get-OptionalNumber -Object $localModelReadinessSummary.reason_counts -Name "LOCAL_MODEL_MISSING" -Default 0)
} else { 0 }
$localModelPackageMismatchCount = if ($null -ne $localModelReadinessSummary -and $null -ne $localModelReadinessSummary.reason_counts) {
    [int](Get-OptionalNumber -Object $localModelReadinessSummary.reason_counts -Name "PACKAGE_RUNTIME_MISMATCH" -Default 0)
} else { 0 }
$localTrainingStartGroupCount = if ($null -ne $instrumentLocalTrainingPlan) { [int]$instrumentLocalTrainingPlan.summary.start_group_count } else { 0 }
$localTrainingLaneState = if ($null -ne $instrumentLocalTrainingLane) { [string]$instrumentLocalTrainingLane.state } else { "" }
$localTrainingAuditRollbackCount = if ($null -ne $instrumentLocalTrainingAudit) { [int]$instrumentLocalTrainingAudit.summary.rollback_count } else { 0 }
$localTrainingAuditProbationCount = if ($null -ne $instrumentLocalTrainingAudit) { [int]$instrumentLocalTrainingAudit.summary.probation_count } else { 0 }
$localTrainingAuditRepairCount = if ($null -ne $instrumentLocalTrainingAudit) { [int]$instrumentLocalTrainingAudit.summary.repair_applied_count } else { 0 }
$localTrainingGuardrailForcedCount = if ($null -ne $instrumentLocalTrainingGuardrails) { [int]$instrumentLocalTrainingGuardrails.summary.forced_global_fallback_count } else { 0 }
$localTrainingGuardrailProbationCount = if ($null -ne $instrumentLocalTrainingGuardrails) { [int]$instrumentLocalTrainingGuardrails.summary.probation_count } else { 0 }
$repoSystemCoreDirtyCount = if ($null -ne $repoHygiene) { [int](Get-OptionalNumber -Object $repoHygiene.counts -Name "system_core" -Default 0) } else { 0 }
$repoAuxiliaryBridgeDirtyCount = if ($null -ne $repoHygiene) { [int](Get-OptionalNumber -Object $repoHygiene.counts -Name "auxiliary_bridge" -Default 0) } else { 0 }
$supervisorBoundaryContaminatedCount = if ($null -ne $supervisorScopeAudit) { [int](Get-OptionalNumber -Object $supervisorScopeAudit.summary -Name "contaminated_count" -Default 0) } else { 0 }
$supervisorBoundaryClean = ($null -ne $supervisorScopeAudit -and [string]$supervisorScopeAudit.verdict -eq "SUPERVISOR_SCOPE_BOUNDARY_OK")
$learningArtifactVerdict = if ($null -ne $learningArtifactInventory) { [string](Get-OptionalValue -Object $learningArtifactInventory -Name "verdict" -Default "") } else { "" }
$learningArtifactCriticalMissingCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "critical_missing_count" -Default 0) } else { 0 }
$learningArtifactCriticalStaleCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "critical_stale_count" -Default 0) } else { 0 }
$learningArtifactRepairSucceededCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "repair_succeeded_count" -Default 0) } else { 0 }
$learningArtifactRetentionPendingCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "retention_pending_count" -Default 0) } else { 0 }
$learningArtifactRetentionArchivedCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "retention_archived_count" -Default 0) } else { 0 }
$learningArtifactLiveLogStaleSymbolCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "live_log_stale_symbol_count" -Default 0) } else { 0 }
$learningArtifactSpoolEmptyCount = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "spool_empty_count" -Default 0) } else { 0 }
$learningProgressAlertMinutes = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "learning_progress_alert_minutes" -Default 30) } else { 30 }
$learningProgressVerdict = if ($null -ne $learningArtifactInventory) { [string](Get-OptionalValue -Object $learningArtifactInventory.summary -Name "learning_progress_verdict" -Default "") } else { "" }
$learningProgressFleetAlert30m = if ($null -ne $learningArtifactInventory) { [bool](Get-OptionalValue -Object $learningArtifactInventory.summary -Name "learning_progress_fleet_alert_30m" -Default $false) } else { $false }
$learningProgressFleetLessonAlert30m = if ($null -ne $learningArtifactInventory) { [bool](Get-OptionalValue -Object $learningArtifactInventory.summary -Name "learning_progress_fleet_lesson_alert_30m" -Default $false) } else { $false }
$learningProgressFirstWaveAlert30m = if ($null -ne $learningArtifactInventory) { [bool](Get-OptionalValue -Object $learningArtifactInventory.summary -Name "learning_progress_first_wave_alert_30m" -Default $false) } else { $false }
$learningProgressFirstWaveLessonAlert30m = if ($null -ne $learningArtifactInventory) { [bool](Get-OptionalValue -Object $learningArtifactInventory.summary -Name "learning_progress_first_wave_lesson_alert_30m" -Default $false) } else { $false }
$learningProgressObservationActiveCount30m = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "learning_progress_observation_active_count_30m" -Default 0) } else { 0 }
$learningProgressLessonActiveCount30m = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "learning_progress_lesson_active_count_30m" -Default 0) } else { 0 }
$learningProgressFirstWaveObservationActiveCount30m = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "learning_progress_first_wave_observation_active_count_30m" -Default 0) } else { 0 }
$learningProgressFirstWaveLessonActiveCount30m = if ($null -ne $learningArtifactInventory) { [int](Get-OptionalNumber -Object $learningArtifactInventory.summary -Name "learning_progress_first_wave_lesson_active_count_30m" -Default 0) } else { 0 }
$globalTeacherCohortVerdict = if ($null -ne $globalTeacherCohortAudit) { [string](Get-OptionalValue -Object $globalTeacherCohortAudit -Name "verdict" -Default "") } else { "" }
$globalTeacherCohortTargetCount = if ($null -ne $globalTeacherCohortAudit) { [int](Get-OptionalNumber -Object $globalTeacherCohortAudit.summary -Name "target_symbol_count" -Default 0) } else { 0 }
$globalTeacherCohortRuntimeActiveCount = if ($null -ne $globalTeacherCohortAudit) { [int](Get-OptionalNumber -Object $globalTeacherCohortAudit.summary -Name "teacher_runtime_active_count" -Default 0) } else { 0 }
$globalTeacherCohortRuntimeInactiveCount = if ($null -ne $globalTeacherCohortAudit) { [int](Get-OptionalNumber -Object $globalTeacherCohortAudit.summary -Name "teacher_runtime_inactive_count" -Default 0) } else { 0 }
$globalTeacherCohortFreshFullLessonCount = if ($null -ne $globalTeacherCohortAudit) { [int](Get-OptionalNumber -Object $globalTeacherCohortAudit.summary -Name "fresh_full_lesson_count" -Default 0) } else { 0 }
$globalTeacherCohortStalledCount = if ($null -ne $globalTeacherCohortAudit) { [int](Get-OptionalNumber -Object $globalTeacherCohortAudit.summary -Name "learning_stalled_count" -Default 0) } else { 0 }
$globalTeacherCohortMissingLessonSymbols = if ($null -ne $globalTeacherCohortAudit) { @(Get-OptionalValue -Object $globalTeacherCohortAudit.summary -Name "symbols_without_fresh_lessons" -Default @()) } else { @() }
$globalTeacherCohortInactiveSymbols = if ($null -ne $globalTeacherCohortAudit) { @(Get-OptionalValue -Object $globalTeacherCohortAudit.summary -Name "symbols_without_teacher_runtime" -Default @()) } else { @() }
$learningProgressGlobalTeacherAlert30m = ($globalTeacherCohortTargetCount -gt 0 -and ($globalTeacherCohortRuntimeInactiveCount -gt 0 -or $globalTeacherCohortStalledCount -gt 0))
$postMigrationStartupVerdict = if ($null -ne $postMigrationStartupAudit) { [string](Get-OptionalValue -Object $postMigrationStartupAudit -Name "verdict" -Default "") } else { "" }
$postMigrationStartupOk = ($null -ne $postMigrationStartupAudit -and [bool](Get-OptionalValue -Object $postMigrationStartupAudit -Name "ok" -Default $false))
$postMigrationContinuityCount = if ($null -ne $postMigrationStartupAudit) { [int](Get-OptionalNumber -Object $postMigrationStartupAudit.final.summary -Name "continuity_fresh_count" -Default 0) } else { 0 }
$postMigrationWatchdogMissingCount = if ($null -ne $postMigrationStartupAudit) { [int](Get-OptionalNumber -Object $postMigrationStartupAudit.final.summary -Name "watchdog_missing_target_count" -Default 0) } else { 0 }
$postMigrationWatchdogStaleCount = if ($null -ne $postMigrationStartupAudit) { [int](Get-OptionalNumber -Object $postMigrationStartupAudit.final.summary -Name "watchdog_stale_target_count" -Default 0) } else { 0 }
$postMigrationPendingSyncCount = if ($null -ne $postMigrationStartupAudit) { [int](Get-OptionalNumber -Object $postMigrationStartupAudit.final.summary -Name "pending_vps_sync_count" -Default 0) } else { 0 }
$postMigrationTruthFlowState = if ($null -ne $postMigrationStartupAudit) { [string](Get-OptionalValue -Object $postMigrationStartupAudit.final.summary -Name "truth_flow_state" -Default "") } else { "" }
$learningProgressAlarm30m = ($learningProgressFleetAlert30m -or $learningProgressFirstWaveAlert30m -or $learningProgressFirstWaveLessonAlert30m -or $learningProgressGlobalTeacherAlert30m)
$learningProgressKnownCause = ($firstWaveRuntimeOutsideWindowCount -gt 0 -or $firstWaveRuntimeFreezeCount -gt 0 -or $paperLiveIdleCount -gt 0)
$verdict = if (
    $learningProgressAlarm30m
) {
    if ($learningProgressKnownCause) {
        "ALARM_POSTEPU_NAUKI_30M_ZNANA_PRZYCZYNA"
    }
    else {
        "ALARM_POSTEPU_NAUKI_30M"
    }
}
elseif (
    ($pathHygiene -ne $null -and [string]$pathHygiene.verdict -eq "CZYSTO") -and
    ($hotPath -ne $null -and [string]$hotPath.verdict -eq "GORACY_SZLAK_CZYSTY") -and
    $learningArtifactCriticalMissingCount -eq 0 -and
    $learningArtifactCriticalStaleCount -eq 0 -and
    ($null -ne $vpsSpoolBridge -and [string]$vpsSpoolBridge.verdict -in @("MOST_STABILNY", "MOST_UTWARDZONY")) -and
    $contractPendingCount -eq 0 -and
    $qdmRefreshRequiredCount -eq 0 -and
    $qdmServerTailBridgeRequiredCount -eq 0 -and
    -not $mlOverlayRolloutBlocked -and
    -not $mlScalpingCritical -and
    $repoSystemCoreDirtyCount -eq 0 -and
    $supervisorBoundaryClean -and
    ($null -eq $postMigrationStartupAudit -or $postMigrationStartupOk) -and
    $opsPending.Count -eq 0 -and
    $runtimePending.Count -eq 0 -and
    $runtimeArchiveSkippedReason -eq "" -and
    ($localTrainingAuditRollbackCount -eq 0 -or $localTrainingAuditRepairCount -ge $localTrainingAuditRollbackCount)
) {
    if ($totalFreedGb -gt 0 -or $opsDeleted.Count -gt 0 -or $runtimeDeleted.Count -gt 0 -or $runtimeEmptyDirsRemoved -gt 0) {
        "DOBROSTAN_UTWARDZONY"
    }
    else {
        "DOBROSTAN_STABILNY"
    }
}
else {
    "WYMAGA_DALSZEJ_HIGIENY"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    common_root = $CommonRoot
    apply_mode = $safeAutoHealEnabled
    auto_heal_level = $effectiveAutoHealLevel
    safe_auto_heal_enabled = $safeAutoHealEnabled
    controlled_auto_heal_enabled = $controlledAutoHealEnabled
    manifest = $manifestState
    learning_path_hygiene = if ($null -ne $pathHygiene) { [pscustomobject]@{ verdict = [string]$pathHygiene.verdict } } else { $null }
    learning_hot_path = if ($null -ne $hotPath) { [pscustomobject]@{ verdict = [string]$hotPath.verdict } } else { $null }
    runtime_latest_scrub = $runtimeLatestScrub
    learning_artifact_inventory = $learningArtifactInventory
    global_teacher_cohort_audit = $globalTeacherCohortAudit
    repo_hygiene = $repoHygiene
    supervisor_scope_audit = $supervisorScopeAudit
    post_migration_startup_audit = $postMigrationStartupAudit
    vps_spool_bridge = $vpsSpoolBridge
    qdm_missing_supported_sync = $qdmMissingSyncStatus
    qdm_visibility_refresh = $qdmVisibilityRefresh
    global_qdm_retrain = $globalQdmRetrain
    instrument_data_readiness = $instrumentDataReadiness
    instrument_shadow_datasets = $instrumentShadowDatasets
    instrument_training_readiness = $instrumentTrainingReadiness
    candidate_gap_audit = $candidateGapAudit
    outcome_closure_audit = $outcomeClosureAudit
    local_model_readiness = $localModelReadiness
    learning_source_audit = $learningSourceAudit
    ml_scalping_fit_audit = $mlScalpingFitAudit
    trade_transition_audit = $tradeTransitionAudit
    ml_overlay_audit = $mlOverlayAudit
    paper_live_action_gap_audit = $paperLiveActionGapAudit
    paper_loss_source_audit = $paperLossSourceAudit
    qdm_custom_symbol_realism_audit = $qdmCustomSymbolRealismAudit
    mt5_first_wave_server_parity_audit = $mt5FirstWaveServerParityAudit
    mt5_first_wave_runtime_activity_audit = $mt5FirstWaveRuntimeActivityAudit
    first_wave_lesson_closure_audit = $firstWaveLessonClosureAudit
    shadow_runtime_bootstrap = $shadowRuntimeBootstrap
    instrument_local_training_plan = $instrumentLocalTrainingPlan
    instrument_local_training_lane = $instrumentLocalTrainingLane
    instrument_local_training_audit = $instrumentLocalTrainingAudit
    instrument_local_training_guardrails = $instrumentLocalTrainingGuardrails
    artifact_layers = [ordered]@{
        freed_gb_total = [double]$artifactCleanup.freed_gb_total
        qdm_export_deleted_count = @($artifactCleanup.qdm_export_deleted).Count
        research_csv_deleted_count = @($artifactCleanup.research_csv_deleted).Count
    }
    ops_retention = [ordered]@{
        deleted_count = $opsDeleted.Count
        pending_count = $opsPending.Count
        freed_gb = [math]::Round($opsFreedBytes / 1GB, 3)
        deleted = @($opsDeleted | Select-Object -First 50)
        pending = @($opsPending | Select-Object -First 50)
    }
    runtime_archive_prune = [ordered]@{
        skipped_reason = $runtimeArchiveSkippedReason
        deleted_count = $runtimeDeleted.Count
        pending_count = $runtimePending.Count
        empty_dirs_removed = $runtimeEmptyDirsRemoved
        freed_gb = [math]::Round($runtimeFreedBytes / 1GB, 3)
        deleted = @($runtimeDeleted | Select-Object -First 50)
        pending = @($runtimePending | Select-Object -First 50)
    }
    summary = [ordered]@{
        total_freed_gb = $totalFreedGb
        ops_deleted_count = $opsDeleted.Count
        ops_pending_count = $opsPending.Count
        runtime_archive_deleted_count = $runtimeDeleted.Count
        runtime_archive_pending_count = $runtimePending.Count
        runtime_empty_dirs_removed = $runtimeEmptyDirsRemoved
        qdm_export_pending_count = $exportPendingCount
        qdm_contract_pending_count = $contractPendingCount
        shadow_dataset_ready_count = $shadowDatasetReadyCount
        candidate_gap_final_zero_count = $candidateGapFinalZeroCount
        candidate_gap_strategy_zero_count = $candidateGapStrategyZeroCount
        candidate_gap_risk_zero_count = $candidateGapRiskZeroCount
        outcome_closure_ready_count = $outcomeClosureReadyCount
        outcome_closure_gap_count = $outcomeClosureGapCount
        outcome_closure_pending_paper_truth_count = $outcomeClosurePendingPaperTruthCount
        outcome_closure_full_ledger_cost_count = $outcomeClosureFullLedgerCostCount
        outcome_closure_broker_net_pln_ready = $outcomeClosureBrokerNetReady
        local_model_training_ready_count = $localModelTrainingReadyCount
        local_model_ranking_pass_count = $localModelRankingPassCount
        local_model_ranking_blocked_count = $localModelRankingBlockedCount
        local_model_ranking_only_count = $localModelRankingOnlyCount
        local_model_runtime_ready_count = $localModelRuntimeReadyCount
        local_model_runtime_disabled_count = $localModelRuntimeDisabledCount
        local_model_global_only_count = $localModelGlobalOnlyCount
        local_model_deployment_pass_count = $localModelDeploymentPassCount
        local_model_deployment_blocked_count = $localModelDeploymentBlockedCount
        local_model_cost_truth_gap_count = $localModelCostTruthGapCount
        local_model_missing_count = $localModelMissingCount
        local_model_package_mismatch_count = $localModelPackageMismatchCount
        learning_source_gap_count = $learningSourceGapCount
        learning_source_blocked_count = $learningSourceBlockedCount
        ml_scalping_fit_verdict = $mlScalpingFitVerdict
        ml_scalping_broker_net_pln_ready = $mlScalpingBrokerNetReady
        ml_scalping_qdm_coverage_ratio = $mlScalpingQdmCoverageRatio
        trade_transition_verdict = $tradeTransitionVerdict
        trade_transition_active_chart_count = $tradeTransitionActiveChartCount
        trade_transition_safe_chart_count = $tradeTransitionSafeChartCount
        trade_transition_global_model_uses_server_ping = $tradeTransitionUsesServerPing
        trade_transition_global_model_uses_server_latency = $tradeTransitionUsesServerLatency
        ml_overlay_rollout_blocked = $mlOverlayRolloutBlocked
        ml_overlay_warning_count = $mlOverlayWarningCount
        ml_overlay_error_count = $mlOverlayErrorCount
        qdm_refresh_required_count = $qdmRefreshRequiredCount
        qdm_server_tail_bridge_required_count = $qdmServerTailBridgeRequiredCount
        qdm_retrain_required_count = $qdmRetrainRequiredCount
        global_qdm_retrain_state = $globalQdmRetrainState
        global_qdm_retrain_start_allowed = $globalQdmRetrainStartAllowed
        global_qdm_retrain_action = $globalQdmRetrainAction
        paper_live_idle_count = $paperLiveIdleCount
        paper_live_active_trade_count = $paperLiveActiveTradeCount
        paper_loss_active_negative_symbols_count = $paperLossActiveNegativeCount
        paper_loss_cost_driven_count = $paperLossCostDrivenCount
        paper_loss_quality_driven_count = $paperLossQualityDrivenCount
        paper_loss_timeout_driven_count = $paperLossTimeoutDrivenCount
        first_wave_server_parity_verdict = $firstWaveServerParityVerdict
        first_wave_server_near_server_count = $firstWaveServerNearServerCount
        first_wave_server_partial_count = $firstWaveServerPartialCount
        first_wave_server_blocked_count = $firstWaveServerBlockedCount
        first_wave_server_live_truth_ready_count = $firstWaveServerLiveTruthReadyCount
        first_wave_server_runtime_profile_match = $firstWaveServerRuntimeProfileMatch
        first_wave_server_capital_isolation_ready = $firstWaveServerCapitalIsolationReady
        first_wave_runtime_activity_verdict = $firstWaveRuntimeActivityVerdict
        first_wave_runtime_live_log_fresh_count = $firstWaveRuntimeLiveLogFreshCount
        first_wave_runtime_truth_live_count = $firstWaveRuntimeTruthLiveCount
        first_wave_runtime_outside_window_count = $firstWaveRuntimeOutsideWindowCount
        first_wave_runtime_tuning_freeze_count = $firstWaveRuntimeFreezeCount
        first_wave_runtime_weak_signal_count = $firstWaveRuntimeWeakSignalCount
        first_wave_lesson_closure_verdict = $firstWaveLessonClosureVerdict
        first_wave_lesson_closure_fresh_ready_count = $firstWaveLessonClosureFreshReadyCount
        first_wave_lesson_closure_historical_ready_count = $firstWaveLessonClosureHistoricalReadyCount
        first_wave_lesson_closure_missing_count = $firstWaveLessonClosureMissingCount
        first_wave_lesson_closure_partial_gap_count = $firstWaveLessonClosurePartialGapCount
        qdm_custom_realism_verdict = $(if ($null -ne $qdmCustomSymbolRealismAudit) { [string]$qdmCustomSymbolRealismAudit.verdict } else { "" })
        qdm_custom_realism_ready_count = $(if ($null -ne $qdmCustomSymbolRealismAudit) { [int](Get-OptionalNumber -Object $qdmCustomSymbolRealismAudit.summary -Name "realism_ready_count" -Default 0) } else { 0 })
        qdm_custom_broker_mirror_ready_count = $(if ($null -ne $qdmCustomSymbolRealismAudit) { [int](Get-OptionalNumber -Object $qdmCustomSymbolRealismAudit.summary -Name "broker_mirror_ready_count" -Default 0) } else { 0 })
        qdm_custom_current_run_count = $(if ($null -ne $qdmCustomSymbolRealismAudit) { [int](Get-OptionalNumber -Object $qdmCustomSymbolRealismAudit.summary -Name "current_run_count" -Default 0) } else { 0 })
        qdm_custom_backfilled_count = $(if ($null -ne $qdmCustomSymbolRealismAudit) { [int](Get-OptionalNumber -Object $qdmCustomSymbolRealismAudit.summary -Name "backfilled_count" -Default 0) } else { 0 })
        shadow_runtime_bootstrap_applied_count = $shadowRuntimeBootstrapAppliedCount
        shadow_runtime_bootstrap_pending_count = $shadowRuntimeBootstrapPendingCount
        local_training_ready_count = $localTrainingReadyCount
        local_training_limited_count = $localTrainingLimitedCount
        local_training_start_group_count = $localTrainingStartGroupCount
        local_training_lane_state = $localTrainingLaneState
        local_training_audit_rollback_count = $localTrainingAuditRollbackCount
        local_training_audit_probation_count = $localTrainingAuditProbationCount
        local_training_audit_repair_count = $localTrainingAuditRepairCount
        local_training_guardrail_forced_count = $localTrainingGuardrailForcedCount
        local_training_guardrail_probation_count = $localTrainingGuardrailProbationCount
        learning_artifact_verdict = $learningArtifactVerdict
        learning_artifact_critical_missing_count = $learningArtifactCriticalMissingCount
        learning_artifact_critical_stale_count = $learningArtifactCriticalStaleCount
        learning_artifact_repair_succeeded_count = $learningArtifactRepairSucceededCount
        learning_artifact_retention_pending_count = $learningArtifactRetentionPendingCount
        learning_artifact_retention_archived_count = $learningArtifactRetentionArchivedCount
        learning_artifact_live_log_stale_symbol_count = $learningArtifactLiveLogStaleSymbolCount
        learning_artifact_spool_empty_count = $learningArtifactSpoolEmptyCount
        learning_progress_alert_minutes = $learningProgressAlertMinutes
        learning_progress_verdict = $learningProgressVerdict
        learning_progress_alarm_30m = $learningProgressAlarm30m
        learning_progress_known_cause = $learningProgressKnownCause
        learning_progress_fleet_alert_30m = $learningProgressFleetAlert30m
        learning_progress_fleet_lesson_alert_30m = $learningProgressFleetLessonAlert30m
        learning_progress_first_wave_alert_30m = $learningProgressFirstWaveAlert30m
        learning_progress_first_wave_lesson_alert_30m = $learningProgressFirstWaveLessonAlert30m
        learning_progress_observation_active_count_30m = $learningProgressObservationActiveCount30m
        learning_progress_lesson_active_count_30m = $learningProgressLessonActiveCount30m
        learning_progress_first_wave_observation_active_count_30m = $learningProgressFirstWaveObservationActiveCount30m
        learning_progress_first_wave_lesson_active_count_30m = $learningProgressFirstWaveLessonActiveCount30m
        global_teacher_cohort_verdict = $globalTeacherCohortVerdict
        global_teacher_cohort_target_count = $globalTeacherCohortTargetCount
        global_teacher_cohort_runtime_active_count = $globalTeacherCohortRuntimeActiveCount
        global_teacher_cohort_runtime_inactive_count = $globalTeacherCohortRuntimeInactiveCount
        global_teacher_cohort_fresh_full_lesson_count = $globalTeacherCohortFreshFullLessonCount
        global_teacher_cohort_learning_stalled_count = $globalTeacherCohortStalledCount
        global_teacher_cohort_alert_30m = $learningProgressGlobalTeacherAlert30m
        global_teacher_cohort_inactive_symbols = @($globalTeacherCohortInactiveSymbols)
        global_teacher_cohort_missing_lesson_symbols = @($globalTeacherCohortMissingLessonSymbols)
        post_migration_startup_verdict = $postMigrationStartupVerdict
        post_migration_startup_ok = $postMigrationStartupOk
        post_migration_continuity_fresh_count = $postMigrationContinuityCount
        post_migration_watchdog_missing_count = $postMigrationWatchdogMissingCount
        post_migration_watchdog_stale_count = $postMigrationWatchdogStaleCount
        post_migration_pending_vps_sync_count = $postMigrationPendingSyncCount
        post_migration_truth_flow_state = $postMigrationTruthFlowState
        repo_system_core_dirty_count = $repoSystemCoreDirtyCount
        repo_auxiliary_bridge_dirty_count = $repoAuxiliaryBridgeDirtyCount
        supervisor_boundary_clean = $supervisorBoundaryClean
        supervisor_boundary_contaminated_count = $supervisorBoundaryContaminatedCount
        vps_bridge_pending_sync_count = if ($null -ne $vpsSpoolBridge) { [int]$vpsSpoolBridge.summary.pending_sync_count } else { 0 }
        vps_bridge_repair_actions_count = if ($null -ne $vpsSpoolBridge) { [int]$vpsSpoolBridge.summary.repair_actions_count } else { 0 }
        vps_bridge_export_lag_total = if ($null -ne $vpsSpoolBridge) { [int]$vpsSpoolBridge.summary.export_spool_lag_total } else { 0 }
        qdm_repair_action = $qdmRepairAction
        qdm_recovery_batch_symbols = $qdmRecoveryBatchSymbols
        qdm_recovery_recovered_symbols = $qdmRecoveryRecoveredSymbols
        qdm_recovery_research_refreshed = $qdmRecoveryResearchRefreshed
    }
    verdict = $verdict
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Wellbeing")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- apply_mode: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add(("- auto_heal_level: {0}" -f $report.auto_heal_level))
$lines.Add(("- total_freed_gb: {0}" -f $report.summary.total_freed_gb))
$lines.Add("")
$lines.Add("## Wejscie")
$lines.Add("")
$lines.Add(("- manifest_fresh: {0}" -f $report.manifest.fresh))
$lines.Add(("- learning_path_hygiene: {0}" -f $(if ($null -ne $report.learning_path_hygiene) { $report.learning_path_hygiene.verdict } else { "BRAK" })))
$lines.Add(("- learning_hot_path: {0}" -f $(if ($null -ne $report.learning_hot_path) { $report.learning_hot_path.verdict } else { "BRAK" })))
$lines.Add(("- learning_artifact_inventory: {0}" -f $(if ($null -ne $report.learning_artifact_inventory) { $report.learning_artifact_inventory.verdict } else { "BRAK" })))
$lines.Add(("- learning_artifact_critical_missing_count: {0}" -f $report.summary.learning_artifact_critical_missing_count))
$lines.Add(("- learning_artifact_critical_stale_count: {0}" -f $report.summary.learning_artifact_critical_stale_count))
$lines.Add(("- learning_artifact_repair_succeeded_count: {0}" -f $report.summary.learning_artifact_repair_succeeded_count))
$lines.Add(("- learning_artifact_retention_pending_count: {0}" -f $report.summary.learning_artifact_retention_pending_count))
$lines.Add(("- learning_artifact_retention_archived_count: {0}" -f $report.summary.learning_artifact_retention_archived_count))
$lines.Add(("- learning_artifact_live_log_stale_symbol_count: {0}" -f $report.summary.learning_artifact_live_log_stale_symbol_count))
$lines.Add(("- learning_artifact_spool_empty_count: {0}" -f $report.summary.learning_artifact_spool_empty_count))
$lines.Add(("- learning_progress_alert_minutes: {0}" -f $report.summary.learning_progress_alert_minutes))
$lines.Add(("- learning_progress_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.learning_progress_verdict)) { "BRAK" } else { $report.summary.learning_progress_verdict })))
$lines.Add(("- learning_progress_alarm_30m: {0}" -f ([string]$report.summary.learning_progress_alarm_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_known_cause: {0}" -f ([string]$report.summary.learning_progress_known_cause).ToLowerInvariant()))
$lines.Add(("- learning_progress_fleet_alert_30m: {0}" -f ([string]$report.summary.learning_progress_fleet_alert_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_first_wave_alert_30m: {0}" -f ([string]$report.summary.learning_progress_first_wave_alert_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_first_wave_lesson_alert_30m: {0}" -f ([string]$report.summary.learning_progress_first_wave_lesson_alert_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_observation_active_count_30m: {0}" -f $report.summary.learning_progress_observation_active_count_30m))
$lines.Add(("- learning_progress_lesson_active_count_30m: {0}" -f $report.summary.learning_progress_lesson_active_count_30m))
$lines.Add(("- learning_progress_first_wave_observation_active_count_30m: {0}" -f $report.summary.learning_progress_first_wave_observation_active_count_30m))
$lines.Add(("- learning_progress_first_wave_lesson_active_count_30m: {0}" -f $report.summary.learning_progress_first_wave_lesson_active_count_30m))
$lines.Add(("- global_teacher_cohort_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.global_teacher_cohort_verdict)) { "BRAK" } else { $report.summary.global_teacher_cohort_verdict })))
$lines.Add(("- global_teacher_cohort_runtime_active_count: {0}/{1}" -f $report.summary.global_teacher_cohort_runtime_active_count, $report.summary.global_teacher_cohort_target_count))
$lines.Add(("- global_teacher_cohort_fresh_full_lesson_count: {0}" -f $report.summary.global_teacher_cohort_fresh_full_lesson_count))
$lines.Add(("- global_teacher_cohort_learning_stalled_count: {0}" -f $report.summary.global_teacher_cohort_learning_stalled_count))
$lines.Add(("- global_teacher_cohort_inactive_symbols: {0}" -f $(if ($report.summary.global_teacher_cohort_inactive_symbols.Count -gt 0) { ($report.summary.global_teacher_cohort_inactive_symbols -join ", ") } else { "BRAK" })))
$lines.Add(("- global_teacher_cohort_missing_lesson_symbols: {0}" -f $(if ($report.summary.global_teacher_cohort_missing_lesson_symbols.Count -gt 0) { ($report.summary.global_teacher_cohort_missing_lesson_symbols -join ", ") } else { "BRAK" })))
$lines.Add(("- post_migration_startup_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.post_migration_startup_verdict)) { "BRAK" } else { $report.summary.post_migration_startup_verdict })))
$lines.Add(("- post_migration_startup_ok: {0}" -f ([string]$report.summary.post_migration_startup_ok).ToLowerInvariant()))
$lines.Add(("- post_migration_continuity_fresh_count: {0}" -f $report.summary.post_migration_continuity_fresh_count))
$lines.Add(("- post_migration_watchdog_missing_count: {0}" -f $report.summary.post_migration_watchdog_missing_count))
$lines.Add(("- post_migration_watchdog_stale_count: {0}" -f $report.summary.post_migration_watchdog_stale_count))
$lines.Add(("- post_migration_pending_vps_sync_count: {0}" -f $report.summary.post_migration_pending_vps_sync_count))
$lines.Add(("- post_migration_truth_flow_state: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.post_migration_truth_flow_state)) { "BRAK" } else { $report.summary.post_migration_truth_flow_state })))
$lines.Add(("- repo_hygiene: {0}" -f $(if ($null -ne $report.repo_hygiene) { $report.repo_hygiene.verdict } else { "BRAK" })))
$lines.Add(("- supervisor_scope_audit: {0}" -f $(if ($null -ne $report.supervisor_scope_audit) { $report.supervisor_scope_audit.verdict } else { "BRAK" })))
$lines.Add(("- vps_spool_bridge: {0}" -f $(if ($null -ne $report.vps_spool_bridge) { $report.vps_spool_bridge.verdict } else { "BRAK" })))
$lines.Add(("- qdm_export_pending_count: {0}" -f $report.summary.qdm_export_pending_count))
$lines.Add(("- qdm_contract_pending_count: {0}" -f $report.summary.qdm_contract_pending_count))
$lines.Add(("- shadow_dataset_ready_count: {0}" -f $report.summary.shadow_dataset_ready_count))
$lines.Add(("- candidate_gap_final_zero_count: {0}" -f $report.summary.candidate_gap_final_zero_count))
$lines.Add(("- candidate_gap_strategy_zero_count: {0}" -f $report.summary.candidate_gap_strategy_zero_count))
$lines.Add(("- candidate_gap_risk_zero_count: {0}" -f $report.summary.candidate_gap_risk_zero_count))
$lines.Add(("- outcome_closure_ready_count: {0}" -f $report.summary.outcome_closure_ready_count))
$lines.Add(("- outcome_closure_gap_count: {0}" -f $report.summary.outcome_closure_gap_count))
$lines.Add(("- outcome_closure_pending_paper_truth_count: {0}" -f $report.summary.outcome_closure_pending_paper_truth_count))
$lines.Add(("- outcome_closure_full_ledger_cost_count: {0}" -f $report.summary.outcome_closure_full_ledger_cost_count))
$lines.Add(("- outcome_closure_broker_net_pln_ready: {0}" -f ([string]$report.summary.outcome_closure_broker_net_pln_ready).ToLowerInvariant()))
$lines.Add(("- local_model_training_ready_count: {0}" -f $report.summary.local_model_training_ready_count))
$lines.Add(("- local_model_ranking_pass_count: {0}" -f $report.summary.local_model_ranking_pass_count))
$lines.Add(("- local_model_ranking_blocked_count: {0}" -f $report.summary.local_model_ranking_blocked_count))
$lines.Add(("- local_model_ranking_only_count: {0}" -f $report.summary.local_model_ranking_only_count))
$lines.Add(("- local_model_runtime_ready_count: {0}" -f $report.summary.local_model_runtime_ready_count))
$lines.Add(("- local_model_runtime_disabled_count: {0}" -f $report.summary.local_model_runtime_disabled_count))
$lines.Add(("- local_model_global_only_count: {0}" -f $report.summary.local_model_global_only_count))
$lines.Add(("- local_model_deployment_pass_count: {0}" -f $report.summary.local_model_deployment_pass_count))
$lines.Add(("- local_model_deployment_blocked_count: {0}" -f $report.summary.local_model_deployment_blocked_count))
$lines.Add(("- local_model_cost_truth_gap_count: {0}" -f $report.summary.local_model_cost_truth_gap_count))
$lines.Add(("- local_model_missing_count: {0}" -f $report.summary.local_model_missing_count))
$lines.Add(("- local_model_package_mismatch_count: {0}" -f $report.summary.local_model_package_mismatch_count))
$lines.Add(("- learning_source_gap_count: {0}" -f $report.summary.learning_source_gap_count))
$lines.Add(("- ml_overlay_rollout_blocked: {0}" -f $report.summary.ml_overlay_rollout_blocked))
$lines.Add(("- ml_overlay_warning_count: {0}" -f $report.summary.ml_overlay_warning_count))
$lines.Add(("- ml_overlay_error_count: {0}" -f $report.summary.ml_overlay_error_count))
$lines.Add(("- learning_source_blocked_count: {0}" -f $report.summary.learning_source_blocked_count))
$lines.Add(("- ml_scalping_fit_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.ml_scalping_fit_verdict)) { "BRAK" } else { $report.summary.ml_scalping_fit_verdict })))
$lines.Add(("- ml_scalping_broker_net_pln_ready: {0}" -f ([string]$report.summary.ml_scalping_broker_net_pln_ready).ToLowerInvariant()))
$lines.Add(("- ml_scalping_qdm_coverage_ratio: {0}" -f $report.summary.ml_scalping_qdm_coverage_ratio))
$lines.Add(("- trade_transition_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.trade_transition_verdict)) { "BRAK" } else { $report.summary.trade_transition_verdict })))
$lines.Add(("- trade_transition_active_chart_count: {0}" -f $report.summary.trade_transition_active_chart_count))
$lines.Add(("- trade_transition_safe_chart_count: {0}" -f $report.summary.trade_transition_safe_chart_count))
$lines.Add(("- trade_transition_global_model_uses_server_ping: {0}" -f ([string]$report.summary.trade_transition_global_model_uses_server_ping).ToLowerInvariant()))
$lines.Add(("- trade_transition_global_model_uses_server_latency: {0}" -f ([string]$report.summary.trade_transition_global_model_uses_server_latency).ToLowerInvariant()))
$lines.Add(("- qdm_refresh_required_count: {0}" -f $report.summary.qdm_refresh_required_count))
$lines.Add(("- qdm_server_tail_bridge_required_count: {0}" -f $report.summary.qdm_server_tail_bridge_required_count))
$lines.Add(("- qdm_retrain_required_count: {0}" -f $report.summary.qdm_retrain_required_count))
$lines.Add(("- global_qdm_retrain_state: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.global_qdm_retrain_state)) { "none" } else { $report.summary.global_qdm_retrain_state })))
$lines.Add(("- global_qdm_retrain_start_allowed: {0}" -f ([string]$report.summary.global_qdm_retrain_start_allowed).ToLowerInvariant()))
$lines.Add(("- paper_live_idle_count: {0}" -f $report.summary.paper_live_idle_count))
$lines.Add(("- paper_live_active_trade_count: {0}" -f $report.summary.paper_live_active_trade_count))
$lines.Add(("- paper_loss_active_negative_symbols_count: {0}" -f $report.summary.paper_loss_active_negative_symbols_count))
$lines.Add(("- paper_loss_cost_driven_count: {0}" -f $report.summary.paper_loss_cost_driven_count))
$lines.Add(("- paper_loss_quality_driven_count: {0}" -f $report.summary.paper_loss_quality_driven_count))
$lines.Add(("- paper_loss_timeout_driven_count: {0}" -f $report.summary.paper_loss_timeout_driven_count))
$lines.Add(("- first_wave_server_parity_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.first_wave_server_parity_verdict)) { "BRAK" } else { $report.summary.first_wave_server_parity_verdict })))
$lines.Add(("- first_wave_server_near_server_count: {0}" -f $report.summary.first_wave_server_near_server_count))
$lines.Add(("- first_wave_server_partial_count: {0}" -f $report.summary.first_wave_server_partial_count))
$lines.Add(("- first_wave_server_blocked_count: {0}" -f $report.summary.first_wave_server_blocked_count))
$lines.Add(("- first_wave_server_live_truth_ready_count: {0}" -f $report.summary.first_wave_server_live_truth_ready_count))
$lines.Add(("- first_wave_server_runtime_profile_match: {0}" -f ([string]$report.summary.first_wave_server_runtime_profile_match).ToLowerInvariant()))
$lines.Add(("- first_wave_server_capital_isolation_ready: {0}" -f ([string]$report.summary.first_wave_server_capital_isolation_ready).ToLowerInvariant()))
$lines.Add(("- first_wave_runtime_activity_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.first_wave_runtime_activity_verdict)) { "BRAK" } else { $report.summary.first_wave_runtime_activity_verdict })))
$lines.Add(("- first_wave_runtime_live_log_fresh_count: {0}" -f $report.summary.first_wave_runtime_live_log_fresh_count))
$lines.Add(("- first_wave_runtime_truth_live_count: {0}" -f $report.summary.first_wave_runtime_truth_live_count))
$lines.Add(("- first_wave_runtime_outside_window_count: {0}" -f $report.summary.first_wave_runtime_outside_window_count))
$lines.Add(("- first_wave_runtime_tuning_freeze_count: {0}" -f $report.summary.first_wave_runtime_tuning_freeze_count))
$lines.Add(("- first_wave_runtime_weak_signal_count: {0}" -f $report.summary.first_wave_runtime_weak_signal_count))
$lines.Add(("- first_wave_lesson_closure_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.first_wave_lesson_closure_verdict)) { "BRAK" } else { $report.summary.first_wave_lesson_closure_verdict })))
$lines.Add(("- first_wave_lesson_closure_fresh_ready_count: {0}" -f $report.summary.first_wave_lesson_closure_fresh_ready_count))
$lines.Add(("- first_wave_lesson_closure_historical_ready_count: {0}" -f $report.summary.first_wave_lesson_closure_historical_ready_count))
$lines.Add(("- first_wave_lesson_closure_missing_count: {0}" -f $report.summary.first_wave_lesson_closure_missing_count))
$lines.Add(("- first_wave_lesson_closure_partial_gap_count: {0}" -f $report.summary.first_wave_lesson_closure_partial_gap_count))
$lines.Add(("- qdm_custom_realism_verdict: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.qdm_custom_realism_verdict)) { "BRAK" } else { $report.summary.qdm_custom_realism_verdict })))
$lines.Add(("- qdm_custom_realism_ready_count: {0}" -f $report.summary.qdm_custom_realism_ready_count))
$lines.Add(("- qdm_custom_broker_mirror_ready_count: {0}" -f $report.summary.qdm_custom_broker_mirror_ready_count))
$lines.Add(("- qdm_custom_current_run_count: {0}" -f $report.summary.qdm_custom_current_run_count))
$lines.Add(("- qdm_custom_backfilled_count: {0}" -f $report.summary.qdm_custom_backfilled_count))
$lines.Add(("- shadow_runtime_bootstrap_applied_count: {0}" -f $report.summary.shadow_runtime_bootstrap_applied_count))
$lines.Add(("- shadow_runtime_bootstrap_pending_count: {0}" -f $report.summary.shadow_runtime_bootstrap_pending_count))
$lines.Add(("- local_training_ready_count: {0}" -f $report.summary.local_training_ready_count))
$lines.Add(("- local_training_limited_count: {0}" -f $report.summary.local_training_limited_count))
$lines.Add(("- local_training_start_group_count: {0}" -f $report.summary.local_training_start_group_count))
$lines.Add(("- local_training_lane_state: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.local_training_lane_state)) { "none" } else { $report.summary.local_training_lane_state })))
$lines.Add(("- local_training_audit_rollback_count: {0}" -f $report.summary.local_training_audit_rollback_count))
$lines.Add(("- local_training_audit_probation_count: {0}" -f $report.summary.local_training_audit_probation_count))
$lines.Add(("- local_training_audit_repair_count: {0}" -f $report.summary.local_training_audit_repair_count))
$lines.Add(("- local_training_guardrail_forced_count: {0}" -f $report.summary.local_training_guardrail_forced_count))
$lines.Add(("- local_training_guardrail_probation_count: {0}" -f $report.summary.local_training_guardrail_probation_count))
$lines.Add(("- repo_system_core_dirty_count: {0}" -f $report.summary.repo_system_core_dirty_count))
$lines.Add(("- repo_auxiliary_bridge_dirty_count: {0}" -f $report.summary.repo_auxiliary_bridge_dirty_count))
$lines.Add(("- supervisor_boundary_clean: {0}" -f $report.summary.supervisor_boundary_clean))
$lines.Add(("- supervisor_boundary_contaminated_count: {0}" -f $report.summary.supervisor_boundary_contaminated_count))
$lines.Add(("- qdm_recovery_batch_symbols: {0}" -f $(if (@($report.summary.qdm_recovery_batch_symbols).Count -gt 0) { (@($report.summary.qdm_recovery_batch_symbols) -join ", ") } else { "none" })))
$lines.Add(("- qdm_recovery_recovered_symbols: {0}" -f $(if (@($report.summary.qdm_recovery_recovered_symbols).Count -gt 0) { (@($report.summary.qdm_recovery_recovered_symbols) -join ", ") } else { "none" })))
$lines.Add("")
$lines.Add("## Akcje")
$lines.Add("")
$lines.Add(("- artifact_layers.freed_gb_total: {0}" -f $report.artifact_layers.freed_gb_total))
$lines.Add(("- ops_retention.deleted_count: {0}" -f $report.ops_retention.deleted_count))
$lines.Add(("- runtime_archive_prune.deleted_count: {0}" -f $report.runtime_archive_prune.deleted_count))
$lines.Add(("- runtime_archive_prune.empty_dirs_removed: {0}" -f $report.runtime_archive_prune.empty_dirs_removed))
$lines.Add(("- qdm_repair_action: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.qdm_repair_action)) { "none" } else { $report.summary.qdm_repair_action })))
$lines.Add(("- global_qdm_retrain_action: {0}" -f $(if ([string]::IsNullOrWhiteSpace($report.summary.global_qdm_retrain_action)) { "none" } else { $report.summary.global_qdm_retrain_action })))
$lines.Add(("- qdm_recovery_research_refreshed: {0}" -f ([string]$report.summary.qdm_recovery_research_refreshed).ToLowerInvariant()))
$lines.Add(("- vps_spool_bridge.pending_sync_count: {0}" -f $report.summary.vps_bridge_pending_sync_count))
$lines.Add(("- vps_spool_bridge.repair_actions_count: {0}" -f $report.summary.vps_bridge_repair_actions_count))
$lines.Add(("- vps_spool_bridge.export_spool_lag_total: {0}" -f $report.summary.vps_bridge_export_lag_total))
if (-not [string]::IsNullOrWhiteSpace($report.runtime_archive_prune.skipped_reason)) {
    $lines.Add(("- runtime_archive_prune.skipped_reason: {0}" -f $report.runtime_archive_prune.skipped_reason))
}
$lines.Add("")

if ($null -ne $report.paper_loss_source_audit) {
    $lines.Add("## Zrodla Strat Paper")
    $lines.Add("")
    $lines.Add(("- active_negative_symbols_count: {0}" -f $report.paper_loss_source_audit.summary.active_negative_symbols_count))
    $lines.Add(("- cost_driven_count: {0}" -f $report.paper_loss_source_audit.summary.cost_driven_count))
    $lines.Add(("- quality_driven_count: {0}" -f $report.paper_loss_source_audit.summary.quality_driven_count))
    $lines.Add(("- timeout_driven_count: {0}" -f $report.paper_loss_source_audit.summary.timeout_driven_count))
    foreach ($item in @($report.paper_loss_source_audit.top_negative_symbols | Select-Object -First 5)) {
        $lines.Add(("- {0}: source={1}, net={2}, why={3}" -f
            $item.symbol_alias,
            $item.glowne_zrodlo_straty,
            $item.netto_dzis,
            $item.dlatego_ze))
    }
    $lines.Add("")
}

if ($report.ops_retention.deleted.Count -gt 0) {
    $lines.Add("## OPS Deleted")
    $lines.Add("")
    foreach ($item in $report.ops_retention.deleted) {
        $lines.Add(("- {0} | {1} MB | {2}" -f $item.rule, $item.size_mb, $item.path))
    }
    $lines.Add("")
}

if ($report.runtime_archive_prune.deleted.Count -gt 0) {
    $lines.Add("## Runtime Archive Deleted")
    $lines.Add("")
    foreach ($item in $report.runtime_archive_prune.deleted) {
        $lines.Add(("- {0} {1} | {2} MB | {3}" -f $item.symbol, $item.log_name, $item.size_mb, $item.path))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

Invoke-OptionalPythonHelper -ScriptPath $controlSnapshotScript -Arguments @("--project-root", $ProjectRoot)
Invoke-OptionalPythonHelper -ScriptPath $controlHealthScript -Arguments @("--project-root", $ProjectRoot)
Invoke-OptionalPythonHelper -ScriptPath $controlActionPlanScript -Arguments @("--project-root", $ProjectRoot)
Invoke-OptionalPythonHelper -ScriptPath $controlWorkbenchScript -Arguments @("--project-root", $ProjectRoot)

$report | ConvertTo-Json -Depth 8
