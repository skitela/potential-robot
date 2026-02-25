param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5TerminalRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [int]$IntervalSec = 2,
    [int]$PulseEverySec = 30,
    [int]$StallAlertSec = 900,
    [string]$StatusPath = ""
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

function Get-LatestMt5LogFile {
    param([string]$TerminalRoot)
    $dir = Join-Path $TerminalRoot "MQL5\Logs"
    if (-not (Test-Path $dir)) {
        return $null
    }
    return (Get-ChildItem -Path $dir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
}

$runtimeRoot = Resolve-RootPath -Path $Root
$interval = [Math]::Max(1, [int]$IntervalSec)
$pulseEvery = [Math]::Max(10, [int]$PulseEverySec)
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = Join-Path $runtimeRoot "RUN\live_trade_monitor_status.json"
}

$tradePattern = [regex]'(?i)\b(buy|sell|order|open|close|filled|reject|deal|retcode|entry|exit|no[-_ ]?trade|fail[-_ ]?safe)\b'
$excludePattern = [regex]'(?i)\b(budget|price used|oanda_price_breakdown|runtime_metrics_10m|status_pulse|heartbeat status=alive|monitor aktywny)\b'
$buyPattern = [regex]'(?i)\b(buy)\b'
$sellPattern = [regex]'(?i)\b(sell)\b'
$scanPattern = [regex]'(?i)\bSCAN_LIMIT\b'
$entrySignalPattern = [regex]'(?i)\bENTRY_SIGNAL\b'
$orderExecPattern = [regex]'(?i)\b(Order executed|ORDER_EXECUTED|DEAL_ADD|DEAL_RESULT|TRADE_TRANSACTION_DEAL_ADD)\b'
$dispatchPattern = [regex]'(?i)\bHYBRID_DISPATCH \| DEAL over ZMQ\b'
$rejectPattern = [regex]'(?i)\bZMQ_REPLY \| status=REJECTED\b'
$ret10017Pattern = [regex]'(?i)\bretcode=10017\b|Order failed:\s*10017'
$windowPattern = [regex]'WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)'
$skipReasonPattern = [regex]'(?i)\bENTRY_SKIP(?:_PRE)?\b.*?\breason=([A-Z0-9_]+)\b'

$tracked = @(
    @{ name = "SAFETY"; path = (Join-Path $runtimeRoot "LOGS\safetybot.log") },
    @{ name = "SCUD"; path = (Join-Path $runtimeRoot "LOGS\scudfab02.log") },
    @{ name = "INFO"; path = (Join-Path $runtimeRoot "LOGS\infobot\infobot.log") },
    @{ name = "REPAIR"; path = (Join-Path $runtimeRoot "LOGS\repair_agent\repair_agent.log") }
)

$offsets = @{}
$totals = @{
    buy = 0
    sell = 0
    events = 0
    entry_signal = 0
    dispatch = 0
    rejected = 0
    retcode_10017 = 0
    order_executed = 0
}
$lastPulse = Get-Date
$currentMt5Path = ""
$lastScanAt = $null
$lastTradeIntentAt = $null
$skipReasons = @{}
$lastPhase = "UNKNOWN"
$lastWindow = "NONE"

function Format-TopSkipReasons {
    param([hashtable]$ReasonCounts, [int]$Top = 3)
    if (-not $ReasonCounts -or $ReasonCounts.Count -eq 0) {
        return "n/a"
    }
    $pairs = @()
    foreach ($k in $ReasonCounts.Keys) {
        $pairs += [PSCustomObject]@{ reason = [string]$k; count = [int]$ReasonCounts[$k] }
    }
    $topPairs = $pairs | Sort-Object -Property count -Descending | Select-Object -First ([Math]::Max(1, [int]$Top))
    return (($topPairs | ForEach-Object { "{0}:{1}" -f $_.reason, $_.count }) -join ", ")
}

Write-Host ("[MONITOR] start root={0} interval={1}s" -f $runtimeRoot, $interval) -ForegroundColor Cyan
Write-Host ("[MONITOR] filters=buy/sell/order/open/close/filled/reject/deal/retcode/entry/exit/no-trade/fail-safe") -ForegroundColor Cyan

while ($true) {
    try {
        $mt5 = Get-LatestMt5LogFile -TerminalRoot $Mt5TerminalRoot
        if ($null -ne $mt5) {
            $newMt5Path = [string]$mt5.FullName
            if ($newMt5Path -ne $currentMt5Path) {
                $currentMt5Path = $newMt5Path
                Write-Host ("[{0}] [MT5] active log => {1}" -f (Get-Date -Format "HH:mm:ss"), $currentMt5Path) -ForegroundColor DarkCyan
            }
        }

        $scanTargets = @($tracked)
        if (-not [string]::IsNullOrWhiteSpace($currentMt5Path)) {
            $scanTargets += @{ name = "MT5"; path = $currentMt5Path }
        }

        foreach ($src in $scanTargets) {
            $name = [string]$src.name
            $path = [string]$src.path
            $lines = Read-AppendedLines -Path $path -Offsets $offsets
            foreach ($line in $lines) {
                $msg = [string]$line
                if ([string]::IsNullOrWhiteSpace($msg)) {
                    continue
                }
                if (-not $tradePattern.IsMatch($msg)) {
                    continue
                }
                if ($excludePattern.IsMatch($msg)) {
                    continue
                }

                if ($name -eq "SAFETY") {
                    $phaseMatch = $windowPattern.Match($msg)
                    if ($phaseMatch.Success) {
                        $lastPhase = [string]$phaseMatch.Groups[1].Value
                        $lastWindow = [string]$phaseMatch.Groups[2].Value
                    }
                    if ($scanPattern.IsMatch($msg)) {
                        $lastScanAt = Get-Date
                    }
                    if ($entrySignalPattern.IsMatch($msg)) {
                        $totals.entry_signal = [int]$totals.entry_signal + 1
                        $lastTradeIntentAt = Get-Date
                    }
                    if ($dispatchPattern.IsMatch($msg)) {
                        $totals.dispatch = [int]$totals.dispatch + 1
                    }
                    if ($rejectPattern.IsMatch($msg)) {
                        $totals.rejected = [int]$totals.rejected + 1
                    }
                    if ($ret10017Pattern.IsMatch($msg)) {
                        $totals.retcode_10017 = [int]$totals.retcode_10017 + 1
                    }
                    if ($orderExecPattern.IsMatch($msg)) {
                        $totals.order_executed = [int]$totals.order_executed + 1
                        $lastTradeIntentAt = Get-Date
                    }
                    $m = $skipReasonPattern.Match($msg)
                    if ($m.Success) {
                        $reason = [string]$m.Groups[1].Value
                        if (-not [string]::IsNullOrWhiteSpace($reason)) {
                            if (-not $skipReasons.ContainsKey($reason)) {
                                $skipReasons[$reason] = 0
                            }
                            $skipReasons[$reason] = [int]$skipReasons[$reason] + 1
                        }
                    }
                }

                $totals.events = [int]$totals.events + 1
                if ($buyPattern.IsMatch($msg)) {
                    $totals.buy = [int]$totals.buy + 1
                }
                if ($sellPattern.IsMatch($msg)) {
                    $totals.sell = [int]$totals.sell + 1
                }

                $color = "Gray"
                if ($buyPattern.IsMatch($msg)) { $color = "Green" }
                elseif ($sellPattern.IsMatch($msg)) { $color = "Red" }
                elseif ($msg -match "(?i)reject|fail[-_ ]?safe|error|retcode") { $color = "Yellow" }
                Write-Host ("[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $name, $msg) -ForegroundColor $color
            }
        }

        $now = Get-Date
        if ((New-TimeSpan -Start $lastPulse -End $now).TotalSeconds -ge $pulseEvery) {
            Write-Host ("[{0}] [PULSE] events={1} buy={2} sell={3} entry={4} dispatch={5} reject={6} ret10017={7} exec={8}" -f ($now.ToString("HH:mm:ss")), $totals.events, $totals.buy, $totals.sell, $totals.entry_signal, $totals.dispatch, $totals.rejected, $totals.retcode_10017, $totals.order_executed) -ForegroundColor Cyan
            if ($null -ne $lastScanAt) {
                $scanAge = [int](New-TimeSpan -Start $lastScanAt -End $now).TotalSeconds
                $tradeAge = if ($null -eq $lastTradeIntentAt) { -1 } else { [int](New-TimeSpan -Start $lastTradeIntentAt -End $now).TotalSeconds }
                if ($scanAge -le ([Math]::Max(60, [int]$StallAlertSec) * 2) -and ($tradeAge -lt 0 -or $tradeAge -ge [Math]::Max(60, [int]$StallAlertSec))) {
                    $top = Format-TopSkipReasons -ReasonCounts $skipReasons -Top 4
                    Write-Host ("[{0}] [STALL_ALERT] no ENTRY_SIGNAL/order for {1}s while scans are active | top_skip_reasons={2}" -f ($now.ToString("HH:mm:ss")), ([Math]::Max(0, $tradeAge)), $top) -ForegroundColor Yellow
                }
            }
            try {
                $scanAgeOut = if ($null -eq $lastScanAt) { -1 } else { [int](New-TimeSpan -Start $lastScanAt -End $now).TotalSeconds }
                $tradeAgeOut = if ($null -eq $lastTradeIntentAt) { -1 } else { [int](New-TimeSpan -Start $lastTradeIntentAt -End $now).TotalSeconds }
                $status = @{
                    ts_utc = $now.ToUniversalTime().ToString("o")
                    root = $runtimeRoot
                    phase = $lastPhase
                    window = $lastWindow
                    scan_age_sec = $scanAgeOut
                    trade_intent_age_sec = $tradeAgeOut
                    top_skip_reasons = (Format-TopSkipReasons -ReasonCounts $skipReasons -Top 5)
                    totals = $totals
                    mt5_log = $currentMt5Path
                }
                $status | ConvertTo-Json -Depth 8 | Set-Content -Path $StatusPath -Encoding UTF8
            } catch {
                Write-Host ("[{0}] [MONITOR_STATUS_ERR] {1}" -f ($now.ToString("HH:mm:ss")), $_.Exception.Message) -ForegroundColor Yellow
            }
            $lastPulse = $now
        }
    } catch {
        Write-Host ("[{0}] [MONITOR_ERR] {1}" -f (Get-Date -Format "HH:mm:ss"), $_.Exception.Message) -ForegroundColor Yellow
    }

    Start-Sleep -Seconds $interval
}
