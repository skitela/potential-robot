param(
    [string]$DriveLetter = "",
    [string]$Label = "OANDAKEY",
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5Login = "",
    [SecureString]$Mt5Password = $null,
    [string]$Mt5Server = "OANDATMS-MT5",
    [string]$Mt5Path = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [switch]$PlaintextPassword,
    [switch]$BootstrapOnly,
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

function ConvertTo-DpapiCipher {
    param([Parameter(Mandatory = $true)][SecureString]$Secret)
    return (ConvertFrom-SecureString -SecureString $Secret)
}

function Normalize-Mt5Server {
    param([string]$Server = "")
    $raw = [string]$Server
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return "OANDATMS-MT5"
    }
    $trim = $raw.Trim()
    $compact = ($trim -replace "\s+", "")
    $up = $compact.ToUpperInvariant()
    if ($up -eq "OANDATMS-MT5" -or $up -eq "OANDA-TMS-MT5" -or $up -eq "OANDATMSMT5") {
        return "OANDATMS-MT5"
    }
    return $trim
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

function Get-DriveFileSystem {
    param([string]$Letter)
    $letterNorm = $Letter.Trim().TrimEnd(":").ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($letterNorm)) { return "" }
    $dev = ($letterNorm + ":")

    try {
        $all = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and ([string]$_.Name).StartsWith($letterNorm + ":\") }
        $one = $all | Select-Object -First 1
        if ($null -ne $one -and -not [string]::IsNullOrWhiteSpace([string]$one.DriveFormat)) {
            return [string]$one.DriveFormat
        }
    } catch {
        # ignore
    }

    try {
        $vol = Get-Volume -DriveLetter $letterNorm -ErrorAction Stop | Select-Object -First 1
        if ($null -ne $vol -and -not [string]::IsNullOrWhiteSpace([string]$vol.FileSystem)) {
            return [string]$vol.FileSystem
        }
    } catch {
        # ignore
    }

    try {
        $d = Get-CimInstance Win32_LogicalDisk -ErrorAction Stop | Where-Object { ([string]$_.DeviceID).ToUpperInvariant() -eq $dev } | Select-Object -First 1
    } catch {
        $d = $null
    }
    if ($null -ne $d -and -not [string]::IsNullOrWhiteSpace([string]$d.FileSystem)) {
        return [string]$d.FileSystem
    }

    try {
        $wmic = & wmic logicaldisk where "DeviceID='$dev'" get FileSystem /value 2>$null
        foreach ($line in $wmic) {
            $s = [string]$line
            if ($s -match "^FileSystem=(.+)$") {
                $fs = [string]$Matches[1]
                if (-not [string]::IsNullOrWhiteSpace($fs)) {
                    return $fs.Trim()
                }
            }
        }
    } catch {
        # ignore
    }

    try {
        $out = & fsutil fsinfo volumeinfo $dev 2>$null
        foreach ($line in $out) {
            $s = [string]$line
            if ($s -match "File System Name\s*:\s*(.+)$") {
                $fs = [string]$Matches[1]
                if (-not [string]::IsNullOrWhiteSpace($fs)) {
                    return $fs.Trim()
                }
            }
        }
    } catch {
        # ignore
    }

    return ""
}

function Assert-DriveFormatReady {
    param([string]$Letter)
    $fs = (Get-DriveFileSystem -Letter $Letter).Trim()
    if ([string]::IsNullOrWhiteSpace($fs)) {
        return [ordered]@{
            ok = $true
            filesystem = "UNKNOWN"
            verification = "UNVERIFIED"
            reason = "filesystem_unknown"
        }
    }
    $fsUp = $fs.ToUpperInvariant()
    if ($fsUp -eq "RAW") {
        throw ("Pendrive {0}: ma format RAW. Sformatuj go na NTFS/FAT32/exFAT." -f $Letter)
    }
    if (@("NTFS", "FAT32", "EXFAT", "FAT") -notcontains $fsUp) {
        throw ("Pendrive {0}: ma nieobslugiwany format '{1}'. Uzyj NTFS/FAT32/exFAT." -f $Letter, $fs)
    }
    return [ordered]@{
        ok = $true
        filesystem = $fs
        verification = "VERIFIED"
        reason = ""
    }
}

$drive = Resolve-UsbDriveLetter -InputLetter $DriveLetter
$driveRoot = "{0}:\\" -f $drive

if (-not (Test-Path $driveRoot)) {
    throw ("Dysk nie istnieje: {0}" -f $driveRoot)
}

if ([string]::IsNullOrWhiteSpace($Mt5Server)) {
    $Mt5Server = "OANDATMS-MT5"
}
$Mt5Server = Normalize-Mt5Server -Server $Mt5Server
$plainPassword = ""
$passwordMode = "PROMPT_ON_FIRST_START"
$passwordLine = "MT5_PASSWORD_DPAPI="
$dpapiCipher = ""

if (-not $BootstrapOnly) {
    if ([string]::IsNullOrWhiteSpace($Mt5Login)) {
        $Mt5Login = Read-Host "Podaj MT5_LOGIN (numer konta)"
    }
    if ([string]::IsNullOrWhiteSpace($Mt5Server)) {
        $srvIn = Read-Host "Podaj MT5_SERVER (Enter = OANDATMS-MT5)"
        if (-not [string]::IsNullOrWhiteSpace($srvIn)) {
            $Mt5Server = $srvIn.Trim()
        }
    }
    $Mt5Server = Normalize-Mt5Server -Server $Mt5Server
    if ($null -eq $Mt5Password) {
        $Mt5Password = Read-Host -AsSecureString "Podaj MT5_PASSWORD"
    }

    $plainPassword = ConvertTo-PlainText -Secret $Mt5Password
    if ([string]::IsNullOrWhiteSpace($plainPassword)) {
        throw "MT5_PASSWORD nie moze byc pusty."
    }
    if ($PlaintextPassword) {
        $passwordMode = "PLAINTEXT"
        $passwordLine = ("MT5_PASSWORD={0}" -f $plainPassword)
    } else {
        $passwordMode = "DPAPI_CURRENT_USER"
        $dpapiCipher = ConvertTo-DpapiCipher -Secret $Mt5Password
        if ([string]::IsNullOrWhiteSpace($dpapiCipher)) {
            throw "Nie udalo sie zaszyfrowac MT5_PASSWORD przez DPAPI."
        }
        $passwordLine = ("MT5_PASSWORD_DPAPI={0}" -f $dpapiCipher)
    }
} else {
    if ([string]::IsNullOrWhiteSpace($Mt5Login)) {
        $Mt5Login = "<UZUPELNIJ_PRZY_PIERWSZYM_STARCIE>"
    }
}

$tokenDir = Join-Path $driveRoot "TOKEN"
$envPath = Join-Path $tokenDir "BotKey.env"
$launcherCmd = Join-Path $driveRoot "START_OANDA_SYSTEM.cmd"
$launcherPs1 = Join-Path $driveRoot "START_OANDA_SYSTEM.ps1"

$envText = @(
    "# OANDA MT5 key file (USB only)",
    "# Wymagane przez BIN/safetybot.py",
    "# Uwaga: DPAPI_CURRENT_USER dziala tylko na tym samym laptopie i koncie Windows",
    ("MT5_LOGIN={0}" -f $Mt5Login),
    ("MT5_PASSWORD_MODE={0}" -f $passwordMode),
    $passwordLine,
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
    filesystem = ""
    bootstrap_only = [bool]$BootstrapOnly
    password_mode = $passwordMode
    format_check = ""
    format_reason = ""
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

    $fmt = Assert-DriveFormatReady -Letter $drive
    $result.filesystem = [string]$fmt.filesystem
    $result.format_check = [string]$fmt.verification
    $result.format_reason = [string]$fmt.reason

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
    $dpapiCipher = ""
    $plainPassword = ""
    Remove-Variable dpapiCipher, plainPassword -ErrorAction SilentlyContinue
}
