param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = "",
    [switch]$FailOnRolloutBlock
)

$scriptPath = Join-Path $ProjectRoot "TOOLS\BUILD_ML_OVERLAY_AUDIT.py"
$args = @(
    $scriptPath,
    "--project-root", $ProjectRoot,
    "--research-root", $ResearchRoot
)
if (-not [string]::IsNullOrWhiteSpace($CommonStateRoot)) {
    $args += @("--common-state-root", $CommonStateRoot)
}
if ($FailOnRolloutBlock) {
    $args += "--fail-on-rollout-block"
}

& $ResearchPython @args
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
