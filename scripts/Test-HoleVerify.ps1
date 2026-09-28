<#
.SYNOPSIS
  Delik-dogrulama TDD testleri (holefix-1): cikis duzlemi = floor.
.DESCRIPTION
  T-HV-00 yeni Verify-Stl parametreleri | T-HV-01a issue 4 delik PASS |
  T-HV-01b/c taban 2 ve 3 varyantlari | T-HV-02 NEGATIF blind 1mm FAIL |
  T-HV-03 kapali kutu through (regresyon bekcisi).
  Dosya ASCII-only; ozel karakterler [char] ile kurulur.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-HoleVerify.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-HVResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-HVDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("hv-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-HVBody($w, $d, $h, $wall, $bottom, $holes) {
  $hol = $null
  if ($null -ne $wall) {
    $hol = [pscustomobject]@{ wall_mm = $wall; open_top = $true; bottom_thickness_mm = $bottom }
  }
  return [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = $w; depth_mm = $d; height_mm = $h }
    hollow = $hol; holes = @($holes); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
}
function New-HVHole($id, $type, $dia, $cx, $cy, $depth) {
  return [pscustomobject]@{
    id = $id; hole_type = $type; diameter_mm = $dia
    center_x_mm = $cx; center_y_mm = $cy; axis = "z"
    depth_mm = $depth; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "ok"
  }
}
function Invoke-HVEngine($body, $tag) {
  $d = New-HVDir $tag
  $sp = [pscustomobject]@{ project_name = $tag; prompt = $tag; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($body); assembly = $null; material = $null }
  $sf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
  & (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sf -ProjectDir $d 2>&1 | Out-Null
  $v = $null
  $vp = Join-Path $d (Join-Path "validation" "body.validation.json")
  if (Test-Path -LiteralPath $vp) { $v = Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json }
  return @{ validation = $v; dir = $d }
}

# T-HV-00: yeni parametreler mevcut.
$vp = (Get-Command (Join-Path $Root (Join-Path "scripts" "Verify-Stl.ps1")) -ErrorAction SilentlyContinue).Parameters
$hasP = ($null -ne $vp -and $vp.ContainsKey("HoleZTop") -and $vp.ContainsKey("HoleZBottom"))
Add-HVResult "T-HV-00" $hasP "HoleZTop/HoleZBottom parametreleri"

# T-HV-01a: issue prompt 4 delik PASS (tam pipeline).
# Adim C sonrasi soru uretilmez; cevapsiz tam kosu beklenir.
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
# T-HV-01a: issue prompt 4 delik PASS (tam pipeline).
# Adim C sonrasi soru uretilmez; cevapsiz tam kosu beklenir.
$pd = New-HVDir "hv01a"
$out = & (Join-Path $EngineDir "Invoke-Pipeline.ps1") -Prompt $issue -ProjectName "issuebox" -ProjectDir $pd 2>&1 | Out-String
$res = $out | ConvertFrom-Json
$holesOk = ([string]$res.status -eq "PASS" -and @($res.questions).Count -eq 0)
foreach ($p in @($res.parts)) {
  if ([string]$p.id -eq "body" -and [string]$p.status -ne "PASS") { $holesOk = $false }
}
Add-HVResult "T-HV-01a" $holesOk ("issue 4 delik pipeline STATUS=" + $res.status)
Remove-Item -LiteralPath $pd -Recurse -Force -ErrorAction SilentlyContinue

# T-HV-01b/c: taban 3 ve taban 2 varyantlari (through, ayni delik).
foreach ($bt in @(3, 2)) {
  $b = New-HVBody 60 40 20 2 $bt @((New-HVHole "h1" "through" 6 10 10 $null))
  $r = Invoke-HVEngine $b ("hv01" + $bt)
  $v = $r.validation
  $hc = @()
  if ($null -ne $v) { $hc = @($v.hole_checks | Where-Object { [string]$_.id -eq "h1" }) }
  $ok = ($null -ne $v -and [string]$v.status -eq "PASS" -and $hc.Count -gt 0 -and [string]$hc[0].result -eq "PASS")
  Add-HVResult ("T-HV-01" + $(if ($bt -eq 3) { "b" } else { "c" })) $ok ("taban=" + $bt + " through delik PASS")
  Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
}

# T-HV-02 NEGATIF: 1 mm blind (tabana ulasmaz) FAIL vermeli.
$b = New-HVBody 60 40 20 2 $null @((New-HVHole "h1" "blind" 6 30 20 1))
$r = Invoke-HVEngine $b "hv02"
$v = $r.validation
$hc = @()
if ($null -ne $v) { $hc = @($v.hole_checks | Where-Object { [string]$_.id -eq "h1" }) }
$negOk = ($hc.Count -gt 0 -and [string]$hc[0].result -eq "FAIL")
Add-HVResult "T-HV-02" $negOk "blind 1mm FAIL (ulasmayan delik gecerli sayilmaz)"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-HV-03: kapali kutu through (regresyon bekcisi, hep PASS).
$b = New-HVBody 40 30 20 $null $null @((New-HVHole "h1" "through" 6 20 15 $null))
$r = Invoke-HVEngine $b "hv03"
$v = $r.validation
$hc = @()
if ($null -ne $v) { $hc = @($v.hole_checks | Where-Object { [string]$_.id -eq "h1" }) }
Add-HVResult "T-HV-03" ($null -ne $v -and [string]$v.status -eq "PASS" -and $hc.Count -gt 0 -and [string]$hc[0].result -eq "PASS") "kapali kutu through PASS"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("HOLE SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
