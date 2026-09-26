<#
.SYNOPSIS
  STL geometrisini otomatik dogrular (Faz 3 kural 6-8: sanity check). Sadece okur, dosya degistirmez.
.DESCRIPTION
  ASCII STL'yi parse eder ve sunlari kontrol eder:
    1. facet sayisi >= MinFacets
    2. bounding box == beklenen olculer (Tolerance mm icinde)
    3. -CheckHole verildiyse: delik rim verteksleri (merkez + cap) ALT ve UST duzlemde mevcut
       (ikisi de varsa delik tam gecislidir)
  Basariliysa olcumleri yazip "VERIFY: PASS" doner.
  Basarisizsa tum hatalari listeleyip throw eder (cikis kodu sifir degil).
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
  [int]$MinFacets = 1
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Stl)) { throw "VERIFY: FAIL - STL bulunamadi: $Stl" }

$failures = New-Object System.Collections.Generic.List[string]
$minX = [double]::MaxValue; $maxX = [double]::MinValue
$minY = [double]::MaxValue; $maxY = [double]::MinValue
$minZ = [double]::MaxValue; $maxZ = [double]::MinValue
$facets = 0; $rimBottom = 0; $rimTop = 0
$first = $true; $isAscii = $false
$holeR = $HoleDiameter / 2

foreach ($l in [System.IO.File]::ReadLines($Stl)) {
  $t = $l.Trim()
  if ($first) {
    $first = $false
    if ($t.StartsWith("solid")) { $isAscii = $true } else { break }
    continue
  }
  if ($t.StartsWith("facet normal")) { $facets++; continue }
  if ($t.StartsWith("vertex")) {
    $p = $t.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($p.Count -lt 4) { continue }
    $x = [double]$p[1]; $y = [double]$p[2]; $z = [double]$p[3]
    if ($x -lt $minX) { $minX = $x }; if ($x -gt $maxX) { $maxX = $x }
    if ($y -lt $minY) { $minY = $y }; if ($y -gt $maxY) { $maxY = $y }
    if ($z -lt $minZ) { $minZ = $z }; if ($z -gt $maxZ) { $maxZ = $z }
    if ($CheckHole -and $holeR -gt 0) {
      $d = [math]::Sqrt(($x - $HoleCX) * ($x - $HoleCX) + ($y - $HoleCY) * ($y - $HoleCY))
      if ([math]::Abs($d - $holeR) -le $Tolerance) {
        if ([math]::Abs($z - $ExpMinZ) -le $Tolerance) { $rimBottom++ }
        elseif ([math]::Abs($z - $ExpMaxZ) -le $Tolerance) { $rimTop++ }
      }
    }
  }
}

if (-not $isAscii) { throw "VERIFY: FAIL - sadece ASCII STL desteklenir: $Stl" }
if ($facets -lt $MinFacets) { $failures.Add("facet sayisi $facets < en az $MinFacets") }
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

Write-Output "bbox: X [$minX, $maxX]  Y [$minY, $maxY]  Z [$minZ, $maxZ]"
Write-Output "facet: $facets"
if ($CheckHole) { Write-Output "delik rim: alt=$rimBottom ust=$rimTop (merkez $HoleCX,$HoleCY cap $HoleDiameter)" }
if ($failures.Count -gt 0) { throw ("VERIFY: FAIL`n - " + ($failures -join "`n - ")) }
Write-Output "VERIFY: PASS"
