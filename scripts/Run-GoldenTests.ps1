<#
.SYNOPSIS
  GOLDEN + semantic regression testleri (organizer golden, matrix, no-reask, snapshot, fuzz).
.DESCRIPTION
  G1 organizer-golden (gorev #26 beklenen 20+ alan + coverage + trace + pipeline).
  G2 cutout format matrix | G3 hole-dia matrix | G4 no-reask | G5 determinism +
  snapshot | G6 adversarial correction | G7 duplicate | G8 units | G9 semantic->geometry
  G10 perf | G11 facts-coverage | G12 shape matrix (desteklenen + desteklenmeyen sinir).
  Cikis: 0 = hepsi gecti.
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
$Parser = Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1"
$GQ = Join-Path $EngineDir "Get-SpecQuestions.ps1"
$Facts = Join-Path $EngineDir "Get-ExplicitFacts.ps1"
$Coverage = Join-Path $EngineDir "Test-FactCoverage.ps1"
$Pipeline = Join-Path $EngineDir "Invoke-Pipeline.ps1"
$GEngine = Join-Path $EngineDir "Invoke-GeometryEngine.ps1"

$results = New-Object System.Collections.Generic.List[object]
function Add-GResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function Remove-GTemp($dir) {
  if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}
function Invoke-GoldenParse($name, $prompt) {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("golden-" + ($name -replace '[^A-Za-z0-9]+', '-') + ".json")
  Remove-GTemp $tmp
  & $Parser -Prompt $prompt -ProjectName $name -OutPath $tmp 2>&1 | Out-Null
  $spec = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
  $qsTxt = & $GQ -SpecFile $tmp -AsJson 2>&1 | Out-String
  $qsParsed = $qsTxt | ConvertFrom-Json
  $qs = @($qsParsed | Where-Object { $_ -ne $null })
  $fxTxt = & $Facts -Prompt $prompt -AsJson 2>&1 | Out-String
  $fxParsed = $fxTxt | ConvertFrom-Json
  $fx = @($fxParsed | Where-Object { $_ -ne $null })
  return @{ spec = $spec; qs = $qs; facts = $fx; file = $tmp }
}

$MULT = [char]0xD7
$ODIA = [char]0xD8
$gPromptTpl = "160{M}100{M}45 mm olculerinde, ustu acik bir elektronik ekipman kutusu yap. Duvar kalinligi 2.5 mm, taban 3 mm, dis koseler 5 mm yaricapli olsun. Iceride uzun kenar boyunca uzanan 2 adet, 2 mm kalinliginda ve ust kenardan 5 mm asagida biten bolme olsun. Arka kisa kenarin ortasinda 20{M}10 mm kablo acikligi olustur. Acikligin alt kenari tabandan 12 mm yukarida olsun. Tabanda 4 adet {O}4.2 mm gecisli vida deligi olustur. Her deligin merkezi ilgili dis kenarlardan 8 mm iceride olsun. Her deligin ust tarafinda {O}8 mm capinda ve 3 mm derinliginde counterbore olustur. Tabanin dort kosesinde 10{M}10 mm temas alani ve 1 mm pah olustur. Uzun kenarlarin ustunde 4 kapak montaj noktasi birak. PLA ve FDM baskiya uygunlugu analiz et. STL ve mumkunse 3MF olustur."
$gPrompt = $gPromptTpl -replace '\{M\}', $MULT -replace '\{O\}', $ODIA

# ---- G1: organizer golden snapshot + sorular + coverage ----
try {
  $g = Invoke-GoldenParse "G1-organizer" $gPrompt
  $b = $g.spec.components[0]
  $chk = New-Object System.Collections.Generic.List[string]
  if (-not ([double]$b.base.width_mm -eq 160 -and [double]$b.base.depth_mm -eq 100 -and [double]$b.base.height_mm -eq 45)) { $chk.Add("body") }
  if (-not ($b.hollow.open_top -eq $true)) { $chk.Add("opentop") }
  if (-not ([double]$b.hollow.wall_mm -eq 2.5)) { $chk.Add("wall") }
  if (-not ([double]$b.hollow.bottom_thickness_mm -eq 3)) { $chk.Add("bottom") }
  $fil = @($b.edge_notes | Where-Object { $_.kind -eq "fillet" } | Select-Object -First 1)
  if (-not ([double]$fil[0].value_mm -eq 5)) { $chk.Add("radius") }
  $divs = @($g.spec.components | Where-Object { $_.id -like "div*" })
  if (-not ($divs.Count -eq 2)) { $chk.Add("divcount") }
  if (-not ([double]$divs[0].thickness_mm -eq 2 -and [double]$divs[1].thickness_mm -eq 2)) { $chk.Add("divth") }
  if (-not ([double]$divs[0].top_gap_mm -eq 5)) { $chk.Add("divgap") }
  $c = $b.cutouts[0]
  if (-not ([double]$c.width_mm -eq 20 -and [double]$c.length_mm -eq 10)) { $chk.Add("cutsize") }
  if (-not ([string]$c.placement.edge -eq "rear_short_edge" -and [string]$c.placement.horizontal -eq "center")) { $chk.Add("cutedge") }
  if (-not ([double]$c.pos_y_mm -eq 12)) { $chk.Add("cutoff") }
  if (-not ([double]$c.pos_x_mm -eq 70)) { $chk.Add("cutx") }
  if (-not ([string]$c.penetration -eq "through_wall")) { $chk.Add("cutdepth") }
  $hs = @($b.holes | Where-Object { [string]$_.id -notlike "mp*" })
  if (-not ($hs.Count -eq 4)) { $chk.Add("holecount") }
  foreach ($h in $hs) {
    if (-not ([double]$h.diameter_mm -eq 4.2 -and [string]$h.hole_type -eq "through" -and [double]$h.edge_offset_mm -eq 8 -and [double]$h.cb_dia_mm -eq 8 -and [double]$h.cb_depth_mm -eq 3)) { $chk.Add("holedetail"); break }
  }
  $cp = @($hs[0].center_x_mm, $hs[0].center_y_mm, $hs[1].center_x_mm, $hs[1].center_y_mm, $hs[2].center_x_mm, $hs[2].center_y_mm, $hs[3].center_x_mm, $hs[3].center_y_mm) -join ","
  if ($cp -ne "8,8,152,8,8,92,152,92") { $chk.Add("corners:" + $cp) }
  $pads = @($b.contact_pads)
  if (-not ($pads.Count -eq 4)) { $chk.Add("pads") }
  $chm = @($b.edge_notes | Where-Object { $_.kind -eq "chamfer" } | Select-Object -First 1)
  if (-not ([double]$chm[0].value_mm -eq 1)) { $chk.Add("chamfer") }
  if (-not ([string]$g.spec.material -eq "PLA")) { $chk.Add("material") }
  $mp = @($b.holes | Where-Object { [string]$_.id -like "mp*" })
  if (-not ($mp.Count -eq 4)) { $chk.Add("mounting") }
  $lidHere = @($g.spec.components | Where-Object { $_.id -eq "lid" })
  if ($lidHere.Count -gt 0) { $chk.Add("nolidsupposed") }
  $forbid = @("body.dims", "body-hollow_top", "body-hole-h1-dia", "body-hole-h2-dia", "body-hole-h3-dia", "body-hole-h4-dia", "body-cutout-c1")
  foreach ($fid in $forbid) {
    if (@($g.qs | Where-Object { $_.question_id -eq $fid }).Count -gt 0) { $chk.Add("reask:" + $fid) }
  }
  $specNoPrompt = ($g.spec | ConvertTo-Json -Depth 8)
  $specNoPrompt = ($specNoPrompt -replace [regex]::Escape($gPrompt), '')
  if ($specNoPrompt -match '(?i)temp|nozzle|speed|gcode|retract|thread[^s]') { $chk.Add("fabricated-printer-data") }
  $fc = 0
  if (@($g.facts).Count -ge 15) { $fc = @($g.facts).Count } else { $chk.Add("facts:" + @($g.facts).Count) }
  $ok = ($chk.Count -eq 0)
  Add-GResult "G1-organizer-golden" $ok $(if ($ok) { "26 alan + soru-kumesi dogru (facts=$fc)" } else { "sapma: " + ($chk -join "|") })
  Remove-GTemp $g.file
} catch { Add-GResult "G1-organizer-golden" $false $_.Exception.Message }

# ---- G2: cutout format matrix ----
$fuzzOk = $true; $fuzzDet = ""
foreach ($fv in @("20x10", ("20" + $MULT + "10"), "20 X 10", "20 mm x 10 mm", "20mmx10mm", "20.5x10.2", "20,5x10,2", "20 carpi 10")) {
  $fp = "On yuze " + $fv + " kablo acikligi ac, konum 5,5 derinlik 8. 80x40x20 kutu yap."
  try {
    $r = Invoke-GoldenParse ("G2-" + ($fv -replace '[^A-Za-z0-9]+', '-')) $fp
    $cc = $r.spec.components[0].cutouts[0]
    $exp = $fv
    $okv = $false
    if ($fv -match "20.5|20,5") { $okv = ([double]$cc.width_mm -eq 20.5 -and [double]$cc.length_mm -eq 10.2) }
    else { $okv = ([double]$cc.width_mm -eq 20 -and [double]$cc.length_mm -eq 10) }
    if (-not $okv) { $fuzzOk = $false; $fuzzDet += $fv + "=" + $cc.width_mm + "x" + $cc.length_mm + " " }
    Remove-GTemp $r.file
  } catch { $fuzzOk = $false; $fuzzDet += $fv + ":HATA " }
}
Add-GResult "G2-cutout-matrix" $fuzzOk $(if ($fuzzOk) { "8 format ayni sonuc" } else { $fuzzDet })

# ---- G3: hole-dia matrix ----
$diaOk = $true; $diaDet = ""
foreach ($dv in @("O4.2", "o4.2", "capi 4.2 mm", "cap 4.2 mm", "4.2 mm capinda")) {
  $da = $dv -replace '^O', $ODIA -replace '^o', ([char]0xF8)
  $dp = "80x40x20 kutu, " + $da + " delik, merkez 20,20."
  try {
    $r = Invoke-GoldenParse ("G3-" + ($dv -replace '[^A-Za-z0-9]+', '-')) $dp
    $dd = $r.spec.components[0].holes[0].diameter_mm
    if (-not ([double]$dd -eq 4.2)) { $diaOk = $false; $diaDet += $dv + "=" + $dd + " " }
    Remove-GTemp $r.file
  } catch { $diaOk = $false; $diaDet += $dv + ":HATA " }
}
Add-GResult "G3-hole-dia-matrix" $diaOk $(if ($diaOk) { "5 format 4.2" } else { $diaDet })

# ---- G4: no-reask ----
try {
  $r = Invoke-GoldenParse "G4-no-reask" "50x50x20 mm kutu, duvar 3 mm, ustu acik, delik 10 soldan 5 alttan 5."
  $nq = @($r.qs).Count
  Add-GResult "G4-no-reask" ($nq -eq 0) $(if ($nq -eq 0) { "soru yok" } else { "sorular: " + ((@($r.qs) | ForEach-Object { $_.question_id }) -join ",") })
  Remove-GTemp $r.file
} catch { Add-GResult "G4-no-reask" $false $_.Exception.Message }

# ---- G5: determinism (cift parse ayni JSON; proje adi normalize) ----
try {
  $a = Invoke-GoldenParse "G5a" $gPrompt
  $b = Invoke-GoldenParse "G5b" $gPrompt
  $a.spec.project_name = "gx"; $b.spec.project_name = "gx"
  $a.spec.prompt = "gx"; $b.spec.prompt = "gx"
  $ja = $a.spec | ConvertTo-Json -Depth 8
  $jb = $b.spec | ConvertTo-Json -Depth 8
  Add-GResult "G5-determinism" ($ja -eq $jb) $(if ($ja -eq $jb) { "iki parse birebir" } else { "fark var!" })
  Remove-GTemp $a.file; Remove-GTemp $b.file
} catch { Add-GResult "G5-determinism" $false $_.Exception.Message }

# ---- G6: adversarial correction (son cevap gecerli) ----
try {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) "golden-g6"
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $comp = [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
  $sp = [pscustomobject]@{ project_name = "g6"; prompt = "g6"; metadata = [pscustomobject]@{ spec_version = "2.0" }; components = @($comp); assembly = $null; material = $null }
  $spf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $spf -Encoding UTF8
  $qsTxt = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $spf -AsJson 2>&1 | Out-String
  $qsObj = $qsTxt | ConvertFrom-Json
  @($qsObj) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $d "spec.questions.json") -Encoding UTF8
  & (Join-Path $EngineDir "Update-SpecAnswer.ps1") -SpecFile $spf -QuestionId "body-dims" -Answer "50x50x20" 2>&1 | Out-Null
  & (Join-Path $EngineDir "Update-SpecAnswer.ps1") -SpecFile $spf -QuestionId "body-dims" -Answer "60x40x30" 2>&1 | Out-Null
  $v = (Get-Content -LiteralPath $spf -Raw | ConvertFrom-Json).components[0].base
  Add-GResult "G6-correction" ([double]$v.width_mm -eq 60 -and [double]$v.height_mm -eq 30) "son cevap gecerli"
  Remove-GTemp $d
} catch { Add-GResult "G6-correction" $false $_.Exception.Message }

# ---- G7: duplicate feature ----
try {
  $r = Invoke-GoldenParse "G7-dupe" "80x40x20 kutu yap. On yuze 20x10 kablo acikligi ac, konum 5,5 derinlik 8. Ayni 20x10 kablo acikligi bir daha belirtilmis olsun."
  $nc = @($r.spec.components[0].cutouts).Count
  Add-GResult "G7-duplicate" ($nc -eq 1) $(if ($nc -eq 1) { "tek cutout" } else { "cutout=$nc" })
  Remove-GTemp $r.file
} catch { Add-GResult "G7-duplicate" $false $_.Exception.Message }

# ---- G8: units ----
try {
  $r = Invoke-GoldenParse "G8-units" "16 cm x 10 cm x 4.5 cm kutu yap."
  $b8 = $r.spec.components[0].base
  $ok8 = ([double]$b8.width_mm -eq 160 -and [double]$b8.depth_mm -eq 100 -and [double]$b8.height_mm -eq 45)
  Add-GResult "G8-units-cm" $ok8 $(if ($ok8) { "cm->mm" } else { "w=$($b8.width_mm)" })
  Remove-GTemp $r.file
} catch { Add-GResult "G8-units-cm" $false $_.Exception.Message }

# ---- G9: semantic -> geometry (cutout rear gercek olcude) ----
try {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) "golden-g9"
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $cut = [pscustomobject]@{ id = "c1"; kind = "rect"; face = "rear"; pos_x_mm = 70; pos_y_mm = 12; width_mm = 20; length_mm = 10; depth_mm = 2.5; status = "ok" }
  $cb9 = [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 }
    hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true; bottom_thickness_mm = $null }
    holes = @(); cutouts = @($cut); edge_notes = @(); transforms = @(); tolerance = $null; expected_bbox = $null
  }
  $sp9 = [pscustomobject]@{ project_name = "g9"; prompt = "g9"; metadata = [pscustomobject]@{ spec_version = "2.0" }; components = @($cb9); assembly = $null; material = $null }
  $spf9 = Join-Path $d "spec.json"
  $sp9 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $spf9 -Encoding UTF8
  $o = & $GEngine -SpecFile $spf9 -ProjectDir $d 2>&1 | Out-String
  $scad = ""
  $scf = Join-Path $d (Join-Path "cad" "body.scad")
  if (Test-Path -LiteralPath $scf) { $scad = Get-Content -LiteralPath $scf -Raw }
  $stlOk = Test-Path -LiteralPath (Join-Path $d (Join-Path "output" "body.stl"))
  $ok9 = ($stlOk -and $scad -match "cut_c1_w = 20" -and $scad -match "70")
  Add-GResult "G9-semantic-geometry" $ok9 $(if ($ok9) { "rear cutout 20x10@70 gercek geometride" } else { "stl=$stlOk" })
  Remove-GTemp $d
} catch { Add-GResult "G9-semantic-geometry" $false $_.Exception.Message }

# ---- G10: perf (10x parse) ----
try {
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  for ($pi = 0; $pi -lt 10; $pi++) {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "golden-perf.json"
    & $Parser -Prompt $gPrompt -ProjectName ("perf" + $pi) -OutPath $tmp 2>&1 | Out-Null
    Remove-GTemp $tmp
  }
  $sw.Stop()
  Add-GResult "G10-perf" ($sw.Elapsed.TotalSeconds -lt 120) ("10x parse: " + [Math]::Round($sw.Elapsed.TotalSeconds, 1) + " sn")
} catch { Add-GResult "G10-perf" $false $_.Exception.Message }

# ---- G11: facts + coverage on golden ----
try {
  $r = Invoke-GoldenParse "G11-cov" $gPrompt
  $qf = Join-Path ([System.IO.Path]::GetTempPath()) "golden-g11-q.json"
  @($r.qs) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qf -Encoding UTF8
  $ff = Join-Path ([System.IO.Path]::GetTempPath()) "golden-g11-f.json"
  @{ facts = @($r.facts) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ff -Encoding UTF8
  $mf = Join-Path ([System.IO.Path]::GetTempPath()) "golden-g11-m.json"
  $menTxt = & (Join-Path $EngineDir "Get-NumericMentions.ps1") -Prompt $gPrompt -AsJson 2>&1 | Out-String
  $menParsed = $menTxt | ConvertFrom-Json
  @{ mentions = @($menParsed | Where-Object { $_ -ne $null }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $mf -Encoding UTF8
  $covTxt = & $Coverage -SpecFile $r.file -FactsFile $ff -QuestionsFile $qf -MentionsFile $mf -AsJson 2>&1 | Out-String
  $cov = $covTxt | ConvertFrom-Json
  $okc = (@($cov.losses).Count -eq 0 -and @($cov.reasks).Count -eq 0 -and @($cov.unconsumed).Count -eq 0 -and [int]$cov.facts -ge 15)
  Add-GResult "G11-coverage" $okc $(if ($okc) { ("facts=" + $cov.facts + " kayip/soru-yok") } else { ("loss=" + (@($cov.losses) -join "|") + " reask=" + (@($cov.reasks) -join "|") + " unconsumed=" + (@($cov.unconsumed) -join "|")) })
  Remove-GTemp $r.file; Remove-GTemp $qf; Remove-GTemp $ff; Remove-GTemp $mf
} catch { Add-GResult "G11-coverage" $false $_.Exception.Message }

# ---- G12: shape matrix (destekli + sinir) ----
try {
  $r = Invoke-GoldenParse "G12-cyl" "cap 30 yukseklik 40 silindir yap."
  $bc = $r.spec.components[0].base
  $okc = ([double]$bc.diameter_mm -eq 30 -and [double]$bc.height_mm -eq 40 -and @($r.qs).Count -eq 0)
  Add-GResult "G12a-cylinder" $okc "silindir sorusuz"
  Remove-GTemp $r.file
  $r = Invoke-GoldenParse "G12-tube" "dis cap 30 ic cap 20 boy 40 boru yap."
  $bt = $r.spec.components[0].base
  $okt = ([double]$bt.outer_diameter_mm -eq 30 -and [double]$bt.inner_diameter_mm -eq 20 -and @($r.qs).Count -eq 0)
  Add-GResult "G12b-tube" $okt "boru sorusuz"
  Remove-GTemp $r.file
  $r = Invoke-GoldenParse "G12-sphere" "cap 30 kure yap."
  $nq = @($r.qs | Where-Object { $_.kind -eq "dims" }).Count
  Add-GResult "G12c-sphere-limit" ($nq -ge 1) "desteklenmeyen sekil soruyor (uydurmuyor)"
  Remove-GTemp $r.file
} catch { Add-GResult "G12-shape" $false $_.Exception.Message }

# ---- G13: golden pipeline (trace + NEEDS_INPUT kumesi) ----
try {
  $pd = Join-Path ([System.IO.Path]::GetTempPath()) "golden-g13"
  if (Test-Path -LiteralPath $pd) { Remove-Item -LiteralPath $pd -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $pd | Out-Null
  $oTxt = & $Pipeline -Prompt $gPrompt -ProjectName "golden13" -ProjectDir $pd 2>&1 | Out-String
  $o = $oTxt | ConvertFrom-Json
  $qids = @(@($o.questions) | ForEach-Object { [string]$_.question_id })
  $bad = @($qids | Where-Object { $_ -eq "body-dims" -or $_ -eq "body-hollow_top" -or $_ -eq "body-cutout-c1" -or ($_ -like "body-hole-h?-dia" -and $_ -notlike "body-hole-mp*") })
  $trOk = Test-Path -LiteralPath (Join-Path $pd (Join-Path "logs" "pipeline-trace.json"))
  $fxOk = Test-Path -LiteralPath (Join-Path $pd "explicit-facts.json")
  $gcodeOk = ($o.gcode_available -eq $false)
  $okg = ([string]$o.status -eq "NEEDS_INPUT" -and $bad.Count -eq 0 -and $trOk -and $fxOk -and $gcodeOk)
  Add-GResult "G13-golden-pipeline" $okg $(if ($okg) { "NEEDS_INPUT dogru kume + trace + gcode yok" } else { "status=$([string]$o.status) bad=$($bad -join ',')" })
  Remove-GTemp $pd
} catch { Add-GResult "G13-golden-pipeline" $false $_.Exception.Message }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "GOLDEN SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
