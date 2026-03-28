param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [int]$IntervalMinutes = 20,
    [int]$EndHourLocal = 8,
    [int]$FreshTickThresholdSec = 180,
    [int]$RestartCooldownSec = 1800,
    [int]$MaxCycles = 0,
    [switch]$NoRepair
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$helperPath = Join-Path $ProjectRoot "TOOLS\REGISTRY_SYMBOL_HELPERS.ps1"
. $helperPath

function Read-JsonOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return $null
    }
}

function Read-KeyValueTsv {
    param([string]$Path)
    $map = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $map }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2 -and -not [string]::IsNullOrWhiteSpace($parts[0])) {
            $map[$parts[0]] = $parts[1]
        }
    }
    return $map
}

function Get-UnixNow {
    return [int]((Get-Date) - [datetime]'1970-01-01').TotalSeconds
}

function Get-LocalNow {
    return [DateTime]::Now
}

function Get-ExpectedFeedState {
    param(
        [string]$Symbol,
        [DateTime]$LocalNow
    )

    if ($Symbol -eq "DE30") {
        return [pscustomobject]@{
            state = "CLOSED_EXPECTED"
            reason = "DE30 poza nocnym monitoringiem feedu do 08:00"
        }
    }

    $day = $LocalNow.DayOfWeek
    $time = $LocalNow.TimeOfDay
    $open2301 = @("COPPER-US", "US500")
    $open2305 = @("AUDUSD","EURUSD","GBPUSD","USDJPY","USDCAD","USDCHF","EURJPY","EURAUD","GOLD","SILVER")

    if ($day -eq [System.DayOfWeek]::Sunday) {
        if ($open2301 -contains $Symbol) {
            if ($time -ge ([TimeSpan]::FromHours(23) + [TimeSpan]::FromMinutes(1))) {
                return [pscustomobject]@{ state = "OPEN_EXPECTED"; reason = "Niedzielny reopen 23:01" }
            }
            return [pscustomobject]@{ state = "CLOSED_EXPECTED"; reason = "Przed reopen 23:01" }
        }
        if ($open2305 -contains $Symbol) {
            if ($time -ge ([TimeSpan]::FromHours(23) + [TimeSpan]::FromMinutes(5))) {
                return [pscustomobject]@{ state = "OPEN_EXPECTED"; reason = "Niedzielny reopen 23:05" }
            }
            return [pscustomobject]@{ state = "CLOSED_EXPECTED"; reason = "Przed reopen 23:05" }
        }
    }

    if ($day -eq [System.DayOfWeek]::Monday -and $LocalNow.Hour -lt $EndHourLocal) {
        return [pscustomobject]@{ state = "OPEN_EXPECTED"; reason = "Poniedzialkowy feed nocny" }
    }

    return [pscustomobject]@{ state = "UNKNOWN"; reason = "Poza zakresem nocnego nadzoru" }
}

function Get-LineCount {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(Get-Content -LiteralPath $Path -Encoding UTF8).Count
}

function Get-RecentCycles {
    param(
        [string]$JournalPath,
        [int]$Count = 4
    )

    if (-not (Test-Path -LiteralPath $JournalPath)) { return @() }
    $lines = @(Get-Content -LiteralPath $JournalPath -Encoding UTF8 | Select-Object -Last $Count)
    $items = @()
    foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $items += ($line | ConvertFrom-Json)
        } catch {
        }
    }
    return $items
}

function Build-ScreenText {
    param(
        [hashtable]$Payload,
        [object[]]$RecentCycles,
        [DateTime]$TargetEndLocal,
        [int]$IntervalMinutes
    )

    $snapshots = @($Payload.snapshots)
    $nowText = [string]$Payload.ts_local
    $activeTuning = @($Payload.active_tuning_symbols)
    $latencyAlerts = @($Payload.latency_alert_symbols)
    $openExpected = @($snapshots | Where-Object { $_.expected_feed_state -eq "OPEN_EXPECTED" })
    $closedExpected = @($snapshots | Where-Object { $_.expected_feed_state -eq "CLOSED_EXPECTED" })
    $topTuning = @($snapshots | Sort-Object tuning_actions_delta, candidate_signals_delta -Descending | Select-Object -First 8)

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("NOCNY SUPERVISOR STROJENIA I LATENCJI")
    $lines.Add(("teraz={0} | koniec={1} | interwal={2} min" -f $nowText, $TargetEndLocal.ToString("yyyy-MM-dd HH:mm:ss"), $IntervalMinutes))
    $lines.Add(("status={0} | watchdog={1} | repair_action={2}" -f $Payload.status, $Payload.watchdog_status, $Payload.repair_action))
    $lines.Add(("open_expected={0} | open_stale={1} | closed_expected={2}" -f @($openExpected).Count, $Payload.open_stale_count, @($closedExpected).Count))
    $lines.Add(("aktywnie_stroi={0} | alerty_latencji={1}" -f @($activeTuning).Count, @($latencyAlerts).Count))
    $lines.Add("")
    $lines.Add("BIEZACY CYKL")
    foreach ($row in $topTuning) {
        $lines.Add(("{0,-10} | health={1,-24} | tick_age={2,4}s | cand+={3,4} | tune+={4,3} | rev={5,2} | trust={6}" -f
                $row.symbol, $row.health, $(if ($null -ne $row.tick_age_sec) { $row.tick_age_sec } else { -1 }),
                $row.candidate_signals_delta, $row.tuning_actions_delta, $row.tuning_revision, $row.tuning_trust_reason))
    }
    if (@($latencyAlerts).Count -gt 0) {
        $lines.Add("")
        $lines.Add("ALERTY LATENCJI")
        foreach ($symbol in $latencyAlerts) {
            $row = $snapshots | Where-Object { $_.symbol -eq $symbol } | Select-Object -First 1
            if ($row) {
                $lines.Add(("{0,-10} | avg={1}us | max={2}us | last={3}us" -f $row.symbol, $row.latency_avg_us, $row.latency_max_us, $row.latency_last_us))
            }
        }
    }
    $lines.Add("")
    $lines.Add("OSTATNIE CYKLE")
    foreach ($cycle in @($RecentCycles)) {
        $lines.Add(("{0} | status={1} | open_stale={2} | tuning={3}" -f
                [string]$cycle.ts_local,
                [string]$cycle.status,
                [int]$cycle.open_stale_count,
                @($cycle.active_tuning_symbols).Count))
    }
    return ($lines -join [Environment]::NewLine)
}

function Build-OperatorTableText {
    param(
        [hashtable]$Payload
    )

    $snapshots = @($Payload.snapshots)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("KROTKA TABELA OPERATORSKA")
    $lines.Add(("stan={0} | czas={1}" -f $Payload.status, $Payload.ts_local))
    $lines.Add("symbol     | sesja            | health        | tick | spr | W/L   | prb | lat us      | rev | trust | ostatnia zmiana")
    $lines.Add("-----------+------------------+---------------+------+-----+-------+-----+-------------+-----+-------+----------------")

    foreach ($row in ($snapshots | Sort-Object session_profile, symbol)) {
        $winsLosses = ("{0}/{1}" -f $row.learning_wins, $row.learning_losses)
        $latency = ("{0}/{1}" -f $row.latency_last_us, $row.latency_max_us)
        $tickAge = if ($null -ne $row.tick_age_sec) { [string]$row.tick_age_sec } else { "-" }
        $trust = if ([string]::IsNullOrWhiteSpace([string]$row.tuning_trust_reason)) { "-" } else { [string]$row.tuning_trust_reason }
        $action = if ([string]::IsNullOrWhiteSpace([string]$row.tuning_last_action_code)) { "-" } else { [string]$row.tuning_last_action_code }
        $lines.Add(("{0,-10} | {1,-16} | {2,-13} | {3,4}s | {4,3} | {5,-5} | {6,3} | {7,-11} | {8,3} | {9,-5} | {10}" -f
                $row.symbol,
                $row.session_profile,
                $row.health,
                $tickAge,
                $row.spread_points,
                $winsLosses,
                $row.learning_sample_count,
                $latency,
                $row.tuning_revision,
                $(if ($row.tuning_trusted -eq 1) { "TAK" } else { "NIE" }),
                $action))
    }

    return ($lines -join [Environment]::NewLine)
}

function Get-SymbolSnapshot {
    param(
        [string]$Symbol,
        [string]$SessionProfile,
        [string]$CommonRoot,
        [hashtable]$PreviousCounts,
        [int]$FreshTickThresholdSec,
        [DateTime]$LocalNow
    )

    $stateDir = Join-Path $CommonRoot ("state\{0}" -f $Symbol)
    $logDir = Join-Path $CommonRoot ("logs\{0}" -f $Symbol)
    $runtimeState = Read-KeyValueTsv -Path (Join-Path $stateDir "runtime_state.csv")
    $tuningPolicy = Read-KeyValueTsv -Path (Join-Path $stateDir "tuning_policy.csv")
    $executionSummary = Read-JsonOrNull -Path (Join-Path $stateDir "execution_summary.json")

    $candidatePath = Join-Path $logDir "candidate_signals.csv"
    $decisionPath = Join-Path $logDir "decision_events.csv"
    $actionsPath = Join-Path $logDir "tuning_actions.csv"

    $candidateCount = Get-LineCount -Path $candidatePath
    $decisionCount = Get-LineCount -Path $decisionPath
    $actionCount = Get-LineCount -Path $actionsPath

    $prevCandidate = 0
    $prevDecision = 0
    $prevAction = 0
    if ($PreviousCounts.ContainsKey($Symbol)) {
        $prevCandidate = [int]$PreviousCounts[$Symbol].candidate_signals
        $prevDecision = [int]$PreviousCounts[$Symbol].decision_events
        $prevAction = [int]$PreviousCounts[$Symbol].tuning_actions
    }

    $nowUnix = Get-UnixNow
    $lastTickAt = if ($runtimeState.ContainsKey("last_tick_at") -and [string]$runtimeState["last_tick_at"] -match '^\d+$') { [int64]$runtimeState["last_tick_at"] } else { 0 }
    $tickAgeSec = if ($lastTickAt -gt 0) { [int]($nowUnix - $lastTickAt) } else { $null }
    $freshTick = ($null -ne $tickAgeSec -and $tickAgeSec -ge 0 -and $tickAgeSec -le $FreshTickThresholdSec)

    $expected = Get-ExpectedFeedState -Symbol $Symbol -LocalNow $LocalNow
    $health = "OK"
    if ($expected.state -eq "CLOSED_EXPECTED") {
        $health = "MARKET_CLOSED_EXPECTED"
    } elseif ($expected.state -eq "OPEN_EXPECTED" -and -not $freshTick) {
        $health = "OPEN_BUT_NO_FRESH_TICK"
    }

    $latencyAvgUs = if ($executionSummary -and $null -ne $executionSummary.local_latency_us_avg) { [int]$executionSummary.local_latency_us_avg } else { 0 }
    $latencyMaxUs = if ($executionSummary -and $null -ne $executionSummary.local_latency_us_max) { [int]$executionSummary.local_latency_us_max } else { 0 }
    $latencyLastUs = if ($executionSummary -and $null -ne $executionSummary.last_local_latency_us) { [int]$executionSummary.last_local_latency_us } else { 0 }

    return [pscustomobject]@{
        symbol = $Symbol
        session_profile = $SessionProfile
        expected_feed_state = $expected.state
        expected_feed_reason = $expected.reason
        health = $health
        runtime_status = if ($runtimeState.ContainsKey("runtime_status")) { [string]$runtimeState["runtime_status"] } else { "" }
        last_tick_at = $lastTickAt
        tick_age_sec = $tickAgeSec
        fresh_tick = [bool]$freshTick
        ticks_seen = if ($runtimeState.ContainsKey("ticks_seen")) { [int64]$runtimeState["ticks_seen"] } else { 0 }
        spread_points = if ($executionSummary -and $null -ne $executionSummary.spread_points) { [int]$executionSummary.spread_points } elseif ($runtimeState.ContainsKey("spread_points")) { [int]$runtimeState["spread_points"] } else { 0 }
        learning_wins = if ($executionSummary -and $null -ne $executionSummary.learning_win_count) { [int64]$executionSummary.learning_win_count } elseif ($runtimeState.ContainsKey("learning_win_count")) { [int64]$runtimeState["learning_win_count"] } else { 0 }
        learning_losses = if ($executionSummary -and $null -ne $executionSummary.learning_loss_count) { [int64]$executionSummary.learning_loss_count } elseif ($runtimeState.ContainsKey("learning_loss_count")) { [int64]$runtimeState["learning_loss_count"] } else { 0 }
        learning_sample_count = if ($runtimeState.ContainsKey("learning_sample_count")) { [int64]$runtimeState["learning_sample_count"] } else { 0 }
        last_eval_at = if ($tuningPolicy.ContainsKey("last_eval_at")) { [int64]$tuningPolicy["last_eval_at"] } else { 0 }
        last_action_at = if ($tuningPolicy.ContainsKey("last_action_at")) { [int64]$tuningPolicy["last_action_at"] } else { 0 }
        tuning_revision = if ($tuningPolicy.ContainsKey("revision")) { [int]$tuningPolicy["revision"] } else { 0 }
        tuning_trusted = if ($tuningPolicy.ContainsKey("trusted_data")) { [int]$tuningPolicy["trusted_data"] } else { 0 }
        tuning_trust_reason = if ($tuningPolicy.ContainsKey("trust_reason")) { [string]$tuningPolicy["trust_reason"] } else { "" }
        tuning_last_action_code = if ($tuningPolicy.ContainsKey("last_action_code")) { [string]$tuningPolicy["last_action_code"] } else { "" }
        latency_avg_us = $latencyAvgUs
        latency_max_us = $latencyMaxUs
        latency_last_us = $latencyLastUs
        candidate_signals_count = $candidateCount
        candidate_signals_delta = ($candidateCount - $prevCandidate)
        decision_events_count = $decisionCount
        decision_events_delta = ($decisionCount - $prevDecision)
        tuning_actions_count = $actionCount
        tuning_actions_delta = ($actionCount - $prevAction)
    }
}

function Resolve-StateKey {
    param(
        [object]$RegistryItem,
        [string]$CommonRoot
    )

    foreach ($candidate in @(Get-RegistrySymbolCandidates -RegistryItem $RegistryItem)) {
        if (Test-Path -LiteralPath (Join-Path $CommonRoot ("state\{0}" -f $candidate))) {
            return $candidate
        }
    }

    $candidates = @(Get-RegistrySymbolCandidates -RegistryItem $RegistryItem)
    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }
    return ""
}

$registryPath = Join-Path $ProjectRoot "CONFIG\microbots_registry.json"
$registry = Read-JsonOrNull -Path $registryPath
if ($null -eq $registry) {
    throw "Brak rejestru mikro-botow: $registryPath"
}

$runDir = Join-Path $ProjectRoot "RUN"
$evidenceDir = Join-Path $ProjectRoot "EVIDENCE"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$statePath = Join-Path $runDir "overnight_tuning_supervisor_state.json"
$statusPath = Join-Path $evidenceDir "overnight_tuning_supervisor_status.json"
$screenPath = Join-Path $evidenceDir "overnight_tuning_supervisor_screen.txt"
$operatorTablePath = Join-Path $evidenceDir "overnight_tuning_supervisor_operator_table.txt"
$dateTag = (Get-LocalNow).ToString("yyyyMMdd_HHmmss")
$journalPath = Join-Path $evidenceDir ("overnight_tuning_supervisor_{0}.jsonl" -f $dateTag)
$scriptStartLocal = Get-LocalNow
$targetEndLocal = Get-Date -Year $scriptStartLocal.Year -Month $scriptStartLocal.Month -Day $scriptStartLocal.Day -Hour $EndHourLocal -Minute 0 -Second 0
if ($scriptStartLocal -ge $targetEndLocal) {
    $targetEndLocal = $targetEndLocal.AddDays(1)
}

$previousState = Read-JsonOrNull -Path $statePath
$previousCounts = @{}
if ($previousState -and $previousState.symbol_counts) {
    foreach ($entry in @($previousState.symbol_counts.PSObject.Properties)) {
        $previousCounts[$entry.Name] = @{
            candidate_signals = [int]$entry.Value.candidate_signals
            decision_events = [int]$entry.Value.decision_events
            tuning_actions = [int]$entry.Value.tuning_actions
        }
    }
}

$cycle = 0
while ($true) {
    $localNow = Get-LocalNow
    if ($localNow -ge $targetEndLocal) {
        break
    }
    if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
        break
    }
    $cycle++

    $watchdogPayload = $null
    try {
        $watchdogRaw = & (Join-Path $ProjectRoot "TOOLS\RUN_RUNTIME_WATCHDOG_PL.ps1") -ProjectRoot $ProjectRoot
        $watchdogPayload = $watchdogRaw | ConvertFrom-Json
    } catch {
        $watchdogPayload = [pscustomobject]@{
            status = "WATCHDOG_ERROR"
            repair_needed = $true
            repair_action = "WATCHDOG_EXCEPTION"
            repair_error = $_.Exception.Message
        }
    }

    $snapshots = @()
    foreach ($item in @($registry.symbols)) {
        $symbolKey = Resolve-StateKey -RegistryItem $item -CommonRoot $CommonRoot
        $snapshots += Get-SymbolSnapshot -Symbol $symbolKey -SessionProfile ([string]$item.session_profile) -CommonRoot $CommonRoot -PreviousCounts $previousCounts -FreshTickThresholdSec $FreshTickThresholdSec -LocalNow $localNow
    }

    $openExpected = @($snapshots | Where-Object { $_.expected_feed_state -eq "OPEN_EXPECTED" })
    $openStale = @($openExpected | Where-Object { -not $_.fresh_tick })
    $activeTuning = @($snapshots | Where-Object { $_.tuning_actions_delta -gt 0 -or $_.candidate_signals_delta -gt 0 })
    $latencyAlerts = @($snapshots | Where-Object { $_.latency_max_us -ge 5000 -or $_.latency_last_us -ge 5000 })
    $activeTuningSymbols = @($activeTuning | ForEach-Object { $_.symbol })
    $latencyAlertSymbols = @($latencyAlerts | ForEach-Object { $_.symbol })

    $repairAction = "NONE"
    $repairError = ""
    $repairPerformed = $false

    $repairCooldownUntil = $null
    if ($previousState -and $previousState.repair_cooldown_until_utc) {
        try { $repairCooldownUntil = [DateTime]::Parse([string]$previousState.repair_cooldown_until_utc).ToUniversalTime() } catch { $repairCooldownUntil = $null }
    }

    $cooldownActive = ($null -ne $repairCooldownUntil -and [DateTime]::UtcNow -lt $repairCooldownUntil)
    $majorFeedFailure = (@($openExpected).Count -gt 0 -and @($openStale).Count -eq @($openExpected).Count)

    if (-not $NoRepair -and $majorFeedFailure -and -not $cooldownActive) {
        try {
            & (Join-Path $ProjectRoot "RUN\OPEN_OANDA_MT5_WITH_MICROBOTS.ps1") | Out-Null
            $repairPerformed = $true
            $repairAction = "RESTART_MT5_FEED_RECOVERY"
            $repairCooldownUntil = [DateTime]::UtcNow.AddSeconds($RestartCooldownSec)
        } catch {
            $repairAction = "RESTART_MT5_FEED_RECOVERY_FAILED"
            $repairError = $_.Exception.Message
        }
    } elseif ($majorFeedFailure -and $cooldownActive) {
        $repairAction = "COOLDOWN_ACTIVE"
    }

    $symbolCounts = @{}
    foreach ($row in $snapshots) {
        $symbolCounts[$row.symbol] = @{
            candidate_signals = [int]$row.candidate_signals_count
            decision_events = [int]$row.decision_events_count
            tuning_actions = [int]$row.tuning_actions_count
        }
    }

    $payload = [ordered]@{
        schema_version = "1.0"
        ts_local = $localNow.ToString("yyyy-MM-dd HH:mm:ss zzz")
        ts_utc = [DateTime]::UtcNow.ToString("o")
        status = if ($majorFeedFailure) { "FEED_ALERT" } elseif (@($latencyAlerts).Count -gt 0) { "LATENCY_ALERT" } else { "OK" }
        watchdog_status = if ($watchdogPayload) { [string]$watchdogPayload.status } else { "" }
        watchdog_repair_needed = if ($watchdogPayload -and $watchdogPayload.PSObject.Properties["repair_needed"]) { [bool]$watchdogPayload.repair_needed } else { $false }
        repair_action = $repairAction
        repair_performed = [bool]$repairPerformed
        repair_error = $repairError
        open_expected_count = @($openExpected).Count
        open_stale_count = @($openStale).Count
        active_tuning_symbols = $activeTuningSymbols
        latency_alert_symbols = $latencyAlertSymbols
        snapshots = @($snapshots)
    }

    ($payload | ConvertTo-Json -Depth 7 -Compress) | Add-Content -LiteralPath $journalPath -Encoding UTF8
    $payload | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath $statusPath -Encoding UTF8

    $recentCycles = Get-RecentCycles -JournalPath $journalPath -Count 4
    $screenText = Build-ScreenText -Payload $payload -RecentCycles $recentCycles -TargetEndLocal $targetEndLocal -IntervalMinutes $IntervalMinutes
    $operatorTableText = Build-OperatorTableText -Payload $payload
    $combinedScreenText = $screenText + [Environment]::NewLine + [Environment]::NewLine + $operatorTableText
    $combinedScreenText | Set-Content -LiteralPath $screenPath -Encoding UTF8
    $operatorTableText | Set-Content -LiteralPath $operatorTablePath -Encoding UTF8
    Clear-Host
    Write-Host $screenText
    Write-Host ""
    Write-Host $operatorTableText

    $statePayload = [ordered]@{
        schema_version = "1.0"
        ts_utc = [DateTime]::UtcNow.ToString("o")
        repair_cooldown_until_utc = if ($repairCooldownUntil) { $repairCooldownUntil.ToString("o") } else { "" }
        journal_path = $journalPath
        screen_path = $screenPath
        operator_table_path = $operatorTablePath
        symbol_counts = $symbolCounts
    }
    $statePayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statePath -Encoding UTF8
    $previousState = $statePayload
    $previousCounts = $symbolCounts

    if ($MaxCycles -gt 0 -and $cycle -ge $MaxCycles) {
        break
    }
    Start-Sleep -Seconds ($IntervalMinutes * 60)
}
