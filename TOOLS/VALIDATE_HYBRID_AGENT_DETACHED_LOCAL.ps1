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

function Get-AllTerminalDataDirs {
    $base = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path -LiteralPath $base)) {
        return @()
    }
    return @(
        Get-ChildItem -LiteralPath $base -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^[A-F0-9]{32}$' } |
        Select-Object -ExpandProperty FullName |
        Sort-Object -Unique
    )
}

$projectRoot = "C:\OANDA_MT5_SYSTEM"
$evidenceDir = Join-Path $projectRoot "EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$dirs = @((Get-AllTerminalDataDirs) + (Get-Mt5DataDirs -Server $ServerName) | Sort-Object -Unique)
$issues = New-Object System.Collections.Generic.List[string]
$items = @()

foreach ($dir in $dirs) {
    $activeMq5 = Join-Path $dir "MQL5\Experts\HybridAgent.mq5"
    $activeEx5 = Join-Path $dir "MQL5\Experts\HybridAgent.ex5"
    $detached = Join-Path $dir "MQL5\Experts\DETACHED_HYBRID_AGENT"

    $row = [ordered]@{
        mt5_data_dir = $dir
        active_mq5_present = (Test-Path -LiteralPath $activeMq5)
        active_ex5_present = (Test-Path -LiteralPath $activeEx5)
        detached_folder_present = (Test-Path -LiteralPath $detached)
    }

    if ($row.active_mq5_present) {
        $issues.Add("ACTIVE_HYBRID_AGENT_MQ5_PRESENT:" + $dir)
    }
    if ($row.active_ex5_present) {
        $issues.Add("ACTIVE_HYBRID_AGENT_EX5_PRESENT:" + $dir)
    }
    if (-not $row.detached_folder_present) {
        $issues.Add("DETACHED_FOLDER_MISSING:" + $dir)
    }

    $items += $row
}

$terminalProcesses = @()
try {
    $terminalProcesses = @(Get-Process terminal64 -ErrorAction Stop | Select-Object Id, ProcessName, Path)
} catch {
    $terminalProcesses = @()
}

$result = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    server_name = $ServerName
    ok = ($issues.Count -eq 0)
    mt5_dirs = $items
    terminal64_running = (@($terminalProcesses).Count -gt 0)
    terminal64_processes = @($terminalProcesses)
    issues = @($issues)
}

$jsonPath = Join-Path $evidenceDir "validate_hybrid_agent_detached_local_report.json"
$txtPath = Join-Path $evidenceDir "validate_hybrid_agent_detached_local_report.txt"
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$result | ConvertTo-Json -Depth 6

if (-not $result.ok) {
    exit 1
}
