param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string[]]$SymbolAliases = @("GBPUSD","USDCAD","USDCHF"),
    [int]$TimeoutSec = 3600,
    [string[]]$WorkerNames = @("worker_main_1","worker_main_2","worker_main_3"),
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [string]$BatchReportName = "strategy_tester_batch_latest",
    [string]$EvidenceSubdir = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$results = @()
$repeatabilityReports = @()
for ($i = 0; $i -lt $SymbolAliases.Count; $i++) {
    $symbolAlias = $SymbolAliases[$i]
    $workerName = if ($i -lt $WorkerNames.Count) { $WorkerNames[$i] } else { "worker_$($i + 1)" }
    $run = & (Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1") `
        -ProjectRoot $ProjectRoot `
        -Mt5Exe $Mt5Exe `
        -TerminalDataDir $TerminalDataDir `
        -SymbolAlias $symbolAlias `
        -WorkerName $workerName `
        -TimeoutSec $TimeoutSec `
        -FromDate $FromDate `
        -ToDate $ToDate `
        -EvidenceSubdir $EvidenceSubdir
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
    ("- generated_at_utc: {0}" -f $report.generated_at_utc)
)
foreach ($run in $results) {
    $mdLines += ("- {0} / {1}: {2}, duration={3}, balance={4}" -f $run.symbol_alias, $run.sandbox_name, $run.result_label, $run.test_duration, $run.final_balance)
}
foreach ($item in $repeatabilityReports) {
    $mdLines += ("- repeatability {0}: {1}" -f $item.symbol_alias, $item.repeatability_status)
}
($mdLines -join "`r`n") | Set-Content -LiteralPath $mdPath -Encoding UTF8

$report
