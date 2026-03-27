param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$ResearchRoot = "C:\TRADING_DATA\RESEARCH",
    [string]$ResearchPython = "C:\TRADING_TOOLS\MicroBotResearchEnv\Scripts\python.exe",
    [string]$CommonStateRoot = "",
    [string[]]$Symbols = @(),
    [switch]$ExportOnnx
)

$tailBridgeScript = Join-Path $ProjectRoot "RUN\BUILD_SERVER_PARITY_TAIL_BRIDGE.ps1"
$ledgerScript = Join-Path $ProjectRoot "RUN\BUILD_BROKER_NET_LEDGER.ps1"
$trainScript = Join-Path $ProjectRoot "TOOLS\TRAIN_PAPER_GATE_ACCEPTOR_MODEL.py"

& $tailBridgeScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

& $ledgerScript -ProjectRoot $ProjectRoot -ResearchRoot $ResearchRoot -ResearchPython $ResearchPython -CommonStateRoot $CommonStateRoot | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$args = @($trainScript, "--project-root", $ProjectRoot, "--research-root", $ResearchRoot, "--mode", "symbols")
if ($CommonStateRoot -ne "") {
    $args += @("--common-state-root", $CommonStateRoot)
}
if ($Symbols.Count -gt 0) {
    $args += "--symbols"
    $args += $Symbols
}
if ($ExportOnnx) {
    $args += "--export-onnx"
}

& $ResearchPython @args
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
