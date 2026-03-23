param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [switch]$PortableTerminal,
    [int]$NearProfitCount = 3,
    [string[]]$ExcludedSymbolAliases = @(),
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$CalibrationWindowDays = 5,
    [int]$TimeoutSec = 14400,
    [ValidateSet(0,1,2,3)]
    [int]$Optimization = 2,
    [ValidateSet(0,1,2,3,4,5,6,7)]
    [int]$OptimizationCriterion = 6,
    [string]$EvidenceSubdir = "optimization_lab",
    [string]$BatchReportName = "near_profit_optimization_latest",
    [switch]$SkipResearchRefresh,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$ResearchPerfProfile = "Light"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

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

function Get-NearProfitOrderKey {
    param([object]$Entry)

    $qdmReady = if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "qdm_custom_pilot_ready") { [bool]$Entry.qdm_custom_pilot_ready } else { $false }
    $historicalTrustRank = 0
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "best_tester_trust") {
        $bestTesterTrust = [string]$Entry.best_tester_trust
        switch ($bestTesterTrust) {
            "LOW_SAMPLE" { $historicalTrustRank = 2 }
            "FOREFIELD_DIRTY" { $historicalTrustRank = 1 }
            "PAPER_CONVERSION_BLOCKED" { $historicalTrustRank = 1 }
            default { $historicalTrustRank = 0 }
        }
    }
    $currentTrustRank = 0
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "current_priority_trust") {
        $currentPriorityTrust = [string]$Entry.current_priority_trust
        $currentPriorityTrustReason = if ($Entry.PSObject.Properties.Name -contains "current_priority_trust_reason") { [string]$Entry.current_priority_trust_reason } else { "" }
        if ($currentPriorityTrust -eq "LOW_SAMPLE" -or $currentPriorityTrustReason -like "*LOW_SAMPLE*") {
            $currentTrustRank = 2
        }
        elseif (
            $currentPriorityTrust -eq "FOREFIELD_DIRTY" -or
            $currentPriorityTrust -eq "PAPER_CONVERSION_BLOCKED" -or
            $currentPriorityTrustReason -like "*FOREFIELD_DIRTY*" -or
            $currentPriorityTrustReason -like "*PAPER_CONVERSION_BLOCKED*"
        ) {
            $currentTrustRank = 1
        }
    }
    $trustRank = [Math]::Max($historicalTrustRank, $currentTrustRank)
    $currentCostRank = 2
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "current_priority_cost") {
        switch ([string]$Entry.current_priority_cost) {
            "LOW" { $currentCostRank = 0 }
            "MEDIUM" { $currentCostRank = 1 }
            "HIGH" { $currentCostRank = 2 }
            "NON_REPRESENTATIVE" { $currentCostRank = 3 }
            default { $currentCostRank = 2 }
        }
    }
    $spreadRank = 999999.0
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "current_priority_spread_points") {
        try {
            $spreadRank = [double]$Entry.current_priority_spread_points
        }
        catch {
            $spreadRank = 999999.0
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
    $liveNetRank = 0.0
    if ($null -ne $Entry -and $Entry.PSObject.Properties.Name -contains "live_net_24h") {
        try {
            $liveNetRank = -1.0 * [double]$Entry.live_net_24h
        }
        catch {
            $liveNetRank = 0.0
        }
    }

    return [pscustomobject]@{
        qdm_rank = if ($qdmReady) { 0 } else { 1 }
        trust_rank = $trustRank
        live_net_rank = $liveNetRank
        cost_rank = $currentCostRank
        spread_rank = $spreadRank
        pnl_rank = -1.0 * $bestTesterPnl
        priority_rank = $priorityRank
        symbol_alias = [string]$Entry.symbol_alias
    }
}

function Resolve-NearProfitDateWindow {
    param(
        [string]$FromDate,
        [string]$ToDate,
        [int]$CalibrationWindowDays
    )

    $effectiveFromDate = $FromDate
    $effectiveToDate = $ToDate
    $windowApplied = $false

    if ($CalibrationWindowDays -le 0) {
        return [pscustomobject]@{
            from_date = $effectiveFromDate
            to_date = $effectiveToDate
            window_applied = $windowApplied
            calibration_window_days = 0
        }
    }

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $dateFormat = "yyyy.MM.dd"
    $styles = [System.Globalization.DateTimeStyles]::None
    $parsedFromDate = [datetime]::MinValue
    $parsedToDate = [datetime]::MinValue

    if (
        [datetime]::TryParseExact($FromDate, $dateFormat, $culture, $styles, [ref]$parsedFromDate) -and
        [datetime]::TryParseExact($ToDate, $dateFormat, $culture, $styles, [ref]$parsedToDate)
    ) {
        $targetWindowDays = [Math]::Max(1, $CalibrationWindowDays)
        $candidateFromDate = $parsedToDate.AddDays(-1 * ($targetWindowDays - 1))
        if ($candidateFromDate -gt $parsedFromDate) {
            $effectiveFromDate = $candidateFromDate.ToString($dateFormat, $culture)
            $windowApplied = $true
        }
    }

    return [pscustomobject]@{
        from_date = $effectiveFromDate
        to_date = $effectiveToDate
        window_applied = $windowApplied
        calibration_window_days = [Math]::Max(1, $CalibrationWindowDays)
    }
}

if (-not (Test-Path -LiteralPath $ProfitTrackingPath)) {
    throw "Profit tracking file not found: $ProfitTrackingPath"
}

$profitTracking = Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nearProfit = @(
        $profitTracking.near_profit |
            Sort-Object `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).qdm_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).trust_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).live_net_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).cost_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).spread_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).pnl_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).priority_rank } }, `
                @{ Expression = { (Get-NearProfitOrderKey -Entry $_).symbol_alias } }
)
if ($nearProfit.Count -le 0) {
    throw "No near-profit symbols available in $ProfitTrackingPath"
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

$excludedAliasSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($alias in @($ExcludedSymbolAliases)) {
    if (-not [string]::IsNullOrWhiteSpace($alias)) {
        [void]$excludedAliasSet.Add((Convert-ToCanonicalSymbol -Symbol ([string]$alias)))
    }
}

$filteredNearProfit = if ($excludedAliasSet.Count -gt 0) {
    @(
        $nearProfit |
            Where-Object {
                -not $excludedAliasSet.Contains((Convert-ToCanonicalSymbol -Symbol ([string]$_.symbol_alias)))
            }
    )
} else {
    @($nearProfit)
}

if ($filteredNearProfit.Count -le 0) {
    $filteredNearProfit = @($nearProfit)
}

$selected = @($filteredNearProfit | Select-Object -First ([Math]::Max(1, $NearProfitCount)))
$symbolAliases = @($selected | ForEach-Object { Convert-ToCanonicalSymbol -Symbol ([string]$_.symbol_alias) } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($symbolAliases.Count -le 0) {
    throw "Near-profit list did not yield usable symbol aliases."
}

$dateWindow = Resolve-NearProfitDateWindow -FromDate $FromDate -ToDate $ToDate -CalibrationWindowDays $CalibrationWindowDays

$workerNames = @()
for ($i = 0; $i -lt $symbolAliases.Count; $i++) {
    $workerNames += ("opt_worker_{0}" -f ($i + 1))
}

$report = & (Join-Path $ProjectRoot "TOOLS\RUN_STRATEGY_TESTER_BATCH.ps1") `
    -ProjectRoot $ProjectRoot `
    -Mt5Exe $Mt5Exe `
    -TerminalDataDir $TerminalDataDir `
    -PortableTerminal:$PortableTerminal `
    -SymbolAliases $symbolAliases `
    -WorkerNames $workerNames `
    -TimeoutSec $TimeoutSec `
    -FromDate $dateWindow.from_date `
    -ToDate $dateWindow.to_date `
    -BatchReportName $BatchReportName `
    -EvidenceSubdir $EvidenceSubdir `
    -Optimization $Optimization `
    -OptimizationCriterion $OptimizationCriterion `
    -SkipResearchRefresh:$SkipResearchRefresh `
    -ResearchPerfProfile $ResearchPerfProfile

$report | Add-Member -NotePropertyName "requested_from_date" -NotePropertyValue $FromDate -Force
$report | Add-Member -NotePropertyName "requested_to_date" -NotePropertyValue $ToDate -Force
$report | Add-Member -NotePropertyName "effective_from_date" -NotePropertyValue ([string]$dateWindow.from_date) -Force
$report | Add-Member -NotePropertyName "effective_to_date" -NotePropertyValue ([string]$dateWindow.to_date) -Force
$report | Add-Member -NotePropertyName "calibration_window_days" -NotePropertyValue ([int]$dateWindow.calibration_window_days) -Force
$report | Add-Member -NotePropertyName "calibration_window_applied" -NotePropertyValue ([bool]$dateWindow.window_applied) -Force

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER"
if (-not [string]::IsNullOrWhiteSpace($EvidenceSubdir)) {
    $evidenceDir = Join-Path $evidenceDir $EvidenceSubdir
}
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$jsonPath = Join-Path $evidenceDir ($BatchReportName + ".json")
$mdPath = Join-Path $evidenceDir ($BatchReportName + ".md")
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$mdLines = @(
    "# Near Profit Optimization Latest",
    "",
    ("- requested_from_date: {0}" -f $report.requested_from_date),
    ("- requested_to_date: {0}" -f $report.requested_to_date),
    ("- effective_from_date: {0}" -f $report.effective_from_date),
    ("- effective_to_date: {0}" -f $report.effective_to_date),
    ("- calibration_window_days: {0}" -f $report.calibration_window_days),
    ("- calibration_window_applied: {0}" -f $report.calibration_window_applied)
)
foreach ($run in @($report.runs)) {
    $mdLines += ("- {0} / {1}: {2}, duration={3}, timeout_sec={4}, optimization_rows={5}" -f $run.symbol_alias, $run.sandbox_name, $run.result_label, $run.test_duration, $run.timeout_sec, $run.optimization_result_rows)
}
($mdLines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
