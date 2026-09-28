<#
.SYNOPSIS
  DesignSpec v2 dogrulama (geometry/feature/assembly/manufacturability). SADECE kontrol; DEGISTIRMEZ.
.DESCRIPTION
  HATA (BLOCKED): pozitiflik ihlalleri, eksik kritik olcu (status=missing), govde-disi delik/kesik,
    imkansiz hollow, kor-delik yuzey ihlali, joint eksikligi (clearance/vida), bilinmeyen parca/eksen/sekil.
  UYARI (uretim surer, deger korunur): ince duvar/delik/detay, tolerans yoklugu, uygulanmayan kenar
  notlari, yaklasik bbox, desteklenmeyen-ama-engelsiz durumlar.
  Cikis: 0 = hata yok, 1 = hata var. -AsJson ile JSON.
  NOT: $SpecFile (yol) / $gspecObj (veri) ayrimi zorunlu (case-insensitive carpisma yasagi).
.EXAMPLE
  powershell -File engine\Test-GeometrySpec.ps1 -SpecFile projects\x\spec.json -AsJson
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [string]$Printer = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "CanonicalSpec.ps1")
if (-not (Test-Path -LiteralPath $SpecFile)) { throw "Spec bulunamadi: $SpecFile" }
$gspecObj = ConvertTo-CanonicalSpec (Get-Content -LiteralPath $SpecFile -Raw | ConvertFrom-Json)

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$minWall = 1.2; $minFeature = 0.8; $minHole = 2.0
$printerId = ""
if ($Printer -ne "" -and (Test-Path -LiteralPath $Printer)) {
  try {
    $pj = Get-Content -LiteralPath $Printer -Raw | ConvertFrom-Json
    $printerId = $pj.id
    if ($pj.min_wall_mm -gt 0) { $minWall = [double]$pj.min_wall_mm }
    if ($pj.min_feature_mm -gt 0) { $minFeature = [double]$pj.min_feature_mm }
    if ($pj.min_hole_mm -gt 0) { $minHole = [double]$pj.min_hole_mm }
  } catch { $warnings.Add("WARNING: yazici profili okunamadi; varsayilan limitler kullanildi") }
} else {
  $warnings.Add("WARNING: yazici profili verilmedi; varsayilan limitlerle karsilastirildi")
}

$compIds = New-Object System.Collections.Generic.List[string]
foreach ($c in @($gspecObj.components)) { if ($c -and $c.id) { $compIds.Add([string]$c.id) } }
if ($compIds.Count -eq 0) { $errors.Add("hicbir bilesen tanimli degil") }

foreach ($c in @($gspecObj.components)) {
  if ($null -eq $c) { continue }
  $cid = $c.id
  $b = $c.base
  if ($null -eq $b -or $null -eq $b.shape) { $errors.Add("($cid) base.shape eksik"); continue }
  $shape = [string]$b.shape
  $knownShapes = @("box", "cylinder", "sphere", "cone", "tube", "rounded_box")
  if ($knownShapes -notcontains $shape) { $errors.Add("($cid) bilinmeyen sekil: $shape"); continue }

  function Need-Pos($v, $label) {
    if ($null -eq $v -or [double]$v -le 0) { $errors.Add("($cid) ${label}: pozitif olmali (mevcut: $v)") }
  }
  if ($shape -eq "box") { Need-Pos $b.width_mm "width_mm"; Need-Pos $b.depth_mm "depth_mm"; Need-Pos $b.height_mm "height_mm" }
  elseif ($shape -eq "cylinder") { Need-Pos $b.diameter_mm "diameter_mm"; Need-Pos $b.height_mm "height_mm" }
  elseif ($shape -eq "sphere") { Need-Pos $b.diameter_mm "diameter_mm" }
  elseif ($shape -eq "cone") { Need-Pos $b.bottom_diameter_mm "bottom_diameter_mm"; Need-Pos $b.top_diameter_mm "top_diameter_mm"; Need-Pos $b.height_mm "height_mm" }
  elseif ($shape -eq "tube") {
    Need-Pos $b.outer_diameter_mm "outer_diameter_mm"; Need-Pos $b.inner_diameter_mm "inner_diameter_mm"; Need-Pos $b.height_mm "height_mm"
    if ($null -ne $b.outer_diameter_mm -and $null -ne $b.inner_diameter_mm -and [double]$b.inner_diameter_mm -ge [double]$b.outer_diameter_mm) {
      $errors.Add("($cid) inner_diameter < outer_diameter olmali")
    }
  }
  elseif ($shape -eq "rounded_box") {
    Need-Pos $b.width_mm "width_mm"; Need-Pos $b.depth_mm "depth_mm"; Need-Pos $b.height_mm "height_mm"; Need-Pos $b.radius_mm "radius_mm"
  }

  $bw = 0; $bd = 0; $bh = 0
  if ($shape -eq "box" -or $shape -eq "rounded_box") { $bw = [double]$b.width_mm; $bd = [double]$b.depth_mm; $bh = [double]$b.height_mm }

  if ($null -ne $c.hollow) {
    $wl = $c.hollow.wall_mm
    if ($null -eq $wl -or [double]$wl -le 0) { $errors.Add("($cid) hollow.wall_mm kritik olcu eksik/gecersiz -> model olusturulamaz") }
    elseif ($shape -ne "box") { $errors.Add("($cid) hollow sadece box tabanda desteklenir") }
    elseif (2 * [double]$wl -ge $bw -or 2 * [double]$wl -ge $bd -or [double]$wl -ge $bh) {
      $errors.Add("($cid) hollow imkansiz: duvar $wl govdeye sigmyor (FAIL)")
    }
    if ($null -eq $c.hollow.open_top) { $errors.Add("($cid) hollow.open_top belirtilmemis (ustu acik mi?) -> model olusturulamaz") }
    if ($null -ne $c.hollow.bottom_thickness_mm -and $bh -gt 0 -and [double]$c.hollow.bottom_thickness_mm -ge $bh) { $errors.Add("($cid) hollow.bottom_thickness_mm govde yuksekligini asiyor -> model olusturulamaz") }
    if ($null -ne $wl -and [double]$wl -gt 0 -and [double]$wl -lt $minWall) {
      $warnings.Add("WARNING: ($cid) duvar $wl mm < limit $minWall mm; deger korundu")
    }
  }

  # Adim A: govde-ici bolme geciidi (sayi + kalinlik + sigima).
  $dpat = $c.divider_pattern
  if ($null -ne $dpat) {
    $dc = 0
    if ($null -ne $dpat.count) { $dc = [int]$dpat.count }
    if ($shape -ne "box" -and $shape -ne "rounded_box") { $errors.Add("($cid) divider_pattern yalnizca box/rounded_box tabanda desteklenir") }
    elseif ($dc -lt 1) { $errors.Add("($cid) divider_pattern.count pozitif olmali (mevcut: $($dpat.count))") }
    elseif ($null -eq $dpat.thickness_mm -or [double]$dpat.thickness_mm -le 0) { $errors.Add("($cid) divider_pattern.thickness_mm kritik olcu eksik/gecersiz -> model olusturulamaz") }
    elseif (($shape -eq "box" -or $shape -eq "rounded_box") -and $bw -gt 0) {
      $wl2 = 0
      if ($null -ne $c.hollow -and $null -ne $c.hollow.wall_mm) { $wl2 = [double]$c.hollow.wall_mm }
      if ((2 * $wl2 + $dc * [double]$dpat.thickness_mm) -gt $bw) { $errors.Add("($cid) divider_pattern sigmyor: 2*duvar + adet*kalinlik govde genisligini asiyor -> model olusturulamaz") }
    }
    if ($null -ne $dpat.top_gap_mm -and [double]$dpat.top_gap_mm -lt 0) { $errors.Add("($cid) divider_pattern.top_gap_mm negatif olamaz") }
  }

  # Adim C: cozumlulmus pattern kapsadigi deliklerin merkezini compiler uretir (gate atlar).
  $hpOK = ($null -ne $c.hole_pattern -and ([string]$c.hole_pattern.type -eq "corner_pattern" -or [string]$c.hole_pattern.type -eq "mid_edge") -and [int]$c.hole_pattern.count -ge 1 -and $null -ne $c.hole_pattern.diameter_mm -and $null -ne $c.hole_pattern.edge_offset_mm -and $bw -gt 0 -and $bd -gt 0)

  foreach ($h in @($c.holes)) {
    if ($null -eq $h) { continue }
    $hid = $h.id
    if ($null -eq $h.diameter_mm -or [double]$h.diameter_mm -le 0) { $errors.Add("($cid) delik '$hid': cap pozitif olmali"); continue }
    $dd = [double]$h.diameter_mm
    if ($dd -lt $minHole) { $warnings.Add("WARNING: ($cid) delik '$hid' capi $dd mm < min delik $minHole mm") }
    if ($h.status -eq "missing" -or $null -eq $h.center_x_mm -or $null -eq $h.center_y_mm) {
      if (-not ($hpOK -and $null -ne $h.placement)) { $errors.Add("($cid) delik '$hid': merkez kritik olcu eksik (status=missing) -> model olusturulamaz"); continue }
    }
    # Pattern kapsiyor ve merkez henuz bos: compiler cozuyor; merkez-bagimli
    # kontroller (eksen-disi konum) atlanir, merkezsiz kontroller calisir.
    $deferC = ($hpOK -and $null -ne $h.placement -and ($null -eq $h.center_x_mm -or $null -eq $h.center_y_mm))
    if ($h.axis -and $h.axis -ne "z") { $errors.Add("($cid) delik '$hid': su an sadece z ekseni desteklenir"); continue }
    $ht = "through"; if ($h.hole_type) { $ht = [string]$h.hole_type }
    if ($ht -eq "blind") {
      if ($null -eq $h.depth_mm -or [double]$h.depth_mm -le 0) { $errors.Add("($cid) delik '$hid': blind depth eksik") }
      elseif ($shape -eq "box" -and [double]$h.depth_mm -ge $bh) { $errors.Add("($cid) delik '$hid': blind depth govdeyi deliyor") }
    }
    if (($ht -eq "countersink") -and ($null -eq $h.cs_dia_mm -or $null -eq $h.cs_depth_mm)) { $errors.Add("($cid) delik '$hid': countersink olculeri eksik") }
    if (($ht -eq "counterbore") -and ($null -eq $h.cb_dia_mm -or $null -eq $h.cb_depth_mm)) { $errors.Add("($cid) delik '$hid': counterbore olculeri eksik") }
    if ($shape -eq "box" -and $bw -gt 0 -and $bd -gt 0 -and -not $deferC) {
      $rr = $dd / 2
      $cx = [double]$h.center_x_mm; $cy = [double]$h.center_y_mm
      if (($cx - $rr) -lt 0 -or ($cx + $rr) -gt $bw -or ($cy - $rr) -lt 0 -or ($cy + $rr) -gt $bd) {
        $errors.Add("($cid) delik '$hid': govde disinda kaliyor")
      }
    }
  }

  foreach ($t in @($c.cutouts)) {
    if ($null -eq $t) { continue }
    $tid = $t.id
    $twPen = ([string]$t.penetration -eq "through_wall")
    if ($t.status -eq "missing" -or $null -eq $t.width_mm -or $null -eq $t.length_mm -or ($null -eq $t.depth_mm -and -not $twPen) -or $null -eq $t.pos_x_mm -or $null -eq $t.pos_y_mm) {
      $errors.Add("($cid) kesik '$tid': olcu/konum eksik (status=missing) -> model olusturulamaz"); continue
    }
    if ([double]$t.width_mm -le 0 -or [double]$t.length_mm -le 0 -or ($null -ne $t.depth_mm -and [double]$t.depth_mm -le 0)) { $errors.Add("($cid) kesik '$tid': olculer pozitif olmali"); continue }
    $faceBase = ([string]$t.face -replace '_short_edge$','' -replace '_long_edge$','')
    if ($shape -eq "box") {
      if ($faceBase -eq "top") {
        if ([double]$t.pos_x_mm -lt 0 -or [double]$t.pos_y_mm -lt 0 -or ([double]$t.pos_x_mm + [double]$t.width_mm) -gt $bw -or ([double]$t.pos_y_mm + [double]$t.length_mm) -gt $bd -or ($null -ne $t.depth_mm -and [double]$t.depth_mm -gt $bh)) {
          $errors.Add("($cid) kesik '$tid': govde disina tasiyor")
        }
      } elseif ($faceBase -eq "front" -or $faceBase -eq "rear") {
        if ([double]$t.pos_x_mm -lt 0 -or ([double]$t.pos_x_mm + [double]$t.width_mm) -gt $bw -or [double]$t.pos_y_mm -lt 0 -or ([double]$t.pos_y_mm + [double]$t.length_mm) -gt $bh -or ($null -ne $t.depth_mm -and [double]$t.depth_mm -gt $bd)) {
          $errors.Add("($cid) kesik '$tid': govde disina tasiyor")
        }
      } else { $errors.Add("($cid) kesik '$tid': yuz top/front/rear olmali") }
    }
  }

  foreach ($e in @($c.edge_notes)) {
    if ($null -eq $e) { continue }
    if ($null -eq $e.value_mm) { $errors.Add("($cid) $($e.kind) degeri eksik -> model olusturulamaz"); continue }
    $warnings.Add("WARNING: ($cid) $($e.kind) $($e.value_mm) mm ($($e.target)) uygulanmadi; ana model korundu")
  }

  if ($null -ne $c.pending_rotate) { $errors.Add("($cid) rotate ekseni belirtilmemis -> model olusturulamaz") }
  if ($c.pending_mirror -eq $true) { $errors.Add("($cid) ayna ekseni belirtilmemis -> model olusturulamaz") }

  $rotCount = 0
  foreach ($tr in @($c.transforms)) {
    if ($null -eq $tr) { continue }
    if ($tr.op -eq "rotate") {
      foreach ($ax in @($tr.x, $tr.y, $tr.z)) { if ($null -ne $ax -and [double]$ax -ne 0) { $rotCount++ } }
    } elseif ($tr.op -eq "mirror") {
      if ($tr.axis -ne "x" -and $tr.axis -ne "y" -and $tr.axis -ne "z") { $errors.Add("($cid) ayna ekseni x/y/z olmali") }
    } elseif ($tr.op -ne "translate") { $errors.Add("($cid) bilinmeyen transform: $($tr.op)") }
  }
  if ($rotCount -gt 1) { $warnings.Add("WARNING: ($cid) cok-eksenli rotate: bbox yaklasik dogrulanir") }

  $tol = $c.tolerance
  if ($null -eq $tol) { $warnings.Add("WARNING: ($cid) tolerans belirtilmedi") }
  else {
    if ($tol.status -eq "missing" -or ($null -eq $tol.clearance_mm -and $tol.type -ne "none")) {
      $errors.Add("($cid) tolerans kritik olcu eksik (status=missing) -> model olusturulamaz")
    }
    if ($null -ne $tol.clearance_mm -and [double]$tol.clearance_mm -lt 0) {
      $errors.Add("($cid) tolerans gecersiz: clearance negatif olamaz")
    }
    if ($tol.fit_to -and ($compIds -notcontains [string]$tol.fit_to)) {
      $errors.Add("($cid) tolerans.fit_to bilinmeyen parcaya bakiyor: $($tol.fit_to)")
    }
  }
}

$asm = $gspecObj.assembly
if ($null -ne $asm) {
  foreach ($p in @($asm.parts)) { if ($compIds -notcontains [string]$p) { $errors.Add("assembly: bilinmeyen parca '$p'") } }
  foreach ($j in @($asm.joints)) {
    if ($null -eq $j) { continue }
    $knownJ = @("press_fit", "sliding_fit", "screw", "snap_fit")
    if ($knownJ -notcontains [string]$j.type) { $errors.Add("joint '$($j.id)': bilinmeyen tip") ; continue }
    if ($compIds -notcontains [string]$j.part_a -or $compIds -notcontains [string]$j.part_b) {
      $errors.Add("joint '$($j.id)': parca referansi gecersiz")
    }
    if (([string]$j.type -eq "press_fit" -or [string]$j.type -eq "sliding_fit") -and $null -eq $j.clearance_mm) {
      $errors.Add("joint '$($j.id)': $($j.type) icin clearance_mm kritik olcu eksik -> BLOCKED")
    }
    if ($null -ne $j.clearance_mm -and [double]$j.clearance_mm -lt 0) {
      $errors.Add("joint '$($j.id)': clearance negatif olamaz")
    }
    if ([string]$j.type -eq "screw" -and $null -eq $j.clearance_mm -and $null -eq $j.screw) {
      $errors.Add("joint '$($j.id)': screw icin clearance veya vida olcusu sart")
    }
    if ([string]$j.type -eq "snap_fit") { $warnings.Add("WARNING: joint '$($j.id)' snap_fit geometriye bagli; metadata olarak saklandi") }
  }
}

$status = "OK"
if ($errors.Count -gt 0) { $status = "BLOCKED" }
elseif ($warnings.Count -gt 0) { $status = "OK_WITH_WARNINGS" }

$report = [pscustomobject]@{
  status = $status; spec = $SpecFile; printer = $printerId
  errors = @($errors.ToArray()); warnings = @($warnings.ToArray())
}
if ($AsJson) { $report | ConvertTo-Json -Depth 5 }
else {
  Write-Output "DESIGN: $status"
  foreach ($e in $errors) { Write-Output "  ERROR: $e" }
  foreach ($w in $warnings) { Write-Output "  $w" }
}
if ($errors.Count -gt 0) { exit 1 } else { exit 0 }
