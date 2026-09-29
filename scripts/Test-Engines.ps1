<#
.SYNOPSIS
  Phase 5 engine registry/adapter testleri (T-ENG-01..10).
.DESCRIPTION
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-Engines.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngDir = Join-Path $Root (Join-Path "engine" "Engines")

$results = New-Object System.Collections.Generic.List[object]
function Add-ENGResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-ENGDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("eng-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

. (Join-Path $EngDir "EngineRegistry.ps1")
. (Join-Path $EngDir "EngineContract.ps1")
$reg = Get-EngineRegistry

# T-ENG-01: registry butunlugu.
$reqFields = @("id", "license", "status", "adapter", "capabilities")
$regOk = (@($reg.engines).Count -ge 15)
foreach ($e in @($reg.engines)) {
  foreach ($f in $reqFields) {
    if ($null -eq $e.$f) { $regOk = $false }
  }
}
Add-ENGResult "T-ENG-01" $regOk ("registry motor=" + @($reg.engines).Count)

# T-ENG-02: trimesh gercek analiz.
$stl = Join-Path $Root (Join-Path "projects" (Join-Path "organizer-v12" (Join-Path "output" "body.stl")))
$h = Get-EngineHealth $reg "trimesh"
$anOk = $false; $det = ""
if ([string]$h.status -eq "READY") {
  $r = Invoke-EngineOp $reg "trimesh" "Analyze" @{ Stl = $stl; OutJson = "" }
  $anOk = ([string]$r.status -eq "OK" -and [bool]$r.watertight -eq $true -and [int]$r.faces -gt 0 -and @($r.bbox_max).Count -eq 3)
  $det = ("watertight=" + $r.watertight + " faces=" + $r.faces)
} else { $det = "health=" + $h.status }
Add-ENGResult "T-ENG-02" $anOk ("trimesh Analyze: " + $det)

# T-ENG-03: orca tespiti (yapili sonuc, uydurma yok).
$oh = Get-EngineHealth $reg "orcaslicer"
$ohOk = ([string]$oh.status -eq "READY" -and (Test-Path -LiteralPath ([string]$oh.exe))) -or ([string]$oh.status -eq "NOT_READY" -and [string]$oh.reason -ne "")
Add-ENGResult "T-ENG-03" $ohOk ("orca health=" + $oh.status)

# T-ENG-04: profilsiz slice BLOCKED, G-code yok.
$d = New-ENGDir "eng04"
$sr = Invoke-EngineOp $reg "orcaslicer" "Slice" @{ Model = $stl; OutDir = $d }
$noG = $true
foreach ($gf in (Get-ChildItem -LiteralPath $d -Filter "*.gcode" -ErrorAction SilentlyContinue)) { $noG = $false }
Add-ENGResult "T-ENG-04" (([string]$sr.status -eq "BLOCKED" -or [string]$sr.status -eq "NOT_READY") -and $noG) ("slice--> " + $sr.status)
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-ENG-05: bilinmeyen engine/op UNSUPPORTED (throw yok).
$u1 = Invoke-EngineOp $reg "yok-motor" "Analyze" @{}
$u2 = Invoke-EngineOp $reg "trimesh" "Slice" @{}
Add-ENGResult "T-ENG-05" (([string]$u1.status -eq "UNSUPPORTED") -and ([string]$u2.status -eq "UNSUPPORTED")) "UNSUPPORTED sozlesmesi"

# T-ENG-06: machine-limited AI (trellis): NOT_READY + sebep, indirme yok.
$th = Get-EngineHealth $reg "trellis"
$wdir = Join-Path $env:TEMP "eng06x"
$noDl = $true
$tdir = Join-Path $Root "..\3D-AI-External\ai-reconstruction\TRELLIS"
try {
  $tdir = [System.IO.Path]::GetFullPath((Join-Path $Root "..\3D-AI-External\ai-reconstruction\TRELLIS"))
} catch { }
if (Test-Path -LiteralPath $tdir) {
  foreach ($ext in @("*.safetensors", "*.bin", "*.pt", "*.ckpt")) {
    $hit = Get-ChildItem -LiteralPath $tdir -Recurse -Filter $ext -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $hit) { $noDl = $false }
  }
}
Add-ENGResult "T-ENG-06" (([string]$th.status -eq "MACHINE_LIMITED") -and ([string]$th.reason -ne "") -and $noDl) ("trellis " + $th.status)
Remove-Item -LiteralPath $wdir -Recurse -Force -ErrorAction SilentlyContinue

# T-ENG-07: lisans-risklilerde adapter yok + dogru status.
$lrOk = $true
foreach ($id in @("text-to-cad", "pymeshfix", "prusa", "curaengine")) {
  $e = Get-Engine $reg $id
  if ($null -eq $e -or [string]$e.adapter -ne "") { $lrOk = $false }
  if ([string]$e.status -ne "LICENSE_REVIEW" -and [string]$e.status -ne "NOT_INTEGRATED") { $lrOk = $false }
}
Add-ENGResult "T-ENG-07" $lrOk "riskli motorlarda adapter yok"

# T-ENG-08: aday izolasyonu (spec degismez, cikti verilen yolda).
$d = New-ENGDir "eng08"
$specSrc = Join-Path $Root (Join-Path "projects" (Join-Path "organizer-v12" "spec.json"))
$specCopy = Join-Path $d "spec.json"
Copy-Item -LiteralPath $specSrc -Destination $specCopy -Force
$before = (Get-Content -LiteralPath $specCopy -Raw).Length
$oj = Join-Path $d "mesh.json"
$r = Invoke-EngineOp $reg "trimesh" "Analyze" @{ Stl = $stl; OutJson = $oj }
$after = (Get-Content -LiteralPath $specCopy -Raw).Length
Add-ENGResult "T-ENG-08" (($before -eq $after) -and (Test-Path -LiteralPath $oj) -and ([string]$r.status -eq "OK")) "izolasyon: spec ayni, cikti hedefte"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-ENG-09: adapter dosyalarinda hard-coded kullanici yolu yok.
$hcOk = $true
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $EngDir "adapters") -Filter "*.ps1")) {
  $t = Get-Content -LiteralPath $f.FullName -Raw
  if ($t -match "C:\\Users") { $hcOk = $false }
}
Add-ENGResult "T-ENG-09" $hcOk "hard-coded yol yok"

# T-ENG-10: bozuk env -> NOT_READY (throw yok).
$oldExt = [System.Environment]::GetEnvironmentVariable("THREE_D_AI_EXTERNAL")
try {
  [System.Environment]::SetEnvironmentVariable("THREE_D_AI_EXTERNAL", (Join-Path ([System.IO.Path]::GetTempPath()) "eng-nope-xyz"))
  . (Join-Path $EngDir (Join-Path "adapters" "TrimeshAdapter.ps1"))
  $bh = Trimesh-Health
  $fbOk = ([string]$bh.status -eq "NOT_READY")
} catch { $fbOk = $false }
finally { [System.Environment]::SetEnvironmentVariable("THREE_D_AI_EXTERNAL", $oldExt) }
Add-ENGResult "T-ENG-10" $fbOk "fallback NOT_READY"

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("ENGINES SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
