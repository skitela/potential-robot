param(
    [int]$DurationMin = 20,
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [switch]$RequireIdle,
    [int]$IdleThresholdSec = 900,
    [switch]$RequireOutsideActive,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-WindowPhase {
    param([string]$RuntimeRoot)
    $logPath = Join-Path $RuntimeRoot "LOGS\safetybot.log"
    if (-not (Test-Path -LiteralPath $logPath)) {
        return "UNKNOWN"
    }
    $lines = Get-Content -LiteralPath $logPath -Tail 3000 -ErrorAction SilentlyContinue
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        $ln = [string]$lines[$i]
        if ($ln -match "WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)") {
            return [string]$Matches[1]
        }
    }
    return "UNKNOWN"
}

function Get-IdleSecondsBestEffort {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class OandaIdleProbe2 {
    [StructLayout(LayoutKind.Sequential)]
    public struct LASTINPUTINFO {
        public uint cbSize;
        public uint dwTime;
    }
    [DllImport("user32.dll")]
    public static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
    public static uint GetIdleMilliseconds() {
        LASTINPUTINFO lii = new LASTINPUTINFO();
        lii.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
        if (!GetLastInputInfo(ref lii)) { return 0; }
        return (uint)Environment.TickCount - lii.dwTime;
    }
}
"@ -ErrorAction SilentlyContinue | Out-Null
        $idleMs = [uint32][OandaIdleProbe2]::GetIdleMilliseconds()
        return [int][Math]::Floor([double]$idleMs / 1000.0)
    } catch {
        return -1
    }
}

$idleSec = Get-IdleSecondsBestEffort
$phase = Get-WindowPhase -RuntimeRoot $Root
$needIdle = $RequireIdle.IsPresent -and (-not $Force.IsPresent)
$needOutside = $RequireOutsideActive.IsPresent -and (-not $Force.IsPresent)
if ($needIdle -and $idleSec -ge 0 -and $idleSec -lt [Math]::Max(10, [int]$IdleThresholdSec)) {
    Write-Host "RUN_RUNTIME_LATENCY_AUDIT skip reason=OPERATOR_ACTIVE idle_sec=$idleSec threshold_sec=$IdleThresholdSec"
    exit 0
}
if ($needOutside -and ([string]$phase).ToUpperInvariant() -eq "ACTIVE") {
    Write-Host "RUN_RUNTIME_LATENCY_AUDIT skip reason=ACTIVE_WINDOW phase=$phase"
    exit 0
}

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
