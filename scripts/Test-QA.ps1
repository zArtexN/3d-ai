<#
.SYNOPSIS
  Q&A cevap parser testleri (dogal cevaplar kabul, muglak/gecersiz red).
.DESCRIPTION
  T-QA-01 dia "10" -> PASS | T-QA-02 "10 mm" -> PASS | T-QA-03 "O10" -> PASS
  T-QA-04 center "15,15" -> PASS | T-QA-05 tolerance "0.2 mm" -> PASS
  T-QA-06 "biraz"/bos -> red (tekrar soru sinyali) | T-QA-07 "-5" -> red | T-QA-08 "0" -> red
  T-QA-09 center "15 15" (bosluklu) -> PASS | T-QA-10 stabil ID ile tekrar cevap -> PASS
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-QA.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-QAResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-QAHole($id, $dia, $cx, $cy, $st) {
  return [pscustomobject]@{
    id = $id; hole_type = "through"; diameter_mm = $dia
    center_x_mm = $cx; center_y_mm = $cy; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = $st
  }
}
function New-QABody($holes, $tol) {
  return [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 60; depth_mm = 40; height_mm = 20 }
    hollow = $null; holes = $holes; cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $tol; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
  }
}
function New-QABodyNoDims($holes, $tol) {
  return [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }
    hollow = $null; holes = $holes; cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $tol; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
  }
}
function New-QASpec($dir, $name, $comp) {
  $spec = [pscustomobject]@{
    project_name = $name; prompt = $name
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    components = @($comp); assembly = $null; material = $null
  }
  $sp = Join-Path $dir "spec.json"
  $spec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sp -Encoding UTF8
  $qsTxt = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $sp -AsJson 2>&1 | Out-String
  $qsObj = $qsTxt | ConvertFrom-Json
  $qf = Join-Path $dir "spec.questions.json"
  if ($null -eq $qsObj) { "[]" | Set-Content -LiteralPath $qf -Encoding UTF8 }
  else { @($qsObj) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qf -Encoding UTF8 }
  return $sp
}
function Invoke-QAAnswer($sp, $qid, $ans) {
  try {
    & (Join-Path $EngineDir "Update-SpecAnswer.ps1") -SpecFile $sp -QuestionId $qid -Answer $ans 2>&1 | Out-Null
    return @{ applied = $true; error = "" }
  } catch {
    return @{ applied = $false; error = [string]$_.Exception.Message }
  }
}
function New-QADir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("qa-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

$diaId = "body-hole-h1-dia"
$cenId = "body-hole-h1-center"
$tolId = "body-clearance"

# T-QA-01/02/03: dogal cap cevaplari
foreach ($case in @(@("T-QA-01", "10"), @("T-QA-02", "10 mm"), @("T-QA-03", "Ø10"), @("T-QA-03b", "cap 10")) ) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
    $r = Invoke-QAAnswer $sp $diaId $case[1]
    $v = -1
    if ($r.applied) { $v = [double](Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0].diameter_mm }
    $ok = ($r.applied -and $v -eq 10)
    Add-QAResult $case[0] $ok $(if ($ok) { "cap=10 islendi" } else { "hata: $($r.error)" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-04: merkez
$d = New-QADir "T-QA-04"
try {
  $sp = New-QASpec $d "T-QA-04" (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
  $r = Invoke-QAAnswer $sp $cenId "15,15"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r.applied -and [double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15)
  Add-QAResult "T-QA-04" $ok $(if ($ok) { "merkez 15,15" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-04" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-05: tolerans
$d = New-QADir "T-QA-05"
try {
  $tol = [pscustomobject]@{ type = "clearance"; clearance_mm = $null; fit_to = $null; status = "missing" }
  $sp = New-QASpec $d "T-QA-05" (New-QABody @() $tol)
  $r = Invoke-QAAnswer $sp $tolId "0.2 mm"
  $v = -1
  if ($r.applied) { $v = [double](Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].tolerance.clearance_mm }
  $ok = ($r.applied -and $v -eq 0.2)
  Add-QAResult "T-QA-05" $ok $(if ($ok) { "tolerans 0.2" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-05" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-06: muglak + bos -> red
$d = New-QADir "T-QA-06"
try {
  $sp = New-QASpec $d "T-QA-06" (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
  $r1 = Invoke-QAAnswer $sp $diaId "biraz"
  $r2 = Invoke-QAAnswer $sp $diaId ""
  $ok = ((-not $r1.applied) -and (-not $r2.applied))
  Add-QAResult "T-QA-06" $ok $(if ($ok) { "muglak/bos reddedildi" } else { "yanlis kabul!" })
} catch { Add-QAResult "T-QA-06" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-07/08: negatif + sifir -> red
foreach ($case in @(@("T-QA-07", "-5"), @("T-QA-08", "0"))) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
    $r = Invoke-QAAnswer $sp $diaId $case[1]
    $ok = (-not $r.applied)
    Add-QAResult $case[0] $ok $(if ($ok) { "gecersiz red: $($r.error)" } else { "yanlis kabul!" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-11/12: center varyantlari
foreach ($case in @(@("T-QA-11", "15 mm, 15 mm"), @("T-QA-12", "merkez 15 15"), @("T-QA-12b", "15 mm 15 mm"), @("T-QA-12c", "merkez 15,15"))) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
    $r = Invoke-QAAnswer $sp $cenId $case[1]
    $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
    $ok = ($r.applied -and [double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15)
    Add-QAResult $case[0] $ok $(if ($ok) { "kabul: $($case[1])" } else { "hata: $($r.error)" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-13/14/15/16: gecersiz merkezler
foreach ($case in @(@("T-QA-13", "15"), @("T-QA-14", "-1,15"), @("T-QA-15", "0,15"), @("T-QA-16", "abc"))) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
    $r = Invoke-QAAnswer $sp $cenId $case[1]
    $ok = (-not $r.applied)
    Add-QAResult $case[0] $ok $(if ($ok) { "reddedildi: $($r.error)" } else { "yanlis kabul!" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}
$d = New-QADir "T-QA-09"
try {
  $sp = New-QASpec $d "T-QA-09" (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
  $r = Invoke-QAAnswer $sp $cenId "15 15"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r.applied -and [double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15)
  Add-QAResult "T-QA-09" $ok $(if ($ok) { "bosluklu cift kabul" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-09" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-10: stabil ID ile cift cevap (once yanlis sira riski yok)
$d = New-QADir "T-QA-10"
try {
  $sp = New-QASpec $d "T-QA-10" (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
  $r1 = Invoke-QAAnswer $sp $diaId "12"
  $r2 = Invoke-QAAnswer $sp $cenId "20,20"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r1.applied -and $r2.applied -and [double]$h.diameter_mm -eq 12 -and [double]$h.center_x_mm -eq 20)
  Add-QAResult "T-QA-10" $ok $(if ($ok) { "sirali cevaplar dogru alanlara" } else { "karisti" })
} catch { Add-QAResult "T-QA-10" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-17: UI-esdeger adimli akis open_top -> center (task repro)
$d = New-QADir "T-QA-17"
try {
  $pipe = Join-Path $Root (Join-Path "engine" "Invoke-Pipeline.ps1")
  $pd = Join-Path $d "proj"
  $pr = "50x50x10 kutu, icini bosalt duvar 2, delik 10"
  $o1txt = & $pipe -Prompt $pr -ProjectName "qa17" -ProjectDir $pd 2>&1 | Out-String
  $o1 = $o1txt | ConvertFrom-Json
  $s1ok = ([string]$o1.status -eq "NEEDS_INPUT")
  $a1 = [pscustomobject]@{}
  $a1 | Add-Member -NotePropertyName "body-hollow_top" -NotePropertyValue "kapali"
  $a1 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $d "a1.json") -Encoding UTF8
  $o2txt = & $pipe -Prompt $pr -ProjectName "qa17" -ProjectDir $pd -AnswersFile (Join-Path $d "a1.json") 2>&1 | Out-String
  $o2 = $o2txt | ConvertFrom-Json
  $q2ids = @(@($o2.questions) | ForEach-Object { [string]$_.question_id })
  $s2ok = ([string]$o2.status -eq "NEEDS_INPUT" -and ($q2ids -contains "body-hole-h1-center") -and -not ($o2.errors -join " " -match "acik"))
  $a2 = [pscustomobject]@{}
  $a2 | Add-Member -NotePropertyName "body-hollow_top" -NotePropertyValue "kapali"
  $a2 | Add-Member -NotePropertyName "body-hole-h1-center" -NotePropertyValue "15,15"
  $a2 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $d "a2.json") -Encoding UTF8
  $o3txt = & $pipe -Prompt $pr -ProjectName "qa17" -ProjectDir $pd -AnswersFile (Join-Path $d "a2.json") 2>&1 | Out-String
  $o3 = $o3txt | ConvertFrom-Json
  $s3ok = ([string]$o3.status -eq "PASS")
  $stlOk = Test-Path -LiteralPath (Join-Path $pd (Join-Path "output" "body.stl"))
  $ok = ($s1ok -and $s2ok -and $s3ok -and $stlOk)
  Add-QAResult "T-QA-17" $ok $(if ($ok) { "open_top->center->PASS, karisma yok" } else { "s1=$s1ok s2=$s2ok s3=$s3ok stl=$stlOk" })
} catch { Add-QAResult "T-QA-17" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-18: bayat qid -> NEEDS_INPUT, carpisma yok
$d = New-QADir "T-QA-18"
try {
  $pipe = Join-Path $Root (Join-Path "engine" "Invoke-Pipeline.ps1")
  $pd = Join-Path $d "proj"
  $pr = "60x40x20 kutu, delik 12 merkez 20,20"
  $ax = [pscustomobject]@{}
  $ax | Add-Member -NotePropertyName "q1" -NotePropertyValue "kapali"
  $ax | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $d "ax.json") -Encoding UTF8
  $oTxt = & $pipe -Prompt $pr -ProjectName "qa18" -ProjectDir $pd -AnswersFile (Join-Path $d "ax.json") 2>&1 | Out-String
  $o = $oTxt | ConvertFrom-Json
  $errs = ""
  if ($o.errors) { $errs = @($o.errors) -join " " }
  $ok = ([string]$o.status -eq "NEEDS_INPUT" -and $errs -match "Soru bulunamadi")
  Add-QAResult "T-QA-18" $ok $(if ($ok) { "bayat ID guvenli reddedildi" } else { "status=$([string]$o.status)" })
} catch { Add-QAResult "T-QA-18" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-19: "merkez 15 15" (bosluklu, onekli)
$d = New-QADir "T-QA-19"
try {
  $sp = New-QASpec $d "T-QA-19" (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
  $r = Invoke-QAAnswer $sp $cenId "merkez 15 15"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r.applied -and [double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15)
  Add-QAResult "T-QA-19" $ok $(if ($ok) { "kabul" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-19" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-20: govde olcusu cevaplari (160x100x45 bug repro: tum dogal varyantlar kabul)
$dimsId = "body-dims"
$multA = [char]0xD7
foreach ($case in @(@("T-QA-20a", "160x100x45"), @("T-QA-20b", "160 x 100 x 45"), @("T-QA-20c", ("160 " + $multA + " 100 " + $multA + " 45 mm")), @("T-QA-20d", "160,100,45"), @("T-QA-20e", "160 100 45"), @("T-QA-20f", "160mm x 100mm x 45mm")) ) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABodyNoDims @() $null)
    $r = Invoke-QAAnswer $sp $dimsId $case[1]
    $b = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].base
    $ok = ($r.applied -and [double]$b.width_mm -eq 160 -and [double]$b.depth_mm -eq 100 -and [double]$b.height_mm -eq 45)
    Add-QAResult $case[0] $ok $(if ($ok) { "kabul: $($case[1])" } else { "hata: $($r.error)" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-21: gecersiz govde olculeri red (2 boyut, anlamsiz, negatif)
foreach ($case in @(@("T-QA-21a", "20x10"), @("T-QA-21b", "biraz"), @("T-QA-21c", "abc"), @("T-QA-21d", "-5x10x20")) ) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABodyNoDims @() $null)
    $r = Invoke-QAAnswer $sp $dimsId $case[1]
    $ok = ((-not $r.applied) -and [string]$r.error -ne "")
    Add-QAResult $case[0] $ok $(if ($ok) { "reddedildi: $($r.error)" } else { "yanlis kabul!" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-22: uctan uca govde-dims cevabi (eksik -> sor, "160x100x45" -> isle, tekrar sorma)
$d = New-QADir "T-QA-22"
try {
  $pipe = Join-Path $Root (Join-Path "engine" "Invoke-Pipeline.ps1")
  $pd = Join-Path $d "proj"
  $pr = "Duvar kalinligi 3 mm olan kutu yap."
  $o1txt = & $pipe -Prompt $pr -ProjectName "qa22" -ProjectDir $pd 2>&1 | Out-String
  $o1 = $o1txt | ConvertFrom-Json
  $q1ids = @(@($o1.questions) | ForEach-Object { [string]$_.question_id })
  $s1ok = ([string]$o1.status -eq "NEEDS_INPUT" -and ($q1ids -contains "body-dims"))
  $a1 = [pscustomobject]@{}
  $a1 | Add-Member -NotePropertyName "body-dims" -NotePropertyValue "160x100x45"
  $a1 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $d "a1.json") -Encoding UTF8
  $o2txt = & $pipe -Prompt $pr -ProjectName "qa22" -ProjectDir $pd -AnswersFile (Join-Path $d "a1.json") 2>&1 | Out-String
  $o2 = $o2txt | ConvertFrom-Json
  $q2ids = @(@($o2.questions) | ForEach-Object { [string]$_.question_id })
  $sp2 = Get-Content -LiteralPath (Join-Path $pd "spec.json") -Raw | ConvertFrom-Json
  $bb = $sp2.components[0].base
  $errs2 = ""
  if ($o2.errors) { $errs2 = @($o2.errors) -join " " }
  $s2ok = (($errs2 -notmatch "Cevap islenemedi") -and ($q2ids -notcontains "body-dims") -and [double]$bb.width_mm -eq 160 -and [double]$bb.depth_mm -eq 100 -and [double]$bb.height_mm -eq 45)
  $a2 = [pscustomobject]@{}
  $a2 | Add-Member -NotePropertyName "body-dims" -NotePropertyValue "160x100x45"
  $a2 | Add-Member -NotePropertyName "body-hollow_top" -NotePropertyValue "kapali"
  $a2 | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $d "a2.json") -Encoding UTF8
  $o3txt = & $pipe -Prompt $pr -ProjectName "qa22" -ProjectDir $pd -AnswersFile (Join-Path $d "a2.json") 2>&1 | Out-String
  $o3 = $o3txt | ConvertFrom-Json
  $stlOk = Test-Path -LiteralPath (Join-Path $pd (Join-Path "output" "body.stl"))
  $s3ok = ([string]$o3.status -eq "PASS" -and $stlOk)
  $ok = ($s1ok -and $s2ok -and $s3ok)
  Add-QAResult "T-QA-22" $ok $(if ($ok) { "eksik soruldu, cevap islendi, PASS" } else { "s1=$s1ok s2=$s2ok s3=$s3ok errs=$errs2" })
} catch { Add-QAResult "T-QA-22" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-23..29: cutout cevaplari (olcu/konum/derinlik; tek sayi ve dogal formlar).
function New-QACut($w, $l, $px, $py, $dep, $pen, $st) {
  return [pscustomobject]@{
    id = "c1"; kind = "rect"; face = "front"; pos_x_mm = $px; pos_y_mm = $py
    width_mm = $w; length_mm = $l; depth_mm = $dep; penetration = $pen; status = $st
  }
}
function New-QACutBody($cut) {
  return [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 80; depth_mm = 40; height_mm = 20 }
    hollow = $null; holes = @(); cutouts = @($cut); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
  }
}
function Get-QACut($sp) {
  return (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].cutouts[0]
}
# T-QA-23: olcu+derinlik korunurken tek sayi ile pos_x.
$d = New-QADir "T-QA-23"
try {
  $sp = New-QASpec $d "T-QA-23" (New-QACutBody (New-QACut 20 10 $null 12 8 $null "missing"))
  $r = Invoke-QAAnswer $sp "body-cutout-c1" "10"
  $t = Get-QACut $sp
  $ok = ($r.applied -and [double]$t.pos_x_mm -eq 10 -and [double]$t.pos_y_mm -eq 12 -and [double]$t.depth_mm -eq 8 -and [double]$t.width_mm -eq 20 -and [double]$t.length_mm -eq 10)
  Add-QAResult "T-QA-23" $ok $(if ($ok) { "tek sayi pos_x doldurdu, digerleri korundu" } else { "applied=$($r.applied) err=$($r.error)" })
} catch { Add-QAResult "T-QA-23" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
# T-QA-24: sonraki tek sayi ile pos_y.
$d = New-QADir "T-QA-24"
try {
  $sp = New-QASpec $d "T-QA-24" (New-QACutBody (New-QACut 20 10 70 $null 8 $null "missing"))
  $r = Invoke-QAAnswer $sp "body-cutout-c1" "3"
  $t = Get-QACut $sp
  $ok = ($r.applied -and [double]$t.pos_y_mm -eq 3 -and [double]$t.pos_x_mm -eq 70 -and [double]$t.depth_mm -eq 8)
  Add-QAResult "T-QA-24" $ok $(if ($ok) { "tek sayi pos_y doldurdu" } else { "applied=$($r.applied) err=$($r.error)" })
} catch { Add-QAResult "T-QA-24" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
# T-QA-25: sonraki tek sayi ile depth + status ok.
$d = New-QADir "T-QA-25"
try {
  $sp = New-QASpec $d "T-QA-25" (New-QACutBody (New-QACut 20 10 70 12 $null $null "missing"))
  $r = Invoke-QAAnswer $sp "body-cutout-c1" "6"
  $t = Get-QACut $sp
  $ok = ($r.applied -and [double]$t.depth_mm -eq 6 -and [string]$t.status -eq "ok")
  Add-QAResult "T-QA-25" $ok $(if ($ok) { "tek sayi depth doldurdu, status ok" } else { "applied=$($r.applied) err=$($r.error)" })
} catch { Add-QAResult "T-QA-25" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
# T-QA-26: "yatay 10" ve "dikey alttan 3" dogal formlar.
$d = New-QADir "T-QA-26"
try {
  $sp = New-QASpec $d "T-QA-26" (New-QACutBody (New-QACut 20 10 $null $null 8 $null "missing"))
  $r1 = Invoke-QAAnswer $sp "body-cutout-c1" "yatay 10"
  $t1 = Get-QACut $sp
  $r2 = Invoke-QAAnswer $sp "body-cutout-c1" "dikey alttan 3"
  $t2 = Get-QACut $sp
  $ok = ($r1.applied -and [double]$t1.pos_x_mm -eq 10 -and $r2.applied -and [double]$t2.pos_y_mm -eq 3 -and [double]$t2.pos_x_mm -eq 10 -and [double]$t2.depth_mm -eq 8)
  Add-QAResult "T-QA-26" $ok $(if ($ok) { "yatay/dikey formlar islendi" } else { "e1=$($r1.error) e2=$($r2.error)" })
} catch { Add-QAResult "T-QA-26" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
# T-QA-27: "konum 10,3" ve "konum 10 3" + bilinen alanlar korunur.
$d = New-QADir "T-QA-27"
try {
  $sp = New-QASpec $d "T-QA-27" (New-QACutBody (New-QACut 20 10 $null $null 8 $null "missing"))
  $r1 = Invoke-QAAnswer $sp "body-cutout-c1" "konum 10,3"
  $t1 = Get-QACut $sp
  $sp2dir = New-QADir "T-QA-27b"
  $sp2 = New-QASpec $sp2dir "T-QA-27b" (New-QACutBody (New-QACut 20 10 $null $null 8 $null "missing"))
  $r2 = Invoke-QAAnswer $sp2 "body-cutout-c1" "konum 10 3"
  $t2 = Get-QACut $sp2
  $ok = ($r1.applied -and [double]$t1.pos_x_mm -eq 10 -and [double]$t1.pos_y_mm -eq 3 -and [double]$t1.width_mm -eq 20 -and [double]$t1.depth_mm -eq 8 -and $r2.applied -and [double]$t2.pos_x_mm -eq 10 -and [double]$t2.pos_y_mm -eq 3)
  Add-QAResult "T-QA-27" $ok $(if ($ok) { "konum formlari islendi, bilinenler korundu" } else { "e1=$($r1.error) e2=$($r2.error)" })
} catch { Add-QAResult "T-QA-27" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue; Remove-Item -LiteralPath (Join-Path ([System.IO.Path]::GetTempPath()) "qa-T-QA-27b") -Recurse -Force -ErrorAction SilentlyContinue }
# T-QA-28: "5x12" ve "derinlik 6" mevcut davranis korunur.
$d = New-QADir "T-QA-28"
try {
  $sp = New-QASpec $d "T-QA-28" (New-QACutBody (New-QACut $null $null 70 12 $null $null "missing"))
  $r1 = Invoke-QAAnswer $sp "body-cutout-c1" "5x12"
  $t1 = Get-QACut $sp
  $r2 = Invoke-QAAnswer $sp "body-cutout-c1" "derinlik 6"
  $t2 = Get-QACut $sp
  $ok = ($r1.applied -and [double]$t1.width_mm -eq 5 -and [double]$t1.length_mm -eq 12 -and $r2.applied -and [double]$t2.depth_mm -eq 6 -and [double]$t2.pos_x_mm -eq 70 -and [double]$t2.pos_y_mm -eq 12)
  Add-QAResult "T-QA-28" $ok $(if ($ok) { "olcu ve derinlik formlari korunur" } else { "e1=$($r1.error) e2=$($r2.error)" })
} catch { Add-QAResult "T-QA-28" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
# T-QA-29: anlasilmayan cevap degerleri silmez.
$d = New-QADir "T-QA-29"
try {
  $sp = New-QASpec $d "T-QA-29" (New-QACutBody (New-QACut 20 10 70 $null 8 $null "missing"))
  $r = Invoke-QAAnswer $sp "body-cutout-c1" "abc"
  $t = Get-QACut $sp
  $ok = ((-not $r.applied) -and [double]$t.width_mm -eq 20 -and [double]$t.pos_x_mm -eq 70 -and [double]$t.depth_mm -eq 8 -and $null -eq $t.pos_y_mm)
  Add-QAResult "T-QA-29" $ok $(if ($ok) { "reddedildi, degerler korundu" } else { "applied=$($r.applied)" })
} catch { Add-QAResult "T-QA-29" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "QA SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
