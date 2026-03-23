param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RegistryPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\microbots_registry.json",
    [string]$PriorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$MlHintsPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\ml_tuning_hints_latest.json",
    [string]$PaperLiveFeedbackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json",
    [string]$SessionMatrixPath = "C:\MAKRO_I_MIKRO_BOT\CONFIG\session_window_matrix_v1.json",
    [string]$QdmProfileBuilderPath = "C:\MAKRO_I_MIKRO_BOT\RUN\BUILD_QDM_WEAKEST_PROFILE.ps1",
    [string]$QdmPackPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_weakest_pack_latest.csv",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$SlotMinutes = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

foreach ($path in @($RegistryPath, $PriorityPath, $SessionMatrixPath, $QdmProfileBuilderPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required file not found: $path"
    }
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $QdmPackPath) | Out-Null

function Resolve-ResearchGroup {
    param([string]$SessionProfile)

    switch ($SessionProfile) {
        "FX_ASIA" { return "FX_ASIA" }
        "FX_MAIN" { return "FX_AM" }
        "FX_CROSS" { return "FX_AM" }
        "METALS_SPOT_PM" { return "METALS" }
        "METALS_FUTURES" { return "METALS" }
        "INDEX_EU" { return "INDEX_EU" }
        "INDEX_US" { return "INDEX_US" }
        default { return "UNMAPPED" }
    }
}

function Convert-HhMmToMinutes {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    $parts = $Value.Trim().Split(':')
    if ($parts.Count -ne 2) {
        return $null
    }

    return ([int]$parts[0] * 60 + [int]$parts[1])
}

function Convert-MinutesToHhMm {
    param([int]$TotalMinutes)

    $normalized = $TotalMinutes % (24 * 60)
    if ($normalized -lt 0) {
        $normalized += 24 * 60
    }

    $hours = [int][math]::Floor($normalized / 60)
    $minutes = [int]($normalized % 60)
    return ("{0:D2}:{1:D2}" -f $hours, $minutes)
}

function Get-TradeWindows {
    param(
        [object]$SessionMatrix,
        [string]$GroupName
    )

    $group = @($SessionMatrix.groups | Where-Object { [string]$_.group -eq $GroupName } | Select-Object -First 1)
    if ($group.Count -eq 0) {
        return @()
    }

    $windows = New-Object System.Collections.Generic.List[object]
    foreach ($window in @($group[0].operator_windows_pl)) {
        if ([string]$window.mode -ne "TRADE") {
            continue
        }

        $primaryLabel = if ($window.PSObject.Properties.Name -contains "pl") {
            [string]$window.pl
        }
        else {
            [string]$window.winter_pl
        }

        if ([string]::IsNullOrWhiteSpace($primaryLabel) -or $primaryLabel -notmatch '^\d{2}:\d{2}-\d{2}:\d{2}$') {
            continue
        }

        $rangeParts = $primaryLabel.Split('-')
        $startMinutes = Convert-HhMmToMinutes -Value $rangeParts[0]
        $endMinutes = Convert-HhMmToMinutes -Value $rangeParts[1]
        if ($null -eq $startMinutes -or $null -eq $endMinutes) {
            continue
        }

        if ($endMinutes -le $startMinutes) {
            $endMinutes += (24 * 60)
        }

        $windows.Add([pscustomobject]@{
            window_id = [string]$window.window_id
            primary_label = $primaryLabel
            summer_label = if ($window.PSObject.Properties.Name -contains "summer_pl") { [string]$window.summer_pl } else { "" }
            start_minutes = $startMinutes
            end_minutes = $endMinutes
            duration_minutes = ($endMinutes - $startMinutes)
        })
    }

    return @($windows | Sort-Object start_minutes)
}

function New-SequentialSlots {
    param(
        [object[]]$Windows,
        [int]$Count,
        [int]$SlotMinutes
    )

    if ($Count -le 0) {
        return @()
    }

    $slots = New-Object System.Collections.Generic.List[object]
    if ($Windows.Count -eq 0) {
        for ($i = 0; $i -lt $Count; $i++) {
            $slots.Add([pscustomobject]@{
                slot_index = ($i + 1)
                slot_window_id = "UNSCHEDULED"
                slot_label = "UNSCHEDULED"
                slot_start_pl = ""
                slot_end_pl = ""
                overflow = $true
            })
        }
        return @($slots)
    }

    $windowIndex = 0
    $cursor = [int]$Windows[0].start_minutes
    for ($i = 0; $i -lt $Count; $i++) {
        while ($windowIndex -lt $Windows.Count) {
            $window = $Windows[$windowIndex]
            if ($cursor -lt $window.start_minutes) {
                $cursor = [int]$window.start_minutes
            }
            if (($cursor + $SlotMinutes) -le [int]$window.end_minutes) {
                break
            }

            $windowIndex++
            if ($windowIndex -lt $Windows.Count) {
                $cursor = [int]$Windows[$windowIndex].start_minutes
            }
        }

        if ($windowIndex -ge $Windows.Count) {
            $slots.Add([pscustomobject]@{
                slot_index = ($i + 1)
                slot_window_id = "OVERFLOW"
                slot_label = "OVERFLOW"
                slot_start_pl = ""
                slot_end_pl = ""
                overflow = $true
            })
            continue
        }

        $window = $Windows[$windowIndex]
        $slotStart = $cursor
        $slotEnd = $cursor + $SlotMinutes
        $slots.Add([pscustomobject]@{
            slot_index = ($i + 1)
            slot_window_id = [string]$window.window_id
            slot_label = ("{0}-{1}" -f (Convert-MinutesToHhMm -TotalMinutes $slotStart), (Convert-MinutesToHhMm -TotalMinutes $slotEnd))
            slot_start_pl = (Convert-MinutesToHhMm -TotalMinutes $slotStart)
            slot_end_pl = (Convert-MinutesToHhMm -TotalMinutes $slotEnd)
            overflow = $false
        })
        $cursor = $slotEnd
    }

    return @($slots.ToArray())
}

function Get-FirstHint {
    param([object]$MlItem)

    if ($null -eq $MlItem) {
        return "brak mocnej wskazowki ML"
    }

    $hints = @($MlItem.hints)
    if ($hints.Count -eq 0) {
        return "brak mocnej wskazowki ML"
    }

    return [string]$hints[0]
}

function Get-Mt5FollowupReason {
    param([object]$PriorityEntry)

    if ($null -eq $PriorityEntry) {
        return "missing_priority_context"
    }

    if ([string]::IsNullOrWhiteSpace([string]$PriorityEntry.latest_tester_result)) {
        return "missing_recent_tester_verdict"
    }

    if ([string]$PriorityEntry.latest_tester_result -ne "successfully_finished") {
        return "retest_after_non_finished_or_failed_batch"
    }

    if ([string]$PriorityEntry.priority_band -in @("CRITICAL", "HIGH")) {
        return "priority_band_requires_followup"
    }

    if ([double]$PriorityEntry.live_net_24h -lt 0) {
        return "live_runtime_negative_followup"
    }

    return "maintain_verified_rotation"
}

function Test-QdmCustomPilotReady {
    param(
        [object]$PriorityEntry,
        [object]$ProfitEntry
    )

    if ($null -ne $ProfitEntry -and $ProfitEntry.PSObject.Properties.Name -contains "qdm_custom_pilot_ready") {
        return [bool]$ProfitEntry.qdm_custom_pilot_ready
    }

    if ($null -ne $PriorityEntry -and $PriorityEntry.PSObject.Properties.Name -contains "qdm_custom_pilot_ready") {
        return [bool]$PriorityEntry.qdm_custom_pilot_ready
    }

    return $false
}

function Get-ProfitStatus {
    param([object]$ProfitEntry)

    if ($null -eq $ProfitEntry) {
        return ""
    }

    if ($ProfitEntry.PSObject.Properties.Name -contains "status") {
        return [string]$ProfitEntry.status
    }

    return ""
}

function Get-ResearchPriorityTier {
    param(
        [object]$PriorityEntry,
        [object]$ProfitEntry,
        [bool]$QdmSupported
    )

    $status = Get-ProfitStatus -ProfitEntry $ProfitEntry
    $qdmCustomPilotReady = Test-QdmCustomPilotReady -PriorityEntry $PriorityEntry -ProfitEntry $ProfitEntry
    $trustState = if ($null -ne $PriorityEntry) { [string]$PriorityEntry.trust_state } else { "" }

    if ($status -eq "TESTER_POSITIVE" -and $qdmCustomPilotReady) { return 0 }
    if ($status -eq "TESTER_POSITIVE") { return 1 }
    if ($status -eq "NEAR_PROFIT" -and $qdmCustomPilotReady -and $trustState -eq "TRUSTED") { return 2 }
    if ($status -eq "NEAR_PROFIT" -and $qdmCustomPilotReady) { return 3 }
    if ($status -eq "LIVE_POSITIVE" -and $qdmCustomPilotReady) { return 4 }
    if ($qdmCustomPilotReady -and $trustState -eq "TRUSTED") { return 5 }
    if ($qdmCustomPilotReady) { return 6 }
    if ($QdmSupported -and $trustState -eq "TRUSTED") { return 7 }
    if ($QdmSupported) { return 8 }
    return 9
}

function Get-ResearchPriorityScore {
    param(
        [object]$PriorityEntry,
        [object]$ProfitEntry,
        [bool]$QdmSupported
    )

    $score = 0.0
    if ($null -ne $PriorityEntry) {
        $score += [double]$PriorityEntry.priority_score
    }

    $status = Get-ProfitStatus -ProfitEntry $ProfitEntry
    switch ($status) {
        "TESTER_POSITIVE" { $score += 450.0 }
        "NEAR_PROFIT" { $score += 220.0 }
        "LIVE_POSITIVE" { $score += 140.0 }
    }

    $qdmCustomPilotReady = Test-QdmCustomPilotReady -PriorityEntry $PriorityEntry -ProfitEntry $ProfitEntry
    if ($qdmCustomPilotReady) {
        $score += 140.0
    }
    elseif ($QdmSupported) {
        $score += 45.0
    }

    $trustState = if ($null -ne $PriorityEntry) { [string]$PriorityEntry.trust_state } else { "" }
    switch ($trustState) {
        "TRUSTED" { $score += 45.0 }
        "LOW_SAMPLE" { $score += 12.0 }
        "FOREFIELD_DIRTY" { $score -= 25.0 }
        "PAPER_CONVERSION_BLOCKED" { $score -= 35.0 }
    }

    $costState = if ($null -ne $PriorityEntry) { [string]$PriorityEntry.cost_state } else { "" }
    switch ($costState) {
        "HIGH" { $score -= 10.0 }
        "NON_REPRESENTATIVE" { $score -= 30.0 }
    }

    $bestTesterPnl = 0.0
    if ($null -ne $ProfitEntry -and $ProfitEntry.PSObject.Properties.Name -contains "best_tester_pnl") {
        $bestTesterPnl = [double]$ProfitEntry.best_tester_pnl
    }
    elseif ($null -ne $PriorityEntry) {
        $bestTesterPnl = [double]$PriorityEntry.latest_tester_pnl
    }

    if ($bestTesterPnl -gt 0) {
        $score += [Math]::Min(($bestTesterPnl / 4.0), 180.0)
    }
    elseif ($bestTesterPnl -lt 0) {
        $score += [Math]::Max(($bestTesterPnl / 20.0), -35.0)
    }

    if ($null -ne $ProfitEntry -and $ProfitEntry.PSObject.Properties.Name -contains "active_optimization_candidate_pnl") {
        $activeCandidatePnl = $ProfitEntry.active_optimization_candidate_pnl
        if ($null -ne $activeCandidatePnl) {
            $activeCandidatePnlValue = [double]$activeCandidatePnl
            if ($activeCandidatePnlValue -gt 0) {
                $score += [Math]::Min(($activeCandidatePnlValue / 6.0), 120.0)
            }
            elseif ($activeCandidatePnlValue -lt 0) {
                $score += [Math]::Max(($activeCandidatePnlValue / 25.0), -20.0)
            }
        }
    }

    return [Math]::Round($score, 3)
}

& $QdmProfileBuilderPath `
    -ProjectRoot $ProjectRoot `
    -PriorityReportPath $PriorityPath `
    -OutputPath $QdmPackPath `
    -EvidenceDir $EvidenceDir `
    -DesiredCount 99 | Out-Null

$registry = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$priorityReport = Get-Content -LiteralPath $PriorityPath -Raw -Encoding UTF8 | ConvertFrom-Json
$sessionMatrix = Get-Content -LiteralPath $SessionMatrixPath -Raw -Encoding UTF8 | ConvertFrom-Json

$mlHints = $null
if (Test-Path -LiteralPath $MlHintsPath) {
    $mlHints = Get-Content -LiteralPath $MlHintsPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$paperLiveFeedback = $null
if (Test-Path -LiteralPath $PaperLiveFeedbackPath) {
    $paperLiveFeedback = Get-Content -LiteralPath $PaperLiveFeedbackPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$profitTracking = $null
if (Test-Path -LiteralPath $ProfitTrackingPath) {
    $profitTracking = Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$qdmProfilePath = Join-Path $EvidenceDir "qdm_weakest_profile_latest.json"
$qdmProfile = Get-Content -LiteralPath $qdmProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json

$priorityMap = @{}
foreach ($entry in @($priorityReport.ranked_instruments)) {
    $priorityMap[[string]$entry.symbol_alias] = $entry
}

$mlMap = @{}
if ($null -ne $mlHints) {
    foreach ($entry in @($mlHints.items)) {
        $mlMap[[string]$entry.symbol_alias] = $entry
    }
}

$runtimeMap = @{}
if ($null -ne $paperLiveFeedback) {
    foreach ($item in @($paperLiveFeedback.top_active) + @($paperLiveFeedback.key_instruments)) {
        $key = [string]$item.instrument
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $runtimeMap.ContainsKey($key)) {
            $runtimeMap[$key] = $item
        }
    }
}

$profitMap = @{}
if ($null -ne $profitTracking) {
    foreach ($item in @($profitTracking.live_positive) + @($profitTracking.tester_positive) + @($profitTracking.near_profit)) {
        $key = [string]$item.symbol_alias
        if (-not [string]::IsNullOrWhiteSpace($key) -and -not $profitMap.ContainsKey($key)) {
            $profitMap[$key] = $item
        }
    }
}

$qdmIncludedMap = @{}
foreach ($item in @($qdmProfile.included)) {
    $qdmIncludedMap[[string]$item.symbol_alias] = $item
}

$qdmSkippedMap = @{}
foreach ($item in @($qdmProfile.skipped)) {
    $qdmSkippedMap[[string]$item.symbol_alias] = [string]$item.reason
}

$researchPriorityMap = @{}
foreach ($item in @($registry.symbols)) {
    $alias = [string]$item.symbol
    $priorityEntry = if ($priorityMap.ContainsKey($alias)) { $priorityMap[$alias] } else { $null }
    $profitEntry = if ($profitMap.ContainsKey($alias)) { $profitMap[$alias] } else { $null }
    $qdmSupported = $qdmIncludedMap.ContainsKey($alias)
    $researchPriorityMap[$alias] = [pscustomobject]@{
        tier = Get-ResearchPriorityTier -PriorityEntry $priorityEntry -ProfitEntry $profitEntry -QdmSupported $qdmSupported
        score = Get-ResearchPriorityScore -PriorityEntry $priorityEntry -ProfitEntry $profitEntry -QdmSupported $qdmSupported
        profit_status = Get-ProfitStatus -ProfitEntry $profitEntry
        qdm_custom_pilot_ready = Test-QdmCustomPilotReady -PriorityEntry $priorityEntry -ProfitEntry $profitEntry
    }
}

$orderedRegistry = @(
    $registry.symbols |
        Sort-Object @{
            Expression = {
                $key = [string]$_.symbol
                return [int]$researchPriorityMap[$key].tier
            }
        }, @{
            Expression = {
                $key = [string]$_.symbol
                return [double]$researchPriorityMap[$key].score
            }
            Descending = $true
        }, @{
            Expression = {
                $key = [string]$_.symbol
                if ($priorityMap.ContainsKey($key)) {
                    return [int]$priorityMap[$key].rank
                }
                return 999
            }
        }, symbol
)

$groupOrder = @("FX_ASIA", "FX_AM", "INDEX_EU", "METALS", "INDEX_US", "UNMAPPED")
$slotRows = New-Object System.Collections.Generic.List[object]
$groupSummaries = New-Object System.Collections.Generic.List[object]
$globalSlotIndex = 0

foreach ($groupName in $groupOrder) {
    $groupItems = @(
        $orderedRegistry |
            Where-Object { (Resolve-ResearchGroup -SessionProfile ([string]$_.session_profile)) -eq $groupName }
    )

    if ($groupItems.Count -eq 0) {
        continue
    }

    $windows = Get-TradeWindows -SessionMatrix $sessionMatrix -GroupName $groupName
    $slots = New-SequentialSlots -Windows $windows -Count $groupItems.Count -SlotMinutes $SlotMinutes

    for ($i = 0; $i -lt $groupItems.Count; $i++) {
        $item = $groupItems[$i]
        $alias = [string]$item.symbol
        $priorityEntry = if ($priorityMap.ContainsKey($alias)) { $priorityMap[$alias] } else { $null }
        $profitEntry = if ($profitMap.ContainsKey($alias)) { $profitMap[$alias] } else { $null }
        $runtimeEntry = if ($runtimeMap.ContainsKey($alias)) { $runtimeMap[$alias] } else { $null }
        $mlEntry = if ($mlMap.ContainsKey($alias)) { $mlMap[$alias] } else { $null }
        $qdmEntry = if ($qdmIncludedMap.ContainsKey($alias)) { $qdmIncludedMap[$alias] } else { $null }
        $researchPriority = $researchPriorityMap[$alias]
        $slot = $slots[$i]

        $globalSlotIndex++
        $focusObjective = if ($null -ne $priorityEntry) {
            [string]$priorityEntry.recommended_action
        }
        else {
            "utrzymac obserwacje i dopisac werdykt po nastepnym cyklu"
        }

        $slotRows.Add([pscustomobject]@{
            global_slot_index = $globalSlotIndex
            research_group = $groupName
            session_profile = [string]$item.session_profile
            symbol_alias = $alias
            broker_symbol = [string]$item.broker_symbol
            code_symbol = [string]$item.code_symbol
            research_priority_tier = [int]$researchPriority.tier
            research_priority_score = [double]$researchPriority.score
            profit_status = [string]$researchPriority.profit_status
            qdm_custom_pilot_ready = [bool]$researchPriority.qdm_custom_pilot_ready
            priority_rank = if ($null -ne $priorityEntry) { [int]$priorityEntry.rank } else { 999 }
            priority_score = if ($null -ne $priorityEntry) { [double]$priorityEntry.priority_score } else { 0.0 }
            priority_band = if ($null -ne $priorityEntry) { [string]$priorityEntry.priority_band } else { "UNKNOWN" }
            live_net_24h = if ($null -ne $priorityEntry) { [double]$priorityEntry.live_net_24h } elseif ($null -ne $runtimeEntry) { [double]$runtimeEntry.net } else { 0.0 }
            live_opens_24h = if ($null -ne $priorityEntry) { [int]$priorityEntry.live_opens_24h } elseif ($null -ne $runtimeEntry) { [int]$runtimeEntry.opens } else { 0 }
            trust_state = if ($null -ne $priorityEntry) { [string]$priorityEntry.trust_state } elseif ($null -ne $runtimeEntry) { [string]$runtimeEntry.trust } else { "" }
            cost_state = if ($null -ne $priorityEntry) { [string]$priorityEntry.cost_state } elseif ($null -ne $runtimeEntry) { [string]$runtimeEntry.cost } else { "" }
            latest_tester_result = if ($null -ne $priorityEntry) { [string]$priorityEntry.latest_tester_result } else { "" }
            latest_tester_pnl = if ($null -ne $priorityEntry) { [double]$priorityEntry.latest_tester_pnl } else { 0.0 }
            ml_risk_score = if ($null -ne $mlEntry) { [double]$mlEntry.ml_risk_score } else { 0.0 }
            ml_first_hint = Get-FirstHint -MlItem $mlEntry
            qdm_supported = ($null -ne $qdmEntry)
            qdm_symbol = if ($null -ne $qdmEntry) { [string]$qdmEntry.qdm_symbol } else { "" }
            qdm_datasource = if ($null -ne $qdmEntry) { [string]$qdmEntry.datasource } else { "" }
            qdm_export_name = if ($null -ne $qdmEntry) { [string]$qdmEntry.mt5_export_name } else { "" }
            qdm_note = if ($null -ne $qdmEntry) { "supported" } elseif ($qdmSkippedMap.ContainsKey($alias)) { [string]$qdmSkippedMap[$alias] } else { "no_qdm_mapping" }
            research_data_lane = if ($null -ne $qdmEntry) { "QDM_PLUS_MT5" } else { "MT5_RUNTIME_TESTER_FALLBACK" }
            slot_minutes = $SlotMinutes
            slot_index_in_group = [int]$slot.slot_index
            slot_window_id = [string]$slot.slot_window_id
            slot_pl = [string]$slot.slot_label
            slot_start_pl = [string]$slot.slot_start_pl
            slot_end_pl = [string]$slot.slot_end_pl
            slot_overflow = [bool]$slot.overflow
            focus_objective = $focusObjective
            mt5_followup_required = $true
            mt5_followup_reason = Get-Mt5FollowupReason -PriorityEntry $priorityEntry
        })
    }

    $groupSummaries.Add([pscustomobject]@{
        research_group = $groupName
        symbols = $groupItems.Count
        scheduled_slots = @($slots | Where-Object { -not $_.overflow }).Count
        overflow_slots = @($slots | Where-Object { $_.overflow }).Count
        trade_windows = @($windows | ForEach-Object { $_.primary_label })
    })
}

$testerQueueArray = @(
    $orderedRegistry |
        ForEach-Object { [string]$_.symbol } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique
)
$qdmSyncTargetArray = @(
    $orderedRegistry |
        ForEach-Object { [string]$_.symbol } |
        Where-Object { $qdmIncludedMap.ContainsKey($_) } |
        Select-Object -Unique
)
$groupSummaryArray = @($groupSummaries.ToArray())
$slotPlanArray = @($slotRows.ToArray())

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    runtime_profile = "LAPTOP_RESEARCH"
    slot_minutes = $SlotMinutes
    qdm_pack_path = $QdmPackPath
    tester_queue = $testerQueueArray
    qdm_sync_targets = $qdmSyncTargetArray
    group_summary = $groupSummaryArray
    slot_plan = $slotPlanArray
    summary = [ordered]@{
        total_symbols = $slotPlanArray.Count
        qdm_supported_symbols = @($slotPlanArray | Where-Object { $_.qdm_supported }).Count
        qdm_unsupported_symbols = @($slotPlanArray | Where-Object { -not $_.qdm_supported }).Count
        qdm_custom_pilot_ready_symbols = @($slotPlanArray | Where-Object { $_.qdm_custom_pilot_ready }).Count
        tester_positive_symbols = @($slotPlanArray | Where-Object { $_.profit_status -eq "TESTER_POSITIVE" }).Count
        near_profit_symbols = @($slotPlanArray | Where-Object { $_.profit_status -eq "NEAR_PROFIT" }).Count
        mt5_queue_count = $testerQueueArray.Count
    }
}

$jsonLatest = Join-Path $EvidenceDir "qdm_intensive_research_plan_latest.json"
$mdLatest = Join-Path $EvidenceDir "qdm_intensive_research_plan_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("qdm_intensive_research_plan_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("qdm_intensive_research_plan_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# QDM Intensive Research Plan Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- runtime_profile: {0}" -f $report.runtime_profile))
$lines.Add(("- slot_minutes: {0}" -f $report.slot_minutes))
$lines.Add(("- total_symbols: {0}" -f $report.summary.total_symbols))
$lines.Add(("- qdm_supported_symbols: {0}" -f $report.summary.qdm_supported_symbols))
$lines.Add(("- qdm_custom_pilot_ready_symbols: {0}" -f $report.summary.qdm_custom_pilot_ready_symbols))
$lines.Add(("- tester_positive_symbols: {0}" -f $report.summary.tester_positive_symbols))
$lines.Add(("- near_profit_symbols: {0}" -f $report.summary.near_profit_symbols))
$lines.Add(("- mt5_queue_count: {0}" -f $report.summary.mt5_queue_count))
$lines.Add("")
$lines.Add("## Group Summary")
$lines.Add("")
foreach ($group in $report.group_summary) {
    $tradeWindows = if (@($group.trade_windows).Count -gt 0) { (@($group.trade_windows) -join ", ") } else { "brak" }
    $lines.Add(("- {0}: symbols={1}, scheduled={2}, overflow={3}, trade_windows={4}" -f
        $group.research_group,
        $group.symbols,
        $group.scheduled_slots,
        $group.overflow_slots,
        $tradeWindows))
}
$lines.Add("")
$lines.Add("## MT5 Queue")
$lines.Add("")
$lines.Add(("- {0}" -f ($report.tester_queue -join ", ")))
$lines.Add("")

foreach ($groupName in $groupOrder) {
    $rows = @($report.slot_plan | Where-Object { $_.research_group -eq $groupName })
    if ($rows.Count -eq 0) {
        continue
    }

    $lines.Add(("## {0}" -f $groupName))
    $lines.Add("")
    foreach ($row in $rows) {
        $qdmState = if ($row.qdm_supported) { ("QDM {0} via {1}" -f $row.qdm_symbol, $row.qdm_datasource) } else { ("QDM brak: {0}" -f $row.qdm_note) }
        $lines.Add(("- slot #{0} {1} {2}: lane_tier={3}, lane_score={4}, profit_status={5}, rank={6}, trust={7}, cost={8}, live_net_24h={9}, ml_risk={10}, {11}" -f
            $row.slot_index_in_group,
            $row.slot_pl,
            $row.symbol_alias,
            $row.research_priority_tier,
            $row.research_priority_score,
            $(if ([string]::IsNullOrWhiteSpace([string]$row.profit_status)) { "NONE" } else { [string]$row.profit_status }),
            $row.priority_rank,
            $row.trust_state,
            $row.cost_state,
            $row.live_net_24h,
            $row.ml_risk_score,
            $qdmState))
        $lines.Add(("  research_lane: {0}" -f $row.research_data_lane))
        $lines.Add(("  focus: {0}" -f $row.focus_objective))
        $lines.Add(("  mt5_followup: {0}" -f $row.mt5_followup_reason))
        $lines.Add(("  ml_hint: {0}" -f $row.ml_first_hint))
    }
    $lines.Add("")
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report
