param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$scriptPath = Join-Path $ProjectRoot "TOOLS\RUN_RUNTIME_WATCHDOG_PL.ps1"
if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Brak skryptu watchdoga: $scriptPath"
}

& $scriptPath -ProjectRoot $ProjectRoot
