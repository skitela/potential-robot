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
    [int]$IdleTimeoutSeconds = 21600,
    [int]$PulseSeconds = 30
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
        [string[]]`$Pending,
        [string]`$CurrentNote = ""
    )

    `$status = [pscustomobject]@{
        generated_at_local = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        state = `$State
        current_symbol = `$CurrentSymbol
        completed = @(`$Completed)
        pending = @(`$Pending)
        log_path = '$logPath'
        current_note = `$CurrentNote
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
    if (-not [string]::IsNullOrWhiteSpace(`$status.current_note)) {
        `$lines.Add(('- current_note: {0}' -f `$status.current_note))
    }
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
        [int]`$TimeoutSeconds,
        [string]`$CurrentSymbol,
        [object[]]`$Completed,
        [string[]]`$Pending
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

        Save-QueueStatus -State 'waiting_for_idle' -CurrentSymbol `$CurrentSymbol -Completed @(`$Completed) -Pending `$Pending -CurrentNote 'secondary_mt5_busy'
        Start-Sleep -Seconds 15
    }

    throw "Secondary MT5 lane did not become idle within `$TimeoutSeconds seconds."
}

function Invoke-TesterScriptWithEnvelope {
    param(
        [string]`$TesterScript,
        [string]`$ProjectRootPath,
        [string]`$Mt5ExePath,
        [string]`$TerminalDataDirPath,
        [string]`$SymbolAlias,
        [string]`$WorkerName,
        [string]`$EvidenceSubdir,
        [string]`$FromDate,
        [string]`$ToDate,
        [int]`$TimeoutSec,
        [int]`$PulseSeconds,
        [string]`$CurrentSymbol,
        [object[]]`$Completed,
        [string[]]`$Pending
    )

    `$runnerToken = [guid]::NewGuid().ToString('N')
    `$runnerPath = Join-Path `$env:TEMP ("microbot_tester_runner_" + `$runnerToken + ".ps1")
    `$stdoutPath = Join-Path `$env:TEMP ("microbot_tester_runner_" + `$runnerToken + ".stdout.log")
    `$stderrPath = Join-Path `$env:TEMP ("microbot_tester_runner_" + `$runnerToken + ".stderr.log")

    `$runnerLines = @(
        "`$ErrorActionPreference = 'Stop'",
        "& '" + `$TesterScript + "'",
        "    -ProjectRoot '" + `$ProjectRootPath + "'",
        "    -Mt5Exe '" + `$Mt5ExePath + "'",
        "    -TerminalDataDir '" + `$TerminalDataDirPath + "'",
        "    -SymbolAlias '" + `$SymbolAlias + "'",
        "    -WorkerName '" + `$WorkerName + "'",
        "    -EvidenceSubdir '" + `$EvidenceSubdir + "'",
        "    -FromDate '" + `$FromDate + "'",
        "    -ToDate '" + `$ToDate + "'",
        "    -TimeoutSec " + [string]`$TimeoutSec
    )
    (`$runnerLines -join "`r`n") | Set-Content -LiteralPath `$runnerPath -Encoding UTF8

    `$proc = `$null
    `$deadline = (Get-Date).AddSeconds([Math]::Max(`$TimeoutSec + 900, 1800))
    try {
        `$proc = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', `$runnerPath) `
            -WorkingDirectory `$ProjectRootPath `
            -RedirectStandardOutput `$stdoutPath `
            -RedirectStandardError `$stderrPath `
            -PassThru

        while (-not `$proc.HasExited) {
            Save-QueueStatus -State 'running' -CurrentSymbol `$CurrentSymbol -Completed @(`$Completed) -Pending @(`$Pending) -CurrentNote ("tester_process_id=" + [string]`$proc.Id)

            if ((Get-Date) -ge `$deadline) {
                Stop-Process -Id `$proc.Id -Force -ErrorAction SilentlyContinue
                Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
                    Where-Object {
                        (`$_.Name -eq 'terminal64.exe' -or `$_.Name -eq 'metatester64.exe') -and
                        -not [string]::IsNullOrWhiteSpace(`$_.ExecutablePath) -and
                        ([System.IO.Path]::GetFullPath(`$_.ExecutablePath).ToLowerInvariant() -in @(
                            [System.IO.Path]::GetFullPath(`$Mt5ExePath).ToLowerInvariant(),
                            [System.IO.Path]::GetFullPath((Join-Path (Split-Path -Parent `$Mt5ExePath) 'metatester64.exe')).ToLowerInvariant()
                        ))
                    } |
                    ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }

                return [pscustomobject]@{
                    state = 'envelope_timeout'
                    output = ''
                }
            }

            Start-Sleep -Seconds `$PulseSeconds
            try { `$proc.Refresh() } catch {}
        }

        `$stdout = if (Test-Path -LiteralPath `$stdoutPath) { (Get-Content -LiteralPath `$stdoutPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
        `$stderr = if (Test-Path -LiteralPath `$stderrPath) { (Get-Content -LiteralPath `$stderrPath -Raw -ErrorAction SilentlyContinue).Trim() } else { '' }
        `$combinedOutput = (@(`$stdout, `$stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace(`$_) }) -join "`r`n"

        `$processState = 'Failed'
        if (`$proc.ExitCode -eq 0) {
            `$processState = 'Completed'
        }

        return [pscustomobject]@{
            state = `$processState
            output = `$combinedOutput
        }
    }
    finally {
        foreach (`$path in @(`$runnerPath, `$stdoutPath, `$stderrPath)) {
            if (Test-Path -LiteralPath `$path) {
                Remove-Item -LiteralPath `$path -Force -ErrorAction SilentlyContinue
            }
        }
    }
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
        Save-QueueStatus -State 'waiting_for_idle' -CurrentSymbol `$symbolAlias -Completed @(`$completed) -Pending `$pending -CurrentNote 'awaiting_secondary_mt5_idle'
        Wait-SecondaryMt5Idle -TerminalExe '$Mt5Exe' -MetaTesterExe '$metaTesterExe' -TimeoutSeconds $IdleTimeoutSeconds -CurrentSymbol `$symbolAlias -Completed @(`$completed) -Pending `$pending

        `$token = Get-Token -Value `$symbolAlias
        `$workerName = ("{0}_fix_queue" -f `$token)
        `$evidenceSubdir = ("weakest_lab\{0}_queue" -f `$token)

        `$pending = @(`$symbols | Where-Object { `$completed -notcontains `$_ -and `$_ -ne `$symbolAlias })
        Save-QueueStatus -State 'running' -CurrentSymbol `$symbolAlias -Completed @(`$completed) -Pending `$pending -CurrentNote 'tester_job_started'

        `$testerOutcome = Invoke-TesterScriptWithEnvelope `
            -TesterScript '$testerScript' `
            -ProjectRootPath '$ProjectRoot' `
            -Mt5ExePath '$Mt5Exe' `
            -TerminalDataDirPath '$TerminalDataDir' `
            -SymbolAlias `$symbolAlias `
            -WorkerName `$workerName `
            -EvidenceSubdir `$evidenceSubdir `
            -FromDate '$FromDate' `
            -ToDate '$ToDate' `
            -TimeoutSec $TimeoutSec `
            -PulseSeconds $PulseSeconds `
            -CurrentSymbol `$symbolAlias `
            -Completed @(`$completed) `
            -Pending `$pending

        `$completed.Add(`$symbolAlias)
        `$pending = @(`$symbols | Where-Object { `$completed -notcontains `$_ })
        Save-QueueStatus -State 'waiting_for_idle' -CurrentSymbol '' -Completed @(`$completed) -Pending `$pending -CurrentNote ("last_result=" + [string]`$testerOutcome.state)
    }

    Save-QueueStatus -State 'completed' -CurrentSymbol '' -Completed @(`$completed) -Pending @() -CurrentNote ''
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
