param([string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT")
$ErrorActionPreference = "Stop"
& (Join-Path $ProjectRoot "TOOLS\SET_RUNTIME_CONTROL_PL.ps1") -ProjectRoot $ProjectRoot -Zakres system -Tryb CLOSE_ONLY -Powod "WLACZONO_CLOSE_ONLY"
