param(
    [int]$DurationMin = 20,
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$durationSec = [Math]::Max(1, [int]$DurationMin) * 60
$runner = Join-Path $Root "TOOLS\run_bridge_soak_audit.ps1"
if (-not (Test-Path $runner)) {
    throw "Missing bridge soak runner: $runner"
}

Write-Host "RUN_RUNTIME_LATENCY_AUDIT start duration_min=$DurationMin profile=$Profile root=$Root"
& powershell -ExecutionPolicy Bypass -File $runner -Root $Root -DurationSec $durationSec -Profile $Profile
$rc = $LASTEXITCODE
Write-Host "RUN_RUNTIME_LATENCY_AUDIT done rc=$rc"
exit $rc

