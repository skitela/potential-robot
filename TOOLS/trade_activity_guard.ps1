param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [ValidateSet("full", "safety_only")]
    [string]$Profile = "safety_only",
    [int]$PollSec = 15,
    [int]$NoTradeSec = 900,
    [int]$RestartCooldownSec = 1200
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

function Write-JsonlEvent {
    param(
        [string]$Path,
        [hashtable]$Payload
    )
    $line = ($Payload | ConvertTo-Json -Compress -Depth 8)
    Add-Content -Path $Path -Value $line -Encoding UTF8
}

function Invoke-SystemControlAction {
    param(
        [string]$RuntimeRoot,
        [string]$ActionName,
        [ValidateSet("full", "safety_only")]
        [string]$Profile = "safety_only",
        [int]$TimeoutSec = 240
    )
    $sc = Join-Path $RuntimeRoot "TOOLS\SYSTEM_CONTROL.ps1"
    if (-not (Test-Path $sc)) {
        return @{
            ok = $false
            action = $ActionName
            error = "missing_system_control"
            output = ""
        }
    }
    try {
        $out = (& powershell -ExecutionPolicy Bypass -File $sc -Action $ActionName -Root $RuntimeRoot -Profile $Profile 2>&1 | Out-String).Trim()
        $ok = ($out -match "status=PASS")
        return @{
            ok = [bool]$ok
            action = $ActionName
            error = ""
            output = [string]$out
        }
    } catch {
        return @{
            ok = $false
            action = $ActionName
            error = [string]$_.Exception.Message
            output = ""
        }
    }
}

function Get-TopSkipReasons {
    param(
        [string]$SafetyLogPath,
        [int]$Tail = 1200,
        [int]$Top = 4
    )
    $out = @()
    if (-not (Test-Path $SafetyLogPath)) {
        return $out
    }
    $counts = @{}
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
        if (-not $counts.ContainsKey($k)) {
            $counts[$k] = 0
        }
        $counts[$k] = [int]$counts[$k] + 1
    }
    foreach ($k in $counts.Keys) {
        $out += [PSCustomObject]@{ reason = [string]$k; count = [int]$counts[$k] }
    }
    return @($out | Sort-Object -Property count -Descending | Select-Object -First ([Math]::Max(1, [int]$Top)))
}

function Get-LastWindowPhase {
    param([string]$SafetyLogPath)
    if (-not (Test-Path $SafetyLogPath)) {
        return @{
            phase = "UNKNOWN"
            window = "NONE"
            line = ""
        }
    }
    $m = Get-Content -Path $SafetyLogPath -Tail 1200 | Select-String -Pattern "WINDOW_PHASE" | Select-Object -Last 1
    if ($null -eq $m) {
        return @{
            phase = "UNKNOWN"
            window = "NONE"
            line = ""
        }
    }
    $line = [string]$m.Line
    if ($line -match "WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)") {
        return @{
            phase = [string]$Matches[1]
            window = [string]$Matches[2]
            line = $line
        }
    }
    return @{
        phase = "UNKNOWN"
        window = "NONE"
        line = $line
    }
}

$runtimeRoot = Resolve-RootPath -Path $Root
$runDir = Join-Path $runtimeRoot "RUN"
$logDir = Join-Path $runtimeRoot "LOGS"
$evidenceDir = Join-Path $runtimeRoot "EVIDENCE\trade_activity_guard"
$safetyLog = Join-Path $logDir "safetybot.log"

New-Item -Path $evidenceDir -ItemType Directory -Force | Out-Null
$jsonlPath = Join-Path $evidenceDir "guard_events.jsonl"
$statusPath = Join-Path $runDir "trade_activity_guard_status.json"

if (-not (Test-Path $safetyLog)) {
    throw "Missing safety log: $safetyLog"
}

$offsets = @{}
$null = Read-AppendedLines -Path $safetyLog -Offsets $offsets

$phaseInfo = Get-LastWindowPhase -SafetyLogPath $safetyLog
$phase = [string]$phaseInfo.phase
$windowId = [string]$phaseInfo.window
$lastPhaseLine = [string]$phaseInfo.line
$lastScanAt = $null
$lastTradeEventAt = $null
$lastRestartAt = $null
$restartDoneForActiveCycle = $false

Write-Host ("[TRADE_GUARD] start root={0} profile={1} no_trade_sec={2} cooldown_sec={3}" -f $runtimeRoot, $Profile, $NoTradeSec, $RestartCooldownSec) -ForegroundColor Cyan

while ($true) {
    $lines = Read-AppendedLines -Path $safetyLog -Offsets $offsets
    foreach ($line in $lines) {
        $msg = [string]$line
        if ([string]::IsNullOrWhiteSpace($msg)) {
            continue
        }

        if ($msg -match "WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)") {
            $newPhase = [string]$Matches[1]
            $newWindow = [string]$Matches[2]
            $lastPhaseLine = $msg
            if ($newPhase -ne $phase -or $newWindow -ne $windowId) {
                if ($newPhase -eq "ACTIVE" -and $phase -ne "ACTIVE") {
                    $restartDoneForActiveCycle = $false
                }
                if ($newPhase -ne "ACTIVE") {
                    $restartDoneForActiveCycle = $false
                }
                $phase = $newPhase
                $windowId = $newWindow
            }
            continue
        }

        if ($msg -match "SCAN_LIMIT") {
            $lastScanAt = Get-Date
            continue
        }

        if ($msg -match "ENTRY_SIGNAL|Order executed|ORDER_SEND|DEAL_ADD|DEAL_RESULT") {
            $lastTradeEventAt = Get-Date
            continue
        }
    }

    $now = Get-Date
    $scanAgeSec = if ($null -eq $lastScanAt) { [double]::PositiveInfinity } else { [double]($now - $lastScanAt).TotalSeconds }
    $tradeAgeSec = if ($null -eq $lastTradeEventAt) { [double]::PositiveInfinity } else { [double]($now - $lastTradeEventAt).TotalSeconds }
    $cooldownOk = $true
    if ($null -ne $lastRestartAt) {
        $cooldownOk = (([double]($now - $lastRestartAt).TotalSeconds) -ge [double]([Math]::Max(60, [int]$RestartCooldownSec)))
    }

    $shouldRepair = (
        ($phase -eq "ACTIVE") -and
        ($scanAgeSec -le [double]([Math]::Max(180, [int]$NoTradeSec * 2))) -and
        ($tradeAgeSec -ge [double]([Math]::Max(120, [int]$NoTradeSec))) -and
        $cooldownOk -and
        (-not $restartDoneForActiveCycle)
    )

    if ($shouldRepair) {
        $preStatus = Invoke-SystemControlAction -RuntimeRoot $runtimeRoot -ActionName "status" -Profile $Profile
        $stopRes = Invoke-SystemControlAction -RuntimeRoot $runtimeRoot -ActionName "stop" -Profile $Profile
        Start-Sleep -Seconds 3
        $startRes = Invoke-SystemControlAction -RuntimeRoot $runtimeRoot -ActionName "start" -Profile $Profile
        Start-Sleep -Seconds 2
        $postStatus = Invoke-SystemControlAction -RuntimeRoot $runtimeRoot -ActionName "status" -Profile $Profile
        $topSkips = Get-TopSkipReasons -SafetyLogPath $safetyLog -Tail 1500 -Top 4

        $evt = @{
            ts_utc = $now.ToUniversalTime().ToString("o")
            event = "repair_trigger_no_trade"
            profile = $Profile
            phase = $phase
            window = $windowId
            no_trade_sec = [int]$NoTradeSec
            scan_age_sec = [int]$scanAgeSec
            trade_age_sec = $(if ([double]::IsInfinity($tradeAgeSec)) { -1 } else { [int]$tradeAgeSec })
            pre_status = $preStatus
            stop = $stopRes
            start = $startRes
            post_status = $postStatus
            top_skip_reasons = $topSkips
            phase_line = $lastPhaseLine
        }
        Write-JsonlEvent -Path $jsonlPath -Payload $evt

        $lastRestartAt = Get-Date
        $restartDoneForActiveCycle = $true
        Write-Host ("[TRADE_GUARD] repair triggered in ACTIVE window={0}" -f $windowId) -ForegroundColor Yellow
    }

    $status = @{
        ts_utc = $now.ToUniversalTime().ToString("o")
        profile = $Profile
        phase = $phase
        window = $windowId
        scan_age_sec = $(if ([double]::IsInfinity($scanAgeSec)) { -1 } else { [int]$scanAgeSec })
        trade_age_sec = $(if ([double]::IsInfinity($tradeAgeSec)) { -1 } else { [int]$tradeAgeSec })
        restart_done_for_active_cycle = [bool]$restartDoneForActiveCycle
        last_restart_utc = $(if ($null -eq $lastRestartAt) { "" } else { $lastRestartAt.ToUniversalTime().ToString("o") })
        jsonl = $jsonlPath
    }
    $status | ConvertTo-Json -Depth 6 | Set-Content -Path $statusPath -Encoding UTF8

    Start-Sleep -Seconds ([Math]::Max(3, [int]$PollSec))
}
