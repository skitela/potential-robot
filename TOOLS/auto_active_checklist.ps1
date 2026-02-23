param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5TerminalRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [int]$PollSec = 5,
    [int]$TimeoutHours = 8
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

function Read-AppendedLines {
    param(
        [string]$Path,
        [hashtable]$Offsets,
        [int64]$MaxReadBytes = 1024KB
    )
    if (-not (Test-Path $Path)) {
        return @()
    }
    $item = Get-Item -Path $Path -ErrorAction Stop
    $len = [int64]$item.Length

    if (-not $Offsets.ContainsKey($Path)) {
        $Offsets[$Path] = $len
        return @()
    }
    $start = [int64]$Offsets[$Path]
    if ($len -lt $start) {
        $start = 0
    }
    if (($len - $start) -le 0) {
        $Offsets[$Path] = $len
        return @()
    }
    if (($len - $start) -gt $MaxReadBytes) {
        $start = [Math]::Max(0, $len - $MaxReadBytes)
    }

    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        try {
            $text = $sr.ReadToEnd()
        } finally {
            $sr.Dispose()
        }
    } finally {
        $fs.Dispose()
    }

    $Offsets[$Path] = $len
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }
    return [System.Text.RegularExpressions.Regex]::Split($text, "\r?\n")
}

function Get-LatestLine {
    param(
        [string]$Path,
        [string]$Pattern,
        [int]$Tail = 1200
    )
    if (-not (Test-Path $Path)) {
        return $null
    }
    $m = Get-Content -Path $Path -Tail $Tail | Select-String -Pattern $Pattern | Select-Object -Last 1
    if ($null -eq $m) {
        return $null
    }
    return [string]$m.Line
}

function Get-RecentSkipReasons {
    param(
        [string]$SafetyLogPath,
        [int]$Tail = 1500
    )
    $reasons = @{}
    if (-not (Test-Path $SafetyLogPath)) {
        return $reasons
    }
    $rx = [regex]'ENTRY_SKIP(?:_PRE)? .*?\breason=([A-Z0-9_]+)\b'
    $lines = Get-Content -Path $SafetyLogPath -Tail $Tail
    foreach ($line in $lines) {
        $m = $rx.Match([string]$line)
        if (-not $m.Success) {
            continue
        }
        $k = [string]$m.Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($k)) {
            continue
        }
        if (-not $reasons.ContainsKey($k)) {
            $reasons[$k] = 0
        }
        $reasons[$k] = [int]$reasons[$k] + 1
    }
    return $reasons
}

function Get-LatestMt5LogFile {
    param([string]$TerminalRoot)
    $dir = Join-Path $TerminalRoot "MQL5\Logs"
    if (-not (Test-Path $dir)) {
        return $null
    }
    return (Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

function Invoke-ActiveChecklist {
    param(
        [string]$RuntimeRoot,
        [string]$TerminalRoot,
        [string]$WindowId,
        [string]$TriggerLine
    )
    $now = Get-Date
    $utcNow = $now.ToUniversalTime()
    $plNow = [System.TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($now, "Central European Standard Time")

    $safetyLog = Join-Path $RuntimeRoot "LOGS\safetybot.log"
    $scudLog = Join-Path $RuntimeRoot "LOGS\scudfab02.log"
    $metaDir = Join-Path $RuntimeRoot "META"
    $outputDir = Join-Path $RuntimeRoot "EVIDENCE\ACTIVE_CHECKS"
    New-Item -Path $outputDir -ItemType Directory -Force | Out-Null

    $statusOutput = ""
    try {
        $statusOutput = (& powershell -ExecutionPolicy Bypass -File (Join-Path $RuntimeRoot "TOOLS\SYSTEM_CONTROL.ps1") -Action status -Profile full 2>&1 | Out-String).Trim()
    } catch {
        $statusOutput = "SYSTEM_CONTROL_STATUS_CALL_FAILED: $($_.Exception.Message)"
    }
    $statusPass = ($statusOutput -match "status=PASS")

    $pyProcs = Get-CimInstance Win32_Process | Where-Object { $_.Name -match "python" }
    $procChecks = [ordered]@{
        safetybot = [bool]($pyProcs | Where-Object { $_.CommandLine -match "safetybot\.py" })
        scud = [bool]($pyProcs | Where-Object { $_.CommandLine -match "scudfab02\.py" })
        learner = [bool]($pyProcs | Where-Object { $_.CommandLine -match "learner_offline\.py" })
        infobot = [bool]($pyProcs | Where-Object { $_.CommandLine -match "infobot\.py" })
        repair_agent = [bool]($pyProcs | Where-Object { $_.CommandLine -match "repair_agent\.py" })
    }

    $latestBudget = Get-LatestLine -Path $safetyLog -Pattern "BUDGET day_ny="
    $latestScan = Get-LatestLine -Path $safetyLog -Pattern "SCAN_LIMIT"
    $latestSnapshotDegraded = Get-LatestLine -Path $safetyLog -Pattern "SNAPSHOT_HEALTH_DEGRADED"
    $latestEntrySignal = Get-LatestLine -Path $safetyLog -Pattern "ENTRY_SIGNAL"
    $latestOrder = Get-LatestLine -Path $safetyLog -Pattern "Order executed|ORDER_SEND|DEAL_ADD|deal="
    $latestSkip = Get-LatestLine -Path $safetyLog -Pattern "ENTRY_SKIP"
    $skipReasons = Get-RecentSkipReasons -SafetyLogPath $safetyLog -Tail 1500

    $scudRecent = Get-LatestLine -Path $scudLog -Pattern "RUN_ONCE"
    $verdictLight = "UNKNOWN"
    $qaLight = "UNKNOWN"
    try {
        $verdictPath = Join-Path $metaDir "verdict.json"
        if (Test-Path $verdictPath) {
            $verdictObj = Get-Content -Path $verdictPath -Raw | ConvertFrom-Json
            $verdictLight = [string]($verdictObj.light)
        }
    } catch {
        $verdictLight = "READ_ERROR"
    }
    try {
        $learnerPath = Join-Path $metaDir "learner_advice.json"
        if (Test-Path $learnerPath) {
            $learnerObj = Get-Content -Path $learnerPath -Raw | ConvertFrom-Json
            $qaLight = [string]($learnerObj.qa_light)
        }
    } catch {
        $qaLight = "READ_ERROR"
    }

    $mt5File = Get-LatestMt5LogFile -TerminalRoot $TerminalRoot
    $mt5Ready = $null
    $mt5Auto = $null
    if ($null -ne $mt5File) {
        $mt5Ready = Get-LatestLine -Path $mt5File.FullName -Pattern "HybridAgent ready"
        $mt5Auto = Get-LatestLine -Path $mt5File.FullName -Pattern "automated trading is (enabled|disabled)"
    }

    $report = [ordered]@{
        schema = "oanda_mt5.active_checklist.v1"
        ts_utc = $utcNow.ToString("o")
        ts_pl = $plNow.ToString("yyyy-MM-dd HH:mm:ss zzz")
        trigger = [ordered]@{
            window_id = $WindowId
            line = $TriggerLine
        }
        system_control_status_pass = [bool]$statusPass
        system_control_status_raw = $statusOutput
        process_alive = $procChecks
        snapshot = [ordered]@{
            verdict_light = $verdictLight
            learner_qa_light = $qaLight
            latest_budget = $latestBudget
            latest_scan = $latestScan
            latest_snapshot_degraded = $latestSnapshotDegraded
            latest_entry_signal = $latestEntrySignal
            latest_order = $latestOrder
            latest_skip = $latestSkip
            skip_reasons_recent = $skipReasons
            scud_recent = $scudRecent
            mt5_log_file = $(if ($null -ne $mt5File) { [string]$mt5File.FullName } else { "" })
            mt5_hybrid_ready = $mt5Ready
            mt5_algo_toggle = $mt5Auto
        }
    }

    $stamp = $utcNow.ToString("yyyyMMdd_HHmmss")
    $base = "active_checklist_{0}_{1}" -f $stamp, ($WindowId -replace "[^A-Za-z0-9_]+", "_")
    $jsonPath = Join-Path $outputDir ($base + ".json")
    $txtPath = Join-Path $outputDir ($base + ".txt")

    $report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding UTF8

    $txt = @()
    $txt += "ACTIVE CHECKLIST PASS"
    $txt += "UTC: $($utcNow.ToString("o"))"
    $txt += "PL:  $($plNow.ToString("yyyy-MM-dd HH:mm:ss zzz"))"
    $txt += "window_id: $WindowId"
    $txt += "system_control_status_pass: $statusPass"
    $txt += "verdict_light: $verdictLight"
    $txt += "learner_qa_light: $qaLight"
    $txt += "latest_scan: $latestScan"
    $txt += "latest_entry_signal: $latestEntrySignal"
    $txt += "latest_order: $latestOrder"
    $txt += "latest_snapshot_degraded: $latestSnapshotDegraded"
    $txt += "latest_skip: $latestSkip"
    $txt += "mt5_hybrid_ready: $mt5Ready"
    $txt += "mt5_algo_toggle: $mt5Auto"
    $txt += "json_report: $jsonPath"
    $txt | Set-Content -Path $txtPath -Encoding UTF8

    Write-Host ("[ACTIVE_CHECKLIST] window={0} report={1}" -f $WindowId, $jsonPath) -ForegroundColor Green
    return $jsonPath
}

$runtimeRoot = Resolve-RootPath -Path $Root
$safetyLog = Join-Path $runtimeRoot "LOGS\safetybot.log"
if (-not (Test-Path $safetyLog)) {
    throw "Missing safety log: $safetyLog"
}

$offsets = @{}
$null = Read-AppendedLines -Path $safetyLog -Offsets $offsets

$lastPhase = "UNKNOWN"
$lastWindow = ""
$phaseLine = Get-LatestLine -Path $safetyLog -Pattern "WINDOW_PHASE"
if ($phaseLine -match "phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)") {
    $lastPhase = [string]$Matches[1]
    $lastWindow = [string]$Matches[2]
}

$needNonActiveBeforeTrigger = ($lastPhase -eq "ACTIVE")
$seenNonActive = (-not $needNonActiveBeforeTrigger)
$deadline = (Get-Date).AddHours([Math]::Max(1, [int]$TimeoutHours))

Write-Host ("[ACTIVE_CHECKLIST] watcher started root={0} last_phase={1} last_window={2}" -f $runtimeRoot, $lastPhase, $lastWindow) -ForegroundColor Cyan

while ((Get-Date) -lt $deadline) {
    $lines = Read-AppendedLines -Path $safetyLog -Offsets $offsets
    foreach ($line in $lines) {
        $msg = [string]$line
        if ([string]::IsNullOrWhiteSpace($msg)) {
            continue
        }
        if ($msg -notmatch "WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)") {
            continue
        }

        $phase = [string]$Matches[1]
        $window = [string]$Matches[2]

        if ($phase -ne "ACTIVE") {
            $seenNonActive = $true
            continue
        }

        if ($phase -eq "ACTIVE" -and $seenNonActive) {
            $null = Invoke-ActiveChecklist -RuntimeRoot $runtimeRoot -TerminalRoot $Mt5TerminalRoot -WindowId $window -TriggerLine $msg
            exit 0
        }
    }
    Start-Sleep -Seconds ([Math]::Max(1, [int]$PollSec))
}

Write-Host "[ACTIVE_CHECKLIST] timeout reached without ACTIVE transition." -ForegroundColor Yellow
exit 2
