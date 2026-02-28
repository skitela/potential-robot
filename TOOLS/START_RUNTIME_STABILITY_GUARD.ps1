param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$IntervalSec = 300,
    [int]$TimeoutSec = 180,
    [switch]$RunBenchmarkOutsideActive
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

$runtimeRoot = Resolve-RootPath -Path $Root
$scriptPath = Join-Path $runtimeRoot "TOOLS\runtime_stability_cycle.py"
if (-not (Test-Path $scriptPath)) {
    Write-Error "Missing script: $scriptPath"
    exit 2
}

$logDir = Join-Path $runtimeRoot "LOGS\bootstrap"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
$outLog = Join-Path $logDir ("runtime_stability_guard_" + $stamp + "_out.log")
$errLog = Join-Path $logDir ("runtime_stability_guard_" + $stamp + "_err.log")

$args = @(
    "-3.12",
    "-B",
    $scriptPath,
    "--root", $runtimeRoot,
    "--loop",
    "--interval-sec", ([string]([Math]::Max(30, [int]$IntervalSec))),
    "--timeout-sec", ([string]([Math]::Max(30, [int]$TimeoutSec)))
)
if ($RunBenchmarkOutsideActive) {
    $args += "--run-benchmark-outside-active"
}

$proc = Start-Process -FilePath "py" -ArgumentList $args -WorkingDirectory $runtimeRoot -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
Write-Output ("RUNTIME_STABILITY_GUARD_STARTED pid={0} out={1} err={2}" -f [int]$proc.Id, $outLog, $errLog)
exit 0
