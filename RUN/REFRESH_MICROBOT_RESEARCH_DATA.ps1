param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$EnvRoot = "C:\TRADING_TOOLS\MicroBotResearchEnv",
    [string]$CommonRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\Common\Files\MAKRO_I_MIKRO_BOT",
    [string]$OutputRoot = "C:\TRADING_DATA\RESEARCH"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$pythonExe = Join-Path $EnvRoot "Scripts\python.exe"
$scriptPath = Join-Path $ProjectRoot "TOOLS\EXPORT_MT5_RESEARCH_DATA.py"

if (-not (Test-Path -LiteralPath $pythonExe)) {
    throw "Research python not found: $pythonExe"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Export script not found: $scriptPath"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null

& $pythonExe $scriptPath --project-root $ProjectRoot --common-root $CommonRoot --output-root $OutputRoot
