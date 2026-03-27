param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalOrigin = "C:\Program Files\OANDA TMS MT5 Terminal",
    [string]$TerminalDataDir = "",
    [string]$ScriptName = "ExportBrokerMinuteTail",
    [string[]]$ExportNames = @("MB_GOLD_DUKA", "MB_SILVER_DUKA", "MB_US500_DUKA"),
    [string[]]$SymbolAliases = @("GOLD", "SILVER", "US500"),
    [string[]]$BrokerSymbols = @("GOLD.pro", "SILVER.pro", "US500.pro"),
    [int]$HoursBack = 96,
    [int]$TimeoutSec = 300,
    [string]$CommonRelativeOutputRoot = "MAKRO_I_MIKRO_BOT\\broker_tail",
    [string]$LatestStatusPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\OPS\broker_minute_tail_export_latest.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-TerminalDataDirByOrigin {
    param([string]$OriginPath)

    $base = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    $normalizedOrigin = [System.IO.Path]::GetFullPath($OriginPath).TrimEnd('\').ToLowerInvariant()
    $match = Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Where-Object {
            $originFile = Join-Path $_.FullName "origin.txt"
            if (-not (Test-Path -LiteralPath $originFile)) { return $false }
            $content = (Get-Content -LiteralPath $originFile -Raw -Encoding UTF8).Trim()
            if ([string]::IsNullOrWhiteSpace($content)) { return $false }
            try {
                return ([System.IO.Path]::GetFullPath($content).TrimEnd('\').ToLowerInvariant() -eq $normalizedOrigin)
            } catch {
                return $false
            }
        } |
        Select-Object -First 1

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
        } catch {}
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

if ($ExportNames.Count -ne $SymbolAliases.Count -or $ExportNames.Count -ne $BrokerSymbols.Count) {
    throw "ExportNames, SymbolAliases and BrokerSymbols must have the same length."
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
if ([string]::IsNullOrWhiteSpace($TerminalDataDir)) {
    $TerminalDataDir = Resolve-TerminalDataDirByOrigin -OriginPath $TerminalOrigin
}

$terminalExe = Join-Path $TerminalOrigin "terminal64.exe"
$metaEditorExe = Join-Path $TerminalOrigin "MetaEditor64.exe"
if (-not (Test-Path -LiteralPath $terminalExe)) { throw "Terminal executable not found: $terminalExe" }
if (-not (Test-Path -LiteralPath $metaEditorExe)) { throw "MetaEditor not found: $metaEditorExe" }

$scriptSource = Join-Path $projectPath ("MQL5\\Scripts\\{0}.mq5" -f $ScriptName)
if (-not (Test-Path -LiteralPath $scriptSource)) {
    throw "Script source not found: $scriptSource"
}

$commonRoot = Join-Path $env:APPDATA "MetaQuotes\Terminal\Common\Files"
$targetCommonDir = Join-Path $commonRoot $CommonRelativeOutputRoot
New-Item -ItemType Directory -Force -Path $targetCommonDir | Out-Null

$scriptsTargetDir = Join-Path $TerminalDataDir "MQL5\Scripts"
$presetsTargetDir = Join-Path $TerminalDataDir "MQL5\Presets"
$logsDir = Join-Path $projectPath "LOGS"
$opsDir = Join-Path $projectPath "EVIDENCE\OPS"
$runDir = Join-Path $opsDir "broker_tail_run"
New-Item -ItemType Directory -Force -Path $scriptsTargetDir,$presetsTargetDir,$logsDir,$opsDir,$runDir | Out-Null

$scriptTarget = Join-Path $scriptsTargetDir ("{0}.mq5" -f $ScriptName)
Copy-Item -LiteralPath $scriptSource -Destination $scriptTarget -Force

$compileLog = Join-Path $logsDir ("COMPILE_{0}.log" -f $ScriptName)
& $metaEditorExe "/compile:$scriptTarget" "/log:$compileLog" | Out-Null
$compileText = Read-TextBestEffort -Path $compileLog
$compileOk = $false
if ($compileText -and ($compileText -match 'Result:\s+0 errors' -or $compileText -match '0 error\(s\)')) {
    $compileOk = $true
}
if (-not $compileOk) {
    throw "Compile failed for $ScriptName"
}

$runId = "broker_tail_export_{0}" -f (Get-Date -Format "yyyyMMdd_HHmmss")
$scriptPresetName = "{0}.set" -f $runId
$scriptPresetPath = Join-Path $presetsTargetDir $scriptPresetName
$configPath = Join-Path $runDir ("{0}.ini" -f $runId)
$terminalLogCopyPath = Join-Path $opsDir ("{0}__terminal.log" -f $runId)
$mqlLogCopyPath = Join-Path $opsDir ("{0}__mql.log" -f $runId)

Write-PresetFile -Path $scriptPresetPath -Values @{
    InpOutputRoot = $CommonRelativeOutputRoot
    InpExportNames = ($ExportNames -join ';')
    InpSymbolAliases = ($SymbolAliases -join ';')
    InpBrokerSymbols = ($BrokerSymbols -join ';')
    InpHoursBack = $HoursBack
}

$config = @"
[StartUp]
Script=$ScriptName
ScriptParameters=$scriptPresetName
Symbol=$($BrokerSymbols[0])
Period=M1
ShutdownTerminal=1
"@
Set-Content -LiteralPath $configPath -Value $config -Encoding ASCII

$busyProcesses = @(Get-RunningTerminalProcessesForOrigin -TerminalExePath $terminalExe)
if ($busyProcesses.Count -gt 0) {
    throw "Terminal origin is busy; broker tail export skipped to avoid colliding with active MT5 instance."
}

$launchAt = Get-Date
$process = Start-Process -FilePath $terminalExe -ArgumentList @("/config:$configPath") -PassThru
$runTimedOut = $false
try {
    Wait-Process -Id $process.Id -Timeout $TimeoutSec -ErrorAction Stop
} catch {
    $runTimedOut = $true
    Get-Process -Id $process.Id -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2

$mqlLogDir = Join-Path $TerminalDataDir "MQL5\Logs"
$terminalLogItem = if (Test-Path -LiteralPath $mqlLogDir) {
    Get-ChildItem -LiteralPath $mqlLogDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $launchAt.AddSeconds(-5) } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
} else { $null }

$mqlLogItem = $terminalLogItem
if ($null -ne $terminalLogItem) {
    Copy-Item -LiteralPath $terminalLogItem.FullName -Destination $terminalLogCopyPath -Force
    Copy-Item -LiteralPath $terminalLogItem.FullName -Destination $mqlLogCopyPath -Force
}

$logText = if ($null -ne $terminalLogItem) { Read-TextBestEffort -Path $terminalLogItem.FullName } else { "" }
$successMessage = Get-LatestRegexMatchValue -Text $logText -Pattern "BROKER_TAIL_EXPORT_SUMMARY.*"
$warningMessage = Get-LatestRegexMatchValue -Text $logText -Pattern "BROKER_TAIL_EXPORT_WARN.*|BROKER_TAIL_EXPORT_FATAL.*"

$files = @()
foreach ($exportName in $ExportNames) {
    $path = Join-Path $targetCommonDir ("{0}_BROKER_TAIL.csv" -f $exportName)
    $rows = 0
    if (Test-Path -LiteralPath $path) {
        $rows = [Math]::Max(((Get-Content -LiteralPath $path -Encoding UTF8 | Measure-Object -Line).Lines - 1), 0)
    }
    $files += [pscustomobject]@{
        export_name = $exportName
        path = $path
        present = (Test-Path -LiteralPath $path)
        row_count = $rows
    }
}

$result = [ordered]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    terminal_origin = $TerminalOrigin
    terminal_data_dir = $TerminalDataDir
    compile_ok = $compileOk
    run_timed_out = $runTimedOut
    success_message = $successMessage
    warning_message = $warningMessage
    common_output_root = $targetCommonDir
    export_names = @($ExportNames)
    symbol_aliases = @($SymbolAliases)
    broker_symbols = @($BrokerSymbols)
    files = $files
    terminal_log_copy_path = $(if (Test-Path -LiteralPath $terminalLogCopyPath) { $terminalLogCopyPath } else { $null })
    mql_log_copy_path = $(if (Test-Path -LiteralPath $mqlLogCopyPath) { $mqlLogCopyPath } else { $null })
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $LatestStatusPath) | Out-Null
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $LatestStatusPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6
