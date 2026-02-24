param(
    [string]$Root = "C:\OANDA_MT5_SYSTEM",
    [string]$Mt5DataDir = "C:\Users\skite\AppData\Roaming\MetaQuotes\Terminal\47AEB69EDDAD4D73097816C71FB25856",
    [int]$PollMs = 1200
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class WinApi {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);

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
}
"@

function Resolve-RootPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    }
    return (Resolve-Path $Path).Path
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

    $fs = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $fs.Seek($start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $true, 4096, $true)
        try { $txt = $sr.ReadToEnd() } finally { $sr.Dispose() }
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
    $tmp = "$Path.tmp"
    $json = $Object | ConvertTo-Json -Depth 8
    $json | Set-Content -Path $tmp -Encoding UTF8
    Move-Item -Force $tmp $Path
}

function Append-Line {
    param([string]$Path, [string]$Line)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    Add-Content -Path $Path -Value $Line -Encoding UTF8
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
    accepted_events = 0
    rejected_events = 0
    popup_actions = 0
    last_popup_title = ""
    last_popup_action_utc = ""
    last_log_event = ""
    mt5_log = ""
}

[ordered]@{
    pid = $PID
    started = (Get-Date).ToString("o")
    status_path = $statusPath
    event_log = $eventLog
} | ConvertTo-Json | Set-Content -Path $pidPath -Encoding UTF8

Append-Line -Path $eventLog -Line ("[{0}] RISK_GUARD_START pid={1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $PID)

$keywords = @(
    "high risk investment warning",
    "investment warning",
    "high risk",
    "ostrze",
    "ryzyk",
    "warning"
)

$lastActionByHwnd = @{}
$offsets = @{}

while ($true) {
    try {
        $mt5log = Join-Path $Mt5DataDir ("logs\" + (Get-Date -Format "yyyyMMdd") + ".log")
        $state.mt5_log = $mt5log
        $newLines = Read-NewLines -Path $mt5log -Offsets $offsets
        foreach ($line in $newLines) {
            $msg = [string]$line
            if ([string]::IsNullOrWhiteSpace($msg)) { continue }
            if ($msg -match "high risk investment warning has been accepted") {
                $state.accepted_events = [int]$state.accepted_events + 1
                $state.last_log_event = $msg
                Append-Line -Path $eventLog -Line ("[{0}] RISK_WARNING_ACCEPTED {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
            } elseif ($msg -match "high risk investment warning has been rejected") {
                $state.rejected_events = [int]$state.rejected_events + 1
                $state.last_log_event = $msg
                Append-Line -Path $eventLog -Line ("[{0}] RISK_WARNING_REJECTED {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $msg)
            }
        }

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
                $titleLower = $title.ToLowerInvariant()
                $match = $false
                foreach ($k in $keywords) {
                    if ($titleLower.Contains($k)) { $match = $true; break }
                }
                if (-not $match) { continue }

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
                # Enter first (default button), then common Alt shortcuts.
                [System.Windows.Forms.SendKeys]::SendWait("{ENTER}")
                Start-Sleep -Milliseconds 100
                [System.Windows.Forms.SendKeys]::SendWait("%Y")
                Start-Sleep -Milliseconds 80
                [System.Windows.Forms.SendKeys]::SendWait("%A")
                Start-Sleep -Milliseconds 80
                [System.Windows.Forms.SendKeys]::SendWait("%O")

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
