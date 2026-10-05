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
  [int]$MaxRetries = 3,
  [double]$MeasurementTolerance = 0.1
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir
. (Join-Path $EngineDir "Geometry.ps1")
# Adim C: delik yerlesim matematigi (compiler uretimi; tek kaynak).
. (Join-Path $EngineDir "HoleLayout.ps1")

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
  if ($gsettings -and $gsettings.defaultPrinter) { $Printer = $gsettings.defaultPrinter }
}
# Template gercek printer degildir: source=template veya usable_for_slicing=false
# ise profil yok sayilir (geometri uretimi durmaz; yaziciya ozel kontrol UNKNOWN).
$printerPath = ""
$printerProfileId = ""
if ($Printer -ne "") {
  $cand = $Printer
  if (-not [System.IO.Path]::IsPathRooted($cand)) { $cand = Join-Path $Root (Join-Path "printers" ($Printer + ".json")) }
  if (Test-Path -LiteralPath $cand) {
    try {
      $pjTmp = Get-Content -LiteralPath $cand -Raw | ConvertFrom-Json
      if ([string]$pjTmp.source -ne "template" -and $pjTmp.usable_for_slicing -ne $false) {
        $printerPath = $cand
        $printerProfileId = [string]$pjTmp.id
      }
    } catch { }
  }
}

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
    errors = @($dv.errors); warnings = @($dv.warnings); printer = $printerProfileId
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
  $cutoutChecks = @()
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
      if ($shape -eq "rounded_box" -and $null -ne $b.radius_mm) {
        $paramLines.Add("corner_radius = " + (Format-Num ([double]$b.radius_mm)) + ";")
      }
    } else {
      foreach ($k in @("width_mm", "depth_mm", "height_mm", "diameter_mm", "outer_diameter_mm", "inner_diameter_mm", "radius_mm")) {
        if ($null -ne $b.$k) { $paramLines.Add(($k -replace "_mm$", "") + " = " + (Format-Num ([double]$b.$k)) + ";") }
      }
    }
    $paramLines.Add('$fn = 96;  // dairesel yuzey cozunurlugu (bbox dogrulugu icin)')

    $cuts = New-Object System.Collections.Generic.List[object]

    # --- semantic hole pattern cozumu (Adim C): compiler deterministik uretir ---
    # Parser degerlerini korur; bos ya da derived-isaretli merkezleri pattern'den doldurur.
    $hp = $c.hole_pattern
    if ($null -ne $hp -and ([string]$hp.type -eq "corner_pattern" -or [string]$hp.type -eq "mid_edge") -and ($shape -eq "box" -or $shape -eq "rounded_box")) {
      $hw = [double]$b.width_mm; $hd = [double]$b.depth_mm
      $ho = 0; if ($null -ne $hp.edge_offset_mm) { $ho = [double]$hp.edge_offset_mm }
      $hcn = 0; if ($null -ne $hp.count) { $hcn = [int]$hp.count }
      if ($hw -gt 0 -and $hd -gt 0 -and $ho -gt 0 -and $hcn -ge 1) {
        $cc2 = Get-PatternCenters ([string]$hp.type) $hw $hd $ho
        if ($null -ne $cc2) {
          $ci2 = 0
          foreach ($ph in @($c.holes)) {
            if ($null -eq $ph) { continue }
            if ([string]$ph.id -like "mp*") { continue }
            if ($ci2 -ge $cc2.Count) { break }
            $needFill = ($null -eq $ph.center_x_mm -or $null -eq $ph.center_y_mm)
            $isDerived = ($null -ne $ph.placement -and [string]$ph.placement.provenance -eq "derived")
            if ($needFill -or $isDerived) {
              $ph.center_x_mm = $cc2[$ci2][0]; $ph.center_y_mm = $cc2[$ci2][1]; $ph.status = "ok"
              if ($null -eq $ph.placement) {
                $ph | Add-Member -NotePropertyName "placement" -NotePropertyValue ([pscustomobject]@{ type = [string]$hp.type; provenance = "derived" }) -Force
              }
            }
            $ci2++
          }
        }
      }
    }

    # --- hollow ---
    if ($null -ne $c.hollow) {
      if ($shape -eq "rounded_box") {
        $hb = New-GHollowRoundedBox $ew $ed $hh ([double]$c.hollow.wall_mm) ([double]$b.radius_mm) ([bool]$c.hollow.open_top) $c.hollow.bottom_thickness_mm
      } else {
        $hb = New-GHollowBox $ew $ed $hh ([double]$c.hollow.wall_mm) ([bool]$c.hollow.open_top) $c.hollow.bottom_thickness_mm
      }
      if (-not $hb.ok) { throw $hb.reason }
      $paramLines.Add("wall_thickness = " + (Format-Num ([double]$c.hollow.wall_mm)) + ";")
      $geo = $hb
    }

    # --- delikler ---
    foreach ($h in @($c.holes)) {
      if ($null -eq $h) { continue }
      $ht = "through"; if ($h.hole_type) { $ht = [string]$h.hole_type }
      $hAxis = "z"; if ($h.axis) { $hAxis = [string]$h.axis }
      $extra = $null
      if ($ht -eq "blind") { $extra = [pscustomobject]@{ depth = [double]$h.depth_mm } }
      elseif ($ht -eq "countersink") { $extra = [pscustomobject]@{ cs_dia = [double]$h.cs_dia_mm; cs_depth = [double]$h.cs_depth_mm } }
      elseif ($ht -eq "counterbore") { $extra = [pscustomobject]@{ cb_dia = [double]$h.cb_dia_mm; cb_depth = [double]$h.cb_depth_mm } }
      # Yuz-tabanli delik (axis=y): bodyH = dd (derinlik Y). Koordinatlar: x=center_x, y=center_y (Z konumu).
      $hBodyH = $hh
      if ($hAxis -eq "y") { $hBodyH = $dd }
      $gh = New-GHole ([double]$h.diameter_mm) ([double]$h.center_x_mm) ([double]$h.center_y_mm) $hBodyH $ht $extra $hAxis
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
        $faceBase = ([string]$t.face -replace '_short_edge$','' -replace '_long_edge$','')
        $useDepth = $t.depth_mm
        if ($null -eq $useDepth -and [string]$t.penetration -eq "through_wall") {
          if ($null -ne $c.hollow -and $null -ne $c.hollow.wall_mm) { $useDepth = [double]$c.hollow.wall_mm }
          else { throw ("kesik '" + [string]$t.id + "': through_wall icin duvar kalinligi gerekli (derinlik cikarilamadi)") }
        }
        $gc = New-GCutout $faceBase ([double]$t.pos_x_mm) ([double]$t.pos_y_mm) ([double]$t.width_mm) ([double]$t.length_mm) ([double]$useDepth) $ww $dd $hh
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

    # --- planner partisyonlari + kamalar (v1.0, additive; divider yolu ayni Merge-G) ---
    # partitions: axis=y -> X'te ince, Y boyunca uzun (bolme); axis=x -> Y'de ince, X boyunca (dudak).
    foreach ($pt in @($c.partitions)) {
      if ($null -eq $pt) { continue }
      if ([string]$pt.axis -eq "x") {
        $gb = New-GBox ([double]$pt.length_mm) ([double]$pt.thickness_mm) ([double]$pt.height_mm)
      } else {
        $gb = New-GBox ([double]$pt.thickness_mm) ([double]$pt.length_mm) ([double]$pt.height_mm)
      }
      $gb = Move-G $gb ([double]$pt.x_mm) ([double]$pt.y_mm) ([double]$pt.z0_mm)
      $paramLines.Add("partition_" + [string]$pt.id + "_x = " + (Format-Num ([double]$pt.x_mm)) + ";")
      $geo = Merge-G(@(@($geo) + @($gb)))
      $divBoxes.Add([pscustomobject]@{ id = [string]$pt.id; bmin = @($gb.bmin); bmax = @($gb.bmax) }) | Out-Null
    }
    foreach ($wd in @($c.wedges)) {
      if ($null -eq $wd) { continue }
      $ewy0 = [double]$wd.y0_mm
      if ($wd.angle_driven -eq $true -and $null -ne $wd.angle_deg) {
        $ewy0 = [double]$wd.y1_mm - [double]$wd.height_mm * [math]::Tan([double]$wd.angle_deg * [math]::PI / 180.0)
      }
      $gw = New-GWedge ([double]$wd.x0_mm) ([double]$wd.x1_mm) $ewy0 ([double]$wd.y1_mm) ([double]$wd.z0_mm) ([double]$wd.height_mm)
      $paramLines.Add("wedge_" + [string]$wd.id + "_angle = " + (Format-Num ([double]$wd.angle_deg)) + ";")
      $geo = Merge-G(@(@($geo) + @($gw)))
      $divBoxes.Add([pscustomobject]@{ id = [string]$wd.id; bmin = @($gw.bmin); bmax = @($gw.bmax) }) | Out-Null
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
    $specVerNote = "?"
    if ($null -ne $gspecObj.metadata -and $null -ne $gspecObj.metadata.spec_version) { $specVerNote = [string]$gspecObj.metadata.spec_version }
    $featIds = @()
    foreach ($fh in @($c.holes)) { if ($fh -and $fh.id) { $featIds += [string]$fh.id } }
    foreach ($ft in @($c.cutouts)) { if ($ft -and $ft.id) { $featIds += [string]$ft.id } }
    if ($null -ne $c.divider_pattern) { $featIds += ("dividers:" + [string]$c.divider_pattern.count) }
    foreach ($fp in @($c.partitions)) { if ($fp -and $fp.id) { $featIds += [string]$fp.id } }
    foreach ($fw in @($c.wedges)) { if ($fw -and $fw.id) { $featIds += [string]$fw.id } }
    $noteLines.Add(("spec: v" + $specVerNote + "; features: " + ($featIds -join ",")))
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
      # Olcum toleransi merkezi: imalat toleransi (clearance) ile karistirilmaz.
      $baseArgs = @{ Stl = $stl; Tolerance = $MeasurementTolerance; ExpMinX = [double]$expMin[0]; ExpMinY = [double]$expMin[1]; ExpMinZ = [double]$expMin[2]; ExpMaxX = [double]$expMax[0]; ExpMaxY = [double]$expMax[1]; ExpMaxZ = [double]$expMax[2] }
      $throughHoles = @(@($c.holes) | Where-Object { $_ -and (-not $_.hole_type -or [string]$_.hole_type -eq "through" -or [string]$_.hole_type -eq "clearance") })
      $blindHoles = @(@($c.holes) | Where-Object { $_ -and [string]$_.hole_type -eq "blind" })
      # Cikis duzlemi: deligin gectigi malzemenin ustu (birlesim bbox degil).
      # hollow+acik govdede delik tabanda biter (floor);
      # hollow-olmayan kutuda taban plaka ustunde (govde yuksekligi);
      # kapali/hollow-olmayan parcalarda parca tepesi (mevcut davranis).
      $exitZ = [double]$expMax[2]
      if (($shape -eq "box" -or $shape -eq "rounded_box") -and $null -eq $c.hollow) {
        $exitZ = $hh
      }
      elseif ($null -ne $c.hollow -and $c.hollow.open_top -eq $true -and $null -ne $c.hollow.wall_mm) {
        $btX = $null
        if ($null -ne $c.hollow.bottom_thickness_mm) { $btX = $c.hollow.bottom_thickness_mm }
        $exitZ = Get-HollowFloor ([double]$c.hollow.wall_mm) $btX
      }
      $worst = "PASS"
      if ($throughHoles.Count -eq 0 -and $blindHoles.Count -eq 0) {
        $res = Run-GVerify $baseArgs
        $lastVerify = $res.text
        if ($res.code -ne 0) { $worst = "FAIL" } elseif ($lastVerify -match "WARNING") { $worst = "WARNING" }
      } else {
        foreach ($h in $throughHoles) {
          # Y-ekseni delikleri: Verify-Stl Z-duzlemi tabanli; Y-ekseni deligi dogrulanamaz (UNVERIFIED).
          if ([string]$h.axis -eq "y") {
            $holeChecks += [pscustomobject]@{ id = [string]$h.id; result = "UNVERIFIED"; reason = "y-ekseni deligi: Z-duzlemi dogrulamasi uygulanamaz"; expected_diameter = [double]$h.diameter_mm; expected_center = @([double]$h.center_x_mm, [double]$h.center_y_mm) }
            continue
          }
          $hargs = $baseArgs.Clone()
          $hargs.CheckHole = $true
          $hargs.HoleCX = [double]$h.center_x_mm
          $hargs.HoleCY = [double]$h.center_y_mm
          $hargs.HoleDiameter = [double]$h.diameter_mm
          $hargs.HoleZTop = $exitZ
          $vjFile = Join-Path ([System.IO.Path]::GetTempPath()) ("vrfy-" + $cid + "-" + [string]$h.id + ".json")
          $hargs.JsonOut = $vjFile
          $res = Run-GVerify $hargs
          $txt = $res.text
          $rr2 = "PASS"; if ($res.code -ne 0) { $rr2 = "FAIL" } elseif ($txt -match "WARNING") { $rr2 = "WARNING" }
          $mDia = $null; $mCen = $null
          try {
            if (Test-Path -LiteralPath $vjFile) {
              $vj = Get-Content -LiteralPath $vjFile -Raw | ConvertFrom-Json
              if ($null -ne $vj.hole_measured_diameter) { $mDia = [double]$vj.hole_measured_diameter }
              if ($null -ne $vj.hole_measured_center -and @($vj.hole_measured_center).Count -ge 2 -and $null -ne $vj.hole_measured_center[0]) {
                $mCen = @([double]$vj.hole_measured_center[0], [double]$vj.hole_measured_center[1])
              }
            }
          } catch { }
          Remove-Item -LiteralPath $vjFile -Force -ErrorAction SilentlyContinue
          $holeChecks += [pscustomobject]@{ id = [string]$h.id; result = $rr2; expected_diameter = [double]$h.diameter_mm; measured_diameter = $mDia; expected_center = @([double]$h.center_x_mm, [double]$h.center_y_mm); measured_center = $mCen }
          if ($rr2 -eq "FAIL") { $worst = "FAIL" } elseif ($rr2 -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
          $lastVerify = $txt
        }
        foreach ($h in $blindHoles) {
          # Kor delik: giris delik gecis ustunde, dip delik tabaninda aranir.
          $blindTop = [double]$expMax[2]
          if (($shape -eq "box" -or $shape -eq "rounded_box") -and $null -eq $c.hollow) {
            $blindTop = $hh
          }
          $hargs = $baseArgs.Clone()
          $hargs.CheckHole = $true
          $hargs.HoleCX = [double]$h.center_x_mm
          $hargs.HoleCY = [double]$h.center_y_mm
          $hargs.HoleDiameter = [double]$h.diameter_mm
          $hargs.HoleZTop = $blindTop
          $hargs.HoleZBottom = ($blindTop - [double]$h.depth_mm)
          $res = Run-GVerify $hargs
          $txt = $res.text
          $rr2 = "PASS"; if ($res.code -ne 0) { $rr2 = "FAIL" } elseif ($txt -match "WARNING") { $rr2 = "WARNING" }
          $holeChecks += [pscustomobject]@{ id = [string]$h.id; result = $rr2 }
          if ($rr2 -eq "FAIL") { $worst = "FAIL" } elseif ($rr2 -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
          $lastVerify = $txt
        }
      }
      # Kesik aciklik olcumu (rect; slot UNVERIFIED). Delikten bagimsiz calisir.
      foreach ($t in @($c.cutouts)) {
          if ($null -eq $t) { continue }
          $tid = [string]$t.id
          if ([string]$t.kind -eq "slot") {
            $cutoutChecks += [pscustomobject]@{ id = $tid; result = "UNVERIFIED"; reason = "slot olcumu desteklenmiyor" }
            continue
          }
          $cfBase = ([string]$t.face -replace '_short_edge$','' -replace '_long_edge$','')
          $cax = ""; $cpl = 0; $cu0 = 0; $cv0 = 0
          if ($cfBase -eq "front") { $cax = "y"; $cpl = 0; $cu0 = [double]$t.pos_x_mm; $cv0 = [double]$t.pos_y_mm }
          elseif ($cfBase -eq "rear") { $cax = "y"; $cpl = $dd; $cu0 = [double]$t.pos_x_mm; $cv0 = [double]$t.pos_y_mm }
          elseif ($cfBase -eq "top") { $cax = "z"; $cpl = $hh; $cu0 = [double]$t.pos_x_mm; $cv0 = [double]$t.pos_y_mm }
          else {
            $cutoutChecks += [pscustomobject]@{ id = $tid; result = "UNVERIFIED"; reason = ("bilinmeyen yuz: " + [string]$t.face) }
            continue
          }
          $cargs = $baseArgs.Clone()
          $cargs.CheckCutout = $true
          $cargs.CutAxis = $cax; $cargs.CutPlane = [double]$cpl
          $cargs.CutU0 = [double]$cu0; $cargs.CutV0 = [double]$cv0
          $cargs.CutW = [double]$t.width_mm; $cargs.CutL = [double]$t.length_mm
          $cvj = Join-Path ([System.IO.Path]::GetTempPath()) ("vrfy-" + $cid + "-" + $tid + ".json")
          $cargs.JsonOut = $cvj
          $cres = Run-GVerify $cargs
          $ctxt = $cres.text
          $crr = "PASS"; if ($cres.code -ne 0) { $crr = "FAIL" } elseif ($ctxt -match "WARNING") { $crr = "WARNING" }
          $mw = $null; $mpx = $null
          try {
            if (Test-Path -LiteralPath $cvj) {
              $cj = Get-Content -LiteralPath $cvj -Raw | ConvertFrom-Json
              if ($null -ne $cj.cut_measured_rect -and @($cj.cut_measured_rect).Count -ge 4 -and $null -ne $cj.cut_measured_rect[0]) {
                $mw = [math]::Round([double]$cj.cut_measured_rect[2] - [double]$cj.cut_measured_rect[0], 4)
                $mpx = [double]$cj.cut_measured_rect[0]
              }
            }
          } catch { }
          Remove-Item -LiteralPath $cvj -Force -ErrorAction SilentlyContinue
          $cutoutChecks += [pscustomobject]@{ id = $tid; result = $crr; expected_width = [double]$t.width_mm; measured_width = $mw; expected_pos_x = [double]$cu0; measured_pos_x = $mpx }
          if ($crr -eq "FAIL") { $worst = "FAIL" } elseif ($crr -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
          $lastVerify = $ctxt
        }
      $partStatus = $worst
    } while ($partStatus -eq "FAIL" -and $attempt -lt $MaxRetries)

    if ($partStatus -eq "FAIL") { $partStatus = "FAILED_AFTER_RETRIES" }

    # --- mesh kalitesi (gercek olcum; Get-MeshQuality mock degil) ---
    $meshInfo = $null
    $meshStl = Join-Path $ProjectDir (Join-Path "output" ($cid + ".stl"))
    if (Test-Path -LiteralPath $meshStl) {
      try {
        $mqTxt = & (Join-Path $EngineDir "Get-MeshQuality.ps1") -StlFile $meshStl -AsJson 2>&1 | Out-String
        $meshInfo = $mqTxt | ConvertFrom-Json
      } catch { $meshInfo = $null }
    }
    if ($null -ne $meshInfo -and [string]$meshInfo.status -eq "FAIL") {
      $partStatus = "FAILED_AFTER_RETRIES"
      $lastVerify = ($lastVerify + " | MESH-FAIL: " + (@($meshInfo.failures) -join "; "))
    }
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
  # Duvar/taban: construction metadata (mesh olcumu degil; method alani ayirir).
  $wallCheck = $null
  $baseCheck = $null
  if ($null -ne $c.hollow -and $null -ne $c.hollow.wall_mm) {
    $wallCheck = [pscustomobject]@{ method = "construction"; thickness_mm = [double]$c.hollow.wall_mm; source = "hollow.wall_mm" }
  }
  if ($null -ne $c.hollow -and $null -ne $c.hollow.bottom_thickness_mm) {
    $baseCheck = [pscustomobject]@{ method = "construction"; thickness_mm = [double]$c.hollow.bottom_thickness_mm; source = "hollow.bottom_thickness_mm" }
  }
  $meshComps = $null
  $meshStat = $null
  if ($null -ne $meshInfo) {
    $meshComps = [int]$meshInfo.connected_components
    $meshStat = [string]$meshInfo.status
  }
  Write-GValidation $ProjectDir $cid ([pscustomobject]@{
    status = $partStatus
    part = $cid
    categories = [pscustomobject]@{ geometry = $geoCat; feature = $featCat; assembly = $asmCat; manufacturability = $mfgCat }
    bbox_min = @($expMin); bbox_max = @($expMax)
    bbox_check = [pscustomobject]@{ expected_min = @($expMin); expected_max = @($expMax); tolerance_mm = $MeasurementTolerance; status = $partStatus }
    file_bytes = $(if ($stlInfo) { $stlInfo.Length } else { 0 })
    hole_checks = @($holeChecks)
    cutout_checks = @($cutoutChecks)
    expected_holes = @(@($c.holes) | Where-Object { $_ -and [string]$_.id -notlike "mp*" }).Count
    actual_holes = @(@($holeChecks) | Where-Object { $_ -and [string]$_.result -ne "UNVERIFIED" }).Count
    wall_check = $wallCheck
    base_check = $baseCheck
    connected_components = $meshComps
    mesh_status = $meshStat
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
