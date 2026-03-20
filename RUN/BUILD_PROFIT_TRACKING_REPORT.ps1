param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$RuntimeReviewPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\paper_live_feedback_latest.json",
    [string]$PriorityPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\tuning_priority_latest.json",
    [string]$TesterEvidenceRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER",
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

        $symbolAlias = Normalize-Alias ([string]$summary.symbol_alias)
        if ([string]::IsNullOrWhiteSpace($symbolAlias)) {
            continue
        }

        $pnl = Convert-ToDoubleOrNull $summary.realized_pnl_lifetime
        if ($null -eq $pnl) {
            continue
        }

        $row = [pscustomobject]@{
            symbol_alias = $symbolAlias
            pnl          = $pnl
            result_label = [string]$summary.result_label
            trust_state  = [string]$summary.trust_state
            source_path  = $file.FullName
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

$runtimeBySymbol = @{}
foreach ($item in @($runtime.key_instruments)) {
    $runtimeBySymbol[[string]$item.instrument] = $item
}
foreach ($item in @($runtime.top_active)) {
    if (-not $runtimeBySymbol.ContainsKey([string]$item.instrument)) {
        $runtimeBySymbol[[string]$item.instrument] = $item
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

    $bestTesterPnl = if ($tester) { $tester.pnl } else { Convert-ToDoubleOrNull $item.latest_tester_pnl }
    $hasTesterBaseline = $false
    if ($tester) {
        $hasTesterBaseline = $true
    }
    elseif (($item.PSObject.Properties.Name -contains 'latest_tester_path') -and -not [string]::IsNullOrWhiteSpace([string]$item.latest_tester_path)) {
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
        best_tester_pnl   = $bestTesterPnl
        best_tester_trust = if ($tester) { $tester.trust_state } else { [string]$item.latest_tester_trust }
        best_tester_path  = if ($tester) { $tester.source_path } else { [string]$item.latest_tester_path }
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
        $lines.Add(("- {0}: best_tester_pnl={1} trust={2}" -f $item.symbol_alias, $item.best_tester_pnl, $item.best_tester_trust))
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
        $lines.Add(("- {0}: best_tester_pnl={1} live_opens={2} live_closes={3} live_wins={4} live_losses={5} live_net_24h={6} action={7}" -f $item.symbol_alias, $item.best_tester_pnl, $item.live_opens_24h, $item.live_closes_24h, $item.live_wins_24h, $item.live_losses_24h, $item.live_net_24h, $item.recommended_action))
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
