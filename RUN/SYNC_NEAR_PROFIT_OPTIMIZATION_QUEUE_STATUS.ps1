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
    [string]$StartedAtLocal = "",
    [int]$RunTimeoutSec = 0
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

function Get-NearProfitOrderKey {
    param([object]$Entry)

    $qdmReady = if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "qdm_custom_pilot_ready") { [bool]$Entry.qdm_custom_pilot_ready } else { $false }
    $trustRank = 0
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "best_tester_trust") {
        $bestTesterTrust = [string]$Entry.best_tester_trust
        switch ($bestTesterTrust) {
            "LOW_SAMPLE" { $trustRank = 2 }
            "FOREFIELD_DIRTY" { $trustRank = 1 }
            "PAPER_CONVERSION_BLOCKED" { $trustRank = 1 }
            default { $trustRank = 0 }
        }
    }
    $bestTesterPnl = 0.0
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "best_tester_pnl") {
        try {
            $bestTesterPnl = [double]$Entry.best_tester_pnl
        }
        catch {
            $bestTesterPnl = 0.0
        }
    }
    $priorityRank = 999999
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "priority_rank") {
        try {
            $priorityRank = [int]$Entry.priority_rank
        }
        catch {
            $priorityRank = 999999
        }
    }

    return [pscustomobject]@{
        qdm_rank = if ($qdmReady) { 0 } else { 1 }
        trust_rank = $trustRank
        pnl_rank = -1.0 * $bestTesterPnl
        priority_rank = $priorityRank
        symbol_alias = [string]$Entry.symbol_alias
    }
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

    $nearProfit = @(
        $profitTracking.near_profit |
            Sort-Object `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).qdm_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).trust_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).pnl_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).priority_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).symbol_alias } }
    )
    if ($nearProfit.Count -le 0) {
        return @()
    }

    $testerPositiveAliasSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($entry in @($profitTracking.tester_positive)) {
        $alias = Convert-ToCanonicalSymbol -Symbol ([string]$entry.symbol_alias)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            [void]$testerPositiveAliasSet.Add($alias)
        }
    }

    $eligibleNearProfit = @(
        $nearProfit |
            Where-Object {
                $alias = Convert-ToCanonicalSymbol -Symbol ([string]$_.symbol_alias)
                -not [string]::IsNullOrWhiteSpace($alias) -and
                -not $testerPositiveAliasSet.Contains($alias)
            }
    )

    if ($eligibleNearProfit.Count -gt 0) {
        $nearProfit = $eligibleNearProfit
    }

    return @(
        $nearProfit |
            Select-Object -First ([Math]::Max(1, $TopCount)) |
            ForEach-Object { Convert-ToCanonicalSymbol -Symbol ([string]$_.symbol_alias) } |
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
            current_symbol = ""
            config_path = ""
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

    $terminalProcess = $matchingProcesses | Where-Object { $_.Name -eq "terminal64.exe" } | Select-Object -First 1
    $configPath = ""
    $currentSymbol = ""

    if ($null -ne $terminalProcess -and -not [string]::IsNullOrWhiteSpace($terminalProcess.CommandLine)) {
        $commandLine = [string]$terminalProcess.CommandLine
        $configMatch = [regex]::Match($commandLine, '/config:(?:"(?<path>[^"]+)"|(?<path>\S+))', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($configMatch.Success) {
            $configPath = [string]$configMatch.Groups["path"].Value
            if (Test-Path -LiteralPath $configPath) {
                try {
                    foreach ($line in Get-Content -LiteralPath $configPath -ErrorAction Stop) {
                        if ($line -like "Symbol=*") {
                            $currentSymbol = Convert-ToCanonicalSymbol -Symbol ($line.Substring(7))
                            break
                        }
                    }
                }
                catch {
                }
            }
        }
    }

    return [pscustomobject]@{
        terminal_count = @($matchingProcesses | Where-Object { $_.Name -eq "terminal64.exe" }).Count
        metatester_count = @($matchingProcesses | Where-Object { $_.Name -eq "metatester64.exe" }).Count
        total_count = $matchingProcesses.Count
        current_symbol = $currentSymbol
        config_path = $configPath
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

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream)
        $count = 0
        while ($null -ne $reader.ReadLine()) {
            $count++
        }
        return [int]$count
    }
    catch {
        return [int](@(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue | Measure-Object -Line).Lines)
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Get-TextFileStats {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            line_count = 0
            locked = $false
        }
    }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream)
        $count = 0
        while ($null -ne $reader.ReadLine()) {
            $count++
        }
        return [pscustomobject]@{
            line_count = [int]$count
            locked = $false
        }
    }
    catch {
        return [pscustomobject]@{
            line_count = 0
            locked = $true
        }
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Read-LastNonEmptyLine {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    try {
        $lines = @(Get-Content -LiteralPath $Path -ErrorAction Stop)
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            $line = [string]$lines[$i]
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                return $line
            }
        }
    }
    catch {
    }

    return ""
}

function Get-TesterPassSummary {
    param([string]$Path)

    $summary = [ordered]@{
        latest_pass = $null
        best_pass = $null
        positive_count = 0
    }

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]$summary
    }

    $stream = $null
    $reader = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        $reader = New-Object System.IO.StreamReader($stream)
        while (-not $reader.EndOfStream) {
            $line = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }

            try {
                $pass = $line | ConvertFrom-Json
            }
            catch {
                continue
            }

            $summary.latest_pass = $pass
            $pnl = [double](0 + $pass.realized_pnl_lifetime)
            if ($pnl -gt 0) {
                $summary.positive_count++
            }

            if ($null -eq $summary.best_pass -or $pnl -gt [double](0 + $summary.best_pass.realized_pnl_lifetime)) {
                $summary.best_pass = $pass
            }
        }
    }
    catch {
        return [pscustomobject]$summary
    }
    finally {
        if ($null -ne $reader) {
            $reader.Dispose()
        }
        elseif ($null -ne $stream) {
            $stream.Dispose()
        }
    }

    return [pscustomobject]$summary
}

function Resolve-ActiveSandboxState {
    param(
        [string]$Root,
        [string]$CurrentSymbol,
        [string[]]$PreferredTagTokens = @()
    )

    $canonical = Convert-ToCanonicalSymbol -Symbol $CurrentSymbol
    if ([string]::IsNullOrWhiteSpace($canonical) -or -not (Test-Path -LiteralPath $Root)) {
        return $null
    }

    $candidateRoots = @(
        Get-ChildItem -Path $Root -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like ("MAKRO_I_MIKRO_BOT_TESTER_{0}_*" -f $canonical) } |
            Sort-Object LastWriteTime -Descending
    )

    $sandboxRoot = $null
    if ($candidateRoots.Count -gt 0 -and $PreferredTagTokens.Count -gt 0) {
        $sandboxRoot = @(
            $candidateRoots |
                Where-Object {
                    $rootNameUpper = $_.Name.ToUpperInvariant()
                    foreach ($token in $PreferredTagTokens) {
                        if (-not [string]::IsNullOrWhiteSpace($token) -and $rootNameUpper.Contains($token.ToUpperInvariant())) {
                            return $true
                        }
                    }
                    return $false
                }
        ) | Select-Object -First 1
    }

    if ($null -eq $sandboxRoot) {
        $sandboxRoot = $candidateRoots | Select-Object -First 1
    }

    if ($null -eq $sandboxRoot) {
        return $null
    }

    $stateDir = Join-Path $sandboxRoot.FullName ("state\{0}" -f $canonical)
    $logDir = Join-Path $sandboxRoot.FullName ("logs\{0}" -f $canonical)
    $runDir = Join-Path $sandboxRoot.FullName ("run\{0}" -f $canonical)
    $keyDir = Join-Path $sandboxRoot.FullName ("key\{0}" -f $canonical)
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
    $candidateSignalStats = Get-TextFileStats -Path $candidateSignalsPath
    $decisionEventStats = Get-TextFileStats -Path $decisionEventsPath
    $tuningExperimentStats = Get-TextFileStats -Path $tuningExperimentsPath
    $testerPassStats = Get-TextFileStats -Path $testerPassPath
    $testerPassSummary = Get-TesterPassSummary -Path $testerPassPath
    $latestTesterPass = $testerPassSummary.latest_pass
    $bestTesterPass = $testerPassSummary.best_pass

    return [ordered]@{
        root_path = $sandboxRoot.FullName
        root_name = $sandboxRoot.Name
        state_dir_present = (Test-Path -LiteralPath $stateDir)
        log_dir_present = (Test-Path -LiteralPath $logDir)
        run_dir_present = (Test-Path -LiteralPath $runDir)
        key_dir_present = (Test-Path -LiteralPath $keyDir)
        storage_contract_complete = (
            (Test-Path -LiteralPath $stateDir) -and
            (Test-Path -LiteralPath $logDir) -and
            (Test-Path -LiteralPath $runDir) -and
            (Test-Path -LiteralPath $keyDir)
        )
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
        candidate_signal_rows = $candidateSignalStats.line_count
        candidate_signal_rows_locked = $candidateSignalStats.locked
        candidate_signal_bytes = if ($null -ne $candidateSignalsItem) { [long]$candidateSignalsItem.Length } else { 0L }
        decision_event_rows = $decisionEventStats.line_count
        decision_event_rows_locked = $decisionEventStats.locked
        decision_event_bytes = if ($null -ne $decisionEventsItem) { [long]$decisionEventsItem.Length } else { 0L }
        tuning_experiment_rows = $tuningExperimentStats.line_count
        tuning_experiment_rows_locked = $tuningExperimentStats.locked
        tuning_experiment_bytes = if ($null -ne $tuningExperimentsItem) { [long]$tuningExperimentsItem.Length } else { 0L }
        tester_pass_rows = $testerPassStats.line_count
        tester_pass_rows_locked = $testerPassStats.locked
        tester_pass_bytes = if ($null -ne $testerPassItem) { [long]$testerPassItem.Length } else { 0L }
        tester_session_present = (Test-Path -LiteralPath $testerSessionPath)
        tester_positive_pass_count = [int](0 + $testerPassSummary.positive_count)
        latest_tester_pass_frame = if ($null -ne $latestTesterPass) { [int](0 + $latestTesterPass.frame_pass) } else { 0 }
        latest_tester_pass_custom_score = if ($null -ne $latestTesterPass) { [double](0 + $latestTesterPass.custom_score) } else { 0.0 }
        latest_tester_pass_realized_pnl = if ($null -ne $latestTesterPass) { [double](0 + $latestTesterPass.realized_pnl_lifetime) } else { 0.0 }
        latest_tester_pass_inputs = if ($null -ne $latestTesterPass -and $latestTesterPass.PSObject.Properties.Name -contains "optimization_inputs") { @($latestTesterPass.optimization_inputs) } else { @() }
        best_tester_pass_custom_score = if ($null -ne $bestTesterPass) { [double](0 + $bestTesterPass.custom_score) } else { 0.0 }
        best_tester_pass_realized_pnl = if ($null -ne $bestTesterPass) { [double](0 + $bestTesterPass.realized_pnl_lifetime) } else { 0.0 }
        best_tester_pass_inputs = if ($null -ne $bestTesterPass -and $bestTesterPass.PSObject.Properties.Name -contains "optimization_inputs") { @($bestTesterPass.optimization_inputs) } else { @() }
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
    param(
        [string]$BatchReportPath,
        [datetime]$StartedAt = [datetime]::MinValue,
        [string[]]$SelectedSymbols = @()
    )

    if ([string]::IsNullOrWhiteSpace($BatchReportPath)) {
        return $null
    }

    $dir = Split-Path -Parent $BatchReportPath
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        return $null
    }

    $selectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($symbol in @($SelectedSymbols)) {
        $alias = Convert-ToCanonicalSymbol -Symbol ([string]$symbol)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            [void]$selectedSet.Add($alias)
        }
    }

    $batchReportName = [System.IO.Path]::GetFileName($BatchReportPath)
    foreach ($candidate in @(Get-ChildItem -Path $dir -Filter "*_summary.json" -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $batchReportName } | Sort-Object LastWriteTime -Descending)) {
        if ($StartedAt -ne [datetime]::MinValue -and $candidate.LastWriteTime -lt $StartedAt.AddSeconds(-15)) {
            continue
        }

        if ($selectedSet.Count -gt 0) {
            $summary = Read-JsonFile -Path $candidate.FullName
            if ($null -eq $summary) {
                continue
            }
            $alias = Convert-ToCanonicalSymbol -Symbol ([string]$summary.symbol_alias)
            if ([string]::IsNullOrWhiteSpace($alias) -or -not $selectedSet.Contains($alias)) {
                continue
            }
        }

        return $candidate
    }

    return $null
}

function Get-CompletedOptimizationSymbolsSinceStart {
    param(
        [string]$BatchReportPath,
        [datetime]$StartedAt = [datetime]::MinValue,
        [string[]]$SelectedSymbols = @()
    )

    $dir = Split-Path -Parent $BatchReportPath
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        return @()
    }

    $selectedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($symbol in @($SelectedSymbols)) {
        $alias = Convert-ToCanonicalSymbol -Symbol ([string]$symbol)
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            [void]$selectedSet.Add($alias)
        }
    }

    $completed = New-Object System.Collections.Generic.List[string]
    foreach ($summaryItem in @(Get-ChildItem -Path $dir -Filter "*_summary.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending)) {
        if ($StartedAt -ne [datetime]::MinValue -and $summaryItem.LastWriteTime -lt $StartedAt.AddSeconds(-15)) {
            continue
        }

        $summary = Read-JsonFile -Path $summaryItem.FullName
        if ($null -eq $summary) {
            continue
        }

        $alias = Convert-ToCanonicalSymbol -Symbol ([string]$summary.symbol_alias)
        if ([string]::IsNullOrWhiteSpace($alias) -or -not $selectedSet.Contains($alias)) {
            continue
        }

        if (-not $completed.Contains($alias)) {
            [void]$completed.Add($alias)
        }
    }

    return @($completed.ToArray())
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
    if ($Status.run_timeout_sec -gt 0) {
        $lines.Add(("- run_timeout_sec: {0}" -f $Status.run_timeout_sec))
        $lines.Add(("- run_elapsed_sec: {0}" -f $Status.run_elapsed_sec))
        $lines.Add(("- run_remaining_sec: {0}" -f $Status.run_remaining_sec))
        $lines.Add(("- run_timeout_near: {0}" -f $Status.run_timeout_near))
    }
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
        $lines.Add(("- storage_contract_complete: {0}" -f $Status.active_sandbox.storage_contract_complete))
        $lines.Add(("- state_dir_present: {0}" -f $Status.active_sandbox.state_dir_present))
        $lines.Add(("- log_dir_present: {0}" -f $Status.active_sandbox.log_dir_present))
        $lines.Add(("- run_dir_present: {0}" -f $Status.active_sandbox.run_dir_present))
        $lines.Add(("- key_dir_present: {0}" -f $Status.active_sandbox.key_dir_present))
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
        $lines.Add(("- candidate_signal_rows_locked: {0}" -f $Status.active_sandbox.candidate_signal_rows_locked))
        $lines.Add(("- candidate_signal_bytes: {0}" -f $Status.active_sandbox.candidate_signal_bytes))
        $lines.Add(("- decision_event_rows: {0}" -f $Status.active_sandbox.decision_event_rows))
        $lines.Add(("- decision_event_rows_locked: {0}" -f $Status.active_sandbox.decision_event_rows_locked))
        $lines.Add(("- decision_event_bytes: {0}" -f $Status.active_sandbox.decision_event_bytes))
        $lines.Add(("- tuning_experiment_rows: {0}" -f $Status.active_sandbox.tuning_experiment_rows))
        $lines.Add(("- tuning_experiment_rows_locked: {0}" -f $Status.active_sandbox.tuning_experiment_rows_locked))
        $lines.Add(("- tuning_experiment_bytes: {0}" -f $Status.active_sandbox.tuning_experiment_bytes))
        $lines.Add(("- tester_pass_rows: {0}" -f $Status.active_sandbox.tester_pass_rows))
        $lines.Add(("- tester_pass_rows_locked: {0}" -f $Status.active_sandbox.tester_pass_rows_locked))
        $lines.Add(("- tester_pass_bytes: {0}" -f $Status.active_sandbox.tester_pass_bytes))
        $lines.Add(("- tester_session_present: {0}" -f $Status.active_sandbox.tester_session_present))
        $lines.Add(("- tester_positive_pass_count: {0}" -f $Status.active_sandbox.tester_positive_pass_count))
        if ($Status.active_sandbox.latest_tester_pass_frame -gt 0) {
            $lines.Add(("- latest_tester_pass_frame: {0}" -f $Status.active_sandbox.latest_tester_pass_frame))
            $lines.Add(("- latest_tester_pass_custom_score: {0}" -f $Status.active_sandbox.latest_tester_pass_custom_score))
            $lines.Add(("- latest_tester_pass_realized_pnl: {0}" -f $Status.active_sandbox.latest_tester_pass_realized_pnl))
            $lines.Add(("- latest_tester_pass_inputs: {0}" -f ((@($Status.active_sandbox.latest_tester_pass_inputs) -join "; "))))
        }
        if (@($Status.active_sandbox.best_tester_pass_inputs).Count -gt 0 -or $Status.active_sandbox.best_tester_pass_realized_pnl -ne 0) {
            $lines.Add(("- best_tester_pass_custom_score: {0}" -f $Status.active_sandbox.best_tester_pass_custom_score))
            $lines.Add(("- best_tester_pass_realized_pnl: {0}" -f $Status.active_sandbox.best_tester_pass_realized_pnl))
            $lines.Add(("- best_tester_pass_inputs: {0}" -f ((@($Status.active_sandbox.best_tester_pass_inputs) -join "; "))))
        }
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
$previousStatus = Read-JsonFile -Path $latestJson

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
$resolvedState = $State
$resolvedCurrentSymbol = $CurrentSymbol
$resolvedCompleted = @($Completed)
$resolvedPending = @($Pending)
$resolvedNote = $CurrentNote
$resolvedStartedAt = $StartedAtLocal
$resolvedRunTimeoutSec = $RunTimeoutSec

if ([string]::IsNullOrWhiteSpace($resolvedStartedAt) -and $null -ne $previousStatus) {
    $resolvedStartedAt = [string]$previousStatus.started_at_local
}

if (($resolvedRunTimeoutSec -le 0) -and $null -ne $previousStatus -and $previousStatus.PSObject.Properties.Name -contains "run_timeout_sec") {
    $resolvedRunTimeoutSec = [int](0 + $previousStatus.run_timeout_sec)
}

if (($resolvedRunTimeoutSec -le 0) -and $wrapperRunning -and $UseDedicatedPortableLabLane) {
    $resolvedRunTimeoutSec = 14400
}

if ([string]::IsNullOrWhiteSpace($resolvedStartedAt) -and $null -ne $logItem) {
    $resolvedStartedAt = $logItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}

$startedAtDate = $null
if (-not [string]::IsNullOrWhiteSpace($resolvedStartedAt)) {
    try {
        $startedAtDate = [datetime]::ParseExact($resolvedStartedAt, "yyyy-MM-dd HH:mm:ss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        $startedAtDate = $null
    }
}

$latestOptimizationSummaryItem = Resolve-LatestOptimizationRunSummaryItem -BatchReportPath $BatchReportPath -StartedAt $(if ($null -ne $startedAtDate) { $startedAtDate } else { [datetime]::MinValue }) -SelectedSymbols $selectedSymbols
$latestOptimizationSummary = if ($null -ne $latestOptimizationSummaryItem) { Read-JsonFile -Path $latestOptimizationSummaryItem.FullName } else { $null }
$latestOptimizationSummarySymbol = if ($null -ne $latestOptimizationSummary) { Convert-ToCanonicalSymbol -Symbol ([string]$latestOptimizationSummary.symbol_alias) } else { "" }
$completedSinceStart = Get-CompletedOptimizationSymbolsSinceStart -BatchReportPath $BatchReportPath -StartedAt $(if ($null -ne $startedAtDate) { $startedAtDate } else { [datetime]::MinValue }) -SelectedSymbols $selectedSymbols

$runElapsedSec = 0
if ($null -ne $startedAtDate) {
    $runElapsedSec = [int][Math]::Max(0, ((Get-Date) - $startedAtDate).TotalSeconds)
}

$runRemainingSec = 0
if ($resolvedRunTimeoutSec -gt 0) {
    $runRemainingSec = [int]($resolvedRunTimeoutSec - $runElapsedSec)
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
        if ($UseDedicatedPortableLabLane) {
            if ($dedicatedLabHasActivity) {
                if (-not [string]::IsNullOrWhiteSpace([string]$dedicatedLabProcessState.current_symbol)) {
                    $resolvedCurrentSymbol = [string]$dedicatedLabProcessState.current_symbol
                }

                if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                    $resolvedNote = "portable_lab_lane_active"
                }
                elseif (
                    $resolvedNote -eq "optimization_lane_active_from_summary" -and
                    -not [string]::IsNullOrWhiteSpace([string]$dedicatedLabProcessState.current_symbol) -and
                    (Convert-ToCanonicalSymbol -Symbol $resolvedCurrentSymbol) -ne (Convert-ToCanonicalSymbol -Symbol ([string]$dedicatedLabProcessState.current_symbol))
                ) {
                    $resolvedNote = "portable_lab_config_active"
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "portable_lab_wrapper_running"
            }

            if ([string]::IsNullOrWhiteSpace($resolvedCurrentSymbol) -and -not [string]::IsNullOrWhiteSpace([string]$dedicatedLabProcessState.current_symbol)) {
                $resolvedCurrentSymbol = [string]$dedicatedLabProcessState.current_symbol
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
    elseif ($UseDedicatedPortableLabLane -and $dedicatedLabHasActivity) {
        $resolvedState = "running"
        if (-not [string]::IsNullOrWhiteSpace([string]$dedicatedLabProcessState.current_symbol)) {
            $resolvedCurrentSymbol = [string]$dedicatedLabProcessState.current_symbol
        }
        if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
            $resolvedNote = "portable_lab_process_active"
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

if ($resolvedState -eq "running" -and @($completedSinceStart).Count -gt 0) {
    $resolvedCompleted = @(
        @($resolvedCompleted + $completedSinceStart) |
            ForEach-Object { Convert-ToCanonicalSymbol -Symbol ([string]$_) } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Select-Object -Unique
    )

    $activeCanonical = Convert-ToCanonicalSymbol -Symbol $resolvedCurrentSymbol
    $resolvedPending = @(
        $selectedSymbols |
            ForEach-Object { Convert-ToCanonicalSymbol -Symbol ([string]$_) } |
            Where-Object {
                -not [string]::IsNullOrWhiteSpace($_) -and
                ($_ -eq $activeCanonical -or @($resolvedCompleted) -notcontains $_)
            } |
            Select-Object -Unique
    )

    if (-not [string]::IsNullOrWhiteSpace($activeCanonical)) {
        $resolvedCompleted = @($resolvedCompleted | Where-Object { $_ -ne $activeCanonical })
    }
}

$preferredSandboxTagTokens = @()
if ($UseDedicatedPortableLabLane) {
    $preferredSandboxTagTokens += "OPT_WORKER_"
}

$activeSandboxSymbol = $resolvedCurrentSymbol
if (
    $UseDedicatedPortableLabLane -and
    -not [string]::IsNullOrWhiteSpace([string]$dedicatedLabProcessState.current_symbol)
) {
    $activeSandboxSymbol = [string]$dedicatedLabProcessState.current_symbol
}

$activeSandbox = Resolve-ActiveSandboxState -Root $CommonFilesRoot -CurrentSymbol $activeSandboxSymbol -PreferredTagTokens $preferredSandboxTagTokens

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
    dedicated_lab_current_symbol = [string]$dedicatedLabProcessState.current_symbol
    dedicated_lab_config_path = [string]$dedicatedLabProcessState.config_path
    latest_optimization_summary_symbol = $latestOptimizationSummarySymbol
    near_profit_risk_guard_running = ($nearProfitRiskGuardProcesses.Count -gt 0)
    near_profit_risk_guard_count = $nearProfitRiskGuardProcesses.Count
    near_profit_risk_guard_status_path = $nearProfitRiskGuardStatusPath
    near_profit_risk_guard_accepted_events = if ($null -ne $nearProfitRiskGuardStatus) { [int](0 + $nearProfitRiskGuardStatus.accepted_events) } else { 0 }
    near_profit_risk_guard_rejected_events = if ($null -ne $nearProfitRiskGuardStatus) { [int](0 + $nearProfitRiskGuardStatus.rejected_events) } else { 0 }
    near_profit_risk_guard_last_popup_action_utc = if ($null -ne $nearProfitRiskGuardStatus) { [string]$nearProfitRiskGuardStatus.last_popup_action_utc } else { "" }
    started_at_local = $resolvedStartedAt
    run_timeout_sec = $resolvedRunTimeoutSec
    run_elapsed_sec = $runElapsedSec
    run_remaining_sec = $runRemainingSec
    run_timeout_near = ($resolvedRunTimeoutSec -gt 0 -and $runElapsedSec -ge [int]($resolvedRunTimeoutSec * 0.85))
    log_path = if ($null -ne $logItem) { $logItem.FullName } else { $LogPath }
    batch_report_path = $BatchReportPath
    batch_report_present = ($null -ne $batchReport)
    mt5_status_path = $Mt5TesterStatusPath
    current_note = $resolvedNote
    active_sandbox = $activeSandbox
}

Write-StatusArtifacts -Status $status -JsonPath $latestJson -MdPath $latestMd
$status
