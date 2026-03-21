param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$SourceTerminalOrigin = "C:\Program Files\MetaTrader 5",
    [string]$LabTerminalRoot = "C:\TRADING_TOOLS\MT5_NEAR_PROFIT_LAB",
    [string]$AuthSourceTerminalOrigin = "C:\Program Files\OANDA TMS MT5 Terminal",
    [switch]$CompileAll
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
            } catch {
                return $false
            }
        }

    $match = $matches | Select-Object -First 1
    if (-not $match) {
        throw "No terminal data dir found for origin: $OriginPath"
    }

    return $match.FullName
}

function Copy-CompiledExpertsToPortableLab {
    param(
        [string]$SourceTerminalDataDir,
        [string]$LabRoot
    )

    $sourceExperts = Join-Path $SourceTerminalDataDir "MQL5\Experts\MicroBots"
    $targetExperts = Join-Path $LabRoot "MQL5\Experts\MicroBots"
    if (-not (Test-Path -LiteralPath $sourceExperts)) {
        throw "Source compiled experts directory not found: $sourceExperts"
    }

    New-Item -ItemType Directory -Force -Path $targetExperts | Out-Null
    Copy-Item (Join-Path $sourceExperts "*.ex5") $targetExperts -Force
}

$prepareScript = Join-Path $ProjectRoot "RUN\PREPARE_MT5_LAB_TERMINAL.ps1"
if (-not (Test-Path -LiteralPath $prepareScript)) {
    throw "Required script not found: $prepareScript"
}

if (-not (Test-Path -LiteralPath $SourceTerminalOrigin)) {
    throw "Source terminal origin not found: $SourceTerminalOrigin"
}

New-Item -ItemType Directory -Force -Path $LabTerminalRoot | Out-Null

$sourceTerminalExe = Join-Path $SourceTerminalOrigin "terminal64.exe"
$labTerminalExe = Join-Path $LabTerminalRoot "terminal64.exe"
if (-not (Test-Path -LiteralPath $sourceTerminalExe)) {
    throw "Source terminal exe not found: $sourceTerminalExe"
}

$robocopyLog = Join-Path $ProjectRoot "LOGS\PREPARE_NEAR_PROFIT_PORTABLE_LAB_robocopy.log"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $robocopyLog) | Out-Null
$robocopyArgs = @(
    $SourceTerminalOrigin,
    $LabTerminalRoot,
    "/E",
    "/XO",
    "/R:1",
    "/W:1",
    "/NFL",
    "/NDL",
    "/NJH",
    "/NJS",
    "/NC",
    "/NS",
    "/LOG:$robocopyLog"
)
$null = & robocopy @robocopyArgs
$robocopyCode = $LASTEXITCODE
if ($robocopyCode -gt 7) {
    throw "Robocopy failed while preparing portable lab terminal. Exit code: $robocopyCode"
}

$sourceTerminalDataDir = Resolve-TerminalDataDirByOrigin -OriginPath $SourceTerminalOrigin

$prepared = & $prepareScript `
    -ProjectRoot $ProjectRoot `
    -TerminalOrigin $LabTerminalRoot `
    -TerminalDataDir $LabTerminalRoot `
    -AuthSourceTerminalOrigin $AuthSourceTerminalOrigin `
    -MetaEditorExe (Join-Path $LabTerminalRoot "MetaEditor64.exe") `
    -CompileAll:$CompileAll

Copy-CompiledExpertsToPortableLab -SourceTerminalDataDir $sourceTerminalDataDir -LabRoot $LabTerminalRoot

[pscustomobject]@{
    terminal_origin = $LabTerminalRoot
    terminal_data_dir = $LabTerminalRoot
    mt5_exe = $labTerminalExe
    portable_terminal = $true
    source_terminal_data_dir = $sourceTerminalDataDir
    robocopy_log = $robocopyLog
    robocopy_exit_code = $robocopyCode
    prepare_result = $prepared
}
