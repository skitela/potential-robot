param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalOrigin = "C:\Program Files\MetaTrader 5",
    [string]$TerminalDataDir = "",
    [string]$PilotCsvPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\QDM_PILOT\MB_EURUSD_DUKA_M1_PILOT.csv",
    [string]$CommonRelativeCsvPath = "MAKRO_I_MIKRO_BOT\\qdm_import\\MB_EURUSD_DUKA_M1_PILOT.csv",
    [string]$ScriptName = "QdmImportCustomSymbolBars",
    [string]$CustomSymbol = "EURUSD_QDM_M1",
    [string]$CustomGroup = "Research\\QDM\\Forex",
    [string]$BrokerTemplateSymbol = "EURUSD.pro",
    [bool]$SelectSymbolAfterImport = $true,
    [bool]$RunImport = $true,
    [int]$TimeoutSec = 300,
    [bool]$UseDedicatedPortableLabLane = $true,
    [string]$DedicatedLabTerminalRoot = "C:\TRADING_TOOLS\MT5_QDM_CUSTOM_LAB",
    [string]$DedicatedLabSourceTerminalOrigin = "C:\Program Files\MetaTrader 5",
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\QDM_PILOT\qdm_import_custom_symbol_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-TerminalDataDirByOrigin {
    param([string]$OriginPath)

    $base = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path -LiteralPath $base)) {
        throw "MetaQuotes terminal root not found: $base"
    }

    $normalizedOrigin = [System.IO.Path]::GetFullPath($OriginPath).TrimEnd('\').ToLowerInvariant()
    $matches = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $originFile = Join-Path $_.FullName "origin.txt"
            if (-not (Test-Path -LiteralPath $originFile)) { return $false }
            $content = (Get-Content -LiteralPath $originFile -Raw -Encoding UTF8).Trim()
            if ([string]::IsNullOrWhiteSpace($content)) { return $false }
            try {
                return ([System.IO.Path]::GetFullPath($content).TrimEnd('\').ToLowerInvariant() -eq $normalizedOrigin)
            }
            catch {
                return $false
            }
        }

    $match = $matches | Select-Object -First 1
    if (-not $match) {
        throw "No terminal data dir found for origin: $OriginPath"
    }

    return $match.FullName
}

function Get-RunningTerminalProcessesForOrigin {
    param([string]$TerminalExePath)

    $normalizedTerminalExe = [System.IO.Path]::GetFullPath($TerminalExePath).ToLowerInvariant()

    return @(
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -eq "terminal64.exe" -and
                -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) -and
                ([System.IO.Path]::GetFullPath($_.ExecutablePath).ToLowerInvariant() -eq $normalizedTerminalExe)
            }
    )
}

function Read-TextBestEffort {
    param([string]$Path)

    foreach ($encoding in @("Unicode", "UTF8", "Default")) {
        try {
            $content = Get-Content -LiteralPath $Path -Raw -Encoding $encoding -ErrorAction Stop
            if ($null -ne $content) {
                return [string]$content
            }
        }
        catch {
        }
    }

    return ""
}

function Get-LatestRegexMatchValue {
    param(
        [string]$Text,
        [string]$Pattern
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($Pattern)) {
        return $null
    }

    $matches = [regex]::Matches($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Multiline)
    if ($null -eq $matches -or $matches.Count -le 0) {
        return $null
    }

    return [string]$matches[$matches.Count - 1].Value
}

function Write-PresetFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [hashtable]$Values
    )

    $lines = foreach ($key in $Values.Keys) {
        "{0}={1}" -f $key, $Values[$key]
    }
    Set-Content -LiteralPath $Path -Value $lines -Encoding Default
}

if (-not (Test-Path -LiteralPath $PilotCsvPath)) {
    throw "Pilot CSV not found: $PilotCsvPath"
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$portableTerminal = $false
if ($UseDedicatedPortableLabLane) {
    $preparePortableLabScript = Join-Path $projectPath "RUN\PREPARE_QDM_CUSTOM_PORTABLE_LAB.ps1"
    if (-not (Test-Path -LiteralPath $preparePortableLabScript)) {
        throw "Required script not found: $preparePortableLabScript"
    }

    $portableLab = & $preparePortableLabScript `
        -ProjectRoot $projectPath `
        -SourceTerminalOrigin $DedicatedLabSourceTerminalOrigin `
        -LabTerminalRoot $DedicatedLabTerminalRoot

    if ($null -eq $portableLab) {
        throw "QDM custom portable lab preparation returned no result."
    }

    $TerminalOrigin = [string]$portableLab.terminal_origin
    $TerminalDataDir = [string]$portableLab.terminal_data_dir
    $portableTerminal = [bool]$portableLab.portable_terminal
}

if ([string]::IsNullOrWhiteSpace($TerminalDataDir)) {
    $TerminalDataDir = Resolve-TerminalDataDirByOrigin -OriginPath $TerminalOrigin
}

$terminalDataDir = $TerminalDataDir
$terminalExe = Join-Path $TerminalOrigin "terminal64.exe"
$metaEditorExe = Join-Path $TerminalOrigin "MetaEditor64.exe"
if (-not (Test-Path -LiteralPath $terminalExe)) {
    throw "Terminal executable not found: $terminalExe"
}
if (-not (Test-Path -LiteralPath $metaEditorExe)) {
    throw "MetaEditor not found: $metaEditorExe"
}

$scriptSource = Join-Path $projectPath ("MQL5\\Scripts\\{0}.mq5" -f $ScriptName)
if (-not (Test-Path -LiteralPath $scriptSource)) {
    throw "Script source not found: $scriptSource"
}

$commonRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
$targetCommonCsvPath = Join-Path $commonRoot $CommonRelativeCsvPath
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $targetCommonCsvPath) | Out-Null
Copy-Item -LiteralPath $PilotCsvPath -Destination $targetCommonCsvPath -Force

$scriptsTargetDir = Join-Path $terminalDataDir "MQL5\Scripts"
$presetsTargetDir = Join-Path $terminalDataDir "MQL5\Presets"
$logsDir = Join-Path $projectPath "LOGS"
$evidenceDir = Join-Path $projectPath "EVIDENCE\QDM_PILOT"
$runDir = Join-Path $evidenceDir "run"
$terminalLogDir = Join-Path $terminalDataDir "logs"

New-Item -ItemType Directory -Force -Path $scriptsTargetDir | Out-Null
New-Item -ItemType Directory -Force -Path $presetsTargetDir | Out-Null
New-Item -ItemType Directory -Force -Path $logsDir | Out-Null
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$scriptTarget = Join-Path $scriptsTargetDir ("{0}.mq5" -f $ScriptName)
Copy-Item -LiteralPath $scriptSource -Destination $scriptTarget -Force

$compileLog = Join-Path $logsDir ("COMPILE_{0}.log" -f $ScriptName)
& $metaEditorExe "/compile:$scriptTarget" "/log:$compileLog" | Out-Null

$compileText = Read-TextBestEffort -Path $compileLog
$compileOk = $false
if ($compileText -and ($compileText -match 'Result:\s+0 errors' -or $compileText -match '0 error\(s\)')) {
    $compileOk = $true
}

$runId = "qdm_import_custom_symbol_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")
$scriptPresetName = "{0}.set" -f $runId
$scriptPresetPath = Join-Path $presetsTargetDir $scriptPresetName
$configPath = Join-Path $runDir ("{0}.ini" -f $runId)
$terminalLogCopyPath = Join-Path $evidenceDir ("{0}__terminal.log" -f $runId)
$mqlLogCopyPath = Join-Path $evidenceDir ("{0}__mql.log" -f $runId)

$runStatus = if ($compileOk) { "ready" } else { "compile_failed" }
$runTimedOut = $false
$importSucceeded = $false
$importMessage = ""
$launchAt = $null
$busyProcesses = @()

if ($compileOk) {
    Write-PresetFile -Path $scriptPresetPath -Values @{
        InpCommonCsvPath = $CommonRelativeCsvPath
        InpCustomSymbol = $CustomSymbol
        InpCustomGroup = $CustomGroup
        InpBrokerTemplateSymbol = $BrokerTemplateSymbol
        InpSelectSymbolAfterImport = $(if ($SelectSymbolAfterImport) { "true" } else { "false" })
    }

    $config = @"
[StartUp]
Script=$ScriptName
ScriptParameters=$scriptPresetName
Symbol=$BrokerTemplateSymbol
Period=M1
ShutdownTerminal=1
"@
    Set-Content -LiteralPath $configPath -Value $config -Encoding ASCII

    if ($RunImport) {
        $busyProcesses = @(Get-RunningTerminalProcessesForOrigin -TerminalExePath $terminalExe)
        if ($busyProcesses.Count -gt 0) {
            $runStatus = "blocked_origin_busy"
            $importMessage = "Terminal origin is busy; import launch skipped to avoid colliding with an active MT5 instance."
        }
        else {
            $launchAt = Get-Date
            $terminalArgs = @("/config:$configPath")
            if ($portableTerminal) {
                $terminalArgs += "/portable"
            }
            $process = Start-Process -FilePath $terminalExe -ArgumentList $terminalArgs -PassThru
            try {
                Wait-Process -Id $process.Id -Timeout $TimeoutSec -ErrorAction Stop
                $runStatus = "completed"
            }
            catch {
                $runTimedOut = $true
                $runStatus = "timed_out"
                Get-Process -Id $process.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            }

            Start-Sleep -Seconds 2

            $mqlLogDir = Join-Path $terminalDataDir "MQL5\Logs"
            $terminalLogItem = $null
            if (Test-Path -LiteralPath $terminalLogDir) {
                $terminalLogItem = Get-ChildItem -LiteralPath $terminalLogDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $null -eq $launchAt -or $_.LastWriteTime -ge $launchAt.AddSeconds(-5) } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
            }

            if ($null -ne $terminalLogItem) {
                Copy-Item -LiteralPath $terminalLogItem.FullName -Destination $terminalLogCopyPath -Force
                $terminalLogText = Read-TextBestEffort -Path $terminalLogItem.FullName
                $successRegex = [regex]::Escape("Imported ") + ".*" + [regex]::Escape($CustomSymbol)
                $latestSuccess = Get-LatestRegexMatchValue -Text $terminalLogText -Pattern $successRegex
                if (-not [string]::IsNullOrWhiteSpace($latestSuccess)) {
                    $importSucceeded = $true
                    $importMessage = $latestSuccess
                    if (-not $runTimedOut) {
                        $runStatus = "imported"
                    }
                }
                else {
                    $latestFailure = Get-LatestRegexMatchValue -Text $terminalLogText -Pattern "CustomRatesReplace failed.*|Failed to open common CSV.*|No rates parsed from CSV.*|Custom symbol not ready.*"
                    if (-not [string]::IsNullOrWhiteSpace($latestFailure)) {
                        $importMessage = $latestFailure
                        if (-not $runTimedOut) {
                            $runStatus = "failed"
                        }
                    }
                }
                if ([string]::IsNullOrWhiteSpace($importMessage) -and -not $importSucceeded) {
                    $importMessage = "Terminal run completed, but no explicit import success marker was found in the terminal log."
                }
            }
            elseif ([string]::IsNullOrWhiteSpace($importMessage)) {
                $importMessage = "Terminal run completed, but no fresh terminal log was captured."
            }

            $mqlLogItem = $null
            if (Test-Path -LiteralPath $mqlLogDir) {
                $mqlLogItem = Get-ChildItem -LiteralPath $mqlLogDir -File -ErrorAction SilentlyContinue |
                    Where-Object { $null -eq $launchAt -or $_.LastWriteTime -ge $launchAt.AddSeconds(-5) } |
                    Sort-Object LastWriteTime -Descending |
                    Select-Object -First 1
            }

            if ($null -ne $mqlLogItem) {
                Copy-Item -LiteralPath $mqlLogItem.FullName -Destination $mqlLogCopyPath -Force
            }

            if (-not $importSucceeded -and $null -ne $mqlLogItem) {
                $mqlLogText = Read-TextBestEffort -Path $mqlLogItem.FullName
                $successRegex = [regex]::Escape("Imported ") + ".*" + [regex]::Escape($CustomSymbol)
                $latestSuccess = Get-LatestRegexMatchValue -Text $mqlLogText -Pattern $successRegex
                if (-not [string]::IsNullOrWhiteSpace($latestSuccess)) {
                    $importSucceeded = $true
                    $importMessage = $latestSuccess
                    if (-not $runTimedOut) {
                        $runStatus = "imported"
                    }
                }
                else {
                    $latestFailure = Get-LatestRegexMatchValue -Text $mqlLogText -Pattern "CustomRatesReplace failed.*|Failed to open common CSV.*|No rates parsed from CSV.*|Custom symbol not ready.*"
                    if (-not [string]::IsNullOrWhiteSpace($latestFailure)) {
                        $importMessage = $latestFailure
                        if (-not $runTimedOut) {
                            $runStatus = "failed"
                        }
                    }
                }
            }
        }
    }
    else {
        $runStatus = "prepared_compile_only"
        $importMessage = "Compile and launch assets prepared; run skipped by configuration."
    }
}

$result = [pscustomobject]@{
    schema_version = "1.1"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    terminal_origin = $TerminalOrigin
    terminal_exe = $terminalExe
    terminal_data_dir = $terminalDataDir
    portable_terminal = $portableTerminal
    common_csv_path = $targetCommonCsvPath
    script_name = $ScriptName
    script_target = $scriptTarget
    script_preset_name = $scriptPresetName
    script_preset_path = $scriptPresetPath
    run_config_path = $configPath
    compile_log = $compileLog
    compile_ok = $compileOk
    run_import = $RunImport
    run_status = $runStatus
    run_timed_out = $runTimedOut
    import_succeeded = $importSucceeded
    import_message = $importMessage
    custom_symbol = $CustomSymbol
    custom_group = $CustomGroup
    broker_template_symbol = $BrokerTemplateSymbol
    terminal_log_copy_path = $(if (Test-Path -LiteralPath $terminalLogCopyPath) { $terminalLogCopyPath } else { $null })
    mql_log_copy_path = $(if (Test-Path -LiteralPath $mqlLogCopyPath) { $mqlLogCopyPath } else { $null })
    busy_origin_process_count = $busyProcesses.Count
    busy_origin_process_ids = @($busyProcesses | ForEach-Object { [int]$_.ProcessId })
}

if (-not [string]::IsNullOrWhiteSpace($LatestStatusPath)) {
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
    $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
}

$result | ConvertTo-Json -Depth 5

if (-not $compileOk) {
    exit 1
}
