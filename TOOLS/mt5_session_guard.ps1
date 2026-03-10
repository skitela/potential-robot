param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5DataDir = "",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [int]$PollSec = 5,
    [int]$StartupGraceSec = 300,
    [int]$RestartCooldownSec = 900,
    [int]$DisconnectGraceSec = 20,
    [int]$DisconnectBurstWindowSec = 300,
    [int]$DisconnectBurstThreshold = 3,
    [int]$PolicyRetryWindowSec = 600,
    [int]$PolicyRetryThreshold = 12,
    [int]$FailSafeActivatedWindowSec = 600,
    [int]$FailSafeActivatedThreshold = 8,
    [int]$VirtualHostWarnWindowSec = 3600,
    [int]$VirtualHostWarnAlertThreshold = 5,
    [int]$NoActivePeerWindowSec = 300,
    [int]$NoActivePeerThreshold = 12,
    [int]$NoActivePeerGraceSec = 180,
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
    $start = [int64]0
    if (-not $Offsets.ContainsKey($Path)) {
        # First read: consume recent tail to infer current connectivity state quickly.
        $start = [int64]([Math]::Max(0, ($len - [int64]$MaxReadBytes)))
    } else {
        $start = [int64]$Offsets[$Path]
        if ($len -lt $start) { $start = 0 }
    }
    if (($len - $start) -le 0) {
        $Offsets[$Path] = $len
        return @()
    }
    if (($len - $start) -gt [int64]$MaxReadBytes) {
        $start = [int64]($len - [int64]$MaxReadBytes)
        if ($start -lt 0) { $start = 0 }
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
        $remaining = [int64]($len - $start)
        if ($remaining -lt 0) { $remaining = 0 }
        if ($remaining -gt [int64]2147483647) {
            $remaining = [int64]2147483647
        }
        $toRead = [int]$remaining
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
    $json = $Object | ConvertTo-Json -Depth 10
    $tmp = [System.IO.Path]::Combine(
        $parent,
        ([System.IO.Path]::GetFileName($Path) + ".tmp." + [guid]::NewGuid().ToString("N"))
    )
    try {
        $json | Set-Content -Path $tmp -Encoding UTF8
        Move-Item -Force $tmp $Path
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
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
        [ValidateSet("full", "safety_only")]
        [string]$Profile = "safety_only",
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
        # Guard naprawia runtime i nie powinien ubić samego siebie podczas stop.
        $stopOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sc -Action stop -Root $RuntimeRoot -Profile $Profile -SkipBackgroundGuards 2>&1 | Out-String).Trim()
        Start-Sleep -Seconds 3
        $startOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sc -Action start -Root $RuntimeRoot -Profile $Profile 2>&1 | Out-String).Trim()
        Start-Sleep -Seconds 2
        $statusOut = (& powershell -NoProfile -ExecutionPolicy Bypass -File $sc -Action status -Root $RuntimeRoot -Profile $Profile 2>&1 | Out-String).Trim()
        $ok = ($statusOut -match "status=PASS")
        return @{
            ok = [bool]$ok
            reason = $Reason
            profile = $Profile
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
$safetyLogPath = Join-Path $runtimeRoot "LOGS\safetybot.log"

Write-JsonAtomic -Path $pidPath -Object @{
    pid = [int]$PID
    started_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    profile = $Profile
    mt5_data_dir = $mt5DataDirResolved
    status_path = $statusPath
}

$offsets = @{}
$lostEvents = New-Object System.Collections.ArrayList
$policyRetryEvents = New-Object System.Collections.ArrayList
$severeEvents = New-Object System.Collections.ArrayList
$failSafeActivatedEvents = New-Object System.Collections.ArrayList
$virtualHostWarnEvents = New-Object System.Collections.ArrayList
$noActivePeerEvents = New-Object System.Collections.ArrayList

$lastLostAt = $null
$lastAuthAt = $null
$lastBridgeOkAt = $null
$lastRestartAt = $null
$connectedState = "UNKNOWN"
$lastReason = "NONE"
$scriptStartedAt = Get-Date

$disconnectRx = [regex]'(?i)\bconnection to .* lost\b'
$authRx = [regex]'(?i)\bauthorized on .* through access server\b'
$syncRx = [regex]'(?i)\bterminal synchronized with oanda\b'
$policyRetryRx = [regex]'(?i)\bPOLICY_RUNTIME_OPEN_RETRY\b'
$severeRx = [regex]'(?i)\b(POLICY_RUNTIME_FAILSAFE|ZMQ_INIT_FAIL)\b'
$failSafeActivatedRx = [regex]'(?i)\bFAIL-SAFE ACTIVATED\b'
$virtualHostWarnRx = [regex]'(?i)\bVirtual Hosting\b.*failed to get list of virtual hosts\b'
$noActivePeerRx = [regex]'(?i)\b(NO_ACTIVE_PEER|COMMAND_SEND_TIMEOUT)\b'
$bridgeOkRx = [regex]'(?i)\bBRIDGE_DIAG\b.*\baction=HEARTBEAT\b.*\bstatus=OK\b'

Write-Output ("MT5_SESSION_GUARD start root={0} mt5_dir={1} profile={2} poll={3}s cooldown={4}s" -f $runtimeRoot, $mt5DataDirResolved, $Profile, [int]$PollSec, [int]$RestartCooldownSec)

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
                $isBootstrapRead = (-not $offsets.ContainsKey($lf.FullName))
                $newLines = Read-AppendedLines -Path $lf.FullName -Offsets $offsets
                foreach ($line in $newLines) {
                    $msg = [string]$line
                    if ([string]::IsNullOrWhiteSpace($msg)) { continue }
                    if ($disconnectRx.IsMatch($msg)) {
                        $lastLostAt = $now
                        if (-not $isBootstrapRead) {
                            [void]$lostEvents.Add($now)
                            $connectedState = "DISCONNECTED"
                            Append-Jsonl -Path $eventPath -Payload @{
                                ts_utc = $nowUtc
                                event = "BROKER_CONNECTION_LOST"
                                message = $msg
                            }
                        } elseif ($connectedState -eq "UNKNOWN") {
                            $connectedState = "DISCONNECTED"
                        }
                    }
                    if ($authRx.IsMatch($msg) -or $syncRx.IsMatch($msg)) {
                        $lastAuthAt = $now
                        $connectedState = "CONNECTED"
                    }
                    if ($policyRetryRx.IsMatch($msg)) {
                        if (-not $isBootstrapRead) {
                            [void]$policyRetryEvents.Add($now)
                        }
                    }
                    if ($severeRx.IsMatch($msg)) {
                        if (-not $isBootstrapRead) {
                            [void]$severeEvents.Add($now)
                            Append-Jsonl -Path $eventPath -Payload @{
                                ts_utc = $nowUtc
                                event = "SEVERE_MT5_EVENT"
                                message = $msg
                            }
                        }
                    }
                    if ($failSafeActivatedRx.IsMatch($msg)) {
                        if (-not $isBootstrapRead) {
                            [void]$failSafeActivatedEvents.Add($now)
                            Append-Jsonl -Path $eventPath -Payload @{
                                ts_utc = $nowUtc
                                event = "FAILSAFE_ACTIVATED_EVENT"
                                severity = "WATCH"
                                message = $msg
                            }
                        }
                    }
                    if ($virtualHostWarnRx.IsMatch($msg)) {
                        if (-not $isBootstrapRead) {
                            [void]$virtualHostWarnEvents.Add($now)
                            Append-Jsonl -Path $eventPath -Payload @{
                                ts_utc = $nowUtc
                                event = "VIRTUAL_HOSTING_WARNING"
                                severity = "WARNING_ONLY"
                                message = $msg
                            }
                        }
                    }
                }
            }
        }

        if (Test-Path $safetyLogPath) {
            $isSafetyBootstrapRead = (-not $offsets.ContainsKey($safetyLogPath))
            $safetyLines = Read-AppendedLines -Path $safetyLogPath -Offsets $offsets
            foreach ($line in $safetyLines) {
                $msg = [string]$line
                if ([string]::IsNullOrWhiteSpace($msg)) { continue }
                if ($bridgeOkRx.IsMatch($msg)) {
                    $lastBridgeOkAt = $now
                }
                if ($noActivePeerRx.IsMatch($msg)) {
                    if (-not $isSafetyBootstrapRead) {
                        [void]$noActivePeerEvents.Add($now)
                        Append-Jsonl -Path $eventPath -Payload @{
                            ts_utc = $nowUtc
                            event = "NO_ACTIVE_PEER_EVENT"
                            severity = "WATCH"
                            message = $msg
                        }
                    }
                }
            }
        }

        Prune-Timestamps -List $lostEvents -WindowSec ([Math]::Max(60, [int]$DisconnectBurstWindowSec)) -Now $now
        Prune-Timestamps -List $policyRetryEvents -WindowSec ([Math]::Max(120, [int]$PolicyRetryWindowSec)) -Now $now
        Prune-Timestamps -List $severeEvents -WindowSec 120 -Now $now
        Prune-Timestamps -List $failSafeActivatedEvents -WindowSec ([Math]::Max(120, [int]$FailSafeActivatedWindowSec)) -Now $now
        Prune-Timestamps -List $virtualHostWarnEvents -WindowSec ([Math]::Max(300, [int]$VirtualHostWarnWindowSec)) -Now $now
        Prune-Timestamps -List $noActivePeerEvents -WindowSec ([Math]::Max(60, [int]$NoActivePeerWindowSec)) -Now $now

        $desired = Get-SystemDesiredState -Path $desiredStatePath
        $allowRepair = ([string]$desired.state -eq "RUNNING")
        $virtualHostWarnAlert = ([int]$virtualHostWarnEvents.Count -ge [int]([Math]::Max(1, [int]$VirtualHostWarnAlertThreshold)))
        $startupGraceActive = ((($now - $scriptStartedAt).TotalSeconds) -lt [double]([Math]::Max(0, [int]$StartupGraceSec)))

        $cooldownOk = $true
        if ($null -ne $lastRestartAt) {
            $cooldownOk = ((($now - $lastRestartAt).TotalSeconds) -ge [double]([Math]::Max(60, [int]$RestartCooldownSec)))
        }
        $repairWindowOpen = ($cooldownOk -and (-not $startupGraceActive))

        $shouldRepair = $false
        $repairReason = ""
        $bridgeOkRecently = $false
        if (($severeEvents.Count -gt 0) -and $repairWindowOpen) {
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
            if ($isDisconnected -and $repairWindowOpen) {
                $downSec = [double]($now - $lastLostAt).TotalSeconds
                if ($downSec -ge [double]([Math]::Max(5, [int]$DisconnectGraceSec))) {
                    $shouldRepair = $true
                    $repairReason = "BROKER_DISCONNECTED_STUCK"
                }
            }
        }

        if (-not $shouldRepair) {
            if (($failSafeActivatedEvents.Count -ge [int]([Math]::Max(2, [int]$FailSafeActivatedThreshold))) -and $repairWindowOpen) {
                $shouldRepair = $true
                $repairReason = "FAILSAFE_ACTIVATION_BURST"
            }
        }

        if (-not $shouldRepair) {
            if (($lostEvents.Count -ge [int]([Math]::Max(1, [int]$DisconnectBurstThreshold))) -and $repairWindowOpen) {
                $shouldRepair = $true
                $repairReason = "BROKER_DISCONNECT_BURST"
            }
        }

        if (-not $shouldRepair) {
            if (($policyRetryEvents.Count -ge [int]([Math]::Max(2, [int]$PolicyRetryThreshold))) -and $repairWindowOpen) {
                $shouldRepair = $true
                $repairReason = "POLICY_RUNTIME_RETRY_BURST"
            }
        }

        if (-not $shouldRepair) {
            $noActivePeerReady = ((($now - $scriptStartedAt).TotalSeconds) -ge [double]([Math]::Max(0, [int]$NoActivePeerGraceSec)))
            if ($null -ne $lastBridgeOkAt) {
                $bridgeOkRecently = ((($now - $lastBridgeOkAt).TotalSeconds) -le [double]([Math]::Max(30, [int]$NoActivePeerGraceSec)))
            }
            if ($noActivePeerReady -and (-not $bridgeOkRecently) -and ($noActivePeerEvents.Count -ge [int]([Math]::Max(1, [int]$NoActivePeerThreshold))) -and $repairWindowOpen) {
                $shouldRepair = $true
                $repairReason = "NO_ACTIVE_PEER_BURST"
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
            $repair = Invoke-SystemRepair -RuntimeRoot $runtimeRoot -Reason $repairReason -Profile $Profile -Dry:$DryRun
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
                failsafe_activated_window = [int]$failSafeActivatedEvents.Count
                no_active_peer_window = [int]$noActivePeerEvents.Count
                no_active_peer_window_sec = [int]$NoActivePeerWindowSec
                no_active_peer_threshold = [int]$NoActivePeerThreshold
            }
            $lostEvents.Clear()
            $policyRetryEvents.Clear()
            $severeEvents.Clear()
            $failSafeActivatedEvents.Clear()
            $noActivePeerEvents.Clear()
        }

        $status = @{
            schema = "oanda_mt5.mt5_session_guard.v1"
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            root = $runtimeRoot
            profile = $Profile
            mt5_data_dir = $mt5DataDirResolved
            mt5_log = $(if (@($activeLogs).Count -gt 0) { [string]$activeLogs[0] } else { "" })
            mt5_logs = @($activeLogs)
            connected_state = $connectedState
            desired_state = [string]$desired.state
            desired_state_source = [string]$desired.source
            desired_state_ts_utc = [string]$desired.ts_utc
            repairs_allowed = [bool]$allowRepair
            startup_grace_sec = [int]$StartupGraceSec
            startup_grace_active = [bool]$startupGraceActive
            last_lost_utc = $(if ($null -eq $lastLostAt) { "" } else { $lastLostAt.ToUniversalTime().ToString("o") })
            last_authorized_utc = $(if ($null -eq $lastAuthAt) { "" } else { $lastAuthAt.ToUniversalTime().ToString("o") })
            lost_events_window = [int]$lostEvents.Count
            policy_retry_window = [int]$policyRetryEvents.Count
            severe_events_window = [int]$severeEvents.Count
            failsafe_activated_window = [int]$failSafeActivatedEvents.Count
            virtual_hosting_warning_window = [int]$virtualHostWarnEvents.Count
            virtual_hosting_warning_alert = [bool]$virtualHostWarnAlert
            no_active_peer_window = [int]$noActivePeerEvents.Count
            last_bridge_ok_utc = $(if ($null -eq $lastBridgeOkAt) { "" } else { $lastBridgeOkAt.ToUniversalTime().ToString("o") })
            no_active_peer_bridge_ok_recent = [bool]$bridgeOkRecently
            last_restart_utc = $(if ($null -eq $lastRestartAt) { "" } else { $lastRestartAt.ToUniversalTime().ToString("o") })
            last_restart_reason = $lastReason
            cooldown_ok = [bool]$cooldownOk
            thresholds = @{
                disconnect_grace_sec = [int]$DisconnectGraceSec
                disconnect_burst_window_sec = [int]$DisconnectBurstWindowSec
                disconnect_burst_threshold = [int]$DisconnectBurstThreshold
                policy_retry_window_sec = [int]$PolicyRetryWindowSec
                policy_retry_threshold = [int]$PolicyRetryThreshold
                failsafe_activated_window_sec = [int]$FailSafeActivatedWindowSec
                failsafe_activated_threshold = [int]$FailSafeActivatedThreshold
                no_active_peer_window_sec = [int]$NoActivePeerWindowSec
                no_active_peer_threshold = [int]$NoActivePeerThreshold
                no_active_peer_grace_sec = [int]$NoActivePeerGraceSec
                virtual_hosting_warn_window_sec = [int]$VirtualHostWarnWindowSec
                virtual_hosting_warn_alert_threshold = [int]$VirtualHostWarnAlertThreshold
                restart_cooldown_sec = [int]$RestartCooldownSec
                startup_grace_sec = [int]$StartupGraceSec
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
            profile = $Profile
            mt5_data_dir = $mt5DataDirResolved
            connected_state = $connectedState
            last_restart_reason = $lastReason
            dry_run = [bool]$DryRun
            loop_error = $err
        }
    }
    Start-Sleep -Seconds ([Math]::Max(2, [int]$PollSec))
}
