param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$tool = Join-Path $ProjectRoot "TOOLS\PREPARE_MT5_ROLLOUT.ps1"
if (-not (Test-Path -LiteralPath $tool)) {
    throw "Missing rollout tool: $tool"
}

Write-Host "Running MT5 rollout preflight from RUN wrapper..." -ForegroundColor Cyan
& $tool -ProjectRoot $ProjectRoot
