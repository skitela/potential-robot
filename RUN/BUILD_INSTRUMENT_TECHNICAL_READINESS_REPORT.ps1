param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$QdmMissingOnlyProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_missing_only_profile_latest.json",
    [string]$QdmCustomPilotRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_registry_latest.json",
    [string]$QdmWeakestProfilePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_weakest_profile_latest.json",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$TuningPriorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$Mt5RetestQueuePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_retest_queue_latest.json",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Add-MapEntry {
    param(
        [hashtable]$Map,
        [object]$Item
    )

    if ($null -eq $Item) { return }
    $alias = [string]$Item.symbol_alias
    if ([string]::IsNullOrWhiteSpace($alias)) { return }
    $Map[$alias] = $Item
}

function Get-MapByAlias {
    param([object[]]$Items)

    $map = @{}
    foreach ($item in @($Items)) {
        Add-MapEntry -Map $map -Item $item
    }

    return $map
}

function Get-StatusMap {
    param([object]$ProfitTracking)

    $map = @{}
    if ($null -eq $ProfitTracking) { return $map }

    foreach ($propertyName in @("live_positive", "tester_positive", "near_profit", "runtime_watchlist")) {
        $property = $ProfitTracking.PSObject.Properties[$propertyName]
        if ($null -eq $property) { continue }
        foreach ($entry in @($property.Value)) {
            Add-MapEntry -Map $map -Item $entry
        }
    }

    return $map
}

function Get-QueuePositionMap {
    param([object]$QueueStatus)

    $map = @{}
    if ($null -eq $QueueStatus) { return $map }

    $position = 1
    foreach ($symbol in @($QueueStatus.queue)) {
        $alias = [string]$symbol
        if ([string]::IsNullOrWhiteSpace($alias)) { continue }
        if (-not $map.ContainsKey($alias)) {
            $map[$alias] = $position
        }
        $position++
    }

    return $map
}

function Get-TechnicalReadiness {
    param(
        [bool]$CompiledVerified,
        [string]$QdmHistoryStatus,
        [bool]$QdmCustomPilotReady,
        [object]$PilotExportState
    )

    if (-not $CompiledVerified) {
        return "NOT_READY"
    }

    if ($QdmHistoryStatus -eq "PRESENT" -and $QdmCustomPilotReady) {
        return "FULL_QDM_CUSTOM_READY"
    }

    if (
        $QdmHistoryStatus -eq "PRESENT" -and
        $null -ne $PilotExportState -and
        [string]$PilotExportState.state -eq "EMPTY_EXPORT"
    ) {
        return "QDM_EXPORT_BLOCKED"
    }

    if ($QdmHistoryStatus -eq "PRESENT") {
        return "QDM_HISTORY_READY"
    }

    if ($QdmHistoryStatus -in @("UNSUPPORTED", "MISSING", "BLOCKED")) {
        return "MT5_FALLBACK_ONLY"
    }

    return "COMPILED_ONLY"
}

function Get-QdmPilotExportState {
    param(
        [string]$ProjectRoot,
        [string]$Alias
    )

    $pilotCsvPath = Join-Path $ProjectRoot ("EVIDENCE\QDM_PILOT\MB_{0}_DUKA_M1_PILOT.csv" -f $Alias)
    if (-not (Test-Path -LiteralPath $pilotCsvPath)) {
        return [pscustomobject]@{
            state = "MISSING"
            path = $pilotCsvPath
            length = 0
        }
    }

    $item = Get-Item -LiteralPath $pilotCsvPath
    if ($item.Length -le 0) {
        return [pscustomobject]@{
            state = "EMPTY_EXPORT"
            path = $pilotCsvPath
            length = [int64]$item.Length
        }
    }

    return [pscustomobject]@{
        state = "ROWS_PRESENT"
        path = $pilotCsvPath
        length = [int64]$item.Length
    }
}

function Get-TechnicalBlocker {
    param(
        [string]$Readiness,
        [string]$QdmHistoryStatus,
        [object]$PilotEntry,
        [object]$PilotExportState,
        [object]$MissingEntry,
        [object]$UnsupportedEntry,
        [object]$BlockedEntry
    )

    switch ($Readiness) {
        "FULL_QDM_CUSTOM_READY" { return "" }
        "QDM_EXPORT_BLOCKED" {
            return "QDM export completed but produced an empty MT5 pilot CSV; quarantine custom-symbol path and use MT5/runtime fallback until export anomaly is resolved."
        }
        "QDM_HISTORY_READY" {
            if ($null -ne $PilotExportState -and [string]$PilotExportState.state -eq "EMPTY_EXPORT") {
                return "QDM export completed but produced an empty MT5 pilot CSV; investigate exportToMT5 for this symbol."
            }
            if ($null -ne $PilotEntry -and -not [string]::IsNullOrWhiteSpace([string]$PilotEntry.result_label)) {
                return ("Custom-symbol smoke ended as '{0}'; raise timeout or rerun to fully confirm the path." -f [string]$PilotEntry.result_label)
            }
            return "Custom-symbol smoke has not been completed yet."
        }
        "MT5_FALLBACK_ONLY" {
            switch ($QdmHistoryStatus) {
                "UNSUPPORTED" { return [string]$UnsupportedEntry.reason }
                "MISSING" { return [string]$MissingEntry.reason }
                "BLOCKED" { return [string]$BlockedEntry.reason }
                default { return "QDM history path is not fully ready; keep MT5 fallback." }
            }
        }
        "COMPILED_ONLY" { return "Compiled bot has no confirmed QDM history path yet." }
        default { return "Instrument is not technically ready." }
    }
}

function Get-NextAction {
    param(
        [string]$Alias,
        [string]$Readiness,
        [string]$BusinessStatus,
        [string]$RecommendedAction
    )

    if ($Readiness -eq "FULL_QDM_CUSTOM_READY") {
        switch ($BusinessStatus) {
            "TESTER_POSITIVE" { return "Potwierdzic zwycieski region parametrow i przygotowac paper-live candidate." }
            "NEAR_PROFIT" { return "Kontynuowac optimization lane i zbierac passy dla dodatniego regionu." }
            "LIVE_POSITIVE" { return "Utrzymac runtime, pilnowac ryzyka i zbierac dalsze evidence bez szerokich zmian." }
            default {
                if (-not [string]::IsNullOrWhiteSpace($RecommendedAction)) {
                    return "Pelna sciezka techniczna gotowa; $RecommendedAction."
                }
                return "Pelna sciezka techniczna gotowa; planowac kolejny tester batch."
            }
        }
    }

    if ($Readiness -eq "QDM_HISTORY_READY") {
        return "Dopinac custom-symbol smoke, potem wlaczyc do pelnej sciezki QDM."
    }

    if ($Readiness -eq "QDM_EXPORT_BLOCKED") {
        return "Odsunac od pelnej sciezki QDM custom, zostawic na MT5/runtime fallback albo probation i nie blokowac reszty floty."
    }

    if ($Readiness -eq "MT5_FALLBACK_ONLY") {
        if ($Alias -eq "PLATIN") {
            return "Zostawic na MT5/runtime fallback albo probation; nie blokowac floty przez niedzialajacy QDM mapping."
        }

        return "Pracowac przez MT5 fallback i obnizyc priorytet wobec pelnych sciezek QDM."
    }

    if ($Readiness -eq "COMPILED_ONLY") {
        return "Najpierw domknac dane lub smoke, dopiero potem kierowac do intensywnej nauki."
    }

    return "Wymaga recznego przegladu technicznego."
}

if (-not (Test-Path -LiteralPath $RegistryPath)) {
    throw "Registry not found: $RegistryPath"
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$registry = Read-JsonFile -Path $RegistryPath
$qdmMissingOnlyProfile = Read-JsonFile -Path $QdmMissingOnlyProfilePath
$qdmCustomPilotRegistry = Read-JsonFile -Path $QdmCustomPilotRegistryPath
$qdmWeakestProfile = Read-JsonFile -Path $QdmWeakestProfilePath
$profitTracking = Read-JsonFile -Path $ProfitTrackingPath
$tuningPriority = Read-JsonFile -Path $TuningPriorityPath
$mt5RetestQueue = Read-JsonFile -Path $Mt5RetestQueuePath

$presentMap = Get-MapByAlias -Items @($qdmMissingOnlyProfile.present)
$missingMap = Get-MapByAlias -Items @($qdmMissingOnlyProfile.missing)
$unsupportedMap = Get-MapByAlias -Items @($qdmMissingOnlyProfile.unsupported)
$blockedMap = Get-MapByAlias -Items @($qdmMissingOnlyProfile.blocked)
$pilotMap = Get-MapByAlias -Items @($qdmCustomPilotRegistry.entries)
$weakestIncludedMap = Get-MapByAlias -Items @($qdmWeakestProfile.included)
$weakestSkippedMap = Get-MapByAlias -Items @($qdmWeakestProfile.skipped)
$profitStatusMap = Get-StatusMap -ProfitTracking $profitTracking
$priorityMap = @{}
foreach ($entry in @($tuningPriority.ranked_instruments)) {
    if ($null -eq $entry) { continue }
    $priorityMap[[string]$entry.symbol_alias] = $entry
}
$queuePositionMap = Get-QueuePositionMap -QueueStatus $mt5RetestQueue

$entries = New-Object System.Collections.Generic.List[object]

foreach ($item in @($registry.symbols)) {
    $alias = [string]$item.symbol
    $presentEntry = if ($presentMap.ContainsKey($alias)) { $presentMap[$alias] } else { $null }
    $missingEntry = if ($missingMap.ContainsKey($alias)) { $missingMap[$alias] } else { $null }
    $unsupportedEntry = if ($unsupportedMap.ContainsKey($alias)) { $unsupportedMap[$alias] } else { $null }
    $blockedEntry = if ($blockedMap.ContainsKey($alias)) { $blockedMap[$alias] } else { $null }
    $pilotEntry = if ($pilotMap.ContainsKey($alias)) { $pilotMap[$alias] } else { $null }
    $weakestIncludedEntry = if ($weakestIncludedMap.ContainsKey($alias)) { $weakestIncludedMap[$alias] } else { $null }
    $weakestSkippedEntry = if ($weakestSkippedMap.ContainsKey($alias)) { $weakestSkippedMap[$alias] } else { $null }
    $profitEntry = if ($profitStatusMap.ContainsKey($alias)) { $profitStatusMap[$alias] } else { $null }
    $priorityEntry = if ($priorityMap.ContainsKey($alias)) { $priorityMap[$alias] } else { $null }

    $compiledVerified = ([string]$item.status -eq "compiled_verified")
    $pilotExportState = Get-QdmPilotExportState -ProjectRoot $ProjectRoot -Alias $alias

    $qdmHistoryStatus = "UNKNOWN"
    $qdmSymbol = ""
    if ($null -ne $presentEntry) {
        $qdmHistoryStatus = "PRESENT"
        $qdmSymbol = [string]$presentEntry.qdm_symbol
    }
    elseif ($null -ne $missingEntry) {
        $qdmHistoryStatus = "MISSING"
        $qdmSymbol = [string]$missingEntry.qdm_symbol
    }
    elseif ($null -ne $unsupportedEntry) {
        $qdmHistoryStatus = "UNSUPPORTED"
    }
    elseif ($null -ne $blockedEntry) {
        $qdmHistoryStatus = "BLOCKED"
        $qdmSymbol = [string]$blockedEntry.qdm_symbol
    }

    $qdmCustomPilotReady = (
        $null -ne $pilotEntry -and
        ([string]$pilotEntry.result_label -in @("successfully_finished", "timed_out"))
    )
    $qdmCustomSymbol = if ($null -ne $pilotEntry) { [string]$pilotEntry.custom_symbol } else { "" }

    $technicalReadiness = Get-TechnicalReadiness -CompiledVerified $compiledVerified -QdmHistoryStatus $qdmHistoryStatus -QdmCustomPilotReady $qdmCustomPilotReady -PilotExportState $pilotExportState
    $businessStatus = if ($null -ne $profitEntry -and -not [string]::IsNullOrWhiteSpace([string]$profitEntry.status)) { [string]$profitEntry.status } else { "NEGATIVE" }
    $technicalBlocker = Get-TechnicalBlocker -Readiness $technicalReadiness -QdmHistoryStatus $qdmHistoryStatus -PilotEntry $pilotEntry -PilotExportState $pilotExportState -MissingEntry $missingEntry -UnsupportedEntry $unsupportedEntry -BlockedEntry $blockedEntry
    $recommendedAction = if ($null -ne $profitEntry) { [string]$profitEntry.recommended_action } else { "" }
    $nextAction = Get-NextAction -Alias $alias -Readiness $technicalReadiness -BusinessStatus $businessStatus -RecommendedAction $recommendedAction

    $qdmResearchPackStatus = if ($null -ne $weakestIncludedEntry) {
        "INCLUDED"
    }
    elseif ($null -ne $weakestSkippedEntry) {
        "SKIPPED"
    }
    else {
        "NOT_LISTED"
    }

    $queuePosition = if ($queuePositionMap.ContainsKey($alias)) { [int]$queuePositionMap[$alias] } else { 0 }

    $entries.Add([pscustomobject]@{
        symbol_alias = $alias
        broker_symbol = [string]$item.broker_symbol
        expert = [string]$item.expert
        session_profile = [string]$item.session_profile
        chart_tf = [string]$item.chart_tf
        compiled_verified = $compiledVerified
        qdm_history_status = $qdmHistoryStatus
        qdm_symbol = $qdmSymbol
        qdm_custom_pilot_ready = $qdmCustomPilotReady
        qdm_custom_symbol = $qdmCustomSymbol
        qdm_pilot_result = if ($null -ne $pilotEntry) { [string]$pilotEntry.result_label } else { "" }
        qdm_pilot_row_count = if ($null -ne $pilotEntry) { [int]$pilotEntry.pilot_row_count } else { 0 }
        qdm_pilot_export_state = [string]$pilotExportState.state
        qdm_research_pack_status = $qdmResearchPackStatus
        qdm_research_pack_reason = if ($null -ne $weakestSkippedEntry) { [string]$weakestSkippedEntry.reason } else { "" }
        technical_readiness = $technicalReadiness
        business_status = $businessStatus
        best_tester_pnl = if ($null -ne $profitEntry) { [double]$profitEntry.best_tester_pnl } else { 0.0 }
        priority_rank = if ($null -ne $priorityEntry) { [int]$priorityEntry.rank } else { 999 }
        priority_score = if ($null -ne $priorityEntry) { [double]$priorityEntry.priority_score } else { 0.0 }
        priority_band = if ($null -ne $priorityEntry) { [string]$priorityEntry.priority_band } else { "UNKNOWN" }
        trust_state = if ($null -ne $priorityEntry) { [string]$priorityEntry.trust_state } else { "" }
        cost_state = if ($null -ne $priorityEntry) { [string]$priorityEntry.cost_state } else { "" }
        learning_sample_count = if ($null -ne $priorityEntry) { [int]$priorityEntry.learning_sample_count } else { 0 }
        spread_points = if ($null -ne $priorityEntry) { [double]$priorityEntry.spread_points } else { 0.0 }
        main_tester_queue_position = $queuePosition
        technical_blocker = $technicalBlocker
        next_action = $nextAction
        ready_for_further_tests = ($technicalReadiness -ne "NOT_READY")
    })
}

$entryArray = @($entries.ToArray())
$fullQdmCustomReady = @($entryArray | Where-Object { $_.technical_readiness -eq "FULL_QDM_CUSTOM_READY" } | Sort-Object priority_rank, symbol_alias)
$qdmExportBlocked = @($entryArray | Where-Object { $_.technical_readiness -eq "QDM_EXPORT_BLOCKED" } | Sort-Object priority_rank, symbol_alias)
$qdmHistoryReady = @($entryArray | Where-Object { $_.technical_readiness -eq "QDM_HISTORY_READY" } | Sort-Object priority_rank, symbol_alias)
$fallbackOnly = @($entryArray | Where-Object { $_.technical_readiness -eq "MT5_FALLBACK_ONLY" } | Sort-Object priority_rank, symbol_alias)
$compiledOnly = @($entryArray | Where-Object { $_.technical_readiness -eq "COMPILED_ONLY" } | Sort-Object priority_rank, symbol_alias)
$notReady = @($entryArray | Where-Object { $_.technical_readiness -eq "NOT_READY" } | Sort-Object priority_rank, symbol_alias)

$report = [ordered]@{
    schema_version = "1.0"
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    registry_path = $RegistryPath
    qdm_missing_only_profile_path = $QdmMissingOnlyProfilePath
    qdm_custom_symbol_pilot_registry_path = $QdmCustomPilotRegistryPath
    profit_tracking_path = $ProfitTrackingPath
    tuning_priority_path = $TuningPriorityPath
    mt5_retest_queue_path = $Mt5RetestQueuePath
    summary = [ordered]@{
        total_symbols = $entryArray.Count
        compiled_verified_count = @($entryArray | Where-Object { $_.compiled_verified }).Count
        full_qdm_custom_ready_count = $fullQdmCustomReady.Count
        qdm_export_blocked_count = $qdmExportBlocked.Count
        qdm_history_ready_count = $qdmHistoryReady.Count
        fallback_only_count = $fallbackOnly.Count
        compiled_only_count = $compiledOnly.Count
        not_ready_count = $notReady.Count
        tester_positive_count = @($entryArray | Where-Object { $_.business_status -eq "TESTER_POSITIVE" }).Count
        near_profit_count = @($entryArray | Where-Object { $_.business_status -eq "NEAR_PROFIT" }).Count
        live_positive_count = @($entryArray | Where-Object { $_.business_status -eq "LIVE_POSITIVE" }).Count
    }
    full_qdm_custom_ready = $fullQdmCustomReady
    qdm_export_blocked = $qdmExportBlocked
    qdm_history_ready = $qdmHistoryReady
    fallback_only = $fallbackOnly
    compiled_only = $compiledOnly
    not_ready = $notReady
    entries = $entryArray
}

$jsonLatest = Join-Path $EvidenceDir "instrument_technical_readiness_latest.json"
$mdLatest = Join-Path $EvidenceDir "instrument_technical_readiness_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("instrument_technical_readiness_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("instrument_technical_readiness_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Instrument Technical Readiness Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- total_symbols: {0}" -f $report.summary.total_symbols))
$lines.Add(("- compiled_verified_count: {0}" -f $report.summary.compiled_verified_count))
$lines.Add(("- full_qdm_custom_ready_count: {0}" -f $report.summary.full_qdm_custom_ready_count))
$lines.Add(("- qdm_export_blocked_count: {0}" -f $report.summary.qdm_export_blocked_count))
$lines.Add(("- qdm_history_ready_count: {0}" -f $report.summary.qdm_history_ready_count))
$lines.Add(("- fallback_only_count: {0}" -f $report.summary.fallback_only_count))
$lines.Add(("- tester_positive_count: {0}" -f $report.summary.tester_positive_count))
$lines.Add(("- near_profit_count: {0}" -f $report.summary.near_profit_count))
$lines.Add(("- live_positive_count: {0}" -f $report.summary.live_positive_count))
$lines.Add("")

$sections = @(
    @{ title = "Full QDM Custom Ready"; items = $fullQdmCustomReady },
    @{ title = "QDM Export Blocked"; items = $qdmExportBlocked },
    @{ title = "QDM History Ready"; items = $qdmHistoryReady },
    @{ title = "Fallback Only"; items = $fallbackOnly },
    @{ title = "Compiled Only"; items = $compiledOnly },
    @{ title = "Not Ready"; items = $notReady }
)

foreach ($section in $sections) {
    $lines.Add(("## {0}" -f $section.title))
    $lines.Add("")
    if (@($section.items).Count -eq 0) {
        $lines.Add("- none")
    }
    else {
        foreach ($entry in @($section.items)) {
            $lines.Add(("- {0}: business={1}, priority_rank={2}, queue_pos={3}, qdm={4}, pilot={5}, blocker={6}, next={7}" -f
                $entry.symbol_alias,
                $entry.business_status,
                $entry.priority_rank,
                $entry.main_tester_queue_position,
                $(if ([string]::IsNullOrWhiteSpace($entry.qdm_symbol)) { "-" } else { $entry.qdm_symbol }),
                $(if ($entry.qdm_custom_pilot_ready) { $entry.qdm_custom_symbol } else { "none" }),
                $(if ([string]::IsNullOrWhiteSpace($entry.technical_blocker)) { "none" } else { $entry.technical_blocker }),
                $entry.next_action))
        }
    }
    $lines.Add("")
}

$lines.Add("## Per Instrument")
$lines.Add("")
foreach ($entry in @($entryArray | Sort-Object priority_rank, symbol_alias)) {
    $lines.Add(("- {0}: readiness={1}, business={2}, qdm_status={3}, qdm_symbol={4}, pilot_ready={5}, queue_pos={6}, blocker={7}" -f
        $entry.symbol_alias,
        $entry.technical_readiness,
        $entry.business_status,
        $entry.qdm_history_status,
        $(if ([string]::IsNullOrWhiteSpace($entry.qdm_symbol)) { "-" } else { $entry.qdm_symbol }),
        $entry.qdm_custom_pilot_ready,
        $entry.main_tester_queue_position,
        $(if ([string]::IsNullOrWhiteSpace($entry.technical_blocker)) { "none" } else { $entry.technical_blocker })))
    $lines.Add(("  next_action: {0}" -f $entry.next_action))
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8
