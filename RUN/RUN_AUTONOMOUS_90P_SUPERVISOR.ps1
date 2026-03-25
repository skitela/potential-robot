param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [int]$CycleSeconds = 300,
    [int]$MaxCycles = 0,
    [int]$StartupTurboMinutes = 90
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$priorityScript = Join-Path $ProjectRoot "RUN\BUILD_TUNING_PRIORITY_REPORT.ps1"
$qdmProfileScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_WEAKEST_PROFILE.ps1"
$mlHintsScript = Join-Path $ProjectRoot "RUN\BUILD_ML_TUNING_HINTS.ps1"
$onnxMicroReviewScript = Join-Path $ProjectRoot "RUN\BUILD_ONNX_MICRO_REVIEW_REPORT.ps1"
$activeFleetVerdictsScript = Join-Path $ProjectRoot "RUN\BUILD_ACTIVE_FLEET_VERDICTS_REPORT.ps1"
$winnerDeploymentScript = Join-Path $ProjectRoot "RUN\BUILD_WINNER_DEPLOYMENT_REPORT.ps1"
$learningHealthRegistryScript = Join-Path $ProjectRoot "RUN\BUILD_LEARNING_HEALTH_REGISTRY.ps1"
$learningPaperRuntimePlanScript = Join-Path $ProjectRoot "RUN\BUILD_LEARNING_PAPER_RUNTIME_PLAN.ps1"
$paperRuntimeMigrationScript = Join-Path $ProjectRoot "RUN\MIGRATE_OANDA_MT5_VPS_CLEAN.ps1"
$researchDataContractScript = Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1"
$learningDataContractAuditScript = Join-Path $ProjectRoot "RUN\BUILD_LEARNING_DATA_CONTRACT_AUDIT.ps1"
$researchPlanScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_INTENSIVE_RESEARCH_PLAN.ps1"
$learningHygieneScript = Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_PATH_HYGIENE.ps1"
$learningHotPathScript = Join-Path $ProjectRoot "RUN\CLEAN_LEARNING_SUPERVISOR_HOT_PATH.ps1"
$learningWellbeingScript = Join-Path $ProjectRoot "RUN\MAINTAIN_LEARNING_WELLBEING.ps1"
$mt5QueueSyncScript = Join-Path $ProjectRoot "RUN\SYNC_MT5_RETEST_QUEUE_FROM_RESEARCH_PLAN.ps1"
$retestQueueScript = Join-Path $ProjectRoot "RUN\START_MICROBOT_RETEST_QUEUE_AFTER_IDLE_BACKGROUND.ps1"
$applyLaptopRuntimeScript = Join-Path $ProjectRoot "RUN\APPLY_LAPTOP_RESEARCH_RUNTIME.ps1"
$tripleLoopAuditScript = Join-Path $ProjectRoot "RUN\BUILD_MICROBOT_TRIPLE_LOOP_AUDIT.ps1"
$tuningEffectiveRepairScript = Join-Path $ProjectRoot "RUN\REPAIR_TUNING_EFFECTIVE_SYNC.ps1"
$profitTrackingScript = Join-Path $ProjectRoot "RUN\BUILD_PROFIT_TRACKING_REPORT.ps1"
$onnxFeedbackScript = Join-Path $ProjectRoot "RUN\BUILD_ONNX_FEEDBACK_LOOP_REPORT.ps1"
$dailySystemReportScript = Join-Path $ProjectRoot "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1"
$paperLiveFeedbackScript = Join-Path $ProjectRoot "RUN\BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1"
$hostingReportScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_HOSTING_DAILY_REPORT.ps1"
$technicalReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_TECHNICAL_READINESS_REPORT.ps1"
$dataReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_DATA_READINESS_REPORT.ps1"
$trainingReadinessScript = Join-Path $ProjectRoot "RUN\BUILD_INSTRUMENT_TRAINING_READINESS_REPORT.ps1"
$trustButVerifyScript = Join-Path $ProjectRoot "RUN\BUILD_TRUST_BUT_VERIFY_AUDIT.ps1"
$snapshotScript = Join-Path $ProjectRoot "RUN\SAVE_LOCAL_OPERATOR_SNAPSHOT.ps1"
$fullStackAuditScript = Join-Path $ProjectRoot "RUN\BUILD_FULL_STACK_AUDIT.ps1"
$archiverScript = Join-Path $ProjectRoot "RUN\START_LOCAL_OPERATOR_ARCHIVER_BACKGROUND.ps1"
$mt5WatcherScript = Join-Path $ProjectRoot "RUN\START_MT5_TESTER_STATUS_WATCHER_BACKGROUND.ps1"
$mt5RiskGuardScript = Join-Path $ProjectRoot "RUN\START_MT5_RISK_POPUP_GUARD_BACKGROUND.ps1"
$weakestBatchScript = Join-Path $ProjectRoot "RUN\START_WEAKEST_MT5_BATCH_BACKGROUND.ps1"
$nearProfitBatchScript = Join-Path $ProjectRoot "RUN\START_NEAR_PROFIT_OPTIMIZATION_AFTER_IDLE_BACKGROUND.ps1"
$qdmWeakestScript = Join-Path $ProjectRoot "RUN\START_QDM_WEAKEST_SYNC_BACKGROUND.ps1"
$mlScript = Join-Path $ProjectRoot "RUN\START_REFRESH_AND_TRAIN_MICROBOT_ML_BACKGROUND.ps1"
$perfScript = Join-Path $ProjectRoot "RUN\APPLY_WORKSTATION_PERF_TUNING.ps1"
$statusDir = Join-Path $ProjectRoot "EVIDENCE\OPS"
$researchContractManifestPath = "C:\TRADING_DATA\RESEARCH\reports\research_contract_manifest_latest.json"
$mt5StatusPath = Join-Path $statusDir "mt5_tester_status_latest.json"
$mt5QueuePath = Join-Path $statusDir "mt5_retest_queue_latest.json"
$nearProfitQueuePath = Join-Path $statusDir "near_profit_optimization_queue_latest.json"
$dailySystemReportPath = Join-Path $ProjectRoot "EVIDENCE\DAILY\raport_dzienny_latest.json"
$secondaryMt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe"

foreach ($path in @(
    $priorityScript,
    $qdmProfileScript,
    $mlHintsScript,
    $onnxMicroReviewScript,
    $activeFleetVerdictsScript,
    $winnerDeploymentScript,
    $learningHealthRegistryScript,
    $learningPaperRuntimePlanScript,
    $paperRuntimeMigrationScript,
    $researchDataContractScript,
    $learningDataContractAuditScript,
    $researchPlanScript,
    $learningHygieneScript,
    $learningHotPathScript,
    $learningWellbeingScript,
    $mt5QueueSyncScript,
    $retestQueueScript,
    $applyLaptopRuntimeScript,
    $tripleLoopAuditScript,
    $tuningEffectiveRepairScript,
    $profitTrackingScript,
    $onnxFeedbackScript,
    $dailySystemReportScript,
    $paperLiveFeedbackScript,
    $hostingReportScript,
    $technicalReadinessScript,
    $dataReadinessScript,
    $trainingReadinessScript,
    $trustButVerifyScript,
    $snapshotScript,
    $fullStackAuditScript,
    $archiverScript,
    $mt5WatcherScript,
    $mt5RiskGuardScript,
    $weakestBatchScript,
    $nearProfitBatchScript,
    $qdmWeakestScript,
    $mlScript,
    $perfScript
)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $statusDir | Out-Null

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

function Ensure-BackgroundTask {
    param(
        [string]$Label,
        [scriptblock]$IsRunning,
        [string]$StarterPath = "",
        [scriptblock]$StarterOperation = $null
    )

    if (& $IsRunning) {
        return "already_running"
    }

    if ($null -ne $StarterOperation) {
        & $StarterOperation | Out-Host
    }
    elseif (-not [string]::IsNullOrWhiteSpace($StarterPath)) {
        & $StarterPath | Out-Host
    }
    else {
        throw "Missing starter for background task: $Label"
    }
    return "started"
}

function Get-FileAgeSecondsOrMax {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [int]::MaxValue
    }

    return [int][math]::Round(((Get-Date) - (Get-Item -LiteralPath $Path).LastWriteTime).TotalSeconds)
}

function Read-JsonOrNull {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    catch {
        return $null
    }
}

function Get-PlanSummaryValue {
    param(
        [object]$PlanReport,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $PlanReport -or -not (Test-ObjectHasProperty -Object $PlanReport -Name "summary")) {
        return $Default
    }

    $summary = $PlanReport.summary
    if ($null -eq $summary -or -not (Test-ObjectHasProperty -Object $summary -Name $Name)) {
        return $Default
    }

    return $summary.$Name
}

function Get-PaperRuntimeRepairAssessment {
    param(
        [object]$PlanReport,
        [string]$StampPath,
        [int]$CooldownSeconds = 1800
    )

    $overallAction = [string](Get-PlanSummaryValue -PlanReport $PlanReport -Name "overall_action" -Default "UNKNOWN")
    $shadowGap = [int](Get-PlanSummaryValue -PlanReport $PlanReport -Name "symbols_shadow_observation_gap" -Default 0)
    $rolloutAllowed = [bool](Get-PlanSummaryValue -PlanReport $PlanReport -Name "autonomous_rollout_allowed" -Default $false)

    $result = [ordered]@{
        needs_repair = $false
        reason = "not_needed"
        overall_action = $overallAction
        shadow_gap = $shadowGap
    }

    if (-not $rolloutAllowed) {
        $result.reason = "gate_blocked"
        return [pscustomobject]$result
    }

    if ($overallAction -notin @("ODSWIEZ_PAPER_RUNTIME", "NAPRAW_CIEN_ONNX_NA_PAPER")) {
        return [pscustomobject]$result
    }

    if ($overallAction -eq "NAPRAW_CIEN_ONNX_NA_PAPER" -and $shadowGap -le 0) {
        return [pscustomobject]$result
    }

    if (Test-Path -LiteralPath $StampPath) {
        try {
            $stamp = Get-Content -LiteralPath $StampPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $stampAt = if ($stamp.at_local) { [datetime]$stamp.at_local } else { [datetime]::MinValue }
            if ($stampAt -ne [datetime]::MinValue) {
                $ageSeconds = [int][math]::Round(((Get-Date) - $stampAt).TotalSeconds)
                if ($ageSeconds -lt $CooldownSeconds) {
                    $result.reason = "cooldown_active"
                    return [pscustomobject]$result
                }
            }
        }
        catch {
        }
    }

    $result.needs_repair = $true
    $result.reason = "repair_needed"
    return [pscustomobject]$result
}

function Test-ObjectHasProperty {
    param(
        $Object,
        [string]$Name
    )

    if ($null -eq $Object -or [string]::IsNullOrWhiteSpace($Name)) {
        return $false
    }

    try {
        $properties = $Object.PSObject.Properties
        if ($null -eq $properties) {
            return $false
        }

        return ($properties.Name -contains $Name)
    }
    catch {
        return $false
    }
}

function Invoke-SupervisorAction {
    param(
        [System.Collections.IDictionary]$Actions,
        [string]$Name,
        [scriptblock]$Operation
    )

    Write-Host ("[{0}] START {1}" -f (Get-Date -Format "HH:mm:ss"), $Name)
    try {
        $result = & $Operation
        if ($null -eq $result -or [string]::IsNullOrWhiteSpace([string]$result)) {
            $Actions[$Name] = "ok"
        }
        else {
            $Actions[$Name] = [string]$result
        }
        Write-Host ("[{0}] OK {1} => {2}" -f (Get-Date -Format "HH:mm:ss"), $Name, $Actions[$Name])
        return $true
    }
    catch {
        $message = $_.Exception.Message
        if (-not [string]::IsNullOrWhiteSpace($message)) {
            $message = (($message -replace '\s+', ' ').Trim())
        }
        else {
            $message = "unknown_error"
        }
        $position = if ($null -ne $_.InvocationInfo -and -not [string]::IsNullOrWhiteSpace($_.InvocationInfo.PositionMessage)) {
            ($_.InvocationInfo.PositionMessage -replace '\s+', ' ').Trim()
        }
        else {
            ""
        }
        if (-not [string]::IsNullOrWhiteSpace($position)) {
            $message = "$message | $position"
        }
        $Actions[$Name] = "failed: $message"
        Write-Warning ("[{0}] FAIL {1} => {2}" -f (Get-Date -Format "HH:mm:ss"), $Name, $Actions[$Name])
        return $false
    }
}

function Get-WeakestMt5ActivityCount {
    param(
        [string]$Mt5StatusPath
    )

    $wrapperCount = Get-WrapperCount -Pattern "*weakest_mt5_batch_wrapper_*"
    if ($wrapperCount -gt 0) {
        return $wrapperCount
    }

    $mt5Status = Read-JsonOrNull -Path $Mt5StatusPath
    if ($null -eq $mt5Status) {
        return 0
    }

    $state = [string]$mt5Status.state
    $watchedTerminalRunning = [bool]$mt5Status.watched_terminal_running
    $watchedMetaTesterRunning = [bool]$mt5Status.watched_metatester_running
    $watchedExecutorRunning = [bool]$mt5Status.watched_executor_running

    if ($state -eq "running" -and ($watchedTerminalRunning -or $watchedMetaTesterRunning -or $watchedExecutorRunning)) {
        return 1
    }

    return 0
}

function Get-SystemBootAgeMinutes {
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        if ($null -eq $os -or $null -eq $os.LastBootUpTime) {
            return -1
        }

        return [int][Math]::Round(((Get-Date) - $os.LastBootUpTime).TotalMinutes)
    }
    catch {
        return -1
    }
}

function Resolve-LearningPerfProfile {
    param([int]$StartupTurboMinutes)

    $bootAgeMinutes = Get-SystemBootAgeMinutes
    $startupTurboActive = ($bootAgeMinutes -ge 0 -and $bootAgeMinutes -le $StartupTurboMinutes)
    $profile = if ($startupTurboActive) { "OfflineMax" } else { "ConcurrentLab" }

    return [pscustomobject]@{
        profile = $profile
        boot_age_minutes = $bootAgeMinutes
        startup_turbo_active = $startupTurboActive
    }
}

function Stop-WrapperProcessesByPattern {
    param([string[]]$Patterns)

    $stopped = 0
    foreach ($pattern in @($Patterns | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $processes = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    $_.Name -eq "powershell.exe" -and
                    -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                    $_.CommandLine -like $pattern
                }
        )

        foreach ($proc in $processes) {
            try {
                Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
                $stopped++
            }
            catch {
            }
        }
    }

    return $stopped
}

function Get-Mt5RestartAssessment {
    param(
        [string]$Mt5StatusPath,
        [string]$Mt5QueuePath
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    $mt5Status = Read-JsonOrNull -Path $Mt5StatusPath
    $mt5Queue = Read-JsonOrNull -Path $Mt5QueuePath
    $statusAge = Get-FileAgeSecondsOrMax -Path $Mt5StatusPath
    $queueAge = Get-FileAgeSecondsOrMax -Path $Mt5QueuePath

    if ($null -ne $mt5Status) {
        $statusState = [string]$mt5Status.state
        $watchedTerminalRunning = [bool]$mt5Status.watched_terminal_running
        $watchedMetaTesterRunning = [bool]$mt5Status.watched_metatester_running
        $watchedExecutorRunning = [bool]$mt5Status.watched_executor_running
        if ($statusState -eq "stale") {
            [void]$reasons.Add("tester_stale")
        }
        elseif ($statusState -eq "running" -and -not ($watchedTerminalRunning -or $watchedMetaTesterRunning -or $watchedExecutorRunning)) {
            [void]$reasons.Add("tester_running_without_process")
        }
    }

    if ($statusAge -gt 900) {
        [void]$reasons.Add("tester_status_old")
    }

    if ($null -ne $mt5Queue) {
        $queueState = [string]$mt5Queue.state
        if ($queueState -eq "stale") {
            [void]$reasons.Add("queue_stale")
        }
    }

    if ($queueAge -gt 1800) {
        [void]$reasons.Add("queue_status_old")
    }

    return [pscustomobject]@{
        needs_restart = ($reasons.Count -gt 0)
        reasons = @($reasons)
    }
}

function Get-NearProfitRestartAssessment {
    param([string]$NearProfitQueuePath)

    $reasons = New-Object System.Collections.Generic.List[string]
    $queue = Read-JsonOrNull -Path $NearProfitQueuePath
    $queueAge = Get-FileAgeSecondsOrMax -Path $NearProfitQueuePath

    if ($null -ne $queue) {
        $state = [string]$queue.state
        if ($state -eq "stale") {
            [void]$reasons.Add("near_profit_stale")
        }

        if ((Test-ObjectHasProperty -Object $queue -Name "run_timeout_near") -and [bool]$queue.run_timeout_near) {
            [void]$reasons.Add("near_profit_timeout")
        }

        if (Test-ObjectHasProperty -Object $queue -Name "run_remaining_sec") {
            try {
                if ([int]$queue.run_remaining_sec -lt -300) {
                    [void]$reasons.Add("near_profit_negative_remaining")
                }
            }
            catch {
            }
        }
    }

    if ($queueAge -gt 1800) {
        [void]$reasons.Add("near_profit_status_old")
    }

    return [pscustomobject]@{
        needs_restart = ($reasons.Count -gt 0)
        reasons = @($reasons)
    }
}

function Write-SupervisorStatus {
    param(
        [int]$Cycle,
        [System.Collections.IDictionary]$Actions,
        [string]$LearningPerfProfile,
        [int]$BootAgeMinutes,
        [bool]$StartupTurboActive
    )

    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object { $_.ProcessName -in @("terminal64", "metatester64", "qdmcli", "python") } |
        Sort-Object ProcessName, Id |
        ForEach-Object {
            [pscustomobject]@{
                process = $_.ProcessName
                id = $_.Id
                priority = [string]$_.PriorityClass
                ram_mb = [math]::Round($_.WorkingSet64 / 1MB, 1)
            }
        }

    $priorityReportPath = Join-Path $statusDir "tuning_priority_latest.json"
    $priorityHead = @()
    if (Test-Path -LiteralPath $priorityReportPath) {
        $priorityReport = Get-Content -LiteralPath $priorityReportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $priorityHead = @($priorityReport.ranked_instruments | Select-Object -First 6)
    }

    $mlHintsPath = Join-Path $statusDir "ml_tuning_hints_latest.json"
    $mlHintHead = @()
    if (Test-Path -LiteralPath $mlHintsPath) {
        $mlHints = Get-Content -LiteralPath $mlHintsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $mlHintHead = @($mlHints.items | Select-Object -First 4)
    }

    $qdmProfilePath = Join-Path $statusDir "qdm_weakest_profile_latest.json"
    $qdmHead = @()
    if (Test-Path -LiteralPath $qdmProfilePath) {
        $qdmProfile = Get-Content -LiteralPath $qdmProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $qdmHead = @($qdmProfile.included | Select-Object -First 4)
    }

    $learningHealthPath = Join-Path $statusDir "learning_health_registry_latest.json"
    $learningHealth = $null
    $learningHealthHead = @()
    if (Test-Path -LiteralPath $learningHealthPath) {
        $learningHealth = Get-Content -LiteralPath $learningHealthPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $learningHealthHead = @($learningHealth.top_pressure | Select-Object -First 5)
    }

    $learningPaperRuntimePath = Join-Path $statusDir "learning_paper_runtime_plan_latest.json"
    $learningPaperRuntime = $null
    $learningPaperRuntimeHead = @()
    if (Test-Path -LiteralPath $learningPaperRuntimePath) {
        $learningPaperRuntime = Get-Content -LiteralPath $learningPaperRuntimePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $learningPaperRuntimeHead = @($learningPaperRuntime.top_refresh | Select-Object -First 5)
        if (@($learningPaperRuntimeHead).Count -eq 0) {
            $learningPaperRuntimeHead = @($learningPaperRuntime.top_runtime_active | Select-Object -First 5)
        }
    }

    $learningWellbeingPath = Join-Path $statusDir "learning_wellbeing_latest.json"
    $learningWellbeing = $null
    if (Test-Path -LiteralPath $learningWellbeingPath) {
        $learningWellbeing = Get-Content -LiteralPath $learningWellbeingPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $dataReadinessPath = Join-Path $statusDir "instrument_data_readiness_latest.json"
    $dataReadiness = $null
    $dataReadinessHead = @()
    if (Test-Path -LiteralPath $dataReadinessPath) {
        $dataReadiness = Get-Content -LiteralPath $dataReadinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $dataReadinessHead = @($dataReadiness.top_export_pending | Select-Object -First 5)
        if (@($dataReadinessHead).Count -eq 0) {
            $dataReadinessHead = @($dataReadiness.top_runtime_ready | Select-Object -First 5)
        }
    }

    $trainingReadinessPath = Join-Path $statusDir "instrument_training_readiness_latest.json"
    $trainingReadiness = $null
    $trainingReadinessHead = @()
    if (Test-Path -LiteralPath $trainingReadinessPath) {
        $trainingReadiness = Get-Content -LiteralPath $trainingReadinessPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $trainingReadinessHead = @($trainingReadiness.top_local_training_ready | Select-Object -First 5)
        if (@($trainingReadinessHead).Count -eq 0) {
            $trainingReadinessHead = @($trainingReadiness.top_shadow_ready | Select-Object -First 5)
        }
    }

    $trustButVerifyPath = Join-Path $statusDir "trust_but_verify_latest.json"
    $trustButVerify = $null
    if (Test-Path -LiteralPath $trustButVerifyPath) {
        $trustButVerify = Get-Content -LiteralPath $trustButVerifyPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $mt5QueuePath = Join-Path $statusDir "mt5_retest_queue_latest.json"
    $mt5Queue = $null
    if (Test-Path -LiteralPath $mt5QueuePath) {
        $mt5Queue = Get-Content -LiteralPath $mt5QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $tripleLoopAuditPath = Join-Path $statusDir "microbot_triple_loop_audit_latest.json"
    $tripleLoopAudit = $null
    if (Test-Path -LiteralPath $tripleLoopAuditPath) {
        $tripleLoopAudit = Get-Content -LiteralPath $tripleLoopAuditPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }

    $status = [ordered]@{
        generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        cycle = $Cycle
        learning_perf_profile = $LearningPerfProfile
        startup_turbo_active = $StartupTurboActive
        boot_age_minutes = $BootAgeMinutes
        actions = $Actions
        processes = $processes
        top_priority = $priorityHead
        top_ml_hints = $mlHintHead
        top_qdm_profile = $qdmHead
        learning_health = $learningHealth
        top_learning_health = $learningHealthHead
        learning_paper_runtime = $learningPaperRuntime
        top_learning_paper_runtime = $learningPaperRuntimeHead
        learning_wellbeing = $learningWellbeing
        instrument_data_readiness = $dataReadiness
        top_instrument_data_readiness = $dataReadinessHead
        instrument_training_readiness = $trainingReadiness
        top_instrument_training_readiness = $trainingReadinessHead
        trust_but_verify = $trustButVerify
        mt5_retest_queue = $mt5Queue
    }

    $jsonLatest = Join-Path $statusDir "autonomous_90p_latest.json"
    $mdLatest = Join-Path $statusDir "autonomous_90p_latest.md"
    $status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Autonomous 90P Latest")
    $lines.Add("")
    $lines.Add(("- generated_at_local: {0}" -f $status.generated_at_local))
    $lines.Add(("- cycle: {0}" -f $Cycle))
    $lines.Add(("- learning_perf_profile: {0}" -f $LearningPerfProfile))
    $lines.Add(("- startup_turbo_active: {0}" -f $StartupTurboActive))
    $lines.Add(("- boot_age_minutes: {0}" -f $BootAgeMinutes))
    $lines.Add("")
    $lines.Add("## Actions")
    $lines.Add("")
    foreach ($key in $Actions.Keys | Sort-Object) {
        $lines.Add(("- {0}: {1}" -f $key, $Actions[$key]))
    }
    $lines.Add("")
    $lines.Add("## Processes")
    $lines.Add("")
    foreach ($proc in $processes) {
        $lines.Add(("- {0} #{1}: priority={2}, ram_mb={3}" -f $proc.process, $proc.id, $proc.priority, $proc.ram_mb))
    }
    $lines.Add("")
    $lines.Add("## Top Priority")
    $lines.Add("")
    foreach ($item in $priorityHead) {
        $lines.Add(("- #{0} {1}: score={2}, trust={3}, cost={4}, sample={5}, live_net_24h={6}, action={7}" -f
            $item.rank,
            $item.symbol_alias,
            $item.priority_score,
            $item.trust_state,
            $item.cost_state,
            $item.learning_sample_count,
            $item.live_net_24h,
            $item.recommended_action))
    }
    $lines.Add("")
    $lines.Add("## Top ML Hints")
    $lines.Add("")
    foreach ($item in $mlHintHead) {
        $firstHint = if (@($item.hints).Count -gt 0) { [string]$item.hints[0] } else { "none" }
        $lines.Add(("- #{0} {1}: ml_risk_score={2}, hint={3}" -f
            $item.rank,
            $item.symbol_alias,
            $item.ml_risk_score,
            $firstHint))
    }
    $lines.Add("")
    $lines.Add("## Top QDM Weakest Profile")
    $lines.Add("")
    foreach ($item in $qdmHead) {
        $lines.Add(("- #{0} {1}: qdm_symbol={2}, datasource={3}, export={4}" -f
            $item.rank,
            $item.symbol_alias,
            $item.qdm_symbol,
            $item.datasource,
            $item.mt5_export_name))
    }
    $lines.Add("")
    $lines.Add("## Instrument Data Readiness")
    $lines.Add("")
    if ($null -ne $dataReadiness) {
        $lines.Add(("- export_pending_count: {0}" -f $dataReadiness.summary.export_pending_count))
        $lines.Add(("- contract_pending_count: {0}" -f $dataReadiness.summary.contract_pending_count))
        $lines.Add(("- qdm_contract_ready_count: {0}" -f $dataReadiness.summary.qdm_contract_ready_count))
        foreach ($item in $dataReadinessHead) {
            $lines.Add(("- {0}: state={1}, export={2}, qdm_rows={3}, candidate_rows={4}, outcome_rows={5}" -f
                $item.symbol_alias,
                $item.data_readiness_state,
                $item.active_export_present,
                $item.qdm_contract_rows,
                $item.candidate_contract_rows,
                $item.outcome_rows))
        }
    }
    else {
        $lines.Add("- instrument data readiness report not available")
    }
    $lines.Add("")
    $lines.Add("## Instrument Training Readiness")
    $lines.Add("")
    if ($null -ne $trainingReadiness) {
        $lines.Add(("- shadow_ready_count: {0}" -f $trainingReadiness.summary.training_shadow_ready_count))
        $lines.Add(("- local_training_limited_count: {0}" -f $trainingReadiness.summary.local_training_limited_count))
        $lines.Add(("- local_training_ready_count: {0}" -f $trainingReadiness.summary.local_training_ready_count))
        foreach ($item in $trainingReadinessHead) {
            $lines.Add(("- {0}: readiness={1}, eligibility={2}, teacher_dependency={3}, action={4}" -f
                $item.symbol_alias,
                $item.training_readiness_state,
                $item.local_training_eligibility,
                $item.teacher_dependency_level,
                $item.next_safe_action))
        }
    }
    else {
        $lines.Add("- instrument training readiness report not available")
    }
    $lines.Add("")
    $lines.Add("## Learning Health")
    $lines.Add("")
    if ($null -ne $learningHealth) {
        $lines.Add(("- fallback_globalny: {0}" -f $learningHealth.summary.fallback_globalny))
        $lines.Add(("- mala_probka: {0}" -f $learningHealth.summary.mala_probka))
        $lines.Add(("- wymaga_doszkolenia: {0}" -f $learningHealth.summary.wymaga_doszkolenia))
        $lines.Add(("- wymaga_regeneracji: {0}" -f $learningHealth.summary.wymaga_regeneracji))
        $lines.Add(("- runtime_active_symbols: {0}" -f $learningHealth.summary.runtime_active_symbols))
        foreach ($item in $learningHealthHead) {
            $lines.Add(("- {0}: health={1}, mode={2}, rank={3}, onnx={4}/{5}, runtime_rows={6}" -f
                $item.symbol_alias,
                $item.learning_health_state,
                $item.work_mode,
                $item.priority_rank,
                $item.onnx_status,
                $item.onnx_quality,
                $item.sample_runtime_onnx_rows))
        }
    }
    else {
        $lines.Add("- learning health registry not available")
    }
    $lines.Add("")
    $lines.Add("## Paper Runtime Learning")
    $lines.Add("")
    if ($null -ne $learningPaperRuntime) {
        $lines.Add(("- overall_action: {0}" -f $learningPaperRuntime.summary.overall_action))
        $lines.Add(("- symbols_to_refresh: {0}" -f $learningPaperRuntime.summary.symbols_to_refresh))
        $lines.Add(("- symbols_collecting: {0}" -f $learningPaperRuntime.summary.symbols_collecting))
        $lines.Add(("- symbols_runtime_active: {0}" -f $learningPaperRuntime.summary.symbols_runtime_active))
        foreach ($item in $learningPaperRuntimeHead) {
            $lines.Add(("- {0}: action={1}, role={2}, health={3}, runtime_rows={4}" -f
                $item.symbol_alias,
                $item.migration_action,
                $item.paper_learning_role,
                $item.learning_health_state,
                $item.runtime_rows))
        }
    }
    else {
        $lines.Add("- learning paper runtime plan not available")
    }
    $lines.Add("")
    $lines.Add("## Learning Wellbeing")
    $lines.Add("")
    if ($null -ne $learningWellbeing) {
        $lines.Add(("- verdict: {0}" -f $learningWellbeing.verdict))
        $lines.Add(("- total_freed_gb: {0}" -f $learningWellbeing.summary.total_freed_gb))
        $lines.Add(("- ops_deleted_count: {0}" -f $learningWellbeing.summary.ops_deleted_count))
        $lines.Add(("- runtime_archive_deleted_count: {0}" -f $learningWellbeing.summary.runtime_archive_deleted_count))
        $lines.Add(("- runtime_empty_dirs_removed: {0}" -f $learningWellbeing.summary.runtime_empty_dirs_removed))
        if ($null -ne $learningWellbeing.vps_spool_bridge) {
            $lines.Add(("- vps_spool_bridge: {0}" -f $learningWellbeing.vps_spool_bridge.verdict))
            $lines.Add(("- vps_bridge_pending_sync_count: {0}" -f $learningWellbeing.summary.vps_bridge_pending_sync_count))
            $lines.Add(("- vps_bridge_repair_actions_count: {0}" -f $learningWellbeing.summary.vps_bridge_repair_actions_count))
        }
    }
    else {
        $lines.Add("- learning wellbeing report not available")
    }
    $lines.Add("")
    $lines.Add("## Trust But Verify")
    $lines.Add("")
    if ($null -ne $trustButVerify) {
        $lines.Add(("- verdict: {0}" -f $trustButVerify.verdict))
        $lines.Add(("- needs_manual_eye: {0}" -f $trustButVerify.needs_manual_eye))
        foreach ($finding in @($trustButVerify.findings | Select-Object -First 3)) {
            $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
        }
    }
    else {
        $lines.Add("- trust-but-verify report not available")
    }
    $lines.Add("")
    $lines.Add("## MT5 Retest Queue")
    $lines.Add("")
    if ($null -ne $mt5Queue) {
        $lines.Add(("- state: {0}" -f $mt5Queue.state))
        $lines.Add(("- current_symbol: {0}" -f $mt5Queue.current_symbol))
        $completed = @($mt5Queue.completed)
        $pending = @($mt5Queue.pending)
        $lines.Add(("- completed: {0}" -f $(if ($completed.Count -gt 0) { $completed -join ", " } else { "none" })))
        $lines.Add(("- pending: {0}" -f $(if ($pending.Count -gt 0) { $pending -join ", " } else { "none" })))
    }
    else {
        $lines.Add("- queue status not available")
    }
    $lines.Add("")
    $lines.Add("## Triple Loop Audit")
    $lines.Add("")
    if ($null -ne $tripleLoopAudit) {
        $lines.Add(("- critical_count: {0}" -f $tripleLoopAudit.summary.critical_count))
        $lines.Add(("- warning_count: {0}" -f $tripleLoopAudit.summary.warning_count))
        foreach ($item in @($tripleLoopAudit.symbol_reports | Sort-Object @{ Expression = { $_.severity_counts.critical } ; Descending = $true }, @{ Expression = { $_.severity_counts.warning } ; Descending = $true }, symbol_alias | Select-Object -First 4)) {
            $lines.Add(("- {0}: critical={1}, warning={2}" -f $item.symbol_alias, $item.severity_counts.critical, $item.severity_counts.warning))
        }
    }
    else {
        $lines.Add("- triple loop audit not available")
    }
    ($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
}

$initialPerf = Resolve-LearningPerfProfile -StartupTurboMinutes $StartupTurboMinutes
& $perfScript -ThrottleInteractiveApps -MlPerfProfile $initialPerf.profile | Out-Host

$cycle = 0
while ($true) {
    $cycle++
    $learningPerf = Resolve-LearningPerfProfile -StartupTurboMinutes $StartupTurboMinutes

    $actions = [ordered]@{}

    Invoke-SupervisorAction -Actions $actions -Name "perf_tuning" -Operation {
        & $perfScript -ThrottleInteractiveApps -MlPerfProfile $learningPerf.profile | Out-Null
        "applied profile=$($learningPerf.profile)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "daily_system_report" -Operation {
        $dailyReportAge = Get-FileAgeSecondsOrMax -Path $dailySystemReportPath
        if ($dailyReportAge -le 3600) {
            return ("fresh age_s={0}" -f $dailyReportAge)
        }

        & $dailySystemReportScript | Out-Null
        $dailyReportAge = Get-FileAgeSecondsOrMax -Path $dailySystemReportPath
        "rebuilt age_s=$dailyReportAge"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "paper_live_feedback" -Operation {
        & $paperLiveFeedbackScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "hosting_report" -Operation {
        & $hostingReportScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "priority_report" -Operation {
        & $priorityScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "qdm_profile" -Operation {
        & $qdmProfileScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "ml_hints" -Operation {
        & $mlHintsScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "onnx_micro_review" -Operation {
        & $onnxMicroReviewScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "learning_path_hygiene" -Operation {
        $report = (& $learningHygieneScript -ProjectRoot $ProjectRoot -Apply | ConvertFrom-Json)
        "verdict=$($report.verdict); manifest_fresh=$($report.manifest.fresh)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "learning_hot_path" -Operation {
        $report = (& $learningHotPathScript -ProjectRoot $ProjectRoot -Apply | ConvertFrom-Json)
        "verdict=$($report.verdict); rotated=$($report.summary.rotated_count); waiting_hot=$($report.summary.waiting_hot_count)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "learning_wellbeing" -Operation {
        $report = (& $learningWellbeingScript -ProjectRoot $ProjectRoot -Apply | ConvertFrom-Json)
        "verdict=$($report.verdict); bridge=$($report.vps_spool_bridge.verdict); pending_sync=$($report.summary.vps_bridge_pending_sync_count); lag=$($report.summary.vps_bridge_export_lag_total); repairs=$($report.summary.vps_bridge_repair_actions_count); freed_gb=$($report.summary.total_freed_gb); ops_deleted=$($report.summary.ops_deleted_count); runtime_deleted=$($report.summary.runtime_archive_deleted_count)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "research_data_contract" -Operation {
        & $researchDataContractScript -ProjectRoot $ProjectRoot | Out-Null
        $contractManifest = Read-JsonOrNull -Path $researchContractManifestPath
        if ($null -eq $contractManifest) {
            return "contract_manifest_missing"
        }

        $contractVersion = if (Test-ObjectHasProperty -Object $contractManifest -Name "contract_version") {
            [string]$contractManifest.contract_version
        }
        else {
            "unknown"
        }
        $contractSummary = if (Test-ObjectHasProperty -Object $contractManifest -Name "summary") { $contractManifest.summary } else { $null }
        $tablesReady = if ($null -ne $contractSummary -and (Test-ObjectHasProperty -Object $contractSummary -Name "tables_ready")) {
            [string]$contractSummary.tables_ready
        }
        else {
            "unknown"
        }
        "contract_version=$contractVersion; tables_ready=$tablesReady"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "learning_data_contract_audit" -Operation {
        $report = (& $learningDataContractAuditScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
        "verdict=$($report.verdict); tables_ready=$($report.summary.tables_ready); findings=$($report.summary.findings_total); runtime_active=$($report.summary.runtime_active_symbols)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "laptop_runtime" -Operation {
        & $applyLaptopRuntimeScript | Out-Null
        "applied"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "mt5_queue_sync" -Operation {
        if ((Get-WrapperCount -Pattern "*mt5_retest_queue_wrapper_*") -gt 0) {
            return "skipped queue_wrapper_active"
        }
        & $mt5QueueSyncScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "tuning_effective_sync" -Operation {
        $repair = & $tuningEffectiveRepairScript
        "repaired count=$($repair.repaired_count)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "profit_tracking" -Operation {
        & $profitTrackingScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "onnx_feedback" -Operation {
        & $onnxFeedbackScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "technical_readiness" -Operation {
        & $technicalReadinessScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "instrument_data_readiness" -Operation {
        $report = (& $dataReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
        "export_pending=$($report.summary.export_pending_count); contract_pending=$($report.summary.contract_pending_count); runtime_ready=$($report.summary.onnx_runtime_ready_count)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "instrument_training_readiness" -Operation {
        $report = (& $trainingReadinessScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
        "shadow_ready=$($report.summary.training_shadow_ready_count); limited=$($report.summary.local_training_limited_count); ready=$($report.summary.local_training_ready_count)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "active_fleet_verdicts" -Operation {
        & $activeFleetVerdictsScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "winner_deployment" -Operation {
        & $winnerDeploymentScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "learning_health_registry" -Operation {
        $report = (& $learningHealthRegistryScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
        "fallback=$($report.summary.fallback_globalny); regeneracja=$($report.summary.wymaga_regeneracji); docisk=$($report.summary.do_docisku); runtime_active=$($report.summary.runtime_active_symbols)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "learning_paper_runtime_plan" -Operation {
        $report = (& $learningPaperRuntimePlanScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
        "overall=$($report.summary.overall_action); refresh=$($report.summary.symbols_to_refresh); collecting=$($report.summary.symbols_collecting); runtime_active=$($report.summary.symbols_runtime_active)"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "paper_runtime_self_heal" -Operation {
        $report = (& $learningPaperRuntimePlanScript -ProjectRoot $ProjectRoot | ConvertFrom-Json)
        $stampPath = Join-Path $statusDir "paper_runtime_self_heal_stamp.json"
        $assessment = Get-PaperRuntimeRepairAssessment -PlanReport $report -StampPath $stampPath
        if (-not $assessment.needs_repair) {
            return $assessment.reason
        }

        & $paperRuntimeMigrationScript | Out-Null
        [ordered]@{
            at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            overall_action = $assessment.overall_action
            shadow_gap = $assessment.shadow_gap
        } | ConvertTo-Json | Set-Content -LiteralPath $stampPath -Encoding UTF8
        return ("repaired action={0}; shadow_gap={1}" -f $assessment.overall_action, $assessment.shadow_gap)
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "research_plan" -Operation {
        & $researchPlanScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "triple_loop_audit" -Operation {
        & $tripleLoopAuditScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "archiver" -Operation {
        Ensure-BackgroundTask `
            -Label "archiver" `
            -IsRunning { (Get-WrapperCount -Pattern "*local_operator_archiver_*") -gt 0 } `
            -StarterPath $archiverScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "mt5_status_watcher" -Operation {
        Ensure-BackgroundTask `
            -Label "mt5_status_watcher" `
            -IsRunning { (Get-WrapperCount -Pattern "*mt5_tester_status_watcher_wrapper_*") -gt 0 } `
            -StarterPath $mt5WatcherScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "mt5_risk_guard" -Operation {
        Ensure-BackgroundTask `
            -Label "mt5_risk_guard" `
            -IsRunning { (Get-WrapperCount -Pattern "*mt5_risk_popup_guard_wrapper_*") -gt 0 } `
            -StarterPath $mt5RiskGuardScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "qdm" -Operation {
        Ensure-BackgroundTask `
            -Label "qdm" `
            -IsRunning { (Get-Process -Name qdmcli -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0 } `
            -StarterPath $qdmWeakestScript
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "ml" -Operation {
        Ensure-BackgroundTask `
            -Label "ml" `
            -IsRunning { (Get-WrapperCount -Pattern "*refresh_and_train_ml_wrapper_*") -gt 0 } `
            -StarterOperation { & $mlScript -ProjectRoot $ProjectRoot -PerfProfile $learningPerf.profile }
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "weakest_mt5" -Operation {
        $assessment = Get-Mt5RestartAssessment -Mt5StatusPath $mt5StatusPath -Mt5QueuePath $mt5QueuePath
        if ($assessment.needs_restart) {
            $stopped = Stop-WrapperProcessesByPattern -Patterns @(
                "*weakest_mt5_batch_wrapper_*",
                "*mt5_retest_queue_wrapper_*"
            )
            & $weakestBatchScript | Out-Host
            & $retestQueueScript | Out-Host
            return ("restarted reason={0} stopped={1}" -f (($assessment.reasons -join ",")), $stopped)
        }

        $weakestState = Ensure-BackgroundTask `
            -Label "weakest_mt5" `
            -IsRunning { (Get-WeakestMt5ActivityCount -Mt5StatusPath $mt5StatusPath) -gt 0 } `
            -StarterPath $weakestBatchScript

        $queueState = Ensure-BackgroundTask `
            -Label "mt5_retest_queue" `
            -IsRunning { (Get-WrapperCount -Pattern "*mt5_retest_queue_wrapper_*") -gt 0 } `
            -StarterPath $retestQueueScript

        return ("weakest={0}; queue={1}" -f $weakestState, $queueState)
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "near_profit_optimization" -Operation {
        $assessment = Get-NearProfitRestartAssessment -NearProfitQueuePath $nearProfitQueuePath
        if ($assessment.needs_restart) {
            $stopped = Stop-WrapperProcessesByPattern -Patterns @(
                "*near_profit_optimization_after_idle_wrapper_*",
                "*near_profit_mt5_risk_popup_guard_wrapper_*"
            )
            & $nearProfitBatchScript | Out-Host
            return ("restarted reason={0} stopped={1}" -f (($assessment.reasons -join ",")), $stopped)
        }

        Ensure-BackgroundTask `
            -Label "near_profit_optimization" `
            -IsRunning { (Get-WrapperCount -Pattern "*near_profit_optimization_after_idle_wrapper_*") -gt 0 } `
            -StarterPath $nearProfitBatchScript
    } | Out-Null

    Write-SupervisorStatus -Cycle $cycle -Actions $actions -LearningPerfProfile $learningPerf.profile -BootAgeMinutes $learningPerf.boot_age_minutes -StartupTurboActive $learningPerf.startup_turbo_active

    Invoke-SupervisorAction -Actions $actions -Name "trust_but_verify" -Operation {
        & $trustButVerifyScript | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "full_stack_audit" -Operation {
        & $fullStackAuditScript -ApplyLogRotation | Out-Null
        "rebuilt"
    } | Out-Null

    Invoke-SupervisorAction -Actions $actions -Name "snapshot" -Operation {
        & $snapshotScript | Out-Null
        "saved"
    } | Out-Null

    Write-SupervisorStatus -Cycle $cycle -Actions $actions -LearningPerfProfile $learningPerf.profile -BootAgeMinutes $learningPerf.boot_age_minutes -StartupTurboActive $learningPerf.startup_turbo_active

    if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
        break
    }

    Start-Sleep -Seconds $CycleSeconds
}
