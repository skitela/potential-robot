param(
    [string]$Root = "",
    [string]$Label = "OANDAKEY",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
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

function Get-MissingRuntimeModules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonExe
    )
    $probe = @'
import importlib.util
import json

required = {
    "pyzmq": "zmq",
    "MetaTrader5": "MetaTrader5",
    "pandas": "pandas",
    "numpy": "numpy",
    "ta": "ta",
    "psutil": "psutil",
    "requests": "requests",
    "feedparser": "feedparser",
}
missing = [pkg for pkg, module in required.items() if importlib.util.find_spec(module) is None]
print(json.dumps(missing))
'@
    try {
        $prevErrorPreference = $ErrorActionPreference
        $tmpProbe = Join-Path ([System.IO.Path]::GetTempPath()) ("oanda_runtime_probe_" + [guid]::NewGuid().ToString("N") + ".py")
        try {
            # Python może wypisać ostrzeżenia na stderr; nie chcemy,
            # aby to przerywało preflight zależności.
            $ErrorActionPreference = "Continue"
            Set-Content -Path $tmpProbe -Value $probe -Encoding UTF8
            $raw = (& $PythonExe $tmpProbe 2>&1 | Out-String).Trim()
            $rc = [int]$LASTEXITCODE
        } finally {
            try {
                if (-not [string]::IsNullOrWhiteSpace($tmpProbe) -and (Test-Path -LiteralPath $tmpProbe)) {
                    Remove-Item -Force -LiteralPath $tmpProbe -ErrorAction SilentlyContinue
                }
            } catch {}
            $ErrorActionPreference = $prevErrorPreference
        }
        $jsonLine = ""
        if (-not [string]::IsNullOrWhiteSpace($raw)) {
            $rows = @($raw -split "(`r`n|`n)")
            for ($idx = $rows.Count - 1; $idx -ge 0; $idx--) {
                $candidate = ([string]$rows[$idx]).Trim()
                if ($candidate.StartsWith("[") -and $candidate.EndsWith("]")) {
                    $jsonLine = $candidate
                    break
                }
            }
        }
        if ([string]::IsNullOrWhiteSpace($jsonLine)) {
            return [ordered]@{
                ok = $false
                error = if ($rc -ne 0) { "python_probe_failed" } else { "python_probe_no_json" }
                output = $raw
                missing = @()
            }
        }
        $parsed = $jsonLine | ConvertFrom-Json
        $missing = @($parsed | ForEach-Object { [string]$_ })
        return [ordered]@{
            ok = $true
            missing = @($missing)
            output = $raw
        }
    } catch {
        return [ordered]@{
            ok = $false
            error = $_.Exception.Message
            output = ""
            missing = @()
        }
    }
}

function Ensure-RuntimePythonDeps {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeRoot,
        [Parameter(Mandatory = $true)]
        [string]$PythonExe,
        [switch]$Dry
    )
    $probeBefore = Get-MissingRuntimeModules -PythonExe $PythonExe
    if (-not [bool]$probeBefore.ok) {
        return [ordered]@{
            ok = $false
            status = "probe_failed"
            missing = @()
            error = [string]$probeBefore.error
            output = [string]$probeBefore.output
        }
    }
    $missing = @($probeBefore.missing)
    if (@($missing).Count -eq 0) {
        return [ordered]@{
            ok = $true
            status = "already_ok"
            missing = @()
            installed = @()
        }
    }
    if ($Dry) {
        return [ordered]@{
            ok = $true
            status = "dry_run_missing"
            missing = @($missing)
            installed = @()
        }
    }

    $requirementsFile = Join-Path $RuntimeRoot "requirements.live.lock"
    if (-not (Test-Path -LiteralPath $requirementsFile)) {
        return [ordered]@{
            ok = $false
            status = "missing_requirements_file"
            missing = @($missing)
            requirements = $requirementsFile
        }
    }

    $installOut = ""
    $installRc = 0
    try {
        $installOut = (& $PythonExe -m pip install --disable-pip-version-check --no-input -r $requirementsFile 2>&1 | Out-String)
        $installRc = [int]$LASTEXITCODE
    } catch {
        $installRc = 1
        $installOut = "pip_install_exception: " + $_.Exception.Message
    }
    if ($installRc -ne 0) {
        return [ordered]@{
            ok = $false
            status = "pip_install_failed"
            missing = @($missing)
            requirements = $requirementsFile
            install_rc = [int]$installRc
            output = [string]$installOut
        }
    }

    $probeAfter = Get-MissingRuntimeModules -PythonExe $PythonExe
    if (-not [bool]$probeAfter.ok) {
        return [ordered]@{
            ok = $false
            status = "probe_after_failed"
            missing = @()
            error = [string]$probeAfter.error
            output = [string]$probeAfter.output
        }
    }
    if (@($probeAfter.missing).Count -gt 0) {
        return [ordered]@{
            ok = $false
            status = "missing_after_install"
            missing = @($probeAfter.missing)
            requirements = $requirementsFile
            output = [string]$installOut
        }
    }

    return [ordered]@{
        ok = $true
        status = "installed_from_requirements"
        missing = @()
        installed = @($missing)
        requirements = $requirementsFile
    }
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

function Test-PidRunningSafe {
    param([int]$ProcessId)
    if ([int]$ProcessId -le 0) { return $false }
    try {
        $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        return ($null -ne $proc)
    } catch {
        return $false
    }
}

function Acquire-StartPidLock {
    param(
        [string]$LockPath,
        [int]$CurrentPid
    )
    if ([string]::IsNullOrWhiteSpace($LockPath)) {
        return [ordered]@{ ok = $false; status = "invalid_lock_path" }
    }
    $parent = Split-Path -Parent $LockPath
    New-Item -ItemType Directory -Force -Path $parent | Out-Null

    if (Test-Path -LiteralPath $LockPath) {
        $existing = Read-JsonFileSafe -Path $LockPath
        $existingPid = $null
        if ($null -ne $existing -and $null -ne $existing.pid) {
            try { $existingPid = [int]$existing.pid } catch { $existingPid = $null }
        }
        if (($null -ne $existingPid) -and ($existingPid -ne $CurrentPid) -and (Test-PidRunningSafe -ProcessId $existingPid)) {
            return [ordered]@{
                ok = $false
                status = "already_running"
                pid = [int]$existingPid
            }
        }
        try { Remove-Item -Force -LiteralPath $LockPath -ErrorAction Stop } catch {
            return [ordered]@{
                ok = $false
                status = "stale_lock_remove_failed"
                error = $_.Exception.Message
            }
        }
    }

    $payload = [ordered]@{
        pid = [int]$CurrentPid
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        host = $env:COMPUTERNAME
        script = "RUN/START_WITH_OANDAKEY.ps1"
    }
    $ok = Write-JsonAtomic -Path $LockPath -Object $payload
    return [ordered]@{
        ok = [bool]$ok
        status = if ($ok) { "acquired" } else { "write_failed" }
        pid = [int]$CurrentPid
        path = $LockPath
    }
}

function Get-BridgeHeartbeatOkAgeSec {
    param(
        [string]$LogPath,
        [int]$TailLines = 500
    )
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return $null }
    if (-not (Test-Path $LogPath)) { return $null }
    $lines = @()
    try {
        $lines = @(Get-Content -Path $LogPath -Tail ([Math]::Max(50, [int]$TailLines)) -ErrorAction Stop)
    } catch {
        return $null
    }
    $rx = [regex]'^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}).*\bBRIDGE_DIAG\b.*\baction=HEARTBEAT\b.*\bstatus=OK\b'
    $lastTs = $null
    foreach ($line in $lines) {
        $msg = [string]$line
        if ([string]::IsNullOrWhiteSpace($msg)) { continue }
        $m = $rx.Match($msg)
        if (-not $m.Success) { continue }
        try {
            $lastTs = [datetime]::ParseExact(
                [string]$m.Groups["ts"].Value,
                "yyyy-MM-dd HH:mm:ss,fff",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        } catch {
            continue
        }
    }
    if ($null -eq $lastTs) { return $null }
    return [double]((Get-Date) - $lastTs).TotalSeconds
}

function Invoke-SystemControlStatusSafe {
    param(
        [string]$SystemControlPath,
        [string]$RuntimeRoot,
        [ValidateSet("full", "safety_only")]
        [string]$Profile = "safety_only",
        [int]$TimeoutSec = 12
    )
    $timeoutMs = [Math]::Max(2000, ([int]$TimeoutSec * 1000))
    $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) ("oanda_sc_status_" + [guid]::NewGuid().ToString("N") + ".out.log")
    $tmpErr = Join-Path ([System.IO.Path]::GetTempPath()) ("oanda_sc_status_" + [guid]::NewGuid().ToString("N") + ".err.log")
    $argList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $SystemControlPath,
        "-Action", "status",
        "-Root", $RuntimeRoot,
        "-Profile", $Profile
    )
    try {
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WindowStyle Hidden -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -PassThru -ErrorAction Stop
        $exited = $proc.WaitForExit($timeoutMs)
        if (-not $exited) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            return [ordered]@{
                ok = $false
                timed_out = $true
                exit_code = $null
                status_out = "SYSTEM_CONTROL status timeout"
            }
        }
        $stdout = ""
        $stderr = ""
        try {
            if (Test-Path -LiteralPath $tmpOut) { $stdout = (Get-Content -Path $tmpOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue).Trim() }
            if (Test-Path -LiteralPath $tmpErr) { $stderr = (Get-Content -Path $tmpErr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue).Trim() }
        } catch {}
        $combined = @($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        return [ordered]@{
            ok = ([int]$proc.ExitCode -eq 0)
            timed_out = $false
            exit_code = [int]$proc.ExitCode
            status_out = [string]($combined -join [Environment]::NewLine)
        }
    } catch {
        return [ordered]@{
            ok = $false
            timed_out = $false
            exit_code = $null
            status_out = [string]$_.Exception.Message
        }
    } finally {
        try { Remove-Item -Force -LiteralPath $tmpOut -ErrorAction SilentlyContinue } catch {}
        try { Remove-Item -Force -LiteralPath $tmpErr -ErrorAction SilentlyContinue } catch {}
    }
}

function Invoke-PowerShellWithTimeout {
    param(
        [string[]]$ArgumentList,
        [int]$TimeoutSec = 60
    )
    $timeoutMs = [Math]::Max(2000, ([int]$TimeoutSec * 1000))
    $tmpOut = Join-Path ([System.IO.Path]::GetTempPath()) ("oanda_ps_call_" + [guid]::NewGuid().ToString("N") + ".out.log")
    $tmpErr = Join-Path ([System.IO.Path]::GetTempPath()) ("oanda_ps_call_" + [guid]::NewGuid().ToString("N") + ".err.log")
    try {
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $ArgumentList -WindowStyle Hidden -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr -PassThru -ErrorAction Stop
        $exited = $proc.WaitForExit($timeoutMs)
        if (-not $exited) {
            try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
            return [ordered]@{
                ok = $false
                exit_code = $null
                timed_out = $true
                output = "powershell_call_timeout"
            }
        }
        $stdout = ""
        $stderr = ""
        try {
            if (Test-Path -LiteralPath $tmpOut) { $stdout = (Get-Content -Path $tmpOut -Raw -Encoding UTF8 -ErrorAction SilentlyContinue).Trim() }
            if (Test-Path -LiteralPath $tmpErr) { $stderr = (Get-Content -Path $tmpErr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue).Trim() }
        } catch {}
        $combined = @($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }
        $exitCode = [int]$proc.ExitCode
        return [ordered]@{
            ok = ($exitCode -eq 0)
            exit_code = $exitCode
            timed_out = $false
            output = [string]($combined -join [Environment]::NewLine)
        }
    } catch {
        return [ordered]@{
            ok = $false
            exit_code = $null
            timed_out = $false
            output = [string]$_.Exception.Message
        }
    } finally {
        try { Remove-Item -Force -LiteralPath $tmpOut -ErrorAction SilentlyContinue } catch {}
        try { Remove-Item -Force -LiteralPath $tmpErr -ErrorAction SilentlyContinue } catch {}
    }
}

function Wait-RuntimeReady {
    param(
        [string]$RuntimeRoot,
        [ValidateSet("full", "safety_only")]
        [string]$Profile = "safety_only",
        [int]$TimeoutSec = 120,
        [int]$PollSec = 3
    )
    $sc = Join-Path $RuntimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
    $statusPath = Join-Path $RuntimeRoot "RUN\system_control_last.json"
    $safetyLogPath = Join-Path $RuntimeRoot "LOGS\safetybot.log"

    $timeout = [Math]::Max(10, [int]$TimeoutSec)
    $startedAt = Get-Date
    $deadline = $startedAt.AddSeconds($timeout)
    $lastStatusOut = ""
    $lastError = ""
    $lastHeartbeatAge = $null
    $lastRunningByPid = $false
    $lastDuplicatePids = $false
    $lastStatusPass = $false
    $reconcileAttempted = $false
    $reconcileResult = ""
    $poll = [Math]::Max(2, [int]$PollSec)

    while ((Get-Date) -lt $deadline) {
        try {
            $statusCall = Invoke-SystemControlStatusSafe -SystemControlPath $sc -RuntimeRoot $RuntimeRoot -Profile $Profile -TimeoutSec 12
            $lastStatusOut = [string]$statusCall.status_out
            $lastStatusPass = [bool]$statusCall.ok

            $statusObj = Read-JsonFileSafe -Path $statusPath
            if ($null -ne $statusObj) {
                $statusAction = ""
                $statusState = ""
                try { $statusAction = [string]$statusObj.action } catch { $statusAction = "" }
                try { $statusState = [string]$statusObj.status } catch { $statusState = "" }
                if ($statusAction.Trim().ToLowerInvariant() -eq "status") {
                    if ($statusState.Trim().ToUpperInvariant() -eq "PASS") {
                        $lastStatusPass = $true
                    } elseif ($statusState.Trim().ToUpperInvariant() -eq "FAIL") {
                        $lastStatusPass = $false
                    }
                }
            }
            if (-not $lastStatusPass) {
                $lastStatusPass = ($lastStatusOut -match "status=PASS")
            }
            $comp = $null
            if ($null -ne $statusObj -and $null -ne $statusObj.components) {
                foreach ($r in @($statusObj.components)) {
                    if ([string]$r.name -eq "SafetyBot") { $comp = $r; break }
                }
            }
            $lastRunningByPid = $false
            $lastDuplicatePids = $false
            if ($null -ne $comp) {
                $propRunning = $comp.PSObject.Properties["running_by_pid"]
                if ($null -ne $propRunning) {
                    try { $lastRunningByPid = [bool]$propRunning.Value } catch { $lastRunningByPid = $false }
                }
                $propDup = $comp.PSObject.Properties["duplicate_pids"]
                if ($null -ne $propDup) {
                    try { $lastDuplicatePids = [bool]$propDup.Value } catch { $lastDuplicatePids = $false }
                }
            }
            $lastHeartbeatAge = Get-BridgeHeartbeatOkAgeSec -LogPath $safetyLogPath -TailLines 500
            $heartbeatOk = ($null -ne $lastHeartbeatAge) -and ([double]$lastHeartbeatAge -le 45.0)

            if ($lastStatusPass -and $lastRunningByPid -and (-not $lastDuplicatePids) -and $heartbeatOk) {
                return [ordered]@{
                    ok = $true
                    status_out = $lastStatusOut
                    running_by_pid = [bool]$lastRunningByPid
                    duplicate_pids = [bool]$lastDuplicatePids
                    bridge_heartbeat_ok_age_sec = $lastHeartbeatAge
                    reconcile_attempted = [bool]$reconcileAttempted
                    reconcile_result = $reconcileResult
                    waited_sec = [double]([Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3))
                }
            }

            # Jednorazowa auto-rekonsyliacja stanu:
            # - deduplikacja SafetyBota
            # - naprawa locku jeśli status widzi heartbeat, ale PID nie jest stabilny
            if ((-not $reconcileAttempted) -and ($lastDuplicatePids -or ($heartbeatOk -and (-not $lastRunningByPid)))) {
                $reconcileAttempted = $true
                $reconcileArgs = @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-File", $sc,
                    "-Action", "start",
                    "-Root", $RuntimeRoot,
                    "-Profile", $Profile
                )
                $reconcileCall = Invoke-PowerShellWithTimeout -ArgumentList $reconcileArgs -TimeoutSec 45
                $reconcileResult = [string]$reconcileCall.output
                Start-Sleep -Seconds 2
                continue
            }
        } catch {
            $lastError = [string]$_.Exception.Message
        }
        Start-Sleep -Seconds $poll
    }

    return [ordered]@{
        ok = $false
        status_out = $lastStatusOut
        running_by_pid = [bool]$lastRunningByPid
        duplicate_pids = [bool]$lastDuplicatePids
        bridge_heartbeat_ok_age_sec = $lastHeartbeatAge
        reconcile_attempted = [bool]$reconcileAttempted
        reconcile_result = $reconcileResult
        error = $lastError
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
    $runningPids = @(Get-RunningScriptProcessIds -ScriptPath $scriptPath)
    if (@($runningPids).Count -gt 0) {
        $keepPid = $null
        if (($null -ne $existingPid) -and (@($runningPids) -contains [int]$existingPid)) {
            $keepPid = [int]$existingPid
        } else {
            $keepPid = [int]((@($runningPids | Sort-Object))[0])
        }
        $kill = @($runningPids | Where-Object { [int]$_ -ne [int]$keepPid })
        if (@($kill).Count -gt 0) {
            Stop-ProcessListBestEffort -ProcessIds $kill
        }
        return [ordered]@{
            ok = $true
            status = "already_running"
            pid = [int]$keepPid
            pid_file = $pidPath
            dedup_killed = @($kill)
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
    param(
        [string]$RuntimeRoot,
        [ValidateSet("full", "safety_only")]
        [string]$Profile = "safety_only"
    )
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
    $statusObj = Read-JsonFileSafe -Path $statusPath
    $isDryRunGuard = $false
    if ($null -ne $statusObj -and $null -ne $statusObj.dry_run) {
        try { $isDryRunGuard = [bool]$statusObj.dry_run } catch { $isDryRunGuard = $false }
    }
    $runningPids = @(Get-RunningScriptProcessIds -ScriptPath $scriptPath)
    if ($DryRun) {
        if (@($runningPids).Count -gt 0) {
            return [ordered]@{
                ok = $true
                status = "already_running"
                pid = [int]((@($runningPids | Sort-Object))[0])
                pid_file = $pidPath
                profile = $Profile
                dry_run = $true
            }
        }
        return [ordered]@{
            ok = $true
            status = "dry_run_skip"
            profile = $Profile
            dry_run = $true
        }
    }

    if ($isDryRunGuard -or @($runningPids).Count -gt 1) {
        Stop-ProcessListBestEffort -ProcessIds $runningPids
        Start-Sleep -Milliseconds 300
        $runningPids = @(Get-RunningScriptProcessIds -ScriptPath $scriptPath)
    }
    if (@($runningPids).Count -gt 0) {
        $keepPid = [int]((@($runningPids | Sort-Object))[0])
        $kill = @($runningPids | Where-Object { [int]$_ -ne [int]$keepPid })
        if (@($kill).Count -gt 0) {
            Stop-ProcessListBestEffort -ProcessIds $kill
        }
        return [ordered]@{
            ok = $true
            status = "already_running"
            pid = [int]$keepPid
            pid_file = $pidPath
            profile = $Profile
            dedup_killed = @($kill)
        }
    }

    try {
        $argList = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-Root", $RuntimeRoot,
            "-Profile", $Profile
        )
        $proc = Start-Process -FilePath "powershell.exe" -ArgumentList $argList -WorkingDirectory $RuntimeRoot -WindowStyle Hidden -PassThru
        Start-Sleep -Milliseconds 400
        return [ordered]@{
            ok = $true
            status = "started"
            pid = [int]$proc.Id
            pid_file = $pidPath
            profile = $Profile
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
    profile = $Profile
    dry_run = [bool]$DryRun
    status = "FAIL"
}

$startLockPath = Join-Path $runtimeRoot "RUN\start_with_key.lock"
$startLock = Acquire-StartPidLock -LockPath $startLockPath -CurrentPid ([int]$PID)
$status.start_lock = $startLock
if (-not [bool]$startLock.ok) {
    $status.reason = "start_lock_not_acquired"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("START_WITH_OANDAKEY FAIL_LOCK status={0} pid={1}" -f [string]$startLock.status, [string]$startLock.pid)
    exit 13
}

function Get-RunningScriptProcessIds {
    param([string]$ScriptPath)
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) { return @() }
    $escaped = [regex]::Escape([string]$ScriptPath)
    try {
        return @(
            Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object {
                $_.Name -match "^powershell(\.exe)?$" -and
                $_.CommandLine -and
                ($_.CommandLine -match $escaped)
            } |
            ForEach-Object { [int]$_.ProcessId } |
            Sort-Object -Unique
        )
    } catch {
        return @()
    }
}

function Stop-ProcessListBestEffort {
    param([int[]]$ProcessIds)
    foreach ($pid in @($ProcessIds | Sort-Object -Unique)) {
        if ([int]$pid -le 0) { continue }
        try {
            Stop-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 120
            if (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue) {
                Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
            }
        } catch {
            continue
        }
    }
}

$ghostDriveScript = Join-Path $runtimeRoot "TOOLS\quiet_ghost_drive.ps1"
if (Test-Path $ghostDriveScript) {
    try {
        $ghostArgs = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $ghostDriveScript,
            "-Root", $runtimeRoot,
            "-DriveLetter", "E"
        )
        if ($DryRun) { $ghostArgs += "-DryRun" }
        $ghostOut = (& powershell @ghostArgs 2>&1 | Out-String).Trim()
        $status.ghost_drive_quiet = [ordered]@{
            status = "ok"
            output = $ghostOut
        }
    } catch {
        $status.ghost_drive_quiet = [ordered]@{
            status = "error"
            error = $_.Exception.Message
        }
    }
}

$driveInfo = Resolve-KeyDrive -ExpectedLabel $Label -Dry:$DryRun
$keyRootPath = ""
$drive = ""
$localFallbackRoot = Join-Path $runtimeRoot "KEY"
$localFallbackEnv = Join-Path $localFallbackRoot "TOKEN\\BotKey.env"

if ([bool]$driveInfo.ok) {
    $drive = [string]$driveInfo.drive
    $keyRootPath = ($drive + "\")
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
    $status.key_source = "USB_LABEL"
} elseif (Test-Path -LiteralPath $localFallbackEnv) {
    $keyRootPath = $localFallbackRoot
    $status.detected_drive = "LOCAL_KEY"
    $status.label_state = "fallback_local_key"
    $status.filesystem = "LOCAL_FS"
    $status.format_check = "fallback_skip"
    $status.format_reason = "local_key_env_present"
    $status.key_source = "LOCAL_FALLBACK"
    Write-Output ("START_WITH_OANDAKEY INFO: użyto lokalnego fallbacku klucza: {0}" -f $localFallbackEnv)
} else {
    $status.reason = [string]$driveInfo.reason
    if ($driveInfo.Contains("candidates")) {
        $status.candidates = @($driveInfo.candidates)
    }
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    if ($status.reason -eq "multiple_removable_no_label") {
        Write-Output ("KEY FAIL: Brak etykiety '{0}' i wykryto wiele pendrive. Oznacz docelowy pendrive etykieta '{0}'." -f $Label)
    } else {
        Write-Output ("KEY FAIL: Nie znaleziono pendrive gotowego pod etykiete '{0}' ani fallbacku {1}." -f $Label, $localFallbackEnv)
    }
    exit 2
}

$tokenDir = Join-Path $keyRootPath "TOKEN"
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

$pythonExe = Get-PythonExe -RuntimeRoot $runtimeRoot
$status.python_exe = $pythonExe
$deps = Ensure-RuntimePythonDeps -RuntimeRoot $runtimeRoot -PythonExe $pythonExe -Dry:$DryRun
$status.python_runtime_deps = $deps
if (-not [bool]$deps.ok) {
    $status.status = "FAIL"
    $status.reason = "python_runtime_deps_failed"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("START_WITH_OANDAKEY FAIL_PYTHON_DEPS status={0}" -f [string]$deps.status)
    exit 9
}

$status.status = "PASS_PRECHECK"
$status.key_file_rel = "TOKEN\\BotKey.env"

$profileSetupScript = Join-Path $runtimeRoot "TOOLS\setup_mt5_hybrid_profile.py"
if (Test-Path $profileSetupScript) {
    $profileArgs = @(
        "-B",
        $profileSetupScript,
        "--root", $runtimeRoot,
        "--profile", "OANDA_HYBRID_AUTO",
        "--no-launch"
    )
    $profileRc = 0
    $profileOut = ""
    $profileOk = $false
    $profileAttempt = 0
    $profileMaxAttempts = 2
    $profileLastError = ""
    while ($profileAttempt -lt $profileMaxAttempts) {
        $profileAttempt += 1
        $prevErrorPreference = $ErrorActionPreference
        try {
            # Python może pisać na stderr (np. ostrzeżenia kodowania) mimo rc=0.
            # Nie traktujemy tego jako wyjątek transportowy.
            $ErrorActionPreference = "Continue"
            $profileOut = (& $pythonExe @profileArgs 2>&1 | Out-String)
            $profileRc = [int]$LASTEXITCODE
            $profileOk = ($profileRc -eq 0)
            if ($profileOk) { break }
            $profileLastError = ("profile_setup_exit_code_{0}" -f [int]$profileRc)
        } catch {
            $profileRc = 7
            $profileOut = ("MT5 profile setup launch failed: " + $_.Exception.Message)
            $profileLastError = [string]$_.Exception.Message
            $profileOk = $false
        } finally {
            $ErrorActionPreference = $prevErrorPreference
        }
        if ($profileAttempt -lt $profileMaxAttempts) {
            Start-Sleep -Seconds 2
        }
    }
    $status.mt5_profile_setup = [ordered]@{
        ok = [bool]$profileOk
        exit_code = [int]$profileRc
        output = [string]$profileOut
        profile = "OANDA_HYBRID_AUTO"
        python = [string]$pythonExe
        attempts = [int]$profileAttempt
        last_error = [string]$profileLastError
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

$preseedScript = Join-Path $runtimeRoot "TOOLS\preseed_kernel_config.py"
if (Test-Path $preseedScript) {
    $pythonPreseed = $null
    try { $pythonPreseed = [string]$status.mt5_profile_setup.python } catch { $pythonPreseed = "" }
    if ([string]::IsNullOrWhiteSpace($pythonPreseed)) {
        $pythonPreseed = Get-PythonExe -RuntimeRoot $runtimeRoot
    }
    if ($DryRun) {
        $status.kernel_config_preseed = [ordered]@{
            ok = $true
            status = "dry_run_skip"
            script = $preseedScript
        }
    } else {
        $preseedRc = 0
        $preseedOut = ""
        try {
            $preseedOut = (& $pythonPreseed -B $preseedScript --root $runtimeRoot 2>&1 | Out-String)
            $preseedRc = [int]$LASTEXITCODE
        } catch {
            $preseedRc = 8
            $preseedOut = ("preseed launch failed: " + $_.Exception.Message)
        }
        $status.kernel_config_preseed = [ordered]@{
            ok = ($preseedRc -eq 0)
            exit_code = [int]$preseedRc
            output = [string]$preseedOut
            script = $preseedScript
            python = $pythonPreseed
        }
        if ($preseedRc -ne 0) {
            Write-Output ("START_WITH_OANDAKEY WARN: kernel config preseed failed rc={0}" -f $preseedRc)
        }
    }
} else {
    $status.kernel_config_preseed = [ordered]@{
        ok = $false
        status = "missing_script"
        script = $preseedScript
    }
}

$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
if (-not (Test-Path $systemControl)) {
    $status.status = "FAIL"
    $status.reason = "missing_system_control"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("START_WITH_OANDAKEY FAIL: missing script {0}" -f $systemControl)
    exit 4
}

# Uruchamiamy guard popupu przed startem runtime/MT5, aby złapać okno ryzyka
# natychmiast po pojawieniu się (bez ingerencji w hot-path).
if ($DryRun) {
    $status.risk_popup_guard = [ordered]@{
        ok = $true
        status = "dry_run_skip"
    }
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
} else {
    $riskGuard = Start-RiskPopupGuard -RuntimeRoot $runtimeRoot
    $status.risk_popup_guard = $riskGuard
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    if (-not [bool]$riskGuard.ok) {
        Write-Output ("START_WITH_OANDAKEY WARN: risk popup guard failed status={0}" -f [string]$riskGuard.status)
    } else {
        Write-Output ("START_WITH_OANDAKEY RISK_GUARD status={0} pid={1}" -f [string]$riskGuard.status, [string]$riskGuard.pid)
    }
}

$systemControlArgs = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $systemControl,
    "-Action", "start",
    "-Root", $runtimeRoot,
    "-Profile", $Profile
)
if ($DryRun) {
    $systemControlArgs += "-DryRun"
}

try {
    $startCall = Invoke-PowerShellWithTimeout -ArgumentList $systemControlArgs -TimeoutSec 75
    $startOut = [string]$startCall.output
    if ($startCall.timed_out) {
        $rc = 1
    } elseif ($null -eq $startCall.exit_code) {
        $rc = 1
    } else {
        $rc = [int]$startCall.exit_code
    }
} catch {
    $startOut = [string]$_.Exception.Message
    $rc = 1
}
$status.system_control_start = [ordered]@{
    exit_code = [int]$rc
    output = [string]$startOut
}

$status.status = if ($rc -eq 0) { "PASS_STARTED" } else { "FAIL_START" }
$status.start_exit_code = $rc
[void](Write-JsonAtomic -Path $statusPath -Object $status)

if ($rc -eq 0) {
    if ($DryRun) {
        $status.mt5_session_guard = [ordered]@{
            ok = $true
            status = "dry_run_skip"
            profile = $Profile
        }
        $status.runtime_ready = [ordered]@{
            ok = $true
            status = "dry_run_skip"
        }
        $status.status = "PASS_READY_DRYRUN"
        [void](Write-JsonAtomic -Path $statusPath -Object $status)
    } else {
        $sessionGuard = Start-Mt5SessionGuard -RuntimeRoot $runtimeRoot -Profile $Profile
        $status.mt5_session_guard = $sessionGuard
        [void](Write-JsonAtomic -Path $statusPath -Object $status)
        if (-not [bool]$sessionGuard.ok) {
            Write-Output ("START_WITH_OANDAKEY WARN: mt5 session guard failed status={0}" -f [string]$sessionGuard.status)
        } else {
            Write-Output ("START_WITH_OANDAKEY MT5_SESSION_GUARD status={0} pid={1}" -f [string]$sessionGuard.status, [string]$sessionGuard.pid)
        }
        $ready = Wait-RuntimeReady -RuntimeRoot $runtimeRoot -Profile $Profile -TimeoutSec 120 -PollSec 3
        $status.runtime_ready = $ready
        if (-not [bool]$ready.ok) {
            $status.status = "FAIL_RUNTIME_NOT_READY"
            [void](Write-JsonAtomic -Path $statusPath -Object $status)
            Write-Output ("START_WITH_OANDAKEY FAIL_RUNTIME_NOT_READY status_out={0} running_by_pid={1} duplicate_pids={2} hb_ok_age_sec={3}" -f [string]$ready.status_out, [int]([bool]$ready.running_by_pid), [int]([bool]$ready.duplicate_pids), [string]$ready.bridge_heartbeat_ok_age_sec)
            exit 10
        }
        $status.status = "PASS_READY"
        [void](Write-JsonAtomic -Path $statusPath -Object $status)
    }
    $reportedDrive = [string]$status.detected_drive
    if ([string]::IsNullOrWhiteSpace($reportedDrive)) {
        $reportedDrive = [string]$drive
    }
    Write-Output ("START_WITH_OANDAKEY PASS drive={0} profile={1} dry_run={2}" -f $reportedDrive, $Profile, [int]([bool]$DryRun))
    exit 0
}

Write-Output ("START_WITH_OANDAKEY FAIL rc={0}" -f $rc)
exit $rc
