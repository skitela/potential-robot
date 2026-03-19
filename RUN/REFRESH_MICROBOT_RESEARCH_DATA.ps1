param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
$scriptPath = Join-Path $ProjectRoot "TOOLS\EXPORT_MT5_RESEARCH_DATA.py"
$perfScript = Join-Path $ProjectRoot "RUN\SET_MICROBOT_RESEARCH_PERF_ENV.ps1"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Export script not found: $scriptPath"
}
if (-not (Test-Path -LiteralPath $perfScript)) {
    throw "Research perf env script not found: $perfScript"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

& $perfScript -Profile $PerfProfile | Out-Host

& $pythonExe $scriptPath --project-root $ProjectRoot --common-root $CommonRoot --output-root $OutputRoot
