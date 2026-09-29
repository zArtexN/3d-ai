<#
.SYNOPSIS
  Phase 6 TDD: AI reconstruction candidate flow (T-REC-01..15).
.DESCRIPTION
  Mock motor test-disidir (gercek AI calismaz; registry NOT_READY).
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-Reconstruction.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-RECResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-RECDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("rec-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-TestPng($path, $w, $h, $r, $g, $b) {
  Add-Type -AssemblyName System.Drawing
  $bm = New-Object System.Drawing.Bitmap($w, $h)
  $gr = [System.Drawing.Graphics]::FromImage($bm)
  $gr.Clear([System.Drawing.Color]::FromArgb($r, $g, $b))
  $bm.SetPixel(0, 0, [System.Drawing.Color]::FromArgb((($r + 1) % 256), $g, $b))
  $bm.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $gr.Dispose(); $bm.Dispose()
}
function NumEq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.01) } catch { return $false }
}
function Invoke-RECFlow($dir, $images, $views, $engine, $w, $allowMock, $accept) {
  $argHash = @{ ProjectDir = $dir; ImageFiles = @($images); EngineId = $engine }
  if (@($views).Count -gt 0) { $argHash["ViewNames"] = @($views) }
  if ($w -gt 0) { $argHash["KnownWidthMm"] = [double]$w }
  if ($allowMock) { $argHash["AllowMock"] = $true }
  if ($accept) { $argHash["Accept"] = $true }
  $o = & (Join-Path $EngineDir "Invoke-Reconstruction.ps1") @argHash 2>&1 | Out-String
  try { return ($o | ConvertFrom-Json) } catch { return $null }
}

# T-REC-01: tek goruntu + bilinen olcek.
$d = New-RECDir "rec01"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 100 $true $false
$ok1 = ($null -ne $r -and [string]$r.status -eq "OK" -and (NumEq $r.scale.value 2.5))
Add-RECResult "T-REC-01" $ok1 "tek goruntu olcek 2.5"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-02: coklu goruntu MEDIUM + view kaydi.
$d = New-RECDir "rec02"
New-TestPng (Join-Path $d "f.png") 200 150 200 50 50
New-TestPng (Join-Path $d "b.png") 150 200 50 200 50
New-TestPng (Join-Path $d "t.png") 180 180 50 50 200
$r = Invoke-RECFlow $d @((Join-Path $d "f.png"), (Join-Path $d "b.png"), (Join-Path $d "t.png")) @("front", "back", "top") "mock" 100 $true $false
$ok2 = ($null -ne $r -and [string]$r.confidence.level -eq "MEDIUM" -and (@($r.views).Count -eq 3))
Add-RECResult "T-REC-02" $ok2 "multi-view MEDIUM"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-03: gecersiz goruntu BLOCKED, version yok.
$d = New-RECDir "rec03"
"not-an-image" | Set-Content -LiteralPath (Join-Path $d "bad.png") -Encoding UTF8
$r = Invoke-RECFlow $d @((Join-Path $d "bad.png")) @() "mock" 0 $true $false
$vdir = Join-Path $d "versions"
Add-RECResult "T-REC-03" (($null -ne $r) -and ([string]$r.status -eq "BLOCKED") -and (-not (Test-Path -LiteralPath $vdir))) "gecersiz goruntu BLOCKED"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-04: olceksiz -> UNKNOWN + genislik sorusu, ops yok.
$d = New-RECDir "rec04"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 0 $true $false
$wq = @(@($r.questions) | Where-Object { [string]$_ -match "genislik" })
Add-RECResult "T-REC-04" (($null -ne $r) -and ([string]$r.scale.status -eq "UNKNOWN") -and ($wq.Count -gt 0) -and (@($r.proposed_patch).Count -eq 0)) "olcek UNKNOWN, soru var"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-05: bilinen olcek -> boyutlar dogru (40*2.5=100, 30*2.5=75, 20*2.5=50).
$d = New-RECDir "rec05"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 100 $true $false
$ops = @($r.proposed_patch)
$mw = $null; $mh = $null; $md = $null
foreach ($o in $ops) {
  if ([string]$o.path -eq "body.base.width_mm") { $mw = [double]$o.value }
  if ([string]$o.path -eq "body.base.height_mm") { $mh = [double]$o.value }
  if ([string]$o.path -eq "body.base.depth_mm") { $md = [double]$o.value }
}
Add-RECResult "T-REC-05" ((NumEq $mw 100) -and (NumEq $mh 50) -and (NumEq $md 75)) "olcekli boyutlar 100/75/50"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-06: mutabakat (patch degerleri == olcekli olcum).
$d = New-RECDir "rec06"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 80 $true $false
$ok6 = ($null -ne $r -and [string]$r.status -eq "OK")
foreach ($o in @($r.proposed_patch)) {
  if ([string]$o.path -eq "body.base.width_mm" -and -not (NumEq ([double]$o.value) 80)) { $ok6 = $false }
  if ([string]$o.path -eq "body.base.depth_mm" -and -not (NumEq ([double]$o.value) 60)) { $ok6 = $false }
  if ([string]$o.path -eq "body.base.height_mm" -and -not (NumEq ([double]$o.value) 40)) { $ok6 = $false }
}
Add-RECResult "T-REC-06" $ok6 "patch == olcekli olcum (80/60/40)"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-08: onarim (acik mesh -> watertight).
$d = New-RECDir "rec08"
. (Join-Path $EngineDir "AiReconstruct.ps1")
$openMesh = Join-Path $d "open.stl"
$fullMesh = Join-Path $d "full.stl"
New-MockReconMesh $fullMesh 10 10 10 | Out-Null
$fl = Get-Content -LiteralPath $fullMesh
$kept = @($fl[0..77] + @($fl[85]))
[System.IO.File]::WriteAllLines($openMesh, $kept, (New-Object System.Text.UTF8Encoding $false))
$pyRoot = $null
$ev = [System.Environment]::GetEnvironmentVariable("THREE_D_AI_EXTERNAL")
if (-not [string]::IsNullOrWhiteSpace($ev)) { $pyRoot = $ev }
else { $pyRoot = Join-Path (Split-Path -Parent $Root) "3D-AI-External" }
$py = Join-Path $pyRoot (Join-Path "envs" (Join-Path "python312" "python.exe"))
$fixedMesh = Join-Path $d "fixed.stl"
$repOk = $false
if ((Test-Path -LiteralPath $py) -and (Test-Path -LiteralPath (Join-Path $pyRoot (Join-Path "envs" "repair_mesh.py")))) {
  $ro = & $py (Join-Path $pyRoot (Join-Path "envs" "repair_mesh.py")) $openMesh $fixedMesh 2>&1 | Out-String
  try {
    $rj = $ro | ConvertFrom-Json
    $repOk = ([bool]$rj.watertight -eq $true)
  } catch { $repOk = $false }
}
Add-RECResult "T-REC-08" $repOk "acik mesh onarildi"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-07: mesh QA alanlari.
$d = New-RECDir "rec07"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 100 $true $false
Add-RECResult "T-REC-07" (($null -ne $r) -and ([bool]$r.mesh_qa.watertight -eq $true) -and ([double]$r.mesh_qa.volume_mm3 -gt 0) -and (@($r.mesh_qa.bbox_mm).Count -eq 3)) "mesh QA mevcut"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-11: bilinmeyen motor -> NOT_READY/BLOCKED, version yok.
$d = New-RECDir "rec11"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "bogus-engine" 0 $false $false
$vdir = Join-Path $d "versions"
Add-RECResult "T-REC-11" (($null -ne $r) -and ([string]$r.status -ne "OK") -and (-not (Test-Path -LiteralPath $vdir))) "bilinmeyen motor uretmez"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-12: machine-limited (trellis) -> NOT_READY, indirme yok.
$d = New-RECDir "rec12"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "trellis" 0 $false $false
Add-RECResult "T-REC-12" (($null -ne $r) -and ([string]$r.status -eq "NOT_READY")) "trellis NOT_READY"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-13: AllowMock yoksa mock BLOCKED.
$d = New-RECDir "rec13"
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 0 $false $false
Add-RECResult "T-REC-13" (($null -ne $r) -and ([string]$r.status -eq "BLOCKED")) "mock kapisiz BLOCKED"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC-09/10: izolasyon + spec korumasi (kabul yokken).
$d = New-RECDir "rec0910"
$spec0 = [pscustomobject]@{ project_name = "rec0910"; prompt = "x"; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @(); assembly = $null; material = $null }
$spec0 | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $d "spec.json") -Encoding UTF8
$before = Get-Content -LiteralPath (Join-Path $d "spec.json") -Raw
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 100 $true $false
$after = Get-Content -LiteralPath (Join-Path $d "spec.json") -Raw
Add-RECResult "T-REC-09" ($before -eq $after) "kabul yokken spec ayni"
Add-RECResult "T-REC-10" ($before -eq $after) "DesignSpec korunur"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-REC accept: version uretimi + boyutlar.
$d = New-RECDir "recacc"
$spec0 = [pscustomobject]@{
  project_name = "recacc"; prompt = "x"; metadata = [pscustomobject]@{ spec_version = "2.1" }
  components = @([pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 10; depth_mm = 10; height_mm = 10 }
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  })
  assembly = $null; material = $null
}
$spec0 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $d "spec.json") -Encoding UTF8
New-TestPng (Join-Path $d "front.png") 200 150 200 50 50
$r = Invoke-RECFlow $d @((Join-Path $d "front.png")) @() "mock" 100 $true $true
$vf = Join-Path $d (Join-Path "versions" "v002.json")
$vv = $null
if (Test-Path -LiteralPath $vf) { $vv = (Get-Content -LiteralPath $vf -Raw | ConvertFrom-Json).spec }
Add-RECResult "T-REC-ACC" (($null -ne $r) -and ([string]$r.status -eq "OK") -and ([string]$r.version -eq "v002") -and ($null -ne $vv) -and (NumEq $vv.components[0].base.width_mm 100)) "kabul versionlandi"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("RECON SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
