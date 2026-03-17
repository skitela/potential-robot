param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [string]$Period = "M5",
    [string]$FromDate = "2026.02.01",
    [string]$ToDate = "2026.03.16",
    [int]$Model = 4,
    [double]$Deposit = 10000.0,
    [int]$Leverage = 100,
    [int]$TimeoutSec = 1800,
    [switch]$RestoreMicrobotsProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

& (Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1") `
    -ProjectRoot $ProjectRoot `
    -Mt5Exe $Mt5Exe `
    -TerminalDataDir $TerminalDataDir `
    -SymbolAlias "NZDUSD" `
    -Period $Period `
    -FromDate $FromDate `
    -ToDate $ToDate `
    -Model $Model `
    -Deposit $Deposit `
    -Leverage $Leverage `
    -TimeoutSec $TimeoutSec `
    -RestoreMicrobotsProfile:$RestoreMicrobotsProfile
