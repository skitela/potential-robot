param(
    [string]$ProjectRoot = "C:\MAKRO_I_MIKRO_BOT",
    [string]$TerminalOrigin = "C:\Program Files\MetaTrader 5",
    [string]$TerminalDataDir = "",
    [string]$AuthSourceTerminalOrigin = "C:\Program Files\OANDA TMS MT5 Terminal",
    [string]$AuthSourceTerminalDataDir = "",
    [string]$MetaEditorExe = "",
    [switch]$CompileAll = $true
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

function Copy-ProjectSourcesToTerminal {
    param(
        [string]$SourceProjectRoot,
        [string]$TargetTerminalDataDir
    )

    $targetMql5 = Join-Path $TargetTerminalDataDir "MQL5"
    $targetExperts = Join-Path $targetMql5 "Experts\MicroBots"
    $targetCore = Join-Path $targetMql5 "Include\Core"
    $targetProfiles = Join-Path $targetMql5 "Include\Profiles"
    $targetStrategies = Join-Path $targetMql5 "Include\Strategies"
    $targetStrategiesCommon = Join-Path $targetMql5 "Include\Strategies\Common"

    @($targetExperts, $targetCore, $targetProfiles, $targetStrategies, $targetStrategiesCommon) | ForEach-Object {
        New-Item -ItemType Directory -Force -Path $_ | Out-Null
    }

    Copy-Item (Join-Path $SourceProjectRoot "MQL5\Experts\MicroBots\*.mq5") $targetExperts -Force
    Copy-Item (Join-Path $SourceProjectRoot "MQL5\Include\Core\*.mqh") $targetCore -Force
    Copy-Item (Join-Path $SourceProjectRoot "MQL5\Include\Profiles\*.mqh") $targetProfiles -Force
    Copy-Item (Join-Path $SourceProjectRoot "MQL5\Include\Strategies\*.mqh") $targetStrategies -Force
    Copy-Item (Join-Path $SourceProjectRoot "MQL5\Include\Strategies\Common\*.mqh") $targetStrategiesCommon -Force
}

function Copy-AuthConfigToTerminal {
    param(
        [string]$SourceTerminalDataDir,
        [string]$TargetTerminalDataDir
    )

    if ([string]::IsNullOrWhiteSpace($SourceTerminalDataDir) -or -not (Test-Path -LiteralPath $SourceTerminalDataDir)) {
        return @()
    }

    $sourceConfig = Join-Path $SourceTerminalDataDir "config"
    $targetConfig = Join-Path $TargetTerminalDataDir "config"
    if (-not (Test-Path -LiteralPath $sourceConfig)) {
        return @()
    }

    New-Item -ItemType Directory -Force -Path $targetConfig | Out-Null

    $copied = New-Object System.Collections.Generic.List[string]
    foreach ($fileName in @("accounts.dat", "common.ini", "servers.dat")) {
        $sourcePath = Join-Path $sourceConfig $fileName
        if (-not (Test-Path -LiteralPath $sourcePath)) {
            continue
        }

        $targetPath = Join-Path $targetConfig $fileName
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        $copied.Add($targetPath)
    }

    return @($copied)
}

if ([string]::IsNullOrWhiteSpace($TerminalDataDir)) {
    $TerminalDataDir = Resolve-TerminalDataDirByOrigin -OriginPath $TerminalOrigin
}

if ([string]::IsNullOrWhiteSpace($AuthSourceTerminalDataDir) -and -not [string]::IsNullOrWhiteSpace($AuthSourceTerminalOrigin)) {
    try {
        $AuthSourceTerminalDataDir = Resolve-TerminalDataDirByOrigin -OriginPath $AuthSourceTerminalOrigin
    }
    catch {
        $AuthSourceTerminalDataDir = ""
    }
}

if ([string]::IsNullOrWhiteSpace($MetaEditorExe)) {
    $MetaEditorExe = Join-Path $TerminalOrigin "MetaEditor64.exe"
}

if (-not (Test-Path -LiteralPath $TerminalDataDir)) {
    throw "Terminal data dir not found: $TerminalDataDir"
}
if (-not (Test-Path -LiteralPath $MetaEditorExe)) {
    throw "MetaEditor not found: $MetaEditorExe"
}

$projectRootResolved = (Resolve-Path -LiteralPath $ProjectRoot).Path
Copy-ProjectSourcesToTerminal -SourceProjectRoot $projectRootResolved -TargetTerminalDataDir $TerminalDataDir
$authConfigCopied = Copy-AuthConfigToTerminal -SourceTerminalDataDir $AuthSourceTerminalDataDir -TargetTerminalDataDir $TerminalDataDir

$compileResults = @()
if ($CompileAll) {
    $registryPath = Join-Path $projectRootResolved "CONFIG\microbots_registry.json"
    $registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $logDir = Join-Path $projectRootResolved "LOGS"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    foreach ($item in $registry.symbols) {
        $expertName = [string]$item.expert
        $expertTarget = Join-Path $TerminalDataDir ("MQL5\Experts\MicroBots\{0}.mq5" -f $expertName)
        $compileLog = Join-Path $logDir ("COMPILE_SECONDARY_{0}.log" -f $expertName)
        & $MetaEditorExe "/compile:$expertTarget" "/log:$compileLog" | Out-Null
        $ok = $false
        if (Test-Path -LiteralPath $compileLog) {
            foreach ($encoding in @('Unicode','UTF8','Default')) {
                try {
                    $text = Get-Content -LiteralPath $compileLog -Raw -Encoding $encoding -ErrorAction Stop
                } catch {
                    $text = $null
                }
                if ($text) {
                    if ($text -match 'Result:\s+0 errors' -or $text -match '0 error\(s\)') {
                        $ok = $true
                    }
                    break
                }
            }
        }

        $compileResults += [pscustomobject]@{
            expert = $expertName
            compile_ok = $ok
            compile_log = $compileLog
        }
    }
}

[pscustomobject]@{
    terminal_origin = $TerminalOrigin
    terminal_data_dir = $TerminalDataDir
    auth_source_terminal_data_dir = $AuthSourceTerminalDataDir
    auth_config_copied = $authConfigCopied
    metaeditor = $MetaEditorExe
    compile_all = [bool]$CompileAll
    compile_results = $compileResults
}
