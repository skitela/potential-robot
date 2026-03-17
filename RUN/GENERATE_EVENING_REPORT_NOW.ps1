param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
)

$ErrorActionPreference = "Stop"

& (Join-Path $ProjectRoot "TOOLS\GENERATE_DAILY_SYSTEM_REPORTS.ps1") -ProjectRoot $ProjectRoot | Out-Null
& (Join-Path $ProjectRoot "TOOLS\GENERATE_EVENING_OWNER_REPORT.ps1") -ProjectRoot $ProjectRoot
