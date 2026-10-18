# Start a process on a separate (hidden) Windows desktop.
# Jericho refuses a second instance by FindWindowA("MercuryGameClass"), which only sees
# windows on the caller's desktop, so test clients run on their own desktop.
# Usage: launch_on_desktop.ps1 -Desktop JerichoBot1 -Exe <path> -Args "<args>" -WorkDir <dir>
param(
    [Parameter(Mandatory)] [string] $Desktop,
    [Parameter(Mandatory)] [string] $Exe,
    [string] $Args = "",
    [Parameter(Mandatory)] [string] $WorkDir
)

Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class DesktopLauncher {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    struct STARTUPINFO {
        public int cb; public string lpReserved; public string lpDesktop; public string lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateDesktop(string name, IntPtr dev, IntPtr devmode, int flags, uint access, IntPtr sa);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string app, string cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags,
        IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    public static int Start(string desktop, string exe, string args, string dir) {
        const uint GENERIC_ALL = 0x10000000;
        if (CreateDesktop(desktop, IntPtr.Zero, IntPtr.Zero, 0, GENERIC_ALL, IntPtr.Zero) == IntPtr.Zero)
            throw new System.ComponentModel.Win32Exception();
        var si = new STARTUPINFO();
        si.cb = Marshal.SizeOf(si);
        si.lpDesktop = desktop;
        PROCESS_INFORMATION pi;
        if (!CreateProcess(exe, "\"" + exe + "\" " + args, IntPtr.Zero, IntPtr.Zero, false, 0, IntPtr.Zero, dir, ref si, out pi))
            throw new System.ComponentModel.Win32Exception();
        CloseHandle(pi.hThread); CloseHandle(pi.hProcess);
        return pi.dwProcessId;
    }
}
"@

[DesktopLauncher]::Start($Desktop, $Exe, $Args, $WorkDir)
