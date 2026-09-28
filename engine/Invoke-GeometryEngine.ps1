<#
.SYNOPSIS
  V1.1 Geometry Engine: DesignSpec v2 -> parca basi SCAD -> STL -> validation (max 3 tur).
.DESCRIPTION
  V1 motoruna DOKUNMAZ (ayri dosya). Her bilesen:
    cad/<id>.scad, output/<id>.stl (+3mf), validation/<id>.validation.json
  Ayrica: project.json (created_at/updated_at/prompt/status/parts/validation_status),
  README (parca listesi + parca dogrulamalari). Assembly metadata saklanir (simulasyon yok).
  FAIL -> duzelt/tekrar (max MaxRetries) -> FAILED_AFTER_RETRIES. G-code YOK.
  NOT: $SpecFile (yol) / $gspecObj (veri) ayrimi zorunlu.
.EXAMPLE
  powershell -File engine\Invoke-GeometryEngine.ps1 -SpecFile projects\x\spec.json
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [string]$ProjectDir = "",
  [string]$Printer = "",
  [int]$MaxRetries = 3
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir
. (Join-Path $EngineDir "Geometry.ps1")

function Get-GSettings {
  $p = Join-Path $Root "settings.json"
  if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }
  return $null
}
function Write-NoBom($path, [string[]]$lines) {
  [System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding $false))
}
function Run-GVerify([hashtable]$VArgs) {
  try {
    $o = & $verifyScript @VArgs 2>&1 | Out-String
    return @{ code = 0; text = $o }
  } catch {
    return @{ code = 1; text = $_.Exception.Message }
  }
}

if (-not (Test-Path -LiteralPath $SpecFile)) { throw "Spec bulunamadi: $SpecFile" }
. (Join-Path $EngineDir "CanonicalSpec.ps1")
$rawSpec = Get-Content -LiteralPath $SpecFile -Raw | ConvertFrom-Json
$preDivs = @(@($rawSpec.components) | Where-Object { $_ -and [string]$_.id -like "div*" }).Count
$gspecObj = ConvertTo-CanonicalSpec $rawSpec
$gateSpecFile = $SpecFile
if ($preDivs -gt 0) {
  # Eski format dogrudan verildiyse gate kanonik kopya uzerinden calisir (girdi dosyasi degismez).
  $gateSpecFile = Join-Path ([System.IO.Path]::GetTempPath()) (([string]$gspecObj.project_name + "-canonical.json") -replace '[^A-Za-z0-9]+', '-')
  $gspecObj | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $gateSpecFile -Encoding UTF8
}
$gsettings = Get-GSettings

if ($ProjectDir -eq "") {
  $pdir = "projects"
  if ($gsettings -and $gsettings.projectsDir) { $pdir = $gsettings.projectsDir }
  if (-not [System.IO.Path]::IsPathRooted($pdir)) { $pdir = Join-Path $Root $pdir }
  $ProjectDir = Join-Path $pdir $gspecObj.project_name
}
if ($Printer -eq "") {
  $Printer = "generic-fdm"
  if ($gsettings -and $gsettings.defaultPrinter) { $Printer = $gsettings.defaultPrinter }
}
$printerPath = $Printer
if (-not [System.IO.Path]::IsPathRooted($printerPath)) { $printerPath = Join-Path $Root (Join-Path "printers" ($Printer + ".json")) }

$exportScript = Join-Path $Root (Join-Path "scripts" "Export-Stl.ps1")
$verifyScript = Join-Path $Root (Join-Path "scripts" "Verify-Stl.ps1")

function Write-GValidation($dir, $name, $obj) {
  $vdir = Join-Path $dir "validation"
  New-Item -ItemType Directory -Force -Path $vdir | Out-Null
  $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $vdir ($name + ".validation.json")) -Encoding UTF8
}

# 1. Spec dogrulama
  $dvOut = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile $gateSpecFile -Printer $printerPath -AsJson 2>&1
$dvCode = $LASTEXITCODE
$dvTxt = $dvOut | Out-String
$dv = $dvTxt | ConvertFrom-Json
if ($dvCode -ne 0) {
  New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
  Write-GValidation $ProjectDir "project" ([pscustomobject]@{
    status = "BLOCKED"; reason = "design validation hatalari"
    errors = @($dv.errors); warnings = @($dv.warnings); printer = $Printer
  })
  Write-Output "GENGINE: BLOCKED - kritik hata var, model uretilmedi."
  foreach ($e in $dv.errors) { Write-Output "  ERROR: $e" }
  exit 2
}
foreach ($dw in @($dv.warnings)) { Write-Output "  $dw" }

# OpenSCAD coz (bir kez; oncelik resolver icinde: local > settings > env > tools/ > PATH > bilinen)
$openScad = & (Join-Path $Root (Join-Path "scripts" "Resolve-OpenScad.ps1")) 2>&1 | Select-Object -Last 1

$partResults = New-Object System.Collections.Generic.List[object]
$projectWarnings = New-Object System.Collections.Generic.List[string]
foreach ($w in @($dv.warnings)) { $projectWarnings.Add([string]$w) }

foreach ($c in @($gspecObj.components)) {
  $cid = [string]$c.id
  $partStatus = "FAIL"
  $attempt = 0
  $lastVerify = ""
  $expMin = @(0, 0, 0); $expMax = @(0, 0, 0)
  $holeChecks = @()
  try {
    # --- taban sekli ---
    $b = $c.base
    $shape = [string]$b.shape
    $ww = 0; $dd = 0; $hh = 0
    if ($shape -eq "box") { $geo = New-GBox ([double]$b.width_mm) ([double]$b.depth_mm) ([double]$b.height_mm) }
    elseif ($shape -eq "cylinder") {
      $ax = "z"; if ($b.axis) { $ax = [string]$b.axis }
      $geo = New-GCylinder ([double]$b.diameter_mm) ([double]$b.height_mm) $ax
    }
    elseif ($shape -eq "sphere") { $geo = New-GSphere ([double]$b.diameter_mm) }
    elseif ($shape -eq "cone") { $geo = New-GCone ([double]$b.bottom_diameter_mm) ([double]$b.top_diameter_mm) ([double]$b.height_mm) }
    elseif ($shape -eq "tube") { $geo = New-GTube ([double]$b.outer_diameter_mm) ([double]$b.inner_diameter_mm) ([double]$b.height_mm) }
    elseif ($shape -eq "rounded_box") { $geo = New-GRoundedBox ([double]$b.width_mm) ([double]$b.depth_mm) ([double]$b.height_mm) ([double]$b.radius_mm) }
    else { throw "desteklenmeyen sekil: $shape" }
    if ($shape -eq "box" -or $shape -eq "rounded_box") { $ww = [double]$b.width_mm; $dd = [double]$b.depth_mm; $hh = [double]$b.height_mm }
    elseif ($shape -eq "cylinder" -or $shape -eq "tube") { $hh = [double]$b.height_mm }

    # --- tolerans: fit_to + clearance -> kutu kapakta kucultme ---
    $paramLines = New-Object System.Collections.Generic.List[string]
    if ($shape -eq "box" -or $shape -eq "rounded_box") {
      $ew = $ww; $ed = $dd
      if ($c.tolerance -and $c.tolerance.fit_to -and $null -ne $c.tolerance.clearance_mm) {
        $cl = [double]$c.tolerance.clearance_mm
        $ew = ($ww - 2 * $cl); $ed = ($dd - 2 * $cl)
        $paramLines.Add("clearance = " + (Format-Num $cl) + ";  // fit_to $($c.tolerance.fit_to)")
        $geo = New-GBox $ew $ed ([double]$b.height_mm)
      }
      $paramLines.Add("width = " + (Format-Num $ew) + ";")
      $paramLines.Add("depth = " + (Format-Num $ed) + ";")
      $paramLines.Add("height = " + (Format-Num ([double]$b.height_mm)) + ";")
    } else {
      foreach ($k in @("width_mm", "depth_mm", "height_mm", "diameter_mm", "outer_diameter_mm", "inner_diameter_mm", "radius_mm")) {
        if ($null -ne $b.$k) { $paramLines.Add(($k -replace "_mm$", "") + " = " + (Format-Num ([double]$b.$k)) + ";") }
      }
    }
    $paramLines.Add('$fn = 96;  // dairesel yuzey cozunurlugu (bbox dogrulugu icin)')

    $cuts = New-Object System.Collections.Generic.List[object]

    # --- hollow ---
    if ($null -ne $c.hollow) {
      $hb = New-GHollowBox $ew $ed $hh ([double]$c.hollow.wall_mm) ([bool]$c.hollow.open_top) $c.hollow.bottom_thickness_mm
      if (-not $hb.ok) { throw $hb.reason }
      $paramLines.Add("wall_thickness = " + (Format-Num ([double]$c.hollow.wall_mm)) + ";")
      $geo = $hb
    }

    # --- delikler ---
    foreach ($h in @($c.holes)) {
      if ($null -eq $h) { continue }
      $ht = "through"; if ($h.hole_type) { $ht = [string]$h.hole_type }
      $extra = $null
      if ($ht -eq "blind") { $extra = [pscustomobject]@{ depth = [double]$h.depth_mm } }
      elseif ($ht -eq "countersink") { $extra = [pscustomobject]@{ cs_dia = [double]$h.cs_dia_mm; cs_depth = [double]$h.cs_depth_mm } }
      elseif ($ht -eq "counterbore") { $extra = [pscustomobject]@{ cb_dia = [double]$h.cb_dia_mm; cb_depth = [double]$h.cb_depth_mm } }
      $gh = New-GHole ([double]$h.diameter_mm) ([double]$h.center_x_mm) ([double]$h.center_y_mm) $hh $ht $extra
      $cuts.Add($gh)
      $paramLines.Add("hole_" + [string]$h.id + "_dia = " + (Format-Num ([double]$h.diameter_mm)) + ";")
      $paramLines.Add("hole_" + [string]$h.id + "_x = " + (Format-Num ([double]$h.center_x_mm)) + ";")
      $paramLines.Add("hole_" + [string]$h.id + "_y = " + (Format-Num ([double]$h.center_y_mm)) + ";")
    }

    # --- kesikler ---
    foreach ($t in @($c.cutouts)) {
      if ($null -eq $t) { continue }
      if ([string]$t.kind -eq "slot") {
        $gs = New-GSlot ([double]$t.pos_x_mm) ([double]$t.pos_y_mm) ([double]$t.length_mm) ([double]$t.width_mm) $hh ([double]$t.depth_mm)
        $cuts.Add($gs)
      } else {
        $gc = New-GCutout ([string]$t.face) ([double]$t.pos_x_mm) ([double]$t.pos_y_mm) ([double]$t.width_mm) ([double]$t.length_mm) ([double]$t.depth_mm) $ww $dd $hh
        $cuts.Add($gc)
      }
      $paramLines.Add("cut_" + [string]$t.id + "_w = " + (Format-Num ([double]$t.width_mm)) + ";")
      $paramLines.Add("cut_" + [string]$t.id + "_l = " + (Format-Num ([double]$t.length_mm)) + ";")
    }

    $geo = Carve-G $geo $cuts.ToArray()

    # --- govde-ici bolmeler (Adim A, spec 2.1): uzun kenar (X) boyunca esit aralikli paneller ---
    # Turetim (tahmin degil): ic genislik iw = W-2*duvar; bosluk F = iw - adet*kalinlik;
    # aralik g = F/(adet+1); x_i = duvar + g*i + kalinlik*(i-1);
    # panel: kalinlik x ic_derinlik x (H-duvar-top_gap), taban z0 = duvar (bosluk tabani).
    $divBoxes = New-Object System.Collections.Generic.List[object]
    $dpat = $c.divider_pattern
    if ($null -ne $dpat -and ($shape -eq "box" -or $shape -eq "rounded_box")) {
      $dcn = 0; if ($null -ne $dpat.count) { $dcn = [int]$dpat.count }
      $dth = 0; if ($null -ne $dpat.thickness_mm) { $dth = [double]$dpat.thickness_mm }
      $dgap = 0; if ($null -ne $dpat.top_gap_mm) { $dgap = [double]$dpat.top_gap_mm }
      if ($dcn -ge 1 -and $dth -gt 0 -and $ww -gt 0 -and $dd -gt 0 -and $hh -gt 0) {
        $wl2 = 0
        if ($null -ne $c.hollow -and $null -ne $c.hollow.wall_mm) { $wl2 = [double]$c.hollow.wall_mm }
        $bt2 = $null
        if ($null -ne $c.hollow) { $bt2 = $c.hollow.bottom_thickness_mm }
        $iw2 = $ww - 2 * $wl2
        $free = $iw2 - $dcn * $dth
        if ($free -lt 0) { throw "divider_pattern sigmyor: 2*duvar + adet*kalinlik govde genisligini asiyor" }
        $gg = $free / ($dcn + 1)
        $id2 = $dd - 2 * $wl2
        $z0 = Get-HollowFloor $wl2 $bt2
        $dh = ($hh - $dgap) - $z0
        if ($dh -le 0) { throw "divider_pattern: yukseklik kalmadi (top_gap cok buyuk)" }
        $dgList = New-Object System.Collections.Generic.List[object]
        for ($di = 1; $di -le $dcn; $di++) {
          $x0 = $wl2 + $gg * $di + $dth * ($di - 1)
          $gb = New-GBox $dth $id2 $dh
          $gb = Move-G $gb $x0 $wl2 $z0
          $dvName = ("divider_{0:000}" -f $di)
          $paramLines.Add("divider_" + $di + "_x = " + (Format-Num $x0) + ";")
          $paramLines.Add("divider_" + $di + "_w = " + (Format-Num $dth) + ";")
          $dgList.Add($gb) | Out-Null
          $divBoxes.Add([pscustomobject]@{ id = $dvName; bmin = @($gb.bmin); bmax = @($gb.bmax) }) | Out-Null
        }
        if ($dgList.Count -gt 0) { $geo = Merge-G(@(@($geo) + @($dgList.ToArray()))) }
      }
    }

    # --- kenar notlari (uygulanmaz, uyarilir) ---
    foreach ($e in @($c.edge_notes)) {
      if ($null -eq $e) { continue }
      $projectWarnings.Add("WARNING: ($cid) $($e.kind) $($e.value_mm) mm uygulanmadi; model korundu")
    }

    # --- transformlar ---
    foreach ($tr in @($c.transforms)) {
      if ($null -eq $tr) { continue }
      if ([string]$tr.op -eq "translate") { $geo = Move-G $geo ([double]$tr.x) ([double]$tr.y) ([double]$tr.z) }
      elseif ([string]$tr.op -eq "rotate") { $geo = Turn-G $geo ([double]$tr.x) ([double]$tr.y) ([double]$tr.z) }
      elseif ([string]$tr.op -eq "mirror") { $geo = Mirror-G $geo ([string]$tr.axis) }
    }
    foreach ($n in @($geo.notes)) { $projectWarnings.Add("WARNING: ($cid) $n") }

    # --- beklenen bbox ---
    if ($c.expected_bbox) { $expMin = @($c.expected_bbox.min); $expMax = @($c.expected_bbox.max) }
    else {
      $expMin = @(([math]::Round([double]$geo.bmin[0], 4)), ([math]::Round([double]$geo.bmin[1], 4)), ([math]::Round([double]$geo.bmin[2], 4)))
      $expMax = @(([math]::Round([double]$geo.bmax[0], 4)), ([math]::Round([double]$geo.bmax[1], 4)), ([math]::Round([double]$geo.bmax[2], 4)))
    }

    # --- SCAD yaz (bolumlu, BOM-suz) ---
    $noteLines = New-Object System.Collections.Generic.List[string]
    if ($gspecObj.assembly) { $noteLines.Add("assembly metadata: validation disi (simulasyon yok)") }
    $doc = Build-ScadDocument ($gspecObj.project_name + " / " + $cid) $paramLines.ToArray() @($geo.scad) $noteLines.ToArray()
    $cadDir = Join-Path $ProjectDir "cad"
    New-Item -ItemType Directory -Force -Path $cadDir | Out-Null
    $scadPath = Join-Path $cadDir ($cid + ".scad")
    Write-NoBom $scadPath $doc
    $outDir = Join-Path $ProjectDir "output"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # --- export + verify + retry ---
    do {
      $attempt++
      $expOk = $true
      try {
        & $exportScript -Scad $scadPath -OutDir $outDir -OpenScadExe $openScad 2>&1 | Out-Null
        $stagedStl = Join-Path $outDir "model.stl"
        if ((Test-Path -LiteralPath $stagedStl) -and $stagedStl -ne (Join-Path $outDir ($cid + ".stl"))) {
          Move-Item -LiteralPath $stagedStl -Destination (Join-Path $outDir ($cid + ".stl")) -Force
          $staged3mf = Join-Path $outDir "model.3mf"
          if (Test-Path -LiteralPath $staged3mf) {
            Move-Item -LiteralPath $staged3mf -Destination (Join-Path $outDir ($cid + ".3mf")) -Force
          }
        }
      }
      catch { $expOk = $false; $lastVerify = $_.Exception.Message }
      if (-not $expOk) { $partStatus = "FAIL"; continue }
      $stl = Join-Path $outDir ($cid + ".stl")
      $baseArgs = @{ Stl = $stl; ExpMinX = [double]$expMin[0]; ExpMinY = [double]$expMin[1]; ExpMinZ = [double]$expMin[2]; ExpMaxX = [double]$expMax[0]; ExpMaxY = [double]$expMax[1]; ExpMaxZ = [double]$expMax[2] }
      $throughHoles = @(@($c.holes) | Where-Object { $_ -and (-not $_.hole_type -or [string]$_.hole_type -eq "through" -or [string]$_.hole_type -eq "clearance") })
      $worst = "PASS"
      if ($throughHoles.Count -eq 0) {
        $res = Run-GVerify $baseArgs
        $lastVerify = $res.text
        if ($res.code -ne 0) { $worst = "FAIL" } elseif ($lastVerify -match "WARNING") { $worst = "WARNING" }
      } else {
        foreach ($h in $throughHoles) {
          $hargs = $baseArgs.Clone()
          $hargs.CheckHole = $true
          $hargs.HoleCX = [double]$h.center_x_mm
          $hargs.HoleCY = [double]$h.center_y_mm
          $hargs.HoleDiameter = [double]$h.diameter_mm
          $res = Run-GVerify $hargs
          $txt = $res.text
          $rr2 = "PASS"; if ($res.code -ne 0) { $rr2 = "FAIL" } elseif ($txt -match "WARNING") { $rr2 = "WARNING" }
          $holeChecks += [pscustomobject]@{ id = [string]$h.id; result = $rr2 }
          if ($rr2 -eq "FAIL") { $worst = "FAIL" } elseif ($rr2 -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
          $lastVerify = $txt
        }
      }
      $partStatus = $worst
    } while ($partStatus -eq "FAIL" -and $attempt -lt $MaxRetries)

    if ($partStatus -eq "FAIL") { $partStatus = "FAILED_AFTER_RETRIES" }
  } catch {
    $partStatus = "BLOCKED"
    $lastVerify = $_.Exception.Message
  }

  $stlInfo = Get-Item -LiteralPath (Join-Path $ProjectDir (Join-Path "output" ($cid + ".stl"))) -ErrorAction SilentlyContinue
  $geoCat = "PASS"
  if ($partStatus -eq "WARNING") { $geoCat = "WARNING" }
  elseif ($partStatus -eq "FAIL" -or $partStatus -eq "FAILED_AFTER_RETRIES") { $geoCat = "FAIL" }
  elseif ($partStatus -eq "BLOCKED") { $geoCat = "BLOCKED" }
  $featCat = "PASS"
  foreach ($hc in $holeChecks) { if ($hc.result -eq "FAIL") { $featCat = "FAIL" } }
  if ($partStatus -eq "BLOCKED") { $featCat = "BLOCKED" }
  $asmCat = "PASS"
  if ($gspecObj.assembly) {
    foreach ($j in @($gspecObj.assembly.joints)) {
      if ($j -and ([string]$j.part_a -eq $cid -or [string]$j.part_b -eq $cid)) {
        if ($null -eq $j.clearance_mm -and [string]$j.type -ne "snap_fit") { $asmCat = "WARNING" }
      }
    }
  }
  if ($partStatus -eq "BLOCKED") { $asmCat = "BLOCKED" }
  $mfgCat = "PASS"
  foreach ($wrn in @($projectWarnings.ToArray())) {
    if ([string]$wrn -match [regex]::Escape("(" + $cid + ")")) { $mfgCat = "WARNING" }
  }
  if ($partStatus -eq "BLOCKED") { $mfgCat = "BLOCKED" }
  Write-GValidation $ProjectDir $cid ([pscustomobject]@{
    status = $partStatus
    part = $cid
    categories = [pscustomobject]@{ geometry = $geoCat; feature = $featCat; assembly = $asmCat; manufacturability = $mfgCat }
    bbox_min = @($expMin); bbox_max = @($expMax)
    file_bytes = $(if ($stlInfo) { $stlInfo.Length } else { 0 })
    hole_checks = @($holeChecks)
    retries = [math]::Max(0, ($attempt - 1))
    detail_head = ($lastVerify -split '\r\n|\r|\n' | Select-Object -First 3) -join " | "
  })
  $partResults.Add([pscustomobject]@{ id = $cid; status = $partStatus; bbox_min = @($expMin); bbox_max = @($expMax) })
  Write-Output "GENGINE [$cid]: $partStatus (tur: $attempt)"
  # Bolme dogrulamalari: ayri STL yok, geometri parent STL icinde (parent alani).
  if ($null -ne $divBoxes) {
    foreach ($db in $divBoxes) {
      Write-GValidation $ProjectDir $db.id ([pscustomobject]@{
        status = $partStatus; part = $db.id; parent = $cid
        categories = [pscustomobject]@{ geometry = $geoCat; feature = $featCat; assembly = $asmCat; manufacturability = $mfgCat }
        bbox_min = @($db.bmin); bbox_max = @($db.bmax)
        file_bytes = $(if ($stlInfo) { $stlInfo.Length } else { 0 })
        hole_checks = @(); retries = 0
        detail_head = ("govde-ici bolme (parent " + $cid + ", STL: output/" + $cid + ".stl)")
      })
      $partResults.Add([pscustomobject]@{ id = $db.id; status = $partStatus; parent = $cid; bbox_min = @($db.bmin); bbox_max = @($db.bmax) })
    }
  }
}

# --- proje ozeti ---
$worstAll = "PASS"
foreach ($pr in $partResults) {
  if ($pr.status -eq "BLOCKED" -or $pr.status -eq "FAILED_AFTER_RETRIES" -or $pr.status -eq "FAIL") { $worstAll = "FAILED" }
  elseif ($pr.status -eq "WARNING" -and $worstAll -eq "PASS") { $worstAll = "WARNING" }
}
$now = (Get-Date).ToUniversalTime().ToString("o")
$dsVer = "2.0"
foreach ($pc in @($gspecObj.components)) {
  if ($pc -and $null -ne $pc.divider_pattern) { $dsVer = "2.1"; break }
}
$proj = [pscustomobject]@{
  project_id = [string]$gspecObj.project_name
  project_name = [string]$gspecObj.project_name
  created_at = $now; updated_at = $now; prompt = $gspecObj.prompt; status = $worstAll
  designspec_version = $dsVer; engine_version = "V1.1"; pipeline_version = "V1.2"
  parts = @($partResults.ToArray()); validation_status = $worstAll; assembly = $gspecObj.assembly
  gcode_available = $false; gcode_note = "NOT AVAILABLE - printer profile required"
}
$proj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ProjectDir "project.json") -Encoding UTF8

if ($null -ne $gspecObj.prompt) { $gspecObj.prompt | Set-Content -LiteralPath (Join-Path $ProjectDir "input.md") -Encoding UTF8
  $destJson = Join-Path $ProjectDir "input.json"
  if ([System.IO.Path]::GetFullPath($SpecFile) -ne [System.IO.Path]::GetFullPath($destJson)) {
    Copy-Item -LiteralPath $SpecFile -Destination $destJson -Force
  }
}

$rm = New-Object System.Collections.Generic.List[string]
$rm.Add("# $($gspecObj.project_name) (Geometry Engine V1.1)")
$rm.Add("")
$rm.Add("## Kaynak prompt (degistirilmeden)")
$rm.Add("> $($gspecObj.prompt)")
$rm.Add("")
$rm.Add("## Parcalar")
$rm.Add("| Parca | Durum | bbox min | bbox max | STL |")
$rm.Add("| ----- | ----- | -------- | -------- | --- |")
foreach ($pr in $partResults) {
  $stlRef = "output/" + $pr.id + ".stl"
  if ($pr.parent) { $stlRef = "output/" + $pr.parent + ".stl (govde-ici)" }
  $rm.Add("| $($pr.id) | $($pr.status) | $($pr.bbox_min -join ', ') | $($pr.bbox_max -join ', ') | $stlRef |")
}
$rm.Add("")
$rm.Add("## Dogrulama")
$rm.Add("- Proje status: $worstAll")
foreach ($wrn in @($projectWarnings.ToArray())) { $rm.Add("- $wrn") }
if ($gspecObj.assembly) {
  $rm.Add("")
  $rm.Add("## Montaj (metadata, simulasyon yok)")
  foreach ($j in @($gspecObj.assembly.joints)) {
    $rm.Add("- $($j.id): $($j.type) ($($j.part_a) + $($j.part_b), clearance $($j.clearance_mm))")
  }
}
$rm.Add("")
$rm.Add("## Dosyalar")
$rm.Add("- input.md / input.json, project.json")
$rm.Add("- cad/<parca>.scad, output/<parca>.stl, validation/<parca>.validation.json")
$rm.Add("- slice/ : yok (G-code uretilmedi)")
$rm.Add("")
$rm.Add("## Malzeme")
if ($gspecObj.material) { $rm.Add("- $($gspecObj.material)") } else { $rm.Add("- belirtilmedi") }
$rm | Set-Content -LiteralPath (Join-Path $ProjectDir "README.md") -Encoding UTF8

Write-Output "GENGINE: $worstAll"
if ($worstAll -eq "FAILED") { exit 2 } else { exit 0 }
