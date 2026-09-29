<#
.SYNOPSIS
  AI reconstruction orkestratoru (Phase 6).
.DESCRIPTION
  Akis: giris dogrulama -> engine kontrolu (mock haric gercek AI yoksa
  NOT_READY) -> aday mesh (candidates/) -> mesh QA (Phase 2) -> olcum ->
  onarim denemesi (aday kopyasi) -> olcek -> patch onerisi -> sorular.
  Mevcut DesignSpec degismez; -Accept ile version uretilir.
  Mock motor test-disidir; -AllowMock sart.
.EXAMPLE
  powershell -File engine\Invoke-Reconstruction.ps1 -ProjectDir projects\x -ImageFiles @("a.png") -EngineId mock -AllowMock -Accept
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [string[]]$ImageFiles = @(),
  [string[]]$ViewNames = @(),
  [string]$EngineId = "auto",
  [double]$KnownWidthMm = 0,
  [double]$ReferenceMm = 0,
  [switch]$AllowMock,
  [switch]$Accept
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir
. (Join-Path $EngineDir "AiReconstruct.ps1")
. (Join-Path $EngineDir "DesignSpecPatch.ps1")
. (Join-Path $EngineDir "ProjectVersions.ps1")

function Write-ReconResult($obj, $code) {
  $obj | ConvertTo-Json -Depth 8
  exit $code
}

if (-not (Test-Path -LiteralPath $ProjectDir)) {
  New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
}
$candDir = Join-Path $ProjectDir (Join-Path "candidates" ("recon-" + ([System.Guid]::NewGuid().ToString("N")).Substring(0, 8)))
New-Item -ItemType Directory -Force -Path $candDir | Out-Null

$chk = Test-ReconImageSet $ImageFiles
if (-not $chk.ok) {
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-ReconResult ([pscustomobject]@{
    status = "BLOCKED"; reason = "giris dogrulama"; errors = @($chk.errors)
    version = $null; questions = @(); gcode_available = $false
  }) 2
}

$engine = [string]$EngineId
if ($engine -eq "auto" -or $engine -eq "") {
  $engine = "none-available"
}
if ($engine -eq "mock" -and -not $AllowMock) {
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-ReconResult ([pscustomobject]@{
    status = "BLOCKED"; reason = "mock motor test-disidir (-AllowMock sart)"
    version = $null; questions = @(); gcode_available = $false
  }) 2
}
if ($engine -ne "mock") {
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-ReconResult ([pscustomobject]@{
    status = "NOT_READY"; reason = ("motor hazir degil: " + $engine + " (registry MACHINE_LIMITED; agirlik indirilmedi)")
    version = $null; questions = @(); gcode_available = $false
  }) 3
}

$views = @()
for ($i = 0; $i -lt @($ImageFiles).Count; $i++) {
  $vn = "view" + ($i + 1)
  if ($i -lt @($ViewNames).Count -and -not [string]::IsNullOrWhiteSpace([string]$ViewNames[$i])) { $vn = [string]$ViewNames[$i] }
  $views += $vn
}
$meshPath = Join-Path $candDir "candidate.stl"
New-MockReconMesh $meshPath 40 30 20 | Out-Null

$mqTxt = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $meshPath -AsJson 2>&1 | Out-String
$mq = $null
try { $mq = $mqTxt | ConvertFrom-Json } catch { $mq = $null }
if ($null -eq $mq -or [string]$mq.status -ne "PASS") {
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-ReconResult ([pscustomobject]@{
    status = "BLOCKED"; reason = "aday mesh QA basarisiz"
    version = $null; questions = @(); gcode_available = $false
  }) 2
}
$bb = @($mq.bbox_size_mm)
$measuredUnits = 0
if (@($bb).Count -ge 3 -and [double]$bb[0] -gt 0) { $measuredUnits = [double]$bb[0] }

$repairInfo = [pscustomobject]@{ attempted = $false; improved = $false; note = "gerekmedi (watertight)" }
if ([bool]$mq.watertight -eq $false) {
  $repairInfo = [pscustomobject]@{ attempted = $true; improved = $false; note = "onarim denendi" }
  $pyRoot = $null
  $ev = [System.Environment]::GetEnvironmentVariable("THREE_D_AI_EXTERNAL")
  if (-not [string]::IsNullOrWhiteSpace($ev)) { $pyRoot = $ev }
  else { $pyRoot = Join-Path (Split-Path -Parent $Root) "3D-AI-External" }
  $py = Join-Path $pyRoot (Join-Path "envs" (Join-Path "python312" "python.exe"))
  $rscript = Join-Path $pyRoot (Join-Path "envs" "repair_mesh.py")
  if ((Test-Path -LiteralPath $py) -and (Test-Path -LiteralPath $rscript)) {
    $fixedPath = Join-Path $candDir "candidate-fixed.stl"
    try {
      $ro = & $py $rscript $meshPath $fixedPath 2>&1 | Out-String
      $rj = $ro | ConvertFrom-Json
      if ($null -ne $rj -and [bool]$rj.watertight -eq $true) {
        $fqTxt = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $fixedPath -AsJson 2>&1 | Out-String
        $fq = $fqTxt | ConvertFrom-Json
        if ($null -ne $fq -and [string]$fq.status -eq "PASS" -and [bool]$fq.watertight -eq $true) {
          $meshPath = $fixedPath
          $mq = $fq
          $repairInfo = [pscustomobject]@{ attempted = $true; improved = $true; note = "onarildi, QA tekrar gecti" }
        }
      }
    } catch { $repairInfo = [pscustomobject]@{ attempted = $true; improved = $false; note = "onarim basarisiz" } }
  } else {
    $repairInfo = [pscustomobject]@{ attempted = $false; improved = $false; note = "onarim araci yok" }
  }
}

$known = $null
if ($KnownWidthMm -gt 0 -or $ReferenceMm -gt 0) {
  $known = [pscustomobject]@{ width_mm = $KnownWidthMm; reference_mm = $ReferenceMm }
}
$scale = Get-ReconScale $measuredUnits $known
$conf = Get-ReconConfidence @($ImageFiles).Count ([string]$scale.status) "mock"
$scaledDims = $null
$unknowns = New-Object System.Collections.Generic.List[string]
if ([string]$scale.status -eq "KNOWN") {
  $s = [double]$scale.scale
  $bb2 = @($mq.bbox_size_mm)
  $scaledDims = [pscustomobject]@{
    width_mm = [math]::Round([double]$bb2[0] * $s, 3)
    depth_mm = [math]::Round([double]$bb2[1] * $s, 3)
    height_mm = [math]::Round([double]$bb2[2] * $s, 3)
  }
} else {
  $unknowns.Add("width") | Out-Null
  $unknowns.Add("height") | Out-Null
  $unknowns.Add("depth") | Out-Null
  $unknowns.Add("scale") | Out-Null
}
$prop = New-ReconPatchProposal $scaledDims $unknowns

$out = [pscustomobject]@{
  status = "OK"; reason = "aday uretildi"
  engine = "mock"; engine_version = "test-only"
  candidate_mesh = $meshPath
  mesh_qa = [pscustomobject]@{ status = [string]$mq.status; watertight = [bool]$mq.watertight; volume_mm3 = $mq.volume_mm3; bbox_mm = @($mq.bbox_size_mm) }
  repair = $repairInfo
  scale = [pscustomobject]@{ value = $scale.scale; source = [string]$scale.source; status = [string]$scale.status }
  confidence = [pscustomobject]@{ level = [string]$conf.level; reasons = @($conf.reasons) }
  views = @($views)
  proposed_patch = @($prop.ops)
  questions = @($prop.questions)
  version = $null; gcode_available = $false
}

if ($Accept -and [string]$scale.status -eq "KNOWN" -and @($prop.ops).Count -gt 0) {
  $specPath = Join-Path $ProjectDir "spec.json"
  if (-not (Test-Path -LiteralPath $specPath)) {
    Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-ReconResult ([pscustomobject]@{
      status = "BLOCKED"; reason = "kabul icin spec.json gerekli"
      version = $null; questions = @(); gcode_available = $false
    }) 2
  }
  $idx = Read-VersionsIndex $ProjectDir
  if ($null -eq $idx) {
    $bspec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
    $idx = Initialize-Versions $ProjectDir $bspec "initial import"
  }
  $cur = Get-VersionSpec $ProjectDir ([string]$idx.current)
  $okAll = $true
  foreach ($o in @($prop.ops)) {
    $vr = Test-PatchOp $cur $o
    if (-not $vr.ok) { $okAll = $false }
  }
  if (-not $okAll) {
    Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-ReconResult ([pscustomobject]@{
      status = "REJECTED"; reason = "patch validation"; version = [string]$idx.current
      questions = @(); gcode_available = $false
    }) 2
  }
  $nspec = $cur | ConvertTo-Json -Depth 12 | ConvertFrom-Json
  foreach ($o in @($prop.ops)) { $nspec = Invoke-PatchOp $nspec $o }
  $nid = New-ProjectVersion $ProjectDir ([string]$idx.current) $nspec "recon: olcekli boyutlar" $prop.ops $null $null
  $nspec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $specPath -Encoding UTF8
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  $out.version = $nid
  $out.status = "OK"
  $out | ConvertTo-Json -Depth 8
  exit 0
}
$out | ConvertTo-Json -Depth 8
exit 0
