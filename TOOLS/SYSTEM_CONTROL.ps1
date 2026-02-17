param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action,
    [string]$Root = "",
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

function Get-PythonPath {
    param([string]$RuntimeRoot)
    try {
        $py312 = (& py -3.12 -c "import sys; print(sys.executable)" 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $py312Path = [string]($py312 | Select-Object -First 1)
            if (-not [string]::IsNullOrWhiteSpace($py312Path) -and (Test-Path $py312Path.Trim())) {
                return $py312Path.Trim()
            }
        }
    } catch {
        # ignore and continue with local venv candidates
    }
    $candidates = @(
        "C:\OANDA_VENV\.venv\Scripts\python.exe",
        (Join-Path $RuntimeRoot ".venv\Scripts\python.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            return $c
        }
    }
    return "python"
}

function Get-LockPid {
    param([string]$LockPath)
    if (-not (Test-Path $LockPath)) {
        return $null
    }
    try {
        $raw = (Get-Content -Raw -Encoding UTF8 $LockPath).Trim()
    } catch {
        return $null
    }
    if (-not $raw) {
        return $null
    }
    if ($raw.StartsWith("{")) {
        try {
            $obj = $raw | ConvertFrom-Json
            if ($null -ne $obj -and $null -ne $obj.pid) {
                return [int]$obj.pid
            }
        } catch {
            # ignore malformed json lock
        }
    }
    if ($raw -match "^\d+$") {
        return [int]$raw
    }
    return $null
}

function Get-ComponentProcessIds {
    param(
        [string]$RuntimeRoot,
        [string]$ScriptName
    )
    $ids = @()
    try {
        $binPath = (Join-Path $RuntimeRoot ("BIN\" + $ScriptName)).Replace("\", "\\")
        $procs = Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.CommandLine -and (
                $_.CommandLine -like "*$binPath*" -or
                $_.CommandLine -like "*" + $ScriptName + "*"
            )
        }
        $ids = @($procs | ForEach-Object { [int]$_.ProcessId } | Sort-Object -Unique)
    } catch {
        $ids = @()
    }
    return @($ids)
}

function Get-FileAgeSec {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        return $null
    }
    try {
        $it = Get-Item $Path -ErrorAction Stop
        return [double]((Get-Date) - $it.LastWriteTime).TotalSeconds
    } catch {
        return $null
    }
}

function Get-ComponentLogPath {
    param(
        [string]$RuntimeRoot,
        [string]$CompName
    )
    switch ($CompName) {
        "SafetyBot" { return (Join-Path $RuntimeRoot "LOGS\safetybot.log") }
        "SCUD" { return (Join-Path $RuntimeRoot "LOGS\scudfab02.log") }
        "Learner" { return (Join-Path $RuntimeRoot "LOGS\learner_offline.log") }
        "InfoBot" { return (Join-Path $RuntimeRoot "LOGS\infobot\infobot.log") }
        "RepairAgent" { return (Join-Path $RuntimeRoot "LOGS\repair_agent\repair_agent.log") }
        default { return "" }
    }
}

function Get-ComponentLogTtlSec {
    param([string]$CompName)
    switch ($CompName) {
        "Learner" { return 600 }
        default { return 240 }
    }
}

function Stop-PidSafely {
    param(
        [int]$ProcessId,
        [switch]$Dry
    )
    if ($ProcessId -le 0) {
        return "skip"
    }
    if ($Dry) {
        return "dry_run"
    }
    $proc = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($null -eq $proc) {
        return "not_running"
    }
    try {
        Stop-Process -Id $ProcessId -ErrorAction SilentlyContinue
    } catch {
        # ignore and fallback to forced stop
    }
    Start-Sleep -Milliseconds 900
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        try {
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        } catch {
            # ignore final check handles it
        }
        Start-Sleep -Milliseconds 300
    }
    if (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue) {
        return "force_failed"
    }
    return "stopped"
}

function Test-PidRunning {
    param([int]$ProcessId)
    if ($ProcessId -le 0) {
        return $false
    }
    return ($null -ne (Get-Process -Id $ProcessId -ErrorAction SilentlyContinue))
}

function Cleanup-StaleLock {
    param(
        [string]$LockPath,
        [switch]$Dry
    )
    if (-not $LockPath) {
        return @{
            status = "n/a"
            pid = $null
        }
    }
    if (-not (Test-Path $LockPath)) {
        return @{
            status = "missing"
            pid = $null
        }
    }
    $lockPidNum = Get-LockPid -LockPath $LockPath
    if ($null -ne $lockPidNum -and (Test-PidRunning -ProcessId ([int]$lockPidNum))) {
        return @{
            status = "active_lock"
            pid = [int]$lockPidNum
        }
    }
    if ($Dry) {
        return @{
            status = "dry_run_stale"
            pid = $lockPidNum
        }
    }
    try {
        Remove-Item -Force $LockPath -ErrorAction Stop
        return @{
            status = "stale_removed"
            pid = $lockPidNum
        }
    } catch {
        try {
            [System.IO.File]::WriteAllText($LockPath, "")
            return @{
                status = "stale_truncated"
                pid = $lockPidNum
            }
        } catch {
            return @{
                status = "stale_remove_failed"
                pid = $lockPidNum
                error = $_.Exception.Message
            }
        }
    }
}

function Start-Component {
    param(
        [string]$RuntimeRoot,
        [string]$PythonPath,
        [hashtable]$Comp,
        [string]$LockPath = "",
        [switch]$Dry
    )
    $existing = Get-ComponentProcessIds -RuntimeRoot $RuntimeRoot -ScriptName ([string]$Comp.Script)
    if (@($existing).Count -gt 0) {
        return @{
            status = "already_running"
            pids = @($existing)
        }
    }

    $scriptPath = Join-Path $RuntimeRoot ("BIN\" + [string]$Comp.Script)
    if (-not (Test-Path $scriptPath)) {
        return @{
            status = "missing_script"
            script = $scriptPath
        }
    }

    $args = @()
    if ($null -ne $Comp.Args -and @($Comp.Args).Count -gt 0) {
        $args = @($Comp.Args | ForEach-Object { [string]$_ })
    }

    $lockInfo = Cleanup-StaleLock -LockPath $LockPath -Dry:$Dry
    if ($lockInfo.status -eq "active_lock") {
        # Guard against stale PID reuse: lock pid is alive, but target script is not.
        if ((@($existing).Count -eq 0) -and (Test-Path $LockPath) -and (-not $Dry)) {
            try {
                Remove-Item -Force $LockPath -ErrorAction Stop
                $lockInfo = @{
                    status = "stale_removed_pid_reuse"
                    pid = $lockInfo.pid
                }
            } catch {
                return @{
                    status = "blocked_active_lock"
                    lock = $LockPath
                    pid = $lockInfo.pid
                    error = ("stale_pid_reuse_remove_failed: " + $_.Exception.Message)
                }
            }
        } elseif ((@($existing).Count -eq 0) -and (Test-Path $LockPath) -and $Dry) {
            $lockInfo = @{
                status = "dry_run_stale_pid_reuse"
                pid = $lockInfo.pid
            }
        }
    }
    if ($lockInfo.status -eq "active_lock") {
        return @{
            status = "blocked_active_lock"
            lock = $LockPath
            pid = $lockInfo.pid
        }
    }
    if ($lockInfo.status -eq "stale_remove_failed") {
        return @{
            status = "blocked_stale_lock"
            lock = $LockPath
            pid = $lockInfo.pid
            error = [string]$lockInfo.error
        }
    }

    $argList = @("`"$scriptPath`"") + $args
    if ($Dry) {
        return @{
            status = "dry_run"
            command = ("`"$PythonPath`" " + ($argList -join " "))
            lock = $LockPath
            lock_cleanup = $lockInfo.status
        }
    }

    try {
        $bootDir = Join-Path $RuntimeRoot "LOGS\bootstrap"
        New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss_fff"
        $outLog = Join-Path $bootDir (([string]$Comp.Name) + "_" + $stamp + "_out.log")
        $errLog = Join-Path $bootDir (([string]$Comp.Name) + "_" + $stamp + "_err.log")

        $proc = Start-Process -FilePath $PythonPath -ArgumentList (@($scriptPath) + $args) -WorkingDirectory $RuntimeRoot -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru -ErrorAction Stop
        Start-Sleep -Milliseconds 700
        if ($proc.HasExited) {
            return @{
                status = "start_failed_exited"
                pid = [int]$proc.Id
                exit_code = [int]$proc.ExitCode
                stdout_log = $outLog
                stderr_log = $errLog
                lock = $LockPath
                lock_cleanup = $lockInfo.status
            }
        }
        return @{
            status = "started"
            pid = [int]$proc.Id
            stdout_log = $outLog
            stderr_log = $errLog
            lock = $LockPath
            lock_cleanup = $lockInfo.status
        }
    } catch {
        return @{
            status = "start_failed"
            error = $_.Exception.Message
        }
    }
}

function Remove-LockSafe {
    param(
        [string]$LockPath,
        [switch]$Dry
    )
    if (-not (Test-Path $LockPath)) {
        return "missing"
    }
    if ($Dry) {
        return "dry_run"
    }
    try {
        Remove-Item -Force $LockPath -ErrorAction Stop
        return "removed"
    } catch {
        try {
            [System.IO.File]::WriteAllText($LockPath, "")
            return "truncated"
        } catch {
            return "remove_failed"
        }
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
    $wrote = $false
    try {
        $data | Set-Content -Encoding UTF8 -Path $tmp
        Move-Item -Force $tmp $Path
        $wrote = $true
    } catch {
        try {
            $data | Set-Content -Encoding UTF8 -Path $Path
            $wrote = $true
        } catch {
            $wrote = $false
        } finally {
            try { Remove-Item -Force $tmp -ErrorAction SilentlyContinue } catch {}
        }
    }
    return [bool]$wrote
}

$runtimeRoot = Resolve-Root -InputRoot $Root
if (-not (Test-Path (Join-Path $runtimeRoot "BIN"))) {
    Write-Error "BIN directory missing under root: $runtimeRoot"
    exit 2
}
New-Item -ItemType Directory -Force -Path (Join-Path $runtimeRoot "RUN") | Out-Null

$components = @(
    @{ Name = "SafetyBot"; Script = "safetybot.py"; Args = @(); Lock = "RUN\safetybot.lock" },
    @{ Name = "SCUD"; Script = "scudfab02.py"; Args = @("loop", "10"); Lock = "RUN\scudfab02.lock" },
    @{ Name = "Learner"; Script = "learner_offline.py"; Args = @("loop", "3600"); Lock = "" },
    @{ Name = "InfoBot"; Script = "infobot.py"; Args = @(); Lock = "RUN\infobot.lock" },
    @{ Name = "RepairAgent"; Script = "repair_agent.py"; Args = @(); Lock = "RUN\repair_agent.lock" }
)

$pythonPath = Get-PythonPath -RuntimeRoot $runtimeRoot
$result = [ordered]@{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    action = $Action
    dry_run = [bool]$DryRun
    root = $runtimeRoot
    python = $pythonPath
    components = @()
}

$hasError = $false

switch ($Action) {
    "status" {
        foreach ($c in $components) {
            $ids = Get-ComponentProcessIds -RuntimeRoot $runtimeRoot -ScriptName ([string]$c.Script)
            $lockPath = if ([string]::IsNullOrWhiteSpace([string]$c.Lock)) { "" } else { Join-Path $runtimeRoot ([string]$c.Lock) }
            $lockExists = if ($lockPath) { Test-Path $lockPath } else { $false }
            $logPath = Get-ComponentLogPath -RuntimeRoot $runtimeRoot -CompName ([string]$c.Name)
            $logAgeSec = if ($logPath) { Get-FileAgeSec -Path $logPath } else { $null }
            $ttl = Get-ComponentLogTtlSec -CompName ([string]$c.Name)
            $logFresh = $false
            if ($null -ne $logAgeSec) {
                $logFresh = ([double]$logAgeSec -le [double]$ttl)
            }
            $runningByPid = [bool](@($ids).Count -gt 0)
            # WMI can be restricted on some hosts; lock+fresh-log is accepted heartbeat fallback.
            $runningByHeartbeat = $false
            if ($lockPath) {
                $runningByHeartbeat = ([bool]$lockExists -and [bool]$logFresh)
            } else {
                $runningByHeartbeat = [bool]$logFresh
            }
            $result.components += [ordered]@{
                name = [string]$c.Name
                script = [string]$c.Script
                running = ([bool]$runningByPid -or [bool]$runningByHeartbeat)
                running_by_pid = [bool]$runningByPid
                running_by_heartbeat = [bool]$runningByHeartbeat
                pids = @($ids)
                lock = $lockPath
                lock_exists = [bool]$lockExists
                log_path = $logPath
                log_age_sec = $logAgeSec
                log_ttl_sec = [int]$ttl
            }
        }
    }
    "start" {
        foreach ($c in $components) {
            $lockPath = if ([string]::IsNullOrWhiteSpace([string]$c.Lock)) { "" } else { Join-Path $runtimeRoot ([string]$c.Lock) }
            $item = Start-Component -RuntimeRoot $runtimeRoot -PythonPath $pythonPath -Comp $c -LockPath $lockPath -Dry:$DryRun
            $row = [ordered]@{
                name = [string]$c.Name
                script = [string]$c.Script
                result = $item
            }
            if (@("start_failed", "start_failed_exited", "missing_script", "blocked_active_lock", "blocked_stale_lock") -contains [string]$item.status) {
                $hasError = $true
            }
            $result.components += $row
        }
    }
    "stop" {
        foreach ($c in $components) {
            $lockPath = if ([string]::IsNullOrWhiteSpace([string]$c.Lock)) { "" } else { Join-Path $runtimeRoot ([string]$c.Lock) }
            $pids = @()
            if ($lockPath) {
                $lockPid = Get-LockPid -LockPath $lockPath
                if ($null -ne $lockPid -and [int]$lockPid -gt 0) {
                    $pids += [int]$lockPid
                }
            }
            $pids += Get-ComponentProcessIds -RuntimeRoot $runtimeRoot -ScriptName ([string]$c.Script)
            $pids = @($pids | Sort-Object -Unique)

            $stopStates = @()
            foreach ($procId in $pids) {
                $stopStates += @{
                    pid = [int]$procId
                    state = (Stop-PidSafely -ProcessId ([int]$procId) -Dry:$DryRun)
                }
            }

            $lockState = if ($lockPath) { Remove-LockSafe -LockPath $lockPath -Dry:$DryRun } else { "n/a" }
            if ($stopStates | Where-Object { $_.state -eq "force_failed" }) {
                $hasError = $true
            }
            if ($lockState -eq "remove_failed") {
                $hasError = $true
            }

            $result.components += [ordered]@{
                name = [string]$c.Name
                script = [string]$c.Script
                pids = @($pids)
                stop_states = @($stopStates)
                lock = $lockPath
                lock_cleanup = $lockState
            }
        }
    }
}

$result.status = if ($hasError) { "FAIL" } else { "PASS" }
$statusPath = Join-Path $runtimeRoot "RUN\system_control_last.json"
$writeOk = Write-JsonAtomic -Path $statusPath -Object $result
Write-Output ("SYSTEM_CONTROL action={0} status={1} dry_run={2} root={3}" -f $Action, $result.status, [int]([bool]$DryRun), $runtimeRoot)
if (-not $writeOk) {
    Write-Warning ("SYSTEM_CONTROL: could not write status file at {0}" -f $statusPath)
}

if ($hasError) {
    exit 1
}
exit 0
