param(
    [string]$ServerName = "OANDATMS-MT5"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-IniValue {
    param(
        [string[]]$Lines,
        [string]$Section,
        [string]$Key
    )
    $sec = "[" + $Section + "]"
    $inSection = $false
    foreach ($line in $Lines) {
        $t = [string]$line
        if ($t -match '^\[.*\]$') {
            $inSection = ($t -ieq $sec)
            continue
        }
        if (-not $inSection) { continue }
        if ($t -match ('^' + [regex]::Escape($Key) + '\s*=(.*)$')) {
            return $matches[1].Trim()
        }
    }
    return ""
}

function Get-Mt5DataDirs {
    param([string]$Server)
    $base = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    $dirs = @()
    if (-not (Test-Path -LiteralPath $base)) {
        return @()
    }
    foreach ($dir in Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue) {
        $ini = Join-Path $dir.FullName "config\common.ini"
        if (-not (Test-Path -LiteralPath $ini)) { continue }
        $lines = Get-Content -LiteralPath $ini -Encoding UTF8
        $srv = Get-IniValue -Lines $lines -Section "Common" -Key "Server"
        if ($srv -ieq $Server) {
            $dirs += $dir.FullName
        }
    }
    return @($dirs | Sort-Object -Unique)
}

function Stop-TerminalProcesses {
    $rows = @()
    try {
        $rows = @(Get-CimInstance Win32_Process -ErrorAction Stop | Where-Object {
            $_.Name -ieq "terminal64.exe"
        })
    } catch {
        $rows = @()
    }

    $stopped = @()
    foreach ($row in $rows) {
        $procIdLocal = [int]$row.ProcessId
        try {
            Stop-Process -Id $procIdLocal -Force -ErrorAction Stop
            $stopped += [ordered]@{
                pid = $procIdLocal
                status = "stopped"
                command_line = [string]$row.CommandLine
            }
        } catch {
            $stopped += [ordered]@{
                pid = $procIdLocal
                status = "stop_failed"
                command_line = [string]$row.CommandLine
                error = $_.Exception.Message
            }
        }
    }
    return @($stopped)
}

function Quarantine-HybridAgent {
    param([string[]]$DataDirs)
    $results = @()
    $stamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss")
    foreach ($dir in $DataDirs) {
        $expertsDir = Join-Path $dir "MQL5\Experts"
        $quarantineDir = Join-Path $expertsDir ("DETACHED_HYBRID_AGENT\" + $stamp)
        $files = @(
            (Join-Path $expertsDir "HybridAgent.mq5"),
            (Join-Path $expertsDir "HybridAgent.ex5")
        )
        foreach ($src in $files) {
            if (-not (Test-Path -LiteralPath $src)) { continue }
            New-Item -ItemType Directory -Force -Path $quarantineDir | Out-Null
            $dst = Join-Path $quarantineDir ([System.IO.Path]::GetFileName($src))
            Move-Item -LiteralPath $src -Destination $dst -Force
            $results += [ordered]@{
                source = $src
                destination = $dst
                status = "moved"
            }
        }
    }
    return @($results)
}

$systemControlOutput = ""
if (Test-Path -LiteralPath "C:\OANDA_MT5_SYSTEM\TOOLS\SYSTEM_CONTROL.ps1") {
    $systemControlOutput = powershell -NoProfile -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\SYSTEM_CONTROL.ps1 -Action stop -Root C:\OANDA_MT5_SYSTEM -Profile safety_only 2>&1 | Out-String
}

$dirs = Get-Mt5DataDirs -Server $ServerName
$stopped = Stop-TerminalProcesses
$quarantine = Quarantine-HybridAgent -DataDirs $dirs

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    server_name = $ServerName
    system_control_output = $systemControlOutput
    mt5_data_dirs = @($dirs)
    terminal_stop = @($stopped)
    quarantine = @($quarantine)
}

$result | ConvertTo-Json -Depth 6
