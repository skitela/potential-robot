param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [int]$LookbackMinutes = 30
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

function Parse-LineTimestamp {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return $null }
    if ($Line -match "^(?<ts>\d{4}-\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2},\d{3})") {
        try {
            return [datetime]::ParseExact($Matches["ts"], "yyyy-MM-dd HH:mm:ss,fff", [System.Globalization.CultureInfo]::InvariantCulture)
        } catch {
            return $null
        }
    }
    return $null
}

$runtimeRoot = Resolve-RootPath -Path $Root
$safetyLog = Join-Path $runtimeRoot "LOGS\safetybot.log"
$sessionStatusPath = Join-Path $runtimeRoot "RUN\mt5_session_guard_status.json"
$outDir = Join-Path $runtimeRoot "EVIDENCE\runtime_diagnostics"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$now = Get-Date
$cutoff = $now.AddMinutes(-1 * [Math]::Max(1, [int]$LookbackMinutes))
$lines = @()
if (Test-Path $safetyLog) {
    $lines = @(Get-Content -Path $safetyLog -Tail 12000)
}

$noActivePeer = 0
$sendTimeout = 0
$hbSkip = 0
$firstTs = $null
$lastTs = $null
$sample = New-Object System.Collections.ArrayList

foreach ($line in $lines) {
    $msg = [string]$line
    if ([string]::IsNullOrWhiteSpace($msg)) { continue }
    $ts = Parse-LineTimestamp -Line $msg
    if ($null -eq $ts) { continue }
    if ($ts -lt $cutoff) { continue }

    if ($msg -match "NO_ACTIVE_PEER") {
        $noActivePeer++
        if ($null -eq $firstTs) { $firstTs = $ts }
        $lastTs = $ts
        if ($sample.Count -lt 6) { [void]$sample.Add($msg) }
    }
    if ($msg -match "COMMAND_SEND_TIMEOUT|bridge_timeout_reason=SEND_TIMEOUT") { $sendTimeout++ }
    if ($msg -match "HEARTBEAT_SKIP.*timeout_nonfatal") { $hbSkip++ }
}

$sessionStatus = $null
if (Test-Path $sessionStatusPath) {
    try {
        $sessionStatus = Get-Content -Path $sessionStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        $sessionStatus = $null
    }
}

$report = [ordered]@{
    schema = "oanda_mt5.no_active_peer_diag.v1"
    ts_utc = $now.ToUniversalTime().ToString("o")
    lookback_minutes = [int]$LookbackMinutes
    cutoff_utc = $cutoff.ToUniversalTime().ToString("o")
    safety_log = $safetyLog
    counters = [ordered]@{
        no_active_peer = [int]$noActivePeer
        send_timeout = [int]$sendTimeout
        heartbeat_skip_timeout = [int]$hbSkip
    }
    first_event_local = $(if ($null -eq $firstTs) { "" } else { $firstTs.ToString("o") })
    last_event_local = $(if ($null -eq $lastTs) { "" } else { $lastTs.ToString("o") })
    sample_lines = @($sample)
    session_guard = $sessionStatus
}

$stamp = $now.ToString("yyyyMMdd_HHmmss")
$jsonPath = Join-Path $outDir ("no_active_peer_diag_" + $stamp + ".json")
$txtPath = Join-Path $outDir ("no_active_peer_diag_" + $stamp + ".txt")

$report | ConvertTo-Json -Depth 10 | Set-Content -Path $jsonPath -Encoding UTF8

$txt = @()
$txt += "NO_ACTIVE_PEER_DIAG"
$txt += ("ts_utc={0}" -f $report.ts_utc)
$txt += ("lookback_minutes={0}" -f [int]$LookbackMinutes)
$txt += ("no_active_peer={0}" -f [int]$noActivePeer)
$txt += ("send_timeout={0}" -f [int]$sendTimeout)
$txt += ("heartbeat_skip_timeout={0}" -f [int]$hbSkip)
$txt += ("first_event_local={0}" -f [string]$report.first_event_local)
$txt += ("last_event_local={0}" -f [string]$report.last_event_local)
$txt += ("json={0}" -f $jsonPath)
$txt | Set-Content -Path $txtPath -Encoding UTF8

Write-Output ("NO_ACTIVE_PEER_DIAG_OK json={0} txt={1}" -f $jsonPath, $txtPath)
exit 0
