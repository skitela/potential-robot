param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ContractPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\post_migration_startup_audit_v1.json",
    [int]$WaitBeforeAuditSec = -1,
    [int]$ContinuitySamples = -1,
    [int]$ContinuityIntervalSec = -1,
    [switch]$ApplySafeRepair,
    [switch]$SkipWait
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Get-OptionalValue {
    param(
        [object]$Object,
        [string]$Name,
        $Default = $null
    )

    if ($null -eq $Object) {
        return $Default
    }

    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $Default
    }

    return $property.Value
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

function Get-ConfigSeconds {
    param(
        [object]$Thresholds,
        [string]$Name,
        [int]$Default
    )

    return [int](Get-OptionalNumber -Object $Thresholds -Name $Name -Default $Default)
}

function New-FileProbe {
    param(
        [string]$Label,
        [string]$Path,
        [int]$ThresholdSeconds
    )

    $probe = [ordered]@{
        label = $Label
        path = $Path
        exists = $false
        fresh = $false
        last_write_local = $null
        age_seconds = $null
        threshold_seconds = $ThresholdSeconds
        last_write_ticks = $null
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$probe
    }

    $item = Get-Item -LiteralPath $Path
    $ageSeconds = [int][Math]::Round(((Get-Date) - $item.LastWriteTime).TotalSeconds)

    $probe.exists = $true
    $probe.fresh = ($ageSeconds -le $ThresholdSeconds)
    $probe.last_write_local = $item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $probe.age_seconds = $ageSeconds
    $probe.last_write_ticks = [int64]$item.LastWriteTimeUtc.Ticks
    return [pscustomobject]$probe
}

function Invoke-ScriptStep {
    param(
        [string]$ScriptPath,
        [hashtable]$Parameters = @{},
        [string]$Label
    )

    $result = [ordered]@{
        label = $Label
        script = $ScriptPath
        ok = $false
        message = ""
    }

    if (-not (Test-Path -LiteralPath $ScriptPath)) {
        $result.message = "missing"
        return [pscustomobject]$result
    }

    try {
        & $ScriptPath @Parameters | Out-Null
        $result.ok = $true
        $result.message = "ok"
    }
    catch {
        $result.message = $_.Exception.Message
    }

    return [pscustomobject]$result
}

function Get-SymbolStateSnapshot {
    param(
        [string]$CommonRoot,
        [string]$SymbolAlias,
        [hashtable]$Thresholds
    )

    $stateDir = Join-Path $CommonRoot ("state\{0}" -f $SymbolAlias)
    $logsDir = Join-Path $CommonRoot ("logs\{0}" -f $SymbolAlias)

    return [pscustomobject]@{
        symbol_alias = $SymbolAlias
        runtime_status = New-FileProbe -Label "runtime_status" -Path (Join-Path $stateDir "runtime_status.json") -ThresholdSeconds $Thresholds.runtime_status_sec
        execution_summary = New-FileProbe -Label "execution_summary" -Path (Join-Path $stateDir "execution_summary.json") -ThresholdSeconds $Thresholds.execution_summary_sec
        decision_log = New-FileProbe -Label "decision_log" -Path (Join-Path $logsDir "decision_events.csv") -ThresholdSeconds $Thresholds.decision_log_sec
        onnx_log = New-FileProbe -Label "onnx_log" -Path (Join-Path $logsDir "onnx_observations.csv") -ThresholdSeconds $Thresholds.onnx_log_sec
    }
}

function Collect-SymbolSamples {
    param(
        [string]$CommonRoot,
        [string[]]$TargetSymbols,
        [hashtable]$Thresholds,
        [int]$Samples,
        [int]$IntervalSeconds
    )

    $allSamples = New-Object System.Collections.Generic.List[object]
    $sampleCount = [Math]::Max(2, $Samples)
    $sleepSeconds = [Math]::Max(1, $IntervalSeconds)

    for ($sampleIndex = 1; $sampleIndex -le $sampleCount; $sampleIndex++) {
        $sampleRows = foreach ($symbol in $TargetSymbols) {
            Get-SymbolStateSnapshot -CommonRoot $CommonRoot -SymbolAlias $symbol -Thresholds $Thresholds
        }

        $allSamples.Add([pscustomobject]@{
            sample_index = $sampleIndex
            collected_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            rows = @($sampleRows)
        }) | Out-Null

        if ($sampleIndex -lt $sampleCount) {
            Start-Sleep -Seconds $sleepSeconds
        }
    }

    return @($allSamples.ToArray())
}

function Get-ContinuityState {
    param(
        [object[]]$Samples,
        [string]$SymbolAlias
    )

    $symbolRows = foreach ($sample in @($Samples)) {
        @($sample.rows | Where-Object { $_.symbol_alias -eq $SymbolAlias })
    }

    if (@($symbolRows).Count -eq 0) {
        return [pscustomobject]@{
            state = "BRAK_PROBEK"
            runtime_status_changed = $false
            execution_summary_changed = $false
        }
    }

    $runtimeTicks = @($symbolRows | ForEach-Object { $_.runtime_status.last_write_ticks } | Where-Object { $null -ne $_ } | Select-Object -Unique)
    $executionTicks = @($symbolRows | ForEach-Object { $_.execution_summary.last_write_ticks } | Where-Object { $null -ne $_ } | Select-Object -Unique)
    $runtimeChanged = ($runtimeTicks.Count -gt 1)
    $executionChanged = ($executionTicks.Count -gt 1)
    $finalRow = $symbolRows[-1]
    $runtimeFresh = [bool]$finalRow.runtime_status.fresh
    $executionFresh = [bool]$finalRow.execution_summary.fresh

    $state = if ($runtimeChanged -or $executionChanged) {
        "PRZEPLYW_POTWIERDZONY"
    }
    elseif ($runtimeFresh -and $executionFresh) {
        "PRZEPLYW_SWIEZY_BEZ_ZMIANY_W_OKNIE"
    }
    else {
        "BRAK_SWIEZEGO_PRZEPLYWU"
    }

    return [pscustomobject]@{
        state = $state
        runtime_status_changed = $runtimeChanged
        execution_summary_changed = $executionChanged
    }
}

function Invoke-RefreshSuite {
    param(
        [string]$ProjectRoot,
        [bool]$AllowRepair
    )

    $steps = New-Object System.Collections.Generic.List[object]

    $steps.Add((Invoke-ScriptStep -Label "hosting_report" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_HOSTING_DAILY_REPORT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
    $steps.Add((Invoke-ScriptStep -Label "paper_live_feedback" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null

    $watchdogParams = @{ ProjectRoot = $ProjectRoot }
    if (-not $AllowRepair) {
        $watchdogParams["NoRepair"] = $true
    }
    $steps.Add((Invoke-ScriptStep -Label "runtime_watchdog" -ScriptPath (Join-Path $ProjectRoot "TOOLS\RUN_RUNTIME_WATCHDOG_PL.ps1") -Parameters $watchdogParams)) | Out-Null

    $steps.Add((Invoke-ScriptStep -Label "vps_spool_wellbeing" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_VPS_SPOOL_WELLBEING_AUDIT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot; Apply = $AllowRepair })) | Out-Null
    $steps.Add((Invoke-ScriptStep -Label "truth_status" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_PRETRADE_EXECUTION_TRUTH_STATUS.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
    $steps.Add((Invoke-ScriptStep -Label "first_wave_runtime_activity" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
    $steps.Add((Invoke-ScriptStep -Label "first_wave_server_parity" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_SERVER_PARITY_AUDIT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null

    if ($AllowRepair) {
        $steps.Add((Invoke-ScriptStep -Label "vps_spool_sync" -ScriptPath (Join-Path $ProjectRoot "RUN\SYNC_VPS_SPOOL_BACKLOG.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
        $steps.Add((Invoke-ScriptStep -Label "research_data_contract" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_RESEARCH_DATA_CONTRACT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
        $steps.Add((Invoke-ScriptStep -Label "audit_supervisor_safe" -ScriptPath (Join-Path $ProjectRoot "RUN\RUN_AUDIT_SUPERVISOR.ps1") -Parameters @{ ProjectRoot = $ProjectRoot; Mode = "Once"; ApplySafeAutoHeal = $true })) | Out-Null
        $steps.Add((Invoke-ScriptStep -Label "hosting_report_after_repair" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_HOSTING_DAILY_REPORT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
        $steps.Add((Invoke-ScriptStep -Label "paper_live_feedback_after_repair" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_CANONICAL_PAPER_LIVE_FEEDBACK.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
        $steps.Add((Invoke-ScriptStep -Label "truth_status_after_repair" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_PRETRADE_EXECUTION_TRUTH_STATUS.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
        $steps.Add((Invoke-ScriptStep -Label "first_wave_runtime_activity_after_repair" -ScriptPath (Join-Path $ProjectRoot "RUN\BUILD_MT5_FIRST_WAVE_RUNTIME_ACTIVITY_AUDIT.ps1") -Parameters @{ ProjectRoot = $ProjectRoot })) | Out-Null
    }

    return @($steps.ToArray())
}

function Evaluate-StartupState {
    param(
        [string]$ProjectRoot,
        [string[]]$TargetSymbols,
        [hashtable]$Thresholds,
        [object[]]$Samples,
        [object[]]$RefreshSteps
    )

    $opsRoot = Join-Path $ProjectRoot "EVIDENCE\OPS"
    $researchManifestPath = "C:\TRADING_DATA\RESEARCH\reports\research_export_manifest_latest.json"

    $hostingReportPath = Join-Path $opsRoot "mt5_hosting_daily_report_latest.json"
    $paperLiveFeedbackPath = Join-Path $opsRoot "paper_live_feedback_latest.json"
    $vpsSpoolWellbeingPath = Join-Path $opsRoot "vps_spool_wellbeing_latest.json"
    $truthStatusPath = Join-Path $opsRoot "mt5_pretrade_execution_truth_status_latest.json"
    $firstWaveRuntimeActivityPath = Join-Path $opsRoot "mt5_first_wave_runtime_activity_latest.json"
    $runtimeWatchdogPath = Join-Path $ProjectRoot "EVIDENCE\runtime_watchdog_status.json"

    $hostingReport = Read-JsonSafe -Path $hostingReportPath
    $paperLiveFeedback = Read-JsonSafe -Path $paperLiveFeedbackPath
    $vpsSpoolWellbeing = Read-JsonSafe -Path $vpsSpoolWellbeingPath
    $truthStatus = Read-JsonSafe -Path $truthStatusPath
    $firstWaveRuntimeActivity = Read-JsonSafe -Path $firstWaveRuntimeActivityPath
    $runtimeWatchdog = Read-JsonSafe -Path $runtimeWatchdogPath
    $researchManifest = Read-JsonSafe -Path $researchManifestPath

    $freshness = [ordered]@{
        hosting_report = New-FileProbe -Label "hosting_report" -Path $hostingReportPath -ThresholdSeconds $Thresholds.hosting_report_sec
        paper_live_feedback = New-FileProbe -Label "paper_live_feedback" -Path $paperLiveFeedbackPath -ThresholdSeconds $Thresholds.paper_live_feedback_sec
        runtime_watchdog = New-FileProbe -Label "runtime_watchdog" -Path $runtimeWatchdogPath -ThresholdSeconds $Thresholds.runtime_watchdog_sec
        vps_spool_wellbeing = New-FileProbe -Label "vps_spool_wellbeing" -Path $vpsSpoolWellbeingPath -ThresholdSeconds $Thresholds.vps_spool_wellbeing_sec
        truth_status = New-FileProbe -Label "truth_status" -Path $truthStatusPath -ThresholdSeconds $Thresholds.truth_status_sec
        first_wave_runtime_activity = New-FileProbe -Label "first_wave_runtime_activity" -Path $firstWaveRuntimeActivityPath -ThresholdSeconds $Thresholds.runtime_activity_sec
        research_manifest = New-FileProbe -Label "research_manifest" -Path $researchManifestPath -ThresholdSeconds $Thresholds.research_manifest_sec
    }

    $findings = New-Object System.Collections.Generic.List[object]

    $rosterCount = [int](Get-OptionalNumber -Object $hostingReport -Name "roster_count" -Default 0)
    $hostingInstruments = @()
    foreach ($row in @($hostingReport.instrument_rows)) {
        $instrument = [string](Get-OptionalValue -Object $row -Name "Instrument" -Default "")
        if (-not [string]::IsNullOrWhiteSpace($instrument)) {
            $hostingInstruments += $instrument.ToUpperInvariant()
        }
    }

    $watchdogStaleSymbols = @()
    $watchdogMissingSymbols = @()
    foreach ($symbol in @($runtimeWatchdog.stale_symbols)) {
        $watchdogStaleSymbols += ([string]$symbol).ToUpperInvariant()
    }
    foreach ($symbol in @($runtimeWatchdog.missing_symbols)) {
        $watchdogMissingSymbols += ([string]$symbol).ToUpperInvariant()
    }

    $targetMissingInHosting = @($TargetSymbols | Where-Object { $_ -notin $hostingInstruments })
    $targetStaleInWatchdog = @($TargetSymbols | Where-Object { $_ -in $watchdogStaleSymbols })
    $targetMissingInWatchdog = @($TargetSymbols | Where-Object { $_ -in $watchdogMissingSymbols })

    if (-not [bool](Get-OptionalValue -Object $runtimeWatchdog -Name "terminal_running" -Default $false)) {
        $findings.Add([pscustomobject]@{
            severity = "critical"
            component = "terminal_runtime"
            message = "Terminal MT5 nie jest widoczny jako uruchomiony po migracji."
        }) | Out-Null
    }

    if (-not $freshness.runtime_watchdog.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "high"
            component = "runtime_watchdog"
            message = "Watcher runtime nie jest swiezy po migracji."
            context = @{ age_seconds = $freshness.runtime_watchdog.age_seconds }
        }) | Out-Null
    }

    if (-not $freshness.hosting_report.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "high"
            component = "hosting_report"
            message = "Raport hostingu MT5 nie jest swiezy po migracji."
            context = @{ age_seconds = $freshness.hosting_report.age_seconds }
        }) | Out-Null
    }

    if ($rosterCount -lt $TargetSymbols.Count) {
        $findings.Add([pscustomobject]@{
            severity = "high"
            component = "hosting_roster"
            message = "Hosting nie pokazuje pelnej obsady aktywnej czworki."
            context = @{
                roster_count = $rosterCount
                expected_count = $TargetSymbols.Count
            }
        }) | Out-Null
    }

    if ($targetMissingInHosting.Count -gt 0) {
        $findings.Add([pscustomobject]@{
            severity = "high"
            component = "hosting_roster"
            message = "W hostingu brakuje czesci aktywnych instrumentow."
            context = @{ missing_symbols = @($targetMissingInHosting) }
        }) | Out-Null
    }

    if ($targetMissingInWatchdog.Count -gt 0) {
        $findings.Add([pscustomobject]@{
            severity = "critical"
            component = "runtime_watchdog"
            message = "Runtime watchdog widzi brakujace stany dla aktywnej czworki."
            context = @{ missing_symbols = @($targetMissingInWatchdog) }
        }) | Out-Null
    }

    if ($targetStaleInWatchdog.Count -gt 0) {
        $findings.Add([pscustomobject]@{
            severity = "high"
            component = "runtime_watchdog"
            message = "Runtime watchdog widzi przeterminowane heartbeat-y aktywnej czworki."
            context = @{ stale_symbols = @($targetStaleInWatchdog) }
        }) | Out-Null
    }

    if (-not $freshness.vps_spool_wellbeing.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "vps_spool_wellbeing"
            message = "Dobrostan spoola VPS nie jest swiezy."
            context = @{ age_seconds = $freshness.vps_spool_wellbeing.age_seconds }
        }) | Out-Null
    }

    if (-not $freshness.paper_live_feedback.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "paper_live_feedback"
            message = "Raport sprzezenia paper-live nie jest swiezy po migracji."
            context = @{ age_seconds = $freshness.paper_live_feedback.age_seconds }
        }) | Out-Null
    }

    if (-not $freshness.truth_status.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "truth_status"
            message = "Status prawdy wykonania nie jest swiezy po migracji."
            context = @{ age_seconds = $freshness.truth_status.age_seconds }
        }) | Out-Null
    }

    if (-not $freshness.first_wave_runtime_activity.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "first_wave_runtime_activity"
            message = "Audyt aktywnosci pierwszej czworki nie jest swiezy po migracji."
            context = @{ age_seconds = $freshness.first_wave_runtime_activity.age_seconds }
        }) | Out-Null
    }

    if (-not $freshness.research_manifest.fresh) {
        $findings.Add([pscustomobject]@{
            severity = "medium"
            component = "research_manifest"
            message = "Manifest eksportu research nie jest swiezy po migracji."
            context = @{ age_seconds = $freshness.research_manifest.age_seconds }
        }) | Out-Null
    }

    $pendingSyncCount = [int](Get-OptionalNumber -Object (Get-OptionalValue -Object $vpsSpoolWellbeing -Name "summary" -Default $null) -Name "pending_sync_count" -Default 0)
    $pendingSyncOldestAge = [int](Get-OptionalNumber -Object (Get-OptionalValue -Object $vpsSpoolWellbeing -Name "summary" -Default $null) -Name "pending_sync_oldest_age_seconds" -Default 0)
    if ($pendingSyncCount -gt 0 -and $pendingSyncOldestAge -gt 120) {
        $findings.Add([pscustomobject]@{
            severity = "high"
            component = "vps_spool_wellbeing"
            message = "Po migracji nadal wisza zalegle paczki danych VPS."
            context = @{
                pending_sync_count = $pendingSyncCount
                pending_sync_oldest_age_seconds = $pendingSyncOldestAge
            }
        }) | Out-Null
    }

    $symbolResults = New-Object System.Collections.Generic.List[object]
    $continuityConfirmedCount = 0
    $continuityFreshCount = 0

    foreach ($symbol in $TargetSymbols) {
        $finalSample = @($Samples[-1].rows | Where-Object { $_.symbol_alias -eq $symbol })[0]
        $continuity = Get-ContinuityState -Samples $Samples -SymbolAlias $symbol
        $continuityState = [string]$continuity.state
        if ($continuityState -eq "PRZEPLYW_POTWIERDZONY") {
            $continuityConfirmedCount++
        }
        if ($continuityState -in @("PRZEPLYW_POTWIERDZONY", "PRZEPLYW_SWIEZY_BEZ_ZMIANY_W_OKNIE")) {
            $continuityFreshCount++
        }

        if (-not [bool]$finalSample.runtime_status.fresh) {
            $findings.Add([pscustomobject]@{
                severity = "high"
                component = "symbol_runtime_status"
                message = "Runtime status symbolu nie jest swiezy po migracji."
                context = @{
                    symbol_alias = $symbol
                    age_seconds = $finalSample.runtime_status.age_seconds
                }
            }) | Out-Null
        }

        if (-not [bool]$finalSample.execution_summary.fresh) {
            $findings.Add([pscustomobject]@{
                severity = "high"
                component = "symbol_execution_summary"
                message = "Podsumowanie wykonania symbolu nie jest swieze po migracji."
                context = @{
                    symbol_alias = $symbol
                    age_seconds = $finalSample.execution_summary.age_seconds
                }
            }) | Out-Null
        }

        if (-not [bool]$finalSample.decision_log.fresh) {
            $findings.Add([pscustomobject]@{
                severity = "medium"
                component = "symbol_decision_log"
                message = "Dziennik decyzji symbolu nie jest swiezy po migracji."
                context = @{
                    symbol_alias = $symbol
                    age_seconds = $finalSample.decision_log.age_seconds
                }
            }) | Out-Null
        }

        if (-not [bool]$finalSample.onnx_log.fresh) {
            $findings.Add([pscustomobject]@{
                severity = "medium"
                component = "symbol_onnx_log"
                message = "Dziennik obserwacji modelu nie jest swiezy po migracji."
                context = @{
                    symbol_alias = $symbol
                    age_seconds = $finalSample.onnx_log.age_seconds
                }
            }) | Out-Null
        }

        if ($continuityState -eq "BRAK_SWIEZEGO_PRZEPLYWU") {
            $findings.Add([pscustomobject]@{
                severity = "high"
                component = "symbol_continuity"
                message = "W krotkim oknie po migracji nie potwierdzono swiezego przeplywu stanu symbolu."
                context = @{ symbol_alias = $symbol }
            }) | Out-Null
        }

        $symbolResults.Add([pscustomobject]@{
            symbol_alias = $symbol
            runtime_status = $finalSample.runtime_status
            execution_summary = $finalSample.execution_summary
            decision_log = $finalSample.decision_log
            onnx_log = $finalSample.onnx_log
            continuity = $continuity
        }) | Out-Null
    }

    $truthSummary = Get-OptionalValue -Object $truthStatus -Name "truth_summary" -Default $null
    $activitySummary = Get-OptionalValue -Object $firstWaveRuntimeActivity -Name "summary" -Default $null
    $freshPaperOpenCount = [int](Get-OptionalNumber -Object $activitySummary -Name "fresh_paper_open_count" -Default 0)
    $truthLiveSymbolCount = [int](Get-OptionalNumber -Object $activitySummary -Name "truth_live_symbol_count" -Default 0)
    $pretradeRows = [int](Get-OptionalNumber -Object $truthSummary -Name "pretrade_rows" -Default 0)
    $executionRows = [int](Get-OptionalNumber -Object $truthSummary -Name "execution_rows" -Default 0)
    $truthChainRows = [int](Get-OptionalNumber -Object $truthSummary -Name "truth_chain_rows" -Default 0)

    $truthFlowState = "BRAK_SWIEZEJ_PROBY"
    if ($freshPaperOpenCount -gt 0) {
        if ($truthLiveSymbolCount -gt 0 -or ($pretradeRows -gt 0 -and $executionRows -gt 0 -and $truthChainRows -gt 0)) {
            $truthFlowState = "ZYWA_PRAWDA_POTWIERDZONA"
        }
        else {
            $truthFlowState = "PROBY_BYLY_ALE_BRAK_PRAWDY"
            $findings.Add([pscustomobject]@{
                severity = "critical"
                component = "truth_flow"
                message = "Po swiezych probach papierowych nie pojawil sie zywy zapis prawdy przed zleceniem i po wykonaniu."
                context = @{
                    fresh_paper_open_count = $freshPaperOpenCount
                    truth_live_symbol_count = $truthLiveSymbolCount
                    pretrade_rows = $pretradeRows
                    execution_rows = $executionRows
                    truth_chain_rows = $truthChainRows
                }
            }) | Out-Null
        }
    }

    $criticalCount = @($findings | Where-Object { $_.severity -eq "critical" }).Count
    $highCount = @($findings | Where-Object { $_.severity -eq "high" }).Count

    $verdict = if ($criticalCount -gt 0) {
        "ROZRUCH_PO_MIGRACJI_NIEUDANY"
    }
    elseif ($highCount -gt 0) {
        "ROZRUCH_PO_MIGRACJI_WYMAGA_NAPRAWY"
    }
    elseif ($truthFlowState -eq "BRAK_SWIEZEJ_PROBY") {
        "ROZRUCH_PO_MIGRACJI_STABILNY_BEZ_SWIEZEJ_PROBY"
    }
    else {
        "ROZRUCH_PO_MIGRACJI_STABILNY"
    }

    $ok = $verdict -in @("ROZRUCH_PO_MIGRACJI_STABILNY", "ROZRUCH_PO_MIGRACJI_STABILNY_BEZ_SWIEZEJ_PROBY")

    return [pscustomobject]@{
        ok = $ok
        verdict = $verdict
        freshness = [pscustomobject]$freshness
        summary = [pscustomobject]@{
            target_symbol_count = $TargetSymbols.Count
            continuity_confirmed_count = $continuityConfirmedCount
            continuity_fresh_count = $continuityFreshCount
            hosting_roster_count = $rosterCount
            watchdog_terminal_running = [bool](Get-OptionalValue -Object $runtimeWatchdog -Name "terminal_running" -Default $false)
            watchdog_missing_target_count = $targetMissingInWatchdog.Count
            watchdog_stale_target_count = $targetStaleInWatchdog.Count
            fresh_paper_open_count = $freshPaperOpenCount
            truth_live_symbol_count = $truthLiveSymbolCount
            pretrade_rows = $pretradeRows
            execution_rows = $executionRows
            truth_chain_rows = $truthChainRows
            truth_flow_state = $truthFlowState
            pending_vps_sync_count = $pendingSyncCount
            pending_vps_sync_oldest_age_seconds = $pendingSyncOldestAge
        }
        target_symbols = @($TargetSymbols)
        symbol_results = @($symbolResults.ToArray())
        findings = @($findings.ToArray())
        refresh_steps = @($RefreshSteps)
    }
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
$contract = Read-JsonSafe -Path $ContractPath
if ($null -eq $contract) {
    throw "Brak kontraktu audytu rozruchu po migracji: $ContractPath"
}

$waitSeconds = if ($WaitBeforeAuditSec -ge 0) { $WaitBeforeAuditSec } else { [int](Get-OptionalNumber -Object $contract -Name "wait_before_audit_sec" -Default 180) }
$sampleCount = if ($ContinuitySamples -ge 0) { $ContinuitySamples } else { [int](Get-OptionalNumber -Object $contract -Name "continuity_samples" -Default 3) }
$sampleInterval = if ($ContinuityIntervalSec -ge 0) { $ContinuityIntervalSec } else { [int](Get-OptionalNumber -Object $contract -Name "continuity_interval_sec" -Default 20) }
$thresholdConfig = Get-OptionalValue -Object $contract -Name "freshness_thresholds" -Default $null
$targetSymbols = @((Get-OptionalValue -Object $contract -Name "target_symbols" -Default @()) | ForEach-Object { ([string]$_).ToUpperInvariant() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($targetSymbols.Count -eq 0) {
    throw "Kontrakt audytu po migracji nie definiuje symboli docelowych."
}

$thresholds = @{
    hosting_report_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "hosting_report_sec" -Default 1800
    paper_live_feedback_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "paper_live_feedback_sec" -Default 1800
    runtime_watchdog_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "runtime_watchdog_sec" -Default 900
    vps_spool_wellbeing_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "vps_spool_wellbeing_sec" -Default 1800
    truth_status_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "truth_status_sec" -Default 1800
    runtime_activity_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "runtime_activity_sec" -Default 1800
    research_manifest_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "research_manifest_sec" -Default 1800
    runtime_status_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "runtime_status_sec" -Default 240
    execution_summary_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "execution_summary_sec" -Default 240
    decision_log_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "decision_log_sec" -Default 1800
    onnx_log_sec = Get-ConfigSeconds -Thresholds $thresholdConfig -Name "onnx_log_sec" -Default 1800
}

$opsRoot = Join-Path $projectRootResolved "EVIDENCE\OPS"
$jsonPath = Join-Path $opsRoot "post_migration_startup_audit_latest.json"
$mdPath = Join-Path $opsRoot "post_migration_startup_audit_latest.md"
New-Item -ItemType Directory -Force -Path $opsRoot | Out-Null

$waitApplied = 0
if (-not $SkipWait -and $waitSeconds -gt 0) {
    $waitApplied = $waitSeconds
    Start-Sleep -Seconds $waitSeconds
}

$initialRefreshSteps = Invoke-RefreshSuite -ProjectRoot $projectRootResolved -AllowRepair:$false
$commonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT"
$initialSamples = Collect-SymbolSamples -CommonRoot $commonRoot -TargetSymbols $targetSymbols -Thresholds $thresholds -Samples $sampleCount -IntervalSeconds $sampleInterval
$initialEvaluation = Evaluate-StartupState -ProjectRoot $projectRootResolved -TargetSymbols $targetSymbols -Thresholds $thresholds -Samples $initialSamples -RefreshSteps $initialRefreshSteps

$repairApplied = $false
$repairSteps = @()
$finalSamples = $initialSamples
$finalEvaluation = $initialEvaluation

if (-not $initialEvaluation.ok -and $ApplySafeRepair) {
    $repairApplied = $true
    $repairSteps = Invoke-RefreshSuite -ProjectRoot $projectRootResolved -AllowRepair:$true
    $finalSamples = Collect-SymbolSamples -CommonRoot $commonRoot -TargetSymbols $targetSymbols -Thresholds $thresholds -Samples $sampleCount -IntervalSeconds $sampleInterval
    $finalEvaluation = Evaluate-StartupState -ProjectRoot $projectRootResolved -TargetSymbols $targetSymbols -Thresholds $thresholds -Samples $finalSamples -RefreshSteps $repairSteps
}

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    project_root = $projectRootResolved
    contract_path = $ContractPath
    symbol_scope = [string](Get-OptionalValue -Object $contract -Name "symbol_scope" -Default "")
    target_symbols = @($targetSymbols)
    wait_before_audit_sec = $waitSeconds
    wait_applied_sec = $waitApplied
    continuity_samples = $sampleCount
    continuity_interval_sec = $sampleInterval
    apply_safe_repair = [bool]$ApplySafeRepair
    repair_applied = $repairApplied
    initial = [pscustomobject]@{
        ok = $initialEvaluation.ok
        verdict = $initialEvaluation.verdict
        summary = $initialEvaluation.summary
        findings = $initialEvaluation.findings
        refresh_steps = $initialRefreshSteps
    }
    final = $finalEvaluation
    sample_window = [pscustomobject]@{
        initial = @($initialSamples)
        final = @($finalSamples)
    }
    ok = $finalEvaluation.ok
    verdict = $finalEvaluation.verdict
}

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Audit Post Migration Startup")
$lines.Add("")
$lines.Add(("- wygenerowano: {0}" -f $report.generated_at_local))
$lines.Add(("- verdict: {0}" -f $report.verdict))
$lines.Add(("- ok: {0}" -f ([string]$report.ok).ToLowerInvariant()))
$lines.Add(("- wait_applied_sec: {0}" -f $report.wait_applied_sec))
$lines.Add(("- continuity_samples: {0}" -f $report.continuity_samples))
$lines.Add(("- continuity_interval_sec: {0}" -f $report.continuity_interval_sec))
$lines.Add(("- repair_applied: {0}" -f ([string]$report.repair_applied).ToLowerInvariant()))
$lines.Add("")
$lines.Add("## Final Summary")
$lines.Add("")
$lines.Add(("- target_symbol_count: {0}" -f $report.final.summary.target_symbol_count))
$lines.Add(("- continuity_confirmed_count: {0}" -f $report.final.summary.continuity_confirmed_count))
$lines.Add(("- continuity_fresh_count: {0}" -f $report.final.summary.continuity_fresh_count))
$lines.Add(("- hosting_roster_count: {0}" -f $report.final.summary.hosting_roster_count))
$lines.Add(("- watchdog_terminal_running: {0}" -f ([string]$report.final.summary.watchdog_terminal_running).ToLowerInvariant()))
$lines.Add(("- watchdog_missing_target_count: {0}" -f $report.final.summary.watchdog_missing_target_count))
$lines.Add(("- watchdog_stale_target_count: {0}" -f $report.final.summary.watchdog_stale_target_count))
$lines.Add(("- fresh_paper_open_count: {0}" -f $report.final.summary.fresh_paper_open_count))
$lines.Add(("- truth_live_symbol_count: {0}" -f $report.final.summary.truth_live_symbol_count))
$lines.Add(("- truth_flow_state: {0}" -f $report.final.summary.truth_flow_state))
$lines.Add(("- pending_vps_sync_count: {0}" -f $report.final.summary.pending_vps_sync_count))
$lines.Add("")
$lines.Add("## Findings")
$lines.Add("")
if (@($report.final.findings).Count -eq 0) {
    $lines.Add("- brak krytycznych i wysokich problemow po migracji")
}
else {
    foreach ($finding in @($report.final.findings)) {
        $lines.Add(("- [{0}] {1}: {2}" -f $finding.severity, $finding.component, $finding.message))
    }
}
$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report | ConvertTo-Json -Depth 10
