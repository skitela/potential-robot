param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$DurationHours = 8,
    [int]$IntervalSec = 60,
    [int]$MinAlive = 3,
    [int]$UnhealthyStrike = 3,
    [int]$SmokeEveryMin = 30,
    [string]$Mt5Path = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
    [int]$SystemControlTimeoutSec = 180,
    [int]$SmokeTimeoutSec = 120,
    [int]$SafetyLogTtlSec = 600,
    [int]$ScudLogTtlSec = 240,
    [int]$InfoLogTtlSec = 300,
    [int]$RepairLogTtlSec = 1200,
    [int]$LearnerLogTtlSec = 4500,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-Root {
    param([string]$InputRoot)
    if ([string]::IsNullOrWhiteSpace($InputRoot)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $InputRoot).Path
}

function Get-FileAgeSec {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $it = Get-Item $Path -ErrorAction Stop
        return [double]((Get-Date) - $it.LastWriteTime).TotalSeconds
    } catch {
        return $null
    }
}

function Write-EventJsonl {
    param(
        [string]$Path,
        [hashtable]$Payload
    )
    $line = ($Payload | ConvertTo-Json -Compress)
    Add-Content -Path $Path -Value $line -Encoding UTF8
}

function Invoke-ToolCommand {
    param(
        [string]$ExePath,
        [string[]]$ArgumentList,
        [string]$WorkingDir,
        [int]$TimeoutSec,
        [string]$StdOutPath,
        [string]$StdErrPath
    )
    $safeTimeout = [Math]::Max(5, [int]$TimeoutSec)
    try {
        $outDir = Split-Path -Parent $StdOutPath
        if ($outDir) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
        $errDir = Split-Path -Parent $StdErrPath
        if ($errDir) {
            New-Item -ItemType Directory -Path $errDir -Force | Out-Null
        }
        $proc = Start-Process -FilePath $ExePath -ArgumentList $ArgumentList -WorkingDirectory $WorkingDir -WindowStyle Hidden -RedirectStandardOutput $StdOutPath -RedirectStandardError $StdErrPath -PassThru -ErrorAction Stop
    } catch {
        return @{
            ok = $false
            timed_out = $false
            exit_code = $null
            pid = $null
            stdout = $StdOutPath
            stderr = $StdErrPath
            error = $_.Exception.Message
        }
    }

    $timedOut = $false
    try {
        Wait-Process -Id $proc.Id -Timeout $safeTimeout -ErrorAction Stop
    } catch {
        $timedOut = $true
    }
    if ($timedOut) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        } catch {
            # best-effort terminate
        }
        return @{
            ok = $false
            timed_out = $true
            exit_code = $null
            pid = [int]$proc.Id
            stdout = $StdOutPath
            stderr = $StdErrPath
            error = "timeout"
        }
    }
    $proc.Refresh()
    $rc = [int]$proc.ExitCode
    return @{
        ok = ($rc -eq 0)
        timed_out = $false
        exit_code = $rc
        pid = [int]$proc.Id
        stdout = $StdOutPath
        stderr = $StdErrPath
        error = $null
    }
}

function Invoke-SystemControlAction {
    param(
        [string]$PwshExe,
        [string]$SystemControlPath,
        [string]$RuntimeRoot,
        [string]$ActionName,
        [int]$TimeoutSec,
        [string]$EvidenceDir
    )
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $outPath = Join-Path $EvidenceDir ("system_control_" + $ActionName + "_" + $stamp + "_out.log")
    $errPath = Join-Path $EvidenceDir ("system_control_" + $ActionName + "_" + $stamp + "_err.log")
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $SystemControlPath, "-Action", $ActionName, "-Root", $RuntimeRoot, "-Profile", "full")
    return (Invoke-ToolCommand -ExePath $PwshExe -ArgumentList $args -WorkingDir $RuntimeRoot -TimeoutSec $TimeoutSec -StdOutPath $outPath -StdErrPath $errPath)
}

function Invoke-SmokeRun {
    param(
        [string]$RuntimeRoot,
        [string]$SmokeScriptPath,
        [string]$SmokeOutPath,
        [string]$Mt5TerminalPath,
        [int]$TimeoutSec,
        [string]$EvidenceDir
    )
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $outPath = Join-Path $EvidenceDir ("smoke_exec_" + $stamp + "_out.log")
    $errPath = Join-Path $EvidenceDir ("smoke_exec_" + $stamp + "_err.log")
    $args = @("-3.12", "-B", $SmokeScriptPath, "--mt5-path", $Mt5TerminalPath, "--out", $SmokeOutPath)
    return (Invoke-ToolCommand -ExePath "py" -ArgumentList $args -WorkingDir $RuntimeRoot -TimeoutSec $TimeoutSec -StdOutPath $outPath -StdErrPath $errPath)
}

function Test-ComponentAlive {
    param(
        [string]$RootPath,
        [string]$Name,
        [string]$LockRel,
        [string]$LogRel,
        [int]$LogTtlSec
    )
    $lockPath = if ([string]::IsNullOrWhiteSpace($LockRel)) { "" } else { Join-Path $RootPath $LockRel }
    $logPath = Join-Path $RootPath $LogRel
    $lockExists = if ($lockPath) { Test-Path $lockPath } else { $false }
    $age = Get-FileAgeSec -Path $logPath
    $logFresh = ($null -ne $age -and $age -le [double]$LogTtlSec)
    $alive = if ($lockPath) { [bool]$lockExists -and [bool]$logFresh } else { [bool]$logFresh }
    return @{
        name = $Name
        lock_exists = [bool]$lockExists
        log_path = $logPath
        log_age_sec = $age
        log_ttl_sec = [int]$LogTtlSec
        alive = [bool]$alive
    }
}

function Get-LatestMt5Log {
    param([string]$RootPath)
    $logDir = Join-Path $RootPath "MQL5\Logs"
    if (-not (Test-Path $logDir)) { return $null }
    $it = Get-ChildItem -Path $logDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    return $it
}

$runtimeRoot = Resolve-Root -InputRoot $Root
$interval = [Math]::Max(10, [int]$IntervalSec)
$duration = [Math]::Max(1, [int]$DurationHours)
$minAliveCount = [Math]::Max(1, [int]$MinAlive)
$strikeLimit = [Math]::Max(1, [int]$UnhealthyStrike)
$smokeEvery = [Math]::Max(5, [int]$SmokeEveryMin)
$sysCtlTimeout = [Math]::Max(30, [int]$SystemControlTimeoutSec)
$smokeTimeout = [Math]::Max(30, [int]$SmokeTimeoutSec)
$safetyTtl = [Math]::Max(60, [int]$SafetyLogTtlSec)
$scudTtl = [Math]::Max(60, [int]$ScudLogTtlSec)
$infoTtl = [Math]::Max(60, [int]$InfoLogTtlSec)
$repairTtl = [Math]::Max(60, [int]$RepairLogTtlSec)
$learnerTtl = [Math]::Max(300, [int]$LearnerLogTtlSec)

$evidenceDir = Join-Path $runtimeRoot "EVIDENCE\night_watch"
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$jsonlPath = Join-Path $evidenceDir ("night_watch_" + $runId + ".jsonl")
$statusPath = Join-Path $evidenceDir ("night_watch_" + $runId + "_status.json")
$lastSmokePath = Join-Path $evidenceDir ("night_watch_" + $runId + "_last_smoke.json")

$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
$smokeScript = Join-Path $runtimeRoot "TOOLS\online_smoke_mt5.py"
$pwshExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $pwshExe)) {
    $pwshExe = "powershell"
}

$deadline = (Get-Date).AddHours($duration)
$nextSmoke = Get-Date
$unhealthyStreak = 0
$lastMt5AlertSig = ""

Write-Output ("NIGHT_WATCH start run_id={0} root={1} duration_h={2} interval_s={3}" -f $runId, $runtimeRoot, $duration, $interval)
Write-Output ("NIGHT_WATCH evidence={0}" -f $jsonlPath)

Write-EventJsonl -Path $jsonlPath -Payload @{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "start"
    run_id = $runId
    root = $runtimeRoot
    duration_h = $duration
    interval_s = $interval
    min_alive = $minAliveCount
    strike_limit = $strikeLimit
    smoke_every_min = $smokeEvery
    system_control_timeout_sec = $sysCtlTimeout
    smoke_timeout_sec = $smokeTimeout
    ttl_safety_sec = $safetyTtl
    ttl_scud_sec = $scudTtl
    ttl_infobot_sec = $infoTtl
    ttl_repair_sec = $repairTtl
    ttl_learner_sec = $learnerTtl
    dry_run = [bool]$DryRun
}

while ((Get-Date) -lt $deadline) {
    try {
        $components = @(
            (Test-ComponentAlive -RootPath $runtimeRoot -Name "SafetyBot" -LockRel "RUN\safetybot.lock" -LogRel "LOGS\safetybot.log" -LogTtlSec $safetyTtl),
            (Test-ComponentAlive -RootPath $runtimeRoot -Name "SCUD" -LockRel "RUN\scudfab02.lock" -LogRel "LOGS\scudfab02.log" -LogTtlSec $scudTtl),
            (Test-ComponentAlive -RootPath $runtimeRoot -Name "InfoBot" -LockRel "RUN\infobot.lock" -LogRel "LOGS\infobot\infobot.log" -LogTtlSec $infoTtl),
            (Test-ComponentAlive -RootPath $runtimeRoot -Name "RepairAgent" -LockRel "RUN\repair_agent.lock" -LogRel "LOGS\repair_agent\repair_agent.log" -LogTtlSec $repairTtl),
            (Test-ComponentAlive -RootPath $runtimeRoot -Name "Learner" -LockRel "" -LogRel "LOGS\learner_offline.log" -LogTtlSec $learnerTtl)
        )

        $aliveCount = @($components | Where-Object { $_.alive }).Count
        $healthy = ($aliveCount -ge $minAliveCount)
        if ($healthy) { $unhealthyStreak = 0 } else { $unhealthyStreak += 1 }

        $mt5Log = Get-LatestMt5Log -RootPath "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856"
        $mt5Alert = $null
        if ($null -ne $mt5Log) {
            try {
                $hits = Select-String -Path $mt5Log.FullName -Pattern "FAIL-SAFE ACTIVATED|ZMQ_INIT_FAIL" -ErrorAction Stop | Select-Object -Last 1
                if ($null -ne $hits) {
                    $sig = [string]$hits.Line
                    if ($sig -ne $lastMt5AlertSig) {
                        $lastMt5AlertSig = $sig
                        $mt5Alert = $sig
                    }
                }
            } catch {
                $mt5Alert = $null
            }
        }

        $tick = @{
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            event = "tick"
            run_id = $runId
            alive_count = [int]$aliveCount
            min_alive = [int]$minAliveCount
            healthy = [bool]$healthy
            unhealthy_streak = [int]$unhealthyStreak
            components = $components
        }
        if ($mt5Alert) { $tick.mt5_alert = $mt5Alert }
        Write-EventJsonl -Path $jsonlPath -Payload $tick

        $status = @{
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            run_id = $runId
            healthy = [bool]$healthy
            alive_count = [int]$aliveCount
            unhealthy_streak = [int]$unhealthyStreak
            deadline_utc = $deadline.ToUniversalTime().ToString("o")
            jsonl = $jsonlPath
        }
        $status | ConvertTo-Json -Depth 8 | Set-Content -Path $statusPath -Encoding UTF8

        if ($unhealthyStreak -ge $strikeLimit) {
            $evt = @{
                ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                event = "restart_trigger"
                run_id = $runId
                reason = "unhealthy_streak"
                unhealthy_streak = [int]$unhealthyStreak
                dry_run = [bool]$DryRun
            }
            Write-EventJsonl -Path $jsonlPath -Payload $evt
            if (-not $DryRun) {
                $stopRes = Invoke-SystemControlAction -PwshExe $pwshExe -SystemControlPath $systemControl -RuntimeRoot $runtimeRoot -ActionName "stop" -TimeoutSec $sysCtlTimeout -EvidenceDir $evidenceDir
                Write-EventJsonl -Path $jsonlPath -Payload @{
                    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                    event = "restart_step"
                    run_id = $runId
                    action = "stop"
                    ok = [bool]$stopRes.ok
                    timed_out = [bool]$stopRes.timed_out
                    exit_code = $stopRes.exit_code
                    error = $stopRes.error
                    stdout = $stopRes.stdout
                    stderr = $stopRes.stderr
                }

                Start-Sleep -Seconds 3

                $startRes = Invoke-SystemControlAction -PwshExe $pwshExe -SystemControlPath $systemControl -RuntimeRoot $runtimeRoot -ActionName "start" -TimeoutSec $sysCtlTimeout -EvidenceDir $evidenceDir
                Write-EventJsonl -Path $jsonlPath -Payload @{
                    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                    event = "restart_step"
                    run_id = $runId
                    action = "start"
                    ok = [bool]$startRes.ok
                    timed_out = [bool]$startRes.timed_out
                    exit_code = $startRes.exit_code
                    error = $startRes.error
                    stdout = $startRes.stdout
                    stderr = $startRes.stderr
                }

                $statusRes = Invoke-SystemControlAction -PwshExe $pwshExe -SystemControlPath $systemControl -RuntimeRoot $runtimeRoot -ActionName "status" -TimeoutSec $sysCtlTimeout -EvidenceDir $evidenceDir
                Write-EventJsonl -Path $jsonlPath -Payload @{
                    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                    event = "restart_step"
                    run_id = $runId
                    action = "status"
                    ok = [bool]$statusRes.ok
                    timed_out = [bool]$statusRes.timed_out
                    exit_code = $statusRes.exit_code
                    error = $statusRes.error
                    stdout = $statusRes.stdout
                    stderr = $statusRes.stderr
                }
            }
            $unhealthyStreak = 0
        }

        if ((Get-Date) -ge $nextSmoke) {
            $smokeOut = Join-Path $evidenceDir ("smoke_" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + ".json")
            $smokeRc = -1
            $smokeErr = $null
            $smokeExecOut = $null
            $smokeExecErr = $null
            $smokeTimedOut = $false
            if (-not $DryRun) {
                $smokeRes = Invoke-SmokeRun -RuntimeRoot $runtimeRoot -SmokeScriptPath $smokeScript -SmokeOutPath $smokeOut -Mt5TerminalPath $Mt5Path -TimeoutSec $smokeTimeout -EvidenceDir $evidenceDir
                $smokeTimedOut = [bool]$smokeRes.timed_out
                $smokeRc = if ($null -eq $smokeRes.exit_code) { -1 } else { [int]$smokeRes.exit_code }
                $smokeErr = $smokeRes.error
                $smokeExecOut = $smokeRes.stdout
                $smokeExecErr = $smokeRes.stderr
            }
            $smokeEvt = @{
                ts_utc = (Get-Date).ToUniversalTime().ToString("o")
                event = "smoke"
                run_id = $runId
                rc = [int]$smokeRc
                out = $smokeOut
                err = $smokeErr
                timed_out = [bool]$smokeTimedOut
                exec_stdout = $smokeExecOut
                exec_stderr = $smokeExecErr
                dry_run = [bool]$DryRun
            }
            Write-EventJsonl -Path $jsonlPath -Payload $smokeEvt
            $smokeEvt | ConvertTo-Json -Depth 8 | Set-Content -Path $lastSmokePath -Encoding UTF8
            $nextSmoke = (Get-Date).AddMinutes($smokeEvery)
        }
    } catch {
        Write-EventJsonl -Path $jsonlPath -Payload @{
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            event = "loop_error"
            run_id = $runId
            error = $_.Exception.Message
        }
    }

    Start-Sleep -Seconds $interval
}

Write-EventJsonl -Path $jsonlPath -Payload @{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "done"
    run_id = $runId
}

Write-Output ("NIGHT_WATCH done run_id={0} jsonl={1}" -f $runId, $jsonlPath)
