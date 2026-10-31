# Draws the setup exe's icon (our own art, nothing from a game): a rounded tile in the product's accent colour, two players
# (head and shoulders, the one behind a little higher and paler: the same badge the installers put on the game's shortcut icon)
# and a small arrow into a tray ("install"). Writes an .ico with 16, 24, 32, 48, 64, 128 and 256 px frames (256 as PNG, the
# others as 32-bit DIBs, which both the shell and .NET's Icon read).
# Usage: powershell -File make_icon.ps1 -Out app.ico -Accent 227cce
param([Parameter(Mandatory)] [string] $Out, [string] $Accent = "227cce")
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
$ac = [Drawing.Color]::FromArgb([Convert]::ToInt32($Accent.TrimStart('#'), 16) -bor 0xFF000000)
function Mix($a, $b, $t) { [Drawing.Color]::FromArgb(255, [int]($a.R + ($b.R - $a.R) * $t), [int]($a.G + ($b.G - $a.G) * $t), [int]($a.B + ($b.B - $a.B) * $t)) }
$dark = Mix $ac ([Drawing.Color]::Black) 0.62

function Draw($size) {
    $bmp = New-Object Drawing.Bitmap($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = "AntiAlias"; $g.PixelOffsetMode = "HighQuality"
    $s = [single]$size
    $m = [single]($s * 0.04); $w = $s - 2 * $m; $r = $s * 0.20
    $tile = New-Object Drawing.Drawing2D.GraphicsPath
    $tile.AddArc($m, $m, $r, $r, 180, 90); $tile.AddArc($m + $w - $r, $m, $r, $r, 270, 90)
    $tile.AddArc($m + $w - $r, $m + $w - $r, $r, $r, 0, 90); $tile.AddArc($m, $m + $w - $r, $r, $r, 90, 90); $tile.CloseFigure()
    $grad = New-Object Drawing.Drawing2D.LinearGradientBrush((New-Object Drawing.PointF(0, 0)), (New-Object Drawing.PointF(0, $s)), (Mix $ac ([Drawing.Color]::White) 0.18), $dark)
    $g.FillPath($grad, $tile)
    $pen = New-Object Drawing.Pen([Drawing.Color]::FromArgb(90, 255, 255, 255), [single][Math]::Max(1, $s / 64))
    $g.DrawPath($pen, $tile)
    $u = $s / 16
    # the two players
    foreach ($f in @(@(9.6, 2.0, [Drawing.Color]::FromArgb(190, 218, 246)), @(6.4, 2.8, [Drawing.Color]::White))) {
        $br = New-Object Drawing.SolidBrush($f[2])
        $cx = $f[0] * $u; $top = $f[1] * $u
        $g.FillEllipse($br, [single]($cx - 1.9 * $u), [single]$top, [single](3.8 * $u), [single](3.8 * $u))
        $path = New-Object Drawing.Drawing2D.GraphicsPath
        $path.AddPie([single]($cx - 3.6 * $u), [single]($top + 4.2 * $u), [single](7.2 * $u), [single](6.4 * $u), [single]180, [single]180)
        $g.FillPath($br, $path)
        $path.Dispose(); $br.Dispose()
    }
    # the arrow into a tray, lower right on a dark disc
    $d = $s * 0.46; $x = $s - $d - $s * 0.05; $y = $s - $d - $s * 0.05
    $g.FillEllipse((New-Object Drawing.SolidBrush([Drawing.Color]::FromArgb(14, 20, 30))), [single]$x, [single]$y, [single]$d, [single]$d)
    $g.FillEllipse((New-Object Drawing.SolidBrush($ac)), [single]($x + $s / 40), [single]($y + $s / 40), [single]($d - $s / 20), [single]($d - $s / 20))
    $wp = New-Object Drawing.Pen([Drawing.Color]::White, [single][Math]::Max(1.2, $s / 20))
    $wp.StartCap = "Round"; $wp.EndCap = "Round"; $wp.LineJoin = "Round"
    $cx = $x + $d / 2; $a = $d / 10
    $g.DrawLine($wp, [single]$cx, [single]($y + 2.6 * $a), [single]$cx, [single]($y + 6.0 * $a))
    $g.DrawLines($wp, [Drawing.PointF[]]@((New-Object Drawing.PointF([single]($cx - 1.9 * $a), [single]($y + 4.2 * $a))), (New-Object Drawing.PointF([single]$cx, [single]($y + 6.2 * $a))), (New-Object Drawing.PointF([single]($cx + 1.9 * $a), [single]($y + 4.2 * $a)))))
    $g.DrawLines($wp, [Drawing.PointF[]]@((New-Object Drawing.PointF([single]($cx - 2.6 * $a), [single]($y + 7.3 * $a))), (New-Object Drawing.PointF([single]($cx + 2.6 * $a), [single]($y + 7.3 * $a)))))
    $g.Dispose()
    $bmp
}

$blobs = @()
foreach ($size in 16, 24, 32, 48, 64, 128, 256) {
    $bmp = Draw $size
    $p = New-Object IO.MemoryStream
    if ($size -ge 256) { $bmp.Save($p, [Drawing.Imaging.ImageFormat]::Png) } else {
        $bw = New-Object IO.BinaryWriter($p)
        $mask = [int]([Math]::Ceiling($size / 32.0) * 4)
        $bw.Write([UInt32]40); $bw.Write([Int32]$size); $bw.Write([Int32](2 * $size)); $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]0); $bw.Write([UInt32]($size * $size * 4 + $mask * $size))
        $bw.Write([Int32]0); $bw.Write([Int32]0); $bw.Write([UInt32]0); $bw.Write([UInt32]0)
        $data = $bmp.LockBits((New-Object Drawing.Rectangle(0, 0, $size, $size)), [Drawing.Imaging.ImageLockMode]::ReadOnly, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $px = New-Object byte[] ($data.Stride * $size)
        [Runtime.InteropServices.Marshal]::Copy($data.Scan0, $px, 0, $px.Length)
        $bmp.UnlockBits($data)
        for ($row = $size - 1; $row -ge 0; $row--) { $bw.Write($px, $row * $data.Stride, $size * 4) }
        $bw.Write((New-Object byte[] ($mask * $size)))
        $bw.Flush()
    }
    $blobs += , @($size, $p.ToArray())
    $bmp.Dispose()
}
$ms = New-Object IO.MemoryStream
$w = New-Object IO.BinaryWriter($ms)
$w.Write([UInt16]0); $w.Write([UInt16]1); $w.Write([UInt16]$blobs.Count)
$off = 6 + 16 * $blobs.Count
foreach ($b in $blobs) {
    $size = $b[0]
    $w.Write([byte]$(if ($size -ge 256) { 0 } else { $size })); $w.Write([byte]$(if ($size -ge 256) { 0 } else { $size }))
    $w.Write([byte]0); $w.Write([byte]0); $w.Write([UInt16]1); $w.Write([UInt16]32)
    $w.Write([UInt32]$b[1].Length); $w.Write([UInt32]$off)
    $off += $b[1].Length
}
foreach ($b in $blobs) { $w.Write($b[1]) }
$w.Flush()
[IO.File]::WriteAllBytes($Out, $ms.ToArray())
"icon $Out ($($ms.Length) bytes)"
