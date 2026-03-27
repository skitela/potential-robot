param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = ""
)

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_BROKER_NET_LEDGER.py"

$args = @($scriptPath, "--project-root", $ProjectRoot, "--research-root", $ResearchRoot)
if ($CommonStateRoot -ne "") {
    $args += @("--common-state-root", $CommonStateRoot)
}

& $ResearchPython @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
