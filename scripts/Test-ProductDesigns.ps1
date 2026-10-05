<#
.SYNOPSIS
  Urun-tasarim regression (F-P): planner niyetleri + NL editing + negatifler.
.DESCRIPTION
  A-E mevcut suitlerde korunur (box/partition/cutout/hole/kombo).
  Bu dosya: F organizer, G phone stand, H tray, I NL organizer, J NL stand,
  K NL holder, L eksik kritik olcu, M belirli telefon modeli,
  N radius/chamfer, O buyuk geometri, P hatali girdi.
  Tam pipeline kosanlarda: DesignSpec -> Geometry -> STL -> Mesh QA ->
  Printability dogrulanir. Mock/fake YOK (gercek OpenSCAD).
#>
param([string]$WorkRoot = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ($WorkRoot -eq "") { $WorkRoot = $Root }
$EngineDir = Join-Path $Root "engine"

$pass = 0; $fail = 0
function T-Pass($id, $msg) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $msg) }
function T-Fail($id, $msg) { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $msg) }

function Invoke-Pipe($name, $prompt) {
  $out = & (Join-Path $EngineDir "Invoke-Pipeline.ps1") -Prompt $prompt -ProjectName $name 2>&1 | Out-String
  return (Get-Content -LiteralPath (Join-Path $WorkRoot (Join-Path "projects" (Join-Path $name "pipeline-result.json"))) -Raw | ConvertFrom-Json)
}
function Test-Full($id, $name, $prompt, $needIntent) {
  try {
    $res = Invoke-Pipe $name $prompt
    if ([string]$res.status -ne "PASS" -and [string]$res.status -ne "WARNING") { T-Fail $id ("status=" + [string]$res.status); return }
    if (@($res.questions).Count -ne 0) { T-Fail $id "soru var"; return }
    $pdir = Join-Path $WorkRoot (Join-Path "projects" $name)
    $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" | Select-Object -First 1
    if ($null -eq $stl -or $stl.Length -lt 1000) { T-Fail $id "STL yok/kucuk"; return }
    $mesh = (& (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $stl.FullName -AsJson 2>&1 | Out-String) | ConvertFrom-Json
    if ([string]$mesh.status -ne "PASS") { T-Fail $id ("mesh=" + [string]$mesh.status); return }
    $pa = (& (Join-Path $EngineDir "Analyze-Printability.ps1") -SpecFile (Join-Path $pdir "spec.json") -AsJson 2>&1 | Out-String) | ConvertFrom-Json
    if ([string]$pa.status -eq "FAIL" -or [string]$pa.status -eq "BLOCKED") { T-Fail $id ("printability=" + [string]$pa.status); return }
    if ($needIntent -ne "") {
      $sp = Get-Content -LiteralPath (Join-Path $pdir "spec.json") -Raw | ConvertFrom-Json
      if ([string]$sp.planner.intent -ne $needIntent) { T-Fail $id ("intent=" + [string]$sp.planner.intent); return }
    }
    T-Pass $id ("PASS sorusuz, stl=" + $stl.Length + " mesh=PASS print=" + [string]$pa.status)
  } catch { T-Fail $id $_.Exception.Message }
}

Test-Full "F-organizer" "_ptest-f-org" "Masam icin bolmeli bir organizer tasarla. Kalemler icin bolum, telefon icin egimli yuva ve sarj kablosu icin kanal olsun. Ustu acik, desteksiz basilsin." "organizer"
Test-Full "G-phone-stand" "_ptest-f-stand" "Telefonum icin masada duran egimli bir stand tasarla" "phone_stand"
Test-Full "H-tray" "_ptest-f-tray" "Masa icin sade bir tepsi tasarla, ustu acik olsun" "tray"
Test-Full "I-nl-organizer" "_ptest-f-nlorg" "Calisma masama kompakt ve sik bir masaustu duzenleyici tasarla. Kalemler bir yanda, telefon egimli dursun, kablosu onden gecsin. Ustu acik olsun." "organizer"
Test-Full "J-nl-stand" "_ptest-f-nlstand" "Telefonumu masada 20 derece egimle tutacak sade bir ayak tasarla" "phone_stand"
Test-Full "K-nl-holder" "_ptest-f-nhold" "Duvari delmeden kablo duzenlemek icin bir kablo tutucu tasarla" "cable_clip"
Test-Full "Q-caddy" "_ptest-f-caddy" "Mutfakta kullanmak icin kompakt bir sunger ve bulasik fircasi organizeri tasarla. Sunger icin bir bolme, firca icin dikey bir bolme ve drenaj delikleri olsun. Ustu acik olsun ve desteksiz basilabilsin. Kritik olculeri tasarim amacina gore kendin belirle." "caddy"

# L: eksik kritik olcu -> NEEDS_INPUT (soru var, model yok)
try {
  $res = Invoke-Pipe "_ptest-f-missing" "Duvar kalinligi 3 mm olan kutu yap."
  $missStl = Join-Path $WorkRoot (Join-Path "projects" (Join-Path "_ptest-f-missing" (Join-Path "output" "body.stl")))
  $stlHere = Test-Path -LiteralPath $missStl
  if ([string]$res.status -eq "NEEDS_INPUT" -and @($res.questions).Count -gt 0 -and -not $stlHere) { T-Pass "L-missing" "NEEDS_INPUT, soru var, model yok" }
  else { T-Fail "L-missing" ("status=" + [string]$res.status) }
} catch { T-Fail "L-missing" $_.Exception.Message }

# M: belirli telefon modeli -> NEEDS_INPUT, spec degismez
try {
  $res = Invoke-Pipe "_ptest-f-model" "iPhone 15 Pro icin organizer tasarla, kalem bolumu ve telefon yuvasi olsun, ustu acik."
  $txt = [string]$res.reason + " " + [string]($res | ConvertTo-Json -Compress)
  if ([string]$res.status -eq "NEEDS_INPUT" -and $txt -match "iPhone|telefonun tam modeli") { T-Pass "M-phonemodel" "modelde NEEDS_INPUT, uydurma yok" }
  else { T-Fail "M-phonemodel" ("status=" + [string]$res.status) }
} catch { T-Fail "M-phonemodel" $_.Exception.Message }

# N: gercek radius (rounded hollow => SCAD minkowski) + chamfer WARNING durustlugu
try {
  $res = Invoke-Pipe "_ptest-f-radius" "Cekmece icin kapakli bir saklama kutusu tasarla"
  $pdir = Join-Path $WorkRoot (Join-Path "projects" "_ptest-f-radius")
  $scad = Get-ChildItem -LiteralPath (Join-Path $pdir "cad") -Filter "*.scad" | Select-Object -First 1
  $txt = Get-Content -LiteralPath $scad.FullName -Raw
  $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" | Select-Object -First 1
  $mesh = (& (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $stl.FullName -AsJson 2>&1 | Out-String) | ConvertFrom-Json
  if (([string]$res.status -eq "PASS" -or [string]$res.status -eq "WARNING") -and $txt -match "minkowski" -and [string]$mesh.status -eq "PASS") {
    T-Pass "N-radius" "gercek radius (minkowski) + watertight"
  } else { T-Fail "N-radius" ("status=" + [string]$res.status + " mesh=" + [string]$mesh.status) }
} catch { T-Fail "N-radius" $_.Exception.Message }

# O: buyuk geometri (300mm kutu) -> uretim surer, yatak uyarisi gecerli sayilir
try {
  $res = Invoke-Pipe "_ptest-f-large" "300x300x300 mm kutu, ustu acik, duvar 3"
  $pdir = Join-Path $WorkRoot (Join-Path "projects" "_ptest-f-large")
  $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" -ErrorAction SilentlyContinue | Select-Object -First 1
  if (([string]$res.status -eq "PASS" -or [string]$res.status -eq "WARNING") -and $null -ne $stl) { T-Pass "O-large" "300mm uretildi" }
  else { T-Fail "O-large" ("status=" + [string]$res.status) }
} catch { T-Fail "O-large" $_.Exception.Message }

# P: hatali/bos girdi -> BLOCKED, sahte basari yok
try {
  $res = Invoke-Pipe "_ptest-f-bad" "   "
  if ([string]$res.status -eq "BLOCKED") { T-Pass "P-malformed" "bos girdi BLOCKED" }
  else { T-Fail "P-malformed" ("status=" + [string]$res.status) }
} catch { T-Fail "P-malformed" $_.Exception.Message }

Write-Output "----------------------------------------"
Write-Output ("URUN SONUC: " + $pass + " / " + ($pass + $fail) + " test gecti")
if ($fail -gt 0) { exit 1 } else { exit 0 }
