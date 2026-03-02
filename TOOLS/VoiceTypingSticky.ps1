param(
    [int]$PollMs = 250,
    [int]$AutoOpenCooldownMs = 1800,
    [switch]$DisableAutoOpen,
    [switch]$NoTopMost
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:WorkspaceRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$script:StopFlagPath = Join-Path $script:WorkspaceRoot "RUN\\voice_typing_sticky.stop"

Add-Type -AssemblyName UIAutomationClient

$winApi = @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class VoiceWinApi {
    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int maxCount);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder className, int maxCount);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint flags);
    [DllImport("user32.dll", SetLastError=true)] public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
    public const UInt32 SWP_NOSIZE = 0x0001;
    public const UInt32 SWP_NOMOVE = 0x0002;
    public const UInt32 SWP_NOACTIVATE = 0x0010;
    public const UInt32 SWP_SHOWWINDOW = 0x0040;
    public const UInt32 KEYEVENTF_KEYUP = 0x0002;
    public const byte VK_LWIN = 0x5B;
    public const byte VK_H = 0x48;

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    public static void SendWinH() {
        keybd_event(VK_LWIN, 0, 0, UIntPtr.Zero);
        keybd_event(VK_H, 0, 0, UIntPtr.Zero);
        keybd_event(VK_H, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
        keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, UIntPtr.Zero);
    }
}
'@
Add-Type -TypeDefinition $winApi -ErrorAction SilentlyContinue

function Test-StopRequested {
    return (Test-Path -LiteralPath $script:StopFlagPath)
}

function Get-TextInputHostPids {
    $procs = Get-Process -Name "TextInputHost" -ErrorAction SilentlyContinue
    if (-not $procs) { return @() }
    return @($procs | ForEach-Object { [int]$_.Id })
}

function Get-TopLevelWindowsByPid {
    param([int]$TargetPid)

    $rows = New-Object System.Collections.Generic.List[object]
    $callback = [VoiceWinApi+EnumWindowsProc]{
        param([IntPtr]$hWnd, [IntPtr]$lParam)

        if (-not [VoiceWinApi]::IsWindowVisible($hWnd)) {
            return $true
        }

        [uint32]$procIdOut = 0
        [void][VoiceWinApi]::GetWindowThreadProcessId($hWnd, [ref]$procIdOut)
        if ([int]$procIdOut -ne $TargetPid) {
            return $true
        }

        $len = [VoiceWinApi]::GetWindowTextLength($hWnd)
        $titleSb = New-Object System.Text.StringBuilder ($len + 2)
        [void][VoiceWinApi]::GetWindowText($hWnd, $titleSb, $titleSb.Capacity)
        $title = $titleSb.ToString()

        $classSb = New-Object System.Text.StringBuilder 256
        [void][VoiceWinApi]::GetClassName($hWnd, $classSb, $classSb.Capacity)
        $cls = $classSb.ToString()

        $rect = New-Object VoiceWinApi+RECT
        [void][VoiceWinApi]::GetWindowRect($hWnd, [ref]$rect)
        $width = [Math]::Max(0, $rect.Right - $rect.Left)
        $height = [Math]::Max(0, $rect.Bottom - $rect.Top)

        $rows.Add([pscustomobject]@{
            Handle = $hWnd
            Title = $title
            Class = $cls
            Width = [int]$width
            Height = [int]$height
        })
        return $true
    }

    [void][VoiceWinApi]::EnumWindows($callback, [IntPtr]::Zero)
    return @($rows.ToArray())
}

function Get-VoiceTypingWindow {
    $voiceTitleRegex = '(?i)(voice\\s*typing|dictation|pisanie|dyktowanie)'
    $fallbackClassRegex = '(?i)(Windows\\.UI\\.Core|Xaml|ApplicationFrameWindow)'
    $candidates = New-Object System.Collections.Generic.List[object]

    foreach ($pidItem in (Get-TextInputHostPids)) {
        $wins = Get-TopLevelWindowsByPid -TargetPid $pidItem
        foreach ($w in $wins) {
            $candidates.Add($w)
        }
    }

    if ($candidates.Count -eq 0) {
        return $null
    }

    $explicit = @($candidates | Where-Object { $_.Title -match $voiceTitleRegex })
    if ($explicit.Count -gt 0) {
        return $explicit[0]
    }

    # Fallback: small host window from TextInputHost.
    $fallback = @(
        $candidates | Where-Object {
            $_.Class -match $fallbackClassRegex -and
            $_.Width -gt 100 -and $_.Width -lt 1200 -and
            $_.Height -gt 40 -and $_.Height -lt 500
        }
    )
    if ($fallback.Count -gt 0) {
        return $fallback[0]
    }

    return $null
}

function Set-TopMost {
    param([IntPtr]$Handle)
    if ($Handle -eq [IntPtr]::Zero) { return }
    [void][VoiceWinApi]::SetWindowPos(
        $Handle,
        [VoiceWinApi]::HWND_TOPMOST,
        0, 0, 0, 0,
        ([VoiceWinApi]::SWP_NOMOVE -bor [VoiceWinApi]::SWP_NOSIZE -bor [VoiceWinApi]::SWP_NOACTIVATE -bor [VoiceWinApi]::SWP_SHOWWINDOW)
    )
}

function Test-FocusedElementIsEditable {
    try {
        $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
        if ($null -eq $focused) { return $false }

        $isEnabled = [bool]$focused.Current.IsEnabled
        if (-not $isEnabled) { return $false }

        $isPassword = [bool]$focused.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsPasswordProperty)
        if ($isPassword) { return $false }

        $ct = [string]$focused.Current.ControlType.ProgrammaticName
        if ($ct -eq "ControlType.Edit" -or $ct -eq "ControlType.Document") {
            return $true
        }

        $hasTextPattern = [bool]$focused.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsTextPatternAvailableProperty)
        $hasValuePattern = [bool]$focused.GetCurrentPropertyValue([System.Windows.Automation.AutomationElement]::IsValuePatternAvailableProperty)
        return ($hasTextPattern -or $hasValuePattern)
    }
    catch {
        return $false
    }
}

if (Test-StopRequested) {
    Remove-Item -LiteralPath $script:StopFlagPath -Force -ErrorAction SilentlyContinue
}

$lastAutoOpen = [datetime]::MinValue

while ($true) {
    if (Test-StopRequested) {
        Remove-Item -LiteralPath $script:StopFlagPath -Force -ErrorAction SilentlyContinue
        break
    }

    $voiceWin = Get-VoiceTypingWindow
    if ($voiceWin -and -not $NoTopMost) {
        Set-TopMost -Handle ([IntPtr]$voiceWin.Handle)
    }

    if (-not $DisableAutoOpen) {
        $editable = Test-FocusedElementIsEditable
        if ($editable -and -not $voiceWin) {
            $elapsed = ([datetime]::UtcNow - $lastAutoOpen).TotalMilliseconds
            if ($elapsed -ge [double]$AutoOpenCooldownMs) {
                [VoiceWinApi]::SendWinH()
                $lastAutoOpen = [datetime]::UtcNow
            }
        }
    }

    Start-Sleep -Milliseconds ([Math]::Max(120, [int]$PollMs))
}
