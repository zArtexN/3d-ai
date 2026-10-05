<#
.SYNOPSIS
  Phase 9: tam otomasyon orkestratoru (text/photo/STL/OBJ/3MF/STEP/project).
.DESCRIPTION
  Giris turunu algilar, ilgili hatta yonlendirir, her asamayi
  {stage,input,output,engine,version,status,warnings,errors,artifacts,
  dependencies} ile izler, pahali asamalari checkpoint'ler, resume/retry
  destekler, dry-run raporu uretir ve PRINT_READY kapisini degerlendirir.
  Kritik bilinmeyenlerde durur (NEEDS_INPUT), hata kaydi her zaman
  {stage,engine,reason,artifact,suggested_action} icerir. Deger UYDURMAZ.
.EXAMPLE
  powershell -File engine\Invoke-Orchestrator.ps1 -Source "50x50x20 kutu" -ProjectName demo
  powershell -File engine\Invoke-Orchestrator.ps1 -Source model.stl -ProjectName demo2
  powershell -File engine\Invoke-Orchestrator.ps1 -Source "50x50x20 kutu" -ProjectName demo -DryRun
#>
param(
  [string]$Source = "",
  [string]$InputType = "auto",
  [string]$ProjectName = "",
  [string]$ProjectDir = "",
  [string]$Provider = "MOCK",
  [string]$PrinterJson = "",
  [string]$FilamentJson = "",
  [string]$ProcessJson = "",
  [string]$OrcaExe = "",
  [string]$AnswersJson = "",
  [switch]$DryRun,
  [switch]$Resume,
  [string]$RetryStage = "",
  [switch]$AllowMock
)

$ErrorActionPreference = "Stop"
$OrchEngineDir = $PSScriptRoot
$OrchRoot = Split-Path -Parent $OrchEngineDir
. (Join-Path $OrchEngineDir (Join-Path "Engines" "EngineRegistry.ps1"))
. (Join-Path $OrchEngineDir "Test-PrintReady.ps1")
. (Join-Path $OrchEngineDir "Write-OpLog.ps1")
. (Join-Path $OrchEngineDir "Get-CacheKey.ps1")
. (Join-Path $OrchEngineDir "Test-PathSafe.ps1")
. (Join-Path $OrchEngineDir "Test-SliceReadiness.ps1")
. (Join-Path $OrchEngineDir "New-PrintJob.ps1")

$OrchVersion = "9.0"

function New-StageRecord($id, $engine, $version, $deps) {
  return [pscustomobject]@{
    stage = $id; input = $null; output = $null; engine = $engine; version = $version
    status = "PENDING"; warnings = @(); errors = @(); artifacts = @()
    dependencies = @($deps); fallback_used = $null; at = $null
  }
}
function Close-Stage($rec, $status) {
  $rec.status = $status
  $rec.at = ((Get-Date).ToUniversalTime().ToString("o"))
  return $rec
}
function Add-StageError($rec, $engine, $reason, $artifact, $action) {
  $rec.errors += @([pscustomobject]@{
    stage = $rec.stage; engine = $engine; reason = $reason
    artifact = $artifact; suggested_action = $action
  })
}
function Write-Checkpoint($ckptDir, $rec) {
  New-Item -ItemType Directory -Force -Path $ckptDir | Out-Null
  $tmp = Join-Path $ckptDir ($rec.stage + ".tmp")
  $fin = Join-Path $ckptDir ($rec.stage + ".json")
  ($rec | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $tmp -Encoding UTF8
  Move-Item -LiteralPath $tmp -Destination $fin -Force
}
function Read-Checkpoint($ckptDir, $stageId) {
  $fin = Join-Path $ckptDir ($stageId + ".json")
  if (-not (Test-Path -LiteralPath $fin)) { return $null }
  try {
    $c = Get-Content -LiteralPath $fin -Raw | ConvertFrom-Json
    if ($null -eq $c -or [string]$c.stage -ne $stageId -or [string]$c.status -eq "") { return $null }
    return $c
  } catch { return $null }
}
function Test-CheckpointValid($c) {
  if ($null -eq $c) { return $false }
  if (@("OK", "SKIPPED") -notcontains [string]$c.status) { return $false }
  foreach ($a in @($c.artifacts)) {
    if ([string]$a -ne "" -and -not (Test-Path -LiteralPath ([string]$a))) { return $false }
  }
  return $true
}

function Get-InputKind($inText, $typeHint) {
  $h = ([string]$typeHint).ToLowerInvariant()
  if ($h -ne "" -and $h -ne "auto") {
    if (@("text", "image", "stl", "obj", "3mf", "step", "project") -contains $h) { return $h }
    return "unsupported"
  }
  if ((Test-Path -LiteralPath ([string]$inText)) -and (-not (([string]$inText).Trim().Contains("`n")))) {
    $ext = ([System.IO.Path]::GetExtension([string]$inText)).ToLowerInvariant()
    if (@(".png", ".jpg", ".jpeg", ".bmp", ".webp") -contains $ext) { return "image" }
    if ($ext -eq ".stl") { return "stl" }
    if ($ext -eq ".obj") { return "obj" }
    if ($ext -eq ".3mf") { return "3mf" }
    if (@(".step", ".stp") -contains $ext) { return "step" }
    if (@(".txt", ".md") -contains $ext) { return "textfile" }
    if ((Get-Item -LiteralPath ([string]$inText) -ErrorAction SilentlyContinue).PSIsContainer) {
      $oj = Join-Path ([string]$inText) "orchestration.json"
      if (Test-Path -LiteralPath $oj) { return "project" }
      $imgs = Get-ChildItem -LiteralPath ([string]$inText) -File -ErrorAction SilentlyContinue |
        Where-Object { @(".png", ".jpg", ".jpeg", ".bmp", ".webp") -contains ([System.IO.Path]::GetExtension($_.Name)).ToLowerInvariant() }
      if (@($imgs).Count -gt 0) { return "image" }
      return "project"
    }
    return "unsupported"
  }
  if (-not [string]::IsNullOrWhiteSpace([string]$inText)) { return "text" }
  return "unsupported"
}

function Get-OrchPlan($kind) {
  $tail = @("mesh_qa", "repair", "measure", "printability", "orientation",
            "support", "readiness", "slice", "output_verify", "gate")
  if ($kind -eq "text" -or $kind -eq "textfile") { return (@("detect", "design") + $tail) }
  if ($kind -eq "image") { return (@("detect", "reconstruct") + $tail) }
  if (@("stl", "obj", "3mf") -contains $kind) { return (@("detect", "import_mesh") + $tail) }
  if ($kind -eq "step") { return (@("detect", "cad_import") + $tail) }
  if ($kind -eq "project") { return (@("detect", "resume_load") + $tail) }
  return @("detect")
}

function Get-StageEngine($stageId, $registry) {
  $map = @{
    design = "pipeline"; import_mesh = "copy"; reconstruct = "airecon"
    cad_import = "freecad"; mesh_qa = "trimesh"; repair = "trimesh"
    measure = "trimesh"; printability = "analyzer"; orientation = "trimesh"
    support = "analyzer"; readiness = "gate"; slice = "orcaslicer"
    output_verify = "gate"; gate = "gate"; detect = "router"; resume_load = "router"
  }
  return [string]$map[$stageId]
}

function Select-StageEngine($stageId, $primary, $fallbacks, $healthFn) {
  $h = & $healthFn $primary
  if ([string]$h.status -eq "READY") {
    return @{ engine = $primary; fallback_used = $null; error = "" }
  }
  foreach ($fb in @($fallbacks)) {
    if ([string]$fb.allow -ne "always" -and [string]$fb.allow -ne "mock-ok") { continue }
    $fh = & $healthFn ([string]$fb.engine)
    if ([string]$fh.status -eq "READY" -or [string]$fb.engine -eq "mock") {
      return @{ engine = [string]$fb.engine; fallback_used = [string]$fb.engine; error = "" }
    }
  }
  return @{ engine = $primary; fallback_used = $null; error = ([string]$h.status + ": " + [string]$h.reason) }
}

function Get-RegistryHealth($registry, $id) {
  if ($id -eq "pipeline" -or $id -eq "copy" -or $id -eq "router" -or $id -eq "gate" -or $id -eq "analyzer") {
    return @{ status = "READY"; reason = "built-in" }
  }
  if ($id -eq "mock") { return @{ status = "READY"; reason = "test-only mock" } }
  if ($id -eq "airecon" -or $id -eq "freecad") {
    return @{ status = "NOT_READY"; reason = ("engine kaydedilmedi/kurulu degil: " + $id) }
  }
  try { return (Get-EngineHealth $registry $id) }
  catch { return @{ status = "NOT_READY"; reason = [string]$_.Exception.Message } }
}

$script:ctx = @{}

function Invoke-Stage-detect {
  $rec = New-StageRecord "detect" "router" $OrchVersion @()
  $rec.input = $script:ctx.Input
  $kind = Get-InputKind $script:ctx.Input $script:ctx.InputType
  $rec.output = $kind
  if ($kind -eq "unsupported") {
    Add-StageError $rec "router" ("desteklenmeyen giris turu: '" + [string]$script:ctx.Input + "'") $null "text, image (png/jpg), STL, OBJ, 3MF, STEP veya proje klasoru verin"
    return (Close-Stage $rec "FAILED")
  }
  if (@("image", "stl", "obj", "3mf", "step", "textfile") -contains $kind) {
    if (-not (Test-Path -LiteralPath ([string]$script:ctx.Input))) {
      Add-StageError $rec "router" ("giris dosyasi bulunamadi: " + [string]$script:ctx.Input) $null "dosya yolunu kontrol edin"
      return (Close-Stage $rec "FAILED")
    }
  }
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-design {
  $rec = New-StageRecord "design" "pipeline" "v1.2" @("detect")
  $rec.input = $script:ctx.Input
  $pd = $script:ctx.ProjectDir
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $script:ctx.EngineDir "Invoke-Pipeline.ps1"),
    "-Prompt", [string]$script:ctx.PromptText, "-ProjectName", [string]$script:ctx.ProjectName,
    "-Provider", [string]$script:ctx.Provider, "-NonInteractive")
  if ([string]$script:ctx.AnswersJson -ne "") { $args += @("-AnswersJson", [string]$script:ctx.AnswersJson) }
  $code = 0
  try { & powershell $args 2>&1 | Out-Null; $code = $LASTEXITCODE }
  catch { $code = 99 }
  $rp = Join-Path $pd "pipeline-result.json"
  if (-not (Test-Path -LiteralPath $rp)) {
    Add-StageError $rec "pipeline" ("pipeline sonucu uretilemedi (exit=" + $code + ")") $null "prompt'u ve engine loglarini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  try { $res = Get-Content -LiteralPath $rp -Raw | ConvertFrom-Json }
  catch {
    Add-StageError $rec "pipeline" "pipeline-result.json okunamadi (bozuk cikti)" $rp "hatti tekrar calistirin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.artifacts += @($rp)
  $sp = Join-Path $pd "spec.json"
  if (Test-Path -LiteralPath $sp) { $rec.artifacts += @($sp) }
  $mesh = Find-ProjectMesh $pd
  if ($null -ne $mesh) { $rec.artifacts += @($mesh); $script:ctx.MeshPath = $mesh }
  $script:ctx.SpecPath = $(if (Test-Path -LiteralPath $sp) { $sp } else { "" })
  $st = [string]$res.status
  if ($st -eq "NEEDS_INPUT") {
    $rec.output = "NEEDS_INPUT"
    $script:ctx.Questions = @($res.questions)
    foreach ($q in @($res.questions)) {
      $rec.warnings += @("soru: " + [string]$q.question_id + " - " + [string]$q.question)
    }
    return (Close-Stage $rec "NEEDS_INPUT")
  }
  if ($st -eq "PASS" -or $st -eq "WARNING") {
    $rec.output = $st
    if ($st -eq "WARNING") { $rec.warnings += @("pipeline WARNING ile gecti") }
    if ($null -eq $mesh) {
      Add-StageError $rec "pipeline" "pipeline gecti ama mesh uretilmedi" $rp "geometry engine ciktisini kontrol edin"
      return (Close-Stage $rec "FAILED")
    }
    return (Close-Stage $rec "OK")
  }
  Add-StageError $rec "pipeline" ("pipeline durumu: " + $st + " - " + [string]$res.reason) $rp "validation dosyalarini ve loglari inceleyin"
  return (Close-Stage $rec "FAILED")
}

function Find-ProjectMesh($pd) {
  $od = Join-Path $pd "output"
  $cands = @()
  foreach ($c in @((Join-Path $pd "model.stl"), (Join-Path $od "model.stl"))) {
    if (Test-Path -LiteralPath $c) { $cands += @($c) }
  }
  if (Test-Path -LiteralPath $od) {
    $files = Get-ChildItem -LiteralPath $od -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq ".stl" -or $_.Extension -eq ".3mf" }
    $stls = @($files | Where-Object { $_.Extension -eq ".stl" })
    if (@($stls).Count -gt 0) { $cands += @($stls[0].FullName) }
    else {
      $m3 = @($files | Where-Object { $_.Extension -eq ".3mf" })
      if (@($m3).Count -gt 0) { $cands += @($m3[0].FullName) }
    }
  }
  if (@($cands).Count -gt 0) { return [string]$cands[0] }
  return $null
}

function Get-MeshDims($meshPath) {
  # Donus: @{ ok, watertight, faces, dims[], reason }. STL -> saf PS analizor;
  # 3MF/OBJ -> trimesh (Stl parametre adiyla).
  $ext = ([System.IO.Path]::GetExtension([string]$meshPath)).ToLowerInvariant()
  if ($ext -eq ".stl") {
    try {
      $jo = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:ctx.EngineDir "Get-MeshQuality.ps1") `
        -StlFile ([string]$meshPath) -AsJson 2>&1 | Out-String
      $q = $jo | ConvertFrom-Json
    } catch { return @{ ok = $false; reason = ("STL analiz calismadi: " + $_.Exception.Message) } }
    if ($null -eq $q -or $null -eq $q.bbox_size_mm) {
      return @{ ok = $false; reason = "STL analiz cikti uretmedi" }
    }
    return @{ ok = $true; watertight = ([bool]$q.watertight); faces = [int]$q.triangle_count;
              dims = @([double]$q.bbox_size_mm[0], [double]$q.bbox_size_mm[1], [double]$q.bbox_size_mm[2]); reason = "" }
  }
  try {
    $ad = Get-TrimeshAdapter; . $ad
    $q = Trimesh-Invoke "Analyze" @{ Stl = ([string]$meshPath) }
  } catch { return @{ ok = $false; reason = ("mesh analiz calismadi: " + $_.Exception.Message) } }
  if ($null -eq $q -or [string]$q.status -ne "OK") {
    $why = "mesh analizi basarisiz"
    if ($null -ne $q -and [string]$q.reason -ne "") { $why = [string]$q.reason }
    return @{ ok = $false; reason = $why }
  }
  $d = @(([double]$q.bbox_max[0] - [double]$q.bbox_min[0]),
         ([double]$q.bbox_max[1] - [double]$q.bbox_min[1]),
         ([double]$q.bbox_max[2] - [double]$q.bbox_min[2]))
  return @{ ok = $true; watertight = ([bool]$q.watertight); faces = [int]$q.faces; dims = $d; reason = "" }
}

function Invoke-Stage-import_mesh {
  $rec = New-StageRecord "import_mesh" "copy" $OrchVersion @("detect")
  $src = [string]$script:ctx.Input
  $rec.input = $src
  $id = Join-Path $script:ctx.ProjectDir "input"
  New-Item -ItemType Directory -Force -Path $id | Out-Null
  $dst = Join-Path $id ([System.IO.Path]::GetFileName($src))
  try { Copy-Item -LiteralPath $src -Destination $dst -Force }
  catch {
    Add-StageError $rec "copy" ("dosya kopyalanamadi: " + $_.Exception.Message) $src "dosya izinlerini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.artifacts += @($dst)
  $rec.output = $dst
  $script:ctx.MeshPath = $dst
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-reconstruct {
  $rec = New-StageRecord "reconstruct" "airecon" $OrchVersion @("detect")
  $rec.input = $script:ctx.Input
  $sel = Select-StageEngine "reconstruct" "airecon" @(@{ engine = "mock"; allow = "mock-ok" }) {
    param($e) Get-RegistryHealth $script:ctx.Registry $e
  }
  if ([string]$sel.error -ne "" -and $null -eq $sel.fallback_used) {
    Add-StageError $rec "airecon" ("reconstruction motoru hazir degil (" + $sel.error + "); gercek AI motoru bu makinede yok" ) $null "foto ile uretim icin TRELLIS/TripoSR kurun veya -AllowMock ile test akisini kullanin"
    return (Close-Stage $rec "FAILED")
  }
  if ($sel.fallback_used -eq "mock" -and -not $script:ctx.AllowMock) {
    Add-StageError $rec "mock" "mock motor test-disidir (-AllowMock sart)" $null "test icin -AllowMock verin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.engine = [string]$sel.engine
  $rec.fallback_used = $sel.fallback_used
  $pd = $script:ctx.ProjectDir
  $imgFiles = @()
  if ((Get-Item -LiteralPath ([string]$script:ctx.Input) -ErrorAction SilentlyContinue).PSIsContainer) {
    $imgFiles = @(Get-ChildItem -LiteralPath ([string]$script:ctx.Input) -File -ErrorAction SilentlyContinue |
      Where-Object { @(".png", ".jpg", ".jpeg", ".bmp", ".webp") -contains ([System.IO.Path]::GetExtension($_.Name)).ToLowerInvariant() } |
      ForEach-Object { $_.FullName })
  } else { $imgFiles = @([string]$script:ctx.Input) }
  $rec.input = ($imgFiles -join ";")
  $code = 0
  try {
    $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $script:ctx.EngineDir "Invoke-Reconstruction.ps1") `
      -ProjectDir $pd -ImageFiles $imgFiles -EngineId "mock" -AllowMock 2>&1 | Out-String
    $code = $LASTEXITCODE
    $rj = $out | ConvertFrom-Json
  } catch { $code = 99; $rj = $null }
  if ($code -ne 0 -or $null -eq $rj -or [string]$rj.status -eq "BLOCKED") {
    $why = "aday mesh uretilemedi"
    if ($null -ne $rj -and [string]$rj.reason -ne "") { $why = [string]$rj.reason }
    Add-StageError $rec "mock" $why $null "goruntu setini ve olcegi kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $mesh = [string]$rj.candidate_mesh
  if ($mesh -eq "" -or -not (Test-Path -LiteralPath $mesh)) {
    Add-StageError $rec "mock" "aday mesh yolu gecersiz" $null "reconstruction ciktisini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.artifacts += @($mesh)
  $rec.output = $mesh
  $script:ctx.MeshPath = $mesh
  $rec.warnings += @("mock motor: geometri gercek goruntu iceriginden TURETILMEDI (test akisi)")
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-cad_import {
  $rec = New-StageRecord "cad_import" "freecad" $OrchVersion @("detect")
  $rec.input = $script:ctx.Input
  $resolver = Join-Path $script:ctx.Root (Join-Path "scripts" "Resolve-FreeCad.ps1")
  $exe = ""
  try {
    if (Test-Path -LiteralPath $resolver) {
      $f = & $resolver 2>$null | Select-Object -Last 1
      if ($f -and (Test-Path -LiteralPath ([string]$f))) { $exe = [string]$f }
    }
  } catch { }
  if ($exe -eq "") {
    Add-StageError $rec "freecad" "STEP import motoru bulunamadi (FreeCAD/OCCT bu makinede kurulu degil)" ([string]$script:ctx.Input) "FreeCAD kurun veya STEP'i harici CAD'de STL/3MF'e cevirip mesh hatti kullanin"
    return (Close-Stage $rec "FAILED")
  }
  Add-StageError $rec "freecad" "STEP donusturucu bagli degil (binary var ama ceviri kodu yazilmadi)" $exe "STEP->mesh cevirici implementasyonu gerekli"
  return (Close-Stage $rec "FAILED")
}

function Invoke-Stage-resume_load {
  $rec = New-StageRecord "resume_load" "router" $OrchVersion @("detect")
  $rec.input = $script:ctx.Input
  $oj = Join-Path ([string]$script:ctx.Input) "orchestration.json"
  if (Test-Path -LiteralPath $oj) {
    $rec.artifacts += @($oj)
    $rec.output = "onceki plan yuklendi"
  } else {
    $rec.output = "onceki kayit yok (sifirdan)"
    $rec.warnings += @("orchestration.json bulunamadi; plan bastan kosacak")
  }
  $m = Find-ProjectMesh ([string]$script:ctx.ProjectDir)
  if ($null -ne $m) { $script:ctx.MeshPath = $m; $rec.artifacts += @($m) }
  return (Close-Stage $rec "OK")
}

function Get-TrimeshAdapter {
  $ad = Join-Path $script:ctx.EngineDir (Join-Path "Engines" (Join-Path "adapters" "TrimeshAdapter.ps1"))
  if (-not (Test-Path -LiteralPath $ad)) { return "" }
  return $ad
}

function Invoke-Stage-mesh_qa {
  $rec = New-StageRecord "mesh_qa" "mesh-analyzer" $OrchVersion @("mesh-source")
  $rec.input = $script:ctx.MeshPath
  $cacheFile = Join-Path $script:ctx.ProjectDir (Join-Path ".cache" "meshqa.json")
  $ckey = Get-CacheKey ([string]$script:ctx.MeshPath) "mesh-analyzer" $OrchVersion "" ""
  try {
    if (Test-Path -LiteralPath $cacheFile) {
      $cc = Get-Content -LiteralPath $cacheFile -Raw | ConvertFrom-Json
      if ([string]$cc.key -eq $ckey -and $null -ne $cc.result) {
        $r = $cc.result
        $script:ctx.MeshQuality = [pscustomobject]@{ watertight = [bool]$r.watertight; faces = [int]$r.faces }
        $script:ctx.MeasuredDims = @($r.dims)
        $rec.output = ("watertight=" + [string]$r.watertight + " faces=" + [string]$r.faces + " (cache)")
        if ([bool]$r.watertight -ne $true) { $rec.warnings += @("mesh watertight degil -> repair asamasina gidiyor") }
        return (Close-Stage $rec "OK")
      }
    }
  } catch { }
  $r = Get-MeshDims ([string]$script:ctx.MeshPath)
  if (-not [bool]$r.ok) {
    Add-StageError $rec "mesh-analyzer" ([string]$r.reason) ([string]$script:ctx.MeshPath) "mesh dosyasinin gecerli STL/3MF/OBJ oldugunu dogrulayin"
    return (Close-Stage $rec "FAILED")
  }
  $script:ctx.MeshQuality = [pscustomobject]@{ watertight = [bool]$r.watertight; faces = [int]$r.faces }
  $script:ctx.MeasuredDims = @($r.dims)
  try {
    $cd = Split-Path -Parent $cacheFile
    New-Item -ItemType Directory -Force -Path $cd | Out-Null
    [pscustomobject]@{ key = $ckey; result = $r } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $cacheFile -Encoding UTF8
  } catch { }
  $rec.output = ("watertight=" + [string]$r.watertight + " faces=" + [string]$r.faces)
  if ([bool]$r.watertight -ne $true) { $rec.warnings += @("mesh watertight degil -> repair asamasina gidiyor") }
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-repair {
  $rec = New-StageRecord "repair" "trimesh" $OrchVersion @("mesh_qa")
  $rec.input = $script:ctx.MeshPath
  $q = $script:ctx.MeshQuality
  if ($null -ne $q -and [bool]$q.watertight -eq $true) {
    $rec.output = "no-op (watertight)"
    $script:ctx.RepairedMesh = [string]$script:ctx.MeshPath
    return (Close-Stage $rec "SKIPPED")
  }
  $pyRoot = $script:ctx.ExternalRoot
  $py = Join-Path $pyRoot (Join-Path "envs" (Join-Path "python312" "python.exe"))
  $fix = Join-Path $pyRoot (Join-Path "envs" "repair_mesh.py")
  if (-not (Test-Path -LiteralPath $py) -or -not (Test-Path -LiteralPath $fix)) {
    Add-StageError $rec "trimesh" "onarim araci yok (python312 veya repair_mesh.py bulunamadi)" ([string]$script:ctx.MeshPath) "3D-AI-External env kurulumunu kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $out = Join-Path $script:ctx.ProjectDir "repaired.stl"
  try { $ro = & $py $fix ([string]$script:ctx.MeshPath) $out 2>&1 | Out-String }
  catch {
    Add-StageError $rec "trimesh" ("onarim calismadi: " + $_.Exception.Message) ([string]$script:ctx.MeshPath) "env python + trimesh kurulumunu kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  if (-not (Test-Path -LiteralPath $out)) {
    Add-StageError $rec "trimesh" "onarim cikti uretmedi" ([string]$script:ctx.MeshPath) "giris mesh'inin okunabilir oldugunu dogrulayin"
    return (Close-Stage $rec "FAILED")
  }
  $before = 0; $after = 0
  try {
    $rj = $ro | ConvertFrom-Json
    if ($null -ne $rj.faces) { $after = [int]$rj.faces }
  } catch { }
  try {
    $qa = Get-MeshDims ([string]$script:ctx.MeshPath)
    $qb = Get-MeshDims $out
    if ([bool]$qa.ok) { $before = [int]$qa.faces }
    if ([bool]$qb.ok) {
      $after = [int]$qb.faces
      $script:ctx.MeshQuality = [pscustomobject]@{ watertight = [bool]$qb.watertight; faces = [int]$qb.faces }
      $script:ctx.MeasuredDims = @($qb.dims)
    }
  } catch { }
  if ($before -gt 0 -and $after -lt $before) {
    Add-StageError $rec "trimesh" ("onarim GUvensiz: yuzey kaybi " + $before + " -> " + $after + " (silme politikasi ihlali)") $out "mesh'i harici CAD'de duzeltin; otomatik onarim durduruldu"
    return (Close-Stage $rec "UNSAFE")
  }
  $rec.artifacts += @($out)
  $rec.output = $out
  $script:ctx.RepairedMesh = $out
  $script:ctx.MeshPath = $out
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-measure {
  $rec = New-StageRecord "measure" "mesh-analyzer" $OrchVersion @("repair")
  $rec.input = $script:ctx.MeshPath
  $d = $script:ctx.MeasuredDims
  if ($null -eq $d -or @($d).Count -lt 3) {
    $r = Get-MeshDims ([string]$script:ctx.MeshPath)
    if (-not [bool]$r.ok) {
      Add-StageError $rec "mesh-analyzer" ([string]$r.reason) ([string]$script:ctx.MeshPath) "mesh gecerliligini dogrulayin"
      return (Close-Stage $rec "FAILED")
    }
    $script:ctx.MeasuredDims = @($r.dims)
    $d = @($r.dims)
  }
  $rec.output = ("dims=" + ((@($d) | ForEach-Object { [string]$_ }) -join "x"))
  return (Close-Stage $rec "OK")
}

function Get-PrintSpec($pd) {
  if ([string]$script:ctx.SpecPath -ne "" -and (Test-Path -LiteralPath ([string]$script:ctx.SpecPath))) {
    return [string]$script:ctx.SpecPath
  }
  $d = $script:ctx.MeasuredDims
  if ($null -eq $d -or @($d).Count -lt 3) { return "" }
  $mp = Join-Path $pd "measured-spec.json"
  [pscustomobject]@{
    source = "measured (mesh olcumunden, uydurma degil)"
    components = @([pscustomobject]@{
      id = "body"
      base = [pscustomobject]@{ shape = "box"; width_mm = [double]$d[0]; depth_mm = [double]$d[1]; height_mm = [double]$d[2] }
    })
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $mp -Encoding UTF8
  return $mp
}

function Invoke-Stage-printability {
  $rec = New-StageRecord "printability" "analyzer" $OrchVersion @("measure")
  $pd = $script:ctx.ProjectDir
  $spec = Get-PrintSpec $pd
  if ($spec -eq "") {
    Add-StageError $rec "analyzer" "analiz girdisi yok (spec + olcum uretilemedi)" $null "onceki asama ciktilarini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.input = $spec
  $pf = [string]$script:ctx.PrinterJson
  $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
    (Join-Path $script:ctx.EngineDir "Analyze-Printability.ps1"),
    "-SpecFile", $spec, "-AsJson")
  if ($pf -ne "" -and (Test-Path -LiteralPath $pf)) { $args += @("-PrinterFile", $pf) }
  try {
    $jo = & powershell $args 2>&1 | Out-String
    $pa = $jo | ConvertFrom-Json
  } catch {
    Add-StageError $rec "analyzer" ("printability calismadi: " + $_.Exception.Message) $spec "spec formatini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  if ($null -eq $pa) {
    Add-StageError $rec "analyzer" "printability cikti uretmedi" $spec "analyzer loglarini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $pp = Join-Path $pd "printability.json"
  ($pa | ConvertTo-Json -Depth 8) | Set-Content -LiteralPath $pp -Encoding UTF8
  $rec.artifacts += @($pp)
  $script:ctx.Printability = $pa
  $fails = @(@($pa.checks) | Where-Object { [string]$_.status -eq "FAIL" })
  if (@($fails).Count -gt 0 -and $null -ne $fails) {
    $n = @($fails).Count
    Add-StageError $rec "analyzer" ("printability " + $n + " FAIL: " + ((@($fails) | ForEach-Object { [string]$_.id }) -join ",")) $pp "FAIL check detaylarini duzeltin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.output = ("status=" + [string]$pa.status)
  $ni = 0
  try { $ni = [int]$pa.summary.needs_input } catch { }
  if ($ni -gt 0) { $rec.warnings += @($ni.ToString() + " NEEDS_INPUT check (duvar/malzeme bilinmiyor)") }
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-orientation {
  $rec = New-StageRecord "orientation" "trimesh" $OrchVersion @("printability")
  $rec.input = $script:ctx.MeshPath
  $pyRoot = $script:ctx.ExternalRoot
  $py = Join-Path $pyRoot (Join-Path "envs" (Join-Path "python312" "python.exe"))
  $tool = Join-Path $pyRoot (Join-Path "envs" "orient_mesh.py")
  if (-not (Test-Path -LiteralPath $py) -or -not (Test-Path -LiteralPath $tool)) {
    Add-StageError $rec "trimesh" "oryantasyon araci yok (python312 veya orient_mesh.py bulunamadi)" ([string]$script:ctx.MeshPath) "3D-AI-External env kurulumunu kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $out = Join-Path $script:ctx.ProjectDir "oriented.stl"
  try { $oo = & $py $tool ([string]$script:ctx.MeshPath) $out 2>&1 | Out-String }
  catch {
    Add-StageError $rec "trimesh" ("oryantasyon calismadi: " + $_.Exception.Message) ([string]$script:ctx.MeshPath) "env python + trimesh kurulumunu kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  try { $oj = $oo | ConvertFrom-Json }
  catch {
    Add-StageError $rec "trimesh" "oryantasyon cikti uretmedi" ([string]$script:ctx.MeshPath) "arac ciktisini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  if (-not [bool]$oj.ok) {
    Add-StageError $rec "trimesh" "oryantasyon basarisiz" ([string]$script:ctx.MeshPath) "mesh gecerliligini dogrulayin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.artifacts += @($out)
  $rec.output = ("rotation=" + (($oj.rotation_deg | ForEach-Object { [string]$_ }) -join ","))
  $script:ctx.OrientedMesh = $out
  $script:ctx.MeshPath = $out
  $script:ctx.Orientation = $oj
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-support {
  $rec = New-StageRecord "support" "analyzer" $OrchVersion @("orientation")
  $pa = $script:ctx.Printability
  $need = $false; $why = "overhang/support bulgusu yok"
  if ($null -ne $pa) {
    $hits = @(@($pa.checks) | Where-Object {
      ([string]$_.id -match "overhang|support") -and ([string]$_.status -ne "PASS")
    })
    if (@($hits).Count -gt 0) {
      $need = $true
      $why = ((@($hits) | ForEach-Object { [string]$_.id + ":" + [string]$_.status }) -join "; ")
    }
  }
  $sp = Join-Path $script:ctx.ProjectDir "support.json"
  [pscustomobject]@{
    needed = $need; reason = $why; source = "printability checks (slicer-side, geometri degismez)"
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $sp -Encoding UTF8
  $rec.artifacts += @($sp)
  $rec.output = ("needed=" + [string]$need)
  $script:ctx.Support = [pscustomobject]@{ needed = $need; reason = $why }
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-readiness {
  $rec = New-StageRecord "readiness" "gate" $OrchVersion @("support")
  $r = Test-SliceReadiness -ModelStl ([string]$script:ctx.MeshPath) `
    -PrinterJson ([string]$script:ctx.PrinterJson) -FilamentJson ([string]$script:ctx.FilamentJson) `
    -ProcessJson ([string]$script:ctx.ProcessJson) -OrcaExe ([string]$script:ctx.OrcaExe)
  $rec.output = [string]$r.status
  $script:ctx.Readiness = $r
  foreach ($m in @($r.missing)) { $rec.warnings += @("eksik: " + [string]$m.id + " - " + [string]$m.message) }
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-slice {
  $rec = New-StageRecord "slice" "orcaslicer" $OrchVersion @("readiness")
  $r = $script:ctx.Readiness
  if ($null -eq $r -or [string]$r.status -ne "READY") {
    $rec.output = "skipped (gate kapali)"
    return (Close-Stage $rec "SKIPPED")
  }
  try {
    $ad = Join-Path $script:ctx.EngineDir (Join-Path "Engines" (Join-Path "adapters" "OrcaSlicerAdapter.ps1"))
    . $ad
    $od = Join-Path $script:ctx.ProjectDir "slice"
    New-Item -ItemType Directory -Force -Path $od | Out-Null
    $s = Orca-Invoke "Slice" @{ Model = ([string]$script:ctx.MeshPath); OutDir = $od }
  } catch {
    Add-StageError $rec "orcaslicer" ("slice calismadi: " + $_.Exception.Message) ([string]$script:ctx.MeshPath) "orca binary + profil eslesmesini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  if ($null -eq $s -or [string]$s.status -ne "OK" -or [string]$s.gcode -eq "" -or -not (Test-Path -LiteralPath ([string]$s.gcode))) {
    $why = "slice basarisiz"
    if ($null -ne $s -and [string]$s.reason -ne "") { $why = [string]$s.reason }
    Add-StageError $rec "orcaslicer" $why ([string]$script:ctx.MeshPath) "orca loglarini ve profil adlarini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.artifacts += @([string]$s.gcode)
  $rec.output = [string]$s.gcode
  $script:ctx.Gcode = [string]$s.gcode
  return (Close-Stage $rec "OK")
}

function Invoke-Stage-output_verify {
  $rec = New-StageRecord "output_verify" "gate" $OrchVersion @("slice")
  if ([string]$script:ctx.Gcode -eq "") {
    $rec.output = "skipped (gcode yok)"
    return (Close-Stage $rec "SKIPPED")
  }
  $v = Test-SliceOutput -GcodePath ([string]$script:ctx.Gcode)
  $script:ctx.OutputVerify = $v
  if ([string]$v.status -ne "OK") {
    Add-StageError $rec "gate" ("cikti dogrulama FAIL: " + (($v.errors | ForEach-Object { [string]$_ }) -join "; ")) ([string]$script:ctx.Gcode) "slice ciktisini ve disk alanini kontrol edin"
    return (Close-Stage $rec "FAILED")
  }
  $rec.output = "OK"
  return (Close-Stage $rec "OK")
}

function Get-StageById($stages, $id) {
  foreach ($s in @($stages)) { if ([string]$s.stage -eq $id) { return $s } }
  return $null
}

function Invoke-Stage-gate {
  $rec = New-StageRecord "gate" "gate" $OrchVersion @("output_verify")
  $stages = $script:ctx.Stages
  $ev = Test-PrintReady $stages ([string]$script:ctx.MeshPath) $script:ctx.MeshQuality $script:ctx.Readiness
  if ([string]$ev.verdict -eq "PRINT_READY") { $rec.output = "PRINT_READY" } else { $rec.output = "NOT_PRINT_READY" }
  foreach ($rs in @($ev.reasons)) { $rec.warnings += @([string]$rs) }
  $script:ctx.GateReasons = @($ev.reasons)
  if ([string]$ev.verdict -eq "PRINT_READY") { return (Close-Stage $rec "OK") }
  return (Close-Stage $rec "BLOCKED")
}

function Get-DryRunReport($kind, $plan, $registry) {
  $engs = @(); $reqs = @(); $miss = @(); $arts = @()
  $seen = @{}
  foreach ($sid in @($plan)) {
    $e = Get-StageEngine $sid $registry
    if (-not $seen.ContainsKey($e)) {
      $seen[$e] = $true
      $h = Get-RegistryHealth $registry $e
      $engs += @([pscustomobject]@{ engine = $e; status = [string]$h.status; reason = [string]$h.reason })
      if ([string]$h.status -ne "READY") {
        $reqs += @($e + ": " + [string]$h.reason)
      }
    }
  }
  if ($kind -eq "text" -or $kind -eq "textfile") {
    $arts += @("spec.json", "output/*.stl", "pipeline-result.json")
  } elseif ($kind -eq "image") {
    $miss += @("reconstruction engine (gercek AI yok; -AllowMock ile test akisi)")
    $arts += @("candidates/*/candidate.stl")
  } elseif ($kind -eq "step") {
    $miss += @("STEP import motoru (FreeCAD/OCCT yok)")
  }
  if ([string]$script:ctx.PrinterJson -eq "") { $miss += @("printer profili secilmemis") }
  if ([string]$script:ctx.FilamentJson -eq "") { $miss += @("filament profili secilmemis") }
  if ([string]$script:ctx.ProcessJson -eq "") { $miss += @("process profili secilmemis") }
  $arts += @("printability.json", "oriented.stl", "support.json", "jobs/<id>/job.json", "slice/*.gcode (gate aciksa)")
  return [pscustomobject]@{
    dry_run = $true; input_kind = $kind; stages = @($plan); engines = $engs
    requirements = @($reqs); missing_data = @($miss); expected_artifacts = @($arts)
  }
}

# ---------------- ana akis ----------------
$script:ctx = @{
  Input = $Source; InputType = $InputType; ProjectName = $ProjectName; ProjectDir = $ProjectDir
  Provider = $Provider; PrinterJson = $PrinterJson; FilamentJson = $FilamentJson
  ProcessJson = $ProcessJson; OrcaExe = $OrcaExe; AnswersJson = $AnswersJson
  AllowMock = [bool]$AllowMock; EngineDir = $OrchEngineDir; Root = $OrchRoot
  ExternalRoot = (Get-ExternalRoot); Registry = (Get-EngineRegistry)
  PromptText = ""; MeshPath = ""; SpecPath = ""; MeshQuality = $null; MeasuredDims = $null
  RepairedMesh = ""; OrientedMesh = ""; Orientation = $null; Support = $null
  Printability = $null; Readiness = $null; Gcode = ""; OutputVerify = $null
  GateReasons = @(); Questions = @(); Stages = @()
}

$detKind = Get-InputKind $Source $InputType
$plan = Get-OrchPlan $detKind

if ($detKind -eq "project" -and (Test-Path -LiteralPath ([string]$Source))) {
  $oj = Join-Path ([string]$Source) "orchestration.json"
  if (Test-Path -LiteralPath $oj) {
    try {
      $prev = Get-Content -LiteralPath $oj -Raw | ConvertFrom-Json
      if ($null -ne $prev.plan -and @($prev.plan).Count -gt 0) { $plan = @($prev.plan) }
    } catch { }
  }
}

if ($DryRun) {
  $rep = Get-DryRunReport $detKind $plan $script:ctx.Registry
  $rep | ConvertTo-Json -Depth 8
  exit 0
}

if ([string]$ProjectName -eq "" -and [string]$ProjectDir -eq "") {
  Write-Output '{"status":"FAILED","reason":"ProjectName veya ProjectDir zorunlu (dry-run haric)"}'
  exit 2
}
$pdir = $ProjectDir
if ($pdir -eq "" -and [string]$ProjectName -ne "") {
  $projRoot = Join-Path $OrchRoot "projects"
  $ps = Test-PathSafe $projRoot ([string]$ProjectName)
  if (-not [bool]$ps.ok) {
    Write-Output '{"status":"FAILED","reason":"proje adi kok disina cikiyor (path traversal engellendi)"}'
    exit 2
  }
}
if ($pdir -eq "" -and $detKind -eq "project" -and (Test-Path -LiteralPath ([string]$Source))) {
  $pdir = [string]$Source
}
if ($pdir -eq "") {
  $pdir = "projects"
  if (-not [System.IO.Path]::IsPathRooted($pdir)) { $pdir = Join-Path $OrchRoot $pdir }
  $pdir = Join-Path $pdir $ProjectName
}
$script:ctx.ProjectDir = $pdir
New-Item -ItemType Directory -Force -Path $pdir | Out-Null
$ckptDir = Join-Path $pdir "checkpoints"

if ($detKind -eq "text") { $script:ctx.PromptText = [string]$Source }
elseif ($detKind -eq "textfile") { $script:ctx.PromptText = (Get-Content -LiteralPath ([string]$Source) -Raw) }

$useResume = [bool]$Resume -or [string]$RetryStage -ne ""
if ([string]$RetryStage -ne "") {
  # Retry: hedef asama + sonrasinin checkpoint'lerini sil, oncesini cache'den al.
  $drop = $false
  foreach ($sid in @($plan)) {
    if ($sid -eq $RetryStage) { $drop = $true }
    if ($drop) {
      $cf = Join-Path $ckptDir ($sid + ".json")
      if (Test-Path -LiteralPath $cf) { Remove-Item -LiteralPath $cf -Force -ErrorAction SilentlyContinue }
    }
  }
}
$stages = New-Object System.Collections.ArrayList
$stopEarly = $false
foreach ($sid in @($plan)) {
  if ($useResume) {
    $c = Read-Checkpoint $ckptDir $sid
    if (Test-CheckpointValid $c) {
      $cr = New-StageRecord $sid ([string]$c.engine) ([string]$c.version) @($c.dependencies)
      $cr.input = $c.input; $cr.output = $c.output; $cr.warnings = @($c.warnings)
      $cr.artifacts = @($c.artifacts); $cr.fallback_used = $c.fallback_used
      $cr = Close-Stage $cr "CACHED"
      $stages.Add($cr) | Out-Null
      foreach ($a in @($c.artifacts)) {
        $as = [string]$a
        if ($as -match "\.stl$|\.3mf$") { $script:ctx.MeshPath = $as }
        if ($as -match "spec\.json$") { $script:ctx.SpecPath = $as }
      }
      if ($sid -eq "slice") {
        foreach ($a in @($c.artifacts)) {
          if ([string]$a -match "\.gcode$") { $script:ctx.Gcode = [string]$a }
        }
      }
      continue
    }
  }
  $fn = "Invoke-Stage-" + $sid
  $script:ctx.Stages = @($stages.ToArray())
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  try { $rec = & $fn }
  catch {
    $rec = New-StageRecord $sid (Get-StageEngine $sid $null) $OrchVersion @()
    Add-StageError $rec "orchestrator" ("asama calismadi: " + $_.Exception.Message) $null "loglari inceleyin"
    $rec = Close-Stage $rec "FAILED"
  }
  $sw.Stop()
  try { Write-OpLog $pdir $sid ([string]$rec.engine) $sid $sw.ElapsedMilliseconds ([string]$rec.status) $(if (@($rec.errors).Count -gt 0) { [string]$rec.errors[0].reason } else { "" }) } catch { }
  $stages.Add($rec) | Out-Null
  if ($sid -eq "design" -or $sid -eq "reconstruct" -or $sid -eq "repair" -or $sid -eq "slice") {
    if (@("OK", "SKIPPED") -contains $rec.status) { Write-Checkpoint $ckptDir $rec }
  }
  if ($sid -eq "resume_load") {
    # proje girdisinde onceki plan yuklendi; mesh yolunu geri kazan
    $m = Find-ProjectMesh $pdir
    if ($null -ne $m) { $script:ctx.MeshPath = $m }
  }
  if (@("NEEDS_INPUT", "UNSAFE", "FAILED") -contains $rec.status) {
    if ($sid -ne "gate") { $stopEarly = $true; break }
  }
}
$script:ctx.Stages = @($stages.ToArray())
if ($stopEarly -and $null -eq (Get-StageById $script:ctx.Stages "gate")) {
  # Erken durusta bile kapi degerlendirilir (NOT_PRINT_READY + nedenler).
  try { $gr = Invoke-Stage-gate }
  catch {
    $gr = New-StageRecord "gate" "gate" $OrchVersion @()
    Add-StageError $gr "gate" "kapi degerlendirilemedi" $null "asama ciktilarini kontrol edin"
    $gr = Close-Stage $gr "BLOCKED"
  }
  $script:ctx.Stages = @($script:ctx.Stages + @($gr))
}

$gateRec = Get-StageById $script:ctx.Stages "gate"
$final = "FAILED"
if ($null -ne $gateRec) {
  if ([string]$gateRec.output -eq "PRINT_READY") { $final = "PRINT_READY" }
  elseif ([string]$gateRec.status -eq "BLOCKED") { $final = "NOT_PRINT_READY" }
}
$firstStop = $null
foreach ($s in @($script:ctx.Stages)) {
  if ([string]$s.status -eq "NEEDS_INPUT") { $firstStop = $s; break }
}
if ($null -ne $firstStop) { $final = "NEEDS_INPUT" }
if ($final -eq "FAILED") {
  foreach ($s in @($script:ctx.Stages)) {
    if (@("FAILED") -contains [string]$s.status) { $final = "BLOCKED"; break }
  }
}

$jobInfo = $null
try {
  $jr = New-PrintJob -ProjectDir $pdir -JobId ("orch-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")) `
    -ModelStl ([string]$script:ctx.MeshPath) -PrinterJson ([string]$PrinterJson) `
    -FilamentJson ([string]$FilamentJson) -ProcessJson ([string]$ProcessJson) -OrcaExe ([string]$OrcaExe)
  $jobInfo = [pscustomobject]@{ job_id = $jr.job_id; path = $jr.path; status = $jr.status }
} catch { $jobInfo = $null }

$out = [pscustomobject]@{
  status = $final; input_kind = $detKind; plan = @($plan)
  stages = @($script:ctx.Stages); gate_reasons = @($script:ctx.GateReasons)
  questions = @($script:ctx.Questions); print_job = $jobInfo
  gcode_available = ([string]$script:ctx.Gcode -ne "")
}
($out | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath (Join-Path $pdir "orchestration.json") -Encoding UTF8
$out | ConvertTo-Json -Depth 10
if ($final -eq "PRINT_READY") { exit 0 } else { exit 2 }
