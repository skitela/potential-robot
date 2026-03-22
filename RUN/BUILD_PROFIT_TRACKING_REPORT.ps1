param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RuntimeReviewPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json",
    [string]$PriorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$TesterEvidenceRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER",
    [string]$NearProfitQueuePath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\near_profit_optimization_queue_latest.json",
    [string]$QdmPilotRegistryPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\qdm_custom_symbol_pilot_registry_latest.json",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Convert-ToDoubleOrNull {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    $raw = [string]$Value
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    if ($raw -eq "null") { return $null }

    try {
        return [double]($raw -replace ',', '.')
    }
    catch {
        return $null
    }
}

function Normalize-Alias {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value.ToUpperInvariant()) -replace '[^A-Z0-9]+', '')
}

function Get-FirstValue {
    param(
        [object]$Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($null -ne $Object -and $Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }

    return $null
}

function Get-EffectiveTesterSummaryPnl {
    param([object]$Summary)

    if ($null -eq $Summary) {
        return $null
    }

    $topLevelPnl = Convert-ToDoubleOrNull $Summary.realized_pnl_lifetime
    $telemetry = Get-FirstValue -Object $Summary -Names @("tester_telemetry")
    $passCount = [int](Get-FirstValue -Object $Summary -Names @("tester_optimization_pass_count"))
    $experimentStatus = [string](Get-FirstValue -Object $telemetry -Names @("experiment_status"))
    $telemetryPnl = Convert-ToDoubleOrNull (Get-FirstValue -Object $telemetry -Names @("realized_pnl_lifetime", "custom_score"))

    if (($passCount -gt 0 -or $experimentStatus -eq "OPTIMIZATION_PASS") -and $null -ne $telemetryPnl) {
        return $telemetryPnl
    }

    return $topLevelPnl
}

function Get-EffectiveTesterSummaryResultLabel {
    param([object]$Summary)

    $resultLabel = [string](Get-FirstValue -Object $Summary -Names @("result_label"))
    $passCount = [int](Get-FirstValue -Object $Summary -Names @("tester_optimization_pass_count"))

    if ($resultLabel -eq "timed_out" -and $passCount -gt 0) {
        return "timed_out_with_materialized_passes"
    }

    if (-not [string]::IsNullOrWhiteSpace($resultLabel)) {
        return $resultLabel
    }

    return [string](Get-FirstValue -Object $Summary -Names @("raw_result_label"))
}

function Get-EffectiveTesterSummaryOptimizationInputs {
    param([object]$Summary)

    if ($null -eq $Summary) {
        return @()
    }

    $telemetry = Get-FirstValue -Object $Summary -Names @("tester_telemetry")
    $passCount = [int](Get-FirstValue -Object $Summary -Names @("tester_optimization_pass_count"))
    $experimentStatus = [string](Get-FirstValue -Object $telemetry -Names @("experiment_status"))
    $optimizationInputs = @(Get-FirstValue -Object $telemetry -Names @("optimization_inputs"))

    if (($passCount -gt 0 -or $experimentStatus -eq "OPTIMIZATION_PASS") -and $optimizationInputs.Count -gt 0) {
        return @($optimizationInputs | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @()
}

function Test-MeaningfulTesterSummary {
    param([object]$Summary)

    if ($null -eq $Summary) {
        return $false
    }

    $sampleCount = 0
    if ($Summary.PSObject.Properties.Name -contains 'learning_sample_count') {
        $sampleCount = [int]$Summary.learning_sample_count
    }

    $trustState = ""
    if ($Summary.PSObject.Properties.Name -contains 'trust_state') {
        $trustState = [string]$Summary.trust_state
    }

    $pnl = Get-EffectiveTesterSummaryPnl -Summary $Summary
    $hasMaterialPnl = ($null -ne $pnl -and [math]::Abs($pnl) -ge 0.0000001)

    if ($sampleCount -gt 0) {
        return $true
    }

    if ($hasMaterialPnl) {
        return $true
    }

    if (($trustState -ne "") -and ($trustState -ne "OBSERVATIONS_MISSING")) {
        return $true
    }

    return $false
}

function Test-MeaningfulPriorityTesterBaseline {
    param([object]$Item)

    if ($null -eq $Item) {
        return $false
    }

    $sampleCount = 0
    if ($Item.PSObject.Properties.Name -contains 'latest_tester_sample') {
        $sampleCount = [int]$Item.latest_tester_sample
    }

    $trustState = ""
    if ($Item.PSObject.Properties.Name -contains 'latest_tester_trust') {
        $trustState = [string]$Item.latest_tester_trust
    }

    $pnl = $null
    if ($Item.PSObject.Properties.Name -contains 'latest_tester_pnl') {
        $pnl = Convert-ToDoubleOrNull $Item.latest_tester_pnl
    }
    $hasMaterialPnl = ($null -ne $pnl -and [math]::Abs($pnl) -ge 0.0000001)

    if ($sampleCount -gt 0) {
        return $true
    }

    if ($hasMaterialPnl) {
        return $true
    }

    if (($trustState -ne "") -and ($trustState -ne "OBSERVATIONS_MISSING")) {
        return $true
    }

    return $false
}

function Get-BestTesterBySymbol {
    param([string]$Root)

    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*summary.json" -ErrorAction SilentlyContinue)
    $best = @{}

    foreach ($file in $files) {
        try {
            $summary = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            continue
        }

        if (-not (Test-MeaningfulTesterSummary -Summary $summary)) {
            continue
        }

        $symbolAlias = Normalize-Alias ([string]$summary.symbol_alias)
        if ([string]::IsNullOrWhiteSpace($symbolAlias)) {
            continue
        }

        $pnl = Get-EffectiveTesterSummaryPnl -Summary $summary
        if ($null -eq $pnl) {
            continue
        }

        $row = [pscustomobject]@{
            symbol_alias = $symbolAlias
            pnl          = $pnl
            result_label = Get-EffectiveTesterSummaryResultLabel -Summary $summary
            trust_state  = [string]$summary.trust_state
            source_path  = $file.FullName
            optimization_inputs = @(
                Get-EffectiveTesterSummaryOptimizationInputs -Summary $summary
            )
        }

        if (-not $best.ContainsKey($row.symbol_alias) -or $row.pnl -gt $best[$row.symbol_alias].pnl) {
            $best[$row.symbol_alias] = $row
        }
    }

    return $best
}

if (-not (Test-Path -LiteralPath $RuntimeReviewPath)) {
    throw "Runtime review not found: $RuntimeReviewPath"
}
if (-not (Test-Path -LiteralPath $PriorityPath)) {
    throw "Priority report not found: $PriorityPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

$runtime = Get-Content -LiteralPath $RuntimeReviewPath -Raw -Encoding UTF8 | ConvertFrom-Json
$priority = Get-Content -LiteralPath $PriorityPath -Raw -Encoding UTF8 | ConvertFrom-Json
$bestTester = Get-BestTesterBySymbol -Root $TesterEvidenceRoot
$nearProfitQueue = $null
if (Test-Path -LiteralPath $NearProfitQueuePath) {
    $nearProfitQueue = Get-Content -LiteralPath $NearProfitQueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$qdmPilotRegistry = $null
if (Test-Path -LiteralPath $QdmPilotRegistryPath) {
    $qdmPilotRegistry = Get-Content -LiteralPath $QdmPilotRegistryPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
$qdmPilotByAlias = @{}
if ($null -ne $qdmPilotRegistry -and $qdmPilotRegistry.PSObject.Properties.Name -contains 'entries') {
    foreach ($entry in @($qdmPilotRegistry.entries)) {
        $entryAlias = Normalize-Alias ([string]$entry.symbol_alias)
        if (-not [string]::IsNullOrWhiteSpace($entryAlias)) {
            $qdmPilotByAlias[$entryAlias] = $entry
        }
    }
}

$runtimeBySymbol = @{}
foreach ($item in @($runtime.key_instruments)) {
    $runtimeBySymbol[[string]$item.instrument] = $item
}
foreach ($item in @($runtime.top_active)) {
    if (-not $runtimeBySymbol.ContainsKey([string]$item.instrument)) {
        $runtimeBySymbol[[string]$item.instrument] = $item
    }
}

$activeOptimizationByAlias = @{}
if (
    $null -ne $nearProfitQueue -and
    [string]$nearProfitQueue.state -eq "running" -and
    $nearProfitQueue.PSObject.Properties.Name -contains 'active_sandbox' -and
    $null -ne $nearProfitQueue.active_sandbox
) {
    $activeSymbolAlias = Normalize-Alias ([string]$nearProfitQueue.current_symbol)
    $activeCandidatePnl = Convert-ToDoubleOrNull $nearProfitQueue.active_sandbox.best_tester_pass_realized_pnl
    $activeCandidateInputs = @()
    if ($nearProfitQueue.active_sandbox.PSObject.Properties.Name -contains 'best_tester_pass_inputs') {
        $activeCandidateInputs = @($nearProfitQueue.active_sandbox.best_tester_pass_inputs | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if (
        -not [string]::IsNullOrWhiteSpace($activeSymbolAlias) -and
        $null -ne $activeCandidatePnl -and
        ([math]::Abs($activeCandidatePnl) -ge 0.0000001 -or $activeCandidateInputs.Count -gt 0)
    ) {
        $activeOptimizationByAlias[$activeSymbolAlias] = [pscustomobject]@{
            pnl = $activeCandidatePnl
            optimization_inputs = @($activeCandidateInputs)
        }
    }
}

$rows = foreach ($item in @($priority.ranked_instruments)) {
    $symbol = [string]$item.symbol_alias
    $symbolNorm = Normalize-Alias $symbol
    $tester = $null
    if ($bestTester.ContainsKey($symbolNorm)) {
        $tester = $bestTester[$symbolNorm]
    }

    $runtimeItem = $null
    if ($runtimeBySymbol.ContainsKey($symbol)) {
        $runtimeItem = $runtimeBySymbol[$symbol]
    }
    $activeOptimizationCandidate = $null
    if ($activeOptimizationByAlias.ContainsKey($symbolNorm)) {
        $activeOptimizationCandidate = $activeOptimizationByAlias[$symbolNorm]
    }
    $qdmPilot = $null
    if ($qdmPilotByAlias.ContainsKey($symbolNorm)) {
        $qdmPilot = $qdmPilotByAlias[$symbolNorm]
    }

    $liveOpens = Convert-ToDoubleOrNull $item.live_opens_24h
    $liveCloses = if ($null -ne $runtimeItem -and $runtimeItem.PSObject.Properties.Name -contains 'closes') { Convert-ToDoubleOrNull $runtimeItem.closes } else { $null }
    $liveWins = if ($null -ne $runtimeItem -and $runtimeItem.PSObject.Properties.Name -contains 'wins') { Convert-ToDoubleOrNull $runtimeItem.wins } else { $null }
    $liveLosses = if ($null -ne $runtimeItem -and $runtimeItem.PSObject.Properties.Name -contains 'losses') { Convert-ToDoubleOrNull $runtimeItem.losses } else { $null }
    $liveNeutral = if ($null -ne $runtimeItem -and $runtimeItem.PSObject.Properties.Name -contains 'neutral') { Convert-ToDoubleOrNull $runtimeItem.neutral } else { $null }
    $liveNet = if ($null -ne $runtimeItem -and $runtimeItem.PSObject.Properties.Name -contains 'net') {
        Convert-ToDoubleOrNull $runtimeItem.net
    }
    elseif ($item.PSObject.Properties.Name -contains 'live_net_24h') {
        Convert-ToDoubleOrNull $item.live_net_24h
    }
    else {
        $null
    }

    $priorityTesterPnl = Convert-ToDoubleOrNull $item.latest_tester_pnl
    $bestTesterPnl = $null
    $bestTesterTrust = ""
    $bestTesterPath = ""
    $bestTesterOptimizationInputs = @()

    if ($tester) {
        $bestTesterPnl = $tester.pnl
        $bestTesterTrust = [string]$tester.trust_state
        $bestTesterPath = [string]$tester.source_path
        $bestTesterOptimizationInputs = @($tester.optimization_inputs)
    }

    if ($null -ne $priorityTesterPnl -and ($null -eq $bestTesterPnl -or $priorityTesterPnl -gt $bestTesterPnl)) {
        $bestTesterPnl = $priorityTesterPnl
        $bestTesterTrust = [string]$item.latest_tester_trust
        $bestTesterPath = [string]$item.latest_tester_path
        $bestTesterOptimizationInputs = if ($item.PSObject.Properties.Name -contains 'latest_tester_optimization_inputs') {
            @($item.latest_tester_optimization_inputs)
        }
        else {
            @()
        }
    }

    $hasMeaningfulPriorityBaseline = Test-MeaningfulPriorityTesterBaseline -Item $item
    $hasTesterBaseline = $false
    if ($null -ne $bestTesterPnl) {
        $hasTesterBaseline = $true
    }
    elseif (
        $hasMeaningfulPriorityBaseline -and
        ($item.PSObject.Properties.Name -contains 'latest_tester_path') -and
        -not [string]::IsNullOrWhiteSpace([string]$item.latest_tester_path)
    ) {
        $hasTesterBaseline = $true
    }
    $hasLiveActivity = ($null -ne $liveOpens -and $liveOpens -gt 0)

    $status = "NEGATIVE"
    if ($hasLiveActivity -and $null -ne $liveNet -and $liveNet -gt 0) {
        $status = "LIVE_POSITIVE"
    }
    elseif ($hasTesterBaseline -and $null -ne $bestTesterPnl -and $bestTesterPnl -gt 0) {
        $status = "TESTER_POSITIVE"
    }
    elseif (($hasLiveActivity -and $null -ne $liveNet -and $liveNet -ge -5) -or ($hasTesterBaseline -and $null -ne $bestTesterPnl -and $bestTesterPnl -ge -5)) {
        $status = "NEAR_PROFIT"
    }

    [pscustomobject]@{
        symbol_alias      = $symbol
        status            = $status
        live_opens_24h    = $liveOpens
        live_closes_24h   = $liveCloses
        live_wins_24h     = $liveWins
        live_losses_24h   = $liveLosses
        live_neutral_24h  = $liveNeutral
        live_net_24h      = $liveNet
        best_tester_pnl   = if ($hasTesterBaseline) { $bestTesterPnl } else { $null }
        best_tester_trust = if ($hasTesterBaseline) { $bestTesterTrust } else { "" }
        best_tester_path  = if ($hasTesterBaseline) { $bestTesterPath } else { "" }
        best_tester_optimization_inputs = if ($hasTesterBaseline) { @($bestTesterOptimizationInputs) } else { @() }
        active_optimization_candidate_pnl = if ($null -ne $activeOptimizationCandidate) { $activeOptimizationCandidate.pnl } else { $null }
        active_optimization_candidate_inputs = if ($null -ne $activeOptimizationCandidate) { @($activeOptimizationCandidate.optimization_inputs) } else { @() }
        qdm_custom_pilot_ready = ($null -ne $qdmPilot)
        qdm_custom_symbol = if ($null -ne $qdmPilot) { [string]$qdmPilot.custom_symbol } else { "" }
        qdm_pilot_row_count = if ($null -ne $qdmPilot) { [int]$qdmPilot.pilot_row_count } else { 0 }
        qdm_pilot_result = if ($null -ne $qdmPilot) { [string]$qdmPilot.result_label } else { "" }
        recommended_action = [string]$item.recommended_action
        priority_rank     = [int]$item.rank
    }
}

$livePositive = @($rows | Where-Object { $_.status -eq "LIVE_POSITIVE" } | Sort-Object live_net_24h -Descending)
$testerPositive = @($rows | Where-Object { $_.status -eq "TESTER_POSITIVE" } | Sort-Object best_tester_pnl -Descending)
$nearProfit = @($rows | Where-Object { $_.status -eq "NEAR_PROFIT" } | Sort-Object @{Expression = { if ($null -ne $_.best_tester_pnl) { [math]::Abs($_.best_tester_pnl) } else { 999999 } }}, priority_rank)
$runtimeWatchlist = @($rows | Where-Object { $_.symbol_alias -in @("GOLD", "US500") } | Sort-Object symbol_alias)

$report = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    runtime_window_start = [string]$priority.runtime_window_start
    runtime_window_end = [string]$priority.runtime_window_end
    live_positive_count = $livePositive.Count
    tester_positive_count = $testerPositive.Count
    near_profit_count = $nearProfit.Count
    live_positive = $livePositive
    tester_positive = $testerPositive
    near_profit = $nearProfit
    runtime_watchlist = $runtimeWatchlist
    all = $rows
}

$jsonPath = Join-Path $OutputRoot "profit_tracking_latest.json"
$mdPath = Join-Path $OutputRoot "profit_tracking_latest.md"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Profit Tracking Latest")
$lines.Add("")
if ($report.live_positive_count -gt 0 -or $report.tester_positive_count -gt 0) {
    $lines.Add("<div style=`"color:#c00000;font-size:28px;font-weight:700;`">MAMY SUKCES: CO NAJMNIEJ JEDEN INSTRUMENT JEST NA PLUSIE</div>")
    $lines.Add("")
}
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- live_positive_count: {0}" -f $report.live_positive_count))
$lines.Add(("- tester_positive_count: {0}" -f $report.tester_positive_count))
$lines.Add(("- near_profit_count: {0}" -f $report.near_profit_count))
$lines.Add("")
$lines.Add("## Live Positive")
$lines.Add("")
if ($livePositive.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $livePositive) {
        $lines.Add(("- {0}: live_net_24h={1}" -f $item.symbol_alias, $item.live_net_24h))
    }
}
$lines.Add("")
$lines.Add("## Tester Positive")
$lines.Add("")
if ($testerPositive.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $testerPositive) {
        $inputsSuffix = if (@($item.best_tester_optimization_inputs).Count -gt 0) {
            " inputs={0}" -f ((@($item.best_tester_optimization_inputs) -join "; "))
        }
        else {
            ""
        }
        $candidateSuffix = if ($null -ne $item.active_optimization_candidate_pnl) {
            " active_candidate_pnl={0}" -f $item.active_optimization_candidate_pnl
        }
        else {
            ""
        }
        $qdmSuffix = if ($item.qdm_custom_pilot_ready) {
            " qdm={0} rows={1}" -f $item.qdm_custom_symbol, $item.qdm_pilot_row_count
        }
        else {
            ""
        }
        $lines.Add(("- {0}: best_tester_pnl={1} trust={2}{3}{4}{5}" -f $item.symbol_alias, $item.best_tester_pnl, $item.best_tester_trust, $inputsSuffix, $candidateSuffix, $qdmSuffix))
    }
}
$lines.Add("")
$lines.Add("## Near Profit")
$lines.Add("")
if ($nearProfit.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $nearProfit | Select-Object -First 8) {
        $candidateSuffix = if ($null -ne $item.active_optimization_candidate_pnl) {
            $candidateInputs = if (@($item.active_optimization_candidate_inputs).Count -gt 0) {
                " active_candidate_inputs={0}" -f ((@($item.active_optimization_candidate_inputs) -join "; "))
            }
            else {
                ""
            }
            " active_candidate_pnl={0}{1}" -f $item.active_optimization_candidate_pnl, $candidateInputs
        }
        else {
            ""
        }
        $qdmSuffix = if ($item.qdm_custom_pilot_ready) {
            " qdm={0} rows={1}" -f $item.qdm_custom_symbol, $item.qdm_pilot_row_count
        }
        else {
            ""
        }
        $lines.Add(("- {0}: best_tester_pnl={1} live_opens={2} live_closes={3} live_wins={4} live_losses={5} live_net_24h={6} action={7}{8}{9}" -f $item.symbol_alias, $item.best_tester_pnl, $item.live_opens_24h, $item.live_closes_24h, $item.live_wins_24h, $item.live_losses_24h, $item.live_net_24h, $item.recommended_action, $candidateSuffix, $qdmSuffix))
    }
}
$lines.Add("")
$lines.Add("## Runtime Watchlist")
$lines.Add("")
if ($runtimeWatchlist.Count -eq 0) {
    $lines.Add("- none")
}
else {
    foreach ($item in $runtimeWatchlist) {
        $lines.Add(("- {0}: opens={1} closes={2} wins={3} losses={4} neutral={5} net={6}" -f $item.symbol_alias, $item.live_opens_24h, $item.live_closes_24h, $item.live_wins_24h, $item.live_losses_24h, $item.live_neutral_24h, $item.live_net_24h))
    }
}

($lines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8
$report
