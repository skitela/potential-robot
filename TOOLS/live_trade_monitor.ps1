param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5TerminalRoot = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [int]$IntervalSec = 2,
    [int]$PulseEverySec = 30,
    [int]$StallAlertSec = 900,
    [int]$WarmStartBytes = 524288,
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
        [int64]$MaxReadBytes = 1024KB,
        [int64]$WarmBytes = 0
    )
    if (-not (Test-Path $Path)) {
        return @()
    }

    $item = Get-Item -Path $Path -ErrorAction Stop
    $len = [int64]$item.Length

    $isFirstRead = $false
    if (-not $Offsets.ContainsKey($Path)) {
        $isFirstRead = $true
        $warm = [int64]([Math]::Max(0, $WarmBytes))
        $Offsets[$Path] = [int64]([Math]::Max(0, ($len - $warm)))
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

    if (-not (Get-Variable -Name EncCache -Scope Script -ErrorAction SilentlyContinue)) {
        $Script:EncCache = @{}
    }
    if (-not $Script:EncCache.ContainsKey($Path)) {
        $enc = [System.Text.Encoding]::UTF8
        try {
            $fs0 = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $bom = New-Object byte[] 4
                [void]$fs0.Read($bom, 0, 4)
                if ($bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { $enc = [System.Text.Encoding]::Unicode }
                elseif ($bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { $enc = [System.Text.Encoding]::BigEndianUnicode }
                elseif ($bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) { $enc = [System.Text.Encoding]::UTF8 }
            } finally {
                $fs0.Dispose()
            }
        } catch {
            $enc = [System.Text.Encoding]::UTF8
        }
        $Script:EncCache[$Path] = $enc
    }

    $encUse = [System.Text.Encoding]$Script:EncCache[$Path]
    if (($encUse.WebName -match "utf-16") -and (($start % 2) -ne 0)) {
        $start = [int64]([Math]::Max(0, ($start - 1)))
    }

    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $toRead = [int]([Math]::Max(0, [Math]::Min([int64]2147483647, ($len - $start))))
        if ($toRead -gt $MaxReadBytes) { $toRead = [int]$MaxReadBytes }
        if (($encUse.WebName -match "utf-16") -and (($toRead % 2) -ne 0)) { $toRead -= 1 }
        $text = ""
        if ($toRead -gt 0) {
            $buf = New-Object byte[] $toRead
            $read = $fs.Read($buf, 0, $toRead)
            if (($encUse.WebName -match "utf-16") -and (($read % 2) -ne 0)) { $read -= 1 }
            if ($read -gt 0) {
                if ($read -ne $toRead) { $buf = $buf[0..($read - 1)] }
                $text = $encUse.GetString($buf)
            }
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
$warmBytes = [int64]([Math]::Max(0, [int]$WarmStartBytes))
if ([string]::IsNullOrWhiteSpace($StatusPath)) {
    $StatusPath = Join-Path $runtimeRoot "RUN\live_trade_monitor_status.json"
}

$configPath = Join-Path $runtimeRoot "CONFIG\strategy.json"
$expectedRawSymbols = @()
try {
    if (Test-Path $configPath) {
        $cfg = Get-Content $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($cfg -and $cfg.symbols_to_trade) {
            $expectedRawSymbols = @($cfg.symbols_to_trade | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }
    }
} catch {
    $expectedRawSymbols = @()
}

$tradePattern = [regex]'(?i)\b(buy|sell|order|open|close|filled|reject|deal|retcode|entry|exit|no[-_ ]?trade|fail[-_ ]?safe)\b'
$excludePattern = [regex]'(?i)\b(budget|price used|oanda_price_breakdown|runtime_metrics_10m|status_pulse|heartbeat status=alive|monitor aktywny)\b'
$buyPattern = [regex]'(?i)\b(buy)\b'
$sellPattern = [regex]'(?i)\b(sell)\b'
$scanPattern = [regex]'(?i)\bSCAN_LIMIT\b'
$entrySignalPattern = [regex]'(?i)\bENTRY_SIGNAL\b'
$entrySignalSymPattern = [regex]'(?i)\bENTRY_SIGNAL\b.*?\bsymbol=([^\s]+)\b.*?\bgrp=([A-Z0-9_]+)\b'
$resolveSymPattern = [regex]'(?i)\bRESOLVE_SYMBOL\b.*?\braw=([^\s]+)\b.*?\bcanon=([^\s]+)\b'
$entrySkipSymReasonPattern = [regex]'(?i)\bENTRY_SKIP(?:_PRE)?\b.*?\bsymbol=([^\s]+)\b.*?\bgrp=([A-Z0-9_]+)\b.*?\breason=([A-Z0-9_]+)\b'
$orderExecPattern = [regex]'(?i)\b(Order executed|ORDER_EXECUTED|DEAL_ADD|DEAL_RESULT|TRADE_TRANSACTION_DEAL_ADD)\b'
$dispatchPattern = [regex]'(?i)\bHYBRID_DISPATCH \| DEAL over ZMQ\b'
$dispatchSymPattern = [regex]'(?i)\bHYBRID_DISPATCH \| DEAL over ZMQ\b.*?\bsymbol=([^\s]+)\b'
$dispatchAckPattern = [regex]'(?i)\bHYBRID_DISPATCH_ACK \|\b.*?\bsymbol=([^\s]+)\b.*?\bretcode=([0-9]+)\b'
$dispatchRejectPattern = [regex]'(?i)\bHYBRID_DISPATCH_REJECT \|\b.*?\bsymbol=([^\s]+)\b.*?\bretcode=([0-9]+)\b'
$dispatchErrorPattern = [regex]'(?i)\bHYBRID_DISPATCH_(?:FAIL|ERROR)\b.*?\bsymbol=([^\s]+)\b'
$rejectPattern = [regex]'(?i)\bZMQ_REPLY \| status=REJECTED\b'
$ret10017Pattern = [regex]'(?i)\bretcode=10017\b|Order failed:\s*10017'
$windowPattern = [regex]'WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)'
$windowGroupPattern = [regex]'WINDOW_PHASE\s+phase=([A-Z_]+)\s+window=([A-Z0-9_]+|NONE)\s+group=([A-Z0-9_]+)\s+entry_allowed=([01truefalse]+)\s+strict_group=([01truefalse]+)'
$skipReasonPattern = [regex]'(?i)\bENTRY_SKIP(?:_PRE)?\b.*?\breason=([A-Z0-9_]+)\b'
$missingSnapshotPattern = [regex]'(?i)\bSYMBOL_INFO_STRICT_SNAPSHOT_MISSING\b.*?\bsymbol=([^\s]+)\b'
$eaInitPattern = [regex]'(?i)\bHybridAgent\s+\(([^,]+),[^\)]+\)\s+ZMQ_INIT_OK\b'
$groupArbPattern = [regex]'(?i)\bGROUP_ARB\b.*?\bgrp=([A-Z0-9_]+)\b.*?\bprio_factor=([0-9.]+)\b.*?\bunlock=([0-9.]+)\b.*?\brisk_entry=([01])\b.*?\brisk_borrow_block=([01])\b.*?\brisk_friday=([01])\b.*?\brisk_reopen=([01])\b.*?\breason=([A-Z0-9_]+)\b'
$barPattern = [regex]'(?i)\bZMQ_BAR\b\s*\|\s*([A-Z0-9\.\-]+)\s*\|\s*Time:\s*(\d+)\b'

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

$rawToCanon = @{}
$canonToRaw = @{}
$sym = @{}
$symSkip = @{}
$symMissingSnap = @{}
$eaAttached = @{}
$groupState = @{}
$groupArb = @{}
$barState = @{}

function Normalize-Symbol {
    param([string]$Symbol)
    if ([string]::IsNullOrWhiteSpace($Symbol)) { return "" }
    $s = [string]$Symbol
    if ($rawToCanon.ContainsKey($s)) { return [string]$rawToCanon[$s] }
    return $s
}

function Ensure-SymRow {
    param([string]$Symbol)
    if ([string]::IsNullOrWhiteSpace($Symbol)) { return $null }
    if (-not $sym.ContainsKey($Symbol)) {
        $sym[$Symbol] = [ordered]@{
            symbol = $Symbol
            raw_symbol = if ($canonToRaw.ContainsKey($Symbol)) { [string]$canonToRaw[$Symbol] } else { "" }
            group = ""
            entry_signal = 0
            dispatch = 0
            ack = 0
            reject = 0
            retcode_10017 = 0
            missing_snapshot = 0
            last_entry_signal_utc = ""
            last_dispatch_utc = ""
            last_ack_utc = ""
            last_reject_utc = ""
            last_skip_utc = ""
        }
        $symSkip[$Symbol] = @{}
    }
    return $sym[$Symbol]
}

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

function Format-TopSkipReasonsForSymbol {
    param([string]$Symbol, [int]$Top = 3)
    if ([string]::IsNullOrWhiteSpace($Symbol)) { return "n/a" }
    if (-not $symSkip.ContainsKey($Symbol)) { return "n/a" }
    return (Format-TopSkipReasons -ReasonCounts $symSkip[$Symbol] -Top $Top)
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
            $warm = 0
            if ($warmBytes -gt 0 -and ($name -eq "SAFETY" -or $name -eq "MT5")) {
                $warm = $warmBytes
            }
            $lines = Read-AppendedLines -Path $path -Offsets $offsets -WarmBytes $warm
            foreach ($line in $lines) {
                $msg = [string]$line
                if ([string]::IsNullOrWhiteSpace($msg)) {
                    continue
                }

                if ($name -eq "SAFETY") {
                    $rm = $resolveSymPattern.Match($msg)
                    if ($rm.Success) {
                        $raw = [string]$rm.Groups[1].Value
                        $canon = [string]$rm.Groups[2].Value
                        if (-not [string]::IsNullOrWhiteSpace($raw) -and -not [string]::IsNullOrWhiteSpace($canon)) {
                            $rawToCanon[$raw] = $canon
                            $canonToRaw[$canon] = $raw
                            $row = Ensure-SymRow -Symbol $canon
                            if ($null -ne $row) {
                                $row.raw_symbol = $raw
                            }
                        }
                    }

                    $phaseMatchPre = $windowPattern.Match($msg)
                    if ($phaseMatchPre.Success) {
                        $lastPhase = [string]$phaseMatchPre.Groups[1].Value
                        $lastWindow = [string]$phaseMatchPre.Groups[2].Value
                    }
                    $wg = $windowGroupPattern.Match($msg)
                    if ($wg.Success) {
                        $gPhase = [string]$wg.Groups[1].Value
                        $gWindow = [string]$wg.Groups[2].Value
                        $gName = [string]$wg.Groups[3].Value
                        $gEntry = [string]$wg.Groups[4].Value
                        $gStrict = [string]$wg.Groups[5].Value
                        $groupState[$gName] = [ordered]@{
                            group = $gName
                            phase = $gPhase
                            window = $gWindow
                            entry_allowed = $gEntry
                            strict_group = $gStrict
                            last_seen_utc = (Get-Date).ToUniversalTime().ToString("o")
                        }
                    }
                    if ($scanPattern.IsMatch($msg)) {
                        $lastScanAt = Get-Date
                    }

                    $ga = $groupArbPattern.Match($msg)
                    if ($ga.Success) {
                        $gName = [string]$ga.Groups[1].Value
                        $groupArb[$gName] = [pscustomobject]@{
                            group = $gName
                            prio_factor = [double]$ga.Groups[2].Value
                            unlock = [double]$ga.Groups[3].Value
                            risk_entry = [int]$ga.Groups[4].Value
                            risk_borrow_block = [int]$ga.Groups[5].Value
                            risk_friday = [int]$ga.Groups[6].Value
                            risk_reopen = [int]$ga.Groups[7].Value
                            reason = [string]$ga.Groups[8].Value
                            last_seen_utc = (Get-Date).ToUniversalTime().ToString("o")
                        }
                    }

                    $bm = $barPattern.Match($msg)
                    if ($bm.Success) {
                        $sBar = Normalize-Symbol -Symbol ([string]$bm.Groups[1].Value)
                        $epoch = 0
                        try { $epoch = [int64]$bm.Groups[2].Value } catch { $epoch = 0 }
                        if (-not [string]::IsNullOrWhiteSpace($sBar) -and $epoch -gt 0) {
                            if (-not $barState.ContainsKey($sBar)) {
                                $barState[$sBar] = [ordered]@{ last_epoch = 0; count = 0; last_seen_utc = "" }
                            }
                            $barState[$sBar].last_epoch = [int64]$epoch
                            $barState[$sBar].count = [int]$barState[$sBar].count + 1
                            $barState[$sBar].last_seen_utc = (Get-Date).ToUniversalTime().ToString("o")
                            [void](Ensure-SymRow -Symbol $sBar)
                        }
                    }
                }

                if ($name -eq "MT5") {
                    $ea = $eaInitPattern.Match($msg)
                    if ($ea.Success) {
                        $s = Normalize-Symbol -Symbol ([string]$ea.Groups[1].Value)
                        if (-not [string]::IsNullOrWhiteSpace($s)) {
                            $eaAttached[$s] = (Get-Date).ToUniversalTime().ToString("o")
                            [void](Ensure-SymRow -Symbol $s)
                        }
                    }
                }

                if (-not $tradePattern.IsMatch($msg)) {
                    continue
                }
                if ($excludePattern.IsMatch($msg)) {
                    continue
                }

                if ($name -eq "SAFETY") {
                    $mm = $missingSnapshotPattern.Match($msg)
                    if ($mm.Success) {
                        $s = Normalize-Symbol -Symbol ([string]$mm.Groups[1].Value)
                        if (-not [string]::IsNullOrWhiteSpace($s)) {
                            $row = Ensure-SymRow -Symbol $s
                            if ($null -ne $row) {
                                $row.missing_snapshot = [int]$row.missing_snapshot + 1
                            }
                        }
                    }

                    if ($entrySignalPattern.IsMatch($msg)) {
                        $totals.entry_signal = [int]$totals.entry_signal + 1
                        $lastTradeIntentAt = Get-Date
                        $es = $entrySignalSymPattern.Match($msg)
                        if ($es.Success) {
                            $s = Normalize-Symbol -Symbol ([string]$es.Groups[1].Value)
                            $g = [string]$es.Groups[2].Value
                            $row = Ensure-SymRow -Symbol $s
                            if ($null -ne $row) {
                                $row.entry_signal = [int]$row.entry_signal + 1
                                $row.group = $g
                                $row.last_entry_signal_utc = (Get-Date).ToUniversalTime().ToString("o")
                            }
                        }
                    }
                    $dsm = $dispatchSymPattern.Match($msg)
                    if ($dsm.Success) {
                        $totals.dispatch = [int]$totals.dispatch + 1
                        $s = Normalize-Symbol -Symbol ([string]$dsm.Groups[1].Value)
                        $row = Ensure-SymRow -Symbol $s
                        if ($null -ne $row) {
                            $row.dispatch = [int]$row.dispatch + 1
                            $row.last_dispatch_utc = (Get-Date).ToUniversalTime().ToString("o")
                        }
                    }
                    $ackm = $dispatchAckPattern.Match($msg)
                    if ($ackm.Success) {
                        $s = Normalize-Symbol -Symbol ([string]$ackm.Groups[1].Value)
                        $ret = [int]$ackm.Groups[2].Value
                        $row = Ensure-SymRow -Symbol $s
                        if ($null -ne $row) {
                            $row.ack = [int]$row.ack + 1
                            $row.last_ack_utc = (Get-Date).ToUniversalTime().ToString("o")
                            if ($ret -eq 10017) { $row.retcode_10017 = [int]$row.retcode_10017 + 1 }
                        }
                    }
                    $rejm = $dispatchRejectPattern.Match($msg)
                    if ($rejm.Success) {
                        $s = Normalize-Symbol -Symbol ([string]$rejm.Groups[1].Value)
                        $ret = [int]$rejm.Groups[2].Value
                        $row = Ensure-SymRow -Symbol $s
                        if ($null -ne $row) {
                            $row.reject = [int]$row.reject + 1
                            $row.last_reject_utc = (Get-Date).ToUniversalTime().ToString("o")
                            if ($ret -eq 10017) { $row.retcode_10017 = [int]$row.retcode_10017 + 1 }
                        }
                    }
                    $der = $dispatchErrorPattern.Match($msg)
                    if ($der.Success) {
                        $s = Normalize-Symbol -Symbol ([string]$der.Groups[1].Value)
                        [void](Ensure-SymRow -Symbol $s)
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
                    $ms = $entrySkipSymReasonPattern.Match($msg)
                    if ($ms.Success) {
                        $s = Normalize-Symbol -Symbol ([string]$ms.Groups[1].Value)
                        $g = [string]$ms.Groups[2].Value
                        $r = [string]$ms.Groups[3].Value
                        if (-not [string]::IsNullOrWhiteSpace($s) -and -not [string]::IsNullOrWhiteSpace($r)) {
                            $row = Ensure-SymRow -Symbol $s
                            if ($null -ne $row) {
                                $row.group = $g
                                $row.last_skip_utc = (Get-Date).ToUniversalTime().ToString("o")
                            }
                            if (-not $symSkip.ContainsKey($s)) { $symSkip[$s] = @{} }
                            if (-not $symSkip[$s].ContainsKey($r)) { $symSkip[$s][$r] = 0 }
                            $symSkip[$s][$r] = [int]$symSkip[$s][$r] + 1
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

                $expectedCanon = @()
                foreach ($r in $expectedRawSymbols) {
                    if ($rawToCanon.ContainsKey($r)) {
                        $expectedCanon += [string]$rawToCanon[$r]
                    } else {
                        $expectedCanon += [string]$r
                    }
                }
                $expectedCanon = @($expectedCanon | Sort-Object -Unique)

                $symRows = @()
                $allSyms = @()
                if (@($expectedCanon).Count -gt 0) {
                    $allSyms = @($expectedCanon)
                } else {
                    $allSyms = @($sym.Keys | Sort-Object -Unique)
                }
                foreach ($s in $allSyms) {
                    $canon = Normalize-Symbol -Symbol ([string]$s)
                    $row = Ensure-SymRow -Symbol $canon
                    if ($null -eq $row) { continue }
                    $row.raw_symbol = if ($canonToRaw.ContainsKey($canon)) { [string]$canonToRaw[$canon] } else { [string]$row.raw_symbol }
                    $barEpoch = $null
                    $barUtc = ""
                    $barAge = $null
                    $barDelta = $null
                    $barAhead = $null
                    $barSeen = 0
                    if ($barState.ContainsKey($canon)) {
                        $barEpoch = [int64]$barState[$canon].last_epoch
                        $barSeen = [int]$barState[$canon].count
                        try {
                            $barUtc = ([DateTimeOffset]::FromUnixTimeSeconds([int64]$barEpoch)).UtcDateTime.ToString("o")
                            $delta = [int]([DateTimeOffset]::UtcNow.ToUnixTimeSeconds() - [int64]$barEpoch)
                            $barDelta = [int]$delta
                            $barAhead = [bool]($delta -lt 0)
                            $barAge = [int]([Math]::Abs([double]$delta))
                        } catch {
                            $barUtc = ""
                            $barAge = $null
                            $barDelta = $null
                            $barAhead = $null
                        }
                    }

                    $symRows += [pscustomobject]@{
                        symbol = [string]$row.symbol
                        raw_symbol = [string]$row.raw_symbol
                        group = [string]$row.group
                        entry_signal = [int]$row.entry_signal
                        dispatch = [int]$row.dispatch
                        ack = [int]$row.ack
                        reject = [int]$row.reject
                        retcode_10017 = [int]$row.retcode_10017
                        missing_snapshot = [int]$row.missing_snapshot
                        top_skip_reasons = (Format-TopSkipReasonsForSymbol -Symbol $canon -Top 3)
                        ea_attached = [bool]$eaAttached.ContainsKey($canon)
                        ea_last_seen_utc = if ($eaAttached.ContainsKey($canon)) { [string]$eaAttached[$canon] } else { "" }
                        bar_last_epoch = $barEpoch
                        bar_last_utc = $barUtc
                        bar_age_sec = $barAge
                        bar_delta_sec = $barDelta
                        bar_ahead = $barAhead
                        bar_seen = $barSeen
                        last_entry_signal_utc = [string]$row.last_entry_signal_utc
                        last_dispatch_utc = [string]$row.last_dispatch_utc
                        last_ack_utc = [string]$row.last_ack_utc
                        last_reject_utc = [string]$row.last_reject_utc
                        last_skip_utc = [string]$row.last_skip_utc
                    }
                }
                $rankEntry = @($symRows | Sort-Object -Property entry_signal -Descending | Select-Object -First 15)
                $rankDispatch = @($symRows | Sort-Object -Property dispatch -Descending | Select-Object -First 15)

                $status = @{
                    schema_version = 2
                    ts_utc = $now.ToUniversalTime().ToString("o")
                    ts_local = $now.ToString("o")
                    root = $runtimeRoot
                    phase = $lastPhase
                    window = $lastWindow
                    scan_age_sec = $scanAgeOut
                    trade_intent_age_sec = $tradeAgeOut
                    top_skip_reasons = (Format-TopSkipReasons -ReasonCounts $skipReasons -Top 5)
                    totals = $totals
                    mt5_log = $currentMt5Path
                    expected_symbols_raw = $expectedRawSymbols
                    expected_symbols_canon = $expectedCanon
                    group_state = $groupState
                    group_arb = $groupArb
                    symbol_state = $symRows
                    ranking_entry_signal = $rankEntry
                    ranking_dispatch = $rankDispatch
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
