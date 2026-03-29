param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_MT5_PRETRADE_EXECUTION_TRUTH_STATUS.py"

$arguments = @(
    $scriptPath,
    "--project-root", $ProjectRoot,
    "--research-root", $ResearchRoot
)

if ($CommonStateRoot -ne "") {
    $arguments += @("--common-state-root", $CommonStateRoot)
}

& $ResearchPython @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
