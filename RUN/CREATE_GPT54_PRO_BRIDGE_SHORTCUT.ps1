param(
    [string]$RepoRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$DesktopPath = "",
    [string]$ShortcutName = "GPT 5.4 PRO MOST.lnk"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$launcherPath = Join-Path $RepoRoot "URUCHOM_GPT54_PRO_MOST.cmd"
if (-not (Test-Path -LiteralPath $launcherPath)) {
    throw "Missing launcher: $launcherPath"
}

if ([string]::IsNullOrWhiteSpace($DesktopPath)) {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
}

New-Item -ItemType Directory -Force -Path $DesktopPath | Out-Null
$shortcutPath = Join-Path $DesktopPath $ShortcutName

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcherPath
$shortcut.WorkingDirectory = $RepoRoot
$shortcut.Description = "Jedno klikniecie do panelu mostu GPT-5.4 Pro"
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,220"
$shortcut.Save()

[pscustomobject]@{
    shortcut_path = $shortcutPath
    launcher_path = $launcherPath
    working_directory = $RepoRoot
} | Format-List