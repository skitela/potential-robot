param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalOrigin = "C:\Program Files\MetaTrader 5",
    [string]$PilotCsvPath = "C:\MAKRO_I_MIKRO_BOT\EVIDENCE\QDM_PILOT\MB_EURUSD_DUKA_M1_PILOT.csv",
    [string]$CommonRelativeCsvPath = "MAKRO_I_MIKRO_BOT\\qdm_import\\MB_EURUSD_DUKA_M1_PILOT.csv",
    [string]$ScriptName = "QdmImportCustomSymbolBars"
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

if (-not (Test-Path -LiteralPath $PilotCsvPath)) {
    throw "Pilot CSV not found: $PilotCsvPath"
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$terminalDataDir = Resolve-TerminalDataDirByOrigin -OriginPath $TerminalOrigin
$metaEditorExe = Join-Path $TerminalOrigin "MetaEditor64.exe"
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
New-Item -ItemType Directory -Force -Path $scriptsTargetDir | Out-Null
$scriptTarget = Join-Path $scriptsTargetDir ("{0}.mq5" -f $ScriptName)
Copy-Item -LiteralPath $scriptSource -Destination $scriptTarget -Force

$logDir = Join-Path $projectPath "LOGS"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$compileLog = Join-Path $logDir ("COMPILE_{0}.log" -f $ScriptName)

& $metaEditorExe "/compile:$scriptTarget" "/log:$compileLog" | Out-Null

$compileText = $null
foreach ($encoding in @("Unicode", "UTF8", "Default")) {
    try {
        $compileText = Get-Content -Path $compileLog -Raw -Encoding $encoding -ErrorAction Stop
    }
    catch {
        $compileText = $null
    }
    if ($compileText) { break }
}

$compileOk = $false
if ($compileText -and ($compileText -match 'Result:\s+0 errors' -or $compileText -match '0 error\(s\)')) {
    $compileOk = $true
}

[pscustomobject]@{
    schema_version = "1.0"
    generated_at_utc = (Get-Date).ToUniversalTime().ToString("o")
    terminal_origin = $TerminalOrigin
    terminal_data_dir = $terminalDataDir
    common_csv_path = $targetCommonCsvPath
    script_name = $ScriptName
    script_target = $scriptTarget
    compile_log = $compileLog
    compile_ok = $compileOk
} | ConvertTo-Json -Depth 4

if (-not $compileOk) {
    exit 1
}
