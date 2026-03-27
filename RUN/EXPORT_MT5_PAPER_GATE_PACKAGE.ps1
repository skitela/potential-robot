param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = "",
    [switch]$BootstrapIfMissing,
    [switch]$ExportOnnx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $ProjectRoot "TOOLS\EXPORT_MT5_PAPER_GATE_PACKAGE.py"
if (-not (Test-Path -LiteralPath $ResearchPython)) {
    throw "Research python not found: $ResearchPython"
}
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Package export script not found: $scriptPath"
}

$arguments = @($scriptPath, "--project-root", $ProjectRoot, "--research-root", $ResearchRoot)
if (-not [string]::IsNullOrWhiteSpace($CommonStateRoot)) {
    $arguments += @("--common-state-root", $CommonStateRoot)
}
if ($BootstrapIfMissing) {
    $arguments += "--bootstrap-if-missing"
}
if ($ExportOnnx) {
    $arguments += "--export-onnx"
}

& $ResearchPython @arguments
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
