<#
.SYNOPSIS
  V1.2 uretim hatti testleri (T21-T34 + negatifler + gercekci A/B/C). V1/V1.1 testlerine DOKUNMAZ.
.DESCRIPTION
  T21 pipeline uctan uca PASS | T22 eksik -> NEEDS_INPUT+soru, STL yok | T23 cevap -> PASS
  T24 spec->SCAD bolumlu | T25 STL var | T26 validation kategorileri | T27 multi-part 2 STL
  T28 project.json alanlari | T29 gecersiz spec -> BLOCKED | T30 AI MOCK arayuzu
  T31 recent-load geri okuma | T32 warning yayilimi (PASS+WARNING) | T33 blocked yayilimi
  T34 portable (hardcoded yol yok) | T35-44 negatifler | TA/TB/TC gercekci senaryolar
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Run-PipelineTests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
$Pipeline = Join-Path $EngineDir "Invoke-Pipeline.ps1"
$GEngine = Join-Path $EngineDir "Invoke-GeometryEngine.ps1"
$AIProv = Join-Path $EngineDir "AIProvider.ps1"

$results = New-Object System.Collections.Generic.List[object]
$warnObserved = 0
$blockedObserved = 0
function Add-PResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function Remove-PTemp($dir) {
  for ($i = 0; $i -lt 6 -and (Test-Path -LiteralPath $dir); $i++) {
    try {
      [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
    } catch { Start-Sleep -Milliseconds 800 }
  }
}
function Invoke-PipeCase($tid, $prompt, $answers, $expect, $check) {
  $tmpDir = Join-Path $Root (Join-Path "projects" ("_ptest-" + $tid))
  try {
    Remove-PTemp $tmpDir
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $ph = @{ Prompt = $prompt; ProjectName = ("_ptest-" + $tid); ProjectDir = $tmpDir }
    if ($answers) {
      $af = Join-Path $tmpDir "answers.json"
      $answers | ConvertTo-Json | Set-Content -LiteralPath $af -Encoding UTF8
      $ph.AnswersFile = $af
    }
    $o = & $Pipeline @ph 2>&1 | Out-String
    if ($o -match "WARNING") { $script:warnObserved++ }
    if ($o -match "BLOCKED|NEEDS_INPUT") { $script:blockedObserved++ }
    $resPath = Join-Path $tmpDir "pipeline-result.json"
    $res = $null
    if (Test-Path -LiteralPath $resPath) { $res = Get-Content -LiteralPath $resPath -Raw | ConvertFrom-Json }
    $st = ""; if ($res) { $st = [string]$res.status }
    $ok = ($st -eq $expect)
    $detail = $(if ($ok) { "status=$st" } else { "status=$st ($expect bekleniyordu)" })
    if ($ok -and $check) { $r2 = & $check $tmpDir $res; $ok = $r2.ok; $detail = $r2.detail }
    Add-PResult $tid $ok $detail
  } catch { Add-PResult $tid $false $_.Exception.Message }
  finally { Remove-PTemp $tmpDir }
}
function New-V2Comp($id, $shape) {
  return [pscustomobject]@{
    id = $id; label = $id
    base = [pscustomobject]@{ shape = $shape; width_mm = $null; depth_mm = $null; height_mm = $null }
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
  }
}
function Invoke-EngCase($tid, $specObj, $expect, $check) {
  $tmpDir = Join-Path $Root (Join-Path "projects" ("_ptest-" + $tid))
  try {
    Remove-PTemp $tmpDir
    New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
    $sp = Join-Path $tmpDir "spec.json"
    $specObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sp -Encoding UTF8
    $o = & $GEngine -SpecFile $sp -ProjectDir $tmpDir 2>&1 | Out-String
    if ($o -match "WARNING") { $script:warnObserved++ }
    if ($o -match "BLOCKED|FAILED") { $script:blockedObserved++ }
    $stls = @(Get-ChildItem -LiteralPath (Join-Path $tmpDir "output") -Filter "*.stl" -ErrorAction SilentlyContinue)
    $vdir = Join-Path $tmpDir "validation"
    $stats = @()
    if (Test-Path -LiteralPath $vdir) {
      foreach ($f in (Get-ChildItem -LiteralPath $vdir -Filter "*.validation.json")) {
        $stats += [string](Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json).status
      }
    }
    $info = [pscustomobject]@{ dir = $tmpDir; stls = $stls; statuses = $stats; output = $o }
    $ok = $false; $detail = ""
    if ($expect -eq "PASS") { $ok = ($stls.Count -gt 0 -and ($stats -notcontains "BLOCKED") -and ($stats -notcontains "FAILED_AFTER_RETRIES") -and ($stats -notcontains "FAIL")) }
    else { $ok = ($stls.Count -eq 0 -or ($stats -contains "BLOCKED") -or ($stats -contains "FAILED_AFTER_RETRIES") -or ($stats -contains "FAIL")) }
    $detail = $(if ($ok) { "beklenen sonuc ($expect)" } else { "stl=$($stls.Count) status=$($stats -join ',')" })
    if ($ok -and $check) { $r2 = & $check $info; $ok = $r2.ok; $detail = $r2.detail }
    Add-PResult $tid $ok $detail
  } catch { Add-PResult $tid $false $_.Exception.Message }
  finally { Remove-PTemp $tmpDir }
}

# ---- T21: uctan uca PASS ----
$chk21 = {
  param($dir, $res)
  $s = Test-Path -LiteralPath (Join-Path $dir (Join-Path "output" "body.stl"))
  $v = Test-Path -LiteralPath (Join-Path $dir (Join-Path "validation" "body.validation.json"))
  $ok = ($s -and $v)
  return @{ ok = $ok; detail = $(if ($ok) { "STL+validation uretildi" } else { "dosya eksik" }) }
}
Invoke-PipeCase "T21" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk21

# ---- T22: eksik -> NEEDS_INPUT, STL yok ----
$chk22 = {
  param($dir, $res)
  $q = 0; if ($res.questions) { $q = @($res.questions).Count }
  $s = Test-Path -LiteralPath (Join-Path $dir (Join-Path "output" "body.stl"))
  $ok = ($q -ge 1 -and -not $s)
  return @{ ok = $ok; detail = $(if ($ok) { "soru var ($q), model yok" } else { "soru=$q stl=$s" }) }
}
Invoke-PipeCase "T22" "60x40x20 kutu, delik 12" $null "NEEDS_INPUT" $chk22

# ---- T23: cevap -> PASS + merkez islenmis ----
$chk23 = {
  param($dir, $res)
  $sp = Get-Content -LiteralPath (Join-Path $dir "spec.json") -Raw | ConvertFrom-Json
  $cx = $sp.components[0].holes[0].center_x_mm
  $ok = ([double]$cx -eq 20)
  return @{ ok = $ok; detail = $(if ($ok) { "merkez 20,20 islendi" } else { "merkez=$cx" }) }
}
Invoke-PipeCase "T23" "60x40x20 kutu, delik 12" @{ "body-hole-h1-center" = "20,20" } "PASS" $chk23

# ---- T24/T25/T26: SCAD bolum + STL + kategoriler (T21 tekrarinda dogrula) ----
$chk24 = {
  param($dir, $res)
  $t = Get-Content -LiteralPath (Join-Path $dir (Join-Path "cad" "body.scad")) -Raw
  $ok = ($t -match "PARAMETERS" -and $t -match "GEOMETRY")
  return @{ ok = $ok; detail = $(if ($ok) { "bolumlu SCAD" } else { "bolum eksik" }) }
}
Invoke-PipeCase "T24" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk24
$chk25 = {
  param($dir, $res)
  $f = Get-Item -LiteralPath (Join-Path $dir (Join-Path "output" "body.stl")) -ErrorAction SilentlyContinue
  $ok = ($f -and $f.Length -gt 1024)
  return @{ ok = $ok; detail = $(if ($ok) { "STL $($f.Length) bayt" } else { "STL yok/kucuk" }) }
}
Invoke-PipeCase "T25" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk25
$chk26 = {
  param($dir, $res)
  $v = Get-Content -LiteralPath (Join-Path $dir (Join-Path "validation" "body.validation.json")) -Raw | ConvertFrom-Json
  $ok = ($v.categories -and $v.categories.geometry -and $v.categories.feature -and $v.categories.assembly -and $v.categories.manufacturability)
  return @{ ok = $ok; detail = $(if ($ok) { "4 kategori var" } else { "kategori eksik" }) }
}
Invoke-PipeCase "T26" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk26

# ---- T27: multi-part ----
$chk27 = {
  param($dir, $res)
  $n = @(Get-ChildItem -LiteralPath (Join-Path $dir "output") -Filter "*.stl").Count
  $ok = ($n -eq 2)
  return @{ ok = $ok; detail = $(if ($ok) { "2 STL" } else { "stl=$n" }) }
}
Invoke-PipeCase "T27" "60x40x20 kutu, kapak yukseklik 6, 0.2 mm bosluk" $null "PASS" $chk27

# ---- T28: project.json alanlari ----
$chk28 = {
  param($dir, $res)
  $p = Get-Content -LiteralPath (Join-Path $dir "project.json") -Raw | ConvertFrom-Json
  $ok = ($p.project_id -and $p.designspec_version -eq "2.0" -and $p.engine_version -eq "V1.1" -and $p.gcode_available -eq $false -and $p.created_at -and $p.parts)
  return @{ ok = $ok; detail = $(if ($ok) { "tum alanlar var" } else { "alan eksik" }) }
}
Invoke-PipeCase "T28" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk28

# ---- T29: gecersiz spec -> BLOCKED ----
$s29 = [pscustomobject]@{ project_name = "t29"; prompt = "t29"; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @() }
$c29 = New-V2Comp "body" "box"
$c29.base.width_mm = -5; $c29.base.depth_mm = 40; $c29.base.height_mm = 20
$s29.components = @($c29)
Invoke-EngCase "T29" $s29 "BLOCKED" $null

# ---- T30: AI MOCK ----
try {
  $tmpA = Join-Path ([System.IO.Path]::GetTempPath()) "ai-mock-spec.json"
  $aiTxt = & $AIProv -Provider MOCK -Prompt "40x20x10 kutu" -ProjectName "aimock" -OutSpec $tmpA 2>&1 | Out-String
  $o = $aiTxt | ConvertFrom-Json
  $ok = ($o.provider -eq "MOCK" -and $o.mock -eq $true -and (Test-Path -LiteralPath $tmpA))
  Remove-Item -LiteralPath $tmpA -Force -ErrorAction SilentlyContinue
  Add-PResult "T30" $ok $(if ($ok) { "MOCK spec uretti, etiketli" } else { "provider=$($o.provider)" })
} catch { Add-PResult "T30" $false $_.Exception.Message }

# ---- T31: recent-load geri okuma ----
$chk31 = {
  param($dir, $res)
  $p = Get-Content -LiteralPath (Join-Path $dir "project.json") -Raw | ConvertFrom-Json
  $n = @(Get-ChildItem -LiteralPath (Join-Path $dir "validation") -Filter "*.validation.json").Count
  $ok = (@($p.parts).Count -ge 1 -and $n -ge 1)
  return @{ ok = $ok; detail = $(if ($ok) { "proje geri yuklendi" } else { "eksik" }) }
}
Invoke-PipeCase "T31" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk31

# ---- T32: warning yayilimi ----
$s32 = [pscustomobject]@{ project_name = "t32"; prompt = "t32"; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @() }
$c32 = New-V2Comp "body" "box"
$c32.base.width_mm = 40; $c32.base.depth_mm = 20; $c32.base.height_mm = 10
$c32.hollow = [pscustomobject]@{ wall_mm = 0.6; open_top = $true }
$s32.components = @($c32)
$chk32 = {
  param($info)
  $w = ($info.output -match "WARNING")
  $st = @($info.statuses)
  $ok = ($w -and ($st -notcontains "BLOCKED") -and ($st -notcontains "FAIL"))
  return @{ ok = $ok; detail = $(if ($ok) { "uyari var, FAIL yok" } else { "status=$($st -join ',')" }) }
}
Invoke-EngCase "T32" $s32 "PASS" $chk32

# ---- T33: blocked yayilimi (pipeline) ----
Invoke-PipeCase "T33" "100x80x50 kutu, icini bosalt duvar 60, ustu acik" $null "BLOCKED" $null

# ---- T34: portable ----
$chk34 = {
  param($dir, $res)
  $prof = [System.Environment]::GetEnvironmentVariable("USERPROFILE")
  $hits = New-Object System.Collections.Generic.List[string]
  foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object { $_.Extension -match "json|md|scad|log" })) {
    $t = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($t -and $t.Contains($prof)) { $hits.Add($f.Name) }
  }
  $ok = ($hits.Count -eq 0)
  return @{ ok = $ok; detail = $(if ($ok) { "hardcoded yol yok" } else { "bulundu: $($hits -join ',')" }) }
}
Invoke-PipeCase "T34" "60x40x20 kutu, delik 12 merkez 20,20" $null "PASS" $chk34

# ---- Negatifler T35-T44 ----
function New-Neg($tid, $mut) {
  $c = New-V2Comp "body" "box"
  $c.base.width_mm = 60; $c.base.depth_mm = 40; $c.base.height_mm = 20
  & $mut $c
  $s = [pscustomobject]@{ project_name = $tid; prompt = $tid; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @($c) }
  return $s
}
$m35 = { param($c) $c.hollow = [pscustomobject]@{ wall_mm = $null; open_top = $true } }
Invoke-EngCase "T35" (New-Neg "T35" $m35) "BLOCKED" $null
$m36 = { param($c) $c.holes = @([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = 10; center_x_mm = $null; center_y_mm = $null; axis = "z"; depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null; screw = $null; status = "missing" }) }
Invoke-EngCase "T36" (New-Neg "T36" $m36) "BLOCKED" $null
$m37 = { param($c) }
$s37 = [pscustomobject]@{ project_name = "T37"; prompt = "T37"; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @() }
$c37a = New-V2Comp "body" "box"
$c37a.base.width_mm = 60; $c37a.base.depth_mm = 40; $c37a.base.height_mm = 20
$c37b = New-V2Comp "lid" "box"
$c37b.base.width_mm = 60; $c37b.base.depth_mm = 40; $c37b.base.height_mm = 6
$s37.components = @($c37a, $c37b)
$s37.assembly = [pscustomobject]@{ parts = @("body", "lid"); joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = $null; screw = $null }) }
Invoke-EngCase "T37" $s37 "BLOCKED" $null
$m38 = { param($c) $c.base.width_mm = 100; $c.base.depth_mm = 80; $c.base.height_mm = 50; $c.hollow = [pscustomobject]@{ wall_mm = 60; open_top = $true } }
Invoke-EngCase "T38" (New-Neg "T38" $m38) "BLOCKED" $null
$m39 = { param($c) $c.base.width_mm = -10 }
Invoke-EngCase "T39" (New-Neg "T39" $m39) "BLOCKED" $null
$m40 = { param($c) $c.base.height_mm = 0 }
Invoke-EngCase "T40" (New-Neg "T40" $m40) "BLOCKED" $null
$m41 = { param($c) $c.holes = @([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = 200; center_x_mm = 30; center_y_mm = 20; axis = "z"; depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null; screw = $null; status = "ok" }) }
Invoke-EngCase "T41" (New-Neg "T41" $m41) "BLOCKED" $null
$m42 = { param($c) $c.tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = 0.2; fit_to = "hayalet-parca"; status = "ok" } }
Invoke-EngCase "T42" (New-Neg "T42" $m42) "BLOCKED" $null
$m43 = { param($c) $c.transforms = @([pscustomobject]@{ op = "mirror"; axis = "q" }) }
Invoke-EngCase "T43" (New-Neg "T43" $m43) "BLOCKED" $null
$m44 = { param($c) $c.tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = -0.5; fit_to = $null; status = "ok" } }
Invoke-EngCase "T44" (New-Neg "T44" $m44) "BLOCKED" $null

# ---- TA: organizer full -> PASS 5 STL ----
$sA = [pscustomobject]@{ project_name = "ta"; prompt = "ta"; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @() }
$ca = New-V2Comp "body" "box"
$ca.base.width_mm = 120; $ca.base.depth_mm = 80; $ca.base.height_mm = 60
$ca.hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true }
$d1 = New-V2Comp "div1" "box"
$d1.base.width_mm = 50; $d1.base.depth_mm = 70; $d1.base.height_mm = 40
$d2 = New-V2Comp "div2" "box"
$d2.base.width_mm = 30; $d2.base.depth_mm = 70; $d2.base.height_mm = 40
$ba = New-V2Comp "base" "box"
$ba.base.width_mm = 120; $ba.base.depth_mm = 80; $ba.base.height_mm = 5
$la = New-V2Comp "lid" "box"
$la.base.width_mm = 120; $la.base.depth_mm = 80; $la.base.height_mm = 6
$la.tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = 0.2; fit_to = "body"; status = "ok" }
$sA.components = @($ca, $d1, $d2, $ba, $la)
$sA.assembly = [pscustomobject]@{ parts = @("body", "div1", "div2", "base", "lid"); joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = 0.2; screw = $null }) }
$chkA = {
  param($info)
  $ok = ($info.stls.Count -eq 5)
  return @{ ok = $ok; detail = $(if ($ok) { "5 parca STL" } else { "stl=$($info.stls.Count)" }) }
}
Invoke-EngCase "TA" $sA "PASS" $chkA

# ---- TB: enclosure, clearance eksik -> NEEDS/BLOCKED (model yok) ----
$sB = [pscustomobject]@{ project_name = "tb"; prompt = "tb"; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @() }
$cb = New-V2Comp "bottom" "box"
$cb.base.width_mm = 100; $cb.base.depth_mm = 60; $cb.base.height_mm = 25
$cb.hollow = [pscustomobject]@{ wall_mm = 2; open_top = $true }
$lb = New-V2Comp "lid" "box"
$lb.base.width_mm = 100; $lb.base.depth_mm = 60; $lb.base.height_mm = 5
$sB.components = @($cb, $lb)
$sB.assembly = [pscustomobject]@{ parts = @("bottom", "lid"); joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "bottom"; part_b = "lid"; clearance_mm = $null; screw = $null }) }
Invoke-EngCase "TB" $sB "BLOCKED" $null

# ---- TC: phone stand, destek olcusu eksik -> NEEDS/BLOCKED (model yok) ----
$sC = [pscustomobject]@{ project_name = "tc"; prompt = "tc"; metadata = [pscustomobject]@{ spec_version = "2.0" }; assembly = $null; material = $null; components = @() }
$cc = New-V2Comp "base" "box"
$cc.base.width_mm = 80; $cc.base.depth_mm = 60; $cc.base.height_mm = 8
$cs = New-V2Comp "support" "box"
$cs.base.width_mm = 80; $cs.base.depth_mm = $null; $cs.base.height_mm = 70
$sC.components = @($cc, $cs)
Invoke-EngCase "TC" $sC "BLOCKED" $null

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "PIPELINE SONUC: $passed / $($results.Count) test gecti"
Write-Output "GOZLEM: $warnObserved WARNING, $blockedObserved BLOCKED"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
