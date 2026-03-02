param(
    [switch]$DisableAutoOpen
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$scriptPath = Join-Path $workspaceRoot "TOOLS\\VoiceTypingSticky.ps1"
$startupDir = [Environment]::GetFolderPath("Startup")
$shortcutPath = Join-Path $startupDir "Voice Typing Sticky.lnk"
$stopFlag = Join-Path $workspaceRoot "RUN\\voice_typing_sticky.stop"

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Brak skryptu: $scriptPath"
}

Remove-Item -LiteralPath $stopFlag -Force -ErrorAction SilentlyContinue

$args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$scriptPath`""
if ($DisableAutoOpen) {
    $args += " -DisableAutoOpen"
}

$wsh = New-Object -ComObject WScript.Shell
$lnk = $wsh.CreateShortcut($shortcutPath)
$lnk.TargetPath = "powershell.exe"
$lnk.Arguments = $args
$lnk.WorkingDirectory = $workspaceRoot.Path
$lnk.WindowStyle = 7
$lnk.Description = "Utrzymaj pisanie glosowe (Win+H) zawsze na wierzchu"
$lnk.Save()

$running = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ieq "powershell.exe" -and $_.CommandLine -match "VoiceTypingSticky\\.ps1" }

if (-not $running) {
    Start-Process -FilePath "powershell.exe" -ArgumentList $args -WindowStyle Hidden
    Start-Sleep -Milliseconds 400
}

Write-Output "VOICE_TYPING_STICKY_ENABLED"
Write-Output "SCRIPT=$scriptPath"
Write-Output "SHORTCUT=$shortcutPath"
