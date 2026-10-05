<#
.SYNOPSIS
  wall_station planner niyeti regression testleri (WS-1..WS-5).
.DESCRIPTION
  WS-1: hedef prompt -> PASS, soru yok, CAD/STL/validation/mesh/printability.
  WS-2: gercek geometri dogrulamasi (SCAD metni + STL mesh + parca listesi).
  WS-3: determinizm (iki kosum ayni kritik sonuclar).
  WS-4: belirli telefon modeli -> NEEDS_INPUT, uydurma yok.
  WS-5: organizer davranisi bozulmadi.
  Mock/fake YOK (gercek OpenSCAD). NEEDS_INPUT PASS'e cevrilmez.
.EXAMPLE
  powershell -File scripts\Test-WallStation.ps1
#>
param()

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$script:pass = 0; $script:fail = 0
function WS-Result($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

$wallPrompt = "Duvara monte edilecek modern ve kompakt bir kulaklik + telefon istasyonu tasarla. Kulaklik icin bir kanca, yaklasik 12 derece egimli telefon yuvasi, telefonun sarj kablosunun gececegi bir kablo kanali, iki dikey hizali montaj deligi, duz duvar temas yuzeyi ve desteksiz 3D baskiya uygun tasarim olustur. Kritik olculer belirtilmedigi icin uygun olculeri tasarim amacina gore belirle; yaptigin varsayimlari DesignSpec icinde acikca belirt."
$orgPrompt = "Masam icin bolmeli bir organizer tasarla. Kalemler icin bolum, telefon icin egimli yuva ve sarj kablosu icin kanal olsun. Ustu acik, desteksiz basilsin."

function Invoke-WS-Pipe($name, $prompt) {
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Pipeline.ps1") `
    -Prompt $prompt -ProjectName $name 2>&1 | Out-String
  $rp = Join-Path $Root (Join-Path "projects" (Join-Path $name "pipeline-result.json"))
  if (-not (Test-Path -LiteralPath $rp)) { return $null }
  return (Get-Content -LiteralPath $rp -Raw | ConvertFrom-Json)
}
function Get-WS-Spec($name) {
  $sp = Join-Path $Root (Join-Path "projects" (Join-Path $name "spec.json"))
  if (-not (Test-Path -LiteralPath $sp)) { return $null }
  return (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json)
}

# ---- WS-1: normal prompt e2e ----
try {
  $res = Invoke-WS-Pipe "_ptest-ws-station" $wallPrompt
  $w1ok = $false; $w1note = "sonuc yok"
  if ($null -ne $res) {
    $sp = Get-WS-Spec "_ptest-ws-station"
    $pdir = Join-Path $Root (Join-Path "projects" "_ptest-ws-station")
    $body = $null
    if ($null -ne $sp) { foreach ($c in @($sp.components)) { if ($c -and [string]$c.id -eq "body") { $body = $c; break } } }
    $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" -ErrorAction SilentlyContinue | Select-Object -First 1
    $scad = Get-ChildItem -LiteralPath (Join-Path $pdir "cad") -Filter "*.scad" -ErrorAction SilentlyContinue | Select-Object -First 1
    $hook = $null; $lip = $null; $wdg = $null; $cut = $null
    if ($null -ne $body) {
      foreach ($pt in @($body.partitions)) {
        if ($pt -and [string]$pt.id -eq "hook1") { $hook = $pt }
        if ($pt -and [string]$pt.id -eq "lip1") { $lip = $pt }
      }
      foreach ($w in @($body.wedges)) { if ($w -and [string]$w.id -eq "w1") { $wdg = $w } }
      foreach ($t in @($body.cutouts)) { if ($t -and [string]$t.id -eq "c1") { $cut = $t } }
    }
    $holesOk = ($null -ne $body -and @($body.holes).Count -eq 2)
    if ($holesOk) {
      $hxa = [double](@($body.holes))[0].center_x_mm; $hxb = [double](@($body.holes))[1].center_x_mm
      $holesOk = ($hxa -eq $hxb)
    }
    $mesh = $null
    if ($null -ne $stl) {
      $mesh = (& (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $stl.FullName -AsJson 2>&1 | Out-String) | ConvertFrom-Json
    }
    $pa = (& (Join-Path $EngineDir "Analyze-Printability.ps1") -SpecFile (Join-Path $pdir "spec.json") -AsJson 2>&1 | Out-String) | ConvertFrom-Json
    $paOk = ($null -ne $pa -and @("PASS", "WARNING", "NEEDS_INPUT") -contains [string]$pa.status)
    $checks = @(
      ([string]$res.status -eq "PASS" -or [string]$res.status -eq "WARNING"),
      (@($res.questions).Count -eq 0),
      ($null -ne $sp -and [string]$sp.planner.intent -eq "wall_station"),
      ($null -ne $body -and [double]$body.base.width_mm -eq 140 -and [double]$body.base.depth_mm -eq 100 -and [double]$body.base.height_mm -eq 10),
      $holesOk,
      ($null -ne $wdg -and [double]$wdg.angle_deg -eq 12 -and [bool]$wdg.angle_driven -eq $true),
      ([string]$sp.planner.phone_angle_deg -eq "12" -and [string]$sp.planner.angle_provenance -eq "kullanici"),
      ($null -ne $lip),
      ($null -ne $hook),
      ($null -ne $cut -and [string]$cut.status -eq "ok"),
      ($null -ne $scad),
      ($null -ne $stl -and $stl.Length -gt 1000),
      ($null -ne $mesh -and [string]$mesh.status -eq "PASS" -and [bool]$mesh.watertight -eq $true),
      $paOk,
      (@($sp.components | Where-Object { $_ -ne $null }).Count -eq 1)
    )
    $bad = 0; foreach ($ck in $checks) { if (-not $ck) { $bad++ } }
    if ($bad -eq 0) {
      $w1ok = $true
      $w1note = ("PASS sorusuz intent=wall_station 2-delik 12deg slot+kanca stl=" + $stl.Length + " mesh=PASS print=" + [string]$pa.status)
    } else {
      $w1note = ("status=" + [string]$res.status + " soru=" + @($res.questions).Count + " saglanmayan=" + $bad + "/15")
    }
  }
  WS-Result "WS-1-station-e2e" $w1ok $w1note
} catch { WS-Result "WS-1-station-e2e" $false $_.Exception.Message }

# ---- WS-2: gercek geometri dogrulamasi ----
try {
  $pdir = Join-Path $Root (Join-Path "projects" "_ptest-ws-station")
  $w2ok = $false; $w2note = "WS-1 uretimi yok"
  $scad = Get-ChildItem -LiteralPath (Join-Path $pdir "cad") -Filter "*.scad" -ErrorAction SilentlyContinue | Select-Object -First 1
  $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $scad -and $null -ne $stl) {
    $txt = Get-Content -LiteralPath $scad.FullName -Raw
    $holeDias = @([regex]::Matches($txt, 'hole_h\d+_dia\s*=')) | ForEach-Object { $_.Value }
    $hasPoly = $txt -match "polyhedron"
    $hasHull = $txt -match "hull\(\)"
    $hasHook = $txt -match "hook1"
    $mesh = (& (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $stl.FullName -AsJson 2>&1 | Out-String) | ConvertFrom-Json
    $inX = $true; $inY = $true; $inZ = $true
    if ($null -ne $mesh -and $null -ne $mesh.bbox_min -and $null -ne $mesh.bbox_max) {
      $inX = ([double]$mesh.bbox_min[0] -ge -0.01 -and [double]$mesh.bbox_max[0] -le 140.01)
      $inY = ([double]$mesh.bbox_min[1] -ge -0.01 -and [double]$mesh.bbox_max[1] -le 100.01)
      $inZ = ([double]$mesh.bbox_min[2] -ge -0.01 -and [double]$mesh.bbox_max[2] -le 65.01)
    } else { $inX = $false; $inY = $false; $inZ = $false }
    $res2 = Get-Content -LiteralPath (Join-Path $pdir "pipeline-result.json") -Raw | ConvertFrom-Json
    $partIds = @(@($res2.parts) | ForEach-Object { [string]$_.id })
    $partsOk = ($partIds -contains "body" -and $partIds -contains "lip1" -and $partIds -contains "hook1" -and $partIds -contains "w1")
    $cks = @(
      (@($holeDias).Count -eq 2),
      $hasPoly, $hasHull, $hasHook,
      ($null -ne $mesh -and [bool]$mesh.watertight -eq $true -and [string]$mesh.status -eq "PASS"),
      ($inX -and $inY -and $inZ),
      $partsOk
    )
    $bad = 0; foreach ($ck in $cks) { if (-not $ck) { $bad++ } }
    if ($bad -eq 0) { $w2ok = $true; $w2note = "2 delik (4 yok) slot+kama+kanca SCAD+STL watertight bbox-icinde parcalar body/lip1/hook1/w1" }
    else { $w2note = ("delik=" + @($holeDias).Count + " poly=" + $hasPoly + " hull=" + $hasHull + " hook=" + $hasHook + " mesh=" + [string]$mesh.status + " bbox=" + ($inX -and $inY -and $inZ) + " parca=" + $partsOk) }
  }
  WS-Result "WS-2-real-geometry" $w2ok $w2note
} catch { WS-Result "WS-2-real-geometry" $false $_.Exception.Message }

# ---- WS-3: determinizm ----
try {
  $res = Invoke-WS-Pipe "_ptest-ws-station2" $wallPrompt
  $w3ok = $false; $w3note = "ikinci kosum uretilemedi"
  $a = Get-WS-Spec "_ptest-ws-station"; $b = Get-WS-Spec "_ptest-ws-station2"
  if ($null -ne $a -and $null -ne $b) {
    $ba = @($a.components | Where-Object { $_ -and [string]$_.id -eq "body" })[0]
    $bb = @($b.components | Where-Object { $_ -and [string]$_.id -eq "body" })[0]
    $fa = (@($ba.holes) | ForEach-Object { [string]$_.center_x_mm + "," + [string]$_.center_y_mm }) -join ";"
    $fb = (@($bb.holes) | ForEach-Object { [string]$_.center_x_mm + "," + [string]$_.center_y_mm }) -join ";"
    $same = (([string]$ba.base.width_mm + "x" + [string]$ba.base.depth_mm + "x" + [string]$ba.base.height_mm) -eq ([string]$bb.base.width_mm + "x" + [string]$bb.base.depth_mm + "x" + [string]$bb.base.height_mm)) `
      -and ($fa -eq $fb) `
      -and ([string]$a.planner.phone_angle_deg -eq [string]$b.planner.phone_angle_deg) `
      -and (@($ba.cutouts)[0].pos_x_mm -eq @($bb.cutouts)[0].pos_x_mm -and @($ba.cutouts)[0].pos_y_mm -eq @($bb.cutouts)[0].pos_y_mm) `
      -and (@($ba.partitions | Where-Object { $_ -and [string]$_.id -eq "hook1" })[0].x_mm -eq @($bb.partitions | Where-Object { $_ -and [string]$_.id -eq "hook1" })[0].x_mm) `
      -and (@($ba.holes).Count -eq @($bb.holes).Count -and @($ba.wedges).Count -eq @($bb.wedges).Count -and @($ba.cutouts).Count -eq @($bb.cutouts).Count -and @($ba.partitions).Count -eq @($bb.partitions).Count)
    if ($same) { $w3ok = $true; $w3note = "olcu+delik+aci+slot+kanca+aded ayni" }
    else { $w3note = "kosumlar farkli" }
  }
  WS-Result "WS-3-determinism" $w3ok $w3note
} catch { WS-Result "WS-3-determinism" $false $_.Exception.Message }

# ---- WS-4: belirli telefon modeli ----
try {
  $mp = "iPhone 15 icin duvara monte kulaklik ve telefon istasyonu tasarla, kanca ve egimli yuva olsun"
  $before = ""
  $r4spec = Join-Path $Root (Join-Path "projects" (Join-Path "_ptest-ws-model" "spec.json"))
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Pipeline.ps1") `
    -Prompt $mp -ProjectName "_ptest-ws-model" 2>&1 | Out-String
  $rp = Join-Path $Root (Join-Path "projects" (Join-Path "_ptest-ws-model" "pipeline-result.json"))
  $w4ok = $false; $w4note = "sonuc yok"
  if (Test-Path -LiteralPath $rp) {
    $res = Get-Content -LiteralPath $rp -Raw | ConvertFrom-Json
    $txt = [string]$res.reason + " " + [string]($res | ConvertTo-Json -Compress)
    if ([string]$res.status -eq "NEEDS_INPUT" -and $txt -match "iPhone|telefonun tam modeli") {
      $w4ok = $true; $w4note = "modelde NEEDS_INPUT, uydurma yok, PASS yok"
    } else { $w4note = ("status=" + [string]$res.status) }
  }
  WS-Result "WS-4-phone-model" $w4ok $w4note
} catch { WS-Result "WS-4-phone-model" $false $_.Exception.Message }

# ---- WS-5: organizer regression ----
try {
  $res = Invoke-WS-Pipe "_ptest-f-org" $orgPrompt
  $w5ok = $false; $w5note = "sonuc yok"
  if ($null -ne $res) {
    $pdir = Join-Path $Root (Join-Path "projects" "_ptest-f-org")
    $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (([string]$res.status -eq "PASS" -or [string]$res.status -eq "WARNING") -and @($res.questions).Count -eq 0 -and $null -ne $stl -and $stl.Length -gt 1000) {
      $w5ok = $true; $w5note = ("status=" + [string]$res.status + " sorusuz, stl=" + $stl.Length)
    } else { $w5note = ("status=" + [string]$res.status + " soru=" + @($res.questions).Count) }
  }
  WS-Result "WS-5-organizer" $w5ok $w5note
} catch { WS-Result "WS-5-organizer" $false $_.Exception.Message }

Write-Output "----------------------------------------"
Write-Output ("WALL-STATION SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
