param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 7200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$prepareScript = Join-Path $ProjectRoot "RUN\PREPARE_MT5_LAB_TERMINAL.ps1"
$batchScript = Join-Path $ProjectRoot "TOOLS\RUN_STRATEGY_TESTER_BATCH.ps1"
$priorityScript = Join-Path $ProjectRoot "RUN\APPLY_LAB_PROCESS_PRIORITIES.ps1"
foreach ($path in @($prepareScript, $batchScript, $priorityScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required script not found: $path"
    }
}

Write-Host "Preparing secondary MT5 weakest-first terminal..."
& $prepareScript -ProjectRoot $ProjectRoot -TerminalOrigin (Split-Path -Parent $Mt5Exe) -TerminalDataDir $TerminalDataDir | Out-Host

& $priorityScript | Out-Host

$symbols = @(
    "USDCHF",
    "USDCAD",
    "USDJPY",
    "NZDUSD",
    "GBPJPY",
    "COPPERUS",
    "SILVER",
    "DE30"
)

$workers = @(
    "weakest_mt5_01",
    "weakest_mt5_02",
    "weakest_mt5_03",
    "weakest_mt5_04",
    "weakest_mt5_05",
    "weakest_mt5_06",
    "weakest_mt5_07",
    "weakest_mt5_08"
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
    -BatchReportName "weakest_mt5_batch_latest" `
    -EvidenceSubdir "weakest_lab\primary"
