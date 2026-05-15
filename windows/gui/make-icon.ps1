$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$size = 64
$bitmap = New-Object Drawing.Bitmap $size, $size
$g = [Drawing.Graphics]::FromImage($bitmap)
$g.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias

$bg = [Drawing.Color]::FromArgb(18, 34, 31)
$teal = [Drawing.Color]::FromArgb(15, 118, 110)
$mint = [Drawing.Color]::FromArgb(122, 225, 205)
$gold = [Drawing.Color]::FromArgb(245, 183, 76)
$white = [Drawing.Color]::FromArgb(246, 252, 249)

$g.Clear([Drawing.Color]::Transparent)
$rect = New-Object Drawing.Rectangle 2, 2, 60, 60
$path = New-Object Drawing.Drawing2D.GraphicsPath
$radius = 14
$d = $radius * 2
$path.AddArc($rect.Left, $rect.Top, $d, $d, 180, 90)
$path.AddArc($rect.Right - $d, $rect.Top, $d, $d, 270, 90)
$path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
$path.AddArc($rect.Left, $rect.Bottom - $d, $d, $d, 90, 90)
$path.CloseFigure()
$g.FillPath((New-Object Drawing.SolidBrush $bg), $path)

$chip = New-Object Drawing.Rectangle 18, 24, 28, 20
$g.FillRectangle((New-Object Drawing.SolidBrush $teal), $chip)
$g.DrawRectangle((New-Object Drawing.Pen $white, 2), $chip)

$pen = New-Object Drawing.Pen $mint, 3
$g.DrawLine($pen, 32, 24, 32, 14)
$g.DrawLine($pen, 22, 24, 14, 15)
$g.DrawLine($pen, 42, 24, 50, 15)
$g.DrawLine($pen, 32, 44, 32, 53)
$g.DrawLine($pen, 18, 34, 9, 34)
$g.DrawLine($pen, 46, 34, 55, 34)

$brush = New-Object Drawing.SolidBrush $gold
foreach ($pt in @(@(32, 12), @(13, 14), @(51, 14), @(32, 54), @(8, 34), @(56, 34))) {
    $g.FillEllipse($brush, $pt[0] - 4, $pt[1] - 4, 8, 8)
}

$iconPath = Join-Path $PSScriptRoot "rpi-netboot.ico"
$handle = $bitmap.GetHicon()
$icon = [Drawing.Icon]::FromHandle($handle)
$fs = [IO.File]::Open($iconPath, [IO.FileMode]::Create)
$icon.Save($fs)
$fs.Dispose()
$icon.Dispose()
$g.Dispose()
$bitmap.Dispose()

Get-Item $iconPath
