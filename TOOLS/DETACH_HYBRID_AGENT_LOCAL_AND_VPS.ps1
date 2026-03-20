param(
    [string]$ProjectRoot = "C:\OANDA_MT5_SYSTEM",
    [string]$ServerName = "OANDATMS-MT5",
    [string]$TokenEnvPath = "D:\TOKEN\BotKey.env"
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
    param([string]$TerminalPathHint = "")
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

function Parse-EnvFile {
    param([string]$Path)
    $map = @{}
    Get-Content -LiteralPath $Path -Encoding UTF8 | ForEach-Object {
        $line = [string]$_
        if ($line -match '^\s*#') { return }
        $idx = $line.IndexOf('=')
        if ($idx -gt 0) {
            $map[$line.Substring(0, $idx).Trim()] = $line.Substring($idx + 1)
        }
    }
    return $map
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$evidenceDir = Join-Path $projectPath "EVIDENCE"
New-Item -ItemType Directory -Force -Path $evidenceDir | Out-Null

$localSystemControl = & (Join-Path $projectPath "TOOLS\SYSTEM_CONTROL.ps1") -Action stop -Root $projectPath -Profile safety_only 2>&1 | Out-String
$localMt5Dirs = Get-Mt5DataDirs -Server $ServerName
$localStoppedTerminals = Stop-TerminalProcesses
$localQuarantine = Quarantine-HybridAgent -DataDirs $localMt5Dirs

$cfg = Parse-EnvFile -Path $TokenEnvPath
$secure = ConvertTo-SecureString ([string]$cfg["VPS_ADMIN_PASSWORD_DPAPI"])
$cred = [pscredential]::new([string]$cfg["VPS_ADMIN_LOGIN"], $secure)
$remote = [ordered]@{
    status = "not_started"
    host = [string]$cfg["VPS_HOST"]
}
$session = $null
try {
    $session = New-PSSession -ComputerName ([string]$cfg["VPS_HOST"]) -Credential $cred -ErrorAction Stop
    $remoteData = Invoke-Command -Session $session -ArgumentList $ServerName -ScriptBlock {
        param([string]$RemoteServerName)

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

        $remoteSystemControl = ""
        if (Test-Path -LiteralPath "C:\OANDA_MT5_SYSTEM\TOOLS\SYSTEM_CONTROL.ps1") {
            $remoteSystemControl = powershell -NoProfile -ExecutionPolicy Bypass -File C:\OANDA_MT5_SYSTEM\TOOLS\SYSTEM_CONTROL.ps1 -Action stop -Root C:\OANDA_MT5_SYSTEM -Profile safety_only 2>&1 | Out-String
        }
        $remoteMt5Dirs = Get-Mt5DataDirs -Server $RemoteServerName
        $remoteStoppedTerminals = Stop-TerminalProcesses
        $remoteQuarantine = Quarantine-HybridAgent -DataDirs $remoteMt5Dirs

        [ordered]@{
            system_control_output = $remoteSystemControl
            mt5_data_dirs = @($remoteMt5Dirs)
            terminal_stop = @($remoteStoppedTerminals)
            quarantine = @($remoteQuarantine)
        }
    }
    $remote = [ordered]@{
        status = "ok"
        host = [string]$cfg["VPS_HOST"]
        data = $remoteData
    }
} catch {
    $remote = [ordered]@{
        status = "blocked"
        host = [string]$cfg["VPS_HOST"]
        error = $_.Exception.Message
    }
} finally {
    if ($session) {
        Remove-PSSession -Session $session -ErrorAction SilentlyContinue
    }
}

$report = [ordered]@{
    schema_version = "1.0"
    ts_utc = (Get-Date).ToUniversalTime().ToString("o")
    server_name = $ServerName
    server_location_reference = [ordered]@{
        target_server_name = "VPS Warsaw 01"
        target_server_id = "#260303_1940"
        source_config = "C:\GLOBALNY HANDEL VER1\EURUSD\CONFIG\mql5_server_profile.json"
        source_doc = "C:\GLOBALNY HANDEL VER1\EURUSD\DOCS\EURUSD_VPS_DEPLOYMENT.md"
        remote_root_reference = "C:\GH_EURUSD"
    }
    local = [ordered]@{
        system_control_output = $localSystemControl
        mt5_data_dirs = @($localMt5Dirs)
        terminal_stop = @($localStoppedTerminals)
        quarantine = @($localQuarantine)
    }
    remote = $remote
}

$jsonPath = Join-Path $evidenceDir "detach_hybrid_agent_local_and_vps_report.json"
$txtPath = Join-Path $evidenceDir "detach_hybrid_agent_local_and_vps_report.txt"
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $txtPath -Encoding ASCII
$report | ConvertTo-Json -Depth 8
