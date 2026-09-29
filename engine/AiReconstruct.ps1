<#
.SYNOPSIS
  AI reconstruction yardimci kutuphanesi (Phase 6).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok.
  Giris dogrulama, olcek cozumu, guven skoru, patch onerisi.
  Olcek yoksa UNKNOWN (mm varsayimi YASAK). Guven bilimsel yuzde degildir.
#>

try { Add-Type -AssemblyName System.Drawing -ErrorAction Stop } catch { }

function Test-ReconImageSet($files) {
  $errors = New-Object System.Collections.Generic.List[string]
  $infos = New-Object System.Collections.Generic.List[object]
  $allowed = @(".png", ".jpg", ".jpeg", ".bmp", ".webp", ".tif", ".tiff")
  $seen = @{}
  foreach ($f in @($files)) {
    if ([string]::IsNullOrWhiteSpace([string]$f) -or -not (Test-Path -LiteralPath ([string]$f))) {
      $errors.Add(("dosya yok: " + $f)) | Out-Null
      continue
    }
    $ext = ([System.IO.Path]::GetExtension([string]$f)).ToLowerInvariant()
    if ($allowed -notcontains $ext) { $errors.Add(("tip desteklenmiyor: " + $f)) | Out-Null; continue }
    try {
      $img = [System.Drawing.Image]::FromFile([string]$f)
      $w = [int]$img.Width; $h = [int]$img.Height
      $img.Dispose()
    } catch {
      $errors.Add(("okunamiyor: " + $f)) | Out-Null
      continue
    }
    if ($w -lt 16 -or $h -lt 16) { $errors.Add(("cozunurluk dusuk: " + $f)) | Out-Null; continue }
    $hash = ""
    try {
      $bytes = [System.IO.File]::ReadAllBytes([string]$f)
      $md5 = [System.Security.Cryptography.MD5]::Create()
      $hash = ([System.BitConverter]::ToString($md5.ComputeHash($bytes)) -replace '-', '')
    } catch { }
    if ($hash -ne "" -and $seen.ContainsKey($hash)) { $errors.Add(("tekrarlanan goruntu: " + $f)) | Out-Null; continue }
    if ($hash -ne "") { $seen[$hash] = $true }
    $infos.Add([pscustomobject]@{ path = [string]$f; width = $w; height = $h; hash = $hash }) | Out-Null
  }
  return @{ ok = ($errors.Count -eq 0 -and $infos.Count -gt 0); errors = @($errors.ToArray()); images = @($infos.ToArray()) }
}

function Get-ReconScale($measuredUnits, $known) {
  if ($null -ne $known -and $null -ne $known.width_mm -and [double]$known.width_mm -gt 0 -and [double]$measuredUnits -gt 0) {
    $s = [double]$known.width_mm / [double]$measuredUnits
    return @{ scale = $s; source = "user_measurement"; status = "KNOWN" }
  }
  if ($null -ne $known -and $null -ne $known.reference_mm -and [double]$known.reference_mm -gt 0 -and [double]$measuredUnits -gt 0) {
    $s = [double]$known.reference_mm / [double]$measuredUnits
    return @{ scale = $s; source = "reference_object"; status = "KNOWN" }
  }
  return @{ scale = $null; source = "none"; status = "UNKNOWN" }
}

function Get-ReconConfidence($viewCount, $scaleStatus, $engineId) {
  $level = "LOW"
  $reasons = New-Object System.Collections.Generic.List[string]
  if ([int]$viewCount -ge 3) { $level = "MEDIUM"; $reasons.Add("coklu goru") | Out-Null }
  else { $reasons.Add("tek/gizli geometri bilinmiyor") | Out-Null }
  if ([string]$scaleStatus -ne "KNOWN") { $reasons.Add("olcek bilinmiyor") | Out-Null }
  if ([string]$engineId -eq "mock") {
    if ($level -eq "HIGH") { $level = "MEDIUM" }
    $reasons.Add("mock motor: yuksek guven verilmez") | Out-Null
  }
  return @{ level = $level; reasons = @($reasons.ToArray()) }
}

function New-MockReconMesh($outPath, $w, $d, $h) {
  $dir = Split-Path -Parent $outPath
  if ($dir -ne "" -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $x0 = 0; $y0 = 0; $z0 = 0
  $x1 = [double]$w; $y1 = [double]$d; $z1 = [double]$h
  $v = @(
    @($x0, $y0, $z0), @($x1, $y0, $z0), @($x1, $y1, $z0), @($x0, $y1, $z0),
    @($x0, $y0, $z1), @($x1, $y0, $z1), @($x1, $y1, $z1), @($x0, $y1, $z1)
  )
  $f = @(
    @(0, 1, 2), @(0, 2, 3),
    @(4, 6, 5), @(4, 7, 6),
    @(0, 4, 5), @(0, 5, 1),
    @(1, 5, 6), @(1, 6, 2),
    @(2, 6, 7), @(2, 7, 3),
    @(3, 7, 4), @(3, 4, 0)
  )
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("solid mock_recon") | Out-Null
  foreach ($t in $f) {
    $p0 = $v[[int]$t[0]]; $p1 = $v[[int]$t[1]]; $p2 = $v[[int]$t[2]]
    $e1x = [double]$p1[0] - [double]$p0[0]
    $e1y = [double]$p1[1] - [double]$p0[1]
    $e1z = [double]$p1[2] - [double]$p0[2]
    $e2x = [double]$p2[0] - [double]$p0[0]
    $e2y = [double]$p2[1] - [double]$p0[1]
    $e2z = [double]$p2[2] - [double]$p0[2]
    $nx = $e1y * $e2z - $e1z * $e2y
    $ny = $e1z * $e2x - $e1x * $e2z
    $nz = $e1x * $e2y - $e1y * $e2x
    $lines.Add(("facet normal " + $nx + " " + $ny + " " + $nz)) | Out-Null
    $lines.Add("outer loop") | Out-Null
    foreach ($vi in $t) {
      $p = $v[$vi]
      $lines.Add(("vertex " + $p[0] + " " + $p[1] + " " + $p[2])) | Out-Null
    }
    $lines.Add("endloop") | Out-Null
    $lines.Add("endfacet") | Out-Null
  }
  $lines.Add("endsolid mock_recon") | Out-Null
  [System.IO.File]::WriteAllLines($outPath, $lines.ToArray(), (New-Object System.Text.UTF8Encoding $false))
  return $outPath
}

function New-ReconPatchProposal($scaledDims, $unknowns) {
  $ops = New-Object System.Collections.Generic.List[object]
  $qs = New-Object System.Collections.Generic.List[object]
  if ($null -ne $scaledDims) {
    foreach ($k in @("width_mm", "depth_mm", "height_mm")) {
      if ($null -ne $scaledDims.$k) {
        $ops.Add(@{ op = "replace"; path = ("body.base." + $k); old = $null; value = [double]$scaledDims.$k; reason = "recon"; requires_confirmation = $false }) | Out-Null
      }
    }
  }
  foreach ($u in @($unknowns)) {
    if ([string]$u -eq "width") { $qs.Add("genislik (mm) nedir?") | Out-Null }
    elseif ([string]$u -eq "height") { $qs.Add("yukseklik (mm) nedir?") | Out-Null }
    elseif ([string]$u -eq "depth") { $qs.Add("derinlik (mm) nedir?") | Out-Null }
    elseif ([string]$u -eq "scale") { $qs.Add("olcek referansi nedir? (bilinen olcu)") | Out-Null }
  }
  return @{ ops = @($ops.ToArray()); questions = @($qs.ToArray()) }
}
