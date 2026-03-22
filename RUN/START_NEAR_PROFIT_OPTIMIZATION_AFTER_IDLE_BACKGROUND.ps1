param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [bool]$UseDedicatedPortableLabLane = $true,
    [string]$DedicatedLabTerminalRoot = "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB",
    [string]$DedicatedLabSourceTerminalOrigin = "C:\Program Files\MetaTrader 5",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\logs",
    [string]$OpsEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [int]$NearProfitCount = 3,
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$CalibrationWindowDays = 5,
    [int]$TimeoutSec = 14400,
    [int]$IdleTimeoutSeconds = 21600,
    [int]$PulseSeconds = 30,
    [ValidateSet(0,1,2,3)]
    [int]$Optimization = 2,
    [ValidateSet(0,1,2,3,4,5,6,7)]
    [int]$OptimizationCriterion = 6,
    [switch]$SkipResearchRefresh,
    [ValidateSet("ConcurrentLab", "OfflineMax", "Light")]
    [string]$ResearchPerfProfile = "Light"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NearProfitWrapperProcesses {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*near_profit_optimization_after_idle_wrapper_*"
            }
    )
}

function Get-NearProfitRiskGuardProcesses {
    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "powershell.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.CommandLine) -and
                $_.CommandLine -like "*near_profit_mt5_risk_popup_guard_wrapper_*"
            }
    )
}

function Ensure-NearProfitRiskPopupGuard {
    param(
        [string]$ProjectRootPath,
        [string]$LabTerminalRoot,
        [string]$LogRootPath
    )

    $guardScript = Join-Path $ProjectRootPath "TOOLS\mt5_risk_popup_guard.ps1"
    if (-not (Test-Path -LiteralPath $guardScript)) {
        throw "Near-profit MT5 risk popup guard script not found: $guardScript"
    }

    $existingGuards = @(Get-NearProfitRiskGuardProcesses)
    if ($existingGuards.Count -gt 0) {
        return [pscustomobject]@{
            started = $false
            reason = "already_running"
            active_guard_count = $existingGuards.Count
            log_path = ""
        }
    }

    New-Item -ItemType Directory -Force -Path $LogRootPath | Out-Null

    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $logPath = Join-Path $LogRootPath ("near_profit_mt5_risk_popup_guard_{0}.log" -f $timestamp)
    $wrapperPath = Join-Path $env:TEMP ("near_profit_mt5_risk_popup_guard_wrapper_{0}.ps1" -f $timestamp)
    $statusPath = Join-Path $ProjectRootPath "RUN\near_profit_mt5_risk_guard_status.json"
    $eventLogPath = Join-Path $LogRootPath "near_profit_mt5_risk_guard.log"
    $pidPath = Join-Path $ProjectRootPath "RUN\near_profit_mt5_risk_guard.pid"

    $wrapperContent = @"
`$ErrorActionPreference = 'Stop'
Start-Transcript -Path '$logPath' -Force
try {
    & '$guardScript' -Root '$ProjectRootPath' -Mt5DataDir '$LabTerminalRoot' -PollMs 1200 -StatusPath '$statusPath' -EventLogPath '$eventLogPath' -PidPath '$pidPath'
}
finally {
    Stop-Transcript
}
"@

    Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

    $proc = Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
        -WorkingDirectory $ProjectRootPath `
        -PassThru

    try {
        $proc.PriorityClass = "AboveNormal"
    }
    catch {
    }

    return [pscustomobject]@{
        started = $true
        reason = "started"
        active_guard_count = 1
        log_path = $logPath
    }
}

$batchScript = Join-Path $ProjectRoot "RUN\RUN_NEAR_PROFIT_OPTIMIZATION_BATCH.ps1"
$statusScript = Join-Path $ProjectRoot "RUN\SYNC_NEAR_PROFIT_OPTIMIZATION_QUEUE_STATUS.ps1"
$preparePortableLabScript = Join-Path $ProjectRoot "RUN\PREPARE_NEAR_PROFIT_PORTABLE_LAB.ps1"
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "Near-profit optimization batch script not found: $batchScript"
}
if (-not (Test-Path -LiteralPath $statusScript)) {
    throw "Near-profit optimization status script not found: $statusScript"
}
if (-not (Test-Path -LiteralPath $ProfitTrackingPath)) {
    throw "Profit tracking file not found: $ProfitTrackingPath"
}

$portableTerminal = $false
$nearProfitRiskGuard = $null
if ($UseDedicatedPortableLabLane) {
    if (-not (Test-Path -LiteralPath $preparePortableLabScript)) {
        throw "Near-profit portable lab prepare script not found: $preparePortableLabScript"
    }

    $portableLab = & $preparePortableLabScript `
        -ProjectRoot $ProjectRoot `
        -SourceTerminalOrigin $DedicatedLabSourceTerminalOrigin `
        -LabTerminalRoot $DedicatedLabTerminalRoot

    if ($null -eq $portableLab) {
        throw "Near-profit portable lab preparation returned no result."
    }

    $Mt5Exe = [string]$portableLab.mt5_exe
    $TerminalDataDir = [string]$portableLab.terminal_data_dir
    $portableTerminal = [bool]$portableLab.portable_terminal
    $nearProfitRiskGuard = Ensure-NearProfitRiskPopupGuard -ProjectRootPath $ProjectRoot -LabTerminalRoot $TerminalDataDir -LogRootPath $LogRoot
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OpsEvidenceDir | Out-Null

$existingWrappers = @(Get-NearProfitWrapperProcesses)
if ($existingWrappers.Count -gt 0) {
    & $statusScript `
        -ProjectRoot $ProjectRoot `
        -OpsEvidenceDir $OpsEvidenceDir `
        -LogRoot $LogRoot `
        -ProfitTrackingPath $ProfitTrackingPath `
        -Mt5TesterStatusPath (Join-Path $OpsEvidenceDir "mt5_tester_status_latest.json") `
        -BatchReportPath (Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\optimization_lab\near_profit_optimization_latest.json") `
        -UseDedicatedPortableLabLane $UseDedicatedPortableLabLane `
        -DedicatedLabTerminalRoot $DedicatedLabTerminalRoot `
        -NearProfitCount $NearProfitCount `
        -CurrentNote "near_profit_wrapper_already_running" | Out-Null

    [pscustomobject]@{
        started = $false
        reason = "wrapper_already_running"
        active_wrapper_count = $existingWrappers.Count
        risk_guard_state = $(if ($null -ne $nearProfitRiskGuard) { [string]$nearProfitRiskGuard.reason } else { "" })
        risk_guard_log = $(if ($null -ne $nearProfitRiskGuard) { [string]$nearProfitRiskGuard.log_path } else { "" })
    }
    return
}

$profitTracking = Get-Content -LiteralPath $ProfitTrackingPath -Raw -Encoding UTF8 | ConvertFrom-Json
$nearProfit = @($profitTracking.near_profit | Sort-Object priority_rank, symbol_alias)
if ($nearProfit.Count -le 0) {
    throw "No near-profit symbols available in $ProfitTrackingPath"
}

$selectedSymbols = @(
    $nearProfit |
        Select-Object -First ([Math]::Max(1, $NearProfitCount)) |
        ForEach-Object { [string]$_.symbol_alias } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($selectedSymbols.Count -le 0) {
    throw "Near-profit list did not yield usable symbol aliases."
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot ("near_profit_optimization_after_idle_{0}.log" -f $timestamp)
$wrapperPath = Join-Path $env:TEMP ("near_profit_optimization_after_idle_wrapper_{0}.ps1" -f $timestamp)
$metaTesterExe = Join-Path (Split-Path -Parent $Mt5Exe) "metatester64.exe"
$batchReportPath = Join-Path $ProjectRoot "EVIDENCE\STRATEGY_TESTER\optimization_lab\near_profit_optimization_latest.json"
$mt5TesterStatusPath = Join-Path $OpsEvidenceDir "mt5_tester_status_latest.json"
$quotedSymbols = ($selectedSymbols | ForEach-Object { "'{0}'" -f $_ }) -join ", "
$awaitingIdleNote = if ($UseDedicatedPortableLabLane) { "awaiting_near_profit_lab_idle" } else { "awaiting_secondary_mt5_idle" }
$busyIdleNote = if ($UseDedicatedPortableLabLane) { "near_profit_lab_busy" } else { "secondary_mt5_busy" }
$skipIdleWaitLiteral = if ($UseDedicatedPortableLabLane) { '$true' } else { '$false' }
$portableTerminalLiteral = if ($portableTerminal) { '$true' } else { '$false' }
$skipResearchRefreshLiteral = if ($SkipResearchRefresh) { '$true' } else { '$false' }

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'

function Save-NearProfitQueueStatus {
    param(
        [string]`$State,
        [string]`$CurrentSymbol = '',
        [string[]]`$Completed = @(),
        [string[]]`$Pending = @(),
        [string]`$CurrentNote = ''
    )

    `$statusArgs = @{
        ProjectRoot = '$ProjectRoot'
        OpsEvidenceDir = '$OpsEvidenceDir'
        LogRoot = '$LogRoot'
        ProfitTrackingPath = '$ProfitTrackingPath'
        Mt5TesterStatusPath = '$mt5TesterStatusPath'
        BatchReportPath = '$batchReportPath'
        UseDedicatedPortableLabLane = $skipIdleWaitLiteral
        DedicatedLabTerminalRoot = '$DedicatedLabTerminalRoot'
        NearProfitCount = $NearProfitCount
        State = `$State
        CurrentSymbol = `$CurrentSymbol
        Completed = `$Completed
        Pending = `$Pending
        CurrentNote = `$CurrentNote
        LogPath = '$logPath'
        StartedAtLocal = `$wrapperStartedAtLocal
        RunTimeoutSec = $TimeoutSec
    }

    & '$statusScript' @statusArgs | Out-Null
}

function Wait-SecondaryMt5Idle {
    param(
        [string]`$TerminalExe,
        [string]`$MetaTesterExe,
        [int]`$TimeoutSeconds,
        [string[]]`$Completed,
        [string[]]`$Pending,
        [string]`$CurrentSymbol
    )

    `$terminalExeNorm = [System.IO.Path]::GetFullPath(`$TerminalExe).ToLowerInvariant()
    `$metaTesterExeNorm = [System.IO.Path]::GetFullPath(`$MetaTesterExe).ToLowerInvariant()
    `$deadline = (Get-Date).AddSeconds(`$TimeoutSeconds)

    while ((Get-Date) -lt `$deadline) {
        `$secondaryTerminal = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    `$_.Name -eq 'terminal64.exe' -and
                    -not [string]::IsNullOrWhiteSpace(`$_.ExecutablePath) -and
                    ([System.IO.Path]::GetFullPath(`$_.ExecutablePath).ToLowerInvariant() -eq `$terminalExeNorm)
                }
        )

        `$secondaryTester = @(
            Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                Where-Object {
                    `$_.Name -eq 'metatester64.exe' -and
                    -not [string]::IsNullOrWhiteSpace(`$_.ExecutablePath) -and
                    ([System.IO.Path]::GetFullPath(`$_.ExecutablePath).ToLowerInvariant() -eq `$metaTesterExeNorm)
                }
        )

        if (`$secondaryTerminal.Count -eq 0 -and `$secondaryTester.Count -eq 0) {
            return
        }

        Save-NearProfitQueueStatus -State 'waiting_for_idle' -CurrentSymbol `$CurrentSymbol -Completed `$Completed -Pending `$Pending -CurrentNote '$busyIdleNote'
        Start-Sleep -Seconds 15
    }

    throw "Secondary MT5 lane did not become idle within `$TimeoutSeconds seconds."
}

`$selectedSymbols = @($quotedSymbols)
`$completed = New-Object System.Collections.Generic.List[string]
`$wrapperStartedAtLocal = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

Start-Transcript -Path '$logPath' -Force
try {
    if (-not $skipIdleWaitLiteral) {
        Save-NearProfitQueueStatus -State 'waiting_for_idle' -Completed @() -Pending `$selectedSymbols -CurrentNote '$awaitingIdleNote'
        Wait-SecondaryMt5Idle -TerminalExe '$Mt5Exe' -MetaTesterExe '$metaTesterExe' -TimeoutSeconds $IdleTimeoutSeconds -Completed @() -Pending `$selectedSymbols -CurrentSymbol ''
    }
    else {
        Save-NearProfitQueueStatus -State 'running' -Completed @() -Pending `$selectedSymbols -CurrentNote 'portable_lab_lane_ready'
    }

    Save-NearProfitQueueStatus -State 'running' -Completed @() -Pending @() -CurrentNote 'near_profit_batch_started'

    `$batchArgs = @{
        ProjectRoot = '$ProjectRoot'
        Mt5Exe = '$Mt5Exe'
        TerminalDataDir = '$TerminalDataDir'
        PortableTerminal = $portableTerminalLiteral
        ProfitTrackingPath = '$ProfitTrackingPath'
        NearProfitCount = $NearProfitCount
        FromDate = '$FromDate'
        ToDate = '$ToDate'
        CalibrationWindowDays = $CalibrationWindowDays
        TimeoutSec = $TimeoutSec
        Optimization = $Optimization
        OptimizationCriterion = $OptimizationCriterion
        SkipResearchRefresh = $skipResearchRefreshLiteral
        ResearchPerfProfile = '$ResearchPerfProfile'
    }

    & '$batchScript' @batchArgs | Out-Host

    Save-NearProfitQueueStatus -State 'completed' -Completed `$selectedSymbols -Pending @() -CurrentNote ''
}
catch {
    Save-NearProfitQueueStatus -State 'failed' -Completed @() -Pending `$selectedSymbols -CurrentNote ([string]`$_.Exception.Message)
    throw
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -WorkingDirectory $ProjectRoot `
    -PassThru

try {
    $proc.PriorityClass = "AboveNormal"
}
catch {
}

Write-Host "Background near-profit optimization-after-idle started."
Write-Host "Log: $logPath"
if ($null -ne $nearProfitRiskGuard -and -not [string]::IsNullOrWhiteSpace([string]$nearProfitRiskGuard.log_path)) {
    Write-Host "Near-profit risk guard log: $($nearProfitRiskGuard.log_path)"
}
