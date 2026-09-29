<#
.SYNOPSIS
  Phase 7 TDD: professional printability (T-PRINT-01..10).
.DESCRIPTION
  Dosya ASCII-only. Analyzer spec-only calisir (hizli, OpenSCAD yok).
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-PrintabilityPro.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-PTResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-PTDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("pt-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-PTSpec($tag, $wall, $holes, $extra) {
  $d = New-PTDir $tag
  $hol = $null
  if ($null -ne $wall) { $hol = [pscustomobject]@{ wall_mm = $wall; open_top = $true; bottom_thickness_mm = $null } }
  $body = [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 160; depth_mm = 100; height_mm = 45 }
    hollow = $hol; holes = @($holes); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
  if ($null -ne $extra -and $extra -ne "") {
    $body | Add-Member -NotePropertyName "divider_pattern" -NotePropertyValue ([pscustomobject]@{ count = 2; thickness_mm = 2; top_gap_mm = 0; orientation = "along_length"; status = "ok" }) -Force
  }
  $sp = [pscustomobject]@{ project_name = $tag; prompt = $tag; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($body); assembly = $null; material = $null }
  $sf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
  return @{ dir = $d; file = $sf }
}
function Get-PTAnalysis($specFile, $printerFile) {
  if ([string]$printerFile -ne "") {
    $o = & (Join-Path $EngineDir "Analyze-Printability.ps1") -SpecFile $specFile -PrinterFile $printerFile -AsJson 2>&1 | Out-String
  } else {
    $o = & (Join-Path $EngineDir "Analyze-Printability.ps1") -SpecFile $specFile -AsJson 2>&1 | Out-String
  }
  return ($o | ConvertFrom-Json)
}
function New-PTHole($id, $type, $dia, $axis) {
  return [pscustomobject]@{
    id = $id; hole_type = $type; diameter_mm = $dia
    center_x_mm = 20; center_y_mm = 20; axis = $axis
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "ok"
  }
}

# T-PRINT-01: ince duvar konum + gereksinim kaynagi ile.
$r = New-PTSpec "pt01" 0.6 @() ""
$a = Get-PTAnalysis $r.file ""
$mw = @(@($a.checks) | Where-Object { [string]$_.id -eq "min_wall" })
Add-PTResult "T-PRINT-01" (($mw.Count -gt 0) -and ([string]$mw[0].component -eq "body") -and ([string]$mw[0].requirement_source -eq "none")) "duvar konumlu, kaynaksiz"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-02: delik tip/eksen/tolerans bilgisi.
$r = New-PTSpec "pt02" 2 @((New-PTHole "h1" "blind" 6 "z")) ""
$d = New-PTDir "pt02b"
$sp = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
$sp.components[0].tolerance = [pscustomobject]@{ type = "clearance"; clearance_mm = 0.2; fit_to = $null; status = "ok" }
$sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $d "spec.json") -Encoding UTF8
$a = Get-PTAnalysis (Join-Path $d "spec.json") ""
$hs = @(@($a.checks) | Where-Object { [string]$_.id -eq "hole_size" })
$msg = ""
if ($hs.Count -gt 0) { $msg = [string]$hs[0].message }
Add-PTResult "T-PRINT-02" (($msg -match "blind") -and ($msg -match "clearance")) "delik detayli"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-03: z-disi eksen overhang adayi.
$r = New-PTSpec "pt03" 2 @((New-PTHole "h1" "through" 6 "x")) ""
$a = Get-PTAnalysis $r.file ""
$ov = @(@($a.checks) | Where-Object { [string]$_.id -eq "overhang_estimate" })
Add-PTResult "T-PRINT-03" (($ov.Count -gt 0) -and ([string]$ov[0].status -eq "WARNING") -and ([string]$ov[0].severity -eq "medium") -and ([string]$ov[0].message -match "h1")) "x-ekseni aday"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-04: bolme acikligi bridge adayi.
$r = New-PTSpec "pt04" 2 @() "div"
$a = Get-PTAnalysis $r.file ""
$br = @(@($a.checks) | Where-Object { [string]$_.id -eq "bridging_risk" })
Add-PTResult "T-PRINT-04" (($br.Count -gt 0) -and ([string]$br[0].status -eq "WARNING") -and ([string]$br[0].message -match "96")) "span 96 bridge"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-05: destek geometriyi degistirmez (spec sabiti).
$r = New-PTSpec "pt05" 2 @((New-PTHole "h1" "through" 6 "x")) ""
$before = Get-Content -LiteralPath $r.file -Raw
$a = Get-PTAnalysis $r.file ""
$after = Get-Content -LiteralPath $r.file -Raw
$sq = @(@($a.checks) | Where-Object { [string]$_.id -eq "support_estimate" })
Add-PTResult "T-PRINT-05" (($before -eq $after) -and ($sq.Count -gt 0)) "destek ayri, spec ayni"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-06: oryantasyon adaylari + deterministik oneri (skor uydurma yok).
$d = New-PTDir "pt06"
$sp = [pscustomobject]@{
  project_name = "pt06"; prompt = "pt06"; metadata = [pscustomobject]@{ spec_version = "2.1" }
  components = @([pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 80; depth_mm = 40; height_mm = 20 }
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @(); tolerance = $null
  })
  assembly = $null; material = $null
}
$sf = Join-Path $d "spec.json"
$sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
$or = & (Join-Path $EngineDir "Analyze-Orientation.ps1") -SpecFile $sf -AsJson 2>&1 | Out-String | ConvertFrom-Json
$ors = @(@($or[0]).orientations)
$noScore = $true
foreach ($o in $ors) {
  if ($null -ne $o.score -or $null -ne $o.overall_score) { $noScore = $false }
}
Add-PTResult "T-PRINT-06" ((@($ors).Count -eq 3) -and ([string]$or[0].recommended -match "Orientation A") -and $noScore) "3 aday, skor yok"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-07: onarim yikici degil (watertight giriste yuzey korunur).
$d = New-PTDir "pt07"
. (Join-Path $EngineDir "AiReconstruct.ps1")
$fullMesh = Join-Path $d "full.stl"
New-MockReconMesh $fullMesh 10 10 10 | Out-Null
$pyRoot = $null
$ev = [System.Environment]::GetEnvironmentVariable("THREE_D_AI_EXTERNAL")
if (-not [string]::IsNullOrWhiteSpace($ev)) { $pyRoot = $ev }
else { $pyRoot = Join-Path (Split-Path -Parent $Root) "3D-AI-External" }
$py = Join-Path $pyRoot (Join-Path "envs" (Join-Path "python312" "python.exe"))
$repOk = $false
if ((Test-Path -LiteralPath $py) -and (Test-Path -LiteralPath (Join-Path $pyRoot (Join-Path "envs" "repair_mesh.py")))) {
  $fixedMesh = Join-Path $d "fixed.stl"
  $ro = & $py (Join-Path $pyRoot (Join-Path "envs" "repair_mesh.py")) $fullMesh $fixedMesh 2>&1 | Out-String
  try {
    $rj = $ro | ConvertFrom-Json
    $q1 = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $fullMesh -AsJson 2>&1 | Out-String | ConvertFrom-Json
    $q2 = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $fixedMesh -AsJson 2>&1 | Out-String | ConvertFrom-Json
    $repOk = ([bool]$rj.watertight -eq $true -and [bool]$rj.normals_ok -eq $true -and [int]$q1.triangle_count -eq [int]$q2.triangle_count)
  } catch { $repOk = $false }
}
Add-PTResult "T-PRINT-07" $repOk "onarim yikici degil"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-08: profilsiz min karsilastirma yok.
$r = New-PTSpec "pt08" 0.6 @((New-PTHole "h1" "through" 1  "z")) ""
$a = Get-PTAnalysis $r.file ""
$fab = $false
foreach ($c in @($a.checks)) {
  if ($null -ne $c.limit) { $fab = $true }
}
Add-PTResult "T-PRINT-08" (-not $fab) "uydurma limit yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-09: geometri-disi mod tamamlanir.
$r = New-PTSpec "pt09" $null @() ""
$a = Get-PTAnalysis $r.file ""
Add-PTResult "T-PRINT-09" (($null -ne $a) -and ($null -ne $a.status) -and (@($a.checks).Count -gt 0)) "profil olmasa da analiz biter"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PRINT-10: null degerler cokertmez.
$r = New-PTSpec "pt10" $null @((New-PTHole "h1" "through" 6 "z")) ""
$crash = $false
try { $a = Get-PTAnalysis $r.file "" } catch { $crash = $true }
$needInput = $false
if (-not $crash) {
  foreach ($c in @($a.checks)) { if ([string]$c.status -eq "NEEDS_INPUT") { $needInput = $true } }
}
Add-PTResult "T-PRINT-10" ((-not $crash) -and $needInput) "null guvenli + NEEDS_INPUT"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("PRINTABILITY SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
