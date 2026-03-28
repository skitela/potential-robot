param(
    [ValidateSet("open-chat", "run", "status", "process-once")]
    [string]$Mode = "run",
    [string]$ConfigPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\orchestrator_config.json"
)

$python = "python"
$script = "C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\chatgpt_codex_orchestrator.py"

if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing orchestrator script: $script"
}

$args = @($script, $Mode, "--config", $ConfigPath)

if ($Mode -eq "run") {
    & $python @args
    exit $LASTEXITCODE
}

& $python @args
exit $LASTEXITCODE
