Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class MonitorControl {
    [DllImport("user32.dll", SetLastError=true)]
    public static extern IntPtr SendMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);
    public static readonly IntPtr HWND_BROADCAST = new IntPtr(0xffff);
    public const uint WM_SYSCOMMAND = 0x0112;
    public const uint SC_MONITORPOWER = 0xF170;
}
"@
[MonitorControl]::SendMessage([MonitorControl]::HWND_BROADCAST, [MonitorControl]::WM_SYSCOMMAND, [IntPtr]::new([int][MonitorControl]::SC_MONITORPOWER), [IntPtr]::new(2)) | Out-Null
