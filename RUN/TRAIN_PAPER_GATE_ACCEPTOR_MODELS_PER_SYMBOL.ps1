param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = "",
    [string[]]$Symbols = @(),
    [string]$SymbolGroup = "",
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$PerfProfile = "ConcurrentLab",
    [switch]$ExportOnnx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$mlOverlayCommonScript = Join-Path $ProjectRoot "RUN\ML_OVERLAY_COMMON.ps1"
$trainScript = Join-Path $ProjectRoot "TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py"

foreach ($path in @($mlOverlayCommonScript, $trainScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "MISSING_REQUIRED_FILE: $path"
    }
}

. $mlOverlayCommonScript
Invoke-MlOverlayPreTrain -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot -AllowFreshSkip | Out-Null

$args = @($trainScript, "--project-root", $ProjectRoot, "--research-root", $ResearchRoot, "--mode", "symbols")
if ($CommonStateRoot -ne "") {
    $args += @("--common-state-root", $CommonStateRoot)
}
if ($Symbols.Count -gt 0) {
    $args += "--symbols"
    $args += $Symbols
}
if (-not [string]::IsNullOrWhiteSpace($SymbolGroup)) {
    $args += @("--symbol-group", $SymbolGroup)
}
if ($ExportOnnx) {
    $args += "--export-onnx"
}

& $ResearchPython @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($ExportOnnx) {
    Invoke-MlOverlayPostTrain -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot -ExportOnPromotionOnly | Out-Null
}
else {
    Invoke-MlOverlayAudit -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot | Out-Null
}
