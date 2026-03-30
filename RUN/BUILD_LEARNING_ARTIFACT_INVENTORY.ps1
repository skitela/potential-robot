param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$UniversePlanPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\scalping_universe_plan.json",
    [int]$CriticalFreshnessSeconds = 3600,
    [int]$LiveLogFreshnessHours = 72,
    [int]$LearningLogFreshnessHours = 120,
    [int]$LearningProgressAlertMinutes = 30,
    [int]$QdmSmokeKeepRunsPerSymbol = 4,
    [int]$QdmSmokeRetentionDays = 2,
    [int]$StrategyTesterKeepRunsPerSymbol = 12,
    [int]$StrategyTesterRetentionDays = 2,
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
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
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

        $value = $property.Value
        if ($null -eq $value) {
            return $Default
        }

        return $value
    }
    catch {
        return $Default
    }
}

function Test-NonEmpty {
    param([object]$Value)

    return -not [string]::IsNullOrWhiteSpace([string]$Value)
}

function Convert-ToStorageToken {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value -replace '[^A-Za-z0-9_-]', '_').Trim('_'))
}

function Get-FileState {
    param(
        [string]$Name,
        [string]$Path,
        [int]$ThresholdSeconds,
        [string]$Category
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            name = $Name
            category = $Category
            path = $Path
            exists = $false
            fresh = $false
            age_seconds = $null
            threshold_seconds = $ThresholdSeconds
            size_kb = 0.0
            last_write_local = $null
            last_write_unix = $null
        }
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)
    return [pscustomobject]@{
        name = $Name
        category = $Category
        path = $Path
        exists = $true
        fresh = ($ageSeconds -le $ThresholdSeconds)
        age_seconds = $ageSeconds
        threshold_seconds = $ThresholdSeconds
        size_kb = [math]::Round($item.Length / 1KB, 2)
        last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        last_write_unix = ([DateTimeOffset]$item.LastWriteTime).ToUnixTimeSeconds()
    }
}

function Get-LatestProgressState {
    param(
        [object[]]$States,
        [int]$AlertSeconds
    )

    $existing = @($States | Where-Object { $null -ne $_ -and $_.exists -and $null -ne $_.last_write_unix })
    if ($existing.Count -le 0) {
        return [pscustomobject]@{
            exists = $false
            active_within_alert = $false
            age_seconds = $null
            last_write_local = $null
            source = ""
        }
    }

    $latest = $existing | Sort-Object { [long]$_.last_write_unix } -Descending | Select-Object -First 1
    $ageSeconds = if ($null -ne $latest.age_seconds) { [int]$latest.age_seconds } else { $null }
    return [pscustomobject]@{
        exists = $true
        active_within_alert = ($null -ne $ageSeconds -and $ageSeconds -le $AlertSeconds)
        age_seconds = $ageSeconds
        last_write_local = $latest.last_write_local
        source = $latest.name
    }
}

function Invoke-RepairScript {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        return [pscustomobject]@{
            ok = $false
            message = "missing_script"
        }
    }

    try {
        & $ScriptPath @Parameters | Out-Null
        return [pscustomobject]@{
            ok = $true
            message = "ok"
        }
    }
    catch {
        return [pscustomobject]@{
            ok = $false
            message = $_.Exception.Message
        }
    }
}

function Get-TrainingUniverseSymbols {
    param(
        [string]$Path,
        [string]$LogsRoot
    )

    $symbols = New-Object System.Collections.Generic.List[string]
    $plan = Read-JsonSafe -Path $Path
    if ($null -ne $plan) {
        foreach ($symbol in @($plan.training_universe)) {
            $normalized = ([string]$symbol).Trim().ToUpperInvariant()
            if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $symbols.Contains($normalized)) {
                $symbols.Add($normalized) | Out-Null
            }
        }
    }

    if ((Test-Path -LiteralPath $LogsRoot) -and $symbols.Count -eq 0) {
        foreach ($dir in @(Get-ChildItem -LiteralPath $LogsRoot -Directory -ErrorAction SilentlyContinue)) {
            $normalized = ([string]$dir.Name).Trim().ToUpperInvariant()
            if (-not [string]::IsNullOrWhiteSpace($normalized) -and -not $symbols.Contains($normalized)) {
                $symbols.Add($normalized) | Out-Null
            }
        }
    }

    return @($symbols.ToArray() | Sort-Object)
}

function Get-DirectorySnapshot {
    param(
        [string]$Name,
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            name = $Name
            path = $Path
            exists = $false
            file_count = 0
            total_size_gb = 0.0
            newest_write_local = $null
        }
    }

    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -ErrorAction SilentlyContinue)
    $totalBytes = [int64](($files | Measure-Object -Property Length -Sum).Sum)
    $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return [pscustomobject]@{
        name = $Name
        path = $Path
        exists = $true
        file_count = $files.Count
        total_size_gb = [math]::Round($totalBytes / 1GB, 3)
        newest_write_local = if ($null -ne $newest) { $newest.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
    }
}

function Invoke-QdmSmokeRetention {
    param(
        [string]$SmokeRoot,
        [int]$KeepRunsPerSymbol,
        [int]$RetentionDays,
        [switch]$Apply
    )

    $pending = New-Object System.Collections.Generic.List[object]
    $archived = New-Object System.Collections.Generic.List[object]
    $freedBytes = [int64]0

    if (-not (Test-Path -LiteralPath $SmokeRoot)) {
        return [pscustomobject]@{
            pending = @()
            archived = @()
            freed_gb = 0.0
        }
    }

    $summaryFiles = @(
        Get-ChildItem -LiteralPath $SmokeRoot -File -Filter "*_summary.json" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs($RetentionDays))
    $runsBySymbol = @{}

    foreach ($summaryFile in $summaryFiles) {
        $runId = [System.IO.Path]::GetFileNameWithoutExtension($summaryFile.Name) -replace "_summary$",""
        if ($runId -notmatch '^(?<symbol>[a-z0-9\-]+)_strategy_tester_\d{8}_\d{6}$') {
            continue
        }

        $symbol = $Matches.symbol.ToUpperInvariant()
        if (-not $runsBySymbol.ContainsKey($symbol)) {
            $runsBySymbol[$symbol] = New-Object System.Collections.Generic.List[object]
        }

        $runsBySymbol[$symbol].Add([pscustomobject]@{
            symbol = $symbol
            run_id = $runId
            summary = $summaryFile
        }) | Out-Null
    }

    foreach ($symbol in @($runsBySymbol.Keys)) {
        $runs = @($runsBySymbol[$symbol] | Sort-Object { $_.summary.LastWriteTime } -Descending)
        if ($runs.Count -le $KeepRunsPerSymbol) {
            continue
        }

        foreach ($run in @($runs | Select-Object -Skip $KeepRunsPerSymbol | Where-Object { $_.summary.LastWriteTime -lt $cutoff })) {
            $files = @(Get-ChildItem -LiteralPath $SmokeRoot -File -Filter ($run.run_id + "*") -ErrorAction SilentlyContinue)
            if ($files.Count -eq 0) {
                continue
            }

            $row = [pscustomobject]@{
                symbol = $run.symbol
                run_id = $run.run_id
                file_count = $files.Count
                total_size_mb = [math]::Round((($files | Measure-Object -Property Length -Sum).Sum) / 1MB, 2)
                last_write_local = $run.summary.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            if ($Apply) {
                $archiveRoot = Join-Path $SmokeRoot ("archive\{0}\{1}" -f $run.symbol, $run.run_id)
                New-DirectoryIfMissing -Path $archiveRoot
                foreach ($file in $files) {
                    Move-Item -LiteralPath $file.FullName -Destination (Join-Path $archiveRoot $file.Name) -Force
                    $freedBytes += [int64]$file.Length
                }
                $archived.Add($row) | Out-Null
            }
            else {
                $pending.Add($row) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        pending = @($pending.ToArray())
        archived = @($archived.ToArray())
        freed_gb = [math]::Round($freedBytes / 1GB, 3)
    }
}

function Invoke-StrategyTesterRetention {
    param(
        [string]$RunRoot,
        [int]$KeepRunsPerSymbol,
        [int]$RetentionDays,
        [switch]$Apply
    )

    $pending = New-Object System.Collections.Generic.List[object]
    $archived = New-Object System.Collections.Generic.List[object]
    $freedBytes = [int64]0

    if (-not (Test-Path -LiteralPath $RunRoot)) {
        return [pscustomobject]@{
            pending = @()
            archived = @()
            freed_gb = 0.0
        }
    }

    $iniFiles = @(
        Get-ChildItem -LiteralPath $RunRoot -File -Filter "*_strategy_tester_*.ini" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending
    )
    $cutoff = (Get-Date).AddDays(-1 * [Math]::Abs($RetentionDays))
    $filesBySymbol = @{}

    foreach ($file in $iniFiles) {
        if ($file.Name -notmatch '^(?<symbol>[a-z0-9\-]+)_strategy_tester_\d{8}_\d{6}\.ini$') {
            continue
        }

        $symbol = $Matches.symbol.ToUpperInvariant()
        if (-not $filesBySymbol.ContainsKey($symbol)) {
            $filesBySymbol[$symbol] = New-Object System.Collections.Generic.List[object]
        }

        $filesBySymbol[$symbol].Add($file) | Out-Null
    }

    foreach ($symbol in @($filesBySymbol.Keys)) {
        $files = @($filesBySymbol[$symbol] | Sort-Object LastWriteTime -Descending)
        if ($files.Count -le $KeepRunsPerSymbol) {
            continue
        }

        foreach ($file in @($files | Select-Object -Skip $KeepRunsPerSymbol | Where-Object { $_.LastWriteTime -lt $cutoff })) {
            $row = [pscustomobject]@{
                symbol = $symbol
                file = $file.Name
                size_kb = [math]::Round($file.Length / 1KB, 2)
                last_write_local = $file.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }

            if ($Apply) {
                $archiveRoot = Join-Path $RunRoot ("archive\{0}" -f $symbol)
                New-DirectoryIfMissing -Path $archiveRoot
                Move-Item -LiteralPath $file.FullName -Destination (Join-Path $archiveRoot $file.Name) -Force
                $freedBytes += [int64]$file.Length
                $archived.Add($row) | Out-Null
            }
            else {
                $pending.Add($row) | Out-Null
            }
        }
    }

    return [pscustomobject]@{
        pending = @($pending.ToArray())
        archived = @($archived.ToArray())
        freed_gb = [math]::Round($freedBytes / 1GB, 3)
    }
}

$opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
$reportsRoot = Join-Path $ResearchRoot "reports"
$contractsRoot = Join-Path $ResearchRoot "datasets\contracts"
$smokeRoot = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\qdm_custom_symbol_smoke"
$strategyTesterRunRoot = Join-Path $ProjectRoot "RUN\strategy_tester"
$logsRoot = Join-Path $CommonRoot "logs"
$spoolRoot = Join-Path $CommonRoot "spool"
$jsonPath = Join-Path $opsRoot "learning_artifact_inventory_latest.json"
$mdPath = Join-Path $opsRoot "learning_artifact_inventory_latest.md"

$buildResearchDataContractScript = Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1"
$buildQdmRealismAuditScript = Join-Path $ProjectRoot "RUN\BUILD_QDM_CUSTOM_SYMBOL_REALISM_AUDIT.ps1"
$buildMt5TruthStatusScript = Join-Path $ProjectRoot "RUN\BUILD_MT5_PRETRADE_EXECUTION_TRUTH_STATUS.ps1"

New-DirectoryIfMissing -Path $opsRoot

$repairRuns = @{}
$criticalArtifacts = @(
    @{
        name = "research_export_manifest"
        category = "research_contract"
        path = (Join-Path $reportsRoot "research_export_manifest_latest.json")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildResearchDataContractScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot; ResearchRoot = $ResearchRoot }
    },
    @{
        name = "research_contract_manifest"
        category = "research_contract"
        path = (Join-Path $reportsRoot "research_contract_manifest_latest.json")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildResearchDataContractScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot; ResearchRoot = $ResearchRoot }
    },
    @{
        name = "candidate_signals_contract"
        category = "research_contract"
        path = (Join-Path $contractsRoot "candidate_signals_norm_latest.parquet")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildResearchDataContractScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot; ResearchRoot = $ResearchRoot }
    },
    @{
        name = "onnx_observations_contract"
        category = "research_contract"
        path = (Join-Path $contractsRoot "onnx_observations_norm_latest.parquet")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildResearchDataContractScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot; ResearchRoot = $ResearchRoot }
    },
    @{
        name = "learning_observations_contract"
        category = "research_contract"
        path = (Join-Path $contractsRoot "learning_observations_v2_norm_latest.parquet")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildResearchDataContractScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot; ResearchRoot = $ResearchRoot }
    },
    @{
        name = "qdm_custom_symbol_pilot_registry"
        category = "qdm_learning"
        path = (Join-Path $opsRoot "qdm_custom_symbol_pilot_registry_latest.json")
        threshold_seconds = [Math]::Max($CriticalFreshnessSeconds, 5400)
        repair_script = $null
        repair_parameters = @{}
    },
    @{
        name = "qdm_custom_symbol_smoke_latest"
        category = "qdm_learning"
        path = (Join-Path $opsRoot "qdm_custom_symbol_smoke_latest.json")
        threshold_seconds = [Math]::Max($CriticalFreshnessSeconds, 5400)
        repair_script = $null
        repair_parameters = @{}
    },
    @{
        name = "qdm_custom_symbol_first_wave"
        category = "qdm_learning"
        path = (Join-Path $opsRoot "qdm_custom_symbol_first_wave_latest.json")
        threshold_seconds = [Math]::Max($CriticalFreshnessSeconds, 5400)
        repair_script = $null
        repair_parameters = @{}
    },
    @{
        name = "qdm_custom_symbol_realism_audit"
        category = "qdm_learning"
        path = (Join-Path $opsRoot "qdm_custom_symbol_realism_audit_latest.json")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildQdmRealismAuditScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot }
    },
    @{
        name = "mt5_pretrade_execution_truth_status"
        category = "mt5_truth"
        path = (Join-Path $opsRoot "mt5_pretrade_execution_truth_status_latest.json")
        threshold_seconds = $CriticalFreshnessSeconds
        repair_script = $buildMt5TruthStatusScript
        repair_parameters = @{ ProjectRoot = $ProjectRoot; ResearchRoot = $ResearchRoot }
    }
)

$artifactRows = New-Object System.Collections.Generic.List[object]
foreach ($artifact in $criticalArtifacts) {
    $state = Get-FileState -Name $artifact.name -Path $artifact.path -ThresholdSeconds ([int]$artifact.threshold_seconds) -Category $artifact.category
    $repairSupported = Test-NonEmpty -Value $artifact.repair_script
    $repairAttempted = $false
    $repairResult = $null

    if ($Apply -and $repairSupported -and (-not $state.exists -or -not $state.fresh)) {
        $repairAttempted = $true
        $repairKey = [string]$artifact.repair_script
        if (-not $repairRuns.ContainsKey($repairKey)) {
            $repairRuns[$repairKey] = Invoke-RepairScript -ScriptPath ([string]$artifact.repair_script) -Parameters ([hashtable]$artifact.repair_parameters)
        }

        $repairResult = $repairRuns[$repairKey]
        $state = Get-FileState -Name $artifact.name -Path $artifact.path -ThresholdSeconds ([int]$artifact.threshold_seconds) -Category $artifact.category
    }

    $artifactRows.Add([pscustomobject]@{
        name = $state.name
        category = $state.category
        path = $state.path
        exists = $state.exists
        fresh = $state.fresh
        age_seconds = $state.age_seconds
        threshold_seconds = $state.threshold_seconds
        size_kb = $state.size_kb
        last_write_local = $state.last_write_local
        repair_supported = $repairSupported
        repair_attempted = $repairAttempted
        repair_result = if ($null -ne $repairResult) { $repairResult.message } else { $null }
    }) | Out-Null
}

$universePlan = Read-JsonSafe -Path $UniversePlanPath
$trainingSymbols = Get-TrainingUniverseSymbols -Path $UniversePlanPath -LogsRoot $logsRoot
$firstWaveSymbols = @()
if ($null -ne $universePlan) {
    $firstWaveSymbols = @($universePlan.paper_live_first_wave | ForEach-Object { ([string]$_).Trim().ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}
$liveLogRows = New-Object System.Collections.Generic.List[object]
$liveLogThresholdSeconds = [int]([Math]::Abs($LiveLogFreshnessHours) * 3600)
$learningLogThresholdSeconds = [int]([Math]::Abs($LearningLogFreshnessHours) * 3600)
$learningProgressAlertSeconds = [int]([Math]::Max(1, [Math]::Abs($LearningProgressAlertMinutes)) * 60)

foreach ($symbol in $trainingSymbols) {
    $symbolDir = Join-Path $logsRoot $symbol
    $candidateState = Get-FileState -Name "candidate_signals" -Path (Join-Path $symbolDir "candidate_signals.csv") -ThresholdSeconds $liveLogThresholdSeconds -Category "runtime_log"
    $onnxState = Get-FileState -Name "onnx_observations" -Path (Join-Path $symbolDir "onnx_observations.csv") -ThresholdSeconds $liveLogThresholdSeconds -Category "runtime_log"
    $learningState = Get-FileState -Name "learning_observations_v2" -Path (Join-Path $symbolDir "learning_observations_v2.csv") -ThresholdSeconds $learningLogThresholdSeconds -Category "runtime_log"
    $symbolToken = Convert-ToStorageToken -Value $symbol
    $pretradeState = Get-FileState -Name "pretrade_truth" -Path (Join-Path $spoolRoot ("pretrade_truth\pretrade_truth_{0}.csv" -f $symbolToken)) -ThresholdSeconds $liveLogThresholdSeconds -Category "runtime_log"
    $executionState = Get-FileState -Name "execution_truth" -Path (Join-Path $spoolRoot ("execution_truth\execution_truth_{0}.csv" -f $symbolToken)) -ThresholdSeconds $liveLogThresholdSeconds -Category "runtime_log"
    $observationProgress = Get-LatestProgressState -States @($candidateState, $onnxState) -AlertSeconds $learningProgressAlertSeconds
    $lessonProgress = Get-LatestProgressState -States @($learningState, $pretradeState, $executionState) -AlertSeconds $learningProgressAlertSeconds
    $isFirstWave = $firstWaveSymbols -contains $symbol
    $progressState = if ($lessonProgress.active_within_alert) {
        "AKTYWNE_LEKCJE"
    }
    elseif ($observationProgress.active_within_alert) {
        "AKTYWNA_OBSERWACJA_BEZ_DOMKNIECIA_LEKCJI"
    }
    else {
        "BRAK_POSTEPU_30M"
    }

    $liveLogRows.Add([pscustomobject]@{
        symbol = $symbol
        is_first_wave = $isFirstWave
        candidate_exists = $candidateState.exists
        candidate_fresh = $candidateState.fresh
        candidate_age_seconds = $candidateState.age_seconds
        onnx_exists = $onnxState.exists
        onnx_fresh = $onnxState.fresh
        onnx_age_seconds = $onnxState.age_seconds
        learning_exists = $learningState.exists
        learning_fresh = $learningState.fresh
        learning_age_seconds = $learningState.age_seconds
        pretrade_exists = $pretradeState.exists
        pretrade_fresh = $pretradeState.fresh
        pretrade_age_seconds = $pretradeState.age_seconds
        execution_exists = $executionState.exists
        execution_fresh = $executionState.fresh
        execution_age_seconds = $executionState.age_seconds
        observation_progress_age_seconds = $observationProgress.age_seconds
        observation_progress_last_write_local = $observationProgress.last_write_local
        observation_progress_source = $observationProgress.source
        observation_progress_active_30m = $observationProgress.active_within_alert
        lesson_progress_age_seconds = $lessonProgress.age_seconds
        lesson_progress_last_write_local = $lessonProgress.last_write_local
        lesson_progress_source = $lessonProgress.source
        lesson_progress_active_30m = $lessonProgress.active_within_alert
        learning_progress_state = $progressState
    }) | Out-Null
}

$spoolRows = New-Object System.Collections.Generic.List[object]
foreach ($spoolName in @("candidate_signals", "onnx_observations", "learning_observations_v2", "pretrade_truth", "execution_truth")) {
    $spoolPath = Join-Path $spoolRoot $spoolName
    $files = @()
    if (Test-Path -LiteralPath $spoolPath) {
        $files = @(Get-ChildItem -LiteralPath $spoolPath -File -ErrorAction SilentlyContinue)
    }
    $newest = $files | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $spoolRows.Add([pscustomobject]@{
        name = $spoolName
        path = $spoolPath
        exists = (Test-Path -LiteralPath $spoolPath)
        file_count = $files.Count
        newest_age_seconds = if ($null -ne $newest) { [int][Math]::Round(((Get-Date) - $newest.LastWriteTime).TotalSeconds) } else { $null }
        newest_write_local = if ($null -ne $newest) { $newest.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { $null }
    }) | Out-Null
}

$qdmSmokeRetention = Invoke-QdmSmokeRetention -SmokeRoot $smokeRoot -KeepRunsPerSymbol $QdmSmokeKeepRunsPerSymbol -RetentionDays $QdmSmokeRetentionDays -Apply:$Apply
$strategyTesterRetention = Invoke-StrategyTesterRetention -RunRoot $strategyTesterRunRoot -KeepRunsPerSymbol $StrategyTesterKeepRunsPerSymbol -RetentionDays $StrategyTesterRetentionDays -Apply:$Apply

$storageRoots = @(
    Get-DirectorySnapshot -Name "ops_evidence" -Path $opsRoot
    Get-DirectorySnapshot -Name "research_reports" -Path $reportsRoot
    Get-DirectorySnapshot -Name "research_contracts" -Path $contractsRoot
    Get-DirectorySnapshot -Name "common_logs" -Path $logsRoot
    Get-DirectorySnapshot -Name "common_spool" -Path $spoolRoot
    Get-DirectorySnapshot -Name "qdm_smoke_evidence" -Path $smokeRoot
    Get-DirectorySnapshot -Name "strategy_tester_run_configs" -Path $strategyTesterRunRoot
)

$artifactArray = @($artifactRows.ToArray())
$liveLogArray = @($liveLogRows.ToArray())
$spoolArray = @($spoolRows.ToArray())
$criticalMissingCount = @($artifactArray | Where-Object { -not $_.exists }).Count
$criticalStaleCount = @($artifactArray | Where-Object { $_.exists -and -not $_.fresh }).Count
$repairAttemptedCount = @($artifactArray | Where-Object { $_.repair_attempted }).Count
$repairSucceededCount = @($artifactArray | Where-Object { $_.repair_attempted -and $_.repair_result -eq "ok" }).Count
$liveLogStaleSymbolCount = @($liveLogArray | Where-Object { -not $_.candidate_fresh -or -not $_.onnx_fresh -or -not $_.learning_fresh }).Count
$spoolEmptyCount = @($spoolArray | Where-Object { $_.exists -and $_.file_count -eq 0 }).Count
$retentionPendingCount = @($qdmSmokeRetention.pending).Count + @($strategyTesterRetention.pending).Count
$retentionArchivedCount = @($qdmSmokeRetention.archived).Count + @($strategyTesterRetention.archived).Count
$retentionFreedGb = [math]::Round(([double]$qdmSmokeRetention.freed_gb + [double]$strategyTesterRetention.freed_gb), 3)
$observationActiveCount30m = @($liveLogArray | Where-Object { $_.observation_progress_active_30m }).Count
$lessonActiveCount30m = @($liveLogArray | Where-Object { $_.lesson_progress_active_30m }).Count
$observationStaleCount30m = @($liveLogArray | Where-Object { -not $_.observation_progress_active_30m }).Count
$lessonStaleCount30m = @($liveLogArray | Where-Object { -not $_.lesson_progress_active_30m }).Count
$firstWaveObservationActiveCount30m = @($liveLogArray | Where-Object { $_.is_first_wave -and $_.observation_progress_active_30m }).Count
$firstWaveLessonActiveCount30m = @($liveLogArray | Where-Object { $_.is_first_wave -and $_.lesson_progress_active_30m }).Count
$firstWaveObservationStaleCount30m = @($liveLogArray | Where-Object { $_.is_first_wave -and -not $_.observation_progress_active_30m }).Count
$firstWaveLessonStaleCount30m = @($liveLogArray | Where-Object { $_.is_first_wave -and -not $_.lesson_progress_active_30m }).Count
$fleetProgressAlert30m = ($trainingSymbols.Count -gt 0 -and $observationActiveCount30m -eq 0)
$fleetLessonAlert30m = ($trainingSymbols.Count -gt 0 -and $lessonActiveCount30m -eq 0)
$firstWaveProgressAlert30m = ($firstWaveSymbols.Count -gt 0 -and $firstWaveObservationActiveCount30m -eq 0)
$firstWaveLessonAlert30m = ($firstWaveSymbols.Count -gt 0 -and $firstWaveLessonActiveCount30m -eq 0)
$learningProgressVerdict = if ($fleetProgressAlert30m) {
    "BRAK_POSTEPU_NAUKI_30M"
}
elseif ($firstWaveLessonAlert30m) {
    "BRAK_DOMYKANIA_LEKCJI_PIERWSZEJ_FALI_30M"
}
elseif ($firstWaveProgressAlert30m) {
    "PIERWSZA_FALA_BEZ_POSTEPU_30M"
}
elseif ($lessonActiveCount30m -gt 0) {
    "LEKCJE_AKTYWNE"
}
elseif ($observationActiveCount30m -gt 0) {
    "OBSERWACJA_AKTYWNA_BEZ_DOMKNIECIA_LEKCJI"
}
else {
    "BRAK_POSTEPU_NAUKI_30M"
}

$verdict = if ($criticalMissingCount -eq 0 -and $criticalStaleCount -eq 0) {
    if ($retentionArchivedCount -gt 0) {
        "LEARNING_ARTIFACTS_HEALED_AND_TRIMMED"
    }
    elseif ($retentionPendingCount -gt 0) {
        "LEARNING_ARTIFACTS_HEALTHY_WITH_RETENTION_BACKLOG"
    }
    else {
        "LEARNING_ARTIFACTS_HEALTHY"
    }
}
else {
    "LEARNING_ARTIFACT_GAPS"
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $ProjectRoot
    research_root = $ResearchRoot
    common_root = $CommonRoot
    apply_mode = [bool]$Apply
    storage_roots = $storageRoots
    critical_artifacts = $artifactArray
    live_logs = [ordered]@{
        candidate_threshold_hours = $LiveLogFreshnessHours
        learning_threshold_hours = $LearningLogFreshnessHours
        progress_alert_minutes = $LearningProgressAlertMinutes
        symbols = $liveLogArray
    }
    learning_progress = [ordered]@{
        alert_minutes = $LearningProgressAlertMinutes
        verdict = $learningProgressVerdict
        fleet_progress_alert_30m = $fleetProgressAlert30m
        fleet_lesson_alert_30m = $fleetLessonAlert30m
        first_wave_progress_alert_30m = $firstWaveProgressAlert30m
        first_wave_lesson_alert_30m = $firstWaveLessonAlert30m
        observation_active_count_30m = $observationActiveCount30m
        observation_stale_count_30m = $observationStaleCount30m
        lesson_active_count_30m = $lessonActiveCount30m
        lesson_stale_count_30m = $lessonStaleCount30m
        first_wave_observation_active_count_30m = $firstWaveObservationActiveCount30m
        first_wave_observation_stale_count_30m = $firstWaveObservationStaleCount30m
        first_wave_lesson_active_count_30m = $firstWaveLessonActiveCount30m
        first_wave_lesson_stale_count_30m = $firstWaveLessonStaleCount30m
    }
    spool = $spoolArray
    retention = [ordered]@{
        qdm_custom_symbol_smoke = [ordered]@{
            pending_count = @($qdmSmokeRetention.pending).Count
            archived_count = @($qdmSmokeRetention.archived).Count
            freed_gb = [double]$qdmSmokeRetention.freed_gb
            pending_head = @($qdmSmokeRetention.pending | Select-Object -First 50)
            archived_head = @($qdmSmokeRetention.archived | Select-Object -First 50)
        }
        strategy_tester_run_configs = [ordered]@{
            pending_count = @($strategyTesterRetention.pending).Count
            archived_count = @($strategyTesterRetention.archived).Count
            freed_gb = [double]$strategyTesterRetention.freed_gb
            pending_head = @($strategyTesterRetention.pending | Select-Object -First 50)
            archived_head = @($strategyTesterRetention.archived | Select-Object -First 50)
        }
    }
    summary = [ordered]@{
        critical_artifact_count = $artifactArray.Count
        critical_missing_count = $criticalMissingCount
        critical_stale_count = $criticalStaleCount
        repair_attempted_count = $repairAttemptedCount
        repair_succeeded_count = $repairSucceededCount
        live_log_stale_symbol_count = $liveLogStaleSymbolCount
        spool_empty_count = $spoolEmptyCount
        learning_progress_alert_minutes = $LearningProgressAlertMinutes
        learning_progress_verdict = $learningProgressVerdict
        learning_progress_fleet_alert_30m = $fleetProgressAlert30m
        learning_progress_fleet_lesson_alert_30m = $fleetLessonAlert30m
        learning_progress_first_wave_alert_30m = $firstWaveProgressAlert30m
        learning_progress_first_wave_lesson_alert_30m = $firstWaveLessonAlert30m
        learning_progress_observation_active_count_30m = $observationActiveCount30m
        learning_progress_lesson_active_count_30m = $lessonActiveCount30m
        learning_progress_first_wave_observation_active_count_30m = $firstWaveObservationActiveCount30m
        learning_progress_first_wave_lesson_active_count_30m = $firstWaveLessonActiveCount30m
        retention_pending_count = $retentionPendingCount
        retention_archived_count = $retentionArchivedCount
        retention_freed_gb = $retentionFreedGb
    }
    verdict = $verdict
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Learning Artifact Inventory")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- apply_mode: {0}" -f ([string]$report.apply_mode).ToLowerInvariant()))
$lines.Add("")
$lines.Add("## Summary")
$lines.Add("")
$lines.Add(("- critical_missing_count: {0}" -f $report.summary.critical_missing_count))
$lines.Add(("- critical_stale_count: {0}" -f $report.summary.critical_stale_count))
$lines.Add(("- repair_attempted_count: {0}" -f $report.summary.repair_attempted_count))
$lines.Add(("- repair_succeeded_count: {0}" -f $report.summary.repair_succeeded_count))
$lines.Add(("- live_log_stale_symbol_count: {0}" -f $report.summary.live_log_stale_symbol_count))
$lines.Add(("- spool_empty_count: {0}" -f $report.summary.spool_empty_count))
$lines.Add(("- learning_progress_alert_minutes: {0}" -f $report.summary.learning_progress_alert_minutes))
$lines.Add(("- learning_progress_verdict: {0}" -f $report.summary.learning_progress_verdict))
$lines.Add(("- learning_progress_fleet_alert_30m: {0}" -f ([string]$report.summary.learning_progress_fleet_alert_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_first_wave_alert_30m: {0}" -f ([string]$report.summary.learning_progress_first_wave_alert_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_first_wave_lesson_alert_30m: {0}" -f ([string]$report.summary.learning_progress_first_wave_lesson_alert_30m).ToLowerInvariant()))
$lines.Add(("- learning_progress_observation_active_count_30m: {0}" -f $report.summary.learning_progress_observation_active_count_30m))
$lines.Add(("- learning_progress_lesson_active_count_30m: {0}" -f $report.summary.learning_progress_lesson_active_count_30m))
$lines.Add(("- learning_progress_first_wave_observation_active_count_30m: {0}" -f $report.summary.learning_progress_first_wave_observation_active_count_30m))
$lines.Add(("- learning_progress_first_wave_lesson_active_count_30m: {0}" -f $report.summary.learning_progress_first_wave_lesson_active_count_30m))
$lines.Add(("- retention_pending_count: {0}" -f $report.summary.retention_pending_count))
$lines.Add(("- retention_archived_count: {0}" -f $report.summary.retention_archived_count))
$lines.Add(("- retention_freed_gb: {0}" -f $report.summary.retention_freed_gb))
$lines.Add("")
$lines.Add("## Critical Artifacts")
$lines.Add("")
foreach ($item in $artifactArray) {
    $lines.Add(("- {0}: exists={1}, fresh={2}, age_seconds={3}, repair={4}" -f $item.name, $item.exists, $item.fresh, $item.age_seconds, $(if ($item.repair_attempted) { $item.repair_result } else { "none" })))
}
$lines.Add("")
$lines.Add("## Live Logs")
$lines.Add("")
foreach ($item in $liveLogArray) {
    $lines.Add(("- {0}: candidate={1}/{2}, onnx={3}/{4}, learning={5}/{6}, pretrade={7}/{8}, execution={9}/{10}, postep={11}, obserwacja_30m={12}, lekcje_30m={13}" -f
        $item.symbol,
        $item.candidate_exists,
        $item.candidate_fresh,
        $item.onnx_exists,
        $item.onnx_fresh,
        $item.learning_exists,
        $item.learning_fresh,
        $item.pretrade_exists,
        $item.pretrade_fresh,
        $item.execution_exists,
        $item.execution_fresh,
        $item.learning_progress_state,
        $item.observation_progress_active_30m,
        $item.lesson_progress_active_30m))
}
$lines.Add("")
$lines.Add("## Spool")
$lines.Add("")
foreach ($item in $spoolArray) {
    $lines.Add(("- {0}: exists={1}, file_count={2}, newest_age_seconds={3}" -f $item.name, $item.exists, $item.file_count, $item.newest_age_seconds))
}
$lines.Add("")
$lines.Add("## Storage Roots")
$lines.Add("")
foreach ($item in $storageRoots) {
    $lines.Add(("- {0}: exists={1}, file_count={2}, total_size_gb={3}, newest_write_local={4}" -f $item.name, $item.exists, $item.file_count, $item.total_size_gb, $item.newest_write_local))
}
$lines.Add("")

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 8
