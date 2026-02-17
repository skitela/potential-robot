param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$StartTimeoutSec = 45,
    [int]$ObserveSec = 20,
    [int]$PollSec = 2,
    [switch]$StopFirst
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

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $tmp = "$Path.tmp"
    $data = $Object | ConvertTo-Json -Depth 10
    try {
        $data | Set-Content -Encoding UTF8 -Path $tmp
        Move-Item -Force $tmp $Path
    } catch {
        $data | Set-Content -Encoding UTF8 -Path $Path
        try { Remove-Item -Force $tmp -ErrorAction SilentlyContinue } catch {}
    }
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

$runtimeRoot = Resolve-Root -InputRoot $Root
$systemControl = Join-Path $runtimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
if (-not (Test-Path $systemControl)) {
    Write-Error "Brak skryptu: $systemControl"
    exit 2
}

$bootDir = Join-Path $runtimeRoot "LOGS\bootstrap"
New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
$runDir = Join-Path $runtimeRoot "RUN"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

if ($StopFirst) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $systemControl -Action stop -Root $runtimeRoot | Out-Null
}

$out = Join-Path $bootDir "system_control_online_out.log"
$err = Join-Path $bootDir "system_control_online_err.log"
Remove-Item -Force $out,$err -ErrorAction SilentlyContinue

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath powershell -ArgumentList @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $systemControl,
    "-Action", "start",
    "-Root", $runtimeRoot
) -WorkingDirectory $runtimeRoot -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden

$deadline = (Get-Date).AddSeconds([Math]::Max(5, $StartTimeoutSec))
$timedOut = $false
while ((Get-Date) -lt $deadline) {
    if (-not (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue)) { break }
    Start-Sleep -Milliseconds 500
}
if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) {
    $timedOut = $true
    Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
$sw.Stop()

$exitCode = $null
try { $exitCode = [int]$proc.ExitCode } catch { $exitCode = $null }

$watch = @(
    @{ name = "SafetyBot"; lock = "RUN\safetybot.lock"; log = "LOGS\safetybot.log"; ttl = 240 },
    @{ name = "SCUD"; lock = "RUN\scudfab02.lock"; log = "LOGS\scudfab02.log"; ttl = 240 },
    @{ name = "InfoBot"; lock = "RUN\infobot.lock"; log = "LOGS\infobot\infobot.log"; ttl = 300 },
    @{ name = "RepairAgent"; lock = "RUN\repair_agent.lock"; log = "LOGS\repair_agent\repair_agent.log"; ttl = 300 },
    @{ name = "Learner"; lock = ""; log = "LOGS\learner_offline.log"; ttl = 900 }
)

$timeline = @()
$obsUntil = (Get-Date).AddSeconds([Math]::Max(2, $ObserveSec))
while ((Get-Date) -lt $obsUntil) {
    $snap = [ordered]@{
        ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        components = @()
    }
    foreach ($c in $watch) {
        $lockPath = if ([string]::IsNullOrWhiteSpace([string]$c.lock)) { "" } else { Join-Path $runtimeRoot ([string]$c.lock) }
        $logPath = Join-Path $runtimeRoot ([string]$c.log)
        $lockExists = if ($lockPath) { Test-Path $lockPath } else { $false }
        $age = Get-FileAgeSec -Path $logPath
        $fresh = $false
        if ($null -ne $age) { $fresh = ([double]$age -le [double]$c.ttl) }
        $hb = if ($lockPath) { ([bool]$lockExists -and [bool]$fresh) } else { [bool]$fresh }
        $snap.components += [ordered]@{
            name = [string]$c.name
            lock_exists = [bool]$lockExists
            log_path = $logPath
            log_age_sec = $age
            log_ttl_sec = [int]$c.ttl
            running_heartbeat = [bool]$hb
        }
    }
    $timeline += $snap
    Start-Sleep -Seconds ([Math]::Max(1, $PollSec))
}

$last = $null
if ($timeline.Count -gt 0) {
    $last = $timeline[$timeline.Count - 1]
}
$aliveCount = 0
if ($null -ne $last) {
    $aliveCount = @($last.components | Where-Object { $_.running_heartbeat }).Count
}

$final = "ONLINE_HEARTBEAT_WEAK"
if ($timedOut) {
    $final = "START_TIMEOUT"
} elseif ($aliveCount -ge 2) {
    $final = "ONLINE_HEARTBEAT_OK"
}

$report = [ordered]@{
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    root = $runtimeRoot
    command = ".\TOOLS\SYSTEM_CONTROL.ps1 -Action start -Root $runtimeRoot"
    elapsed_ms = [int]$sw.ElapsedMilliseconds
    timed_out = [bool]$timedOut
    exit_code = $exitCode
    final_status = $final
    alive_heartbeat_count = [int]$aliveCount
    stdout_log = $out
    stderr_log = $err
    timeline = $timeline
}

$reportPath = Join-Path $runtimeRoot "RUN\start_online_smart_report.json"
Write-JsonAtomic -Path $reportPath -Object $report

Write-Output ("SMART_START status={0} elapsed_ms={1} timed_out={2} exit_code={3} alive={4}" -f $final, [int]$sw.ElapsedMilliseconds, [int]([bool]$timedOut), $exitCode, [int]$aliveCount)
Write-Output ("SMART_START report={0}" -f $reportPath)
Write-Output ("SMART_START out={0}" -f $out)
Write-Output ("SMART_START err={0}" -f $err)

if ($final -eq "ONLINE_HEARTBEAT_OK") { exit 0 }
if ($final -eq "START_TIMEOUT") { exit 2 }
exit 1
