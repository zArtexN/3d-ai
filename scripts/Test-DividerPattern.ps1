<#
.SYNOPSIS
  Adim A TDD testleri: bolme = body.divider_pattern (bagimsiz component yok).
.DESCRIPTION
  T-DV-00 kutuphane | T-DV-01 issue prompt'ta div sorusu yok |
  T-DV-02 kalinliksiz TEK soru | T-DV-03 sigima-gate BLOCKED |
  T-DV-04 eski format katlama + sorusuzluk | T-DV-05 geometri (ic hacim,
  esit aralik, top_gap, ayri STL yok).
  Dosya ASCII-only; ozel karakterler [char] ile kurulur.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-DividerPattern.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
$Lib = Join-Path $EngineDir "CanonicalSpec.ps1"

$results = New-Object System.Collections.Generic.List[object]
function Add-DVResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-DVDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("dv-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function Get-DVParse($prompt, $tag) {
  $d = New-DVDir $tag
  $sf = Join-Path $d "spec.json"
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $sf 2>&1 | Out-Null
  $spec = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
  $qs = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $sf -AsJson 2>&1 | Out-String | ConvertFrom-Json
  return @{ spec = $spec; qs = @($qs | Where-Object { $_ -ne $null }); dir = $d }
}
function NumEq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.0001) } catch { return $false }
}

$T = [char]0xD7
$O = [char]0xD8
$uu = [char]0xFC
$cc = [char]0xE7
$ii = [char]0x131
$oo = [char]0xF6
$gg = [char]0x11F
$issue = "160" + $T + "100" + $T + "45 mm kutu, " + $uu + "st" + $uu + " a" + $cc + $ii + "k, " +
  "2.5 mm duvar, 3 mm taban, 2 b" + $oo + "lme 2 mm kal" + $ii + "nl" + $ii + $gg + $ii + "nda, " +
  "4 delik " + $O + "4.2 kenardan 8 mm"

# T-DV-00: kutuphane + donusturucu mevcut.
if (Test-Path -LiteralPath $Lib) { . $Lib }
Add-DVResult "T-DV-00" ((Get-Command ConvertTo-CanonicalSpec -ErrorAction SilentlyContinue) -ne $null) "ConvertTo-CanonicalSpec yuklendi"

# T-DV-01: issue prompt'ta div1/div2 dims sorusu CIKMAMALI.
$r = Get-DVParse $issue "dv01"
$divQs = @($r.qs | Where-Object { [string]$_.component -like "div*" -or [string]$_.target -like "div*" })
Add-DVResult "T-DV-01" ($divQs.Count -eq 0) ("div sorusu=" + $divQs.Count + " (beklenen 0)")

# T-DV-02: kalinlik yoksa TEK soru.
$r = Get-DVParse "80x40x20 kutu, ustu acik, duvar 2 mm, 2 bolme" "dv02"
$dvQs = @($r.qs | Where-Object { [string]$_.kind -like "*divider*" -or [string]$_.target -like "*divider*" })
$oneQ = ($dvQs.Count -eq 1 -and [string]$dvQs[0].kind -eq "divider_thickness" -and [string]$dvQs[0].question -match "Bolme kalinligi")
Add-DVResult "T-DV-02" $oneQ ("divider sorusu=" + ((@($dvQs) | ForEach-Object { [string]$_.question_id }) -join ",") + " (beklenen 1x divider_thickness)")

# T-DV-07: top_gap belirtilmediyse derived=true; belirtildiyse false.
$b02 = @($r.spec.components | Where-Object { [string]$_.id -eq "body" })[0]
Add-DVResult "T-DV-07a" ($b02.divider_pattern.top_gap_derived -eq $true) "gap yoksa derived=true"
$r7 = Get-DVParse "80x40x20 kutu, ustu acik, duvar 2 mm, 2 bolme 2 mm kalinliginda, ust kenardan 5 mm asagida" "dv07"
$b07 = @($r7.spec.components | Where-Object { [string]$_.id -eq "body" })[0]
Add-DVResult "T-DV-07b" ((NumEq $b07.divider_pattern.top_gap_mm 5) -and ($b07.divider_pattern.top_gap_derived -eq $false)) "acik gap=5, derived=false"

# T-DV-03: sigima-gate (2*2.5 + 8*2 = 21 > 20 -> BLOCKED).
$d = New-DVDir "dv03"
$body = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 20; depth_mm = 20; height_mm = 10 }
  hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true; bottom_thickness_mm = 2 }
  holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
  divider_pattern = [pscustomobject]@{ count = 8; thickness_mm = 2; top_gap_mm = 0; orientation = "along_length"; status = "ok" }
}
$sp = [pscustomobject]@{ project_name = "dv03"; prompt = "dv03"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($body); assembly = $null; material = $null }
$spf = Join-Path $d "spec.json"
$sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $spf -Encoding UTF8
$gv = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile $spf -AsJson 2>&1 | Out-String | ConvertFrom-Json
$fitErr = (@($gv.errors | Where-Object { [string]$_ -match "divider" }).Count -gt 0)
Add-DVResult "T-DV-03" $fitErr ("sigima hatasi (beklenen BLOCKED): " + (@($gv.errors) -join "|"))
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-DV-04a: eski format -> divider_pattern katlama (birim).
$legDivs = @(
  [pscustomobject]@{ id = "div1"; base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }; thickness_mm = 2; top_gap_mm = 5 },
  [pscustomobject]@{ id = "div2"; base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }; thickness_mm = 2; top_gap_mm = 5 }
)
$legBody = [pscustomobject]@{ id = "body"; base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 } }
$leg = [pscustomobject]@{ project_name = "legacy"; prompt = "legacy"; components = @($legBody) + @($legDivs) }
$canon = $null
if (Get-Command ConvertTo-CanonicalSpec -ErrorAction SilentlyContinue) { $canon = ConvertTo-CanonicalSpec $leg }
$foldOk = ($null -ne $canon -and $null -ne $canon.components[0].divider_pattern -and
  [int]$canon.components[0].divider_pattern.count -eq 2 -and
  (NumEq $canon.components[0].divider_pattern.thickness_mm 2) -and
  (NumEq $canon.components[0].divider_pattern.top_gap_mm 5) -and
  (@($canon.components | Where-Object { [string]$_.id -like "div*" }).Count -eq 0))
Add-DVResult "T-DV-04a" $foldOk "legacy div1/div2 -> divider_pattern{2, 2mm, gap5}"

# T-DV-04b: eski spec dosyasi -> soru katmaninda div sorusu yok.
$d = New-DVDir "dv04b"
$legBody2 = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 }
  hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true; bottom_thickness_mm = 3 }
  holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
}
$legDivs2 = @(
  [pscustomobject]@{ id = "div1"; label = "bolme 1"; base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }; hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @(); tolerance = $null; expected_bbox = $null; thickness_mm = 2 },
  [pscustomobject]@{ id = "div2"; label = "bolme 2"; base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }; hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @(); tolerance = $null; expected_bbox = $null; thickness_mm = 2 }
)
$sp4 = [pscustomobject]@{ project_name = "dv04b"; prompt = "dv04b"; metadata = [pscustomobject]@{ spec_version = "2.0" }; components = @($legBody2) + @($legDivs2); assembly = $null; material = $null }
$spf4 = Join-Path $d "spec.json"
$sp4 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $spf4 -Encoding UTF8
$q4 = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $spf4 -AsJson 2>&1 | Out-String | ConvertFrom-Json
$divQ4 = @($q4 | Where-Object { $_ -and ([string]$_.component -like "div*" -or [string]$_.target -like "div*") })
Add-DVResult "T-DV-04b" ($divQ4.Count -eq 0) ("legacy dosyada div sorusu=" + $divQ4.Count + " (beklenen 0)")
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-DV-05: geometri (60x40x20, duvar 2, 2x2mm, gap 3).
$d = New-DVDir "dv05"
$gb = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 60; depth_mm = 40; height_mm = 20 }
  hollow = [pscustomobject]@{ wall_mm = 2; open_top = $true; bottom_thickness_mm = 2 }
  holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
  divider_pattern = [pscustomobject]@{ count = 2; thickness_mm = 2; top_gap_mm = 3; orientation = "along_length"; status = "ok" }
}
$gsp = [pscustomobject]@{ project_name = "dv05"; prompt = "dv05"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($gb); assembly = $null; material = $null }
$gspf = Join-Path $d "spec.json"
$gsp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $gspf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $gspf -ProjectDir $d 2>&1 | Out-Null
$stls = @()
if (Test-Path -LiteralPath (Join-Path $d "output")) { $stls = @(Get-ChildItem -LiteralPath (Join-Path $d "output") -Filter "*.stl" | ForEach-Object { $_.Name }) }
$noDivStl = (@($stls | Where-Object { $_ -like "div*" }).Count -eq 0) -and ($stls -contains "body.stl")
$vv = @()
foreach ($vf in @("divider_001", "divider_002")) {
  $vp = Join-Path $d (Join-Path "validation" ($vf + ".validation.json"))
  if (Test-Path -LiteralPath $vp) { $vv += (Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json) }
}
# Ic hacim: x [2,58], y [2,38], ust = 20-3 = 17. Esit aralik: iki panel ortasi simetrik.
$geoOk = ($vv.Count -eq 2)
if ($geoOk) {
  foreach ($v in $vv) {
    if ([double]$v.bbox_min[0] -lt 2 -or [double]$v.bbox_max[0] -gt 58) { $geoOk = $false }
    if ([double]$v.bbox_min[1] -lt 2 -or [double]$v.bbox_max[1] -gt 38) { $geoOk = $false }
    if (-not (NumEq $v.bbox_max[2] 17)) { $geoOk = $false }
    if (-not (NumEq ([double]$v.bbox_max[0] - [double]$v.bbox_min[0]) 2)) { $geoOk = $false }
  }
  $c1 = (([double]$vv[0].bbox_min[0] + [double]$vv[0].bbox_max[0]) / 2)
  $c2 = (([double]$vv[1].bbox_min[0] + [double]$vv[1].bbox_max[0]) / 2)
  # Esit aralik: sol/mid/sag bosluklar esit + simetri.
  $g1 = ($c1 - 1 - 2)
  $gm = ($c2 - 1 - ($c1 + 1))
  $g2 = (58 - ($c2 + 1))
  if (-not (NumEq $g1 $gm) -or -not (NumEq $gm $g2)) { $geoOk = $false }
  if (-not (NumEq ($c1 - 2) (58 - $c2))) { $geoOk = $false }
}
Add-DVResult "T-DV-05a" $noDivStl ("ayri divider STL yok + body.stl var: " + ($stls -join ","))
Add-DVResult "T-DV-05b" $geoOk "paneller ic hacimde, esit aralikli, ust=17"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-DV-06: issue prompt (duvar 2.5 != taban 3) -> bolme tabani bottom_thickness (z=3).
$ri = Get-DVParse $issue "dv06"
$ib = @($ri.spec.components | Where-Object { [string]$_.id -eq "body" })[0]
$d6 = New-DVDir "dv06"
$eb = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = $ib.base.width_mm; depth_mm = $ib.base.depth_mm; height_mm = $ib.base.height_mm }
  hollow = [pscustomobject]@{ wall_mm = $ib.hollow.wall_mm; open_top = $true; bottom_thickness_mm = $ib.hollow.bottom_thickness_mm }
  holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
  divider_pattern = $ib.divider_pattern
}
$esp = [pscustomobject]@{ project_name = "dv06"; prompt = "dv06"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($eb); assembly = $null; material = $null }
$espf = Join-Path $d6 "spec.json"
$esp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $espf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $espf -ProjectDir $d6 2>&1 | Out-Null
$v61 = $null; $v62 = $null
$vp1 = Join-Path $d6 (Join-Path "validation" "divider_001.validation.json")
$vp2 = Join-Path $d6 (Join-Path "validation" "divider_002.validation.json")
if (Test-Path -LiteralPath $vp1) { $v61 = Get-Content -LiteralPath $vp1 -Raw | ConvertFrom-Json }
if (Test-Path -LiteralPath $vp2) { $v62 = Get-Content -LiteralPath $vp2 -Raw | ConvertFrom-Json }
$zOk = ($null -ne $v61 -and $null -ne $v62 -and (NumEq $v61.bbox_min[2] 3) -and (NumEq $v61.bbox_max[2] 45) -and (NumEq $v62.bbox_min[2] 3) -and (NumEq $v62.bbox_max[2] 45))
Add-DVResult "T-DV-06a" $zOk "bolme tabani bottom(3), ust 45"
$scadTxt = ""
$scadP = Join-Path $d6 (Join-Path "cad" "body.scad")
if (Test-Path -LiteralPath $scadP) { $scadTxt = Get-Content -LiteralPath $scadP -Raw }
Add-DVResult "T-DV-06b" ($scadTxt -match [regex]::Escape("translate([2.5, 2.5, 3])")) "body SCAD ic kesim z=3"
Remove-Item -LiteralPath $d6 -Recurse -Force -ErrorAction SilentlyContinue

# T-DV-06b-2: taban < duvar ise de kullanicinin degeri (z=2).
$d = New-DVDir "dv06b"
$sb = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 60; depth_mm = 40; height_mm = 20 }
  hollow = [pscustomobject]@{ wall_mm = 2.5; open_top = $true; bottom_thickness_mm = 2 }
  holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
  divider_pattern = [pscustomobject]@{ count = 1; thickness_mm = 2; top_gap_mm = 0; orientation = "along_length"; status = "ok" }
}
$ssp = [pscustomobject]@{ project_name = "dv06b"; prompt = "dv06b"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($sb); assembly = $null; material = $null }
$sspf = Join-Path $d "spec.json"
$ssp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sspf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sspf -ProjectDir $d 2>&1 | Out-Null
$vv6 = $null
$vp6 = Join-Path $d (Join-Path "validation" "divider_001.validation.json")
if (Test-Path -LiteralPath $vp6) { $vv6 = Get-Content -LiteralPath $vp6 -Raw | ConvertFrom-Json }
Add-DVResult "T-DV-06c" ($null -ne $vv6 -and (NumEq $vv6.bbox_min[2] 2) -and (NumEq $vv6.bbox_max[2] 20)) "taban<duvar da kullanilir (z=2)"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("DIVIDER SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
