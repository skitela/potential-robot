param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5DataDir = "",
    [int]$PollSec = 5,
    [int]$RestartCooldownSec = 900,
    [int]$DisconnectGraceSec = 20,
    [int]$DisconnectBurstWindowSec = 300,
    [int]$DisconnectBurstThreshold = 3,
    [int]$PolicyRetryWindowSec = 600,
    [int]$PolicyRetryThreshold = 12,
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

function Resolve-Mt5DataDir {
    param([string]$Preferred = "")
    if (-not [string]::IsNullOrWhiteSpace($Preferred) -and (Test-Path $Preferred)) {
        return (Resolve-Path $Preferred).Path
    }
    $appData = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($appData)) {
        return ""
    }
    $base = Join-Path $appData "MetaQuotes\Terminal"
    if (-not (Test-Path $base)) {
        return ""
    }
    $bestDir = ""
    $bestTs = [datetime]::MinValue
    foreach ($d in (Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue)) {
        $markerMq5 = Join-Path $d.FullName "MQL5\Experts\HybridAgent.mq5"
        $markerEx5 = Join-Path $d.FullName "MQL5\Experts\HybridAgent.ex5"
        $marker = if (Test-Path $markerMq5) { $markerMq5 } elseif (Test-Path $markerEx5) { $markerEx5 } else { "" }
        if ([string]::IsNullOrWhiteSpace($marker)) { continue }
        try {
            $ts = (Get-Item $marker -ErrorAction Stop).LastWriteTimeUtc
        } catch {
            $ts = [datetime]::MinValue
        }
        if ($ts -gt $bestTs) {
            $bestTs = $ts
            $bestDir = $d.FullName
        }
    }
    return $bestDir
}

function Read-AppendedLines {
    param(
        [string]$Path,
        [hashtable]$Offsets,
        [int64]$MaxReadBytes = 1024KB
    )
    if (-not (Test-Path $Path)) { return @() }

    $item = Get-Item -Path $Path -ErrorAction Stop
    $len = [int64]$item.Length

    if (-not $Offsets.ContainsKey($Path)) {
        $Offsets[$Path] = $len
        return @()
    }
    $start = [int64]$Offsets[$Path]
    if ($len -lt $start) { $start = 0 }
    if (($len - $start) -le 0) {
        $Offsets[$Path] = $len
        return @()
    }
    if (($len - $start) -gt $MaxReadBytes) {
        $start = [Math]::Max(0, $len - $MaxReadBytes)
    }

    if (-not (Get-Variable -Name EncCache -Scope Script -ErrorAction SilentlyContinue)) {
        $Script:EncCache = @{}
    }
    if (-not $Script:EncCache.ContainsKey($Path)) {
        $enc = [System.Text.Encoding]::UTF8
        try {
            $fs0 = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $bom = New-Object byte[] 4
                [void]$fs0.Read($bom, 0, 4)
                if ($bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { $enc = [System.Text.Encoding]::Unicode }
                elseif ($bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { $enc = [System.Text.Encoding]::BigEndianUnicode }
                elseif ($bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) { $enc = [System.Text.Encoding]::UTF8 }
            } finally {
                $fs0.Dispose()
            }
        } catch {
            $enc = [System.Text.Encoding]::UTF8
        }
        $Script:EncCache[$Path] = $enc
    }
    $encUse = [System.Text.Encoding]$Script:EncCache[$Path]
    if (($encUse.WebName -match "utf-16") -and (($start % 2) -ne 0)) {
        $start = [int64]([Math]::Max(0, ($start - 1)))
    }

    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $toRead = [int]([Math]::Max(0, [Math]::Min([int64]2147483647, ($len - $start))))
        if ($toRead -gt $MaxReadBytes) { $toRead = [int]$MaxReadBytes }
        if (($encUse.WebName -match "utf-16") -and (($toRead % 2) -ne 0)) { $toRead -= 1 }
        $txt = ""
        if ($toRead -gt 0) {
            $buf = New-Object byte[] $toRead
            $read = $fs.Read($buf, 0, $toRead)
            if (($encUse.WebName -match "utf-16") -and (($read % 2) -ne 0)) { $read -= 1 }
            if ($read -gt 0) {
                if ($read -ne $toRead) { $buf = $buf[0..($read - 1)] }
                $txt = $encUse.GetString($buf)
            }
        }
    } finally {
        $fs.Dispose()
    }
    $Offsets[$Path] = $len
    if ([string]::IsNullOrWhiteSpace($txt)) { return @() }
    return [System.Text.RegularExpressions.Regex]::Split($txt, "\r?\n")
}

function Prune-Timestamps {
    param(
        [System.Collections.ArrayList]$List,
        [int]$WindowSec,
        [datetime]$Now
    )
    while ($List.Count -gt 0) {
        $first = [datetime]$List[0]
        if (($Now - $first).TotalSeconds -le [double]$WindowSec) { break }
        [void]$List.RemoveAt(0)
    }
}

function Append-Jsonl {
    param([string]$Path, [hashtable]$Payload)
    $line = ($Payload | ConvertTo-Json -Compress -Depth 8)
    Add-Content -Path $Path -Encoding UTF8 -Value $line
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Object)
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = "$Path.tmp"
    $json = $Object | ConvertTo-Json -Depth 10
    $json | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force $tmp $Path
}

function Get-SystemDesiredState {
    param([string]$Path)
    $out = [ordered]@{
        state = "RUNNING"
        source = "default"
        ts_utc = ""
    }
    if (-not (Test-Path $Path)) {
        return $out
    }
    try {
        $raw = Get-Content -Raw -Encoding UTF8 -Path $Path
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $out
        }
        $obj = $raw | ConvertFrom-Json
        $desired = [string]$obj.desired_state
        if (-not [string]::IsNullOrWhiteSpace($desired)) {
            $norm = $desired.Trim().ToUpperInvariant()
            if ($norm -in @("RUNNING", "STOPPED")) {
                $out.state = $norm
            }
        }
        if ($null -ne $obj.ts_utc) {
            $out.ts_utc = [string]$obj.ts_utc
        }
        $out.source = "file"
        return $out
    } catch {
        $out.source = "invalid_file"
        return $out
    }
}

function Invoke-SystemRepair {
    param(
        [string]$RuntimeRoot,
        [string]$Reason,
        [switch]$Dry
    )
    $sc = Join-Path $RuntimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
    if (-not (Test-Path $sc)) {
        return @{
            ok = $false
            reason = $Reason
            error = "missing_system_control"
        }
    }
    if ($Dry) {
        return @{
            ok = $true
            reason = $Reason
            mode = "dry_run"
        }
    }
    try {
        $stopOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sc -Action stop -Root $RuntimeRoot -Profile full 2>&1 | Out-String).Trim()
        Start-Sleep -Seconds 3
        $startOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sc -Action start -Root $RuntimeRoot -Profile full 2>&1 | Out-String).Trim()
        Start-Sleep -Seconds 2
        $statusOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sc -Action status -Root $RuntimeRoot -Profile full 2>&1 | Out-String).Trim()
        $ok = ($statusOut -match "status=PASS")
        return @{
            ok = [bool]$ok
            reason = $Reason
            stop = $stopOut
            start = $startOut
            status = $statusOut
        }
    } catch {
        return @{
            ok = $false
            reason = $Reason
            error = [string]$_.Exception.Message
        }
    }
}

$runtimeRoot = Resolve-RootPath -Path $Root
$mt5DataDirResolved = Resolve-Mt5DataDir -Preferred $Mt5DataDir
$runDir = Join-Path $runtimeRoot "RUN"
$logDir = Join-Path $runtimeRoot "LOGS\monitor"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$statusPath = Join-Path $runDir "mt5_session_guard_status.json"
$pidPath = Join-Path $runDir "mt5_session_guard.pid"
$eventPath = Join-Path $logDir "mt5_session_guard_events.jsonl"
$desiredStatePath = Join-Path $runDir "system_desired_state.json"

Write-JsonAtomic -Path $pidPath -Object @{
    pid = [int]$PID
    started_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    mt5_data_dir = $mt5DataDirResolved
    status_path = $statusPath
}

$offsets = @{}
$lostEvents = New-Object System.Collections.ArrayList
$policyRetryEvents = New-Object System.Collections.ArrayList
$severeEvents = New-Object System.Collections.ArrayList

$lastLostAt = $null
$lastAuthAt = $null
$lastRestartAt = $null
$connectedState = "UNKNOWN"
$lastReason = "NONE"

$disconnectRx = [regex]'(?i)\bconnection to .* lost\b'
$authRx = [regex]'(?i)\bauthorized on .* through access server\b'
$syncRx = [regex]'(?i)\bterminal synchronized with oanda\b'
$policyRetryRx = [regex]'(?i)\bPOLICY_RUNTIME_OPEN_RETRY\b'
$severeRx = [regex]'(?i)\b(POLICY_RUNTIME_FAILSAFE|FAIL-SAFE ACTIVATED|ZMQ_INIT_FAIL)\b'

Write-Output ("MT5_SESSION_GUARD start root={0} mt5_dir={1} poll={2}s cooldown={3}s" -f $runtimeRoot, $mt5DataDirResolved, [int]$PollSec, [int]$RestartCooldownSec)

while ($true) {
    $now = Get-Date
    try {
        $nowUtc = $now.ToUniversalTime().ToString("o")
        $activeLogs = @()
        if (-not [string]::IsNullOrWhiteSpace($mt5DataDirResolved)) {
            $candidateDirs = @(
                (Join-Path $mt5DataDirResolved "logs"),
                (Join-Path $mt5DataDirResolved "MQL5\Logs")
            )
            foreach ($logsDir in $candidateDirs) {
                if (-not (Test-Path $logsDir)) { continue }
                $lf = Get-ChildItem -Path $logsDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if ($null -eq $lf) { continue }
                $activeLogs += @($lf.FullName)
                $newLines = Read-AppendedLines -Path $lf.FullName -Offsets $offsets
                foreach ($line in $newLines) {
                    $msg = [string]$line
                    if ([string]::IsNullOrWhiteSpace($msg)) { continue }
                    if ($disconnectRx.IsMatch($msg)) {
                        $lastLostAt = $now
                        [void]$lostEvents.Add($now)
                        $connectedState = "DISCONNECTED"
                        Append-Jsonl -Path $eventPath -Payload @{
                            ts_utc = $nowUtc
                            event = "BROKER_CONNECTION_LOST"
                            message = $msg
                        }
                    }
                    if ($authRx.IsMatch($msg) -or $syncRx.IsMatch($msg)) {
                        $lastAuthAt = $now
                        $connectedState = "CONNECTED"
                    }
                    if ($policyRetryRx.IsMatch($msg)) {
                        [void]$policyRetryEvents.Add($now)
                    }
                    if ($severeRx.IsMatch($msg)) {
                        [void]$severeEvents.Add($now)
                        Append-Jsonl -Path $eventPath -Payload @{
                            ts_utc = $nowUtc
                            event = "SEVERE_MT5_EVENT"
                            message = $msg
                        }
                    }
                }
            }
        }

        Prune-Timestamps -List $lostEvents -WindowSec ([Math]::Max(60, [int]$DisconnectBurstWindowSec)) -Now $now
        Prune-Timestamps -List $policyRetryEvents -WindowSec ([Math]::Max(120, [int]$PolicyRetryWindowSec)) -Now $now
        Prune-Timestamps -List $severeEvents -WindowSec 120 -Now $now

        $desired = Get-SystemDesiredState -Path $desiredStatePath
        $allowRepair = ([string]$desired.state -eq "RUNNING")

        $cooldownOk = $true
        if ($null -ne $lastRestartAt) {
            $cooldownOk = ((($now - $lastRestartAt).TotalSeconds) -ge [double]([Math]::Max(60, [int]$RestartCooldownSec)))
        }

        $shouldRepair = $false
        $repairReason = ""
        if (($severeEvents.Count -gt 0) -and $cooldownOk) {
            $shouldRepair = $true
            $repairReason = "SEVERE_MT5_EVENT"
        }

        if (-not $shouldRepair) {
            $isDisconnected = $false
            if ($null -ne $lastLostAt) {
                if (($null -eq $lastAuthAt) -or ($lastLostAt -gt $lastAuthAt)) {
                    $isDisconnected = $true
                }
            }
            if ($isDisconnected -and $cooldownOk) {
                $downSec = [double]($now - $lastLostAt).TotalSeconds
                if ($downSec -ge [double]([Math]::Max(5, [int]$DisconnectGraceSec))) {
                    $shouldRepair = $true
                    $repairReason = "BROKER_DISCONNECTED_STUCK"
                }
            }
        }

        if (-not $shouldRepair) {
            if (($lostEvents.Count -ge [int]([Math]::Max(1, [int]$DisconnectBurstThreshold))) -and $cooldownOk) {
                $shouldRepair = $true
                $repairReason = "BROKER_DISCONNECT_BURST"
            }
        }

        if (-not $shouldRepair) {
            if (($policyRetryEvents.Count -ge [int]([Math]::Max(2, [int]$PolicyRetryThreshold))) -and $cooldownOk) {
                $shouldRepair = $true
                $repairReason = "POLICY_RUNTIME_RETRY_BURST"
            }
        }

        if ($shouldRepair -and (-not $allowRepair)) {
            $shouldRepair = $false
            $lastReason = "SKIP_DESIRED_STOPPED"
            Append-Jsonl -Path $eventPath -Payload @{
                ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                event = "AUTO_REPAIR_SKIPPED"
                reason = "DESIRED_STATE_STOPPED"
            }
        }

        if ($shouldRepair) {
            $repair = Invoke-SystemRepair -RuntimeRoot $runtimeRoot -Reason $repairReason -Dry:$DryRun
            $lastRestartAt = Get-Date
            $lastReason = $repairReason
            Append-Jsonl -Path $eventPath -Payload @{
                ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                event = "AUTO_REPAIR_TRIGGERED"
                reason = $repairReason
                result = $repair
                lost_events_window = [int]$lostEvents.Count
                policy_retry_window = [int]$policyRetryEvents.Count
                severe_events_window = [int]$severeEvents.Count
            }
            $lostEvents.Clear()
            $policyRetryEvents.Clear()
            $severeEvents.Clear()
        }

        $status = @{
            schema = "oanda_mt5.mt5_session_guard.v1"
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            root = $runtimeRoot
            mt5_data_dir = $mt5DataDirResolved
            mt5_log = $(if (@($activeLogs).Count -gt 0) { [string]$activeLogs[0] } else { "" })
            mt5_logs = @($activeLogs)
            connected_state = $connectedState
            desired_state = [string]$desired.state
            desired_state_source = [string]$desired.source
            desired_state_ts_utc = [string]$desired.ts_utc
            repairs_allowed = [bool]$allowRepair
            last_lost_utc = $(if ($null -eq $lastLostAt) { "" } else { $lastLostAt.ToUniversalTime().ToString("o") })
            last_authorized_utc = $(if ($null -eq $lastAuthAt) { "" } else { $lastAuthAt.ToUniversalTime().ToString("o") })
            lost_events_window = [int]$lostEvents.Count
            policy_retry_window = [int]$policyRetryEvents.Count
            severe_events_window = [int]$severeEvents.Count
            last_restart_utc = $(if ($null -eq $lastRestartAt) { "" } else { $lastRestartAt.ToUniversalTime().ToString("o") })
            last_restart_reason = $lastReason
            cooldown_ok = [bool]$cooldownOk
            thresholds = @{
                disconnect_grace_sec = [int]$DisconnectGraceSec
                disconnect_burst_window_sec = [int]$DisconnectBurstWindowSec
                disconnect_burst_threshold = [int]$DisconnectBurstThreshold
                policy_retry_window_sec = [int]$PolicyRetryWindowSec
                policy_retry_threshold = [int]$PolicyRetryThreshold
                restart_cooldown_sec = [int]$RestartCooldownSec
            }
            dry_run = [bool]$DryRun
            loop_error = ""
        }
        Write-JsonAtomic -Path $statusPath -Object $status
    } catch {
        $err = [string]$_.Exception.Message
        Append-Jsonl -Path $eventPath -Payload @{
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            event = "LOOP_EXCEPTION"
            error = $err
        }
        Write-JsonAtomic -Path $statusPath -Object @{
            schema = "oanda_mt5.mt5_session_guard.v1"
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            root = $runtimeRoot
            mt5_data_dir = $mt5DataDirResolved
            connected_state = $connectedState
            last_restart_reason = $lastReason
            dry_run = [bool]$DryRun
            loop_error = $err
        }
    }
    Start-Sleep -Seconds ([Math]::Max(2, [int]$PollSec))
}
