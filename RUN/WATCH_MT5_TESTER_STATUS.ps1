param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalLogPath = "",
    [string]$TerminalLogDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\logs",
    [string]$WatchedTerminalPath = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$OutputRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [int]$PollSeconds = 60,
    [int]$StaleMinutes = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$eventRoot = Join-Path $OutputRoot "mt5_tester_events"
New-Item -ItemType Directory -Force -Path $eventRoot | Out-Null

$latestJsonPath = Join-Path $OutputRoot "mt5_tester_status_latest.json"
$latestMdPath = Join-Path $OutputRoot "mt5_tester_status_latest.md"

function Get-LastMatchInfo {
    param(
        [string[]]$Lines,
        [scriptblock]$Predicate
    )

    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if (& $Predicate $Lines[$i]) {
            return [pscustomobject]@{
                index = $i
                line  = $Lines[$i]
            }
        }
    }

    return $null
}

function Resolve-TerminalLogPath {
    param(
        [string]$PreferredPath,
        [string]$LogDir
    )

    if (-not [string]::IsNullOrWhiteSpace($PreferredPath) -and (Test-Path -LiteralPath $PreferredPath)) {
        return $PreferredPath
    }

    if (-not (Test-Path -LiteralPath $LogDir)) {
        return $PreferredPath
    }

    $latest = Get-ChildItem -LiteralPath $LogDir -Filter "*.log" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($latest) {
        return $latest.FullName
    }

    return $PreferredPath
}

function Get-LogLineTimestamp {
    param(
        [string]$Line,
        [datetime]$LogDate
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    $match = [regex]::Match($Line, '^[A-Z0-9]+\t\d+\t(\d{2}:\d{2}:\d{2})\.\d{3}\t')
    if (-not $match.Success) {
        return $null
    }

    try {
        $timeText = $match.Groups[1].Value
        return [datetime]::ParseExact(
            ("{0} {1}" -f $LogDate.ToString("yyyy-MM-dd"), $timeText),
            "yyyy-MM-dd HH:mm:ss",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    }
    catch {
        return $null
    }
}

function Test-WatchedTerminalRunning {
    param([string]$ExecutablePath)

    $normalized = $ExecutablePath.ToLowerInvariant()
    $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -eq "terminal64.exe" -and
            -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
            $_.ExecutablePath.ToLowerInvariant() -eq $normalized
        }

    return (@($processes).Count -gt 0)
}

function Get-Mt5TesterStatus {
    param(
        [string]$LogPath,
        [string]$WatchedTerminalPath,
        [int]$StaleMinutes
    )

    $status = [ordered]@{
        generated_at_local   = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        log_path             = $LogPath
        state                = "idle"
        current_symbol       = ""
        run_stamp            = ""
        latest_progress_pct  = $null
        latest_progress_line = ""
        result_label         = ""
        result_duration      = ""
        latest_result_line   = ""
        last_activity_at_local = ""
        watched_terminal_running = $false
        stale_minutes          = $StaleMinutes
        signature            = ""
    }

    if (-not (Test-Path -LiteralPath $LogPath)) {
        $status.state = "log_missing"
        $status.signature = "log_missing"
        return [pscustomobject]$status
    }

    $logItem = Get-Item -LiteralPath $LogPath -ErrorAction Stop
    $logDate = $logItem.LastWriteTime.Date
    $status.watched_terminal_running = Test-WatchedTerminalRunning -ExecutablePath $WatchedTerminalPath

    $lines = @(Get-Content -LiteralPath $LogPath -Tail 250 -ErrorAction SilentlyContinue)
    if ($lines.Count -eq 0) {
        $status.state = "empty_log"
        $status.signature = "empty_log"
        return [pscustomobject]$status
    }

    $launchInfo = Get-LastMatchInfo -Lines $lines -Predicate {
        param($line)
        $line -match 'launched with .+\\strategy_tester\\([a-z0-9_]+)_strategy_tester_([0-9_]+)\.ini'
    }

    $launchIndex = -1
    if ($launchInfo) {
        $launchIndex = $launchInfo.index
        $launchMatch = [regex]::Match($launchInfo.line, 'launched with .+\\strategy_tester\\([a-z0-9_]+)_strategy_tester_([0-9_]+)\.ini')
        $status.current_symbol = $launchMatch.Groups[1].Value.ToUpperInvariant()
        $status.run_stamp = $launchMatch.Groups[2].Value
    }

    $progressInfo = $null
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($i -lt $launchIndex) { break }
        if ($lines[$i] -match 'AutoTesting\s+processing\s+([0-9]+)\s*%') {
            $progressInfo = [pscustomobject]@{
                index = $i
                line  = $lines[$i]
                pct   = [int]([regex]::Match($lines[$i], 'AutoTesting\s+processing\s+([0-9]+)\s*%').Groups[1].Value)
            }
            break
        }
    }

    $resultInfo = $null
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($i -lt $launchIndex) { break }
        if ($lines[$i] -match 'Tester\s+last test passed with result "([^"]+)" in ([0-9:.]+)') {
            $resultMatch = [regex]::Match($lines[$i], 'Tester\s+last test passed with result "([^"]+)" in ([0-9:.]+)')
            $resultInfo = [pscustomobject]@{
                index    = $i
                line     = $lines[$i]
                label    = $resultMatch.Groups[1].Value
                duration = $resultMatch.Groups[2].Value
            }
            break
        }
    }

    if ($progressInfo) {
        $status.latest_progress_pct = $progressInfo.pct
        $status.latest_progress_line = $progressInfo.line.Trim()
    }

    if ($resultInfo) {
        $status.result_label = $resultInfo.label
        $status.result_duration = $resultInfo.duration
        $status.latest_result_line = $resultInfo.line.Trim()
    }

    $lastActivityLine = $null
    if ($resultInfo) {
        $lastActivityLine = $resultInfo.line
    }
    elseif ($progressInfo) {
        $lastActivityLine = $progressInfo.line
    }
    elseif ($launchInfo) {
        $lastActivityLine = $launchInfo.line
    }

    $lastActivityAt = Get-LogLineTimestamp -Line $lastActivityLine -LogDate $logDate
    if ($lastActivityAt) {
        $status.last_activity_at_local = $lastActivityAt.ToString("yyyy-MM-dd HH:mm:ss")
    }

    if ($launchInfo -and $resultInfo -and $resultInfo.index -gt $launchIndex) {
        $status.state = "completed"
    }
    elseif ($launchInfo) {
        $status.state = "running"
        if (-not $status.watched_terminal_running) {
            $minutesSinceActivity = if ($lastActivityAt) {
                [math]::Round(((Get-Date) - $lastActivityAt).TotalMinutes, 1)
            } else {
                [double]::PositiveInfinity
            }

            if ($minutesSinceActivity -ge $StaleMinutes) {
                $status.state = "stale"
            }
        }
    }

    $status.signature = "{0}|{1}|{2}|{3}|{4}" -f `
        $status.state, `
        $status.current_symbol, `
        ($status.latest_progress_pct), `
        $status.result_label, `
        $status.run_stamp

    return [pscustomobject]$status
}

function Save-Mt5TesterStatus {
    param(
        [psobject]$Status,
        [string]$LatestJsonPath,
        [string]$LatestMdPath,
        [string]$EventRoot
    )

    $previous = $null
    if (Test-Path -LiteralPath $LatestJsonPath) {
        try {
            $previous = Get-Content -LiteralPath $LatestJsonPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        catch {
            $previous = $null
        }
    }

    $Status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $LatestJsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# MT5 Tester Status")
    $lines.Add("")
    $lines.Add(("- generated_at_local: {0}" -f $Status.generated_at_local))
    $lines.Add(("- state: {0}" -f $Status.state))
    $lines.Add(("- current_symbol: {0}" -f $Status.current_symbol))
    $lines.Add(("- run_stamp: {0}" -f $Status.run_stamp))
    if ($null -ne $Status.latest_progress_pct) {
        $lines.Add(("- latest_progress_pct: {0}" -f $Status.latest_progress_pct))
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Status.result_label)) {
        $lines.Add(("- result_label: {0}" -f $Status.result_label))
        $lines.Add(("- result_duration: {0}" -f $Status.result_duration))
    }
    $lines.Add(("- log_path: {0}" -f $Status.log_path))
    $lines.Add("")
    if (-not [string]::IsNullOrWhiteSpace([string]$Status.latest_progress_line)) {
        $lines.Add("## Latest Progress")
        $lines.Add("")
        $lines.Add('```text')
        $lines.Add([string]$Status.latest_progress_line)
        $lines.Add('```')
        $lines.Add("")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Status.latest_result_line)) {
        $lines.Add("## Latest Result")
        $lines.Add("")
        $lines.Add('```text')
        $lines.Add([string]$Status.latest_result_line)
        $lines.Add('```')
    }

    ($lines -join "`r`n") | Set-Content -LiteralPath $LatestMdPath -Encoding UTF8

    $previousSignature = if ($previous) { [string]$previous.signature } else { "" }
    if ($Status.signature -ne $previousSignature) {
        $stamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $eventJsonPath = Join-Path $EventRoot ("mt5_tester_status_{0}.json" -f $stamp)
        $eventMdPath = Join-Path $EventRoot ("mt5_tester_status_{0}.md" -f $stamp)
        $Status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $eventJsonPath -Encoding UTF8
        ($lines -join "`r`n") | Set-Content -LiteralPath $eventMdPath -Encoding UTF8
    }
}

while ($true) {
    $resolvedLogPath = Resolve-TerminalLogPath -PreferredPath $TerminalLogPath -LogDir $TerminalLogDir
    $status = Get-Mt5TesterStatus -LogPath $resolvedLogPath -WatchedTerminalPath $WatchedTerminalPath -StaleMinutes $StaleMinutes
    Save-Mt5TesterStatus -Status $status -LatestJsonPath $latestJsonPath -LatestMdPath $latestMdPath -EventRoot $eventRoot
    Start-Sleep -Seconds $PollSeconds
}
