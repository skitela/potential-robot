param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$IntervalSec = 60,
    [int]$TimeoutSec = 3600,
    [switch]$ShowReport
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

$runtimeRoot = Resolve-Root -InputRoot $Root
$runDir = Join-Path $runtimeRoot "RUN"
$progressPath = Join-Path $runDir "start_online_smart_progress.json"
$reportPath = Join-Path $runDir "start_online_smart_report.json"

$interval = [Math]::Max(1, [int]$IntervalSec)
$timeout = [Math]::Max(5, [int]$TimeoutSec)
$deadline = (Get-Date).AddSeconds($timeout)

$lastSig = ""
$lastPhase = "n/a"
$lastTs = "n/a"

Write-Output ("SMART_WATCH start root={0} interval={1}s timeout={2}s" -f $runtimeRoot, $interval, $timeout)

while ((Get-Date) -lt $deadline) {
    if (Test-Path $progressPath) {
        try {
            $raw = Get-Content -Raw -Path $progressPath -ErrorAction Stop
            $p = $raw | ConvertFrom-Json -ErrorAction Stop
            $sig = "{0}|{1}|{2}|{3}|{4}" -f $p.ts_utc, $p.phase, $p.message, $p.final_status, $p.elapsed_ms
            $phase = [string]$p.phase
            $msg = [string]$p.message
            $elapsedMs = [string]$p.elapsed_ms
            $lastPhase = $phase
            $lastTs = [string]$p.ts_utc
            if ($sig -ne $lastSig) {
                Write-Output ("SMART_WATCH update ts={0} phase={1} elapsed_ms={2} msg={3}" -f $p.ts_utc, $phase, $elapsedMs, $msg)
                $lastSig = $sig
            } else {
                Write-Output ("SMART_WATCH heartbeat phase={0} ts={1}" -f $lastPhase, $lastTs)
            }

            if ($phase -eq "done") {
                if ($ShowReport -and (Test-Path $reportPath)) {
                    Write-Output "---SMART_REPORT---"
                    Get-Content -Raw -Path $reportPath | Write-Output
                }
                Write-Output ("SMART_WATCH done final={0}" -f [string]$p.final_status)
                exit 0
            }
        } catch {
            Write-Output ("SMART_WATCH parse_error file={0} err={1}" -f $progressPath, $_.Exception.Message)
        }
    } else {
        Write-Output ("SMART_WATCH waiting file={0}" -f $progressPath)
    }
    Start-Sleep -Seconds $interval
}

Write-Output ("SMART_WATCH timeout phase={0} last_ts={1}" -f $lastPhase, $lastTs)
exit 2

