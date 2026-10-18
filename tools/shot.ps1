# Screenshot the main window of each running Jericho.exe with PrintWindow
# (PW_RENDERFULLCONTENT), so windows covering it do not end up in the picture and the
# game window is never activated.
# Usage: shot.ps1 -OutDir <dir> [-Tag name]
param([Parameter(Mandatory)] [string] $OutDir, [string] $Tag = "shot")
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public struct RECT { public int L, T, R, B; }
public static class ShotWin {
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint flags);
}
"@
New-Item -ItemType Directory -Force $OutDir | Out-Null
foreach ($p in Get-Process Jericho -ErrorAction SilentlyContinue) {
    # A hung game window would block PrintWindow, so skip it.
    if ($p.MainWindowHandle -eq 0 -or -not $p.Responding) { continue }
    $r = New-Object RECT
    [ShotWin]::GetWindowRect($p.MainWindowHandle, [ref]$r) | Out-Null
    $w = $r.R - $r.L; $h = $r.B - $r.T
    if ($w -le 0 -or $h -le 0) { continue }
    $bmp = New-Object System.Drawing.Bitmap $w, $h
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $hdc = $g.GetHdc()
    [ShotWin]::PrintWindow($p.MainWindowHandle, $hdc, 2) | Out-Null
    $g.ReleaseHdc($hdc)
    # Never copy the screen area as a fallback: other windows (the owner's chats) can lie on
    # top of the game and would end up in the picture. In-game capture: JERICHO_RECORD.
    $f = Join-Path $OutDir ("{0}_{1}_{2:HHmmss}.png" -f $Tag, $p.Id, (Get-Date))
    $bmp.Save($f, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    $f
}
