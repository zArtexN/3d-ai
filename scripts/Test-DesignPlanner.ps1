<#
.SYNOPSIS
  Design Planner regression testleri (mevcut testlere DOKUNMAZ, ek dosya).
.DESCRIPTION
  Korur: parser'in acik-olcu davranisi (planner tetiklenmez), NEEDS_INPUT disiplini.
  Dogrular:
    R1: acik olculu istekte planner devre disi kalir.
    R2: belirli telefon modelinde planner NEEDS_INPUT uretir, spec degismez.
    R3: benchmark-1 promptu NEEDS_INPUT'siz PASS + gercek STL + mesh PASS.
    R4: benchmark-2 promptu 12 dereceyi kullanici degeri olarak alir + PASS.
    R5: planner varsayimlari spec.planner.assumptions'da kayitlidir.
    R6: mevcut geometri (New-GBox/New-GHollowBox) davranisi degismedi.
  Mock YOK, fake STL YOK (gercek OpenSCAD + Verify-Stl).
#>
param([string]$WorkRoot = "")

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
if ($WorkRoot -eq "") { $WorkRoot = $Root }

$pass = 0; $fail = 0
function T-Pass($id, $msg) { $script:pass++; Write-Output "[PASS] $id -- $msg" }
function T-Fail($id, $msg) { $script:fail++; Write-Output "[FAIL] $id -- $msg" }

$B1 = "Masamda kullanmak icin kompakt ve sik bir masaustu organizer tasarla. Kalemler icin bir bolum, telefon icin egimli bir bolum ve telefonun sarj kablosunun gececegi bir kablo kanali olsun. Ustu acik olsun ve 3D yazicide desteksiz basabilecek sekilde tasarla."
$B2 = "Calisma masam icin profesyonel gorunumlu bir organizer tasarla. Telefon icin yaklasik 12 derecelik egimli bir yuva, kalemler icin derin bir bolum, kucuk esyalar icin ayri bir bolum ve telefon sarj kablosu icin onden gorunmeyecek sekilde kablo gecisi olsun. Tasarim kompakt, dengeli ve FDM 3D yazicide desteksiz basilabilir olsun. Gereksiz keskin koseler yerine uygun radiuslar kullan."

# R1: acik olcu -> planner devre disi
$r1spec = Join-Path $WorkRoot "projects\_ptest-planner-r1\spec.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $r1spec) | Out-Null
& (Join-Path $Root "engine\ConvertTo-GeometrySpec.ps1") -Prompt "80x40x20 kutu, ustu acik, duvar 2.5" -ProjectName "_ptest-planner-r1" -OutPath $r1spec 2>&1 | Out-Null
$r1rep = (& (Join-Path $Root "engine\Invoke-DesignPlanner.ps1") -SpecFile $r1spec -Prompt "80x40x20 kutu, ustu acik, duvar 2.5" 2>&1 | Out-String) | ConvertFrom-Json
if ($r1rep.applied -eq $false) { T-Pass "R1-no-trigger" "acik olculu istekte planner calismadi" }
else { T-Fail "R1-no-trigger" "planner hassas istege mudahale etti" }

# R2: belirli telefon modeli -> NEEDS_INPUT, spec degismez
$r2spec = Join-Path $WorkRoot "projects\_ptest-planner-r2\spec.json"
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $r2spec) | Out-Null
& (Join-Path $Root "engine\ConvertTo-GeometrySpec.ps1") -Prompt "iPhone 15 icin masaustu organizer tasarla, kalemler icin bolum ve telefon icin egimli yuva olsun, ustu acik" -ProjectName "_ptest-planner-r2" -OutPath $r2spec 2>&1 | Out-Null
$before = (Get-Content -LiteralPath $r2spec -Raw).Length
$r2rep = (& (Join-Path $Root "engine\Invoke-DesignPlanner.ps1") -SpecFile $r2spec -Prompt "iPhone 15 icin masaustu organizer tasarla, kalemler icin bolum ve telefon icin egimli yuva olsun, ustu acik" 2>&1 | Out-String) | ConvertFrom-Json
$after = (Get-Content -LiteralPath $r2spec -Raw).Length
if ([string]$r2rep.needs_input -ne "" -and $r2rep.applied -eq $false -and $before -eq $after) { T-Pass "R2-phone-model" "belirli modelde NEEDS_INPUT, spec degismedi" }
else { T-Fail "R2-phone-model" "model varsayimi yapildi veya spec degisti" }

# R3+R5: benchmark-1 uctan uca (pipeline)
& (Join-Path $Root "engine\Invoke-Pipeline.ps1") -Prompt $B1 -ProjectName "_ptest-planner-b1" 2>&1 | Out-Null
$b1res = Get-Content -LiteralPath (Join-Path $WorkRoot "projects\_ptest-planner-b1\pipeline-result.json") -Raw | ConvertFrom-Json
$b1spec = Get-Content -LiteralPath (Join-Path $WorkRoot "projects\_ptest-planner-b1\spec.json") -Raw | ConvertFrom-Json
$b1stl = Join-Path $WorkRoot "projects\_ptest-planner-b1\output\body.stl"
$b1mesh = (& (Join-Path $Root "engine\Get-MeshQuality.ps1") -StlFile $b1stl -AsJson 2>&1 | Out-String) | ConvertFrom-Json
if ([string]$b1res.status -eq "PASS" -and @($b1res.questions).Count -eq 0) { T-Pass "R3-b1-pipeline" "benchmark-1 NEEDS_INPUT'siz PASS" }
else { T-Fail "R3-b1-pipeline" ("status=" + [string]$b1res.status + " soru=" + @($b1res.questions).Count) }
if ((Test-Path -LiteralPath $b1stl) -and (Get-Item -LiteralPath $b1stl).Length -gt 1000 -and [string]$b1mesh.status -eq "PASS") { T-Pass "R3-b1-stl" "gercek STL + mesh PASS (watertight)" }
else { T-Fail "R3-b1-stl" "STL yok/kucuk veya mesh FAIL" }
if ($null -ne $b1spec.planner -and @($b1spec.planner.assumptions).Count -ge 8) { T-Pass "R5-assumptions" "varsayimlar spec.planner'da kayitli" }
else { T-Fail "R5-assumptions" "planner blogu eksik" }

# R4: benchmark-2 (12 derece kullanici degeri)
& (Join-Path $Root "engine\Invoke-Pipeline.ps1") -Prompt $B2 -ProjectName "_ptest-planner-b2" 2>&1 | Out-Null
$b2res = Get-Content -LiteralPath (Join-Path $WorkRoot "projects\_ptest-planner-b2\pipeline-result.json") -Raw | ConvertFrom-Json
$b2spec = Get-Content -LiteralPath (Join-Path $WorkRoot "projects\_ptest-planner-b2\spec.json") -Raw | ConvertFrom-Json
$b2stl = Join-Path $WorkRoot "projects\_ptest-planner-b2\output\body.stl"
$b2mesh = (& (Join-Path $Root "engine\Get-MeshQuality.ps1") -StlFile $b2stl -AsJson 2>&1 | Out-String) | ConvertFrom-Json
if ([string]$b2res.status -eq "PASS" -and [double]$b2spec.planner.phone_angle_deg -eq 12 -and [string]$b2spec.planner.angle_provenance -eq "kullanici") { T-Pass "R4-b2-angle" "12 derece kullanici degeri + PASS" }
else { T-Fail "R4-b2-angle" ("aci=" + [string]$b2spec.planner.phone_angle_deg + " status=" + [string]$b2res.status) }
if ((Test-Path -LiteralPath $b2stl) -and [string]$b2mesh.status -eq "PASS" -and [string]$b2mesh.watertight -eq "True") { T-Pass "R4-b2-stl" "gercek STL + watertight" }
else { T-Fail "R4-b2-stl" "STL/mesh sorunu" }

# R6: mevcut geometri davranisi (box+hollow bbox degismedi)
. (Join-Path $Root "engine\Geometry.ps1")
$g = New-GBox 80 40 20
$h = New-GHollowBox 80 40 20 2.5 $true 2.5
if (($g.bmax -join ",") -eq "80,40,20" -and $h.ok -eq $true) { T-Pass "R6-geometry" "mevcut geometri davranisi korunuyor" }
else { T-Fail "R6-geometry" "box/hollow davranisi degisti" }

Write-Output "----------------------------------------"
Write-Output "PLANNER SONUC: $pass / $($pass + $fail) test gecti"
if ($fail -gt 0) { exit 1 } else { exit 0 }
