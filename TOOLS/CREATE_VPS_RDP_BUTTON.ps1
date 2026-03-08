param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$ShortcutName = "Polacz z VPS OANDA.lnk"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
$connectScript = Join-Path $runtimeRoot "TOOLS\CONNECT_VPS_RDP.ps1"
if (-not (Test-Path -LiteralPath $connectScript)) {
    throw "Brak skryptu: $connectScript"
}

$desktop = [Environment]::GetFolderPath("Desktop")
if ([string]::IsNullOrWhiteSpace($desktop)) {
    throw "Nie udalo sie odnalezc Pulpitu."
}

$shortcutPath = Join-Path $desktop $ShortcutName
$wsh = New-Object -ComObject WScript.Shell
$sc = $wsh.CreateShortcut($shortcutPath)
$sc.TargetPath = "powershell.exe"
$sc.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$connectScript`" -Root `"$runtimeRoot`""
$sc.WorkingDirectory = $runtimeRoot
$sc.IconLocation = "%SystemRoot%\System32\mstsc.exe,0"
$sc.Description = "Jednym kliknięciem łączy z VPS OANDA przez RDP"
$sc.Save()

Write-Output ("VPS_RDP_SHORTCUT_OK path={0}" -f $shortcutPath)
exit 0
