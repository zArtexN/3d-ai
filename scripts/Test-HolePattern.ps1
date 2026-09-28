<#
.SYNOPSIS
  Adim C TDD testleri: hole pattern semantic compiler (corner/mid-edge).
.DESCRIPTION
  T-CP-01 issue-tarzi corner derived | T-CP-02 farkli yazim (tane) |
  T-CP-03 mid-edge explicit (corner YOK) | T-CP-04 koselerden explicit |
  T-CP-05 placementsiz (pattern yok, soru var) | T-CP-06 override.
  Dosya ASCII-only; ozel karakterler [char] ile kurulur.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-HolePattern.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-CPResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-CPDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("cp-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function Get-CPParse($prompt, $tag) {
  $d = New-CPDir $tag
  $sf = Join-Path $d "spec.json"
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $sf 2>&1 | Out-Null
  $spec = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
  $qs = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $sf -AsJson 2>&1 | Out-String | ConvertFrom-Json
  $fx = & (Join-Path $EngineDir "Get-ExplicitFacts.ps1") -Prompt $prompt -AsJson 2>&1 | Out-String | ConvertFrom-Json
  return @{ spec = $spec; qs = @($qs | Where-Object { $_ -ne $null }); facts = @($fx | Where-Object { $_ -ne $null }); dir = $d; file = $sf }
}
function NumEq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.0001) } catch { return $false }
}
function Get-Body($spec) {
  return @($spec.components | Where-Object { [string]$_.id -eq "body" })[0]
}
function Get-Holes($body) {
  return @(@($body.holes) | Where-Object { $_ -and [string]$_.id -notlike "mp*" })
}

$T = [char]0xD7
$O = [char]0xD8
$uu = [char]0xFC
$oo = [char]0xF6
$cc = [char]0xE7
$gg = [char]0x11F
$ss = [char]0x15F
$ii = [char]0x131

# TEST C1.
$c1prompt = "160" + $T + "100" + $T + "45 mm dikd" + $oo + "rtgen g" + $oo + "vde, 4 adet " + $O + "4.2 mm ge" + $cc + "i" + $ss + "li delik, merkezleri ilgili d" + $ii + $ss + " kenarlardan 8 mm i" + $cc + "eride."
$r = Get-CPParse $c1prompt "cp01"
$b = Get-Body $r.spec
$hs = Get-Holes $b
$expC = @(8, 8, 152, 8, 8, 92, 152, 92)
$gotC = @()
foreach ($h in $hs) { $gotC += [double]$h.center_x_mm; $gotC += [double]$h.center_y_mm }
$cenOk = ($hs.Count -eq 4)
for ($i = 0; $i -lt 8; $i++) { if (-not (NumEq $gotC[$i] $expC[$i])) { $cenOk = $false } }
$pat = $b.hole_pattern
$patOk = ($null -ne $pat -and [string]$pat.type -eq "corner_pattern" -and [int]$pat.count -eq 4 -and
  (NumEq $pat.diameter_mm 4.2) -and (NumEq $pat.edge_offset_mm 8) -and
  [string]$pat.provenance -eq "derived" -and [string]$pat.placement.reference -eq "outer_body_rectangle")
Add-CPResult "T-CP-01a" ($r.qs.Count -eq 0) ("C1 soru=" + $r.qs.Count + " (beklenen 0)")
Add-CPResult "T-CP-01b" $patOk "C1 pattern corner/derived"
Add-CPResult "T-CP-01c" $cenOk ("C1 merkezler=" + ($gotC -join ","))
$layFx = @($r.facts | Where-Object { [string]$_.target -eq "body.holes" -and [string]$_.property -eq "layout" })
$provOk = ($layFx.Count -gt 0 -and [string]$layFx[0].value -eq "corner_pattern" -and [string]$layFx[0].provenance -eq "derived")
Add-CPResult "T-CP-01d" $provOk "C1 fact provenance=derived"
# C1 compiler kismi: merkezler silinip engine calisir, SCAD'de uretilmis olmali.
$d = New-CPDir "cp01e"
$eb = [pscustomobject]@{
  id = "body"; label = "body"
  base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 }
  hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
  hole_pattern = $b.hole_pattern
}
foreach ($h in $hs) {
  $nh = [pscustomobject]@{
    id = $h.id; hole_type = "through"; diameter_mm = $h.diameter_mm
    center_x_mm = $null; center_y_mm = $null; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "missing"; placement = $h.placement
  }
  $eb.holes += $nh
}
$esp = [pscustomobject]@{ project_name = "cp01e"; prompt = "cp01e"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($eb); assembly = $null; material = $null }
$espf = Join-Path $d "spec.json"
$esp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $espf -Encoding UTF8
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $espf -ProjectDir $d 2>&1 | Out-Null
$scadTxt = ""
$scadP = Join-Path $d (Join-Path "cad" "body.scad")
if (Test-Path -LiteralPath $scadP) { $scadTxt = Get-Content -LiteralPath $scadP -Raw }
$engOk = ($scadTxt -match "hole_h1_x = 8" -and $scadTxt -match "hole_h2_x = 152" -and $scadTxt -match "hole_h3_y = 92" -and $scadTxt -match "hole_h4_x = 152")
Add-CPResult "T-CP-01e" $engOk "C1 compiler SCAD merkezleri uretti"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# TEST C2 (farkli yazim: tane).
$c2prompt = "160x100x45 kutuya 4 tane 4.2 mm " + $cc + "ap" + $ii + "nda ge" + $cc + "i" + $ss + "li delik a" + $cc + ". Her deli" + $gg + "in merkezi d" + $ii + $ss + " kenarlardan 8 mm i" + $cc + "eride."
$r = Get-CPParse $c2prompt "cp02"
$b = Get-Body $r.spec
$hs = Get-Holes $b
$gotC = @()
foreach ($h in $hs) { $gotC += [double]$h.center_x_mm; $gotC += [double]$h.center_y_mm }
$cenOk = ($hs.Count -eq 4)
for ($i = 0; $i -lt 8; $i++) { if (-not (NumEq $gotC[$i] $expC[$i])) { $cenOk = $false } }
$pat = $b.hole_pattern
Add-CPResult "T-CP-02a" ($r.qs.Count -eq 0) ("C2 soru=" + $r.qs.Count + " (beklenen 0)")
Add-CPResult "T-CP-02b" ($null -ne $pat -and [string]$pat.type -eq "corner_pattern" -and [string]$pat.provenance -eq "derived") "C2 pattern corner/derived"
Add-CPResult "T-CP-02c" $cenOk ("C2 merkezler=" + ($gotC -join ","))
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# TEST C3 (kenar ortalari: corner YOK, mid-edge explicit, tek-tek soru YOK).
$c3prompt = "160x100x45 g" + $oo + "vde, 4 adet " + $O + "4.2 delik, kenar pay" + $ii + " 8 mm, delikler kenar ortalar" + $ii + "nda."
$r = Get-CPParse $c3prompt "cp03"
$b = Get-Body $r.spec
$hs = Get-Holes $b
$pat = $b.hole_pattern
$midOk = ($null -ne $pat -and [string]$pat.type -eq "mid_edge" -and [string]$pat.provenance -eq "explicit")
$noCorner = $true
if ($null -ne $pat -and [string]$pat.type -eq "corner_pattern") { $noCorner = $false }
foreach ($h in $hs) {
  if ($null -ne $h.placement -and [string]$h.placement.type -eq "corner_pattern") { $noCorner = $false }
}
$hcQ = @($r.qs | Where-Object { [string]$_.kind -eq "hole_center" })
$expM = @(80, 8, 80, 92, 8, 50, 152, 50)
$gotM = @()
foreach ($h in $hs) { $gotM += [double]$h.center_x_mm; $gotM += [double]$h.center_y_mm }
$midCen = ($hs.Count -eq 4)
for ($i = 0; $i -lt 8; $i++) { if (-not (NumEq $gotM[$i] $expM[$i])) { $midCen = $false } }
Add-CPResult "T-CP-03a" ($midOk -and $noCorner) "C3 mid_edge explicit, corner yok"
Add-CPResult "T-CP-03b" ($hcQ.Count -eq 0) ("C3 tek-tek merkez sorusu yok (" + $hcQ.Count + ")")
Add-CPResult "T-CP-03c" $midCen ("C3 mid-edge merkezler=" + ($gotM -join ","))
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# TEST C4 (koselerden: explicit).
$c4prompt = "160x100x45 g" + $oo + "vde, 4 adet " + $O + "4.2 delik, k" + $oo + $ss + "elerden 8 mm."
$r = Get-CPParse $c4prompt "cp04"
$b = Get-Body $r.spec
$hs = Get-Holes $b
$pat = $b.hole_pattern
$gotC = @()
foreach ($h in $hs) { $gotC += [double]$h.center_x_mm; $gotC += [double]$h.center_y_mm }
$cenOk = ($hs.Count -eq 4)
for ($i = 0; $i -lt 8; $i++) { if (-not (NumEq $gotC[$i] $expC[$i])) { $cenOk = $false } }
Add-CPResult "T-CP-04a" ($null -ne $pat -and [string]$pat.type -eq "corner_pattern" -and [string]$pat.provenance -eq "explicit") "C4 corner explicit"
Add-CPResult "T-CP-04b" $cenOk ("C4 merkezler=" + ($gotC -join ","))
Add-CPResult "T-CP-04c" ($r.qs.Count -eq 0) ("C4 soru=" + $r.qs.Count)
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# TEST C5 (yerlesimsiz: pattern yok, soru var).
$c5prompt = "160x100x45 g" + $oo + "vde, 4 adet " + $O + "4.2 delik."
$r = Get-CPParse $c5prompt "cp05"
$b = Get-Body $r.spec
$hcQ = @($r.qs | Where-Object { [string]$_.kind -eq "hole_center" })
Add-CPResult "T-CP-05a" ($null -eq $b.hole_pattern) "C5 pattern uydurulmadi"
Add-CPResult "T-CP-05b" ($hcQ.Count -gt 0) ("C5 merkez sorulabilir (" + $hcQ.Count + ")")
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# TEST C6 (override: kose degil, kenar ortalari).
$c6prompt = "160x100x45 g" + $oo + "vde, 4 adet " + $O + "4.2 delik, kenarlardan 8 mm. K" + $oo + $ss + "elerde de" + $gg + "il, kenar ortalar" + $ii + "nda olsun."
$r = Get-CPParse $c6prompt "cp06"
$b = Get-Body $r.spec
$hs = Get-Holes $b
$pat = $b.hole_pattern
$gotM = @()
foreach ($h in $hs) { $gotM += [double]$h.center_x_mm; $gotM += [double]$h.center_y_mm }
$midCen = ($hs.Count -eq 4)
for ($i = 0; $i -lt 8; $i++) { if (-not (NumEq $gotM[$i] $expM[$i])) { $midCen = $false } }
$noCorner = ($null -eq $pat -or [string]$pat.type -ne "corner_pattern")
foreach ($h in $hs) {
  if ($null -ne $h.placement -and [string]$h.placement.type -eq "corner_pattern") { $noCorner = $false }
}
Add-CPResult "T-CP-06a" ($null -ne $pat -and [string]$pat.type -eq "mid_edge" -and [string]$pat.provenance -eq "explicit") "C6 override mid_edge"
Add-CPResult "T-CP-06b" ($midCen -and $noCorner) ("C6 eski corner koordinat yok (" + ($gotM -join ",") + ")")
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("HOLEPATTERN SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
