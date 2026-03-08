param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$DriveLetter = "E",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-RootPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $Path).Path
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = [System.IO.Path]::Combine(
        $parent,
        ([System.IO.Path]::GetFileName($Path) + ".tmp." + [guid]::NewGuid().ToString("N"))
    )
    try {
        ($Object | ConvertTo-Json -Depth 8) | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Force $tmp $Path
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Add-Action {
    param(
        [System.Collections.ArrayList]$List,
        [string]$Name,
        [string]$State,
        [string]$Details = ""
    )
    [void]$List.Add([ordered]@{
        name = $Name
        state = $State
        details = $Details
    })
}

function Test-DriveReady {
    param([string]$Letter)
    try {
        $di = New-Object System.IO.DriveInfo(($Letter + ":\"))
        if (-not $di.IsReady) {
            return [ordered]@{
                exists = $true
                ready = $false
                label = ""
                format = ""
            }
        }
        return [ordered]@{
            exists = $true
            ready = $true
            label = [string]$di.VolumeLabel
            format = [string]$di.DriveFormat
        }
    } catch {
        return [ordered]@{
            exists = $false
            ready = $false
            label = ""
            format = ""
        }
    }
}

function Remove-RegistryKeySafe {
    param(
        [string]$Path,
        [switch]$Dry
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return "missing"
    }
    if ($Dry) {
        return "dry_run"
    }
    try {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
        return "removed"
    } catch {
        return ("remove_failed:" + $_.Exception.Message)
    }
}

$runtimeRoot = Resolve-RootPath -Path $Root
$runDir = Join-Path $runtimeRoot "RUN"
$statusPath = Join-Path $runDir "ghost_drive_quiet_status.json"
$events = New-Object System.Collections.ArrayList

$letter = ([string]$DriveLetter).Trim().TrimEnd(":").ToUpperInvariant()
if ([string]::IsNullOrWhiteSpace($letter)) {
    throw "DriveLetter cannot be empty."
}

$probe = Test-DriveReady -Letter $letter
$result = [ordered]@{
    schema = "oanda_mt5.ghost_drive_quiet.v1"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    drive = ($letter + ":")
    dry_run = [bool]$DryRun
    drive_exists = [bool]$probe.exists
    drive_ready = [bool]$probe.ready
    drive_label = [string]$probe.label
    drive_format = [string]$probe.format
    actions = @()
    status = "NO_ACTION"
}

if ($probe.exists -and $probe.ready) {
    Add-Action -List $events -Name "probe_drive" -State "ready" -Details "Drive is ready; no cleanup needed."
    $result.actions = @($events)
    Write-JsonAtomic -Path $statusPath -Object $result
    Write-Output ("GHOST_DRIVE_QUIET status=NO_ACTION drive={0} ready=1" -f ($letter + ":"))
    exit 0
}

Add-Action -List $events -Name "probe_drive" -State "not_ready_or_missing" -Details "Applying stale mapping cleanup."

if ($DryRun) {
    Add-Action -List $events -Name "net_use_delete" -State "dry_run" -Details ("net use {0}: /delete /y" -f $letter)
    Add-Action -List $events -Name "subst_delete" -State "dry_run" -Details ("subst {0}: /d" -f $letter)
} else {
    $null = cmd.exe /c ("net use {0}: /delete /y" -f $letter)
    Add-Action -List $events -Name "net_use_delete" -State ("exit_" + [string]$LASTEXITCODE)
    $null = cmd.exe /c ("subst {0}: /d" -f $letter)
    Add-Action -List $events -Name "subst_delete" -State ("exit_" + [string]$LASTEXITCODE)
}

$mp2User = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\" + $letter
$netUser = "HKCU:\Network\" + $letter
$mp2Machine = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\MountPoints2\" + $letter

Add-Action -List $events -Name "registry_mountpoints_user" -State (Remove-RegistryKeySafe -Path $mp2User -Dry:$DryRun)
Add-Action -List $events -Name "registry_network_user" -State (Remove-RegistryKeySafe -Path $netUser -Dry:$DryRun)
Add-Action -List $events -Name "registry_mountpoints_machine" -State (Remove-RegistryKeySafe -Path $mp2Machine -Dry:$DryRun)

$probeAfter = Test-DriveReady -Letter $letter
$result.drive_exists_after = [bool]$probeAfter.exists
$result.drive_ready_after = [bool]$probeAfter.ready
$result.drive_label_after = [string]$probeAfter.label
$result.drive_format_after = [string]$probeAfter.format
$result.actions = @($events)
$result.status = if ($probeAfter.exists -and $probeAfter.ready) { "READY_AFTER_CLEANUP" } else { "CLEANUP_APPLIED" }

Write-JsonAtomic -Path $statusPath -Object $result
Write-Output ("GHOST_DRIVE_QUIET status={0} drive={1} ready_after={2}" -f [string]$result.status, ($letter + ":"), [int]([bool]$probeAfter.ready))
exit 0
