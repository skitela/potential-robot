param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = ""
)

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_LOCAL_MODEL_READINESS_AUDIT.py"
$args = @(
    $scriptPath,
    "--project-root", $ProjectRoot,
    "--research-root", $ResearchRoot
)
if (-not [string]::IsNullOrWhiteSpace($CommonStateRoot)) {
    $args += @("--common-state-root", $CommonStateRoot)
}

& $ResearchPython @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
