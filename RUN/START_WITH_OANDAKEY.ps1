param(
    [string]$Root = "",
    [string]$Label = "OANDAKEY",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$DEFAULT_MT5_SERVER = "OANDATMS-MT5"
$DEFAULT_MT5_PATH = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe"
$ALLOWED_FILESYSTEMS = @("NTFS", "FAT32", "EXFAT", "FAT")

function Resolve-Root {
    param([string]$InputRoot = "")
    if ([string]::IsNullOrWhiteSpace($InputRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $InputRoot).Path
}

function Get-PythonExe {
    param([string]$RuntimeRoot = "")

    $candidates = @(
        "C:\OANDA_VENV\.venv\Scripts\python.exe",
        (Join-Path $RuntimeRoot ".venv\Scripts\python.exe"),
        "C:\Program Files\Python312\python.exe"
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
            return $candidate
        }
    }

    try {
        $py312 = (& py -3.12 -c "import sys; print(sys.executable)" 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $py312Path = [string]($py312 | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($py312Path) -and (Test-Path $py312Path.Trim())) {
                return $py312Path.Trim()
            }
        }
    } catch {
        # plain python fallback below
    }

    return "python"
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Object
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = "$Path.tmp"
    $data = $Object | ConvertTo-Json -Depth 8
    try {
        $data | Set-Content -Encoding UTF8 -Path $tmp
        Move-Item -Force $tmp $Path
        return $true
    } catch {
        try {
            $data | Set-Content -Encoding UTF8 -Path $Path
            return $true
        } catch {
            return $false
        } finally {
            try { Remove-Item -Force $tmp -ErrorAction SilentlyContinue } catch {}
        }
    }
}

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

function Is-PlaceholderValue {
    param([string]$Value = "")
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }
    $v = $Value.Trim().ToUpperInvariant()
    return @(
        "<UZUPELNIJ_PRZY_PIERWSZYM_STARCIE>",
        "PROMPT_ON_FIRST_START",
        "TODO",
        "CHANGE_ME"
    ) -contains $v
}

function Normalize-Mt5Server {
    param([string]$Server = "")
    $raw = [string]$Server
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $DEFAULT_MT5_SERVER
    }
    $trim = $raw.Trim()
    $compact = ($trim -replace "\s+", "")
    $up = $compact.ToUpperInvariant()
    if ($up -eq "OANDATMS-MT5" -or $up -eq "OANDA-TMS-MT5" -or $up -eq "OANDATMSMT5") {
        return $DEFAULT_MT5_SERVER
    }
    return $trim
}

function Get-RemovableDrives {
    try {
        return @(
            Get-CimInstance Win32_LogicalDisk -ErrorAction Stop |
            Where-Object { $_.DriveType -eq 2 -and $_.DeviceID } |
            Select-Object DeviceID, VolumeName, FileSystem
        )
    } catch {
        return @()
    }
}

function Get-KeyDriveByLabel {
    param([string]$ExpectedLabel = "OANDAKEY")

    $safe = ($ExpectedLabel -replace "'", "''").Trim()
    $drive = ""

    try {
        $v = Get-Volume | Where-Object { $_.FileSystemLabel -eq $safe } | Select-Object -First 1
        if ($null -ne $v -and $v.DriveLetter) {
            $drive = [string]$v.DriveLetter
        }
    } catch {
        $drive = ""
    }

    if ([string]::IsNullOrWhiteSpace($drive)) {
        try {
            $all = [System.IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady }
            foreach ($d in $all) {
                $lbl = [string]$d.VolumeLabel
                if ($lbl.Trim().ToUpperInvariant() -eq $ExpectedLabel.Trim().ToUpperInvariant()) {
                    $name = [string]$d.Name
                    if (-not [string]::IsNullOrWhiteSpace($name)) {
                        $drive = $name.Substring(0, 1)
                        break
                    }
                }
            }
        } catch {
            $drive = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($drive)) {
        try {
            $wmic = & wmic logicaldisk get DeviceID,VolumeName 2>$null
            foreach ($line in $wmic) {
                $s = [string]$line
                if ([string]::IsNullOrWhiteSpace($s)) { continue }
                if ($s -match "DeviceID") { continue }
                $parts = ($s.Trim() -split "\s+")
                if ($parts.Count -lt 2) { continue }
                $dev = [string]$parts[0]
                $vol = [string]::Join(" ", $parts[1..($parts.Count - 1)])
                if ($vol.Trim().ToUpperInvariant() -eq $ExpectedLabel.Trim().ToUpperInvariant()) {
                    $drive = $dev.TrimEnd(":")
                    break
                }
            }
        } catch {
            $drive = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($drive)) {
        return $null
    }
    return ("{0}:" -f $drive.TrimEnd(":"))
}

function Set-VolumeLabelSafe {
    param(
        [Parameter(Mandatory = $true)][string]$Drive,
        [Parameter(Mandatory = $true)][string]$NewLabel
    )
    $letter = $Drive.Trim().TrimEnd(":")
    try {
        Set-Volume -DriveLetter $letter -NewFileSystemLabel $NewLabel -ErrorAction Stop | Out-Null
        return "set_volume"
    } catch {
        $null = cmd.exe /c ("label {0}: {1}" -f $letter, $NewLabel)
        if ($LASTEXITCODE -ne 0) {
            throw "Nie udalo sie ustawic etykiety woluminu."
        }
        return "cmd_label"
    }
}

function Resolve-KeyDrive {
    param(
        [string]$ExpectedLabel = "OANDAKEY",
        [switch]$Dry
    )
    $drive = Get-KeyDriveByLabel -ExpectedLabel $ExpectedLabel
    if (-not [string]::IsNullOrWhiteSpace($drive)) {
        return [ordered]@{
            ok = $true
            drive = $drive
            label_state = "label_ok"
        }
    }

    $rem = @(Get-RemovableDrives)
    if ($rem.Count -eq 0) {
        return [ordered]@{
            ok = $false
            reason = "no_removable_drive"
        }
    }
    if ($rem.Count -gt 1) {
        $cands = @($rem | ForEach-Object { [string]$_.DeviceID })
        return [ordered]@{
            ok = $false
            reason = "multiple_removable_no_label"
            candidates = $cands
        }
    }

    $single = [string]$rem[0].DeviceID
    if ([string]::IsNullOrWhiteSpace($single)) {
        return [ordered]@{
            ok = $false
            reason = "removable_drive_unknown"
        }
    }
    if ($Dry) {
        return [ordered]@{
            ok = $true
            drive = ($single.Trim().TrimEnd(":") + ":")
            label_state = "dry_run_label_assign"
            label_method = "dry_run"
        }
    }

    $method = Set-VolumeLabelSafe -Drive $single -NewLabel $ExpectedLabel
    return [ordered]@{
        ok = $true
        drive = ($single.Trim().TrimEnd(":") + ":")
        label_state = "label_assigned"
        label_method = $method
    }
}

function Get-DriveFileSystem {
    param([Parameter(Mandatory = $true)][string]$Drive)
    $letterNorm = $Drive.Trim().TrimEnd(":").ToUpperInvariant()
    if ([string]::IsNullOrWhiteSpace($letterNorm)) { return "" }
    $dev = $letterNorm + ":"

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
        $d = Get-CimInstance Win32_LogicalDisk -ErrorAction Stop | Where-Object { [string]$_.DeviceID -eq $dev } | Select-Object -First 1
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
    param(
        [Parameter(Mandatory = $true)][string]$Drive,
        [string[]]$AllowedFs = @("NTFS", "FAT32", "EXFAT", "FAT")
    )
    $fs = (Get-DriveFileSystem -Drive $Drive).Trim()
    if ([string]::IsNullOrWhiteSpace($fs)) {
        return [ordered]@{
            ok = $true
            reason = "filesystem_unknown"
            filesystem = "UNKNOWN"
            verification = "UNVERIFIED"
        }
    }
    $fsUp = $fs.ToUpperInvariant()
    if ($fsUp -eq "RAW") {
        return [ordered]@{
            ok = $false
            reason = "drive_not_formatted_raw"
            filesystem = $fs
            verification = "VERIFIED"
        }
    }
    if (-not ($AllowedFs -contains $fsUp)) {
        return [ordered]@{
            ok = $false
            reason = "unsupported_filesystem"
            filesystem = $fs
            verification = "VERIFIED"
        }
    }
    return [ordered]@{
        ok = $true
        filesystem = $fs
        verification = "VERIFIED"
        reason = ""
    }
}

function Read-JsonFileSafe {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function Start-RiskPopupGuard {
    param([string]$RuntimeRoot)
    $scriptPath = Join-Path $RuntimeRoot "TOOLS\mt5_risk_popup_guard.ps1"
    $pidPath = Join-Path $RuntimeRoot "RUN\mt5_risk_guard.pid"
    if (-not (Test-Path $scriptPath)) {
        return [ordered]@{
            ok = $false
            status = "missing_script"
            script = $scriptPath
        }
    }

    $pidObj = Read-JsonFileSafe -Path $pidPath
    $existingPid = $null
    if ($null -ne $pidObj -and $null -ne $pidObj.pid) {
        try { $existingPid = [int]$pidObj.pid } catch { $existingPid = $null }
    }
    if ($null -ne $existingPid) {
        $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($null -ne $proc) {
            return [ordered]@{
                ok = $true
                status = "already_running"
                pid = $existingPid
                pid_file = $pidPath
            }
        }
    }

    try {
        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-Root", $RuntimeRoot
        )
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WorkingDirectory $RuntimeRoot -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 400
        return [ordered]@{
            ok = $true
            status = "started"
            pid = [int]$proc.Id
            pid_file = $pidPath
        }
    } catch {
        return [ordered]@{
            ok = $false
            status = "start_failed"
            error = $_.Exception.Message
            script = $scriptPath
        }
    }
}

function Start-Mt5SessionGuard {
    param([string]$RuntimeRoot)
    $scriptPath = Join-Path $RuntimeRoot "TOOLS\mt5_session_guard.ps1"
    $pidPath = Join-Path $RuntimeRoot "RUN\mt5_session_guard.pid"
    $statusPath = Join-Path $RuntimeRoot "RUN\mt5_session_guard_status.json"
    if (-not (Test-Path $scriptPath)) {
        return [ordered]@{
            ok = $false
            status = "missing_script"
            script = $scriptPath
        }
    }

    $pidObj = Read-JsonFileSafe -Path $pidPath
    $existingPid = $null
    if ($null -ne $pidObj -and $null -ne $pidObj.pid) {
        try { $existingPid = [int]$pidObj.pid } catch { $existingPid = $null }
    }
    if ($null -ne $existingPid) {
        $proc = Get-Process -Id $existingPid -ErrorAction SilentlyContinue
        if ($null -ne $proc) {
            $statusObj = Read-JsonFileSafe -Path $statusPath
            $isDryRunGuard = $false
            if ($null -ne $statusObj -and $null -ne $statusObj.dry_run) {
                try { $isDryRunGuard = [bool]$statusObj.dry_run } catch { $isDryRunGuard = $false }
            }
            if ($isDryRunGuard -and (-not $DryRun)) {
                try {
                    Stop-Process -Id $existingPid -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 400
                } catch {
                    return [ordered]@{
                        ok = $false
                        status = "failed_to_replace_dry_run_guard"
                        pid = $existingPid
                        error = $_.Exception.Message
                    }
                }
            } else {
                return [ordered]@{
                    ok = $true
                    status = "already_running"
                    pid = $existingPid
                    pid_file = $pidPath
                }
            }
        }
    }

    try {
        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-Root", $RuntimeRoot
        )
        if ($DryRun) {
            $argList += "-DryRun"
        }
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WorkingDirectory $RuntimeRoot -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 400
        return [ordered]@{
            ok = $true
            status = "started"
            pid = [int]$proc.Id
            pid_file = $pidPath
            dry_run = [bool]$DryRun
        }
    } catch {
        return [ordered]@{
            ok = $false
            status = "start_failed"
            error = $_.Exception.Message
            script = $scriptPath
        }
    }
}

function Read-KeyEnv {
    param([Parameter(Mandatory = $true)][string]$Path)
    $cfg = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $cfg
    }
    foreach ($line in (Get-Content -Encoding UTF8 -Path $Path)) {
        $s = [string]$line
        if ([string]::IsNullOrWhiteSpace($s)) { continue }
        $t = $s.Trim()
        if ($t.StartsWith("#")) { continue }
        if ($t -notmatch "=") { continue }
        $parts = $t.Split("=", 2)
        $k = [string]$parts[0]
        $v = [string]$parts[1]
        $cfg[$k.Trim()] = $v.Trim()
    }
    return $cfg
}

function Write-KeyEnv {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$Values
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $lines = @(
        "# OANDA MT5 key file (USB only)",
        "# Uwaga: DPAPI_CURRENT_USER dziala tylko na tym samym laptopie i koncie Windows",
        ("MT5_LOGIN={0}" -f ([string]$Values["MT5_LOGIN"])),
        ("MT5_PASSWORD_MODE={0}" -f ([string]$Values["MT5_PASSWORD_MODE"])),
        ("MT5_PASSWORD_DPAPI={0}" -f ([string]$Values["MT5_PASSWORD_DPAPI"])),
        ("MT5_SERVER={0}" -f ([string]$Values["MT5_SERVER"])),
        ("MT5_PATH={0}" -f ([string]$Values["MT5_PATH"]))
    )
    Set-Content -Encoding UTF8 -Path $Path -Value ($lines -join [Environment]::NewLine)
}

function Ensure-KeyEnvReady {
    param(
        [Parameter(Mandatory = $true)][string]$KeyEnvPath,
        [switch]$Dry
    )
    $cfg = Read-KeyEnv -Path $KeyEnvPath

    $login = [string]($cfg["MT5_LOGIN"])
    $server = [string]($cfg["MT5_SERVER"])
    $mt5Path = [string]($cfg["MT5_PATH"])
    $pwdPlain = [string]($cfg["MT5_PASSWORD"])
    $pwdDpapi = [string]($cfg["MT5_PASSWORD_DPAPI"])
    $pwdDpapiB64 = [string]($cfg["MT5_PASSWORD_DPAPI_B64"])

    if (Is-PlaceholderValue $server) { $server = "" }
    if (Is-PlaceholderValue $mt5Path) { $mt5Path = "" }

    if ([string]::IsNullOrWhiteSpace($server)) {
        $server = $DEFAULT_MT5_SERVER
    }
    $server = Normalize-Mt5Server -Server $server
    if ([string]::IsNullOrWhiteSpace($mt5Path)) {
        $mt5Path = $DEFAULT_MT5_PATH
    }

    $hasPassword = $false
    if (-not (Is-PlaceholderValue $pwdPlain)) { $hasPassword = $true }
    if (-not (Is-PlaceholderValue $pwdDpapi)) { $hasPassword = $true }
    if (-not (Is-PlaceholderValue $pwdDpapiB64)) { $hasPassword = $true }

    $needsPrompt = (Is-PlaceholderValue $login) -or (-not $hasPassword)
    if (-not $needsPrompt) {
        $passwordModeResolved = "PLAINTEXT"
        if (-not (Is-PlaceholderValue $pwdDpapi)) {
            $passwordModeResolved = "DPAPI_CURRENT_USER"
        } elseif (-not (Is-PlaceholderValue $pwdDpapiB64)) {
            $passwordModeResolved = "DPAPI_B64_CURRENT_USER"
        }

        $outValues = [ordered]@{
            MT5_LOGIN = $login
            MT5_PASSWORD_MODE = $passwordModeResolved
            MT5_PASSWORD_DPAPI = $pwdDpapi
            MT5_SERVER = $server
            MT5_PATH = $mt5Path
        }
        if ($Dry) {
            return [ordered]@{
                ready = $true
                prompted = $false
                wrote_env = $false
                prompt_required = $false
                server = $server
            }
        }
        Write-KeyEnv -Path $KeyEnvPath -Values $outValues
        if (-not (Is-PlaceholderValue $pwdDpapiB64) -and (Is-PlaceholderValue $pwdDpapi)) {
            # Preserve compatibility payload when only legacy DPAPI_B64 exists.
            Add-Content -Encoding UTF8 -Path $KeyEnvPath -Value ([Environment]::NewLine + ("MT5_PASSWORD_DPAPI_B64={0}" -f $pwdDpapiB64))
        }
        if (-not (Is-PlaceholderValue $pwdPlain) -and (Is-PlaceholderValue $pwdDpapi) -and (Is-PlaceholderValue $pwdDpapiB64)) {
            Add-Content -Encoding UTF8 -Path $KeyEnvPath -Value ([Environment]::NewLine + ("MT5_PASSWORD={0}" -f $pwdPlain))
        }
        return [ordered]@{
            ready = $true
            prompted = $false
            wrote_env = $true
            prompt_required = $false
            server = $server
        }
    }

    if ($Dry) {
        return [ordered]@{
            ready = $false
            prompted = $false
            wrote_env = $false
            prompt_required = $true
            server = $server
        }
    }

    $loginIn = Read-Host "Podaj MT5_LOGIN (numer konta)"
    while ([string]::IsNullOrWhiteSpace($loginIn)) {
        $loginIn = Read-Host "MT5_LOGIN nie moze byc pusty. Podaj MT5_LOGIN"
    }
    $pwdSecure = Read-Host -AsSecureString "Podaj MT5_PASSWORD"
    $pwdPlainLocal = ConvertTo-PlainText -Secret $pwdSecure
    if ([string]::IsNullOrWhiteSpace($pwdPlainLocal)) {
        throw "MT5_PASSWORD nie moze byc pusty."
    }
    $srvPrompt = Read-Host ("Podaj MT5_SERVER (Enter = {0})" -f $server)
    $srvFinal = if ([string]::IsNullOrWhiteSpace($srvPrompt)) { $server } else { $srvPrompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($srvFinal)) { $srvFinal = $DEFAULT_MT5_SERVER }
    $srvFinal = Normalize-Mt5Server -Server $srvFinal

    $pathPrompt = Read-Host ("Podaj MT5_PATH (Enter = {0})" -f $mt5Path)
    $pathFinal = if ([string]::IsNullOrWhiteSpace($pathPrompt)) { $mt5Path } else { $pathPrompt.Trim() }
    if ([string]::IsNullOrWhiteSpace($pathFinal)) { $pathFinal = $DEFAULT_MT5_PATH }

    $cipher = ConvertFrom-SecureString -SecureString $pwdSecure
    $outValues = [ordered]@{
        MT5_LOGIN = $loginIn.Trim()
        MT5_PASSWORD_MODE = "DPAPI_CURRENT_USER"
        MT5_PASSWORD_DPAPI = $cipher
        MT5_SERVER = $srvFinal
        MT5_PATH = $pathFinal
    }
    Write-KeyEnv -Path $KeyEnvPath -Values $outValues

    $cipher = ""
    $pwdPlainLocal = ""
    Remove-Variable cipher, pwdPlainLocal -ErrorAction SilentlyContinue

    return [ordered]@{
        ready = $true
        prompted = $true
        wrote_env = $true
        prompt_required = $false
        server = $srvFinal
    }
}

$runtimeRoot = Resolve-Root -InputRoot $Root
$statusPath = Join-Path $runtimeRoot "RUN\start_with_key_status.json"
$status = [ordered]@{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    expected_label = $Label
    dry_run = [bool]$DryRun
    status = "FAIL"
}

$driveInfo = Resolve-KeyDrive -ExpectedLabel $Label -Dry:$DryRun
if (-not [bool]$driveInfo.ok) {
    $status.reason = [string]$driveInfo.reason
    if ($driveInfo.Contains("candidates")) {
        $status.candidates = @($driveInfo.candidates)
    }
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    if ($status.reason -eq "multiple_removable_no_label") {
        Write-Output ("KEY FAIL: Brak etykiety '{0}' i wykryto wiele pendrive. Oznacz docelowy pendrive etykieta '{0}'." -f $Label)
    } else {
        Write-Output ("KEY FAIL: Nie znaleziono pendrive gotowego pod etykiete '{0}'." -f $Label)
    }
    exit 2
}
$drive = [string]$driveInfo.drive
$status.detected_drive = $drive
$status.label_state = [string]$driveInfo.label_state
if ($driveInfo.Contains("label_method")) {
    $status.label_method = [string]$driveInfo.label_method
}

$fmt = Assert-DriveFormatReady -Drive $drive -AllowedFs $ALLOWED_FILESYSTEMS
if (-not [bool]$fmt.ok) {
    $status.reason = [string]$fmt.reason
    $status.filesystem = [string]$fmt.filesystem
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    if ($status.reason -eq "drive_not_formatted_raw") {
        Write-Output ("KEY FAIL: Pendrive {0} ma format RAW. Sformatuj go na NTFS/FAT32/exFAT i sprobuj ponownie." -f $drive)
    } elseif ($status.reason -eq "unsupported_filesystem") {
        Write-Output ("KEY FAIL: Pendrive {0} ma nieobslugiwany format '{1}'. Uzyj NTFS/FAT32/exFAT." -f $drive, $status.filesystem)
    } else {
        Write-Output ("KEY FAIL: Nie mozna potwierdzic formatu systemu plikow dla {0}." -f $drive)
    }
    exit 5
}
$status.filesystem = [string]$fmt.filesystem
$status.format_check = [string]$fmt.verification
$status.format_reason = [string]$fmt.reason

$tokenDir = Join-Path ($drive + "\") "TOKEN"
if (-not (Test-Path $tokenDir)) {
    if (-not $DryRun) {
        New-Item -ItemType Directory -Force -Path $tokenDir | Out-Null
    }
    $status.token_dir_created = (-not $DryRun)
}

$keyEnv = Join-Path $tokenDir "BotKey.env"
if ((-not (Test-Path $keyEnv)) -and (-not $DryRun)) {
    Write-KeyEnv -Path $keyEnv -Values @{
        MT5_LOGIN = "<UZUPELNIJ_PRZY_PIERWSZYM_STARCIE>"
        MT5_PASSWORD_MODE = "PROMPT_ON_FIRST_START"
        MT5_PASSWORD_DPAPI = ""
        MT5_SERVER = $DEFAULT_MT5_SERVER
        MT5_PATH = $DEFAULT_MT5_PATH
    }
    $status.key_bootstrap_created = $true
}

$envReady = Ensure-KeyEnvReady -KeyEnvPath $keyEnv -Dry:$DryRun
$status.prompt_required = [bool]$envReady.prompt_required
$status.prompted = [bool]$envReady.prompted
$status.key_env_written = [bool]$envReady.wrote_env
$status.server = [string]$envReady.server

$status.status = "PASS_PRECHECK"
$status.key_file_rel = "TOKEN\\BotKey.env"

$profileSetupScript = Join-Path $runtimeRoot "TOOLS\setup_mt5_hybrid_profile.py"
if (Test-Path $profileSetupScript) {
    $pythonExe = Get-PythonExe -RuntimeRoot $runtimeRoot
    $profileArgs = @(
        "-B",
        $profileSetupScript,
        "--root", $runtimeRoot,
        "--profile", "OANDA_HYBRID_AUTO"
    )
    if ($DryRun) {
        $profileArgs += "--no-launch"
    }
    $profileRc = 0
    $profileOut = ""
    $profileOk = $false
    try {
        $profileOut = (& $pythonExe @profileArgs 2>&1 | Out-String)
        $profileRc = [int]$LASTEXITCODE
        $profileOk = ($profileRc -eq 0)
    } catch {
        $profileRc = 7
        $profileOut = ("MT5 profile setup launch failed: " + $_.Exception.Message)
        $profileOk = $false
    }
    $status.mt5_profile_setup = [ordered]@{
        ok = [bool]$profileOk
        exit_code = [int]$profileRc
        output = [string]$profileOut
        profile = "OANDA_HYBRID_AUTO"
        python = [string]$pythonExe
    }
    if (-not $profileOk) {
        $status.status = "FAIL"
        $status.reason = "mt5_profile_setup_failed"
        [void](Write-JsonAtomic -Path $statusPath -Object $status)
        Write-Output ("START_WITH_OANDAKEY FAIL: MT5 profile setup failed rc={0}" -f $profileRc)
        exit 7
    }
} else {
    $status.mt5_profile_setup = [ordered]@{
        ok = $false
        exit_code = 6
        output = "missing setup_mt5_hybrid_profile.py"
        profile = "OANDA_HYBRID_AUTO"
    }
    $status.status = "FAIL"
    $status.reason = "missing_mt5_profile_setup_script"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("START_WITH_OANDAKEY FAIL: missing script {0}" -f $profileSetupScript)
    exit 6
}

$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
if (-not (Test-Path $systemControl)) {
    $status.status = "FAIL"
    $status.reason = "missing_system_control"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("START_WITH_OANDAKEY FAIL: missing script {0}" -f $systemControl)
    exit 4
}

$args = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $systemControl,
    "-Action", "start",
    "-Root", $runtimeRoot
)
if ($DryRun) {
    $args += "-DryRun"
}

$proc = Start-Process -FilePath "powershell.exe" -ArgumentList $args -WorkingDirectory $runtimeRoot -WindowStyle Hidden -PassThru -Wait
$rc = [int]$proc.ExitCode

$status.status = if ($rc -eq 0) { "PASS_STARTED" } else { "FAIL_START" }
$status.start_exit_code = $rc
[void](Write-JsonAtomic -Path $statusPath -Object $status)

if ($rc -eq 0) {
    $riskGuard = Start-RiskPopupGuard -RuntimeRoot $runtimeRoot
    $status.risk_popup_guard = $riskGuard
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    if (-not [bool]$riskGuard.ok) {
        Write-Output ("START_WITH_OANDAKEY WARN: risk popup guard failed status={0}" -f [string]$riskGuard.status)
    } else {
        Write-Output ("START_WITH_OANDAKEY RISK_GUARD status={0} pid={1}" -f [string]$riskGuard.status, [string]$riskGuard.pid)
    }
    $sessionGuard = Start-Mt5SessionGuard -RuntimeRoot $runtimeRoot
    $status.mt5_session_guard = $sessionGuard
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    if (-not [bool]$sessionGuard.ok) {
        Write-Output ("START_WITH_OANDAKEY WARN: mt5 session guard failed status={0}" -f [string]$sessionGuard.status)
    } else {
        Write-Output ("START_WITH_OANDAKEY MT5_SESSION_GUARD status={0} pid={1}" -f [string]$sessionGuard.status, [string]$sessionGuard.pid)
    }
    Write-Output ("START_WITH_OANDAKEY PASS drive={0} dry_run={1}" -f $drive, [int]([bool]$DryRun))
    exit 0
}

Write-Output ("START_WITH_OANDAKEY FAIL rc={0}" -f $rc)
exit $rc
