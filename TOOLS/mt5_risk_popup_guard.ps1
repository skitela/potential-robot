param(
    [string]$Root = "C:\MAKRO_I_MIKRO_BOT",
    [string]$Mt5DataDir = "",
    [string[]]$Mt5DataDirs = @(),
    [int]$PollMs = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class WinApi {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);

    public const int BM_GETCHECK = 0x00F0;
    public const int BM_SETCHECK = 0x00F1;
    public const int BM_CLICK = 0x00F5;
    public const int BST_UNCHECKED = 0x0000;
    public const int BST_CHECKED = 0x0001;

    public static List<Tuple<IntPtr, uint, string>> EnumerateTopWindows() {
        var list = new List<Tuple<IntPtr, uint, string>>();
        EnumWindows((h, l) => {
            if (!IsWindowVisible(h)) return true;
            int len = GetWindowTextLength(h);
            if (len <= 0) return true;
            var sb = new StringBuilder(len + 1);
            GetWindowText(h, sb, sb.Capacity);
            uint pid = 0;
            GetWindowThreadProcessId(h, out pid);
            list.Add(Tuple.Create(h, pid, sb.ToString()));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static List<Tuple<IntPtr, string, string>> EnumerateChildWindows(IntPtr parent) {
        var list = new List<Tuple<IntPtr, string, string>>();
        EnumChildWindows(parent, (h, l) => {
            var clsSb = new StringBuilder(256);
            GetClassName(h, clsSb, clsSb.Capacity);
            int len = GetWindowTextLength(h);
            var txtSb = new StringBuilder(len + 1);
            if (len > 0) {
                GetWindowText(h, txtSb, txtSb.Capacity);
            }
            list.Add(Tuple.Create(h, clsSb.ToString(), txtSb.ToString()));
            return true;
        }, IntPtr.Zero);
        return list;
    }
}
"@

function Resolve-RootPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $Path).Path
}

function Resolve-Mt5DataDir {
    param([string]$Preferred = "")
    if (-not [string]::IsNullOrWhiteSpace($Preferred) -and (Test-Path $Preferred)) {
        return (Resolve-Path $Preferred).Path
    }

    $appData = $env:APPDATA
    if ([string]::IsNullOrWhiteSpace($appData)) {
        return ""
    }
    $base = Join-Path $appData "MetaQuotes\Terminal"
    if (-not (Test-Path $base)) {
        return ""
    }

    $bestDir = ""
    $bestScore = -1
    $bestTs = [datetime]::MinValue

    foreach ($d in (Get-ChildItem -Path $base -Directory -ErrorAction SilentlyContinue)) {
        $profileMarker = Join-Path $d.FullName "MQL5\Profiles\Charts\OANDA_HYBRID_AUTO"
        $expertMarkerEx5 = Join-Path $d.FullName "MQL5\Experts\HybridAgent.ex5"
        $expertMarkerMq5 = Join-Path $d.FullName "MQL5\Experts\HybridAgent.mq5"
        $commonIni = Join-Path $d.FullName "config\common.ini"

        $score = 0
        $markerPath = ""
        if (Test-Path $profileMarker) {
            $score += 8
            $markerPath = $profileMarker
        }
        if (Test-Path $expertMarkerEx5) {
            $score += 6
            if ([string]::IsNullOrWhiteSpace($markerPath)) { $markerPath = $expertMarkerEx5 }
        } elseif (Test-Path $expertMarkerMq5) {
            $score += 4
            if ([string]::IsNullOrWhiteSpace($markerPath)) { $markerPath = $expertMarkerMq5 }
        }
        if (Test-Path $commonIni) {
            $score += 2
            if ([string]::IsNullOrWhiteSpace($markerPath)) { $markerPath = $commonIni }
        }
        if ($score -le 0) { continue }

        $ts = [datetime]::MinValue
        try {
            if (-not [string]::IsNullOrWhiteSpace($markerPath)) {
                $ts = (Get-Item $markerPath -ErrorAction Stop).LastWriteTimeUtc
            }
        } catch {
            $ts = [datetime]::MinValue
        }

        if (($score -gt $bestScore) -or (($score -eq $bestScore) -and ($ts -gt $bestTs))) {
            $bestScore = $score
            $bestTs = $ts
            $bestDir = $d.FullName
        }
    }

    return $bestDir
}

function Resolve-Mt5DataDirList {
    param(
        [string]$Primary = "",
        [string[]]$Additional = @()
    )

    $resolved = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @($Primary) + @($Additional)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        if (Test-Path $candidate) {
            $path = (Resolve-Path $candidate).Path
            if (-not $resolved.Contains($path)) {
                [void]$resolved.Add($path)
            }
        }
    }

    if ($resolved.Count -eq 0) {
        $auto = Resolve-Mt5DataDir -Preferred $Primary
        if (-not [string]::IsNullOrWhiteSpace($auto) -and -not $resolved.Contains($auto)) {
            [void]$resolved.Add($auto)
        }
    }

    return @($resolved.ToArray())
}

function Read-NewLines {
    param(
        [string]$Path,
        [hashtable]$Offsets
    )
    if (-not (Test-Path $Path)) {
        return @()
    }
    $len = [int64](Get-Item $Path).Length
    if (-not $Offsets.ContainsKey($Path)) {
        $Offsets[$Path] = $len
        return @()
    }
    $start = [int64]$Offsets[$Path]
    if ($len -lt $start) { $start = 0 }
    if ($len -eq $start) { return @() }

    # StrictMode: referencing an unset variable is an error, so probe existence first.
    if (-not (Get-Variable -Name EncCache -Scope Script -ErrorAction SilentlyContinue)) {
        $Script:EncCache = @{}
    }
    if (-not $Script:EncCache.ContainsKey($Path)) {
        $enc = [System.Text.Encoding]::UTF8
        try {
            $fs0 = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
            try {
                $bom = New-Object byte[] 4
                [void]$fs0.Read($bom, 0, 4)
                if ($bom[0] -eq 0xFF -and $bom[1] -eq 0xFE) { $enc = [System.Text.Encoding]::Unicode }
                elseif ($bom[0] -eq 0xFE -and $bom[1] -eq 0xFF) { $enc = [System.Text.Encoding]::BigEndianUnicode }
                elseif ($bom[0] -eq 0xEF -and $bom[1] -eq 0xBB -and $bom[2] -eq 0xBF) { $enc = [System.Text.Encoding]::UTF8 }
            } finally {
                $fs0.Dispose()
            }
        } catch {
            $enc = [System.Text.Encoding]::UTF8
        }
        $Script:EncCache[$Path] = $enc
    }

    $encUse = [System.Text.Encoding]$Script:EncCache[$Path]
    if (($encUse.WebName -match "utf-16") -and (($start % 2) -ne 0)) {
        $start = [int64]([Math]::Max(0, $start - 1))
    }

    $txt = ""
    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $toRead = [int]([Math]::Max(0, [Math]::Min([int64]2147483647, ($len - $start))))
        if ($toRead -gt 0) {
            $buf = New-Object byte[] $toRead
            $read = $fs.Read($buf, 0, $toRead)
            if ($read -gt 0) {
                if ($read -ne $toRead) { $buf = $buf[0..($read - 1)] }
                $txt = $encUse.GetString($buf)
            }
        }
    } finally {
        $fs.Dispose()
    }
    $Offsets[$Path] = $len
    if ([string]::IsNullOrWhiteSpace($txt)) { return @() }
    return [System.Text.RegularExpressions.Regex]::Split($txt, "\r?\n")
}

function Write-JsonAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Object
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $json = $Object | ConvertTo-Json -Depth 8
    $tmp = [System.IO.Path]::Combine(
        $parent,
        ([System.IO.Path]::GetFileName($Path) + ".tmp." + [guid]::NewGuid().ToString("N"))
    )
    try {
        $json | Set-Content -Path $tmp -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            try {
                [System.IO.File]::Replace($tmp, $Path, $null, $true)
            } catch {
                [System.IO.File]::Copy($tmp, $Path, $true)
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
            }
        } else {
            [System.IO.File]::Move($tmp, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) {
            try { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
}

function Append-Line {
    param([string]$Path, [string]$Line)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Add-Content -Path $Path -Value $Line -Encoding UTF8
}

function Normalize-Text {
    param([string]$Value = "")
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    return $Value.Trim().ToLowerInvariant()
}

function Test-RiskPopupWindow {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Hwnd,
        [Parameter(Mandatory = $true)][string]$Title
    )

    $markers = @(
        "high risk investment warning",
        "high risk warning",
        "ostrzeżenie o ryzyku",
        "ostrzezenie o ryzyku",
        "ryzyku inwestycyjnym",
        "zapoznałem",
        "zapoznalem",
        "i have read and accept"
    )

    $titleNorm = Normalize-Text -Value $Title
    $children = [WinApi]::EnumerateChildWindows($Hwnd)
    $buttonTexts = @()
    $allTexts = @()
    if (-not [string]::IsNullOrWhiteSpace($titleNorm)) {
        $allTexts += $titleNorm
    }

    $hasOkButton = $false
    foreach ($it in $children) {
        $cls = [string]$it.Item2
        $txt = Normalize-Text -Value ([string]$it.Item3)
        if (-not [string]::IsNullOrWhiteSpace($txt)) {
            $allTexts += $txt
        }
        if ($cls -eq "Button") {
            if (-not [string]::IsNullOrWhiteSpace($txt)) { $buttonTexts += $txt }
            if ($txt -match "^(ok|yes|tak)$") {
                $hasOkButton = $true
            }
        }
    }
    if (-not $hasOkButton) {
        return @{
            is_risk_popup = $false
            reason = "no_ok_button"
            matched_marker = ""
            title = $Title
        }
    }

    $joined = ($allTexts -join " | ")
    $matched = ""
    foreach ($m in $markers) {
        if ($joined.Contains($m)) {
            $matched = $m
            break
        }
    }
    if ([string]::IsNullOrWhiteSpace($matched)) {
        return @{
            is_risk_popup = $false
            reason = "marker_not_found"
            matched_marker = ""
            title = $Title
        }
    }
    return @{
        is_risk_popup = $true
        reason = "marker_match"
        matched_marker = $matched
        title = $Title
    }
}

function Invoke-Win32AcceptRiskPopup {
    param(
        [Parameter(Mandatory = $true)][IntPtr]$Hwnd,
        [Parameter(Mandatory = $true)][string]$Title
    )

    try {
        $children = [WinApi]::EnumerateChildWindows($Hwnd)
        $okBtn = $null
        $ackBtn = $null
        $buttonTexts = @()

        foreach ($it in $children) {
            $cls = [string]$it.Item2
            $txt = [string]$it.Item3
            if ($cls -ne "Button") { continue }
            $t = if ($null -eq $txt) { "" } else { [string]$txt }
            $t = $t.Trim()
            if ($t) { $buttonTexts += $t }
            if ($t -match "^(?i)ok$") { $okBtn = $it.Item1; continue }
            if ($t.ToLowerInvariant().Contains("zapozna")) { $ackBtn = $it.Item1; continue }
        }

        if ($null -eq $okBtn) {
            $joined = ($buttonTexts -join "|")
            return @{ ok = $false; mode = "win32"; error = ("no_ok_button texts=" + $joined) }
        }

        if ($null -ne $ackBtn) {
            try {
                $state = [int]([WinApi]::SendMessage($ackBtn, [WinApi]::BM_GETCHECK, [IntPtr]::Zero, [IntPtr]::Zero))
                if ($state -ne [WinApi]::BST_CHECKED) {
                    [void][WinApi]::SendMessage($ackBtn, [WinApi]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
                    Start-Sleep -Milliseconds 80
                }
            } catch {
                # best-effort
            }
        }

        [void][WinApi]::SendMessage($okBtn, [WinApi]::BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
        return @{ ok = $true; mode = "win32_click"; error = "" }
    } catch {
        return @{ ok = $false; mode = "win32"; error = $_.Exception.Message }
    }
}

$runtimeRoot = Resolve-RootPath -Path $Root
$runDir = Join-Path $runtimeRoot "RUN"
$logDir = Join-Path $runtimeRoot "LOGS\monitor"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$statusPath = Join-Path $runDir "mt5_risk_guard_status.json"
$eventLog = Join-Path $logDir "mt5_risk_guard.log"
$pidPath = Join-Path $runDir "mt5_risk_guard.pid"

$state = [ordered]@{
    started_utc = (Get-Date).ToUniversalTime().ToString("o")
    mt5_data_dir = ""
    mt5_data_dirs = @()
    accepted_events = 0
    rejected_events = 0
    popup_actions = 0
    last_popup_title = ""
    last_popup_action_utc = ""
    last_log_event = ""
    mt5_log = ""
    mt5_logs = @()
}

[ordered]@{
    pid = $PID
    started = (Get-Date).ToString("o")
    status_path = $statusPath
    event_log = $eventLog
} | ConvertTo-Json | Set-Content -Path $pidPath -Encoding UTF8

Append-Line -Path $eventLog -Line ("[{0}] RISK_GUARD_START pid={1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $PID)

$mt5DataDirResolvedList = Resolve-Mt5DataDirList -Primary $Mt5DataDir -Additional $Mt5DataDirs
$state.mt5_data_dirs = @($mt5DataDirResolvedList)
$state.mt5_data_dir = if ($mt5DataDirResolvedList.Count -gt 0) { [string]$mt5DataDirResolvedList[0] } else { "" }
$mt5DirLogValue = if ($mt5DataDirResolvedList.Count -eq 0) { "<unresolved>" } else { ($mt5DataDirResolvedList -join "; ") }
Append-Line -Path $eventLog -Line ("[{0}] RISK_GUARD_MT5_DIRS dirs={1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $mt5DirLogValue)

$lastActionByHwnd = @{}
$offsets = @{}

while ($true) {
    try {
        $needsRefresh = ($mt5DataDirResolvedList.Count -eq 0)
        if (-not $needsRefresh) {
            foreach ($dir in $mt5DataDirResolvedList) {
                if ([string]::IsNullOrWhiteSpace($dir) -or (-not (Test-Path $dir))) {
                    $needsRefresh = $true
                    break
                }
            }
        }

        if ($needsRefresh) {
            $mt5DataDirResolvedList = Resolve-Mt5DataDirList -Primary $Mt5DataDir -Additional $Mt5DataDirs
            $state.mt5_data_dirs = @($mt5DataDirResolvedList)
            $state.mt5_data_dir = if ($mt5DataDirResolvedList.Count -gt 0) { [string]$mt5DataDirResolvedList[0] } else { "" }
        }

        $currentLogs = New-Object System.Collections.Generic.List[string]
        foreach ($resolvedDir in @($mt5DataDirResolvedList)) {
            if ([string]::IsNullOrWhiteSpace($resolvedDir)) {
                continue
            }

            $mt5log = Join-Path $resolvedDir ("logs\" + (Get-Date -Format "yyyyMMdd") + ".log")
            [void]$currentLogs.Add($mt5log)
            $newLines = Read-NewLines -Path $mt5log -Offsets $offsets
            foreach ($line in $newLines) {
                $msg = [string]$line
                if ([string]::IsNullOrWhiteSpace($msg)) { continue }
                if ($msg -match "high risk investment warning has been accepted") {
                    $state.accepted_events = [int]$state.accepted_events + 1
                    $state.last_log_event = $msg
                    Append-Line -Path $eventLog -Line ("[{0}] RISK_WARNING_ACCEPTED dir={1} {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $resolvedDir, $msg)
                } elseif ($msg -match "high risk investment warning has been rejected") {
                    $state.rejected_events = [int]$state.rejected_events + 1
                    $state.last_log_event = $msg
                    Append-Line -Path $eventLog -Line ("[{0}] RISK_WARNING_REJECTED dir={1} {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $resolvedDir, $msg)
                }
            }
        }
        $state.mt5_logs = @($currentLogs.ToArray())
        $state.mt5_log = if ($currentLogs.Count -gt 0) { [string]$currentLogs[0] } else { "" }

        $terminalPids = @(
            Get-Process -Name "terminal64" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id
        )
        if ($terminalPids.Count -gt 0) {
            $wins = [WinApi]::EnumerateTopWindows()
            foreach ($w in $wins) {
                $wndPid = [int]$w.Item2
                if (-not ($terminalPids -contains $wndPid)) { continue }
                $title = [string]$w.Item3
                if ([string]::IsNullOrWhiteSpace($title)) { continue }
                $candidate = Test-RiskPopupWindow -Hwnd $w.Item1 -Title $title
                if (-not [bool]$candidate.is_risk_popup) { continue }

                $hwnd = $w.Item1
                $hwndKey = $hwnd.ToString()
                $now = Get-Date
                $canAct = $true
                if ($lastActionByHwnd.ContainsKey($hwndKey)) {
                    $sec = [double]($now - [datetime]$lastActionByHwnd[$hwndKey]).TotalSeconds
                    if ($sec -lt 10.0) { $canAct = $false }
                }
                if (-not $canAct) { continue }

                [WinApi]::SetForegroundWindow($hwnd) | Out-Null
                Start-Sleep -Milliseconds 120

                $res = Invoke-Win32AcceptRiskPopup -Hwnd $hwnd -Title $title
                if (-not [bool]$res.ok) {
                    Append-Line -Path $eventLog -Line ("[{0}] POPUP_ACCEPT_FAIL title=""{1}"" pid={2} hwnd={3} marker={4} mode={5} err={6}" -f `
                        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $title, $wndPid, $hwndKey, [string]$candidate.matched_marker, $res.mode, $res.error)
                } else {
                    Append-Line -Path $eventLog -Line ("[{0}] POPUP_ACCEPT_OK title=""{1}"" pid={2} hwnd={3} marker={4} mode={5}" -f `
                        (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $title, $wndPid, $hwndKey, [string]$candidate.matched_marker, $res.mode)
                }

                $lastActionByHwnd[$hwndKey] = $now
                $state.popup_actions = [int]$state.popup_actions + 1
                $state.last_popup_title = $title
                $state.last_popup_action_utc = $now.ToUniversalTime().ToString("o")
                Append-Line -Path $eventLog -Line ([string]::Format(
                    "[{0}] POPUP_ACTION title=""{1}"" pid={2} hwnd={3}",
                    $now.ToString("yyyy-MM-dd HH:mm:ss"),
                    $title,
                    $wndPid,
                    $hwndKey
                ))
            }
        }

        $state.ts_utc = (Get-Date).ToUniversalTime().ToString("o")
        Write-JsonAtomic -Path $statusPath -Object $state
    } catch {
        Append-Line -Path $eventLog -Line ("[{0}] GUARD_ERR {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $_.Exception.Message)
    }

    Start-Sleep -Milliseconds ([Math]::Max(300, [int]$PollMs))
}
