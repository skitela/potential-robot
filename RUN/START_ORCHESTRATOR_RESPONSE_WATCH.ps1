param(
    [ValidateSet("run", "status", "process-once")]
    [string]$Mode = "run",
    [string]$ConfigPath = "C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\orchestrator_config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$python = "python"
$script = "C:\MAKRO_I_MIKRO_BOT\TOOLS\orchestrator\orchestrator_response_watch.py"

if (-not (Test-Path -LiteralPath $script)) {
    throw "Missing response watch script: $script"
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    throw "Missing orchestrator config: $ConfigPath"
}

& $python $script $Mode --config $ConfigPath
exit $LASTEXITCODE
