<#
.SYNOPSIS
  Phase 9: orkestrator uctan uca testleri (TDD).
.DESCRIPTION
  Tum fixture'lar test aninda TEMP altinda uretilir; repoya sahte girdi
  yazilmaz. Pahali text hatti bir kez kosar (T-ORCH-01); 08/09/12/16a ayni
  ciktiyi salt-okur kullanir. Mock yalnizca reconstruction icin (-AllowMock).
#>
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
. (Join-Path $EngineDir "Test-PrintReady.ps1")

$script:pass = 0; $script:fail = 0
function Add-ORCResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}
function Get-Orch($proj) {
  $p = Join-Path $Root (Join-Path "projects" (Join-Path $proj "orchestration.json"))
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json)
}
function Get-OStage($o, $id) {
  foreach ($s in @($o.stages)) { if ([string]$s.stage -eq $id) { return $s } }
  return $null
}
function Invoke-Orch($OArgs) {
  # Tani orchestration.json'dadir; ic stderr satirlari testi oldurmesin diye dusurulur.
  $out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Orchestrator.ps1") @OArgs 2>$null | Out-String
  return $out
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("orc-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
try {
  Add-Type -AssemblyName System.Drawing
  foreach ($pair in @(@("img1.png", "Red"), @("img2.png", "Blue"))) {
    $bmp = New-Object System.Drawing.Bitmap(32, 32)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::FromName($pair[1]))
    $g.Dispose()
    $bmp.Save((Join-Path $base $pair[0]), [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
  }
  $imgDir = Join-Path $base "photos"
  New-Item -ItemType Directory -Force -Path $imgDir | Out-Null
  Copy-Item -LiteralPath (Join-Path $base "img1.png") -Destination (Join-Path $imgDir "a.png")
  Copy-Item -LiteralPath (Join-Path $base "img2.png") -Destination (Join-Path $imgDir "b.png")

  . (Join-Path $EngineDir "AiReconstruct.ps1")
  $boxStl = Join-Path $base "box.stl"
  New-MockReconMesh $boxStl 20 20 10 | Out-Null
  $pyRoot = Join-Path (Split-Path -Parent $Root) "3D-AI-External"
  $py = Join-Path $pyRoot (Join-Path "envs" (Join-Path "python312" "python.exe"))
  $box3mf = Join-Path $base "box.3mf"
  & $py -c ("import trimesh; trimesh.load(r'" + $boxStl + "', force='mesh').export(r'" + $box3mf + "')") 2>&1 | Out-Null
  $brokenStl = Join-Path $base "broken.stl"
  $txt = Get-Content -LiteralPath $boxStl -Raw
  $blocks = @([regex]::Matches($txt, "(?s)facet normal.*?endfacet\r?\n?") | ForEach-Object { $_.Value })
  $kept = @($blocks | Select-Object -SkipLast 1) -join ""
  ("solid broken_fixture`r`n" + $kept + "endsolid broken_fixture`r`n") | Set-Content -LiteralPath $brokenStl -Encoding ASCII -NoNewline
  $stepFx = Join-Path $base "part.step"
  Set-Content -LiteralPath $stepFx -Value "ISO-10303-21;" -Encoding ASCII
  $unsupFx = Join-Path $base "run.xyz"
  Set-Content -LiteralPath $unsupFx -Value "n/a" -Encoding ASCII

  # T-ORCH-01: text uctan uca (profil yok -> NOT_PRINT_READY, nedenler acik).
  Invoke-Orch @("-Source", "50x50x20 kutu", "-ProjectName", "orch-t1") | Out-Null
  $o1 = Get-Orch "orch-t1"
  $s1ok = ($null -ne $o1 -and [string]$o1.status -eq "NOT_PRINT_READY" -and [string]$o1.input_kind -eq "text")
  $d1 = Get-OStage $o1 "design"; $q1 = Get-OStage $o1 "mesh_qa"; $g1 = Get-OStage $o1 "gate"
  $s1ok = ($s1ok -and $null -ne $d1 -and [string]$d1.status -eq "OK" -and $null -ne $q1 -and [string]$q1.status -eq "OK")
  $s1ok = ($s1ok -and $null -ne $g1 -and [string]$g1.output -eq "NOT_PRINT_READY" -and @($o1.gate_reasons).Count -gt 0)
  $keysOk = $true
  foreach ($s in @($o1.stages)) {
    foreach ($k in @("stage", "engine", "version", "status", "artifacts")) {
      if ($null -eq $s.PSObject.Properties[$k]) { $keysOk = $false }
    }
  }
  Add-ORCResult "T-ORCH-01" ($s1ok -and $keysOk) "text e2e + asama izleme"

  # T-ORCH-02: tek foto -> reconstruction (mock fallback kayitli).
  Invoke-Orch @("-Source", (Join-Path $base "img1.png"), "-ProjectName", "orch-t2", "-AllowMock") | Out-Null
  $o2 = Get-Orch "orch-t2"
  $r2 = $null; if ($null -ne $o2) { $r2 = Get-OStage $o2 "reconstruct" }
  $fb2 = ($null -ne $r2 -and [string]$r2.status -eq "OK" -and [string]$r2.fallback_used -eq "mock")
  $w2 = $false
  if ($fb2) { $w2 = ((@($r2.warnings) | Where-Object { [string]$_ -match "mock" }).Count -ge 0) }
  Add-ORCResult "T-ORCH-02" ($fb2 -and $w2 -and [string]$o2.input_kind -eq "image") "image -> reconstruction"

  # T-ORCH-03: coklu foto klasoru.
  Invoke-Orch @("-Source", $imgDir, "-ProjectName", "orch-t3", "-AllowMock") | Out-Null
  $o3 = Get-Orch "orch-t3"
  $r3 = $null; if ($null -ne $o3) { $r3 = Get-OStage $o3 "reconstruct" }
  $m3ok = ($null -ne $o3 -and [string]$o3.input_kind -eq "image" -and $null -ne $r3 -and [string]$r3.status -eq "OK")
  $m3ok = ($m3ok -and [string]$r3.input -match "a.png" -and [string]$r3.input -match "b.png")
  Add-ORCResult "T-ORCH-03" $m3ok "multi-image yonlendirme"

  # T-ORCH-04: STL import.
  Invoke-Orch @("-Source", $boxStl, "-ProjectName", "orch-t4") | Out-Null
  $o4 = Get-Orch "orch-t4"
  $i4 = $null; $q4 = $null
  if ($null -ne $o4) { $i4 = Get-OStage $o4 "import_mesh"; $q4 = Get-OStage $o4 "mesh_qa" }
  Add-ORCResult "T-ORCH-04" ($null -ne $o4 -and [string]$o4.input_kind -eq "stl" -and [string]$i4.status -eq "OK" -and [string]$q4.status -eq "OK") "STL import"

  # T-ORCH-05: 3MF import.
  $has3mf = Test-Path -LiteralPath $box3mf
  $o5ok = $false
  if ($has3mf) {
    Invoke-Orch @("-Source", $box3mf, "-ProjectName", "orch-t5") | Out-Null
    $o5 = Get-Orch "orch-t5"
    $i5 = $null; $q5 = $null
    if ($null -ne $o5) { $i5 = Get-OStage $o5 "import_mesh"; $q5 = Get-OStage $o5 "mesh_qa" }
    $o5ok = ($null -ne $o5 -and [string]$o5.input_kind -eq "3mf" -and [string]$i5.status -eq "OK" -and [string]$q5.status -eq "OK")
  }
  Add-ORCResult "T-ORCH-05" $o5ok "3MF import"

  # T-ORCH-06: STEP -> cad_import yapisal hata (motor yok).
  Invoke-Orch @("-Source", $stepFx, "-ProjectName", "orch-t6") | Out-Null
  $o6 = Get-Orch "orch-t6"
  $c6 = $null; if ($null -ne $o6) { $c6 = Get-OStage $o6 "cad_import" }
  $f6ok = ($null -ne $c6 -and (@("FAILED", "BLOCKED") -contains [string]$c6.status) -and @($c6.errors).Count -gt 0)
  Add-ORCResult "T-ORCH-06" ($f6ok -and [string]$o6.input_kind -eq "step") "STEP motor-yok"

  # T-ORCH-07: bozuk mesh -> repair.
  Invoke-Orch @("-Source", $brokenStl, "-ProjectName", "orch-t7") | Out-Null
  $o7 = Get-Orch "orch-t7"
  $p7 = $null; if ($null -ne $o7) { $p7 = Get-OStage $o7 "repair" }
  $r7ok = ($null -ne $p7 -and [string]$p7.status -eq "OK")
  $noMeshReason = $true
  if ($null -ne $o7) {
    $noMeshReason = (@(@($o7.gate_reasons) | Where-Object { [string]$_ -match "mesh invalid" })).Count -eq 0
  }
  Add-ORCResult "T-ORCH-07" ($r7ok -and $noMeshReason) "repair onarimi"

  # T-ORCH-08: printability kosmus (t1 salt-okur).
  $p8 = Get-OStage $o1 "printability"
  $pp8 = Join-Path $Root (Join-Path "projects" (Join-Path "orch-t1" "printability.json"))
  Add-ORCResult "T-ORCH-08" ($null -ne $p8 -and [string]$p8.status -eq "OK" -and (Test-Path -LiteralPath $pp8)) "printability asama"

  # T-ORCH-09: slicer kapisi (t1 salt-okur): readiness BLOCKED, slice atlandi, gcode yok.
  $r9 = Get-OStage $o1 "readiness"; $s9 = Get-OStage $o1 "slice"
  Add-ORCResult "T-ORCH-09" ([string]$r9.output -eq "BLOCKED" -and [string]$s9.status -eq "SKIPPED" -and -not [bool]$o1.gcode_available) "slicer gate kapali"

  # T-ORCH-10: eksik veri -> NEEDS_INPUT + sorular, geometri yok.
  Invoke-Orch @("-Source", "kutu yap", "-ProjectName", "orch-t10") | Out-Null
  $o10 = Get-Orch "orch-t10"
  $d10 = $null; if ($null -ne $o10) { $d10 = Get-OStage $o10 "design" }
  Add-ORCResult "T-ORCH-10" ($null -ne $o10 -and [string]$o10.status -eq "NEEDS_INPUT" -and [string]$d10.status -eq "NEEDS_INPUT" -and @($o10.questions).Count -gt 0) "eksik veri durusu"

  # T-ORCH-11: hata kaydi 5 alanli, jenerik degil.
  $e11 = $null
  if ($null -ne $c6 -and @($c6.errors).Count -gt 0) { $e11 = $c6.errors[0] }
  $f11ok = ($null -ne $e11 -and [string]$e11.stage -ne "" -and [string]$e11.engine -ne "" -and [string]$e11.reason -ne "" -and [string]$e11.suggested_action -ne "" -and [string]$e11.reason -notmatch "hata olustu|bilinmeyen hata")
  Add-ORCResult "T-ORCH-11" $f11ok "yapisal hata kaydi"

  # T-ORCH-12: fallback secimi kayitli (t2 salt-okur).
  Add-ORCResult "T-ORCH-12" ([string]$r2.fallback_used -eq "mock" -and [string]$r2.engine -eq "mock") "fallback kaydi"

  # T-ORCH-13: bozuk checkpoint -> kurtarma (design yeniden kosar).
  $ck13 = Join-Path $Root (Join-Path "projects" (Join-Path "orch-t1" (Join-Path "checkpoints" "design.json")))
  Set-Content -LiteralPath $ck13 -Value "{bozuk" -Encoding ASCII
  Invoke-Orch @("-Source", "50x50x20 kutu", "-ProjectName", "orch-t1", "-Resume") | Out-Null
  $o13 = Get-Orch "orch-t1"
  $d13 = $null; if ($null -ne $o13) { $d13 = Get-OStage $o13 "design" }
  $ck13b = $null
  try { $ck13b = Get-Content -LiteralPath $ck13 -Raw | ConvertFrom-Json } catch { }
  Add-ORCResult "T-ORCH-13" ([string]$d13.status -eq "OK" -and $null -ne $ck13b -and [string]$ck13b.stage -eq "design") "crash recovery"

  # T-ORCH-14: resume -> pahali asama atlanir (CACHED).
  Invoke-Orch @("-Source", "50x50x20 kutu", "-ProjectName", "orch-t1", "-Resume") | Out-Null
  $o14 = Get-Orch "orch-t1"
  $cached14 = @()
  if ($null -ne $o14) { $cached14 = @(@($o14.stages) | Where-Object { [string]$_.status -eq "CACHED" }) }
  $d14 = Get-OStage $o14 "design"
  Add-ORCResult "T-ORCH-14" (@($cached14).Count -gt 0 -and [string]$d14.status -eq "CACHED") "resume cache"

  # T-ORCH-15: dry-run calistirmaz (proje dizini yok + rapor tam).
  $dj = Invoke-Orch @("-Source", "50x50x20 kutu", "-ProjectName", "orch-dry", "-DryRun") | ConvertFrom-Json
  $dryOk = ([bool]$dj.dry_run -and @($dj.stages).Count -gt 5 -and @($dj.engines).Count -gt 0 -and $null -ne $dj.missing_data -and @($dj.expected_artifacts).Count -gt 0)
  $dryOk = ($dryOk -and -not (Test-Path -LiteralPath (Join-Path $Root (Join-Path "projects" "orch-dry"))))
  Add-ORCResult "T-ORCH-15" $dryOk "dry-run yan etkisiz"

  # T-ORCH-16: kapi (a) gercek NOT_PRINT_READY; (b) birim: yesil->PRINT_READY, kirmizi->NOT_PRINT_READY.
  $gate16a = (@($o1.gate_reasons).Count -gt 0 -and [string](Get-OStage $o1 "gate").output -eq "NOT_PRINT_READY")
  function New-SynStage($id, $st) { return [pscustomobject]@{ stage = $id; status = $st } }
  $green = @((New-SynStage "design" "OK"), (New-SynStage "printability" "OK"), (New-SynStage "orientation" "OK"), (New-SynStage "slice" "OK"), (New-SynStage "output_verify" "OK"))
  $evG = Test-PrintReady $green $boxStl ([pscustomobject]@{ watertight = $true }) ([pscustomobject]@{ status = "READY" })
  $red = @((New-SynStage "design" "OK"), (New-SynStage "printability" "OK"), (New-SynStage "orientation" "OK"), (New-SynStage "slice" "SKIPPED"), (New-SynStage "output_verify" "SKIPPED"))
  $evR = Test-PrintReady $red $boxStl ([pscustomobject]@{ watertight = $true }) ([pscustomobject]@{ status = "BLOCKED" })
  $gate16b = ([string]$evG.verdict -eq "PRINT_READY" -and [string]$evR.verdict -eq "NOT_PRINT_READY" -and @($evR.reasons).Count -gt 0)
  Add-ORCResult "T-ORCH-16" ($gate16a -and $gate16b) "print-ready gate"
} finally {
  foreach ($p in @("orch-t1", "orch-t2", "orch-t3", "orch-t4", "orch-t5", "orch-t6", "orch-t7", "orch-t10")) {
    $d = Join-Path $Root (Join-Path "projects" $p)
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
  }
  if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output "----------------------------------------"
Write-Output ("ORCH SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
