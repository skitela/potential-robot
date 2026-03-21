param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string[]]$SymbolAliases = @("GBPUSD","USDCAD","USDCHF"),
    [int]$TimeoutSec = 3600,
    [string[]]$WorkerNames = @("worker_main_1","worker_main_2","worker_main_3"),
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [string]$BatchReportName = "strategy_tester_batch_latest",
    [string]$EvidenceSubdir = "",
    [ValidateSet(0,1,2,3)]
    [int]$Optimization = 0,
    [ValidateSet(0,1,2,3,4,5,6,7)]
    [int]$OptimizationCriterion = 6,
    [switch]$SkipResearchRefresh,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$ResearchPerfProfile = "Light"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-SymbolTimeoutSec {
    param(
        [string]$SymbolAlias,
        [int]$DefaultTimeoutSec
    )

    $overrides = @{
        "SILVER"    = 14400
        "GOLD"      = 10800
        "PLATIN"    = 10800
        "COPPER-US" = 10800
        "US500"     = 10800
        "DE30"      = 10800
    }

    if ($overrides.ContainsKey($SymbolAlias)) {
        return [Math]::Max($DefaultTimeoutSec, [int]$overrides[$SymbolAlias])
    }

    return $DefaultTimeoutSec
}

function Test-TesterRunNeedsRetry {
    param([object]$Run)

    if ($null -eq $Run) {
        return $false
    }

    $resultLabel = [string]$Run.result_label
    $sampleCount = 0
    $paperRows = 0

    try { $sampleCount = [int]$Run.learning_sample_count } catch { $sampleCount = 0 }
    try { $paperRows = [int]$Run.paper_open_rows } catch { $paperRows = 0 }

    return (
        $resultLabel -eq "timed_out" -and
        $sampleCount -le 0 -and
        $paperRows -le 0
    )
}

$results = @()
$repeatabilityReports = @()
for ($i = 0; $i -lt $SymbolAliases.Count; $i++) {
    $symbolAlias = $SymbolAliases[$i]
    $workerName = if ($i -lt $WorkerNames.Count) { $WorkerNames[$i] } else { "worker_$($i + 1)" }
    $effectiveTimeoutSec = Get-SymbolTimeoutSec -SymbolAlias $symbolAlias -DefaultTimeoutSec $TimeoutSec
    $run = & (Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1") `
        -ProjectRoot $ProjectRoot `
        -Mt5Exe $Mt5Exe `
        -TerminalDataDir $TerminalDataDir `
        -SymbolAlias $symbolAlias `
        -WorkerName $workerName `
        -TimeoutSec $effectiveTimeoutSec `
        -FromDate $FromDate `
        -ToDate $ToDate `
        -EvidenceSubdir $EvidenceSubdir `
        -Optimization $Optimization `
        -OptimizationCriterion $OptimizationCriterion `
        -SkipResearchRefresh:$SkipResearchRefresh `
        -ResearchPerfProfile $ResearchPerfProfile

    if (Test-TesterRunNeedsRetry -Run $run) {
        $retryTimeoutSec = [Math]::Max($effectiveTimeoutSec, [int]($effectiveTimeoutSec * 1.5))
        $run = & (Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1") `
            -ProjectRoot $ProjectRoot `
            -Mt5Exe $Mt5Exe `
            -TerminalDataDir $TerminalDataDir `
            -SymbolAlias $symbolAlias `
            -WorkerName $workerName `
            -TimeoutSec $retryTimeoutSec `
            -FromDate $FromDate `
            -ToDate $ToDate `
            -EvidenceSubdir $EvidenceSubdir `
            -Optimization $Optimization `
            -OptimizationCriterion $OptimizationCriterion `
            -SkipResearchRefresh:$SkipResearchRefresh `
            -ResearchPerfProfile $ResearchPerfProfile
    }

    $results += $run

    try {
        $repeatability = & (Join-Path $ProjectRoot "TOOLS\VALIDATE_STRATEGY_TESTER_REPEATABILITY.ps1") `
            -ProjectRoot $ProjectRoot `
            -SymbolAlias $symbolAlias
        $repeatabilityReports += $repeatability
    } catch {
    }
}

$report = [ordered]@{
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    symbols          = $SymbolAliases
    worker_names     = $WorkerNames
    optimization     = $Optimization
    optimization_criterion = $OptimizationCriterion
    runs             = $results
    repeatability    = $repeatabilityReports
}

$evidenceDir = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER"
if (-not [string]::IsNullOrWhiteSpace($EvidenceSubdir)) {
    $evidenceDir = Join-Path $evidenceDir $EvidenceSubdir
}
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null
$jsonPath = Join-Path $evidenceDir ($BatchReportName + ".json")
$mdPath = Join-Path $evidenceDir ($BatchReportName + ".md")
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$mdLines = @(
    "# Strategy Tester Batch Latest",
    "",
    ("- generated_at_utc: {0}" -f $report.generated_at_utc),
    ("- optimization: {0}" -f $report.optimization),
    ("- optimization_criterion: {0}" -f $report.optimization_criterion)
)
foreach ($run in $results) {
    $mdLines += ("- {0} / {1}: {2}, duration={3}, balance={4}" -f $run.symbol_alias, $run.sandbox_name, $run.result_label, $run.test_duration, $run.final_balance)
}
foreach ($item in $repeatabilityReports) {
    $mdLines += ("- repeatability {0}: {1}" -f $item.symbol_alias, $item.repeatability_status)
}
($mdLines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
