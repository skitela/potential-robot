param(
    [string]$Root = "",
    [string]$Label = "OANDAKEY",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Root {
    param([string]$InputRoot = "")
    if ([string]::IsNullOrWhiteSpace($InputRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $InputRoot).Path
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

$runtimeRoot = Resolve-Root -InputRoot $Root
$statusPath = Join-Path $runtimeRoot "RUN\start_with_key_status.json"
$status = [ordered]@{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    expected_label = $Label
    dry_run = [bool]$DryRun
    status = "FAIL"
}

$drive = Get-KeyDriveByLabel -ExpectedLabel $Label
if ([string]::IsNullOrWhiteSpace($drive)) {
    $status.reason = "key_label_not_found"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("KEY FAIL: Nie znaleziono woluminu o etykiecie '{0}'." -f $Label)
    exit 2
}

$keyEnv = Join-Path ($drive + "\") "TOKEN\BotKey.env"
if (-not (Test-Path $keyEnv)) {
    $status.reason = "key_file_missing"
    $status.detected_drive = $drive
    $status.expected_rel = "TOKEN\\BotKey.env"
    [void](Write-JsonAtomic -Path $statusPath -Object $status)
    Write-Output ("KEY FAIL: Wolumin '{0}' znaleziony, ale brakuje TOKEN\\BotKey.env." -f $drive)
    exit 3
}

$status.status = "PASS_PRECHECK"
$status.detected_drive = $drive
$status.key_file_rel = "TOKEN\\BotKey.env"

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
    Write-Output ("START_WITH_OANDAKEY PASS drive={0} dry_run={1}" -f $drive, [int]([bool]$DryRun))
    exit 0
}

Write-Output ("START_WITH_OANDAKEY FAIL rc={0}" -f $rc)
exit $rc
