param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\logs",
    [string]$OpsEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string]$ProfitTrackingPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\profit_tracking_latest.json",
    [int]$NearProfitCount = 3,
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 7200,
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

$batchScript = Join-Path $ProjectRoot "RUN\RUN_NEAR_PROFIT_OPTIMIZATION_BATCH.ps1"
$statusScript = Join-Path $ProjectRoot "RUN\SYNC_NEAR_PROFIT_OPTIMIZATION_QUEUE_STATUS.ps1"
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "Near-profit optimization batch script not found: $batchScript"
}
if (-not (Test-Path -LiteralPath $statusScript)) {
    throw "Near-profit optimization status script not found: $statusScript"
}
if (-not (Test-Path -LiteralPath $ProfitTrackingPath)) {
    throw "Profit tracking file not found: $ProfitTrackingPath"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OpsEvidenceDir | Out-Null

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

    & '$statusScript' `
        -ProjectRoot '$ProjectRoot' `
        -OpsEvidenceDir '$OpsEvidenceDir' `
        -LogRoot '$LogRoot' `
        -ProfitTrackingPath '$ProfitTrackingPath' `
        -Mt5TesterStatusPath '$mt5TesterStatusPath' `
        -BatchReportPath '$batchReportPath' `
        -NearProfitCount $NearProfitCount `
        -State `$State `
        -CurrentSymbol `$CurrentSymbol `
        -Completed `$Completed `
        -Pending `$Pending `
        -CurrentNote `$CurrentNote `
        -LogPath '$logPath' | Out-Null
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

        Save-NearProfitQueueStatus -State 'waiting_for_idle' -CurrentSymbol `$CurrentSymbol -Completed `$Completed -Pending `$Pending -CurrentNote 'secondary_mt5_busy'
        Start-Sleep -Seconds 15
    }

    throw "Secondary MT5 lane did not become idle within `$TimeoutSeconds seconds."
}

`$selectedSymbols = @($quotedSymbols)
`$completed = New-Object System.Collections.Generic.List[string]

Start-Transcript -Path '$logPath' -Force
try {
    Save-NearProfitQueueStatus -State 'waiting_for_idle' -Completed @() -Pending `$selectedSymbols -CurrentNote 'awaiting_secondary_mt5_idle'
    Wait-SecondaryMt5Idle -TerminalExe '$Mt5Exe' -MetaTesterExe '$metaTesterExe' -TimeoutSeconds $IdleTimeoutSeconds -Completed @() -Pending `$selectedSymbols -CurrentSymbol ''

    Save-NearProfitQueueStatus -State 'running' -Completed @() -Pending @() -CurrentNote 'near_profit_batch_started'

    & '$batchScript' `
        -ProjectRoot '$ProjectRoot' `
        -Mt5Exe '$Mt5Exe' `
        -TerminalDataDir '$TerminalDataDir' `
        -ProfitTrackingPath '$ProfitTrackingPath' `
        -NearProfitCount $NearProfitCount `
        -FromDate '$FromDate' `
        -ToDate '$ToDate' `
        -TimeoutSec $TimeoutSec `
        -Optimization $Optimization `
        -OptimizationCriterion $OptimizationCriterion `
        -SkipResearchRefresh:$([bool]$SkipResearchRefresh) `
        -ResearchPerfProfile '$ResearchPerfProfile' | Out-Host

    Save-NearProfitQueueStatus -State 'completed' -Completed `$selectedSymbols -Pending @() -CurrentNote ''
}
catch {
    Save-NearProfitQueueStatus -State 'failed' -Completed @() -Pending `$selectedSymbols -CurrentNote ([string]$_.Exception.Message)
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
