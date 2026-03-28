param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe"
)

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_CANDIDATE_GAP_AUDIT.py"
& $ResearchPython $scriptPath "--project-root" $ProjectRoot "--research-root" $ResearchRoot
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
