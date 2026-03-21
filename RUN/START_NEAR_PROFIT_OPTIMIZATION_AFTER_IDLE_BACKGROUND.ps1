param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\optimization_lab\logs",
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
if (-not (Test-Path -LiteralPath $batchScript)) {
    throw "Near-profit optimization batch script not found: $batchScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot ("near_profit_optimization_after_idle_{0}.log" -f $timestamp)
$wrapperPath = Join-Path $env:TEMP ("near_profit_optimization_after_idle_wrapper_{0}.ps1" -f $timestamp)
$metaTesterExe = Join-Path (Split-Path -Parent $Mt5Exe) "metatester64.exe"

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'

function Wait-SecondaryMt5Idle {
    param(
        [string]`$TerminalExe,
        [string]`$MetaTesterExe,
        [int]`$TimeoutSeconds
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

        Start-Sleep -Seconds 15
    }

    throw "Secondary MT5 lane did not become idle within `$TimeoutSeconds seconds."
}

Start-Transcript -Path '$logPath' -Force
try {
    Wait-SecondaryMt5Idle -TerminalExe '$Mt5Exe' -MetaTesterExe '$metaTesterExe' -TimeoutSeconds $IdleTimeoutSeconds

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
