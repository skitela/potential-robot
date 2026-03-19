param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 3600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$prepareScript = Join-Path $ProjectRoot "RUN\PREPARE_MT5_LAB_TERMINAL.ps1"
$batchScript = Join-Path $ProjectRoot "TOOLS\RUN_STRATEGY_TESTER_BATCH.ps1"
$priorityScript = Join-Path $ProjectRoot "RUN\APPLY_LAB_PROCESS_PRIORITIES.ps1"

if (-not (Test-Path -LiteralPath $prepareScript)) {
    throw "Prepare script not found: $prepareScript"
}
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "Strategy tester batch script not found: $batchScript"
}
if (-not (Test-Path -LiteralPath $priorityScript)) {
    throw "Priority script not found: $priorityScript"
}

Write-Host "Preparing secondary MT5 lab terminal..."
& $prepareScript -ProjectRoot $ProjectRoot -TerminalOrigin (Split-Path -Parent $Mt5Exe) -TerminalDataDir $TerminalDataDir | Out-Host

& $priorityScript | Out-Host

$symbols = @(
    "USDJPY",
    "USDCHF",
    "USDCAD",
    "EURJPY",
    "GBPJPY"
)

$workers = @(
    "fx_mt5_secondary_01",
    "fx_mt5_secondary_02",
    "fx_mt5_secondary_03",
    "fx_mt5_secondary_04",
    "fx_mt5_secondary_05"
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
    -BatchReportName "fx_mt5_secondary_batch_latest" `
    -EvidenceSubdir "fx_lab\secondary"
