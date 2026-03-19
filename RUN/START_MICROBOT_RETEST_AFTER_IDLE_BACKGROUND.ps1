param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\weakest_lab\logs",
    [Parameter(Mandatory = $true)]
    [string]$SymbolAlias,
    [string]$WorkerName = "",
    [string]$EvidenceSubdir = "",
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 7200,
    [int]$IdleTimeoutSeconds = 14400
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testerScript = Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1"
if (-not (Test-Path -LiteralPath $testerScript)) {
    throw "Tester script not found: $testerScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null

$symbolToken = (($SymbolAlias -replace '[^A-Za-z0-9]+','_').Trim('_'))
if ([string]::IsNullOrWhiteSpace($symbolToken)) {
    $symbolToken = "MICROBOT"
}

if ([string]::IsNullOrWhiteSpace($WorkerName)) {
    $WorkerName = ("{0}_fix_queued" -f $symbolToken.ToLowerInvariant())
}

if ([string]::IsNullOrWhiteSpace($EvidenceSubdir)) {
    $EvidenceSubdir = ("weakest_lab\{0}_queued" -f $symbolToken.ToLowerInvariant())
}

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot ("microbot_retest_after_idle_{0}_{1}.log" -f $symbolToken.ToLowerInvariant(), $timestamp)
$wrapperPath = Join-Path $env:TEMP ("microbot_retest_after_idle_wrapper_{0}_{1}.ps1" -f $symbolToken.ToLowerInvariant(), $timestamp)
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

    & '$testerScript' `
        -ProjectRoot '$ProjectRoot' `
        -Mt5Exe '$Mt5Exe' `
        -TerminalDataDir '$TerminalDataDir' `
        -SymbolAlias '$SymbolAlias' `
        -WorkerName '$WorkerName' `
        -EvidenceSubdir '$EvidenceSubdir' `
        -FromDate '$FromDate' `
        -ToDate '$ToDate' `
        -TimeoutSec $TimeoutSec
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

Write-Host "Background microbot retest-after-idle started."
Write-Host "Log: $logPath"
