param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "full",
    [switch]$StopFirst,
    [int]$StartTimeoutSec = 45,
    [int]$ObserveSec = 20,
    [int]$PollSec = 2,
    [int]$ProgressEverySec = 60,
    [int]$WatchIntervalSec = 60,
    [int]$WatchTimeoutSec = 0,
    [switch]$ShowReport,
    [switch]$StartStabilityGuard,
    [int]$StabilityGuardIntervalSec = 300
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
$startScript = Join-Path $runtimeRoot "TOOLS\START_ONLINE_SMART.ps1"
$watchScript = Join-Path $runtimeRoot "TOOLS\START_ONLINE_SMART_WATCH.ps1"
$stabilityGuardScript = Join-Path $runtimeRoot "TOOLS\START_RUNTIME_STABILITY_GUARD.ps1"

if (-not (Test-Path $startScript)) {
    Write-Error "Brak skryptu startowego: $startScript"
    exit 2
}
if (-not (Test-Path $watchScript)) {
    Write-Error "Brak watchera: $watchScript"
    exit 2
}

$bootDir = Join-Path $runtimeRoot "LOGS\bootstrap"
New-Item -ItemType Directory -Force -Path $bootDir | Out-Null
$out = Join-Path $bootDir "start_onclick_out.log"
$err = Join-Path $bootDir "start_onclick_err.log"
Remove-Item -Force $out,$err -ErrorAction SilentlyContinue

$startArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $startScript,
    "-Root", $runtimeRoot,
    "-Profile", $Profile,
    "-StartTimeoutSec", ([string][Math]::Max(5, [int]$StartTimeoutSec)),
    "-ObserveSec", ([string][Math]::Max(2, [int]$ObserveSec)),
    "-PollSec", ([string][Math]::Max(1, [int]$PollSec)),
    "-ProgressEverySec", ([string][Math]::Max(1, [int]$ProgressEverySec))
)
if ($StopFirst) { $startArgs += "-StopFirst" }

Write-Output ("ONECLICK start root={0} profile={1}" -f $runtimeRoot, $Profile)
$p = Start-Process -FilePath powershell -ArgumentList $startArgs -WorkingDirectory $runtimeRoot -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
Write-Output ("ONECLICK spawned start pid={0}" -f [int]$p.Id)

$watchTimeout = [int]$WatchTimeoutSec
if ($watchTimeout -le 0) {
    $watchTimeout = [Math]::Max(30, ([int]$StartTimeoutSec + [int]$ObserveSec + 30))
}
$watchArgs = @(
    "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $watchScript,
    "-Root", $runtimeRoot,
    "-IntervalSec", ([string][Math]::Max(1, [int]$WatchIntervalSec)),
    "-TimeoutSec", ([string][Math]::Max(5, [int]$watchTimeout))
)
if ($ShowReport) { $watchArgs += "-ShowReport" }

& powershell @watchArgs
$watchRc = $LASTEXITCODE

$alive = [bool](Get-Process -Id $p.Id -ErrorAction SilentlyContinue)
if ($alive) {
    Write-Warning ("ONECLICK: start process still alive after watcher, stopping pid={0}" -f [int]$p.Id)
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
}
try { $startRc = [int]$p.ExitCode } catch { $startRc = -1 }

Write-Output ("ONECLICK done watch_rc={0} start_rc={1}" -f [int]$watchRc, [int]$startRc)
if (Test-Path $out) { Write-Output ("ONECLICK out={0}" -f $out) }
if (Test-Path $err) { Write-Output ("ONECLICK err={0}" -f $err) }

if ($watchRc -ne 0) { exit [int]$watchRc }
if ($startRc -ne 0) { exit [int]$startRc }

if ($StartStabilityGuard) {
    if (Test-Path $stabilityGuardScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $stabilityGuardScript -Root $runtimeRoot -IntervalSec ([Math]::Max(30, [int]$StabilityGuardIntervalSec)) | Write-Output
    } else {
        Write-Warning ("ONECLICK: requested stability guard but script missing: {0}" -f $stabilityGuardScript)
    }
}
exit 0
