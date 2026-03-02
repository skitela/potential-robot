Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Voice Typing Sticky.lnk"
$stopFlag = Join-Path $workspaceRoot "RUN\\voice_typing_sticky.stop"

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $stopFlag) | Out-Null
Set-Content -LiteralPath $stopFlag -Value "stop" -Encoding UTF8

$targets = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq "powershell.exe" -and $_.CommandLine -match "VoiceTypingSticky\\.ps1" }

foreach ($p in $targets) {
    try {
        Stop-Process -Id ([int]$p.ProcessId) -Force -ErrorAction SilentlyContinue
    } catch {
    }
}

Remove-Item -LiteralPath $shortcutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue

Write-Output "VOICE_TYPING_STICKY_DISABLED"
Write-Output "SHORTCUT_REMOVED=$shortcutPath"
