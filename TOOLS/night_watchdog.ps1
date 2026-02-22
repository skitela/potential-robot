param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$DurationHours = 8,
    [int]$IntervalSec = 60,
    [int]$MinAlive = 3,
    [int]$UnhealthyStrike = 3,
    [int]$SmokeEveryMin = 30,
    [string]$Mt5Path = "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
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

$evidenceDir = Join-Path $runtimeRoot "EVIDENCE\night_watch"
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null

$runId = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$jsonlPath = Join-Path $evidenceDir ("night_watch_" + $runId + ".jsonl")
$statusPath = Join-Path $evidenceDir ("night_watch_" + $runId + "_status.json")
$lastSmokePath = Join-Path $evidenceDir ("night_watch_" + $runId + "_last_smoke.json")

$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
$smokeScript = Join-Path $runtimeRoot "TOOLS\online_smoke_mt5.py"

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
    dry_run = [bool]$DryRun
}

while ((Get-Date) -lt $deadline) {
    $components = @(
        (Test-ComponentAlive -RootPath $runtimeRoot -Name "SafetyBot" -LockRel "RUN\safetybot.lock" -LogRel "LOGS\safetybot.log" -LogTtlSec 240),
        (Test-ComponentAlive -RootPath $runtimeRoot -Name "SCUD" -LockRel "RUN\scudfab02.lock" -LogRel "LOGS\scudfab02.log" -LogTtlSec 240),
        (Test-ComponentAlive -RootPath $runtimeRoot -Name "InfoBot" -LockRel "RUN\infobot.lock" -LogRel "LOGS\infobot\infobot.log" -LogTtlSec 300),
        (Test-ComponentAlive -RootPath $runtimeRoot -Name "RepairAgent" -LockRel "RUN\repair_agent.lock" -LogRel "LOGS\repair_agent\repair_agent.log" -LogTtlSec 300),
        (Test-ComponentAlive -RootPath $runtimeRoot -Name "Learner" -LockRel "" -LogRel "LOGS\learner_offline.log" -LogTtlSec 900)
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
            & powershell -NoProfile -ExecutionPolicy Bypass -File $systemControl -Action stop -Root $runtimeRoot -Profile full | Out-Null
            Start-Sleep -Seconds 5
            & powershell -NoProfile -ExecutionPolicy Bypass -File $systemControl -Action start -Root $runtimeRoot -Profile full | Out-Null
        }
        $unhealthyStreak = 0
    }

    if ((Get-Date) -ge $nextSmoke) {
        $smokeOut = Join-Path $evidenceDir ("smoke_" + (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ") + ".json")
        $smokeRc = -1
        $smokeErr = $null
        if (-not $DryRun) {
            try {
                & py -3.12 -B $smokeScript --mt5-path $Mt5Path --out $smokeOut
                $smokeRc = [int]$LASTEXITCODE
            } catch {
                $smokeRc = -1
                $smokeErr = $_.Exception.Message
            }
        }
        $smokeEvt = @{
            ts_utc = (Get-Date).ToUniversalTime().ToString("o")
            event = "smoke"
            run_id = $runId
            rc = [int]$smokeRc
            out = $smokeOut
            err = $smokeErr
            dry_run = [bool]$DryRun
        }
        Write-EventJsonl -Path $jsonlPath -Payload $smokeEvt
        $smokeEvt | ConvertTo-Json -Depth 8 | Set-Content -Path $lastSmokePath -Encoding UTF8
        $nextSmoke = (Get-Date).AddMinutes($smokeEvery)
    }

    Start-Sleep -Seconds $interval
}

Write-EventJsonl -Path $jsonlPath -Payload @{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "done"
    run_id = $runId
}

Write-Output ("NIGHT_WATCH done run_id={0} jsonl={1}" -f $runId, $jsonlPath)
