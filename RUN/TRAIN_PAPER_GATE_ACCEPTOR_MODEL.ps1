param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = "",
    [switch]$WithLocalStudents,
    [switch]$ExportOnnx
)

$mlOverlayCommonScript = Join-Path $ProjectRoot "RUN\ML_OVERLAY_COMMON.ps1"
$trainScript = Join-Path $ProjectRoot "TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py"

foreach ($path in @($mlOverlayCommonScript, $trainScript)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "MISSING_REQUIRED_FILE: $path"
    }
}

. $mlOverlayCommonScript
Invoke-MlOverlayPreTrain -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot -AllowFreshSkip | Out-Null

$args = @($trainScript, "--project-root", $ProjectRoot, "--research-root", $ResearchRoot, "--mode")
if ($WithLocalStudents) {
    $args += "full"
} else {
    $args += "global"
}
if ($CommonStateRoot -ne "") {
    $args += @("--common-state-root", $CommonStateRoot)
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
