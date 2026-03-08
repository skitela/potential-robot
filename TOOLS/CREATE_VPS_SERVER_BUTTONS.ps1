param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$DesktopPath = "",
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$runtimeRoot = (Resolve-Path -LiteralPath $Root -ErrorAction Stop).Path
if ([string]::IsNullOrWhiteSpace($DesktopPath)) {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
}
New-Item -ItemType Directory -Force -Path $DesktopPath | Out-Null

$startScript = Join-Path $runtimeRoot "RUN\START_WITH_OANDAKEY.ps1"
$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
if (-not (Test-Path -LiteralPath $startScript)) { throw "Brak skryptu: $startScript" }
if (-not (Test-Path -LiteralPath $systemControl)) { throw "Brak skryptu: $systemControl" }

$wsh = New-Object -ComObject WScript.Shell

function New-OrUpdateShortcut {
    param(
        [string]$Name,
        [string]$Arguments,
        [string]$IconLocation,
        [string]$Description
    )
    $lnk = Join-Path $DesktopPath ($Name + ".lnk")
    if ((Test-Path -LiteralPath $lnk) -and (-not $Force)) {
        Write-Output ("SKIP {0} (uzyj -Force aby nadpisac)" -f $lnk)
        return
    }
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = "powershell.exe"
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $runtimeRoot
    $sc.WindowStyle = 1
    $sc.IconLocation = $IconLocation
    $sc.Description = $Description
    $sc.Save()
    Write-Output ("OK {0}" -f $lnk)
}

New-OrUpdateShortcut `
    -Name "OANDA VPS START" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$startScript`" -Root `"$runtimeRoot`" -Profile safety_only" `
    -IconLocation "$env:SystemRoot\System32\imageres.dll,102" `
    -Description "Start systemu OANDA_MT5_SYSTEM na VPS"

New-OrUpdateShortcut `
    -Name "OANDA VPS STATUS" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$systemControl`" -Action status -Root `"$runtimeRoot`"" `
    -IconLocation "$env:SystemRoot\System32\imageres.dll,76" `
    -Description "Status systemu OANDA_MT5_SYSTEM na VPS"

New-OrUpdateShortcut `
    -Name "OANDA VPS STOP" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$systemControl`" -Action stop -Root `"$runtimeRoot`"" `
    -IconLocation "$env:SystemRoot\System32\shell32.dll,132" `
    -Description "Stop systemu OANDA_MT5_SYSTEM na VPS"

Write-Output ("VPS_SERVER_SHORTCUTS_READY desktop={0}" -f $DesktopPath)
exit 0
