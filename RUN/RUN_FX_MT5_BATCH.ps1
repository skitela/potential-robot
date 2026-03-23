param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 3600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$batchScript = Join-Path $ProjectRoot "TOOLS\RUN_STRATEGY_TESTER_BATCH.ps1"
$priorityScript = Join-Path $ProjectRoot "RUN\APPLY_LAB_PROCESS_PRIORITIES.ps1"
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "Strategy tester batch script not found: $batchScript"
}
if (-not (Test-Path -LiteralPath $priorityScript)) {
    throw "Priority script not found: $priorityScript"
}

& $priorityScript | Out-Host

$symbols = @(
    "EURUSD",
    "GBPUSD",
    "AUDUSD",
    "USDJPY",
    "USDCHF",
    "USDCAD",
    "NZDUSD",
    "EURJPY",
    "GBPJPY",
    "EURAUD"
)

$workers = @(
    "fx_mt5_01",
    "fx_mt5_02",
    "fx_mt5_03",
    "fx_mt5_04",
    "fx_mt5_05",
    "fx_mt5_06",
    "fx_mt5_07",
    "fx_mt5_08",
    "fx_mt5_09",
    "fx_mt5_10",
    "fx_mt5_11"
)

& $batchScript `
    -ProjectRoot $ProjectRoot `
    -Mt5Exe $Mt5Exe `
    -TerminalDataDir $TerminalDataDir `
    -SymbolAliases $symbols `
    -WorkerNames $workers `
    -TimeoutSec $TimeoutSec `
    -FromDate $FromDate `
    -ToDate $ToDate `
    -BatchReportName "fx_mt5_primary_batch_latest" `
    -EvidenceSubdir "fx_lab\primary"
