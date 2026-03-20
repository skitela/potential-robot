$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT"
& (Join-Path $ProjectRoot "TOOLS\APPLY_SESSION_CAPITAL_COORDINATOR.ps1") -ProjectRoot $ProjectRoot -RuntimeProfile PAPER_LIVE
& (Join-Path $ProjectRoot "TOOLS\GENERATE_RUNTIME_CONTROL_SUMMARY.ps1") -ProjectRoot $ProjectRoot | Out-Null
