<#
.SYNOPSIS
  V1.1 geometry test paketi (TEST 8-20). V1 testlerine DOKUNMAZ.
.DESCRIPTION
  TEST 8:  box + through hole -> PASS
  TEST 9:  box + rectangular cutout (front) -> PASS
  TEST 10: hollow box (open top) -> PASS
  TEST 11: box + lid (clearance_fit 0.2) -> 2 STL PASS
  TEST 12: tube -> PASS
  TEST 13: multiple holes (3) -> PASS
  TEST 14: mirrored + translated part -> PASS
  TEST 15: rotated (z90) + translated geometry -> PASS (computed bbox)
  TEST 16: tolerance metadata uygulanir (lid kuculur) -> PASS
  TEST 17: joint clearance eksik -> BLOCKED bekleniyor
  TEST 18: imkansiz duvar -> BLOCKED bekleniyor
  TEST 19: 3 bilesen -> 3 ayri STL -> PASS
  TEST 20: govde-disi delik -> BLOCKED bekleniyor
  Gecici dizinler test sonunda silinir. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Run-GeometryTests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$GEngine = Join-Path $Root (Join-Path "engine" "Invoke-GeometryEngine.ps1")

$results = New-Object System.Collections.Generic.List[object]
$warnObserved = 0
$blockedObserved = 0
function Add-GResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-GComp($id, $shape) {
  return [pscustomobject]@{
    id = $id; label = $id
    base = [pscustomobject]@{ shape = $shape; width_mm = $null; depth_mm = $null; height_mm = $null }
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
}
function New-GHoleSpec($id, $dia, $cx, $cy, $htype) {
  return [pscustomobject]@{
    id = $id; hole_type = $htype; diameter_mm = $dia
    center_x_mm = $cx; center_y_mm = $cy; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "ok"
  }
}
function New-GSpec($name, $comps, $asm) {
  return [pscustomobject]@{
    project_name = $name; prompt = $name
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    components = $comps; assembly = $asm; material = $null
  }
}
function Remove-GTemp($dir) {
  for ($i = 0; $i -lt 6 -and (Test-Path -LiteralPath $dir); $i++) {
    try {
      [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
    } catch { Start-Sleep -Milliseconds 800 }
  }
}
function Invoke-GCase($name, $specObj, $expect, $check) {
  $tid = ($name -replace '[^A-Za-z0-9]+', '-')
  $tmpDir = Join-Path $Root (Join-Path "projects" ("_gtest-" + $tid))
try {
  Remove-GTemp $tmpDir
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $sp = Join-Path $tmpDir "spec.json"
    $specObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sp -Encoding UTF8
    $o = & $GEngine -SpecFile $sp -ProjectDir $tmpDir 2>&1 | Out-String
    $code = $LASTEXITCODE
    $info = [pscustomobject]@{ code = $code; dir = $tmpDir; output = $o }
    if ($o -match "WARNING") { $script:warnObserved++ }
    if ($o -match "BLOCKED") { $script:blockedObserved++ }
    $ok = $false; $detail = ""
    if ($expect -eq "PASS") {
      $ok = ($code -eq 0)
      $detail = $(if ($ok) { "engine PASS" } else { "exit=$code" })
      if ($ok -and $check) { $r2 = & $check $info; $ok = $r2.ok; $detail = $r2.detail }
    } else {
      $ok = ($code -eq 2)
      $detail = $(if ($ok) { "beklenen BLOCKED/FAILED alindi" } else { "exit=$code (2 bekleniyordu)" })
    }
    Add-GResult $name $ok $detail
  } catch { Add-GResult $name $false $_.Exception.Message }
  finally { Remove-GTemp $tmpDir }
}

# TEST 8
$c8 = New-GComp "body" "box"
$c8.base.width_mm = 60; $c8.base.depth_mm = 40; $c8.base.height_mm = 20
$c8.holes = @((New-GHoleSpec "h1" 12 20 20 "through"))
Invoke-GCase "TEST 8 (box+delik)" (New-GSpec "_gtest-TEST 8 (box+delik)" @($c8) $null) "PASS" $null

# TEST 9
$c9 = New-GComp "body" "box"
$c9.base.width_mm = 60; $c9.base.depth_mm = 40; $c9.base.height_mm = 20
$c9.cutouts = @([pscustomobject]@{ id = "c1"; kind = "rect"; face = "front"; pos_x_mm = 20; pos_y_mm = 5; width_mm = 20; length_mm = 10; depth_mm = 10; status = "ok" })
Invoke-GCase "TEST 9 (box+kesik)" (New-GSpec "_gtest-TEST 9 (box+kesik)" @($c9) $null) "PASS" $null

# TEST 10
$c10 = New-GComp "body" "box"
$c10.base.width_mm = 100; $c10.base.depth_mm = 80; $c10.base.height_mm = 50
$c10.hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true }
Invoke-GCase "TEST 10 (hollow)" (New-GSpec "_gtest-TEST 10 (hollow)" @($c10) $null) "PASS" $null

# TEST 11
$c11a = New-GComp "body" "box"
$c11a.base.width_mm = 60; $c11a.base.depth_mm = 40; $c11a.base.height_mm = 20
$c11b = New-GComp "lid" "box"
$c11b.base.width_mm = 60; $c11b.base.depth_mm = 40; $c11b.base.height_mm = 6
$c11b.tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = 0.2; fit_to = "body"; status = "ok" }
$a11 = [pscustomobject]@{ parts = @("body", "lid"); joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = 0.2; screw = $null }) }
$chk11 = {
  param($info)
  $s1 = Test-Path -LiteralPath (Join-Path $info.dir (Join-Path "output" "body.stl"))
  $s2 = Test-Path -LiteralPath (Join-Path $info.dir (Join-Path "output" "lid.stl"))
  $both = ($s1 -and $s2)
  return @{ ok = $both; detail = $(if ($both) { "2 STL uretildi" } else { "STL eksik" }) }
}
Invoke-GCase "TEST 11 (box+lid)" (New-GSpec "_gtest-TEST 11 (box+lid)" @($c11a, $c11b) $a11) "PASS" $chk11

# TEST 12
$c12 = New-GComp "pipe" "tube"
$c12.base = [pscustomobject]@{ shape = "tube"; outer_diameter_mm = 30; inner_diameter_mm = 20; height_mm = 40 }
Invoke-GCase "TEST 12 (tube)" (New-GSpec "_gtest-TEST 12 (tube)" @($c12) $null) "PASS" $null

# TEST 13
$c13 = New-GComp "body" "box"
$c13.base.width_mm = 80; $c13.base.depth_mm = 40; $c13.base.height_mm = 20
$c13.holes = @((New-GHoleSpec "h1" 8 15 15 "through"), (New-GHoleSpec "h2" 8 40 15 "through"), (New-GHoleSpec "h3" 8 65 15 "through"))
$chk13 = {
  param($info)
  $vp = Join-Path $info.dir (Join-Path "validation" "body.validation.json")
  $n = 0
  if (Test-Path -LiteralPath $vp) { $n = @((Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json).hole_checks).Count }
  $ok = ($n -eq 3)
  return @{ ok = $ok; detail = $(if ($ok) { "3 delik dogrulandi" } else { "delik sayisi=$n" }) }
}
Invoke-GCase "TEST 13 (3 delik)" (New-GSpec "_gtest-TEST 13 (3 delik)" @($c13) $null) "PASS" $chk13

# TEST 14
$c14 = New-GComp "part" "box"
$c14.base.width_mm = 30; $c14.base.depth_mm = 20; $c14.base.height_mm = 10
$c14.transforms = @([pscustomobject]@{ op = "mirror"; axis = "x" }, [pscustomobject]@{ op = "translate"; x = 30; y = 0; z = 0 })
Invoke-GCase "TEST 14 (mirror)" (New-GSpec "_gtest-TEST 14 (mirror)" @($c14) $null) "PASS" $null

# TEST 15
$c15 = New-GComp "part" "box"
$c15.base.width_mm = 40; $c15.base.depth_mm = 20; $c15.base.height_mm = 10
$c15.transforms = @([pscustomobject]@{ op = "rotate"; x = 0; y = 0; z = 90 }, [pscustomobject]@{ op = "translate"; x = 20; y = 0; z = 0 })
$chk15 = {
  param($info)
  $vp = Join-Path $info.dir (Join-Path "validation" "part.validation.json")
  $bb = ""
  if (Test-Path -LiteralPath $vp) {
    $v = Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json
    $bb = (($v.bbox_min -join ",") + " / " + ($v.bbox_max -join ","))
  }
  $ok = ($bb -eq "0,0,0 / 20,40,10")
  return @{ ok = $ok; detail = $(if ($ok) { "bbox 20x40x10 hesaplandi" } else { "bbox=$bb" }) }
}
Invoke-GCase "TEST 15 (rotate)" (New-GSpec "_gtest-TEST 15 (rotate)" @($c15) $null) "PASS" $chk15

# TEST 16
$c16a = New-GComp "body" "box"
$c16a.base.width_mm = 60; $c16a.base.depth_mm = 40; $c16a.base.height_mm = 20
$c16b = New-GComp "lid" "box"
$c16b.base.width_mm = 60; $c16b.base.depth_mm = 40; $c16b.base.height_mm = 6
$c16b.tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = 0.2; fit_to = "body"; status = "ok" }
$a16 = [pscustomobject]@{ parts = @("body", "lid"); joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = 0.2; screw = $null }) }
$chk16 = {
  param($info)
  $vp = Join-Path $info.dir (Join-Path "validation" "lid.validation.json")
  $ok = $false; $got = ""
  if (Test-Path -LiteralPath $vp) {
    $v = Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json
    $got = ($v.bbox_max -join " ")
    $ok = (([math]::Abs([double]$v.bbox_max[0] - 59.6) -lt 0.01) -and ([math]::Abs([double]$v.bbox_max[1] - 39.6) -lt 0.01) -and ([double]$v.bbox_max[2] -eq 6))
  }
  return @{ ok = $ok; detail = $(if ($ok) { "tolerans uygulandi (59.6x39.6)" } else { "lid bbox=$got" }) }
}
Invoke-GCase "TEST 16 (tolerans)" (New-GSpec "_gtest-TEST 16 (tolerans)" @($c16a, $c16b) $a16) "PASS" $chk16

# TEST 17
$c17a = New-GComp "body" "box"
$c17a.base.width_mm = 60; $c17a.base.depth_mm = 40; $c17a.base.height_mm = 20
$c17b = New-GComp "lid" "box"
$c17b.base.width_mm = 60; $c17b.base.depth_mm = 40; $c17b.base.height_mm = 6
$a17 = [pscustomobject]@{ parts = @("body", "lid"); joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = $null; screw = $null }) }
Invoke-GCase "TEST 17 (toleranssiz joint)" (New-GSpec "_gtest-TEST 17 (toleranssiz joint)" @($c17a, $c17b) $a17) "BLOCKED" $null

# TEST 18
$c18 = New-GComp "body" "box"
$c18.base.width_mm = 100; $c18.base.depth_mm = 80; $c18.base.height_mm = 50
$c18.hollow = [pscustomobject]@{ wall_mm = 60; open_top = $true }
Invoke-GCase "TEST 18 (imkansiz duvar)" (New-GSpec "_gtest-TEST 18 (imkansiz duvar)" @($c18) $null) "BLOCKED" $null

# TEST 19
$c19a = New-GComp "base" "box"
$c19a.base.width_mm = 80; $c19a.base.depth_mm = 60; $c19a.base.height_mm = 10
$c19b = New-GComp "back" "box"
$c19b.base.width_mm = 80; $c19b.base.depth_mm = 8; $c19b.base.height_mm = 70
$c19c = New-GComp "clip" "box"
$c19c.base.width_mm = 20; $c19c.base.depth_mm = 15; $c19c.base.height_mm = 12
$chk19 = {
  param($info)
  $n = @(Get-ChildItem -LiteralPath (Join-Path $info.dir "output") -Filter "*.stl").Count
  $ok = ($n -eq 3)
  return @{ ok = $ok; detail = $(if ($ok) { "3 ayri STL" } else { "stl sayisi=$n" }) }
}
Invoke-GCase "TEST 19 (3 parca)" (New-GSpec "_gtest-TEST 19 (3 parca)" @($c19a, $c19b, $c19c) $null) "PASS" $chk19

# TEST 20
$c20 = New-GComp "body" "box"
$c20.base.width_mm = 60; $c20.base.depth_mm = 40; $c20.base.height_mm = 20
$c20.holes = @((New-GHoleSpec "h1" 10 200 200 "through"))
Invoke-GCase "TEST 20 (gecersiz delik)" (New-GSpec "_gtest-TEST 20 (gecersiz delik)" @($c20) $null) "BLOCKED" $null

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "GEOMETRY SONUC: $passed / $($results.Count) test gecti"
Write-Output "GOZLEM: $warnObserved WARNING, $blockedObserved BLOCKED"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
