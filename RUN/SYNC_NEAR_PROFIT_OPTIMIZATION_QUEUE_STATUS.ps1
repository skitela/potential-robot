param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OpsEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\logs",
    [string]$CommonFilesRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$Mt5TesterStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_tester_status_latest.json",
    [string]$BatchReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\near_profit_optimization_latest.json",
    [bool]$UseDedicatedPortableLabLane = $true,
    [string]$DedicatedLabTerminalRoot = "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB",
    [int]$NearProfitCount = 3,
    [string]$State,
    [string]$CurrentSymbol = "",
    [string[]]$Completed = @(),
    [string[]]$Pending = @(),
    [string]$CurrentNote = "",
    [string]$LogPath = "",
    [string]$StartedAtLocal = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-NearProfitSymbols {
    param(
        [string]$Path,
        [int]$TopCount
    )

    $profitTracking = Read-JsonFile -Path $Path
    if ($null -eq $profitTracking) {
        return @()
    }

    $nearProfit = @($profitTracking.near_profit | Sort-Object priority_rank, symbol_alias)
    if ($nearProfit.Count -le 0) {
        return @()
    }

    return @(
        $nearProfit |
            Select-Object -First ([Math]::Max(1, $TopCount)) |
            ForEach-Object { [string]$_.symbol_alias } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-WrapperProcesses {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*near_profit_optimization_after_idle_wrapper_*"
            }
    )
}

function Get-NearProfitRiskGuardProcesses {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*near_profit_mt5_risk_popup_guard_wrapper_*"
            }
    )
}

function Get-DedicatedLabProcessState {
    param([string]$TerminalRoot)

    if ([string]::IsNullOrWhiteSpace($TerminalRoot) -or -not (Test-Path -LiteralPath $TerminalRoot)) {
        return [pscustomobject]@{
            terminal_count = 0
            metatester_count = 0
            total_count = 0
        }
    }

    $terminalRootFull = [System.IO.Path]::GetFullPath($TerminalRoot).TrimEnd('\')
    $terminalRootPrefix = ($terminalRootFull + "\").ToLowerInvariant()
    $matchingProcesses = @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                ($_.Name -eq "terminal64.exe" -or $_.Name -eq "metatester64.exe") -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                ([System.IO.Path]::GetFullPath($_.ExecutablePath).ToLowerInvariant().StartsWith($terminalRootPrefix))
            }
    )

    return [pscustomobject]@{
        terminal_count = @($matchingProcesses | Where-Object { $_.Name -eq "terminal64.exe" }).Count
        metatester_count = @($matchingProcesses | Where-Object { $_.Name -eq "metatester64.exe" }).Count
        total_count = $matchingProcesses.Count
    }
}

function Parse-RunStamp {
    param([string]$RunStamp)

    if ([string]::IsNullOrWhiteSpace($RunStamp)) {
        return $null
    }

    try {
        return [datetime]::ParseExact($RunStamp, "yyyyMMdd_HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }
}

function Convert-ToCanonicalSymbol {
    param([string]$Symbol)

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return ""
    }

    $canonical = $Symbol.Trim().ToUpperInvariant()
    $dotIndex = $canonical.IndexOf(".")
    if ($dotIndex -gt 0) {
        $canonical = $canonical.Substring(0, $dotIndex)
    }
    return $canonical
}

function Read-KeyValueTsvMap {
    param([string]$Path)

    $map = @{}
    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $map
    }

    foreach ($line in Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        $parts = $line -split "`t", 2
        if ($parts.Count -ne 2) {
            continue
        }
        $map[[string]$parts[0]] = [string]$parts[1]
    }

    return $map
}

function Convert-FromUnixTimeOrNull {
    param([object]$Value)

    try {
        $seconds = [long]$Value
        if ($seconds -le 0) {
            return $null
        }
        return [DateTimeOffset]::FromUnixTimeSeconds($seconds)
    }
    catch {
        return $null
    }
}

function Get-TextLineCount {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return 0
    }

    return [int](@(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Measure-Object -Line).Lines)
}

function Resolve-ActiveSandboxState {
    param(
        [string]$Root,
        [string]$CurrentSymbol
    )

    $canonical = Convert-ToCanonicalSymbol -Symbol $CurrentSymbol
    if ([string]::IsNullOrWhiteSpace($canonical) -or -not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $sandboxRoot = Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like ("MAKRO_I_MIKRO_BOT_TESTER_{0}_*" -f $canonical) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($null -eq $sandboxRoot) {
        return $null
    }

    $stateDir = Join-Path $sandboxRoot.FullName ("state\{0}" -f $canonical)
    $logDir = Join-Path $sandboxRoot.FullName ("logs\{0}" -f $canonical)
    $runDir = Join-Path $sandboxRoot.FullName ("run\{0}" -f $canonical)
    $runtimeStatePath = Join-Path $stateDir "runtime_state.csv"
    $runtimeStatusPath = Join-Path $stateDir "runtime_status.json"
    $heartbeatPath = Join-Path $stateDir "heartbeat.txt"
    $candidateSignalsPath = Join-Path $logDir "candidate_signals.csv"
    $decisionEventsPath = Join-Path $logDir "decision_events.csv"
    $tuningExperimentsPath = Join-Path $logDir "tuning_experiments.csv"
    $testerPassPath = Join-Path $runDir "tester_optimization_passes.jsonl"
    $testerSessionPath = Join-Path $runDir "tester_telemetry_session.json"

    $runtimeState = Read-KeyValueTsvMap -Path $runtimeStatePath
    $heartbeatMarket = Convert-FromUnixTimeOrNull -Value $runtimeState["last_heartbeat_at"]
    $lastTick = Convert-FromUnixTimeOrNull -Value $runtimeState["last_tick_at"]
    $heartbeatItem = if (Test-Path -LiteralPath $heartbeatPath) { Get-Item -LiteralPath $heartbeatPath -ErrorAction SilentlyContinue } else { $null }
    $heartbeatAgeSec = if ($null -ne $heartbeatItem) {
        [int][Math]::Max(0, ((Get-Date) - $heartbeatItem.LastWriteTime).TotalSeconds)
    } else {
        [int]::MaxValue
    }
    $candidateSignalsItem = if (Test-Path -LiteralPath $candidateSignalsPath) { Get-Item -LiteralPath $candidateSignalsPath -ErrorAction SilentlyContinue } else { $null }
    $decisionEventsItem = if (Test-Path -LiteralPath $decisionEventsPath) { Get-Item -LiteralPath $decisionEventsPath -ErrorAction SilentlyContinue } else { $null }
    $tuningExperimentsItem = if (Test-Path -LiteralPath $tuningExperimentsPath) { Get-Item -LiteralPath $tuningExperimentsPath -ErrorAction SilentlyContinue } else { $null }
    $testerPassItem = if (Test-Path -LiteralPath $testerPassPath) { Get-Item -LiteralPath $testerPassPath -ErrorAction SilentlyContinue } else { $null }

    return [ordered]@{
        root_path = $sandboxRoot.FullName
        root_name = $sandboxRoot.Name
        runtime_state_path = $runtimeStatePath
        runtime_status_path = $runtimeStatusPath
        heartbeat_path = $heartbeatPath
        heartbeat_at_local = if ($null -ne $heartbeatItem) { $heartbeatItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        heartbeat_age_sec = $heartbeatAgeSec
        heartbeat_fresh = ($heartbeatAgeSec -le 300)
        market_heartbeat_at_local = if ($null -ne $heartbeatMarket) { $heartbeatMarket.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        market_last_tick_at_local = if ($null -ne $lastTick) { $lastTick.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss") } else { "" }
        ticks_seen = [int](0 + $runtimeState["ticks_seen"])
        timer_cycles = [int](0 + $runtimeState["timer_cycles"])
        learning_sample_count = [int](0 + $runtimeState["learning_sample_count"])
        learning_win_count = [int](0 + $runtimeState["learning_win_count"])
        learning_loss_count = [int](0 + $runtimeState["learning_loss_count"])
        realized_pnl_lifetime = [double](0 + $runtimeState["realized_pnl_lifetime"])
        candidate_signal_rows = Get-TextLineCount -Path $candidateSignalsPath
        candidate_signal_bytes = if ($null -ne $candidateSignalsItem) { [long]$candidateSignalsItem.Length } else { 0L }
        decision_event_rows = Get-TextLineCount -Path $decisionEventsPath
        decision_event_bytes = if ($null -ne $decisionEventsItem) { [long]$decisionEventsItem.Length } else { 0L }
        tuning_experiment_rows = Get-TextLineCount -Path $tuningExperimentsPath
        tuning_experiment_bytes = if ($null -ne $tuningExperimentsItem) { [long]$tuningExperimentsItem.Length } else { 0L }
        tester_pass_rows = Get-TextLineCount -Path $testerPassPath
        tester_pass_bytes = if ($null -ne $testerPassItem) { [long]$testerPassItem.Length } else { 0L }
        tester_session_present = (Test-Path -LiteralPath $testerSessionPath)
    }
}

function Resolve-LogItem {
    param(
        [string]$Root,
        [string]$ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath)) {
        return Get-Item -LiteralPath $ExplicitPath
    }

    return Get-ChildItem -Path $Root -Filter "near_profit_optimization_after_idle_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-LatestOptimizationRunSummaryItem {
    param([string]$BatchReportPath)

    if ([string]::IsNullOrWhiteSpace($BatchReportPath)) {
        return $null
    }

    $dir = Split-Path -Parent $BatchReportPath
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        return $null
    }

    $batchReportName = [System.IO.Path]::GetFileName($BatchReportPath)
    return Get-ChildItem -Path $dir -Filter "*_summary.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $batchReportName } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Write-StatusArtifacts {
    param(
        [hashtable]$Status,
        [string]$JsonPath,
        [string]$MdPath
    )

    $Status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Near Profit Optimization Queue")
    $lines.Add("")
    $lines.Add(("- generated_at_local: {0}" -f $Status.generated_at_local))
    $lines.Add(("- state: {0}" -f $Status.state))
    $lines.Add(("- current_symbol: {0}" -f $Status.current_symbol))
    $lines.Add(("- wrapper_running: {0}" -f $Status.wrapper_running))
    $lines.Add(("- active_wrapper_count: {0}" -f $Status.active_wrapper_count))
    $lines.Add(("- dedicated_portable_lab_lane: {0}" -f $Status.dedicated_portable_lab_lane))
    $lines.Add(("- dedicated_lab_terminal_count: {0}" -f $Status.dedicated_lab_terminal_count))
    $lines.Add(("- dedicated_lab_metatester_count: {0}" -f $Status.dedicated_lab_metatester_count))
    $lines.Add(("- near_profit_risk_guard_running: {0}" -f $Status.near_profit_risk_guard_running))
    $lines.Add(("- near_profit_risk_guard_count: {0}" -f $Status.near_profit_risk_guard_count))
    $lines.Add(("- near_profit_risk_guard_accepted_events: {0}" -f $Status.near_profit_risk_guard_accepted_events))
    $lines.Add(("- near_profit_risk_guard_rejected_events: {0}" -f $Status.near_profit_risk_guard_rejected_events))
    $lines.Add(("- log_path: {0}" -f $Status.log_path))
    $lines.Add(("- batch_report_path: {0}" -f $Status.batch_report_path))
    if (-not [string]::IsNullOrWhiteSpace([string]$Status.current_note)) {
        $lines.Add(("- current_note: {0}" -f $Status.current_note))
    }
    if ($null -ne $Status.active_sandbox) {
        $lines.Add("")
        $lines.Add("## Active Sandbox")
        $lines.Add("")
        $lines.Add(("- root_name: {0}" -f $Status.active_sandbox.root_name))
        $lines.Add(("- heartbeat_at_local: {0}" -f $Status.active_sandbox.heartbeat_at_local))
        $lines.Add(("- heartbeat_age_sec: {0}" -f $Status.active_sandbox.heartbeat_age_sec))
        $lines.Add(("- heartbeat_fresh: {0}" -f $Status.active_sandbox.heartbeat_fresh))
        $lines.Add(("- market_heartbeat_at_local: {0}" -f $Status.active_sandbox.market_heartbeat_at_local))
        $lines.Add(("- market_last_tick_at_local: {0}" -f $Status.active_sandbox.market_last_tick_at_local))
        $lines.Add(("- ticks_seen: {0}" -f $Status.active_sandbox.ticks_seen))
        $lines.Add(("- timer_cycles: {0}" -f $Status.active_sandbox.timer_cycles))
        $lines.Add(("- learning_sample_count: {0}" -f $Status.active_sandbox.learning_sample_count))
        $lines.Add(("- realized_pnl_lifetime: {0}" -f $Status.active_sandbox.realized_pnl_lifetime))
        $lines.Add(("- candidate_signal_rows: {0}" -f $Status.active_sandbox.candidate_signal_rows))
        $lines.Add(("- candidate_signal_bytes: {0}" -f $Status.active_sandbox.candidate_signal_bytes))
        $lines.Add(("- decision_event_rows: {0}" -f $Status.active_sandbox.decision_event_rows))
        $lines.Add(("- decision_event_bytes: {0}" -f $Status.active_sandbox.decision_event_bytes))
        $lines.Add(("- tuning_experiment_rows: {0}" -f $Status.active_sandbox.tuning_experiment_rows))
        $lines.Add(("- tuning_experiment_bytes: {0}" -f $Status.active_sandbox.tuning_experiment_bytes))
        $lines.Add(("- tester_pass_rows: {0}" -f $Status.active_sandbox.tester_pass_rows))
        $lines.Add(("- tester_pass_bytes: {0}" -f $Status.active_sandbox.tester_pass_bytes))
        $lines.Add(("- tester_session_present: {0}" -f $Status.active_sandbox.tester_session_present))
    }
    $lines.Add("")
    $lines.Add("## Selected")
    $lines.Add("")
    if (@($Status.selected_symbols).Count -gt 0) {
        foreach ($symbol in @($Status.selected_symbols)) {
            $lines.Add(("- {0}" -f $symbol))
        }
    }
    else {
        $lines.Add("- none")
    }
    $lines.Add("")
    $lines.Add("## Completed")
    $lines.Add("")
    if (@($Status.completed).Count -gt 0) {
        foreach ($symbol in @($Status.completed)) {
            $lines.Add(("- {0}" -f $symbol))
        }
    }
    else {
        $lines.Add("- none")
    }
    $lines.Add("")
    $lines.Add("## Pending")
    $lines.Add("")
    if (@($Status.pending).Count -gt 0) {
        foreach ($symbol in @($Status.pending)) {
            $lines.Add(("- {0}" -f $symbol))
        }
    }
    else {
        $lines.Add("- none")
    }

    ($lines -join "`r`n") | Set-Content -LiteralPath $MdPath -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $OpsEvidenceDir | Out-Null

$latestJson = Join-Path $OpsEvidenceDir "near_profit_optimization_queue_latest.json"
$latestMd = Join-Path $OpsEvidenceDir "near_profit_optimization_queue_latest.md"

$selectedSymbols = @(Get-NearProfitSymbols -Path $ProfitTrackingPath -TopCount $NearProfitCount)
$wrapperProcesses = @(Get-WrapperProcesses)
$wrapperRunning = ($wrapperProcesses.Count -gt 0)
$nearProfitRiskGuardProcesses = @(Get-NearProfitRiskGuardProcesses)
$nearProfitRiskGuardStatusPath = Join-Path $ProjectRoot "RUN\near_profit_mt5_risk_guard_status.json"
$nearProfitRiskGuardStatus = Read-JsonFile -Path $nearProfitRiskGuardStatusPath
$dedicatedLabProcessState = Get-DedicatedLabProcessState -TerminalRoot $DedicatedLabTerminalRoot
$dedicatedLabHasActivity = ($dedicatedLabProcessState.total_count -gt 0)
$logItem = Resolve-LogItem -Root $LogRoot -ExplicitPath $LogPath
$mt5TesterStatus = Read-JsonFile -Path $Mt5TesterStatusPath
$batchReport = Read-JsonFile -Path $BatchReportPath
$latestOptimizationSummaryItem = Resolve-LatestOptimizationRunSummaryItem -BatchReportPath $BatchReportPath
$latestOptimizationSummary = if ($null -ne $latestOptimizationSummaryItem) { Read-JsonFile -Path $latestOptimizationSummaryItem.FullName } else { $null }

$resolvedState = $State
$resolvedCurrentSymbol = $CurrentSymbol
$resolvedCompleted = @($Completed)
$resolvedPending = @($Pending)
$resolvedNote = $CurrentNote
$resolvedStartedAt = $StartedAtLocal

if ([string]::IsNullOrWhiteSpace($resolvedStartedAt) -and $null -ne $logItem) {
    $resolvedStartedAt = $logItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}

if ([string]::IsNullOrWhiteSpace($resolvedState)) {
    $resolvedState = "idle"
    $resolvedCompleted = @()
    $resolvedPending = @($selectedSymbols)

    if ($wrapperRunning) {
        $resolvedState = if ($UseDedicatedPortableLabLane) { "running" } else { "waiting_for_idle" }
        $logStart = if ($null -ne $logItem) { $logItem.LastWriteTime } else { $null }
        $summaryFresh = (
            $null -ne $latestOptimizationSummaryItem -and
            (($null -eq $logStart) -or $latestOptimizationSummaryItem.LastWriteTime -ge $logStart.AddSeconds(-15))
        )
        if ($summaryFresh -and $null -ne $latestOptimizationSummary) {
            $resolvedState = "running"
            $resolvedCurrentSymbol = [string]$latestOptimizationSummary.symbol_alias
            if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "optimization_lane_active_from_summary"
            }
        }
        elseif ($UseDedicatedPortableLabLane) {
            if ($dedicatedLabHasActivity) {
                if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                    $resolvedNote = "portable_lab_lane_active"
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "portable_lab_wrapper_running"
            }

            if ([string]::IsNullOrWhiteSpace($resolvedCurrentSymbol) -and @($resolvedPending).Count -gt 0) {
                $resolvedCurrentSymbol = [string]$resolvedPending[0]
            }
        }
        elseif ($null -ne $mt5TesterStatus -and [string]$mt5TesterStatus.state -eq "running") {
            $runStampDate = Parse-RunStamp -RunStamp ([string]$mt5TesterStatus.run_stamp)
            $resolvedCurrentSymbol = [string]$mt5TesterStatus.current_symbol

            if ($null -ne $runStampDate -and $null -ne $logStart -and $runStampDate -ge $logStart.AddMinutes(-1)) {
                $resolvedState = "running"
                if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                    $resolvedNote = "optimization_lane_active"
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "waiting_for_secondary_mt5_idle"
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($resolvedNote)) {
            $resolvedNote = "wrapper_running_without_active_mt5"
        }
    }
    elseif ($null -ne $batchReport) {
        $batchReportItem = if (Test-Path -LiteralPath $BatchReportPath) { Get-Item -LiteralPath $BatchReportPath -ErrorAction SilentlyContinue } else { $null }
        $batchReportFreshForCurrentWrapper = (
            $null -ne $batchReportItem -and
            (
                $null -eq $logItem -or
                $batchReportItem.LastWriteTime -ge $logItem.LastWriteTime.AddSeconds(-15)
            )
        )

        if ($batchReportFreshForCurrentWrapper) {
            $resolvedState = "completed"
            $resolvedCompleted = @($batchReport.symbols)
            $resolvedPending = @()
            if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "batch_report_available"
            }
        }
        else {
            $resolvedState = "stale"
            if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "stale_batch_report"
            }
        }
    }
    elseif ($null -ne $logItem) {
        $resolvedState = "stale"
        if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
            $resolvedNote = "log_present_without_live_wrapper"
        }
    }
}

if (@($resolvedPending).Count -eq 0 -and @($selectedSymbols).Count -gt 0 -and $resolvedState -notin @("completed", "failed")) {
    $resolvedPending = @($selectedSymbols | Where-Object { @($resolvedCompleted) -notcontains $_ })
}

$activeSandbox = Resolve-ActiveSandboxState -Root $CommonFilesRoot -CurrentSymbol $resolvedCurrentSymbol

$status = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    state = $resolvedState
    current_symbol = $resolvedCurrentSymbol
    selected_symbols = @($selectedSymbols)
    completed = @($resolvedCompleted)
    pending = @($resolvedPending)
    near_profit_count = $NearProfitCount
    wrapper_running = $wrapperRunning
    active_wrapper_count = $wrapperProcesses.Count
    dedicated_portable_lab_lane = $UseDedicatedPortableLabLane
    dedicated_lab_terminal_count = $dedicatedLabProcessState.terminal_count
    dedicated_lab_metatester_count = $dedicatedLabProcessState.metatester_count
    near_profit_risk_guard_running = ($nearProfitRiskGuardProcesses.Count -gt 0)
    near_profit_risk_guard_count = $nearProfitRiskGuardProcesses.Count
    near_profit_risk_guard_status_path = $nearProfitRiskGuardStatusPath
    near_profit_risk_guard_accepted_events = if ($null -ne $nearProfitRiskGuardStatus) { [int](0 + $nearProfitRiskGuardStatus.accepted_events) } else { 0 }
    near_profit_risk_guard_rejected_events = if ($null -ne $nearProfitRiskGuardStatus) { [int](0 + $nearProfitRiskGuardStatus.rejected_events) } else { 0 }
    near_profit_risk_guard_last_popup_action_utc = if ($null -ne $nearProfitRiskGuardStatus) { [string]$nearProfitRiskGuardStatus.last_popup_action_utc } else { "" }
    started_at_local = $resolvedStartedAt
    log_path = if ($null -ne $logItem) { $logItem.FullName } else { $LogPath }
    batch_report_path = $BatchReportPath
    batch_report_present = ($null -ne $batchReport)
    mt5_status_path = $Mt5TesterStatusPath
    current_note = $resolvedNote
    active_sandbox = $activeSandbox
}

Write-StatusArtifacts -Status $status -JsonPath $latestJson -MdPath $latestMd
$status
