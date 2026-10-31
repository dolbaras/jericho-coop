# Looks at the stub's error boxes (the only UI it has): builds test exes from a tiny zip whose installer just exits with 3 (so the
# installer's start flag never appears: "the installer window did not start"), one per language (-DFORCE_LANG), takes a picture of
# each box (PrintWindow, nothing clicked), closes it with WM_CLOSE and joins the pictures into one PNG. Also the "damaged" box
# (a flipped payload byte) and the "could not unpack" box (TEMP pointing nowhere) in the PC's own language.
# Usage: test_boxes.ps1 -Out <png> [-Work <folder>]
param([Parameter(Mandatory)] [string] $Out, [string] $Work = (Join-Path ([IO.Path]::GetTempPath()) "mkinstaller-boxes"))
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms, System.Drawing, System.IO.Compression.FileSystem
Add-Type @"
using System; using System.Runtime.InteropServices; using System.Text;
public class BW {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int hh, uint f);
  [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr dc, uint f);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@
$here = $PSScriptRoot
New-Item -ItemType Directory -Force $Work | Out-Null
$zip = Join-Path $Work "tiny.zip"
Remove-Item $zip -ErrorAction SilentlyContinue
$z = [IO.Compression.ZipFile]::Open($zip, "Create")
$e = $z.CreateEntry("coop-installer.ps1"); $s = New-Object IO.StreamWriter($e.Open()); $s.Write("exit 3`r`n"); $s.Close()
$z.Dispose()
$scr = [Windows.Forms.Screen]::AllScreens | Where-Object { -not $_.Primary } | Select-Object -First 1

function Shoot($exe, $title, [hashtable] $env = @{}) {
    $old = @{}; foreach ($k in $env.Keys) { $old[$k] = [Environment]::GetEnvironmentVariable($k); [Environment]::SetEnvironmentVariable($k, $env[$k]) }
    try { $p = Start-Process -FilePath $exe -PassThru } finally { foreach ($k in $env.Keys) { [Environment]::SetEnvironmentVariable($k, $old[$k]) } }
    $script:hw = [IntPtr]::Zero
    for ($i = 0; $i -lt 40 -and $script:hw -eq [IntPtr]::Zero; $i++) {
        Start-Sleep -Milliseconds 250
        [void][BW]::EnumWindows({ param($h, $l)
            if ([BW]::IsWindowVisible($h)) { $pid2 = 0; [void][BW]::GetWindowThreadProcessId($h, [ref]$pid2); if ($pid2 -eq $p.Id) { $script:hw = $h } }
            $true }, [IntPtr]::Zero)
    }
    if ($script:hw -eq [IntPtr]::Zero) { Stop-Process -Id $p.Id -ErrorAction SilentlyContinue; return $null }
    if ($scr) { [void][BW]::SetWindowPos($script:hw, [IntPtr]::Zero, $scr.WorkingArea.X + 80, $scr.WorkingArea.Y + 80, 0, 0, 0x0001 -bor 0x0004) }
    Start-Sleep -Milliseconds 400
    $r = New-Object BW+RECT; [void][BW]::GetWindowRect($script:hw, [ref]$r)
    $w = $r.R - $r.L; $hh = $r.B - $r.T
    $bmp = New-Object Drawing.Bitmap($w, $hh)
    $g = [Drawing.Graphics]::FromImage($bmp); $dc = $g.GetHdc(); [void][BW]::PrintWindow($script:hw, $dc, 2); $g.ReleaseHdc($dc); $g.Dispose()
    [void][BW]::PostMessage($script:hw, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $p.WaitForExit(15000)) { Stop-Process -Id $p.Id -Force }
    $script:boxExit = $p.ExitCode
    $bmp
}
$pics = @()
$labels = @("en", "ru", "de", "fr", "es", "it")
for ($l = 0; $l -lt 6; $l++) {
    $exe = Join-Path $Work "box-$l.exe"
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here "mkinstaller.ps1") -Zip $zip -Out $exe -Product "Test Co-op" -Version 1.0.0 -TempPrefix "mkinstaller-test" -CFlags "-DFORCE_LANG=$l" | Out-Null
    $b = Shoot $exe "Test Co-op"
    if ($b) { $pics += , @("not started / $($labels[$l]) (exit $script:boxExit)", $b) } else { "no box for language $l" }
}
# damaged: flip a byte near the end of the exe (inside the payload resource), PE headers stay valid
$exe = Join-Path $Work "box-0.exe"; $bad = Join-Path $Work "damaged.exe"
$bytes = [IO.File]::ReadAllBytes($exe)
$at = -1; for ($k = 0; $k -lt $bytes.Length - 4; $k++) { if ($bytes[$k] -eq 0x50 -and $bytes[$k + 1] -eq 0x4B -and $bytes[$k + 2] -eq 3 -and $bytes[$k + 3] -eq 4) { $at = $k } }   # (the last one: the stub's own code holds the same four bytes as a constant)
if ($at -lt 0) { throw "payload not found" }
$bytes[$at + 45] = $bytes[$at + 45] -bxor 0xFF   # (inside the zip: its local header and file name)
[IO.File]::WriteAllBytes($bad, $bytes)
$b = Shoot $bad "Test Co-op"; if ($b) { $pics += , @("damaged (exit $script:boxExit)", $b) } else { "no box for the damaged exe" }
# could not unpack: TEMP in a folder that does not exist
$b = Shoot $exe "Test Co-op" @{ TEMP = "Z:\no such folder\"; TMP = "Z:\no such folder\" }; if ($b) { $pics += , @("unpack failed (exit $script:boxExit)", $b) } else { "no box for the unpack failure" }

# one sheet
$W = ($pics | ForEach-Object { $_[1].Width } | Measure-Object -Maximum).Maximum
$cols = 2; $rows = [Math]::Ceiling($pics.Count / $cols)
$cellH = ($pics | ForEach-Object { $_[1].Height } | Measure-Object -Maximum).Maximum + 24
$sheet = New-Object Drawing.Bitmap([int]($W * $cols + 10), [int]($cellH * $rows + 10))
$g = [Drawing.Graphics]::FromImage($sheet); $g.Clear([Drawing.Color]::FromArgb(40, 40, 44))
$f = New-Object Drawing.Font("Segoe UI", 9)
for ($i = 0; $i -lt $pics.Count; $i++) {
    $x = 5 + ($i % $cols) * $W; $y = 5 + [Math]::Floor($i / $cols) * $cellH
    $g.DrawString($pics[$i][0], $f, [Drawing.Brushes]::White, $x, $y)
    $g.DrawImage($pics[$i][1], $x, $y + 18)
}
$g.Dispose(); $sheet.Save($Out, [Drawing.Imaging.ImageFormat]::Png); $sheet.Dispose()
"sheet: $Out ($($pics.Count) boxes)"
