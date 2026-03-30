param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

& (Join-Path $ProjectRoot "TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1") -ProjectRoot $ProjectRoot -RuntimeProfile BROKER_PARITY_FIRST_WAVE
