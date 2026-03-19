param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5Exe = "C:\Program Files\MetaTrader 5\terminal64.exe",
    [string]$TerminalDataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075",
    [string]$LogRoot = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\STRATEGY_TESTER\weakest_lab\logs",
    [string]$OpsEvidenceDir = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS",
    [string[]]$SymbolAliases = @("GBPJPY", "EURAUD", "NZDUSD"),
    [string]$FromDate = "2026.03.01",
    [string]$ToDate = "2026.03.16",
    [int]$TimeoutSec = 7200,
    [int]$IdleTimeoutSeconds = 21600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testerScript = Join-Path $ProjectRoot "TOOLS\RUN_MICROBOT_STRATEGY_TESTER.ps1"
if (-not (Test-Path -LiteralPath $testerScript)) {
    throw "Tester script not found: $testerScript"
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
New-Item -ItemType Directory -Force -Path $OpsEvidenceDir | Out-Null

$queueToken = "mt5_retest_queue"
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$logPath = Join-Path $LogRoot ("{0}_{1}.log" -f $queueToken, $timestamp)
$wrapperPath = Join-Path $env:TEMP ("{0}_wrapper_{1}.ps1" -f $queueToken, $timestamp)
$metaTesterExe = Join-Path (Split-Path -Parent $Mt5Exe) "metatester64.exe"
$statusJsonLatest = Join-Path $OpsEvidenceDir "mt5_retest_queue_latest.json"
$statusMdLatest = Join-Path $OpsEvidenceDir "mt5_retest_queue_latest.md"
$statusJsonStamped = Join-Path $OpsEvidenceDir ("mt5_retest_queue_{0}.json" -f $timestamp)
$statusMdStamped = Join-Path $OpsEvidenceDir ("mt5_retest_queue_{0}.md" -f $timestamp)

$quotedSymbols = ($SymbolAliases | ForEach-Object { "'{0}'" -f $_ }) -join ", "

$wrapperContent = @"
`$ErrorActionPreference = 'Stop'

function Save-QueueStatus {
    param(
        [string]`$State,
        [string]`$CurrentSymbol,
        [object[]]`$Completed,
        [string[]]`$Pending
    )

    `$status = [pscustomobject]@{
        generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        state = `$State
        current_symbol = `$CurrentSymbol
        completed = @(`$Completed)
        pending = @(`$Pending)
        log_path = '$logPath'
    }

    `$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath '$statusJsonLatest' -Encoding UTF8
    `$status | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath '$statusJsonStamped' -Encoding UTF8

    `$lines = New-Object System.Collections.Generic.List[string]
    `$lines.Add('# MT5 Retest Queue Latest')
    `$lines.Add('')
    `$lines.Add(('- generated_at_local: {0}' -f `$status.generated_at_local))
    `$lines.Add(('- state: {0}' -f `$status.state))
    `$lines.Add(('- current_symbol: {0}' -f `$status.current_symbol))
    `$lines.Add(('- log_path: {0}' -f `$status.log_path))
    `$lines.Add('')
    `$lines.Add('## Completed')
    `$lines.Add('')
    if (`$status.completed.Count -gt 0) {
        foreach (`$item in `$status.completed) {
            `$lines.Add(('- {0}' -f `$item))
        }
    }
    else {
        `$lines.Add('- none')
    }
    `$lines.Add('')
    `$lines.Add('## Pending')
    `$lines.Add('')
    if (`$status.pending.Count -gt 0) {
        foreach (`$item in `$status.pending) {
            `$lines.Add(('- {0}' -f `$item))
        }
    }
    else {
        `$lines.Add('- none')
    }

    (`$lines -join "`r`n") | Set-Content -LiteralPath '$statusMdLatest' -Encoding UTF8
    (`$lines -join "`r`n") | Set-Content -LiteralPath '$statusMdStamped' -Encoding UTF8
}

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

function Get-Token {
    param([string]`$Value)

    `$token = (`$Value -replace '[^A-Za-z0-9]+','_').Trim('_').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace(`$token)) {
        return 'microbot'
    }
    return `$token
}

`$symbols = @($quotedSymbols)
`$completed = New-Object System.Collections.Generic.List[string]

Start-Transcript -Path '$logPath' -Force
try {
    Save-QueueStatus -State 'waiting_for_idle' -CurrentSymbol '' -Completed @(`$completed) -Pending `$symbols

    foreach (`$symbolAlias in `$symbols) {
        `$pending = @(`$symbols | Where-Object { `$completed -notcontains `$_ })
        Save-QueueStatus -State 'waiting_for_idle' -CurrentSymbol `$symbolAlias -Completed @(`$completed) -Pending `$pending
        Wait-SecondaryMt5Idle -TerminalExe '$Mt5Exe' -MetaTesterExe '$metaTesterExe' -TimeoutSeconds $IdleTimeoutSeconds

        `$token = Get-Token -Value `$symbolAlias
        `$workerName = ("{0}_fix_queue" -f `$token)
        `$evidenceSubdir = ("weakest_lab\{0}_queue" -f `$token)

        `$pending = @(`$symbols | Where-Object { `$completed -notcontains `$_ -and `$_ -ne `$symbolAlias })
        Save-QueueStatus -State 'running' -CurrentSymbol `$symbolAlias -Completed @(`$completed) -Pending `$pending

        & '$testerScript' `
            -ProjectRoot '$ProjectRoot' `
            -Mt5Exe '$Mt5Exe' `
            -TerminalDataDir '$TerminalDataDir' `
            -SymbolAlias `$symbolAlias `
            -WorkerName `$workerName `
            -EvidenceSubdir `$evidenceSubdir `
            -FromDate '$FromDate' `
            -ToDate '$ToDate' `
            -TimeoutSec $TimeoutSec

        `$completed.Add(`$symbolAlias)
        `$pending = @(`$symbols | Where-Object { `$completed -notcontains `$_ })
        Save-QueueStatus -State 'waiting_for_idle' -CurrentSymbol '' -Completed @(`$completed) -Pending `$pending
    }

    Save-QueueStatus -State 'completed' -CurrentSymbol '' -Completed @(`$completed) -Pending @()
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

Write-Host "Background microbot retest queue-after-idle started."
Write-Host "Log: $logPath"
