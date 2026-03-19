param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$StateRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT\state",
    [string]$RuntimeReviewPath = "C:\OANDA_MT5_SYSTEM\EVIDENCE\vps_sync\mt5_virtual_hosting_runtime_review_24h_compact_latest.json",
    [string]$EvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Normalize-SymbolAlias {
    param(
        [AllowNull()]
        [string]$Symbol
    )

    if ([string]::IsNullOrWhiteSpace($Symbol)) {
        return ""
    }

    $value = $Symbol.Trim()
    if ($value.EndsWith(".pro", [System.StringComparison]::OrdinalIgnoreCase)) {
        $value = $value.Substring(0, $value.Length - 4)
    }
    return $value.ToUpperInvariant()
}

function Get-FirstValue {
    param(
        [object]$Object,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Object.PSObject.Properties.Name -contains $name) {
            return $Object.$name
        }
    }
    return $null
}

function Get-TrustWeight {
    param([string]$TrustState)
    switch ($TrustState) {
        "LOW_SAMPLE" { return 36 }
        "FOREFIELD_DIRTY" { return 32 }
        "PAPER_CONVERSION_BLOCKED" { return 28 }
        default { return 10 }
    }
}

function Get-CostWeight {
    param([string]$CostState)
    switch ($CostState) {
        "NON_REPRESENTATIVE" { return 22 }
        "HIGH" { return 12 }
        "LOW" { return 0 }
        default { return 6 }
    }
}

function Get-SampleWeight {
    param([int]$SampleCount)
    if ($SampleCount -lt 50) { return 26 }
    if ($SampleCount -lt 120) { return 18 }
    if ($SampleCount -lt 250) { return 10 }
    if ($SampleCount -lt 400) { return 6 }
    return 2
}

function Get-BiasWeight {
    param([double]$Bias)
    $absBias = [math]::Abs($Bias)
    if ($absBias -ge 0.15) { return 22 }
    if ($absBias -ge 0.12) { return 16 }
    if ($absBias -ge 0.08) { return 11 }
    if ($absBias -ge 0.04) { return 6 }
    return 2
}

function Get-LiveWeight {
    param(
        [double]$Net,
        [int]$Opens,
        [string]$TrustState
    )

    $score = 0
    if ($Opens -gt 0) {
        $score += 8
        if ($Net -lt 0) {
            $score += [math]::Min([math]::Abs($Net) / 4.0, 40.0)
        }
    }
    elseif ($TrustState -eq "LOW_SAMPLE") {
        $score += 6
    }
    return [int][math]::Round($score, 0)
}

function Get-PriorityBand {
    param([int]$Score)
    if ($Score -ge 80) { return "CRITICAL" }
    if ($Score -ge 60) { return "HIGH" }
    if ($Score -ge 40) { return "MEDIUM" }
    return "LOW"
}

function Get-RecommendedAction {
    param(
        [string]$TrustState,
        [string]$TrustReason,
        [string]$CostState,
        [int]$SampleCount,
        [double]$Net,
        [int]$Opens
    )

    if ($TrustState -eq "LOW_SAMPLE" -or $SampleCount -lt 50) {
        return "powiekszyc probke i dane historyczne, bez strojenia sygnalu"
    }
    if ($CostState -eq "NON_REPRESENTATIVE") {
        return "naprawic reprezentatywnosc kosztu i zrodlo danych"
    }
    if ($TrustState -eq "FOREFIELD_DIRTY") {
        if ($TrustReason -like "*SPREAD_DISTORTION*") {
            return "oczyscic foreground i spread distortion przed dalszym tuningiem"
        }
        return "oczyscic foreground i brudne kandydaty przed tuningiem sygnalu"
    }
    if ($TrustState -eq "PAPER_CONVERSION_BLOCKED" -or $TrustReason -like "*LOW_RATIO*") {
        if ($Opens -gt 0 -and $Net -lt 0) {
            return "uderzyc jednoczesnie w live runtime i candidate-to-paper contract"
        }
        return "pracowac nad candidate-to-paper i kontraktem ryzyka"
    }
    if ($Opens -gt 0 -and $Net -lt 0) {
        return "aktywny instrument live: szukac jednej malej delty po bucketach"
    }
    return "utrzymac obserwacje i przygotowac kolejny tester batch"
}

function Get-LatestTesterSummaries {
    param([string]$StrategyTesterRoot)

    $map = @{}
    if (-not (Test-Path -LiteralPath $StrategyTesterRoot)) {
        return $map
    }

    Get-ChildItem -Path $StrategyTesterRoot -Recurse -Filter "*_summary.json" -File |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object {
            try {
                $summary = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                $alias = Normalize-SymbolAlias (Get-FirstValue -Object $summary -Names @("symbol_alias", "storage_alias", "symbol"))
                if ([string]::IsNullOrWhiteSpace($alias)) {
                    return
                }
                $resultLabel = [string](Get-FirstValue -Object $summary -Names @("result_label"))
                $trustState = [string](Get-FirstValue -Object $summary -Names @("trust_state"))
                $sampleCount = [int](Get-FirstValue -Object $summary -Names @("learning_sample_count"))
                $biasValue = [double](Get-FirstValue -Object $summary -Names @("learning_bias"))
                $pnlValue = [double](Get-FirstValue -Object $summary -Names @("realized_pnl_lifetime"))
                $isEmptySummary = (
                    [string]::IsNullOrWhiteSpace($trustState) -and
                    $sampleCount -le 0 -and
                    [math]::Abs($biasValue) -lt 0.0000001 -and
                    (
                        $null -eq $pnlValue -or
                        [math]::Abs($pnlValue) -lt 0.0000001
                    )
                )
                if ($isEmptySummary) {
                    return
                }
                if ($map.ContainsKey($alias)) {
                    return
                }
                $map[$alias] = [ordered]@{
                    path         = $_.FullName
                    written_local = $_.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
                    trust_state  = $trustState
                    trust_reason = [string](Get-FirstValue -Object $summary -Names @("trust_reason"))
                    cost_state   = [string](Get-FirstValue -Object $summary -Names @("cost_pressure_state"))
                    sample       = $sampleCount
                    bias         = $biasValue
                    pnl          = $pnlValue
                    result_label = $resultLabel
                }
            }
            catch {
            }
        }

    return $map
}

New-Item -ItemType Directory -Force -Path $EvidenceDir | Out-Null

$runtimeReview = $null
if (Test-Path -LiteralPath $RuntimeReviewPath) {
    $runtimeReview = Get-Content -LiteralPath $RuntimeReviewPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

$liveMap = @{}
if ($null -ne $runtimeReview -and $runtimeReview.PSObject.Properties.Name -contains "key_instruments") {
    foreach ($item in $runtimeReview.key_instruments) {
        $alias = Normalize-SymbolAlias $item.instrument
        if (-not [string]::IsNullOrWhiteSpace($alias)) {
            $liveMap[$alias] = $item
        }
    }
}

$testerMap = Get-LatestTesterSummaries -StrategyTesterRoot (Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER")

$items = New-Object System.Collections.Generic.List[object]
Get-ChildItem -Path $StateRoot -Directory -ErrorAction Stop | ForEach-Object {
    $summaryPath = Join-Path $_.FullName "execution_summary.json"
    if (-not (Test-Path -LiteralPath $summaryPath)) {
        return
    }

    try {
        $summary = Get-Content -LiteralPath $summaryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        return
    }

    $alias = Normalize-SymbolAlias (Get-FirstValue -Object $summary -Names @("symbol", "storage_alias", "symbol_alias"))
    if ([string]::IsNullOrWhiteSpace($alias)) {
        return
    }

    $trustState = [string](Get-FirstValue -Object $summary -Names @("trust_state"))
    $trustReason = [string](Get-FirstValue -Object $summary -Names @("trust_reason"))
    $costState = [string](Get-FirstValue -Object $summary -Names @("cost_pressure_state", "cost_state"))
    $sampleCount = [int](Get-FirstValue -Object $summary -Names @("learning_sample_count"))
    $bias = [double](Get-FirstValue -Object $summary -Names @("learning_bias"))
    $spreadPoints = [double](Get-FirstValue -Object $summary -Names @("spread_points", "spread_now"))

    $live = if ($liveMap.ContainsKey($alias)) { $liveMap[$alias] } else { $null }
    $liveNet = if ($null -ne $live) { [double]$live.net } else { 0.0 }
    $liveOpens = if ($null -ne $live) { [int]$live.opens } else { 0 }
    $liveCost = if ($null -ne $live) { [string]$live.cost } else { $costState }
    if ([string]::IsNullOrWhiteSpace($costState)) {
        $costState = $liveCost
    }

    $score = 0
    $score += Get-TrustWeight -TrustState $trustState
    $score += Get-CostWeight -CostState $costState
    $score += Get-SampleWeight -SampleCount $sampleCount
    $score += Get-BiasWeight -Bias $bias
    $score += Get-LiveWeight -Net $liveNet -Opens $liveOpens -TrustState $trustState

    $tester = if ($testerMap.ContainsKey($alias)) { $testerMap[$alias] } else { $null }

    $items.Add([pscustomobject]@{
        rank                = 0
        symbol_alias        = $alias
        priority_score      = [int][math]::Round($score, 0)
        priority_band       = Get-PriorityBand -Score ([int][math]::Round($score, 0))
        trust_state         = $trustState
        trust_reason        = $trustReason
        cost_state          = $costState
        learning_sample_count = $sampleCount
        learning_bias       = [math]::Round($bias, 4)
        spread_points       = [math]::Round($spreadPoints, 2)
        live_opens_24h      = $liveOpens
        live_net_24h        = [math]::Round($liveNet, 2)
        recommended_action  = Get-RecommendedAction -TrustState $trustState -TrustReason $trustReason -CostState $costState -SampleCount $sampleCount -Net $liveNet -Opens $liveOpens
        latest_tester_path  = if ($null -ne $tester) { $tester.path } else { "" }
        latest_tester_result = if ($null -ne $tester) { $tester.result_label } else { "" }
        latest_tester_trust = if ($null -ne $tester) { $tester.trust_state } else { "" }
        latest_tester_cost  = if ($null -ne $tester) { $tester.cost_state } else { "" }
        latest_tester_sample = if ($null -ne $tester) { $tester.sample } else { 0 }
        latest_tester_bias  = if ($null -ne $tester) { [math]::Round([double]$tester.bias, 4) } else { 0.0 }
        latest_tester_pnl   = if ($null -ne $tester) { [math]::Round([double]$tester.pnl, 2) } else { 0.0 }
    })
}

$ranked = $items | Sort-Object `
    @{ Expression = "priority_score"; Descending = $true }, `
    @{ Expression = "live_opens_24h"; Descending = $true }, `
    @{ Expression = "learning_sample_count"; Descending = $false }
$rank = 1
foreach ($item in $ranked) {
    $item.rank = $rank
    $rank++
}

$report = [ordered]@{
    generated_at_local     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc       = (Get-Date).ToUniversalTime().ToString("o")
    runtime_window_start   = if ($null -ne $runtimeReview) { [string]$runtimeReview.window_start_local } else { "" }
    runtime_window_end     = if ($null -ne $runtimeReview) { [string]$runtimeReview.generated_local } else { "" }
    runtime_net_24h        = if ($null -ne $runtimeReview) { [double]$runtimeReview.net } else { 0.0 }
    runtime_active_24h     = if ($null -ne $runtimeReview) { [int]$runtimeReview.active_instruments } else { 0 }
    ranked_instruments     = $ranked
}

$jsonLatest = Join-Path $EvidenceDir "tuning_priority_latest.json"
$mdLatest = Join-Path $EvidenceDir "tuning_priority_latest.md"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$jsonStamped = Join-Path $EvidenceDir ("tuning_priority_{0}.json" -f $timestamp)
$mdStamped = Join-Path $EvidenceDir ("tuning_priority_{0}.md" -f $timestamp)

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonLatest -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonStamped -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Tuning Priority Latest")
$lines.Add("")
$lines.Add(("- generated_at_local: {0}" -f $report.generated_at_local))
$lines.Add(("- runtime_window: {0} -> {1}" -f $report.runtime_window_start, $report.runtime_window_end))
$lines.Add(("- runtime_net_24h: {0}" -f $report.runtime_net_24h))
$lines.Add("")
$lines.Add("## Top Queue")
$lines.Add("")
foreach ($item in $ranked | Select-Object -First 10) {
    $lines.Add(("- #{0} {1}: score={2}, band={3}, trust={4}, cost={5}, sample={6}, live_opens_24h={7}, live_net_24h={8}, action={9}" -f
        $item.rank,
        $item.symbol_alias,
        $item.priority_score,
        $item.priority_band,
        $item.trust_state,
        $item.cost_state,
        $item.learning_sample_count,
        $item.live_opens_24h,
        $item.live_net_24h,
        $item.recommended_action))
}
$lines.Add("")
$lines.Add("## Full Queue")
$lines.Add("")
foreach ($item in $ranked) {
    $lines.Add(("- #{0} {1}: score={2}, trust={3}, reason={4}, cost={5}, sample={6}, bias={7}, live_opens_24h={8}, live_net_24h={9}, tester={10}, action={11}" -f
        $item.rank,
        $item.symbol_alias,
        $item.priority_score,
        $item.trust_state,
        $item.trust_reason,
        $item.cost_state,
        $item.learning_sample_count,
        $item.learning_bias,
        $item.live_opens_24h,
        $item.live_net_24h,
        $item.latest_tester_result,
        $item.recommended_action))
}
($lines -join "`r`n") | Set-Content -LiteralPath $mdLatest -Encoding UTF8
($lines -join "`r`n") | Set-Content -LiteralPath $mdStamped -Encoding UTF8

$report
