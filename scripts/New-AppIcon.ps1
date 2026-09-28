<#
.SYNOPSIS
  3D-AI deterministic app icon generator (no external assets).
.DESCRIPTION
  System.Drawing ile 256px master cizip 16/24/32/48/64/128/256 PNG-girdili
  ICO uretir: assets/app.ico (+ onizleme assets/app-256.png).
  Marka dili: dark industrial + cyan katmanlar (FDM layer + AI node).
  Tamamen deterministik; calistir: powershell -File scripts\New-AppIcon.ps1
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Assets = Join-Path $Root "assets"
New-Item -ItemType Directory -Force -Path $Assets | Out-Null
$IcoPath = Join-Path $Assets "app.ico"
$PngPath = Join-Path $Assets "app-256.png"

Add-Type -AssemblyName System.Drawing

function New-IconBitmap($size) {
  $bmp = New-Object System.Drawing.Bitmap($size, $size)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $u = $size / 256.0
  # Govde: graphite rounded square
  $bg = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 35, 43, 58))
  $br = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 58, 70, 94))
  $rect = New-Object System.Drawing.RectangleF((8 * $u), (8 * $u), (240 * $u), (240 * $u))
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = 44 * $u
  $path.AddArc($rect.X, $rect.Y, $r, $r, 180, 90)
  $path.AddArc($rect.Right - $r, $rect.Y, $r, $r, 270, 90)
  $path.AddArc($rect.Right - $r, $rect.Bottom - $r, $r, $r, 0, 90)
  $path.AddArc($rect.X, $rect.Bottom - $r, $r, $r, 90, 90)
  $path.CloseFigure()
  $g.FillPath($bg, $path)
  $pen = New-Object System.Drawing.Pen($br, ([Math]::Max(2.0, (5 * $u))))
  $g.DrawPath($pen, $path)
  # Katmanlar: 3 izometrik bar (alttan uste koyudan aciga cyan)
  $cols = @(
    [System.Drawing.Color]::FromArgb(255, 3, 105, 161),
    [System.Drawing.Color]::FromArgb(255, 14, 165, 233),
    [System.Drawing.Color]::FromArgb(255, 34, 211, 238)
  )
  $cy = @(168, 122, 76)
  for ($li = 0; $li -lt 3; $li++) {
    $br2 = New-Object System.Drawing.SolidBrush($cols[$li])
    $y = $cy[$li] * $u
    $h = 30 * $u
    $pts = @(
      (New-Object System.Drawing.PointF((52 * $u), ($y + $h))),
      (New-Object System.Drawing.PointF((128 * $u), ($y + $h + (14 * $u)))),
      (New-Object System.Drawing.PointF((204 * $u), ($y + $h))),
      (New-Object System.Drawing.PointF((204 * $u), $y)),
      (New-Object System.Drawing.PointF((128 * $u), ($y + (14 * $u)))),
      (New-Object System.Drawing.PointF((52 * $u), $y))
    )
    $g.FillPolygon($br2, $pts)
    $br2.Dispose()
  }
  # AI node: sag ustte amber nokta + baglanti cizgisi
  $node = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 251, 191, 36))
  $nd = 26 * $u
  $g.FillEllipse($node, ((196 * $u) - $nd / 2), ((44 * $u) - $nd / 2), $nd, $nd)
  $node.Dispose()
  $bg.Dispose(); $br.Dispose(); $pen.Dispose(); $path.Dispose()
  $g.Dispose()
  return $bmp
}

$master = New-IconBitmap 256
$master.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)

# ICO: PNG-girdili multi-size (Vista+ uyumlu, csc /win32icon + WinForms Icon destekler)
$sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngs = @()
foreach ($sz in $sizes) {
  if ($sz -eq 256) { $b = $master }
  else { $b = New-IconBitmap $sz }
  $ms = New-Object System.IO.MemoryStream
  $b.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
  $pngs += @{ size = $sz; bytes = $ms.ToArray() }
  $ms.Dispose()
  if ($sz -ne 256) { $b.Dispose() }
}
$fs = [System.IO.File]::Create($IcoPath)
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([uint16]0); $bw.Write([uint16]1); $bw.Write([uint16]$pngs.Count)
$off = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
  $w = $p.size; if ($w -ge 256) { $w = 0 }
  $bw.Write([byte]$w); $bw.Write([byte]$w); $bw.Write([byte]0); $bw.Write([byte]0)
  $bw.Write([uint16]1); $bw.Write([uint16]32)
  $bw.Write([uint32]$p.bytes.Length); $bw.Write([uint32]$off)
  $off += $p.bytes.Length
}
foreach ($p in $pngs) { $bw.Write($p.bytes) }
$bw.Close(); $fs.Close()
$master.Dispose()
$fi = Get-Item -LiteralPath $IcoPath
Write-Output ("ICON: OK -> " + $IcoPath + " (" + $fi.Length + " bayt, " + $sizes.Count + " boyut)")
