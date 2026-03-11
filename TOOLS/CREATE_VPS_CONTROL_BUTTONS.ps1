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

$controller = Join-Path $runtimeRoot "TOOLS\VPS_REMOTE_CONTROL.ps1"
$rdp = Join-Path $runtimeRoot "TOOLS\CONNECT_VPS_RDP.ps1"
$panel = Join-Path $runtimeRoot "TOOLS\OPEN_VPS_PROVIDER_PORTAL.ps1"
if (-not (Test-Path -LiteralPath $controller)) { throw "Brak skryptu: $controller" }
if (-not (Test-Path -LiteralPath $rdp)) { throw "Brak skryptu: $rdp" }
if (-not (Test-Path -LiteralPath $panel)) { throw "Brak skryptu: $panel" }

$wsh = New-Object -ComObject WScript.Shell

function New-OrUpdateShortcut {
    param(
        [string]$Name,
        [string]$TargetPath,
        [string]$Arguments,
        [string]$WorkingDirectory,
        [string]$IconLocation,
        [string]$Description
    )
    $lnk = Join-Path $DesktopPath ($Name + ".lnk")
    if ((Test-Path -LiteralPath $lnk) -and (-not $Force)) {
        Write-Output ("SKIP {0} (uzyj -Force aby nadpisac)" -f $lnk)
        return
    }
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $TargetPath
    $sc.Arguments = $Arguments
    $sc.WorkingDirectory = $WorkingDirectory
    $sc.WindowStyle = 1
    $sc.IconLocation = $IconLocation
    $sc.Description = $Description
    $sc.Save()
    Write-Output ("OK {0}" -f $lnk)
}

New-OrUpdateShortcut `
    -Name "VPS OANDA START" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$controller`" -Action start -Root `"$runtimeRoot`" -OpenRdp" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\imageres.dll,102" `
    -Description "Start systemu na VPS + otwarcie RDP"

New-OrUpdateShortcut `
    -Name "VPS OANDA STATUS" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$controller`" -Action status -Root `"$runtimeRoot`" -OpenRdp" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\imageres.dll,76" `
    -Description "Status systemu na VPS"

New-OrUpdateShortcut `
    -Name "VPS OANDA STOP" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$controller`" -Action stop -Root `"$runtimeRoot`" -OpenRdp" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\shell32.dll,132" `
    -Description "Stop systemu na VPS"

New-OrUpdateShortcut `
    -Name "VPS OANDA RESTART" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$controller`" -Action restart -Root `"$runtimeRoot`" -OpenRdp" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\imageres.dll,99" `
    -Description "Restart systemu na VPS + otwarcie RDP"

New-OrUpdateShortcut `
    -Name "VPS OANDA POLACZ" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$rdp`" -Root `"$runtimeRoot`"" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\mstsc.exe,0" `
    -Description "Szybkie polaczenie RDP z VPS"

New-OrUpdateShortcut `
    -Name "VPS OANDA POLACZ HASLO" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$rdp`" -Root `"$runtimeRoot`" -PromptForPassword" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\mstsc.exe,0" `
    -Description "RDP z wymuszeniem recznego wpisania hasla"

New-OrUpdateShortcut `
    -Name "VPS OANDA PANEL" `
    -TargetPath "powershell.exe" `
    -Arguments "-NoProfile -ExecutionPolicy Bypass -File `"$panel`"" `
    -WorkingDirectory $runtimeRoot `
    -IconLocation "$env:SystemRoot\System32\shell32.dll,220" `
    -Description "Panel Cyberfolks do wejscia przez VNC/noVNC i zarzadzania VPS"

Write-Output ("VPS_CONTROL_SHORTCUTS_READY desktop={0}" -f $DesktopPath)
exit 0
