param(
    [string]$Root = "",
    [string]$DesktopPath = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
} else {
    $Root = (Resolve-Path $Root).Path
}

if ([string]::IsNullOrWhiteSpace($DesktopPath)) {
    $DesktopPath = [Environment]::GetFolderPath("Desktop")
}

New-Item -ItemType Directory -Force -Path $DesktopPath | Out-Null

$startBat = Join-Path $Root "start.bat"
$stopBat = Join-Path $Root "stop.bat"
if (-not (Test-Path $startBat)) { throw "Missing start.bat at $startBat" }
if (-not (Test-Path $stopBat)) { throw "Missing stop.bat at $stopBat" }

$wsh = New-Object -ComObject WScript.Shell

function New-OrUpdateShortcut {
    param(
        [string]$Name,
        [string]$TargetPath,
        [string]$WorkingDirectory,
        [string]$IconLocation
    )
    $lnk = Join-Path $DesktopPath ($Name + ".lnk")
    if ((Test-Path $lnk) -and (-not $Force)) {
        Write-Output ("SKIP {0} (exists; use -Force to overwrite)" -f $lnk)
        return
    }
    $sc = $wsh.CreateShortcut($lnk)
    $sc.TargetPath = $TargetPath
    $sc.WorkingDirectory = $WorkingDirectory
    $sc.WindowStyle = 1
    $sc.IconLocation = $IconLocation
    $sc.Save()
    Write-Output ("OK {0}" -f $lnk)
}

New-OrUpdateShortcut -Name "OANDA MT5 START" -TargetPath $startBat -WorkingDirectory $Root -IconLocation "$env:SystemRoot\System32\shell32.dll,167"
New-OrUpdateShortcut -Name "OANDA MT5 STOP" -TargetPath $stopBat -WorkingDirectory $Root -IconLocation "$env:SystemRoot\System32\shell32.dll,132"

Write-Output ("SHORTCUTS_READY desktop={0}" -f $DesktopPath)
