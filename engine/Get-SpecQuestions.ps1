<#
.SYNOPSIS
  DesignSpec v2'deki kritik eksikleri soru listesine cevirir. Degisiklik YAPMAZ.
.DESCRIPTION
  Her soru: question_id, component, field, target, kind, question, reason,
  answer (null), source (null), asked_at (null).
  kind degerleri: dims, wall, hole_center, hole_depth, hole_extra, cutout,
  clearance, joint_clearance, lid_height, hole_dia.
  Kritik = geometri/montaji dogrudan etkileyen (olcu, konum, tolerans).
.EXAMPLE
  powershell -File engine\Get-SpecQuestions.ps1 -SpecFile projects\x\spec.json -AsJson
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $SpecFile)) { throw "Spec bulunamadi: $SpecFile" }
$qspecObj = Get-Content -LiteralPath $SpecFile -Raw | ConvertFrom-Json

$qlist = New-Object System.Collections.Generic.List[object]
function Add-Q($comp, $field, $target, $kind, $q, $reason) {
  $n = ($qlist.Count + 1)
  $qid = ("q" + $n)
  $qlist.Add([pscustomobject]@{
    question_id = $qid; component = $comp; field = $field; target = $target; kind = $kind
    question = $q; reason = $reason; answer = $null; source = $null; asked_at = $null
  })
}

$comps = @($qspecObj.components)
if ($comps.Count -eq 0 -or ($comps.Count -eq 1 -and $null -eq $comps[0])) {
  Add-Q "-" "components" "components" "dims" "Modelde hic parca yok. Ornek: 80x40x20 kutu." "parca olmadan geometri uretilemez"
} else {
  foreach ($c in $comps) {
    if ($null -eq $c) { continue }
    $cid = [string]$c.id
    $b = $c.base
    $shape = ""; if ($b -and $b.shape) { $shape = [string]$b.shape }
    $dimMissing = $false
    if ($shape -eq "box" -or $shape -eq "rounded_box") {
      if ($null -eq $b.width_mm -or $null -eq $b.depth_mm -or $null -eq $b.height_mm) { $dimMissing = $true }
    } elseif ($shape -eq "cylinder") {
      if ($null -eq $b.diameter_mm -or $null -eq $b.height_mm) { $dimMissing = $true }
    } elseif ($shape -eq "sphere") {
      if ($null -eq $b.diameter_mm) { $dimMissing = $true }
    } elseif ($shape -eq "cone") {
      if ($null -eq $b.bottom_diameter_mm -or $null -eq $b.top_diameter_mm -or $null -eq $b.height_mm) { $dimMissing = $true }
    } elseif ($shape -eq "tube") {
      if ($null -eq $b.outer_diameter_mm -or $null -eq $b.inner_diameter_mm -or $null -eq $b.height_mm) { $dimMissing = $true }
    } else { $dimMissing = $true }
    if ($dimMissing) {
      $kind = "dims"; if ($cid -eq "lid") { $kind = "lid_height" }
      Add-Q $cid "base.dims" ($cid + ".dims") $kind ("'" + $cid + "' parcasi olculeri eksik. Ornek: 80x40x20 (mm).") "dis olcu olmadan govde uretilemez"
    }
    if ($null -ne $c.hollow -and $null -eq $c.hollow.wall_mm) {
      Add-Q $cid "hollow.wall_mm" ($cid + ".wall") "wall" ("'" + $cid + "' duvar kalinligi nedir? Ornek: duvar 2.5.") "duvar olmadan ici-bos geometri uretilemez; deger uydurulamaz"
    }
    if ($null -ne $c.hollow -and $null -eq $c.hollow.open_top) {
      Add-Q $cid "hollow.open_top" ($cid + ".hollow_top") "hollow_top" ("'" + $cid + "' ustu acik mi kapali mi? Cevap: acik / kapali.") "ic bosluk yonune karar verilmeden geometri kurulamaz"
    }
    if ($null -ne $c.pending_rotate) {
      Add-Q $cid "pending_rotate" ($cid + ".rotate_axis") "rotate_axis" ("Hangi eksende " + [string]$c.pending_rotate + " derece dondureyim? Cevap: X / Y / Z.") "eksen kritik; uydurulamaz"
    }
    if ($c.pending_mirror -eq $true) {
      Add-Q $cid "pending_mirror" ($cid + ".mirror_axis") "mirror_axis" ("Hangi eksene gore ayna? Cevap: X / Y / Z.") "eksen kritik; uydurulamaz"
    }
    foreach ($h in @($c.holes)) {
      if ($null -eq $h) { continue }
      $hid = [string]$h.id
      if ($null -eq $h.diameter_mm) {
        Add-Q $cid ("holes." + $hid + ".diameter_mm") ($cid + ".hole." + $hid + ".dia") "hole_dia" ("Delik '" + $hid + "' capi nedir? Ornek: delik 20.") "cap olmadan delik acilamaz"
      }
      if ($h.status -eq "missing" -or $null -eq $h.center_x_mm -or $null -eq $h.center_y_mm) {
        Add-Q $cid ("holes." + $hid + ".center") ($cid + ".hole." + $hid + ".center") "hole_center" ("Delik '" + $hid + "' merkezi nerede? Ornek: merkez 15,15 (referans koseden mm).") "konum kritik; uydurulamaz"
      }
      $ht = "through"; if ($h.hole_type) { $ht = [string]$h.hole_type }
      if ($ht -eq "blind" -and $null -eq $h.depth_mm) {
        Add-Q $cid ("holes." + $hid + ".depth_mm") ($cid + ".hole." + $hid + ".depth") "hole_depth" ("Kor delik '" + $hid + "' derinligi nedir? Ornek: derinlik 5.") "derinlik olmadan kor delik acilamaz"
      }
      if ($ht -eq "countersink" -and ($null -eq $h.cs_dia_mm -or $null -eq $h.cs_depth_mm)) {
        Add-Q $cid ("holes." + $hid + ".cs") ($cid + ".hole." + $hid + ".cs") "hole_extra" ("Havsa olculeri nedir? Ornek: havsa cap 10 derinlik 3.") "havsa geometrisi olcusuz uretilemez"
      }
      if ($ht -eq "counterbore" -and ($null -eq $h.cb_dia_mm -or $null -eq $h.cb_depth_mm)) {
        Add-Q $cid ("holes." + $hid + ".cb") ($cid + ".hole." + $hid + ".cb") "hole_extra" ("Gomme olculeri nedir? Ornek: gomme cap 10 derinlik 3.") "gomme geometrisi olcusuz uretilemez"
      }
    }
    foreach ($t in @($c.cutouts)) {
      if ($null -eq $t) { continue }
      $tid = [string]$t.id
      if ($t.status -eq "missing" -or $null -eq $t.pos_x_mm -or $null -eq $t.pos_y_mm -or $null -eq $t.width_mm -or $null -eq $t.length_mm -or $null -eq $t.depth_mm) {
        Add-Q $cid ("cutouts." + $tid) ($cid + ".cutout." + $tid) "cutout" ("Kesik '" + $tid + "' olcu/konum/derinlik nedir? Ornek: 20x10, konum 5,5, derinlik 8.") "konumsuz kesik cikarilamaz"
      }
    }
    $tol = $c.tolerance
    if ($null -ne $tol -and ($tol.status -eq "missing" -or ($null -eq $tol.clearance_mm -and $tol.type -ne "none"))) {
      Add-Q $cid "tolerance.clearance_mm" ($cid + ".clearance") "clearance" ("'" + $cid + "' gecme boslugu kac mm? Ornek: 0.2 mm bosluk.") "kritik tolerans uydurulamaz"
    }
    foreach ($e in @($c.edge_notes)) {
      if ($e -and $null -eq $e.value_mm) {
        Add-Q $cid ("edge." + [string]$e.kind) ($cid + ".edge." + [string]$e.kind) "edge_value" ("Kenar islemi (" + [string]$e.kind + ") olcusu kac mm? Ornek: 3.") "olcusuz kenar islemi uygulanamaz"
      }
    }
  }
}

$asm = $qspecObj.assembly
if ($null -ne $asm) {
  foreach ($j in @($asm.joints)) {
    if ($null -eq $j) { continue }
    $jt = [string]$j.type
    if (($jt -eq "press_fit" -or $jt -eq "sliding_fit") -and $null -eq $j.clearance_mm) {
      Add-Q ([string]$j.part_b) ("joints." + [string]$j.id) ("joint." + [string]$j.id) "joint_clearance" ("Baglanti '" + [string]$j.id + "' (" + [string]$j.part_a + "+" + [string]$j.part_b + ") boslugu kac mm? Ornek: 0.2 mm.") "gecme payi olmadan montaj uretilemez"
    }
    if ($jt -eq "screw" -and $null -eq $j.clearance_mm -and $null -eq $j.screw) {
      Add-Q ([string]$j.part_b) ("joints." + [string]$j.id) ("joint." + [string]$j.id) "joint_clearance" ("Vida baglantisi '" + [string]$j.id + "' icin olcu nedir? Ornek: M4 veya bosluk 0.2 mm.") "vida olcusu olmadan delik acilamaz"
    }
  }
}

$arr = @($qlist.ToArray() | Where-Object { $_ -ne $null })
if ($AsJson) {
  if ($arr.Count -eq 0) { "[]" }
  else { $arr | ConvertTo-Json -Depth 4 }
}
else {
  Write-Output "SORU-SAYISI: $($arr.Count)"
  foreach ($q in $arr) { Write-Output "SORU [$($q.question_id)]: $($q.question) (neden: $($q.reason))" }
}
