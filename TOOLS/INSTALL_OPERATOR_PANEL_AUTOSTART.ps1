param(
    [string]$Root = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

$startupDir = [Environment]::GetFolderPath("Startup")
New-Item -ItemType Directory -Force -Path $startupDir | Out-Null

$launcher = Join-Path $Root "TOOLS\START_OPERATOR_PANEL.ps1"
if (-not (Test-Path $launcher)) {
    throw "Missing launcher script: $launcher"
}

$linkPath = Join-Path $startupDir "OANDA Operator Panel.lnk"
if ((Test-Path $linkPath) -and (-not $Force)) {
    Write-Output ("AUTOSTART_EXISTS {0}" -f $linkPath)
    exit 0
}

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($linkPath)
$shortcut.TargetPath = "powershell.exe"
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -Root `"$Root`""
$shortcut.WorkingDirectory = $Root
$shortcut.IconLocation = "$env:SystemRoot\System32\shell32.dll,167"
$shortcut.WindowStyle = 1
$shortcut.Save()

Write-Output ("AUTOSTART_READY {0}" -f $linkPath)

