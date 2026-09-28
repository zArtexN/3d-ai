<#
.SYNOPSIS
  STL geometrisini otomatik dogrular (Faz 3 + V1: sanity check). Sadece okur, dosya degistirmez.
.DESCRIPTION
  ASCII ve BINARY STL parse eder, sunlari kontrol eder:
  FAIL (kritik):
    1. dosya yok / format taninamadi / mesh bos (facet 0)
    2. facet sayisi < MinFacets
    3. bounding box != beklenen olculer (Tolerance mm icinde; Tolerance = olcum toleransi)
    4. -CheckHole verildiyse: delik rim verteksleri ALT ve UST duzlemde yoksa
    5. -CheckCutout verildiyse: yuzey duzleminde beklenen dikdortgende aciklik yoksa/olcusu tutmuyorsa
  Olcum: delik merkezi/capi (ust rim ortalamasi) ve kesik dikdortgeni raporlanir (JsonOut).
    WARNING (uretim gecer, FAIL yapmaz):
      - facet sayisi < WarningMinFacets
      - dosya boyutu < WarningMinBytes
  Sonuc: "VERIFY: PASS" / "VERIFY: WARNING" (cikis 0) / "VERIFY: FAIL" + throw (cikis sifir degil).
  -JsonOut verilirse makine raporu JSON olarak yazilir (validation.json icin).
  Export-Stl.ps1'e DOKUNMAZ; ondan sonra ayri adim olarak calir.
.EXAMPLE
  powershell -File scripts\Verify-Stl.ps1 -Stl projects\demo\output\model.stl -ExpMinX 0 -ExpMinY 0 -ExpMinZ 0 -ExpMaxX 80 -ExpMaxY 40 -ExpMaxZ 20 -CheckHole -HoleCX 40 -HoleCY 20 -HoleDiameter 25
#>
param(
  [Parameter(Mandatory = $true)][string]$Stl,
  [Parameter(Mandatory = $true)][double]$ExpMinX,
  [Parameter(Mandatory = $true)][double]$ExpMinY,
  [Parameter(Mandatory = $true)][double]$ExpMinZ,
  [Parameter(Mandatory = $true)][double]$ExpMaxX,
  [Parameter(Mandatory = $true)][double]$ExpMaxY,
  [Parameter(Mandatory = $true)][double]$ExpMaxZ,
  [double]$Tolerance = 0.05,
  [switch]$CheckHole,
  [double]$HoleCX = 0,
  [double]$HoleCY = 0,
  [double]$HoleDiameter = 0,
  [double]$HoleZBottom = [double]::NaN,
  [double]$HoleZTop = [double]::NaN,
  [switch]$CheckCutout,
  [string]$CutAxis = "y",
  [double]$CutPlane = [double]::NaN,
  [double]$CutU0 = [double]::NaN,
  [double]$CutV0 = [double]::NaN,
  [double]$CutW = [double]::NaN,
  [double]$CutL = [double]::NaN,
  [int]$MinFacets = 1,
  [int]$WarningMinFacets = 12,
  [int]$WarningMinBytes = 1024,
  [string]$JsonOut = ""
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Stl)) { throw "VERIFY: FAIL - STL bulunamadi: $Stl" }

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$minX = [double]::MaxValue; $maxX = [double]::MinValue
$minY = [double]::MaxValue; $maxY = [double]::MinValue
$minZ = [double]::MaxValue; $maxZ = [double]::MinValue
$facets = 0; $rimBottom = 0; $rimTop = 0
$rimTopX = New-Object System.Collections.Generic.List[double]
$rimTopY = New-Object System.Collections.Generic.List[double]
$rimTopR = New-Object System.Collections.Generic.List[double]
$cutRim = 0
$cutUMin = [double]::MaxValue; $cutUMax = [double]::MinValue
$cutVMin = [double]::MaxValue; $cutVMax = [double]::MinValue
$format = "unknown"
$holeR = $HoleDiameter / 2

function Update-BBox($x, $y, $z) {
  if ($x -lt $script:minX) { $script:minX = $x }; if ($x -gt $script:maxX) { $script:maxX = $x }
  if ($y -lt $script:minY) { $script:minY = $y }; if ($y -gt $script:maxY) { $script:maxY = $y }
  if ($z -lt $script:minZ) { $script:minZ = $z }; if ($z -gt $script:maxZ) { $script:maxZ = $z }
}
function Update-Rim($x, $y, $z) {
  if (-not $CheckHole -or $holeR -le 0) { return }
  # Cikis duzlemi: verilmediyse parca bbox alti/ustu (kapali parca varsayimi);
  # hollow+acik govdede motor taban-tepesini (floor) gonderir.
  $zB = $ExpMinZ
  if ($HoleZBottom -eq $HoleZBottom) { $zB = $HoleZBottom }
  $zT = $ExpMaxZ
  if ($HoleZTop -eq $HoleZTop) { $zT = $HoleZTop }
  $dd = [math]::Sqrt(($x - $HoleCX) * ($x - $HoleCX) + ($y - $HoleCY) * ($y - $HoleCY))
  if ([math]::Abs($dd - $holeR) -le $Tolerance) {
    if ([math]::Abs($z - $zB) -le $Tolerance) { $script:rimBottom++ }
    elseif ([math]::Abs($z - $zT) -le $Tolerance) {
      $script:rimTop++
      $script:rimTopX.Add([double]$x) | Out-Null
      $script:rimTopY.Add([double]$y) | Out-Null
      $script:rimTopR.Add([double]$dd) | Out-Null
    }
  }
}
function Update-Cutout($x, $y, $z) {
  if (-not $CheckCutout) { return }
  if ($CutPlane -ne $CutPlane -or $CutU0 -ne $CutU0) { return }
  $n = 0; $u = 0; $v = 0
  if ($CutAxis -eq "y") { $n = $y; $u = $x; $v = $z }
  elseif ($CutAxis -eq "z") { $n = $z; $u = $x; $v = $y }
  else { $n = $x; $u = $y; $v = $z }
  if ([math]::Abs($n - $CutPlane) -gt $Tolerance) { return }
  if ($u -lt ($CutU0 - $Tolerance) -or $u -gt ($CutU0 + $CutW + $Tolerance)) { return }
  if ($v -lt ($CutV0 - $Tolerance) -or $v -gt ($CutV0 + $CutL + $Tolerance)) { return }
  $script:cutRim++
  if ($u -lt $script:cutUMin) { $script:cutUMin = $u }
  if ($u -gt $script:cutUMax) { $script:cutUMax = $u }
  if ($v -lt $script:cutVMin) { $script:cutVMin = $v }
  if ($v -gt $script:cutVMax) { $script:cutVMax = $v }
}

$bytes = [System.IO.File]::ReadAllBytes($Stl)
$fileBytes = $bytes.Length
$head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [math]::Min(512, $fileBytes))

if ($head.StartsWith("solid")) {
  $hasFacet = $false
  foreach ($l in [System.IO.File]::ReadLines($Stl)) { if ($l.Trim().StartsWith("facet")) { $hasFacet = $true; break } }
  if ($hasFacet) {
    $format = "ascii"
    $skipFirst = $true
    foreach ($l in [System.IO.File]::ReadLines($Stl)) {
      $t = $l.Trim()
      if ($skipFirst) { $skipFirst = $false; continue }
      if ($t.StartsWith("facet normal")) { $facets++; continue }
      if ($t.StartsWith("vertex")) {
        $p = $t.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
        if ($p.Count -lt 4) { continue }
        $x = [double]$p[1]; $y = [double]$p[2]; $z = [double]$p[3]
        Update-BBox $x $y $z
        Update-Rim $x $y $z
        Update-Cutout $x $y $z
      }
    }
  }
}
if ($format -eq "unknown" -and $fileBytes -ge 84) {
  $n = [System.BitConverter]::ToUInt32($bytes, 80)
  if ($fileBytes -eq (84 + 50 * $n)) {
    $format = "binary"
    $facets = $n
    for ($i = 0; $i -lt $n; $i++) {
      $base = 88 + 50 * $i + 12
      for ($v = 0; $v -lt 3; $v++) {
        $o = $base + 12 * $v
        $x = [System.BitConverter]::ToSingle($bytes, $o)
        $y = [System.BitConverter]::ToSingle($bytes, ($o + 4))
        $z = [System.BitConverter]::ToSingle($bytes, ($o + 8))
        Update-BBox $x $y $z
        Update-Rim $x $y $z
        Update-Cutout $x $y $z
      }
    }
  }
}

if ($format -eq "unknown") { throw "VERIFY: FAIL - STL formati taninamadi (ASCII degil, binary olcusu tutmuyor): $Stl" }
if ($facets -lt 1) { $failures.Add("mesh bos: facet sayisi 0") }
elseif ($facets -lt $MinFacets) { $failures.Add("facet sayisi $facets < en az $MinFacets") }
elseif ($facets -lt $WarningMinFacets) { $warnings.Add("WARNING: facet sayisi dusuk ($facets < $WarningMinFacets)") }
if ($fileBytes -lt $WarningMinBytes) { $warnings.Add("WARNING: dosya boyutu kucuk ($fileBytes bayt < $WarningMinBytes)") }

$checks = @(
  @("minX", $minX, $ExpMinX), @("maxX", $maxX, $ExpMaxX),
  @("minY", $minY, $ExpMinY), @("maxY", $maxY, $ExpMaxY),
  @("minZ", $minZ, $ExpMinZ), @("maxZ", $maxZ, $ExpMaxZ)
)
foreach ($c in $checks) {
  if ([math]::Abs($c[1] - $c[2]) -gt $Tolerance) {
    $failures.Add("bbox $($c[0]): gercek $($c[1]), beklenen $($c[2]) (tolerans $Tolerance)")
  }
}
if ($CheckHole) {
  if ($holeR -le 0) { $failures.Add("delik capi gecersiz: $HoleDiameter") }
  else {
    if ($rimBottom -eq 0) { $failures.Add("delik alt rim bulunamadi (merkez $HoleCX,$HoleCY cap $HoleDiameter)") }
    if ($rimTop -eq 0) { $failures.Add("delik ust rim bulunamadi - tam gecisli olmayabilir") }
  }
}
$measCX = $null; $measCY = $null; $measDia = $null
if ($CheckHole -and $rimTop -gt 0) {
  $sx = 0; $sy = 0; $sr = 0
  for ($i = 0; $i -lt $rimTopX.Count; $i++) { $sx += $rimTopX[$i]; $sy += $rimTopY[$i]; $sr += $rimTopR[$i] }
  $measCX = [math]::Round($sx / $rimTopX.Count, 4)
  $measCY = [math]::Round($sy / $rimTopY.Count, 4)
  $measDia = [math]::Round(2 * ($sr / $rimTopR.Count), 4)
}
$cutMeasU0 = $null; $cutMeasV0 = $null; $cutMeasU1 = $null; $cutMeasV1 = $null
if ($CheckCutout) {
  if ($cutRim -eq 0) { $failures.Add("kesik aciklik rim bulunamadi (yuzey duzleminde beklenen dikdortgende vertex yok)") }
  else {
    $cutMeasU0 = [math]::Round($cutUMin, 4); $cutMeasU1 = [math]::Round($cutUMax, 4)
    $cutMeasV0 = [math]::Round($cutVMin, 4); $cutMeasV1 = [math]::Round($cutVMax, 4)
    if ([math]::Abs($cutUMin - $CutU0) -gt $Tolerance -or [math]::Abs($cutUMax - ($CutU0 + $CutW)) -gt $Tolerance -or
        [math]::Abs($cutVMin - $CutV0) -gt $Tolerance -or [math]::Abs($cutVMax - ($CutV0 + $CutL)) -gt $Tolerance) {
      $failures.Add("kesik olcusu uyusmuyor: olculen [$cutMeasU0,$cutMeasV0,$cutMeasU1,$cutMeasV1], beklenen [$CutU0,$CutV0,$(($CutU0 + $CutW)),$(($CutV0 + $CutL))] (tolerans $Tolerance)")
    }
  }
}

$status = "PASS"
if ($failures.Count -gt 0) { $status = "FAIL" }
elseif ($warnings.Count -gt 0) { $status = "WARNING" }

Write-Output "format: $format ($fileBytes bayt)"
Write-Output "bbox: X [$minX, $maxX]  Y [$minY, $maxY]  Z [$minZ, $maxZ]"
Write-Output "facet: $facets"
if ($CheckHole) { Write-Output "delik rim: alt=$rimBottom ust=$rimTop (merkez $HoleCX,$HoleCY cap $HoleDiameter)" }
if ($CheckHole -and $rimTop -gt 0) { Write-Output "olcum merkez=$measCX,$measCY cap=$measDia" }
if ($CheckCutout) { Write-Output "kesik rim: $cutRim (olculen [$cutMeasU0,$cutMeasV0,$cutMeasU1,$cutMeasV1])" }
foreach ($wrn in $warnings) { Write-Output $wrn }

if ($JsonOut -ne "") {
  $rep = [pscustomobject]@{
    status = $status
    stl = $Stl
    format = $format
    file_bytes = $fileBytes
    bbox_min = @($minX, $minY, $minZ)
    bbox_max = @($maxX, $maxY, $maxZ)
    bbox_size = @(([math]::Round($maxX - $minX, 4)), ([math]::Round($maxY - $minY, 4)), ([math]::Round($maxZ - $minZ, 4)))
    facet_count = $facets
    rim_bottom = $rimBottom
    rim_top = $rimTop
    hole_measured_center = @($measCX, $measCY)
    hole_measured_diameter = $measDia
    cut_rim = $cutRim
    cut_measured_rect = @($cutMeasU0, $cutMeasV0, $cutMeasU1, $cutMeasV1)
    failures = @($failures)
    warnings = @($warnings)
  }
  $rep | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $JsonOut -Encoding UTF8
}

if ($status -eq "FAIL") { throw ("VERIFY: FAIL`n - " + ($failures -join "`n - ")) }
Write-Output "VERIFY: $status"
