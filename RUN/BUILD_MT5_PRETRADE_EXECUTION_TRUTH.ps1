param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = "",
    [string]$SpoolRoot = ""
)

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_MT5_PRETRADE_EXECUTION_TRUTH.py"

$arguments = @(
    $scriptPath,
    "--project-root", $ProjectRoot,
    "--research-root", $ResearchRoot
)

if ($CommonStateRoot -ne "") {
    $arguments += @( "--common-state-root", $CommonStateRoot )
}

if ($SpoolRoot -ne "") {
    $arguments += @( "--spool-root", $SpoolRoot )
}

& $ResearchPython @arguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }