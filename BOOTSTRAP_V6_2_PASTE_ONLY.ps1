# Wrapper for convenience: run bootstrap from repo root.
# Usage:
#   Set-ExecutionPolicy -Scope Process Bypass
#   .\BOOTSTRAP_V6_2_PASTE_ONLY.ps1 -Mode OFFLINE
#   .\BOOTSTRAP_V6_2_PASTE_ONLY.ps1 -Mode LIVE
& "$PSScriptRoot\RUN\BOOTSTRAP_V6_2.ps1" @args
