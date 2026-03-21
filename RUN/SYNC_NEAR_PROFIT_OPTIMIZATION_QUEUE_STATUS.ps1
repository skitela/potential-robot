param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$OpsEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\logs",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [string]$Mt5TesterStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\mt5_tester_status_latest.json",
    [string]$BatchReportPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\near_profit_optimization_latest.json",
    [int]$NearProfitCount = 3,
    [string]$State,
    [string]$CurrentSymbol = "",
    [string[]]$Completed = @(),
    [string[]]$Pending = @(),
    [string]$CurrentNote = "",
    [string]$LogPath = "",
    [string]$StartedAtLocal = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Read-JsonFile {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Get-NearProfitSymbols {
    param(
        [string]$Path,
        [int]$TopCount
    )

    $profitTracking = Read-JsonFile -Path $Path
    if ($null -eq $profitTracking) {
        return @()
    }

    $nearProfit = @($profitTracking.near_profit | Sort-Object priority_rank, symbol_alias)
    if ($nearProfit.Count -le 0) {
        return @()
    }

    return @(
        $nearProfit |
            Select-Object -First ([Math]::Max(1, $TopCount)) |
            ForEach-Object { [string]$_.symbol_alias } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )
}

function Get-WrapperProcesses {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*near_profit_optimization_after_idle_wrapper_*"
            }
    )
}

function Parse-RunStamp {
    param([string]$RunStamp)

    if ([string]::IsNullOrWhiteSpace($RunStamp)) {
        return $null
    }

    try {
        return [datetime]::ParseExact($RunStamp, "yyyyMMdd_HHmmss", [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return $null
    }
}

function Resolve-LogItem {
    param(
        [string]$Root,
        [string]$ExplicitPath
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitPath) -and (Test-Path -LiteralPath $ExplicitPath)) {
        return Get-Item -LiteralPath $ExplicitPath
    }

    return Get-ChildItem -Path $Root -Filter "near_profit_optimization_after_idle_*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-LatestOptimizationRunSummaryItem {
    param([string]$BatchReportPath)

    if ([string]::IsNullOrWhiteSpace($BatchReportPath)) {
        return $null
    }

    $dir = Split-Path -Parent $BatchReportPath
    if ([string]::IsNullOrWhiteSpace($dir) -or -not (Test-Path -LiteralPath $dir)) {
        return $null
    }

    $batchReportName = [System.IO.Path]::GetFileName($BatchReportPath)
    return Get-ChildItem -Path $dir -Filter "*_summary.json" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne $batchReportName } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Write-StatusArtifacts {
    param(
        [hashtable]$Status,
        [string]$JsonPath,
        [string]$MdPath
    )

    $Status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $JsonPath -Encoding UTF8

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Near Profit Optimization Queue")
    $lines.Add("")
    $lines.Add(("- generated_at_local: {0}" -f $Status.generated_at_local))
    $lines.Add(("- state: {0}" -f $Status.state))
    $lines.Add(("- current_symbol: {0}" -f $Status.current_symbol))
    $lines.Add(("- wrapper_running: {0}" -f $Status.wrapper_running))
    $lines.Add(("- active_wrapper_count: {0}" -f $Status.active_wrapper_count))
    $lines.Add(("- log_path: {0}" -f $Status.log_path))
    $lines.Add(("- batch_report_path: {0}" -f $Status.batch_report_path))
    if (-not [string]::IsNullOrWhiteSpace([string]$Status.current_note)) {
        $lines.Add(("- current_note: {0}" -f $Status.current_note))
    }
    $lines.Add("")
    $lines.Add("## Selected")
    $lines.Add("")
    if (@($Status.selected_symbols).Count -gt 0) {
        foreach ($symbol in @($Status.selected_symbols)) {
            $lines.Add(("- {0}" -f $symbol))
        }
    }
    else {
        $lines.Add("- none")
    }
    $lines.Add("")
    $lines.Add("## Completed")
    $lines.Add("")
    if (@($Status.completed).Count -gt 0) {
        foreach ($symbol in @($Status.completed)) {
            $lines.Add(("- {0}" -f $symbol))
        }
    }
    else {
        $lines.Add("- none")
    }
    $lines.Add("")
    $lines.Add("## Pending")
    $lines.Add("")
    if (@($Status.pending).Count -gt 0) {
        foreach ($symbol in @($Status.pending)) {
            $lines.Add(("- {0}" -f $symbol))
        }
    }
    else {
        $lines.Add("- none")
    }

    ($lines -join "`r`n") | Set-Content -LiteralPath $MdPath -Encoding UTF8
}

New-Item -ItemType Directory -Force -Path $OpsEvidenceDir | Out-Null

$latestJson = Join-Path $OpsEvidenceDir "near_profit_optimization_queue_latest.json"
$latestMd = Join-Path $OpsEvidenceDir "near_profit_optimization_queue_latest.md"

$selectedSymbols = @(Get-NearProfitSymbols -Path $ProfitTrackingPath -TopCount $NearProfitCount)
$wrapperProcesses = @(Get-WrapperProcesses)
$wrapperRunning = ($wrapperProcesses.Count -gt 0)
$logItem = Resolve-LogItem -Root $LogRoot -ExplicitPath $LogPath
$mt5TesterStatus = Read-JsonFile -Path $Mt5TesterStatusPath
$batchReport = Read-JsonFile -Path $BatchReportPath
$latestOptimizationSummaryItem = Resolve-LatestOptimizationRunSummaryItem -BatchReportPath $BatchReportPath
$latestOptimizationSummary = if ($null -ne $latestOptimizationSummaryItem) { Read-JsonFile -Path $latestOptimizationSummaryItem.FullName } else { $null }

$resolvedState = $State
$resolvedCurrentSymbol = $CurrentSymbol
$resolvedCompleted = @($Completed)
$resolvedPending = @($Pending)
$resolvedNote = $CurrentNote
$resolvedStartedAt = $StartedAtLocal

if ([string]::IsNullOrWhiteSpace($resolvedStartedAt) -and $null -ne $logItem) {
    $resolvedStartedAt = $logItem.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}

if ([string]::IsNullOrWhiteSpace($resolvedState)) {
    $resolvedState = "idle"
    $resolvedCompleted = @()
    $resolvedPending = @($selectedSymbols)

    if ($wrapperRunning) {
        $resolvedState = "waiting_for_idle"
        $logStart = if ($null -ne $logItem) { $logItem.LastWriteTime } else { $null }
        $summaryFresh = (
            $null -ne $latestOptimizationSummaryItem -and
            (($null -eq $logStart) -or $latestOptimizationSummaryItem.LastWriteTime -ge $logStart.AddSeconds(-15))
        )
        if ($summaryFresh -and $null -ne $latestOptimizationSummary) {
            $resolvedState = "running"
            $resolvedCurrentSymbol = [string]$latestOptimizationSummary.symbol_alias
            if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "optimization_lane_active_from_summary"
            }
        }
        elseif ($null -ne $mt5TesterStatus -and [string]$mt5TesterStatus.state -eq "running") {
            $runStampDate = Parse-RunStamp -RunStamp ([string]$mt5TesterStatus.run_stamp)
            $resolvedCurrentSymbol = [string]$mt5TesterStatus.current_symbol

            if ($null -ne $runStampDate -and $null -ne $logStart -and $runStampDate -ge $logStart.AddMinutes(-1)) {
                $resolvedState = "running"
                if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                    $resolvedNote = "optimization_lane_active"
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($resolvedNote)) {
                $resolvedNote = "waiting_for_secondary_mt5_idle"
            }
        }
        elseif ([string]::IsNullOrWhiteSpace($resolvedNote)) {
            $resolvedNote = "wrapper_running_without_active_mt5"
        }
    }
    elseif ($null -ne $batchReport) {
        $resolvedState = "completed"
        $resolvedCompleted = @($batchReport.symbols)
        $resolvedPending = @()
        if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
            $resolvedNote = "batch_report_available"
        }
    }
    elseif ($null -ne $logItem) {
        $resolvedState = "stale"
        if ([string]::IsNullOrWhiteSpace($resolvedNote)) {
            $resolvedNote = "log_present_without_live_wrapper"
        }
    }
}

if (@($resolvedPending).Count -eq 0 -and @($selectedSymbols).Count -gt 0 -and $resolvedState -notin @("completed", "failed")) {
    $resolvedPending = @($selectedSymbols | Where-Object { @($resolvedCompleted) -notcontains $_ })
}

$status = [ordered]@{
    generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    state = $resolvedState
    current_symbol = $resolvedCurrentSymbol
    selected_symbols = @($selectedSymbols)
    completed = @($resolvedCompleted)
    pending = @($resolvedPending)
    near_profit_count = $NearProfitCount
    wrapper_running = $wrapperRunning
    active_wrapper_count = $wrapperProcesses.Count
    started_at_local = $resolvedStartedAt
    log_path = if ($null -ne $logItem) { $logItem.FullName } else { $LogPath }
    batch_report_path = $BatchReportPath
    batch_report_present = ($null -ne $batchReport)
    mt5_status_path = $Mt5TesterStatusPath
    current_note = $resolvedNote
}

Write-StatusArtifacts -Status $status -JsonPath $latestJson -MdPath $latestMd
$status
