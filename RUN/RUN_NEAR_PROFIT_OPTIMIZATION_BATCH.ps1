param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [int]$NearProfitCount = 3,
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 7200,
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

if (-not (Test-Path -LiteralPath $ProfitTrackingPath)) {
    throw "Profit tracking file not found: $ProfitTrackingPath"
}

$profitTracking = Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nearProfit = @($profitTracking.near_profit | Sort-Object priority_rank, symbol_alias)
if ($nearProfit.Count -le 0) {
    throw "No near-profit symbols available in $ProfitTrackingPath"
}

$selected = @($nearProfit | Select-Object -First ([Math]::Max(1, $NearProfitCount)))
$symbolAliases = @($selected | ForEach-Object { [string]$_.symbol_alias } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($symbolAliases.Count -le 0) {
    throw "Near-profit list did not yield usable symbol aliases."
}

$workerNames = @()
for ($i = 0; $i -lt $symbolAliases.Count; $i++) {
    $workerNames += ("opt_worker_{0}" -f ($i + 1))
}

& (Join-Path $ProjectRoot "TOOLS\RUN_STRATEGY_TESTER_BATCH.ps1") `
    -ProjectRoot $ProjectRoot `
    -Mt5Exe $Mt5Exe `
    -TerminalDataDir $TerminalDataDir `
    -SymbolAliases $symbolAliases `
    -WorkerNames $workerNames `
    -TimeoutSec $TimeoutSec `
    -FromDate $FromDate `
    -ToDate $ToDate `
    -BatchReportName $BatchReportName `
    -EvidenceSubdir $EvidenceSubdir `
    -Optimization $Optimization `
    -OptimizationCriterion $OptimizationCriterion `
    -SkipResearchRefresh:$SkipResearchRefresh `
    -ResearchPerfProfile $ResearchPerfProfile
