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
    [int]$IdleTimeoutSeconds = 14400,
    [int]$PulseSeconds = 30
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
        [int]`$PulseSeconds
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
            -WindowStyle Hidden `
            -RedirectStandardOutput `$stdoutPath `
            -RedirectStandardError `$stderrPath `
            -PassThru

        while (-not `$proc.HasExited) {
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

Start-Transcript -Path '$logPath' -Force
try {
    Wait-SecondaryMt5Idle -TerminalExe '$Mt5Exe' -MetaTesterExe '$metaTesterExe' -TimeoutSeconds $IdleTimeoutSeconds

    `$testerOutcome = Invoke-TesterScriptWithEnvelope `
        -TesterScript '$testerScript' `
        -ProjectRootPath '$ProjectRoot' `
        -Mt5ExePath '$Mt5Exe' `
        -TerminalDataDirPath '$TerminalDataDir' `
        -SymbolAlias '$SymbolAlias' `
        -WorkerName '$WorkerName' `
        -EvidenceSubdir '$EvidenceSubdir' `
        -FromDate '$FromDate' `
        -ToDate '$ToDate' `
        -TimeoutSec $TimeoutSec `
        -PulseSeconds $PulseSeconds

    Write-Host ("tester_outcome={0}" -f [string]`$testerOutcome.state)
}
finally {
    Stop-Transcript
}
"@

Set-Content -LiteralPath $wrapperPath -Value $wrapperContent -Encoding UTF8

$proc = Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $wrapperPath) `
    -WorkingDirectory $ProjectRoot `
    -WindowStyle Hidden `
    -PassThru

try {
    $proc.PriorityClass = "AboveNormal"
}
catch {
}

Write-Host "Background microbot retest-after-idle started."
Write-Host "Log: $logPath"
