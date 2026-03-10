param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("start", "stop", "status")]
    [string]$Action,
    [string]$Root = "",
    [switch]$DryRun,
    [switch]$SkipBackgroundGuards,
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only"
)

Set-StrictMode -Version Latest

$ErrorActionPreference = "Stop"
$Script:WmiOperationTimeoutSec = 6
$Script:ControlLockHandle = $null
$Script:ControlLockPath = ""

function Resolve-Root {
    param([string]$InputRoot = "")
    if ([string]::IsNullOrWhiteSpace($InputRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $InputRoot).Path
}

function Get-PythonPath {
    param([string]$RuntimeRoot)
    $candidates = @(
        "C:\OANDA_VENV\.venv\Scripts\python.exe",
        (Join-Path $RuntimeRoot ".venv\Scripts\python.exe")
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            return $c
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
        # ignore and continue with plain python fallback
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

function Get-ComponentProcessRows {
    param(
        [string]$RuntimeRoot,
        [string]$ScriptName
    )
    $binPath = (Join-Path $RuntimeRoot ("BIN\" + $ScriptName))
    $binPathEsc = [regex]::Escape($binPath)
    $scriptEsc = [regex]::Escape([string]$ScriptName)

    $attempt = 0
    while ($attempt -lt 3) {
        try {
            $rows = @(Get-CimInstance Win32_Process -OperationTimeoutSec $Script:WmiOperationTimeoutSec -ErrorAction Stop | Where-Object {
                $_.CommandLine -and (
                    ($_.CommandLine -match $binPathEsc) -or
                    ($_.CommandLine -match $scriptEsc)
                )
            })
            return @($rows)
        } catch {
            Start-Sleep -Milliseconds (250 * ($attempt + 1))
            $attempt += 1
        }
    }
    return @()
}

function Get-ComponentProcessIds {
    param(
        [string]$RuntimeRoot,
        [string]$ScriptName
    )
    $rows = Get-ComponentProcessRows -RuntimeRoot $RuntimeRoot -ScriptName $ScriptName
    $ids = @($rows | ForEach-Object { [int]$_.ProcessId } | Sort-Object -Unique)
    return @($ids)
}

function Test-AcceptablePidTree {
    param(
        [int[]]$ProcessIds
    )
    $ids = @($ProcessIds | Where-Object { [int]$_ -gt 0 } | Sort-Object -Unique)
    if (@($ids).Count -le 1) {
        return $true
    }
    $idSet = @{}
    foreach ($procIdLocal in $ids) { $idSet[[int]$procIdLocal] = $true }
    $rows = @()
    try {
        foreach ($procIdLocal in $ids) {
            $r = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$procIdLocal) -OperationTimeoutSec $Script:WmiOperationTimeoutSec -ErrorAction Stop
            if ($null -ne $r) { $rows += @($r) }
        }
    } catch {
        return $false
    }
    if (@($rows).Count -ne @($ids).Count) {
        return $false
    }
    $roots = @()
    foreach ($row in $rows) {
        $procIdLocal = [int]$row.ProcessId
        $ppid = [int]$row.ParentProcessId
        if (-not $idSet.ContainsKey($ppid)) {
            $roots += @($procIdLocal)
        }
    }
    return (@($roots | Sort-Object -Unique).Count -eq 1)
}

function Get-SafetyBotBridgePid {
    param(
        [int[]]$Ports = @(5555, 5556)
    )
    try {
        $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { @($Ports) -contains [int]$_.LocalPort })
        if (@($listeners).Count -eq 0) {
            return $null
        }
        $byPid = @{}
        foreach ($row in $listeners) {
            $ownerPid = [int]$row.OwningProcess
            if (-not $byPid.ContainsKey($ownerPid)) {
                $byPid[$ownerPid] = New-Object System.Collections.Generic.HashSet[int]
            }
            [void]$byPid[$ownerPid].Add([int]$row.LocalPort)
        }
        foreach ($entry in $byPid.GetEnumerator()) {
            $ownerPid = [int]$entry.Key
            $portSet = $entry.Value
            $coversAll = $true
            foreach ($p in $Ports) {
                if (-not $portSet.Contains([int]$p)) {
                    $coversAll = $false
                    break
                }
            }
            if ($coversAll -and (Test-PidRunning -ProcessId $ownerPid)) {
                return $ownerPid
            }
        }
    } catch {
        return $null
    }
    return $null
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

function Get-FileTailSafe {
    param(
        [string]$Path,
        [int]$TailLines = 30
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    if (-not (Test-Path $Path)) { return "" }
    try {
        return ([string](Get-Content -Path $Path -Tail ([Math]::Max(1, [int]$TailLines)) -ErrorAction Stop | Out-String)).Trim()
    } catch {
        return ""
    }
}

function Get-SafetyBotHeartbeatOkAgeSec {
    param(
        [string]$LogPath,
        [int]$TailLines = 500
    )
    if ([string]::IsNullOrWhiteSpace($LogPath)) {
        return $null
    }
    if (-not (Test-Path $LogPath)) {
        return $null
    }
    $lines = @()
    try {
        $lines = @(Get-Content -Path $LogPath -Tail ([Math]::Max(50, [int]$TailLines)) -ErrorAction Stop)
    } catch {
        return $null
    }
    if (@($lines).Count -eq 0) {
        return $null
    }
    $rx = [regex]'^(?<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2},\d{3}).*\bBRIDGE_DIAG\b.*\baction=HEARTBEAT\b.*\bstatus=OK\b'
    $lastTs = $null
    foreach ($ln in $lines) {
        $msg = [string]$ln
        if ([string]::IsNullOrWhiteSpace($msg)) { continue }
        $m = $rx.Match($msg)
        if (-not $m.Success) { continue }
        try {
            $parsed = [datetime]::ParseExact(
                [string]$m.Groups["ts"].Value,
                "yyyy-MM-dd HH:mm:ss,fff",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            $lastTs = $parsed
        } catch {
            continue
        }
    }
    if ($null -eq $lastTs) {
        return $null
    }
    return [double]((Get-Date) - $lastTs).TotalSeconds
}

function Get-SafetyBotBridgeIssueHint {
    param(
        [string]$LogPath,
        [int]$TailLines = 500
    )
    if ([string]::IsNullOrWhiteSpace($LogPath)) { return $null }
    if (-not (Test-Path $LogPath)) { return $null }
    try {
        $tail = [string](Get-Content -Path $LogPath -Tail ([Math]::Max(50, [int]$TailLines)) -ErrorAction Stop | Out-String)
    } catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($tail)) { return $null }
    if ($tail -match "\bNO_ACTIVE_PEER\b") { return "no_active_peer" }
    if ($tail -match "\bSEND_TIMEOUT\b") { return "send_timeout" }
    if ($tail -match "\bIPC send failed\b") { return "ipc_send_failed" }
    return $null
}

function Get-Mt5ProfileLoadIssueHint {
    param(
        [string]$RuntimeRoot,
        [string]$ProfileName = "OANDA_HYBRID_AUTO",
        [int]$TailLines = 300
    )
    $reportPath = Join-Path $RuntimeRoot "RUN\mt5_profile_setup_report.json"
    if (-not (Test-Path $reportPath)) { return $null }
    $profileDir = ""
    try {
        $report = Get-Content -Raw -Encoding UTF8 $reportPath | ConvertFrom-Json
        $profileDir = [string]$report.profile_dir
    } catch {
        $profileDir = ""
    }

    $latestLog = $null
    if (-not [string]::IsNullOrWhiteSpace($profileDir)) {
        $marker = "\MQL5\Profiles\Charts\"
        $idx = $profileDir.IndexOf($marker, [System.StringComparison]::OrdinalIgnoreCase)
        if ($idx -ge 0) {
            $dataDir = $profileDir.Substring(0, $idx)
            if (-not [string]::IsNullOrWhiteSpace($dataDir)) {
                $logDir = Join-Path $dataDir "logs"
                if (Test-Path $logDir) {
                    try {
                        $latestLog = Get-ChildItem $logDir -Filter *.log -ErrorAction Stop | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                    } catch {
                        $latestLog = $null
                    }
                }
            }
        }
    }
    if ($null -eq $latestLog) {
        $terminalBase = Join-Path $env:APPDATA "MetaQuotes\Terminal"
        if (Test-Path $terminalBase) {
            try {
                $latestLog = @(
                    Get-ChildItem $terminalBase -Directory -ErrorAction Stop |
                    ForEach-Object {
                        $d = Join-Path $_.FullName "logs"
                        if (Test-Path $d) {
                            Get-ChildItem $d -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                        }
                    }
                ) | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            } catch {
                $latestLog = $null
            }
        }
    }
    if ($null -eq $latestLog) { return $null }

    $content = ""
    try {
        if ([int64]$latestLog.Length -le 2MB) {
            $content = [string](Get-Content -Path $latestLog.FullName -Raw -ErrorAction Stop)
        } else {
            $content = [string](Get-Content -Path $latestLog.FullName -Tail ([Math]::Max(80, [int]$TailLines)) -ErrorAction Stop | Out-String)
        }
    } catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($content)) { return $null }

    $profilePat = [regex]::Escape([string]$ProfileName)
    $hasFrameFail = ($content -match "(?is)create new frame .*?CHART\d+\.CHR' failed") -and ($content -match ("(?is)" + $profilePat))
    $hasMdiFail = ($content -match "(?is)\bMDI create failed\b")
    if ($hasFrameFail -and $hasMdiFail) {
        return "mt5_profile_load_failed"
    }
    if ($hasFrameFail) {
        return "mt5_chart_frame_create_failed"
    }
    return $null
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

function Test-PidMatchesScript {
    param(
        [int]$ProcessId,
        [string]$RuntimeRoot,
        [string]$ScriptName
    )
    if ($ProcessId -le 0) {
        return $false
    }
    if ([string]::IsNullOrWhiteSpace($ScriptName)) {
        return $false
    }
    $scriptEsc = [regex]::Escape([string]$ScriptName)
    $binPath = Join-Path $RuntimeRoot ("BIN\" + [string]$ScriptName)
    $binPathEsc = [regex]::Escape($binPath)
    try {
        $row = Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f [int]$ProcessId) -OperationTimeoutSec $Script:WmiOperationTimeoutSec -ErrorAction Stop
        if ($null -eq $row -or [string]::IsNullOrWhiteSpace([string]$row.CommandLine)) {
            return $false
        }
        $cmd = [string]$row.CommandLine
        return (($cmd -match $scriptEsc) -or ($cmd -match $binPathEsc))
    } catch {
        return $false
    }
}

function Set-LockPid {
    param(
        [string]$LockPath,
        [int]$LockPidValue,
        [switch]$Dry
    )
    if (-not $LockPath) {
        return "n/a"
    }
    if ($Dry) {
        return "dry_run"
    }
    try {
        [System.IO.File]::WriteAllText($LockPath, ([string]$LockPidValue))
        return "written"
    } catch {
        return "write_failed"
    }
}

function Acquire-ControlLock {
    param(
        [string]$RuntimeRoot,
        [int]$TimeoutSec = 45
    )
    $lockPath = Join-Path $RuntimeRoot "RUN\system_control.action.lock"
    $started = Get-Date
    while (((Get-Date) - $started).TotalSeconds -lt [double]([Math]::Max(1, [int]$TimeoutSec))) {
        try {
            $fs = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            $payload = @{
                pid = [int]$PID
                ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            } | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes([string]$payload)
            $fs.Write($bytes, 0, $bytes.Length)
            $fs.Flush()
            $Script:ControlLockHandle = $fs
            $Script:ControlLockPath = $lockPath
            return @{
                ok = $true
                path = $lockPath
                waited_sec = [double]((Get-Date) - $started).TotalSeconds
                state = "acquired"
            }
        } catch {
            try {
                if (Test-Path $lockPath) {
                    $lockPid = Get-LockPid -LockPath $lockPath
                    if ($null -ne $lockPid) {
                        if (-not (Test-PidRunning -ProcessId ([int]$lockPid))) {
                            Remove-Item -Force $lockPath -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 120
                            continue
                        }
                    } else {
                        $age = Get-FileAgeSec -Path $lockPath
                        if ($null -ne $age -and [double]$age -gt 600.0) {
                            Remove-Item -Force $lockPath -ErrorAction SilentlyContinue
                            Start-Sleep -Milliseconds 120
                            continue
                        }
                    }
                }
            } catch {
                # ignore and retry
            }
            Start-Sleep -Milliseconds 250
        }
    }
    return @{
        ok = $false
        path = $lockPath
        waited_sec = [double]((Get-Date) - $started).TotalSeconds
        state = "timeout"
    }
}

function Release-ControlLock {
    if ($null -ne $Script:ControlLockHandle) {
        try {
            $Script:ControlLockHandle.Dispose()
        } catch {
            # ignore
        }
        $Script:ControlLockHandle = $null
    }
    if (-not [string]::IsNullOrWhiteSpace($Script:ControlLockPath)) {
        try {
            Remove-Item -Force $Script:ControlLockPath -ErrorAction SilentlyContinue
        } catch {
            # ignore
        }
        $Script:ControlLockPath = ""
    }
}

function Deduplicate-ComponentInstances {
    param(
        [string]$RuntimeRoot,
        [string]$ScriptName,
        [string]$LockPath = "",
        [switch]$Dry
    )
    $ids = Get-ComponentProcessIds -RuntimeRoot $RuntimeRoot -ScriptName $ScriptName
    $uniq = @($ids | Sort-Object -Unique)
    if (@($uniq).Count -le 1) {
        return @{
            status = "not_needed"
            initial_pids = @($uniq)
            keep_pid = if (@($uniq).Count -eq 1) { [int]$uniq[0] } else { $null }
            stop_states = @()
            remaining_pids = @($uniq)
            lock_update = "n/a"
        }
    }

    $keepPid = $null
    $lockPid = $null
    if ($LockPath -and (Test-Path $LockPath)) {
        $lockPid = Get-LockPid -LockPath $LockPath
    }
    if ($null -ne $lockPid -and ((@($uniq) -contains [int]$lockPid)) -and (Test-PidRunning -ProcessId ([int]$lockPid))) {
        $keepPid = [int]$lockPid
    } else {
        $keepPid = [int]((@($uniq | Sort-Object -Descending))[0])
    }

    $stopStates = @()
    foreach ($procId in $uniq) {
        if ([int]$procId -eq [int]$keepPid) {
            continue
        }
        $stopStates += @{
            pid = [int]$procId
            state = (Stop-PidSafely -ProcessId ([int]$procId) -Dry:$Dry)
        }
    }

    if (-not $Dry) {
        Start-Sleep -Milliseconds 350
    }
    $remaining = if ($Dry) { @($uniq) } else { @(Get-ComponentProcessIds -RuntimeRoot $RuntimeRoot -ScriptName $ScriptName) }
    $lockUpdate = if ($LockPath -and $keepPid -gt 0) { Set-LockPid -LockPath $LockPath -LockPidValue ([int]$keepPid) -Dry:$Dry } else { "n/a" }
    $ok = (@($remaining).Count -le 1)
    return @{
        status = if ($ok) { "deduplicated" } else { "dedupe_failed" }
        initial_pids = @($uniq)
        keep_pid = [int]$keepPid
        stop_states = @($stopStates)
        remaining_pids = @($remaining | Sort-Object -Unique)
        lock_update = $lockUpdate
    }
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
    $lockPidForProbe = $null
    if ($LockPath -and (Test-Path $LockPath)) {
        try {
            $lockPidForProbe = Get-LockPid -LockPath $LockPath
        } catch {
            $lockPidForProbe = $null
        }
    }
    if ((@($existing).Count -eq 0) -and ($null -ne $lockPidForProbe) -and (Test-PidRunning -ProcessId ([int]$lockPidForProbe))) {
        if (Test-PidMatchesScript -ProcessId ([int]$lockPidForProbe) -RuntimeRoot $RuntimeRoot -ScriptName ([string]$Comp.Script)) {
            $existing = @([int]$lockPidForProbe)
        }
    }
    if (([string]$Comp.Name -eq "SafetyBot") -and (@($existing).Count -eq 0)) {
        $bridgePid = Get-SafetyBotBridgePid
        if ($null -ne $bridgePid) {
            $existing = @([int]$bridgePid)
        }
    }
    if (@($existing).Count -gt 0) {
        $lockRepairState = "n/a"
        if ($LockPath -and (-not (Test-Path $LockPath))) {
            $repairPid = [int]((@($existing | Sort-Object -Descending))[0])
            if ($repairPid -gt 0) {
                $lockRepairState = Set-LockPid -LockPath $LockPath -LockPidValue $repairPid -Dry:$Dry
            }
        }
        if (@($existing).Count -gt 1) {
            if (([string]$Comp.Name -eq "SafetyBot") -and (Test-AcceptablePidTree -ProcessIds @($existing))) {
                return @{
                    status = "already_running_multi_pid_accepted"
                    pids = @($existing)
                    lock_repair = $lockRepairState
                }
            }
            $dedupe = Deduplicate-ComponentInstances -RuntimeRoot $RuntimeRoot -ScriptName ([string]$Comp.Script) -LockPath $LockPath -Dry:$Dry
            if ($dedupe.status -eq "dedupe_failed") {
                return @{
                    status = "duplicate_running"
                    pids = @($existing)
                    dedupe = $dedupe
                    lock_repair = $lockRepairState
                }
            }
            return @{
                status = "deduplicated_running"
                pids = @($dedupe.remaining_pids)
                dedupe = $dedupe
                lock_repair = $lockRepairState
            }
        }
        return @{
            status = "already_running"
            pids = @($existing)
            lock_repair = $lockRepairState
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
        # Guard against PID reuse without creating duplicate runtimes:
        # if lock pid is alive AND belongs to target script, treat as running.
        if (($null -ne $lockInfo.pid) -and (Test-PidRunning -ProcessId ([int]$lockInfo.pid))) {
            $matchesScript = Test-PidMatchesScript -ProcessId ([int]$lockInfo.pid) -RuntimeRoot $RuntimeRoot -ScriptName ([string]$Comp.Script)
            if ($matchesScript) {
                return @{
                    status = "already_running_lock_pid"
                    pids = @([int]$lockInfo.pid)
                    lock = $LockPath
                }
            }
            # Only here we accept lock cleanup as stale PID reuse.
            if ((Test-Path $LockPath) -and (-not $Dry)) {
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
            } elseif ((Test-Path $LockPath) -and $Dry) {
                $lockInfo = @{
                    status = "dry_run_stale_pid_reuse"
                    pid = $lockInfo.pid
                }
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
            try { [void]$proc.WaitForExit(2000) } catch {}
            try { $proc.Refresh() } catch {}
            $exitCode = $null
            try { $exitCode = [int]$proc.ExitCode } catch { $exitCode = $null }
            return @{
                status = "start_failed_exited"
                pid = [int]$proc.Id
                exit_code = $exitCode
                stdout_log = $outLog
                stderr_log = $errLog
                stderr_tail = (Get-FileTailSafe -Path $errLog -TailLines 30)
                lock = $LockPath
                lock_cleanup = $lockInfo.status
            }
        }
        if ([string]$Comp.Name -eq "SafetyBot") {
            $lockStable = $false
            $lockProbePid = $null
            $probeDeadline = (Get-Date).AddSeconds(6)
            while ((Get-Date) -lt $probeDeadline) {
                $proc.Refresh()
                if ($proc.HasExited) {
                    try { [void]$proc.WaitForExit(2000) } catch {}
                    try { $proc.Refresh() } catch {}
                    $exitCode = $null
                    try { $exitCode = [int]$proc.ExitCode } catch { $exitCode = $null }
                    return @{
                        status = "start_failed_exited"
                        pid = [int]$proc.Id
                        exit_code = $exitCode
                        stdout_log = $outLog
                        stderr_log = $errLog
                        stderr_tail = (Get-FileTailSafe -Path $errLog -TailLines 30)
                        lock = $LockPath
                        lock_cleanup = $lockInfo.status
                    }
                }
                if ($LockPath -and (Test-Path $LockPath)) {
                    $lockProbePid = Get-LockPid -LockPath $LockPath
                    if (($null -ne $lockProbePid) -and ([int]$lockProbePid -gt 0) -and (Test-PidRunning -ProcessId ([int]$lockProbePid))) {
                        $lockStable = $true
                        break
                    }
                }
                Start-Sleep -Milliseconds 400
            }
            if (-not $lockStable) {
                return @{
                    status = "start_failed_no_lock"
                    pid = [int]$proc.Id
                    stdout_log = $outLog
                    stderr_log = $errLog
                    stderr_tail = (Get-FileTailSafe -Path $errLog -TailLines 30)
                    lock = $LockPath
                    lock_pid = $lockProbePid
                    lock_cleanup = $lockInfo.status
                }
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

function Stop-BackgroundGuard {
    param(
        [string]$RuntimeRoot,
        [string]$Name,
        [string]$PidFileRel,
        [switch]$Dry
    )
    $pidPath = Join-Path $RuntimeRoot $PidFileRel
    $pidVal = Get-LockPid -LockPath $pidPath
    $state = "not_running"
    if ($null -ne $pidVal -and [int]$pidVal -gt 0) {
        $state = (Stop-PidSafely -ProcessId ([int]$pidVal) -Dry:$Dry)
    }
    $cleanup = "missing"
    if (Test-Path $pidPath) {
        if ($Dry) {
            $cleanup = "dry_run"
        } else {
            try {
                Remove-Item -Force $pidPath -ErrorAction Stop
                $cleanup = "removed"
            } catch {
                $cleanup = "remove_failed"
            }
        }
    }
    return [ordered]@{
        name = $Name
        pid_file = $pidPath
        pid = if ($null -eq $pidVal) { $null } else { [int]$pidVal }
        stop_state = $state
        pid_cleanup = $cleanup
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

function Write-SystemDesiredState {
    param(
        [string]$RuntimeRoot,
        [string]$DesiredState,
        [switch]$Dry
    )
    $path = Join-Path $RuntimeRoot "RUN\system_desired_state.json"
    if ($Dry) {
        return [ordered]@{
            path = $path
            status = "dry_run"
            desired_state = $DesiredState
        }
    }
    $payload = [ordered]@{
        desired_state = [string]$DesiredState
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        source = "SYSTEM_CONTROL"
    }
    $ok = Write-JsonAtomic -Path $path -Object $payload
    return [ordered]@{
        path = $path
        status = if ($ok) { "written" } else { "write_failed" }
        desired_state = $DesiredState
    }
}

$runtimeRoot = Resolve-Root -InputRoot $Root
if (-not (Test-Path (Join-Path $runtimeRoot "BIN"))) {
    Write-Error "BIN directory missing under root: $runtimeRoot"
    exit 2
}
New-Item -ItemType Directory -Force -Path (Join-Path $runtimeRoot "RUN") | Out-Null

$allComponents = @(
    @{ Name = "SafetyBot"; Script = "safetybot.py"; Args = @(); Lock = "RUN\safetybot.lock" },
    @{ Name = "SCUD"; Script = "scudfab02.py"; Args = @("loop", "10"); Lock = "RUN\scudfab02.lock" },
    @{ Name = "Learner"; Script = "learner_offline.py"; Args = @("loop", "3600"); Lock = "" },
    @{ Name = "InfoBot"; Script = "infobot.py"; Args = @(); Lock = "RUN\infobot.lock" },
    @{ Name = "RepairAgent"; Script = "repair_agent.py"; Args = @(); Lock = "RUN\repair_agent.lock" }
)

$components = @($allComponents)
if ($Profile -eq "safety_only") {
    $components = @(
        $allComponents | Where-Object { [string]$_.Name -eq "SafetyBot" }
    )
}

$pythonPath = Get-PythonPath -RuntimeRoot $runtimeRoot
$result = [ordered]@{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    action = $Action
    dry_run = [bool]$DryRun
    profile = $Profile
    root = $runtimeRoot
    python = $pythonPath
    components = @()
}

$hasError = $false
$controlLock = @{
    mode = "not_required"
}

if ($Action -in @("start", "stop")) {
    $controlLock = Acquire-ControlLock -RuntimeRoot $runtimeRoot -TimeoutSec 45
    if (-not [bool]$controlLock.ok) {
        $hasError = $true
        $result.control_lock = $controlLock
        $result.status = "FAIL"
        $statusPath = Join-Path $runtimeRoot "RUN\system_control_last.json"
        $writeOk = Write-JsonAtomic -Path $statusPath -Object $result
        Write-Output ("SYSTEM_CONTROL action={0} status={1} dry_run={2} root={3}" -f $Action, $result.status, [int]([bool]$DryRun), $runtimeRoot)
        if (-not $writeOk) {
            Write-Warning ("SYSTEM_CONTROL: could not write status file at {0}" -f $statusPath)
        }
        exit 1
    }
}
$result.control_lock = $controlLock

try {
    switch ($Action) {
        "status" {
            foreach ($c in $components) {
                $ids = Get-ComponentProcessIds -RuntimeRoot $runtimeRoot -ScriptName ([string]$c.Script)
                $lockPath = if ([string]::IsNullOrWhiteSpace([string]$c.Lock)) { "" } else { Join-Path $runtimeRoot ([string]$c.Lock) }
                $lockExists = if ($lockPath) { Test-Path $lockPath } else { $false }
                $lockPid = $null
                $lockPidRunning = $false
                $runtimeHint = "none"
                if ($lockPath -and $lockExists) {
                    try {
                        $lockPid = Get-LockPid -LockPath $lockPath
                        if ($null -ne $lockPid) {
                            $lockPidRunning = Test-PidRunning -ProcessId ([int]$lockPid)
                            if ($lockPidRunning -and ((@($ids) -notcontains [int]$lockPid))) {
                                $ids += [int]$lockPid
                                $ids = @($ids | Sort-Object -Unique)
                            }
                        }
                    } catch {
                        $lockPid = $null
                        $lockPidRunning = $false
                    }
                }
                if (([string]$c.Name -eq "SafetyBot") -and (@($ids).Count -eq 0) -and (-not $lockPidRunning)) {
                    $bridgePid = Get-SafetyBotBridgePid
                    if ($null -ne $bridgePid) {
                        $ids += [int]$bridgePid
                        $ids = @($ids | Sort-Object -Unique)
                        $runtimeHint = "bridge_ports_5555_5556"
                    }
                }
                $logPath = Get-ComponentLogPath -RuntimeRoot $runtimeRoot -CompName ([string]$c.Name)
                $logAgeSec = if ($logPath) { Get-FileAgeSec -Path $logPath } else { $null }
                $ttl = Get-ComponentLogTtlSec -CompName ([string]$c.Name)
                $logFresh = $false
                if ($null -ne $logAgeSec) {
                    $logFresh = ([double]$logAgeSec -le [double]$ttl)
                }
                $runningByPid = [bool]((@($ids).Count -gt 0) -or $lockPidRunning)
                $multiPidTreeOk = $false
                if (([string]$c.Name -eq "SafetyBot") -and (@($ids).Count -gt 1)) {
                    $multiPidTreeOk = Test-AcceptablePidTree -ProcessIds @($ids)
                }
                $duplicatePids = [bool](([string]$c.Name -eq "SafetyBot") -and (@($ids).Count -gt 1) -and (-not $multiPidTreeOk))
                # WMI can be restricted on some hosts; for SafetyBot heartbeat fallback is accepted
                # only with an existing lock and fresh HEARTBEAT=OK evidence in log.
                $runningByHeartbeat = $false
                $heartbeatOkAgeSec = $null
                $heartbeatOkRecent = $false
                $bridgeIssueHint = $null
                $profileIssueHint = $null
                if ([string]$c.Name -eq "SafetyBot") {
                    $heartbeatOkAgeSec = Get-SafetyBotHeartbeatOkAgeSec -LogPath $logPath -TailLines 500
                    if ($null -ne $heartbeatOkAgeSec) {
                        $heartbeatOkRecent = ([double]$heartbeatOkAgeSec -le [double]([Math]::Min([int]$ttl, 45)))
                    }
                    $runningByHeartbeat = ([bool]$lockExists -and [bool]$logFresh -and [bool]$heartbeatOkRecent -and (-not [bool]$runningByPid))
                } else {
                    $runningByHeartbeat = [bool]$logFresh
                }
                $bridgePeerReady = $true
                if ([string]$c.Name -eq "SafetyBot") {
                    $bridgePeerReady = [bool]$heartbeatOkRecent
                    if (-not $bridgePeerReady) {
                        $bridgeIssueHint = Get-SafetyBotBridgeIssueHint -LogPath $logPath -TailLines 500
                        $profileIssueHint = Get-Mt5ProfileLoadIssueHint -RuntimeRoot $runtimeRoot -ProfileName "OANDA_HYBRID_AUTO" -TailLines 320
                        if ([string]$runtimeHint -eq "none") {
                            if (-not [string]::IsNullOrWhiteSpace([string]$profileIssueHint)) {
                                $runtimeHint = [string]$profileIssueHint
                            } elseif (-not [string]::IsNullOrWhiteSpace([string]$bridgeIssueHint)) {
                                $runtimeHint = [string]$bridgeIssueHint
                            }
                        }
                    }
                }
                $result.components += [ordered]@{
                    name = [string]$c.Name
                    script = [string]$c.Script
                    running = ([bool]$runningByPid -or [bool]$runningByHeartbeat)
                    running_by_pid = [bool]$runningByPid
                    running_by_heartbeat = [bool]$runningByHeartbeat
                    duplicate_pids = [bool]$duplicatePids
                    pids = @($ids)
                    lock = $lockPath
                    lock_exists = [bool]$lockExists
                    lock_pid = $lockPid
                    lock_pid_running = [bool]$lockPidRunning
                    multi_pid_tree_ok = [bool]$multiPidTreeOk
                    log_path = $logPath
                    log_age_sec = $logAgeSec
                    log_ttl_sec = [int]$ttl
                    heartbeat_ok_age_sec = $heartbeatOkAgeSec
                    heartbeat_ok_recent = [bool]$heartbeatOkRecent
                    bridge_peer_ready = [bool]$bridgePeerReady
                    bridge_issue_hint = $bridgeIssueHint
                    mt5_profile_issue = $profileIssueHint
                    runtime_hint = $runtimeHint
                }
                if (-not ([bool]$runningByPid -or [bool]$runningByHeartbeat)) {
                    $hasError = $true
                }
                if ($duplicatePids) {
                    $hasError = $true
                }
                if (([string]$c.Name -eq "SafetyBot") -and [bool]$runningByPid -and (-not [bool]$heartbeatOkRecent)) {
                    $hasError = $true
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
                if (@("start_failed", "start_failed_exited", "start_failed_no_lock", "missing_script", "blocked_active_lock", "blocked_stale_lock", "duplicate_running") -contains [string]$item.status) {
                    $hasError = $true
                }
                $result.components += $row
            }
        }
        "stop" {
            foreach ($c in $components) {
                $lockPath = if ([string]::IsNullOrWhiteSpace([string]$c.Lock)) { "" } else { Join-Path $runtimeRoot ([string]$c.Lock) }
                $initialPids = @()
                $stopStates = @()
                for ($pass = 1; $pass -le 3; $pass++) {
                    $pids = @()
                    if ($lockPath) {
                        $lockPid = Get-LockPid -LockPath $lockPath
                        if ($null -ne $lockPid -and [int]$lockPid -gt 0) {
                            $pids += [int]$lockPid
                        }
                    }
                    $pids += Get-ComponentProcessIds -RuntimeRoot $runtimeRoot -ScriptName ([string]$c.Script)
                    if (([string]$c.Name -eq "SafetyBot") -and (@($pids).Count -eq 0)) {
                        $bridgePid = Get-SafetyBotBridgePid
                        if ($null -ne $bridgePid) {
                            $pids += [int]$bridgePid
                        }
                    }
                    $pids = @($pids | Sort-Object -Unique)
                    if ($pass -eq 1) {
                        $initialPids = @($pids)
                    }
                    if (@($pids).Count -eq 0) {
                        break
                    }
                    foreach ($procId in $pids) {
                        $stopStates += @{
                            pass = [int]$pass
                            pid = [int]$procId
                            state = (Stop-PidSafely -ProcessId ([int]$procId) -Dry:$DryRun)
                        }
                    }
                    if (-not $DryRun) {
                        Start-Sleep -Milliseconds 350
                    }
                }

                $remaining = @()
                if ($lockPath) {
                    $lockPidPost = Get-LockPid -LockPath $lockPath
                    if ($null -ne $lockPidPost -and [int]$lockPidPost -gt 0 -and (Test-PidRunning -ProcessId ([int]$lockPidPost))) {
                        $remaining += [int]$lockPidPost
                    }
                }
                $remaining += Get-ComponentProcessIds -RuntimeRoot $runtimeRoot -ScriptName ([string]$c.Script)
                $remaining = @($remaining | Sort-Object -Unique)

                $lockState = if ($lockPath) { Remove-LockSafe -LockPath $lockPath -Dry:$DryRun } else { "n/a" }
                if ($stopStates | Where-Object { $_.state -eq "force_failed" }) {
                    $hasError = $true
                }
                if ((-not $DryRun) -and (@($remaining).Count -gt 0)) {
                    $hasError = $true
                }
                if ($lockState -eq "remove_failed") {
                    $hasError = $true
                }

                $result.components += [ordered]@{
                    name = [string]$c.Name
                    script = [string]$c.Script
                    pids = @($initialPids)
                    stop_states = @($stopStates)
                    remaining_pids = @($remaining)
                    lock = $lockPath
                    lock_cleanup = $lockState
                }
            }
            if ($SkipBackgroundGuards) {
                $result.guards = @()
                $result.guards_skipped = $true
            } else {
                $guards = @(
                    @{ name = "MT5RiskGuard"; pid_rel = "RUN\mt5_risk_guard.pid" },
                    @{ name = "MT5SessionGuard"; pid_rel = "RUN\mt5_session_guard.pid" }
                )
                $result.guards = @()
                foreach ($g in $guards) {
                    $gstop = Stop-BackgroundGuard -RuntimeRoot $runtimeRoot -Name ([string]$g.name) -PidFileRel ([string]$g.pid_rel) -Dry:$DryRun
                    $result.guards += $gstop
                    if (([string]$gstop.stop_state) -eq "force_failed" -or ([string]$gstop.pid_cleanup) -eq "remove_failed") {
                        $hasError = $true
                    }
                }
            }
        }
    }
} finally {
    if ($Action -in @("start", "stop")) {
        Release-ControlLock
    }
}

$desiredWrite = $null
if (($Action -eq "start") -and (-not $hasError)) {
    $desiredWrite = Write-SystemDesiredState -RuntimeRoot $runtimeRoot -DesiredState "RUNNING" -Dry:$DryRun
}
if (($Action -eq "stop") -and (-not $hasError)) {
    $desiredWrite = Write-SystemDesiredState -RuntimeRoot $runtimeRoot -DesiredState "STOPPED" -Dry:$DryRun
}
if ($null -ne $desiredWrite) {
    $result.desired_state = $desiredWrite
    if (([string]$desiredWrite.status) -eq "write_failed") {
        $hasError = $true
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
