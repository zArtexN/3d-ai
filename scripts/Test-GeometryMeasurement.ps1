<#
.SYNOPSIS
  Phase 2 TDD: determinism + measurement + mesh + units.
.DESCRIPTION
  T-GEO-DET-01/02 | T-GEO-MEASURE-01..09 | T-GEO-MESH-01..03 | T-GEO-UNIT-01..03.
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-GMResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-GMDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("gm-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-GMBox($w, $d, $h, $holes, $wall) {
  $hol = $null
  if ($null -ne $wall) { $hol = [pscustomobject]@{ wall_mm = $wall; open_top = $false; bottom_thickness_mm = $null } }
  return [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = $w; depth_mm = $d; height_mm = $h }
    hollow = $hol; holes = @($holes); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
}
function New-GMHole($id, $dia, $cx, $cy) {
  return [pscustomobject]@{
    id = $id; hole_type = "through"; diameter_mm = $dia
    center_x_mm = $cx; center_y_mm = $cy; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "ok"
  }
}
function Invoke-GMEngine($body, $tag) {
  $d = New-GMDir $tag
  $sp = [pscustomobject]@{ project_name = $tag; prompt = $tag; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($body); assembly = $null; material = $null }
  $sf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
  & (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sf -ProjectDir $d 2>&1 | Out-Null
  return $d
}
function Get-GMVal($d, $name) {
  $p = Join-Path $d (Join-Path "validation" ($name + ".validation.json"))
  if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }
  return $null
}
function NumEq($a, $b, $tol) {
  if ($null -eq $tol) { $tol = 0.1 }
  try { return ([Math]::Abs([double]$a - [double]$b) -le [double]$tol) } catch { return $false }
}

# T-GEO-DET-01/02: ayni spec iki kez -> ayni metrikler.
$detBody = New-GMBox 75 45 30 @((New-GMHole "h1" 8 20 15)) $null
$d1 = Invoke-GMEngine $detBody "det1"
$d2 = Invoke-GMEngine $detBody "det2"
$v1 = Get-GMVal $d1 "body"
$v2 = Get-GMVal $d2 "body"
$detOk = ($null -ne $v1 -and $null -ne $v2)
if ($detOk) {
  foreach ($i in @(0, 1, 2)) {
    if (-not (NumEq $v1.bbox_min[$i] $v2.bbox_min[$i] 0.001)) { $detOk = $false }
    if (-not (NumEq $v1.bbox_max[$i] $v2.bbox_max[$i] 0.001)) { $detOk = $false }
  }
  if ([string]$v1.status -ne [string]$v2.status) { $detOk = $false }
}
Add-GMResult "T-GEO-DET-01" $detOk "iki kosu ayni bbox/status"
$fcOk = $false
if ($null -ne $v1 -and $null -ne $v2) {
  $c1 = @($v1.hole_checks).Count; $c2 = @($v2.hole_checks).Count
  $fcOk = ($c1 -eq 1 -and $c2 -eq 1)
}
Add-GMResult "T-GEO-DET-02" $fcOk "iki kosu ayni feature sayisi"
Remove-Item -LiteralPath $d1 -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $d2 -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MEASURE-01: bbox beklenen (75x45x30).
$b = New-GMBox 75 45 30 @() $null
$d = Invoke-GMEngine $b "m01"
$v = Get-GMVal $d "body"
$bbOk = ($null -ne $v -and (NumEq $v.bbox_max[0] 75) -and (NumEq $v.bbox_max[1] 45) -and (NumEq $v.bbox_max[2] 30) -and (NumEq $v.bbox_min[0] 0) -and (NumEq $v.bbox_min[1] 0) -and (NumEq $v.bbox_min[2] 0))
Add-GMResult "T-GEO-MEASURE-01" $bbOk "bbox 75x45x30"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MEASURE-02: yanlis beklenti -> FAIL (dogrulayici yakalar).
$b = New-GMBox 75 45 30 @() $null
$dd = Invoke-GMEngine $b "m02b"
$stl = Join-Path $dd (Join-Path "output" "body.stl")
$vvFail = $false
try {
  & (Join-Path $Root (Join-Path "scripts" "Verify-Stl.ps1")) -Stl $stl -ExpMinX 0 -ExpMinY 0 -ExpMinZ 0 -ExpMaxX 72 -ExpMaxY 45 -ExpMaxZ 30 2>&1 | Out-Null
} catch { $vvFail = $true }
Add-GMResult "T-GEO-MEASURE-02" $vvFail "72mm beklentisi FAIL"
Remove-Item -LiteralPath $dd -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MEASURE-03/04: delik cap/merkez olcumu.
$b = New-GMBox 75 45 30 @((New-GMHole "h1" 8 20 15)) $null
$d = Invoke-GMEngine $b "m0304"
$v = Get-GMVal $d "body"
$hc = @()
if ($null -ne $v) { $hc = @($v.hole_checks | Where-Object { [string]$_.id -eq "h1" }) }
$diaOk = ($hc.Count -gt 0 -and $null -ne $hc[0].measured_diameter -and (NumEq $hc[0].measured_diameter 8 0.15))
$cenOk = ($hc.Count -gt 0 -and $null -ne $hc[0].measured_center -and (NumEq $hc[0].measured_center[0] 20 0.15) -and (NumEq $hc[0].measured_center[1] 15 0.15))
Add-GMResult "T-GEO-MEASURE-03" $diaOk "delik capi olcumu ~8"
Add-GMResult "T-GEO-MEASURE-04" $cenOk "delik merkezi olcumu ~(20,15)"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MEASURE-05: kesik olcumu (on yuz 20x10, konum 50,12, duvar-kalinligi).
$d = New-GMDir "m05"
$cb = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 }
  hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true; bottom_thickness_mm = $null }
  holes = @()
  cutouts = @([pscustomobject]@{ id = "c1"; kind = "rect"; face = "front"; pos_x_mm = 70; pos_y_mm = 12; width_mm = 20; length_mm = 10; depth_mm = 2.5; status = "ok" })
  edge_notes = @(); transforms = @(); tolerance = $null; expected_bbox = $null
}
$sp = [pscustomobject]@{ project_name = "m05"; prompt = "m05"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($cb); assembly = $null; material = $null }
$sf = Join-Path $d "spec.json"
$sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sf -ProjectDir $d 2>&1 | Out-Null
$v = Get-GMVal $d "body"
$cc = @()
if ($null -ne $v) { $cc = @($v.cutout_checks | Where-Object { [string]$_.id -eq "c1" }) }
$cutOk = ($cc.Count -gt 0 -and [string]$cc[0].result -eq "PASS" -and (NumEq $cc[0].measured_width 20 0.3) -and (NumEq $cc[0].measured_pos_x 70 0.3))
Add-GMResult "T-GEO-MEASURE-05" $cutOk "kesik olcumu 20x10@70"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MEASURE-06/07: duvar/taban (construction metadata, mesh degil).
$d = New-GMDir "m0607"
$wb = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 }
  hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true; bottom_thickness_mm = 3 }
  holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
  divider_pattern = [pscustomobject]@{ count = 2; thickness_mm = 2; top_gap_mm = 0; top_gap_derived = $true; orientation = "along_length"; status = "ok" }
}
$sp = [pscustomobject]@{ project_name = "m0607"; prompt = "m0607"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($wb); assembly = $null; material = $null }
$sf = Join-Path $d "spec.json"
$sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sf -ProjectDir $d 2>&1 | Out-Null
$v = Get-GMVal $d "body"
$wallOk = ($null -ne $v -and $null -ne $v.wall_check -and [string]$v.wall_check.method -eq "construction" -and (NumEq $v.wall_check.thickness_mm 2.5))
$baseOk = ($null -ne $v -and $null -ne $v.base_check -and [string]$v.base_check.method -eq "construction" -and (NumEq $v.base_check.thickness_mm 3))
Add-GMResult "T-GEO-MEASURE-06" $wallOk "duvar construction 2.5 (mesh degil)"
Add-GMResult "T-GEO-MEASURE-07" $baseOk "taban construction 3 (mesh degil)"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MEASURE-08/09: unexpected/missing feature.
$d = New-GMDir "m0809"
$nb = New-GMBox 60 40 20 @() $null
$sp = [pscustomobject]@{ project_name = "m0809"; prompt = "m0809"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($nb); assembly = $null; material = $null }
$sf = Join-Path $d "spec.json"
$sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sf -ProjectDir $d 2>&1 | Out-Null
$v = Get-GMVal $d "body"
$unexpOk = ($null -ne $v -and $null -ne $v.expected_holes -and $null -ne $v.actual_holes -and [int]$v.expected_holes -eq 0 -and [int]$v.actual_holes -eq 0)
$missOk = ($null -ne $v -and [string]$v.status -eq "PASS" -and $null -ne $v.expected_holes)
Add-GMResult "T-GEO-MEASURE-08" $unexpOk "beklenmeyen delik yok (0=0)"
Add-GMResult "T-GEO-MEASURE-09" $missOk "eksik feature yok"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-MESH-01/02/03: gercek mesh kontrolleri.
$d = New-GMDir "mesh01"
$b = New-GMBox 40 30 20 @() $null
$dd = Invoke-GMEngine $b "mesh01b"
$stl = Join-Path $dd (Join-Path "output" "body.stl")
$mq = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $stl -AsJson 2>&1 | Out-String | ConvertFrom-Json
$meshOk = ($null -ne $mq -and [string]$mq.status -eq "PASS" -and [int]$mq.triangle_count -gt 0 -and [int]$mq.zero_area_triangles -eq 0)
Add-GMResult "T-GEO-MESH-01" $meshOk "watertight gecerli mesh"
Remove-Item -LiteralPath $dd -Recurse -Force -ErrorAction SilentlyContinue
$db = New-GMDir "mesh02"
$badStl = Join-Path $db "bad.stl"
@("solid bad", "facet normal 0 0 1", "outer loop", "vertex 0 0 0", "vertex 0 0 0", "vertex 1 0 0", "endloop", "endfacet", "endsolid bad") | Set-Content -LiteralPath $badStl -Encoding UTF8
$mqBad = $null
try { $mqBad = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $badStl -AsJson 2>&1 | Out-String | ConvertFrom-Json } catch { }
Add-GMResult "T-GEO-MESH-02" (($null -eq $mqBad) -or ([string]$mqBad.status -ne "PASS")) "bozuk mesh reddedildi"
Remove-Item -LiteralPath $db -Recurse -Force -ErrorAction SilentlyContinue
$d = New-GMDir "mesh03"
$b = New-GMBox 60 40 20 @() $null
$dd = Invoke-GMEngine $b "mesh03b"
$v = Get-GMVal $dd "body"
$compOk = ($null -ne $v -and [int]$v.connected_components -eq 1)
Add-GMResult "T-GEO-MESH-03" $compOk "tek parca (1 component)"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $dd -Recurse -Force -ErrorAction SilentlyContinue

# T-GEO-UNIT-01/02/03: ondalik + birim normalizasyonu (spec seviyesi, gercek assert).
function Get-GMWall($prompt, $tag) {
  $d = New-GMDir $tag
  $sf = Join-Path $d "spec.json"
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $sf 2>&1 | Out-Null
  $sp = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
  $w = $sp.components[0].hollow.wall_mm
  $bw = $sp.components[0].base.width_mm
  Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
  return @{ wall = $w; width = $bw }
}
$u1 = Get-GMWall "80x40x20 kutu, duvar 2,5 mm, ustu acik" "u1"
$u2 = Get-GMWall "80x40x20 kutu, duvar 2.5 mm, ustu acik" "u2"
Add-GMResult "T-GEO-UNIT-01" ((NumEq $u1.wall 2.5) -and (NumEq $u1.wall $u2.wall)) ("virgul=nokta (" + $u1.wall + "=" + $u2.wall + ")")
Add-GMResult "T-GEO-UNIT-02" (NumEq $u2.wall 2.5) ("nokta 2.5 (" + $u2.wall + ")")
$u3 = Get-GMWall "16 cm x 10 cm x 4.5 cm kutu, duvar 2 mm, ustu acik" "u3"
Add-GMResult "T-GEO-UNIT-03" ((NumEq $u3.width 160) -and (NumEq $u2.wall 2.5)) ("cm->mm (" + $u3.width + ")")

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("GEOMETRY SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
