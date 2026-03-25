param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$ScriptPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\BUILD_INSTRUMENT_DATA_READINESS.py"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

foreach ($path in @($ResearchPython, $ScriptPath)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Required path not found: $path"
    }
}

& $ResearchPython $ScriptPath
Get-Content -LiteralPath (Join-Path $ProjectRoot "EVIDENCE\OPS\instrument_data_readiness_latest.json") -Raw -Encoding UTF8
