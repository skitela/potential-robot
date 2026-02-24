param(
    [string]$TerminalDataDir = "",
    [string]$Server = "OANDATMS-MT5",
    [switch]$NoRestart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-IniValue {
    param(
        [string[]]$Lines,
        [string]$Section,
        [string]$Key
    )
    $sec = "[$Section]"
    $inSection = $false
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if ($t -match "^\[.*\]$") {
            $inSection = ($t -ieq $sec)
            continue
        }
        if (-not $inSection) { continue }
        if ($t -match ("^" + [regex]::Escape($Key) + "\s*=(.*)$")) {
            return $matches[1].Trim()
        }
    }
    return ""
}

function Set-IniValue {
    param(
        [System.Collections.Generic.List[string]]$Lines,
        [string]$Section,
        [string]$Key,
        [string]$Value
    )
    $sectionHeader = "[$Section]"
    $sectionStart = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -ieq $sectionHeader) {
            $sectionStart = $i
            break
        }
    }

    if ($sectionStart -lt 0) {
        if ($Lines.Count -gt 0 -and $Lines[$Lines.Count - 1].Trim() -ne "") {
            $Lines.Add("")
        }
        $Lines.Add($sectionHeader)
        $Lines.Add("$Key=$Value")
        return
    }

    $sectionEnd = $Lines.Count
    for ($i = $sectionStart + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -match "^\[.*\]$") {
            $sectionEnd = $i
            break
        }
    }

    for ($i = $sectionStart + 1; $i -lt $sectionEnd; $i++) {
        if ($Lines[$i].Trim() -match ("^" + [regex]::Escape($Key) + "\s*=")) {
            $Lines[$i] = "$Key=$Value"
            return
        }
    }

    $Lines.Insert($sectionEnd, "$Key=$Value")
}

function Find-TerminalDataDir {
    param([string]$ServerName)
    if (-not [string]::IsNullOrWhiteSpace($TerminalDataDir)) {
        $explicit = Resolve-Path $TerminalDataDir -ErrorAction Stop
        return $explicit.Path
    }

    $base = Join-Path $env:APPDATA "MetaQuotes\Terminal"
    if (-not (Test-Path $base)) {
        throw "Nie znaleziono katalogu: $base"
    }

    $best = $null
    $bestScore = -1
    foreach ($dir in Get-ChildItem $base -Directory -ErrorAction SilentlyContinue) {
        $ini = Join-Path $dir.FullName "config\common.ini"
        if (-not (Test-Path $ini)) { continue }
        $lines = Get-Content $ini -Encoding UTF8
        $srv = Get-IniValue -Lines $lines -Section "Common" -Key "Server"
        $score = 1
        if ($srv -ieq $ServerName) { $score += 1000 }
        try {
            $score += [int]((Get-Item $ini).LastWriteTimeUtc.ToFileTimeUtc() / 10000000)
        } catch {}
        if ($score -gt $bestScore) {
            $bestScore = $score
            $best = $dir.FullName
        }
    }
    if (-not $best) {
        throw "Nie znaleziono katalogu danych MT5 z plikiem common.ini"
    }
    return $best
}

function Find-TerminalExe {
    $proc = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "terminal64.exe" -and -not [string]::IsNullOrWhiteSpace($_.ExecutablePath) } |
        Select-Object -First 1
    if ($proc -and (Test-Path $proc.ExecutablePath)) {
        return $proc.ExecutablePath
    }
    $candidates = @(
        "C:\Program Files\OANDA TMS MT5 Terminal\terminal64.exe",
        "C:\Program Files\MetaTrader 5\terminal64.exe"
    )
    foreach ($p in $candidates) {
        if (Test-Path $p) { return $p }
    }
    return ""
}

$dataDir = Find-TerminalDataDir -ServerName $Server
$commonIni = Join-Path $dataDir "config\common.ini"
if (-not (Test-Path $commonIni)) {
    throw "Nie znaleziono: $commonIni"
}

$raw = Get-Content $commonIni -Encoding UTF8
$profileLast = Get-IniValue -Lines $raw -Section "Charts" -Key "ProfileLast"
if ([string]::IsNullOrWhiteSpace($profileLast)) {
    $profileLast = "Default"
}

$lines = [System.Collections.Generic.List[string]]::new()
foreach ($l in $raw) { [void]$lines.Add($l) }

# Wymuszenie ustawień z zakładki Strategie (MT5 -> Opcje -> Strategie)
Set-IniValue -Lines $lines -Section "Experts" -Key "Enabled" -Value "1"
Set-IniValue -Lines $lines -Section "Experts" -Key "AllowDllImport" -Value "1"
Set-IniValue -Lines $lines -Section "Experts" -Key "Account" -Value "0"
Set-IniValue -Lines $lines -Section "Experts" -Key "Profile" -Value "0"
Set-IniValue -Lines $lines -Section "Experts" -Key "Chart" -Value "0"
Set-IniValue -Lines $lines -Section "Experts" -Key "Api" -Value "0"

$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backup = "$commonIni.bak.$timestamp"
Copy-Item -Path $commonIni -Destination $backup -Force
Set-Content -Path $commonIni -Value $lines -Encoding UTF8

Write-Output "MT5_AUTOTRADE_FIX OK"
Write-Output "data_dir=$dataDir"
Write-Output "common_ini=$commonIni"
Write-Output "backup=$backup"
Write-Output "profile=$profileLast"
Write-Output "experts_enabled=1 dll=1 disable_on_account=0 disable_on_profile=0 disable_on_chart=0 disable_by_api=0"

if (-not $NoRestart) {
    $exe = Find-TerminalExe
    if ([string]::IsNullOrWhiteSpace($exe)) {
        Write-Output "restart=SKIP reason=terminal_exe_not_found"
        exit 0
    }
    $procs = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "terminal64.exe" } |
        Select-Object -ExpandProperty ProcessId
    foreach ($procId in $procs) {
        try { Stop-Process -Id $procId -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Seconds 2
    foreach ($procId in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ieq "terminal64.exe" } |
        Select-Object -ExpandProperty ProcessId)) {
        try { Stop-Process -Id $procId -Force -ErrorAction SilentlyContinue } catch {}
    }
    Start-Sleep -Seconds 1
    Start-Process -FilePath $exe -ArgumentList "/profile:$profileLast" | Out-Null
    Write-Output "restart=OK exe=$exe"
}

exit 0
