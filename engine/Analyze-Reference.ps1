<#
.SYNOPSIS
  Referans model analizi (URL/dosya). Guvenli, salt-okunur; hicbir seyi CALISTIRMAZ, olcu UYDURMAZ.
.DESCRIPTION
  URL: yalnizca http/https, timeout, max 3 redirect, boyut limiti, icerik-tipi + uzanti dogrulama.
  Dosya: .stl/.3mf/.step/.stp kopyalanir (orijinal degismez); foto (.png/.jpg) tip olarak isaretlenir.
  Analiz: STL bbox (ascii+binary) + facet; 3MF vertex sinirlari (zip/xml, salt-okunur);
  STEP yalnizca metadata (olcu bilinmiyor); foto bilinmiyor.
  Cikti: reference.json {type, source, accessible, readable, bbox_known, bbox, facet_count,
  features[], missing[]} + ozet satirlari. Bilinmeyen kritik = missing listesinde.
.EXAMPLE
  powershell -File engine\Analyze-Reference.ps1 -Url "https://..." -ProjectDir projects\x
  powershell -File engine\Analyze-Reference.ps1 -File "C:\a\b.stl" -ProjectDir projects\x
#>
param(
  [string]$Url = "",
  [string]$File = "",
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [int]$TimeoutSec = 20,
  [int]$MaxBytesMB = 50
)

$ErrorActionPreference = "Stop"
$allowedExt = @(".stl", ".3mf", ".step", ".stp")
$photoExt = @(".png", ".jpg", ".jpeg")

if (($Url -eq "" -and $File -eq "") -or ($Url -ne "" -and $File -ne "")) {
  throw "URL veya File parametrelerinden yalnizca biri verilmelidir."
}
$refDir = Join-Path $ProjectDir "reference"
New-Item -ItemType Directory -Force -Path $refDir | Out-Null
$maxBytes = $MaxBytesMB * 1024 * 1024

$rep = [pscustomobject]@{
  type = "unknown"; source = ""; accessible = $false; readable = $false
  bbox_known = $false; bbox_min = $null; bbox_max = $null; facet_count = 0
  features = @(); missing = @(); local_path = ""
}

function Get-StlBbox($path) {
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $n = $bytes.Length
  $minX = [double]::MaxValue; $maxX = [double]::MinValue
  $minY = [double]::MaxValue; $maxY = [double]::MinValue
  $minZ = [double]::MaxValue; $maxZ = [double]::MinValue
  $facets = 0
  $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [math]::Min(512, $n))
  $isAscii = $false
  if ($head.StartsWith("solid")) {
    $fc = 0
    foreach ($l in [System.IO.File]::ReadLines($path)) {
      if ($l.Trim().StartsWith("facet")) { $fc++; if ($fc -gt 2) { break } }
    }
    if ($fc -gt 0) { $isAscii = $true }
  }
  if ($isAscii) {
    foreach ($l in [System.IO.File]::ReadLines($path)) {
      $t = $l.Trim()
      if ($t.StartsWith("facet normal")) { $facets++ }
      elseif ($t.StartsWith("vertex")) {
        $p = $t.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($p.Count -lt 4) { continue }
        $x = [double]$p[1]; $y = [double]$p[2]; $z = [double]$p[3]
        if ($x -lt $minX) { $minX = $x }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($y -gt $maxY) { $maxY = $y }
        if ($z -lt $minZ) { $minZ = $z }
        if ($z -gt $maxZ) { $maxZ = $z }
      }
    }
  } else {
    if ($n -lt 84) { throw "STL okunamadi (dosya cok kucuk)" }
    $cnt = [System.BitConverter]::ToUInt32($bytes, 80)
    if ($n -ne (84 + 50 * $cnt)) { throw "STL okunamadi (binary olcu tutmuyor)" }
    $facets = $cnt
    for ($i = 0; $i -lt $cnt; $i++) {
      $base = (88 + 50 * $i + 12)
      for ($v = 0; $v -lt 3; $v++) {
        $o = ($base + 12 * $v)
        $x = [System.BitConverter]::ToSingle($bytes, $o)
        $y = [System.BitConverter]::ToSingle($bytes, ($o + 4))
        $z = [System.BitConverter]::ToSingle($bytes, ($o + 8))
        if ($x -lt $minX) { $minX = $x }
        if ($x -gt $maxX) { $maxX = $x }
        if ($y -lt $minY) { $minY = $y }
        if ($y -gt $maxY) { $maxY = $y }
        if ($z -lt $minZ) { $minZ = $z }
        if ($z -gt $maxZ) { $maxZ = $z }
      }
    }
  }
  return @{ facets = $facets; bmin = @($minX, $minY, $minZ); bmax = @($maxX, $maxY, $maxZ) }
}

if ($Url -ne "") {
  if ($Url -notmatch '^(?i)https?://') { throw "Guvenli degil: yalnizca http/https kabul edilir." }
  $rep.source = $Url
  $req = [System.Net.HttpWebRequest]::Create($Url)
  $req.Timeout = ($TimeoutSec * 1000)
  $req.ReadWriteTimeout = ($TimeoutSec * 1000)
  $req.AllowAutoRedirect = $true
  $req.MaximumAutomaticRedirections = 3
  $req.UserAgent = "3D-AI-Designer/ref-analyzer"
  try { $resp = $req.GetResponse() }
  catch { throw "Baglanti alinamadi (timeout/limit/erisim): $($_.Exception.Message)" }
  try {
    $ctype = [string]$resp.ContentType
    $clen = $resp.ContentLength
    if ($clen -gt $maxBytes) { throw "Dosya cok buyuk (limit $MaxBytesMB MB)." }
    $upath = $Url.Split("?")[0]
    $ext = [System.IO.Path]::GetExtension($upath).ToLowerInvariant()
    if ($allowedExt -notcontains $ext) {
      if ($ctype -match "model/stl|model/mesh") { $ext = ".stl" }
      elseif ($ctype -match "model/3mf|application/vnd.*3mf") { $ext = ".3mf" }
      else { throw "Bu baglantidan dogrudan 3D model alinamadi (uzanti/tip: $ext / $ctype)." }
    }
    $dest = Join-Path $refDir ("reference" + $ext)
    $rs = $resp.GetResponseStream()
    $fs = [System.IO.File]::OpenWrite($dest)
    try {
      $buf = New-Object byte[] 65536
      $total = 0
      while (($rd = $rs.Read($buf, 0, $buf.Length)) -gt 0) {
        $total += $rd
        if ($total -gt $maxBytes) { throw "Dosya cok buyuk (limit $MaxBytesMB MB)." }
        $fs.Write($buf, 0, $rd)
      }
    } finally { $fs.Close(); $rs.Close() }
    $rep.type = $ext.TrimStart(".")
    $rep.accessible = $true
    $rep.local_path = $dest
  } finally { $resp.Close() }
} else {
  if (-not (Test-Path -LiteralPath $File)) { throw "Referans dosya bulunamadi." }
  $rep.source = $File
  $ext = [System.IO.Path]::GetExtension($File).ToLowerInvariant()
  if ($photoExt -contains $ext) {
    $dest = Join-Path $refDir ("reference" + $ext)
    Copy-Item -LiteralPath $File -Destination $dest -Force
    $rep.type = "photo"
    $rep.accessible = $true
    $rep.local_path = $dest
    $rep.missing = @("tum olculer (gorselden olcu cikarilmaz)", "derinlik/yukseklik", "delik konumlari")
  } elseif ($allowedExt -contains $ext) {
    $dest = Join-Path $refDir ("reference" + $ext)
    Copy-Item -LiteralPath $File -Destination $dest -Force
    $rep.type = $ext.TrimStart(".")
    $rep.accessible = $true
    $rep.local_path = $dest
  } else {
    throw "Desteklenmeyen referans formati: $ext (stl/3mf/step/stp/png/jpg)."
  }
}

if ($rep.type -eq "stl") {
  $bb = Get-StlBbox $rep.local_path
  $rep.readable = $true
  $rep.bbox_known = $true
  $rep.bbox_min = @($bb.bmin)
  $rep.bbox_max = @($bb.bmax)
  $rep.facet_count = $bb.facets
  $rep.features = @("dis olculer (mesh bbox)", "facet sayisi $($bb.facets)")
  $rep.missing = @("delik/ozellik konumlari (meshten guvenli cikarilmaz)", "duvar kalinligi", "toleranslar")
} elseif ($rep.type -eq "3mf") {
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zip = [System.IO.Compression.ZipFile]::OpenRead($rep.local_path)
    try {
      $entry = $zip.Entries | Where-Object { $_.FullName -eq "3D/3dmodel.model" } | Select-Object -First 1
      if ($null -eq $entry) { throw "3dmodel.model bulunamadi" }
      $sr = New-Object System.IO.StreamReader($entry.Open())
      $xml = $sr.ReadToEnd()
      $sr.Close()
      $doc = New-Object System.Xml.XmlDocument
      $doc.LoadXml($xml)
      $vs = $doc.GetElementsByTagName("vertex")
      if ($vs.Count -eq 0) { throw "vertex yok" }
      $x0 = [double]::MaxValue; $x1 = [double]::MinValue
      $y0 = [double]::MaxValue; $y1 = [double]::MinValue
      $z0 = [double]::MaxValue; $z1 = [double]::MinValue
      foreach ($v in $vs) {
        $x = [double]$v.GetAttribute("x"); $y = [double]$v.GetAttribute("y"); $z = [double]$v.GetAttribute("z")
        if ($x -lt $x0) { $x0 = $x }
        if ($x -gt $x1) { $x1 = $x }
        if ($y -lt $y0) { $y0 = $y }
        if ($y -gt $y1) { $y1 = $y }
        if ($z -lt $z0) { $z0 = $z }
        if ($z -gt $z1) { $z1 = $z }
      }
      $rep.readable = $true
      $rep.bbox_known = $true
      $rep.bbox_min = @($x0, $y0, $z0)
      $rep.bbox_max = @($x1, $y1, $z1)
      $rep.features = @("dis olculer (3mf vertex)", "vertex sayisi $($vs.Count)")
      $rep.missing = @("delik/ozellik konumlari", "duvar kalinligi", "toleranslar")
    } finally { $zip.Dispose() }
  } catch {
    $rep.missing = @("3mf icerigi okunamadi: $($_.Exception.Message)", "tum olculer sorulmali")
  }
} elseif ($rep.type -eq "step" -or $rep.type -eq "stp") {
  $rep.readable = $true
  $rep.missing = @("STEP geometrisi bu asamada olculmuyor (FreeCAD gerekli)", "tum olculer sorulmali")
}

$rep | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $refDir "reference.json") -Encoding UTF8
Write-Output "REFERANS TURU: $($rep.type)"
Write-Output "ERISIM: $(if ($rep.accessible) { 'ok' } else { 'yok' })"
Write-Output "OKUNABILIR: $(if ($rep.readable) { 'ok' } else { 'sinirli' })"
if ($rep.bbox_known) { Write-Output "OLCU: $($rep.bbox_min -join ' ') / $($rep.bbox_max -join ' ')" }
else { Write-Output "OLCU: bilinmiyor (sorulmali)" }
foreach ($m in $rep.missing) { Write-Output "EKSIK: $m" }
