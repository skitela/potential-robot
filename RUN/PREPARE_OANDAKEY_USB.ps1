param(
    [string]$DriveLetter = "",
    [string]$Label = "OANDAKEY",
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5Login = "",
    [SecureString]$Mt5Password = $null,
    [string]$Mt5Server = "",
    [string]$Mt5Path = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [switch]$SkipLabelChange,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function ConvertTo-PlainText {
    param([SecureString]$Secret)
    if ($null -eq $Secret) { return "" }
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Resolve-UsbDriveLetter {
    param([string]$InputLetter = "")
    if (-not [string]::IsNullOrWhiteSpace($InputLetter)) {
        return $InputLetter.Trim().TrimEnd(":").ToUpperInvariant()
    }
    $removable = @(
        Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
        Where-Object { $_.DriveType -eq 2 -and $_.DeviceID } |
        ForEach-Object { ([string]$_.DeviceID).TrimEnd(":").ToUpperInvariant() } |
        Sort-Object -Unique
    )
    if ($removable.Count -eq 1) {
        return $removable[0]
    }
    if ($removable.Count -eq 0) {
        throw "Nie znaleziono pendrive (DriveType=2). Podaj -DriveLetter."
    }
    throw ("Wykryto wiele pendrive: {0}. Podaj -DriveLetter." -f ($removable -join ", "))
}

function Set-VolumeLabelSafe {
    param(
        [string]$Letter,
        [string]$NewLabel
    )
    try {
        Set-Volume -DriveLetter $Letter -NewFileSystemLabel $NewLabel -ErrorAction Stop | Out-Null
        return "set_volume"
    } catch {
        $cmd = "label {0}: {1}" -f $Letter, $NewLabel
        $null = cmd.exe /c $cmd
        if ($LASTEXITCODE -ne 0) {
            throw "Nie udalo sie ustawic etykiety woluminu."
        }
        return "cmd_label"
    }
}

$drive = Resolve-UsbDriveLetter -InputLetter $DriveLetter
$driveRoot = "{0}:\\" -f $drive

if (-not (Test-Path $driveRoot)) {
    throw ("Dysk nie istnieje: {0}" -f $driveRoot)
}

if ([string]::IsNullOrWhiteSpace($Mt5Login)) {
    $Mt5Login = Read-Host "Podaj MT5_LOGIN (numer konta)"
}
if ([string]::IsNullOrWhiteSpace($Mt5Server)) {
    $Mt5Server = Read-Host "Podaj MT5_SERVER"
}
if ($null -eq $Mt5Password) {
    $Mt5Password = Read-Host -AsSecureString "Podaj MT5_PASSWORD"
}

$plainPassword = ConvertTo-PlainText -Secret $Mt5Password
if ([string]::IsNullOrWhiteSpace($plainPassword)) {
    throw "MT5_PASSWORD nie moze byc pusty."
}

$tokenDir = Join-Path $driveRoot "TOKEN"
$envPath = Join-Path $tokenDir "BotKey.env"
$launcherCmd = Join-Path $driveRoot "START_OANDA_SYSTEM.cmd"
$launcherPs1 = Join-Path $driveRoot "START_OANDA_SYSTEM.ps1"

$envText = @(
    "# OANDA MT5 key file (USB only)",
    "# Wymagane przez BIN/safetybot.py",
    ("MT5_LOGIN={0}" -f $Mt5Login),
    ("MT5_PASSWORD={0}" -f $plainPassword),
    ("MT5_SERVER={0}" -f $Mt5Server),
    ("MT5_PATH={0}" -f $Mt5Path)
) -join [Environment]::NewLine

$launcherCmdText = @"
@echo off
setlocal EnableExtensions
set "ROOT=$Root"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%\RUN\START_WITH_OANDAKEY.ps1" -Root "%ROOT%"
set "RC=%ERRORLEVEL%"
if "%RC%"=="0" (
    echo START_OK
) else (
    echo START_FAIL rc=%RC%
)
endlocal & exit /b %RC%
"@

$launcherPs1Text = @"
param([string]`$Root = "$Root")
& powershell -NoProfile -ExecutionPolicy Bypass -File "`$Root\RUN\START_WITH_OANDAKEY.ps1" -Root "`$Root"
exit `$LASTEXITCODE
"@

$result = [ordered]@{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    drive = $drive
    label_target = $Label
    label_changed = $false
    label_method = ""
    wrote_env = $false
    wrote_launcher_cmd = $false
    wrote_launcher_ps1 = $false
    dry_run = [bool]$DryRun
}

try {
    if (-not $SkipLabelChange) {
        if ($DryRun) {
            $result.label_changed = $true
            $result.label_method = "dry_run"
        } else {
            $method = Set-VolumeLabelSafe -Letter $drive -NewLabel $Label
            $result.label_changed = $true
            $result.label_method = $method
        }
    } else {
        $result.label_method = "skipped"
    }

    if ($DryRun) {
        $result.wrote_env = $true
        $result.wrote_launcher_cmd = $true
        $result.wrote_launcher_ps1 = $true
    } else {
        New-Item -ItemType Directory -Force -Path $tokenDir | Out-Null
        Set-Content -Path $envPath -Value $envText -Encoding UTF8
        Set-Content -Path $launcherCmd -Value $launcherCmdText -Encoding ASCII
        Set-Content -Path $launcherPs1 -Value $launcherPs1Text -Encoding UTF8
        $result.wrote_env = $true
        $result.wrote_launcher_cmd = $true
        $result.wrote_launcher_ps1 = $true
    }

    $result.status = "PASS"
    $json = $result | ConvertTo-Json -Depth 8
    Write-Output $json
    exit 0
} finally {
    $plainPassword = ""
    Remove-Variable plainPassword -ErrorAction SilentlyContinue
}
