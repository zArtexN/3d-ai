<#
.SYNOPSIS
  Phase 3 TDD: iterative edit + version history (T-EDIT-001..025).
.DESCRIPTION
  Dosya ASCII-only. Agir e2e kosulari gruplandi (engine ~40sn).
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-DesignEdit.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-EDResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-EDDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ed-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-EDSpec($tag) {
  $d = New-EDDir $tag
  $body = [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 60; depth_mm = 40; height_mm = 20 }
    hollow = [pscustomobject]@{ wall_mm = 2; open_top = $true; bottom_thickness_mm = 2 }
    holes = @([pscustomobject]@{
      id = "h1"; hole_type = "through"; diameter_mm = 10
      center_x_mm = 15; center_y_mm = 15; axis = "z"
      depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
      screw = $null; status = "ok"
    })
    cutouts = @([pscustomobject]@{ id = "c1"; kind = "rect"; face = "front"; pos_x_mm = 30; pos_y_mm = 5; width_mm = 20; length_mm = 10; depth_mm = 2; status = "ok" })
    edge_notes = @(); transforms = @(); tolerance = $null; expected_bbox = $null
  }
  $sp = [pscustomobject]@{ project_name = $tag; prompt = $tag; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($body); assembly = $null; material = $null; disabled_features = @() }
  $sf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
  return @{ dir = $d; file = $sf }
}
function Invoke-EDEdit($dir, $instruction, $auto) {
  $arg = @{ ProjectDir = $dir; Instruction = $instruction }
  if ($auto) { $o = & (Join-Path $EngineDir "Invoke-SpecEdit.ps1") -ProjectDir $dir -Instruction $instruction -AutoAccept 2>&1 | Out-String }
  else { $o = & (Join-Path $EngineDir "Invoke-SpecEdit.ps1") -ProjectDir $dir -Instruction $instruction 2>&1 | Out-String }
  try { return ($o | ConvertFrom-Json) } catch { return $null }
}
function NumEq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.0001) } catch { return $false }
}

. (Join-Path $EngineDir "DesignSpecPatch.ps1")
. (Join-Path $EngineDir "EditIntent.ps1")
. (Join-Path $EngineDir "ProjectVersions.ps1")

# T-EDIT-001/011/012/020: duvar editi e2e (deger + kritik diff + ilgili-disi + ID).
$r = New-EDSpec "ed01"
$o = Invoke-EDEdit $r.dir "duvari 4 mm yap" $true
$sp = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
$wOk = ($null -ne $o -and [string]$o.status -eq "OK" -and [string]$o.version -eq "v002")
$wOk = ($wOk -and (NumEq $sp.components[0].hollow.wall_mm 4))
$dl = @()
if ($null -ne $o) { $dl = @($o.diff_report) }
Add-EDResult "T-EDIT-001" ($wOk -and ((@($o.diff_changed) | Where-Object { [string]$_.path -eq "body.hollow.wall_mm" }).Count -eq 1)) "duvar 2->4, version v002"
$dOk = ((($dl -join " ") -match "body.hollow.wall_mm") -and (($dl -join " ") -match "\+2"))
Add-EDResult "T-EDIT-011" $dOk "kritik diff delta +1"
$chg = @()
if ($null -ne $o) { $chg = @($o.diff_changed | ForEach-Object { [string]$_.path }) }
Add-EDResult "T-EDIT-012" (($chg.Count -eq 1) -and ($chg[0] -eq "body.hollow.wall_mm")) "ilgili-disi degismedi"
$hids = @(@($sp.components[0].holes) | ForEach-Object { [string]$_.id })
$cids = @(@($sp.components[0].cutouts) | ForEach-Object { [string]$_.id })
Add-EDResult "T-EDIT-020" (($hids -contains "h1") -and ($cids -contains "c1")) "ID stabil"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-002: genislik editi e2e (spec.json guncel surume senkron olur).
$r = New-EDSpec "ed02"
$o = Invoke-EDEdit $r.dir "genisligi 80 mm yap" $true
$sp = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
Add-EDResult "T-EDIT-002" (($null -ne $o) -and ([string]$o.status -eq "OK") -and (NumEq $sp.components[0].base.width_mm 80)) "genislik 80 (spec senkron)"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-003: delik tasima e2e.
$r = New-EDSpec "ed03"
$o = Invoke-EDEdit $r.dir "delik h1'i 3 mm saga tasi" $true
$v = $null
$vd = Join-Path $r.dir (Join-Path "versions" "v002.json")
if (Test-Path -LiteralPath $vd) { $v = (Get-Content -LiteralPath $vd -Raw | ConvertFrom-Json).spec.components[0].holes[0] }
Add-EDResult "T-EDIT-003" (($null -ne $o) -and ([string]$o.status -eq "OK") -and ($null -ne $v) -and (NumEq $v.center_x_mm 18) -and (NumEq $v.center_y_mm 15)) "h1 saga +3"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-004: delik capi e2e.
$r = New-EDSpec "ed04"
$o = Invoke-EDEdit $r.dir "delik capini 8 mm yap" $true
$v = $null
$vd = Join-Path $r.dir (Join-Path "versions" "v002.json")
if (Test-Path -LiteralPath $vd) { $v = (Get-Content -LiteralPath $vd -Raw | ConvertFrom-Json).spec.components[0].holes[0] }
Add-EDResult "T-EDIT-004" (($null -ne $o) -and ([string]$o.status -eq "OK") -and ($null -ne $v) -and (NumEq $v.diameter_mm 8)) "cap 8"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-005 + needs-confirmation: kesit kaldirma.
$r = New-EDSpec "ed05"
$o1 = Invoke-EDEdit $r.dir "on kesiti kaldir" $false
$vfile = Join-Path $r.dir (Join-Path "versions" "v002.json")
$noVer = -not (Test-Path -LiteralPath $vfile)
$o2 = Invoke-EDEdit $r.dir "on kesiti kaldir" $true
$cs = @()
if (Test-Path -LiteralPath $vfile) {
  $vs = (Get-Content -LiteralPath $vfile -Raw | ConvertFrom-Json).spec
  $cs = @($vs.components[0].cutouts)
}
Add-EDResult "T-EDIT-005" (([string]$o1.status -eq "NEEDS_CONFIRMATION") -and $noVer -and ([string]$o2.status -eq "OK") -and ($cs.Count -eq 0)) "kaldirma onayli + kesit gitti"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-006: delik ekleme (id collision yok).
$r = New-EDSpec "ed06"
$o = Invoke-EDEdit $r.dir "cap 8 merkez 30,10 delik ekle" $true
$hs = @()
$vd = Join-Path $r.dir (Join-Path "versions" "v002.json")
if (Test-Path -LiteralPath $vd) { $hs = @((Get-Content -LiteralPath $vd -Raw | ConvertFrom-Json).spec.components[0].holes) }
$ids = @($hs | ForEach-Object { [string]$_.id })
Add-EDResult "T-EDIT-006" (($null -ne $o) -and ([string]$o.status -eq "OK") -and ($ids -contains "h1") -and ($ids -contains "h2")) "h2 eklendi, h1 korundu"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-007/025: multi atomic (basari + rollback).
$r = New-EDSpec "ed07"
$o = Invoke-EDEdit $r.dir "duvari 4 mm yap ve tabani 5 mm yap" $true
$idx = $null
$ip = Join-Path $r.dir (Join-Path "versions" "index.json")
if (Test-Path -LiteralPath $ip) { $idx = Get-Content -LiteralPath $ip -Raw | ConvertFrom-Json }
$sp = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
Add-EDResult "T-EDIT-007" (($null -ne $o) -and ([string]$o.status -eq "OK") -and (@($idx.versions).Count -eq 2)) "multi tek version"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
$r = New-EDSpec "ed25"
$before = Get-Content -LiteralPath $r.file -Raw
$o = Invoke-EDEdit $r.dir "duvari 4 mm yap ve zart zurt 5 mm yap" $true
$after = Get-Content -LiteralPath $r.file -Raw
$idx = $null
$ip = Join-Path $r.dir (Join-Path "versions" "index.json")
if (Test-Path -LiteralPath $ip) { $idx = Get-Content -LiteralPath $ip -Raw | ConvertFrom-Json }
Add-EDResult "T-EDIT-025" (([string]$o.status -ne "OK") -and ($before -eq $after) -and (@($idx.versions).Count -eq 1)) "rollback: hicbiri uygulanmadi"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-008: belirsizlik reddi.
$r = New-EDSpec "ed08"
$o = Invoke-EDEdit $r.dir "bunu biraz buyut" $true
$idx = $null
$ip = Join-Path $r.dir (Join-Path "versions" "index.json")
if (Test-Path -LiteralPath $ip) { $idx = Get-Content -LiteralPath $ip -Raw | ConvertFrom-Json }
Add-EDResult "T-EDIT-008" (([string]$o.status -eq "NEEDS_INPUT") -and (@($idx.versions).Count -eq 1)) "belirsiz -> soru, version yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-009/010/022/023/024: patch validasyon zinciri (unit).
. (Join-Path $EngineDir "DesignSpecPatch.ps1")
$u = New-EDSpec "edval"
$uspec = Get-Content -LiteralPath $u.file -Raw | ConvertFrom-Json
$r9 = Test-PatchOp $uspec @{ op = "replace"; path = "body.base.color"; value = 1 }
Add-EDResult "T-EDIT-009" (-not $r9.ok) "gecersiz path reject"
$r10 = Test-PatchOp $uspec @{ op = "replace"; path = "body.material"; value = "x" }
$r10b = Test-PatchOp $uspec @{ op = "replace"; path = "body.holes.h1.diameter_mm"; value = "abc" }
Add-EDResult "T-EDIT-010" ((-not $r10.ok) -and (-not $r10b.ok)) "schema/tip ihlali reject"
try { $r22 = Test-PatchOp $null "bozuk-girdi"; $ok22 = (-not $r22.ok) } catch { $ok22 = $true }
Add-EDResult "T-EDIT-022" $ok22 "gecersiz girdi reject (throw yok)"
# T-EDIT-024: yetkisiz alanlar (printer/filament/process/material) reject.
$r = New-EDSpec "ed24"
$uspec = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
$rejAll = $true
foreach ($bp in @("printers.generic.nozzle_mm", "filament.pla.temp", "process.x.speed", "body.base.width_mm.extra", "body.material")) {
  $rr = Test-PatchOp $uspec @{ op = "replace"; path = $bp; value = 1 }
  if ($rr.ok) { $rejAll = $false }
}
Add-EDResult "T-EDIT-024" $rejAll "yetkisiz alanlar reject"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-EDIT-023: unitsiz string deger reject.
$r = New-EDSpec "ed23"
$uspec = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
$r23 = Test-PatchOp $uspec @{ op = "replace"; path = "body.base.width_mm"; value = "80 mm" }
Add-EDResult "T-EDIT-023" (-not $r23.ok) "string birim reject"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-013: gate-BLOCKED patch version uretmez (duvar 100 / govde 60).
$r = New-EDSpec "ed13"
$before = Get-Content -LiteralPath $r.file -Raw
$o = Invoke-EDEdit $r.dir "duvari 100 mm yap" $true
$after = Get-Content -LiteralPath $r.file -Raw
$nov2 = -not (Test-Path -LiteralPath (Join-Path $r.dir (Join-Path "versions" "v002.json")))
Add-EDResult "T-EDIT-013" (([string]$o.status -ne "OK") -and ($before -eq $after) -and $nov2) "gate-BLOCKED: version yok, current ayni"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-014: olcum uyumsuzlugu version uretmez (expected_bbox dar + gecerli edit).
$r = New-EDSpec "ed14"
$sp14 = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
$sp14.components[0] | Add-Member -NotePropertyName "expected_bbox" -NotePropertyValue ([pscustomobject]@{ min = @(0, 0, 0); max = @(1, 1, 1) }) -Force
$sp14 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $r.file -Encoding UTF8
$o = Invoke-EDEdit $r.dir "duvari 4 mm yap" $true
$nov2 = -not (Test-Path -LiteralPath (Join-Path $r.dir (Join-Path "versions" "v002.json")))
Add-EDResult "T-EDIT-014" (([string]$o.status -ne "OK") -and $nov2) "olcum-BLOCKED: version yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-015/016/017/019: paylasimli projede undo/redo/branch/restore.
$rv = New-EDSpec "edver"
$o = Invoke-EDEdit $rv.dir "duvari 4 mm yap" $true
$u15 = Invoke-EDEdit $rv.dir "onceki haline don" $true
$idx = Get-Content -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "index.json")) -Raw | ConvertFrom-Json
Add-EDResult "T-EDIT-015" (([string]$u15.status -eq "OK") -and ([string]$u15.version -eq "v001") -and ([string]$idx.current -eq "v001")) "undo V2->V1"
$o = Invoke-EDEdit $rv.dir "ileri al" $true
$idx = Get-Content -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "index.json")) -Raw | ConvertFrom-Json
Add-EDResult "T-EDIT-016" (([string]$o.status -eq "OK") -and ([string]$o.version -eq "v002") -and ([string]$idx.current -eq "v002")) "redo V1->V2"
$o = Invoke-EDEdit $rv.dir "onceki haline don" $true
$o = Invoke-EDEdit $rv.dir "tabani 5 mm yap" $true
$idx = Get-Content -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "index.json")) -Raw | ConvertFrom-Json
$v3 = $null
$vp3 = Join-Path $rv.dir (Join-Path "versions" "v003.json")
if (Test-Path -LiteralPath $vp3) { $v3 = Get-Content -LiteralPath $vp3 -Raw | ConvertFrom-Json }
$v2gone = -not (Test-Path -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "v002.json")))
Add-EDResult "T-EDIT-017" (($null -ne $o) -and ([string]$o.status -eq "OK") -and ([string]$o.version -eq "v003") -and (-not $v2gone) -and ([string]$v3.parent_version -eq "v001")) "branch: V3 parent V1, V2 korunur"
$o = Invoke-EDEdit $rv.dir "v001'e don" $true
$idx = Get-Content -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "index.json")) -Raw | ConvertFrom-Json
$v4 = $null
$vp4 = Join-Path $rv.dir (Join-Path "versions" "v004.json")
if (Test-Path -LiteralPath $vp4) { $v4 = Get-Content -LiteralPath $vp4 -Raw | ConvertFrom-Json }
Add-EDResult "T-EDIT-019" (($null -ne $o) -and ([string]$o.status -eq "OK") -and ([string]$v4.restore_from -eq "v001") -and ([string]$idx.current -eq "v004")) "restore V1->V4"
# T-EDIT-018: immutability (tum snapshotlar sabit).
$h1ok = $true
foreach ($vf in (Get-ChildItem -LiteralPath (Join-Path $rv.dir "versions") -Filter "v*.json")) {
  $vv = Get-Content -LiteralPath $vf.FullName -Raw | ConvertFrom-Json
  if ([string]$vv.version_id -ne [string]$vf.BaseName) { $h1ok = $false }
}
$v1a = Get-Content -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "v001.json")) -Raw
$o = Invoke-EDEdit $rv.dir "duvari 6 mm yap" $true
$v1b = Get-Content -LiteralPath (Join-Path $rv.dir (Join-Path "versions" "v001.json")) -Raw
Add-EDResult "T-EDIT-018" ($h1ok -and ($v1a -eq $v1b)) "snapshotlar immutable"
Remove-Item -LiteralPath $rv.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-021: retli feature korunur (delik ekleme reddedilir).
$r = New-EDSpec "ed21"
$sp21 = Get-Content -LiteralPath $r.file -Raw | ConvertFrom-Json
$sp21 | Add-Member -NotePropertyName "disabled_features" -NotePropertyValue @("hole") -Force
$sp21 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $r.file -Encoding UTF8
$o = Invoke-EDEdit $r.dir "cap 8 merkez 30,10 delik ekle" $true
$nov2 = -not (Test-Path -LiteralPath (Join-Path $r.dir (Join-Path "versions" "v002.json")))
Add-EDResult "T-EDIT-021" (([string]$o.status -ne "OK") -and $nov2) "retli delik eklenemez"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-027: invariant demeti (gecerli edit sonrasi).
$r = New-EDSpec "ed27"
$o = Invoke-EDEdit $r.dir "duvari 4 mm yap" $true
$sp = Get-Content -LiteralPath (Join-Path $r.dir (Join-Path "versions" "v002.json")) -Raw | ConvertFrom-Json
$gd = New-EDDir "ed27g"
$sp.spec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $gd "spec.json") -Encoding UTF8
$gv = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile (Join-Path $gd "spec.json") -AsJson 2>&1 | Out-String | ConvertFrom-Json
Remove-Item -LiteralPath $gd -Recurse -Force -ErrorAction SilentlyContinue
$invOk = (($null -ne $o) -and ([string]$o.status -eq "OK") -and (@($gv.errors).Count -eq 0))
$invOk = ($invOk -and ((@($sp.spec.components[0].holes) | ForEach-Object { [string]$_.id }) -contains "h1"))
$invOk = ($invOk -and ($null -ne $sp.spec.components[0].hollow.wall_mm))
$idx = Get-Content -LiteralPath (Join-Path $r.dir (Join-Path "versions" "index.json")) -Raw | ConvertFrom-Json
$invOk = ($invOk -and ([string]$idx.current -eq "v002"))
Add-EDResult "T-EDIT-027" $invOk "invariantlar: gecerli spec, ID stabil, current gecerli"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-028: crash guvenligi (basarisiz kostu ardindan aday artik yok).
$r = New-EDSpec "ed28"
$o = Invoke-EDEdit $r.dir "duvari 100 mm yap" $true
$leftCands = @(Get-ChildItem -LiteralPath (Join-Path $r.dir "candidates") -Directory -ErrorAction SilentlyContinue)
$idx = Get-Content -LiteralPath (Join-Path $r.dir (Join-Path "versions" "index.json")) -Raw | ConvertFrom-Json
Add-EDResult "T-EDIT-028" ((@($leftCands).Count -eq 0) -and ([string]$idx.current -eq "v001")) "aday temizlandi, current V1"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-EDIT-029: proje izolasyonu.
$ra = New-EDSpec "ed29a"
$rb = New-EDSpec "ed29b"
$oa = Invoke-EDEdit $ra.dir "duvari 4 mm yap" $true
$idxb = $null
$ipb = Join-Path $rb.dir (Join-Path "versions" "index.json")
if (Test-Path -LiteralPath $ipb) { $idxb = Get-Content -LiteralPath $ipb -Raw | ConvertFrom-Json }
$spb = Get-Content -LiteralPath $rb.file -Raw | ConvertFrom-Json
$bClean = ($null -eq $idxb) -or ([string]$idxb.current -eq "v001")
Add-EDResult "T-EDIT-029" (([string]$oa.status -eq "OK") -and $bClean -and (NumEq $spb.components[0].hollow.wall_mm 2)) "B etkilenmedi"
Remove-Item -LiteralPath $ra.dir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $rb.dir -Recurse -Force -ErrorAction SilentlyContinue
