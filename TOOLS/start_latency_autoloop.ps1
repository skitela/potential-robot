param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$MaxAttempts = 15,
    [int]$SoakSec = 1200,
    [double]$TargetP95Ms = 700,
    [double]$TargetP99Ms = 850,
    [int]$TradeMinSamples = 10,
    [switch]$RetentionBeforeLoop,
    [int]$RetentionEvery = 0
)

$ErrorActionPreference = "Stop"
$rootResolved = (Resolve-Path $Root).Path
Set-Location $rootResolved

$runDir = Join-Path $rootResolved "RUN"
New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$logPath = Join-Path $runDir ("latency_autoloop_" + $stamp + ".log")
$errPath = Join-Path $runDir ("latency_autoloop_" + $stamp + ".err.log")
$pidPath = Join-Path $runDir "latency_autoloop_pid.txt"

$args = @(
    "TOOLS/latency_autoloop.py",
    "--root", $rootResolved,
    "--max-attempts", [string]$MaxAttempts,
    "--soak-sec", [string]$SoakSec,
    "--target-p95-ms", [string]$TargetP95Ms,
    "--target-p99-ms", [string]$TargetP99Ms,
    "--trade-min-samples", [string]$TradeMinSamples
)
if($RetentionBeforeLoop){ $args += "--retention-before-loop" }
if($RetentionEvery -gt 0){ $args += @("--retention-every", [string]$RetentionEvery) }

$proc = Start-Process -FilePath "python" -ArgumentList $args -WorkingDirectory $rootResolved -RedirectStandardOutput $logPath -RedirectStandardError $errPath -PassThru -WindowStyle Hidden

[string]$proc.Id | Set-Content -Path $pidPath -Encoding UTF8
Write-Output ("LATENCY_AUTOLOOP_STARTED pid={0} log={1} err={2} pid_file={3}" -f $proc.Id, $logPath, $errPath, $pidPath)
