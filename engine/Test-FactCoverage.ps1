<#
.SYNOPSIS
  Explicit-fact coverage: facts vs DesignSpec vs questions karsilastirmasi.
.DESCRIPTION
  Iki sinif ihlal arar (bilgi kaybi):
  1. LOSS: confidence-1 fact spec'e yansimamis (parser dusurmus/degistirmis).
  2. REASK: cozumlulmus (degeri mevcut) property icin soru uretilmis.
  Cikis JSON: losses, reasks, facts, resolved, coverage_pct. Her zaman exit 0
  (advisory; GOLDEN test assert eder, pipeline trace'e yazar).
.EXAMPLE
  powershell -File engine\Test-FactCoverage.ps1 -SpecFile s.json -FactsFile f.json -QuestionsFile q.json -AsJson
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [Parameter(Mandatory = $true)][string]$FactsFile,
  [Parameter(Mandatory = $true)][string]$QuestionsFile,
  [string]$MentionsFile = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Continue"
function Load-Json($p) {
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  try { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) } catch { return $null }
}
function Num-Eq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.0001) } catch { return ([string]$a -eq [string]$b) }
}

$spec = Load-Json $SpecFile
$ff = Load-Json $FactsFile
$facts = @()
if ($null -ne $ff) {
  if ($ff.facts) { $facts = @($ff.facts) }
  elseif ($ff -is [array]) { $facts = @($ff) }
}
$qs = @()
$qraw = Load-Json $QuestionsFile
if ($null -ne $qraw) {
  if ($qraw -is [array]) { $qs = @($qraw) } else { $qs = @($qraw) }
}
$qs = @($qs | Where-Object { $_ -ne $null })

function Get-Comp($id) {
  if ($null -eq $spec -or $null -eq $spec.components) { return $null }
  foreach ($c in @($spec.components)) {
    if ($c -and [string]$c.id -eq [string]$id) { return $c }
  }
  return $null
}

$losses = New-Object System.Collections.Generic.List[string]
$resolved = 0
foreach ($f in $facts) {
  if ($null -eq $f -or [int]$f.confidence -ne 1) { continue }
  $t = [string]$f.target; $p = [string]$f.property; $v = $f.value
  $ok = $false
  if ($t -eq "body") {
    $b = Get-Comp "body"
    if ($null -ne $b -and $null -ne $b.base) {
      if ($p -eq "width" -and (Num-Eq $b.base.width_mm $v)) { $ok = $true }
      if ($p -eq "depth" -and (Num-Eq $b.base.depth_mm $v)) { $ok = $true }
      if ($p -eq "height" -and (Num-Eq $b.base.height_mm $v)) { $ok = $true }
    }
  } elseif ($t -eq "body.hollow") {
    $b = Get-Comp "body"
    if ($null -ne $b -and $null -ne $b.hollow) {
      if ($p -eq "wall_mm" -and (Num-Eq $b.hollow.wall_mm $v)) { $ok = $true }
      if ($p -eq "bottom_thickness_mm" -and (Num-Eq $b.hollow.bottom_thickness_mm $v)) { $ok = $true }
      if ($p -eq "open_top" -and $null -ne $b.hollow.open_top -and ([bool]$b.hollow.open_top -eq [bool]$v)) { $ok = $true }
    }
  } elseif ($t -eq "body.holes") {
    $b = Get-Comp "body"
    $hs = @()
    if ($null -ne $b) { $hs = @(@($b.holes) | Where-Object { $_ -ne $null -and [string]$_.id -notlike "mp*" }) }
    if ($p -eq "count" -and $hs.Count -eq [int]$v) { $ok = $true }
    if ($p -eq "diameter_mm") { foreach ($h in $hs) { if (Num-Eq $h.diameter_mm $v) { $ok = $true } } }
    if ($p -eq "hole_type") { foreach ($h in $hs) { if ([string]$h.hole_type -eq [string]$v) { $ok = $true } } }
    if ($p -eq "edge_offset_mm") { foreach ($h in $hs) { if (Num-Eq $h.edge_offset_mm $v) { $ok = $true } } }
    if ($p -eq "layout" -and [string]$v -eq "corner_pattern") { foreach ($h in $hs) { if ($null -ne $h.placement -and [string]$h.placement.type -eq "corner_pattern") { $ok = $true } } }
    if ($p -eq "cb_dia_mm") { foreach ($h in $hs) { if (Num-Eq $h.cb_dia_mm $v) { $ok = $true } } }
    if ($p -eq "cb_depth_mm") { foreach ($h in $hs) { if (Num-Eq $h.cb_depth_mm $v) { $ok = $true } } }
  } elseif ($t -eq "body.c1") {
    $b = Get-Comp "body"
    $t1 = $null
    if ($null -ne $b) { $t1 = @(@($b.cutouts) | Where-Object { $_ -ne $null } | Select-Object -First 1) }
    if ($null -ne $t1) {
      if (($p -eq "width_mm" -and (Num-Eq $t1.width_mm $v)) -or ($p -eq "length_mm" -and (Num-Eq $t1.length_mm $v)) -or ($p -eq "bottom_offset_mm" -and (Num-Eq $t1.pos_y_mm $v))) { $ok = $true }
      if ($p -eq "horizontal" -and [string]$v -eq "center" -and $null -ne $t1.placement -and [string]$t1.placement.type -eq "edge_centered") { $ok = $true }
    }
  } elseif ($t -eq "dividers") {
    $divs = @()
    if ($null -ne $spec) { $divs = @(@($spec.components) | Where-Object { $_ -and [string]$_.id -like "div*" }) }
    if ($p -eq "count" -and $divs.Count -eq [int]$v) { $ok = $true }
    if ($p -eq "thickness_mm") { $all = $true; foreach ($d in $divs) { if (-not (Num-Eq $d.thickness_mm $v)) { $all = $false } }; if ($all -and $divs.Count -gt 0) { $ok = $true } }
    if ($p -eq "top_gap_mm") { $all = $true; foreach ($d in $divs) { if (-not (Num-Eq $d.top_gap_mm $v)) { $all = $false } }; if ($all -and $divs.Count -gt 0) { $ok = $true } }
  } elseif ($t -eq "mounting") {
    $b = Get-Comp "body"
    $mps = @()
    if ($null -ne $b) { $mps = @(@($b.holes) | Where-Object { $_ -and [string]$_.id -like "mp*" }) }
    if ($p -eq "count" -and $mps.Count -eq [int]$v) { $ok = $true }
  } elseif ($t -eq "body.edge") {
    $b = Get-Comp "body"
    if ($null -ne $b) {
      if ($p -eq "fillet_mm") { foreach ($e in @($b.edge_notes)) { if ($e -and [string]$e.kind -eq "fillet" -and (Num-Eq $e.value_mm $v)) { $ok = $true } } }
      if ($p -eq "chamfer_mm") { foreach ($e in @($b.edge_notes)) { if ($e -and [string]$e.kind -eq "chamfer" -and (Num-Eq $e.value_mm $v)) { $ok = $true } } }
    }
  } elseif ($t -eq "pads") {
    $b = Get-Comp "body"
    if ($null -ne $b -and $null -ne $b.contact_pads -and @($b.contact_pads).Count -gt 0) { $ok = $true }
  } elseif ($t -eq "project" -and $p -eq "material") {
    if ($null -ne $spec -and [string]$spec.material -eq [string]$v) { $ok = $true }
  } else { $ok = $true }
  if ($ok) { $resolved++ } else { $losses.Add(($t + "." + $p + "=" + [string]$v)) }
}

# UNCONSUMED (Adim D): ham metindeki sayi ifadesi (mention) hicbir fact'e baglanmamis.
# Kural: metin-kesisimi, yoksa deger+sinif eslesmesi. Bilgi-amacli (advisory);
# exit her zaman 0, pipeline status degismez.
$mentions = @()
if ($MentionsFile -ne "" -and (Test-Path -LiteralPath $MentionsFile)) {
  try {
    $mm = Get-Content -LiteralPath $MentionsFile -Raw | ConvertFrom-Json
    if ($null -ne $mm) {
      if ($mm.mentions) { $mentions = @($mm.mentions) }
      elseif ($mm -is [array]) { $mentions = @($mm) }
    }
  } catch { $mentions = @() }
}
$measureProps = @("width", "depth", "height", "wall_mm", "bottom_thickness_mm", "diameter_mm", "edge_offset_mm", "thickness_mm", "top_gap_mm", "fillet_mm", "chamfer_mm", "clearance_mm", "depth_mm", "cb_dia_mm", "cb_depth_mm", "width_mm", "length_mm", "bottom_offset_mm")
function Test-Consumed($m) {
  $mk = [string]$m.kind; $mr = [string]$m.raw
  foreach ($f in $facts) {
    if ($null -eq $f -or [int]$f.confidence -ne 1) { continue }
    $fs = [string]$f.source
    if ($fs -ne "" -and $mr -ne "" -and ($fs.Contains($mr) -or $mr.Contains($fs))) { return $true }
  }
  if ($mk -eq "triple" -or $mk -eq "pair") {
    $elems = @($m.value)
    $allHit = $true
    foreach ($ev in $elems) {
      $hit = $false
      foreach ($f in $facts) {
        if ($null -eq $f -or [int]$f.confidence -ne 1) { continue }
        if (([string]$f.target -eq "body" -or [string]$f.target -eq "body.c1" -or [string]$f.target -eq "pads") -and (Num-Eq $f.value $ev)) { $hit = $true }
      }
      if (-not $hit) { $allHit = $false }
    }
    if ($allHit -and $elems.Count -gt 0) { return $true }
    return $false
  }
  foreach ($f in $facts) {
    if ($null -eq $f -or [int]$f.confidence -ne 1) { continue }
    $fp = [string]$f.property
    $eq = Num-Eq $f.value $m.value
    if (-not $eq) { continue }
    if ($mk -eq "count" -and $fp -eq "count") { return $true }
    if ($mk -eq "diameter" -and ($fp -eq "diameter_mm" -or $fp -eq "cb_dia_mm")) { return $true }
    if ($mk -eq "measure" -and $measureProps -contains $fp) { return $true }
  }
  return $false
}
$unconsumed = New-Object System.Collections.Generic.List[string]
foreach ($m in $mentions) {
  if ($null -eq $m) { continue }
  if (-not (Test-Consumed $m)) { $unconsumed.Add(([string]$m.id + " [" + [string]$m.kind + "] " + [string]$m.raw)) }
}

$reasks = New-Object System.Collections.Generic.List[string]
foreach ($q in $qs) {
  $kind = [string]$q.kind; $tgt = [string]$q.target
  $segs = @($tgt -split '\.')
  $cid = $segs[0]
  $c = Get-Comp $cid
  $isResolved = $false
  if ($kind -eq "dims" -and $null -ne $c -and $null -ne $c.base) {
    $isResolved = ($null -ne $c.base.width_mm -and $null -ne $c.base.depth_mm -and $null -ne $c.base.height_mm)
  } elseif (($kind -eq "hole_dia" -or $kind -eq "hole_center" -or $kind -eq "hole_depth" -or $kind -eq "hole_extra") -and $null -ne $c) {
    $hid = ""; $hi = [array]::IndexOf($segs, "hole")
    if ($hi -ge 0 -and ($hi + 1) -lt $segs.Count) { $hid = $segs[$hi + 1] }
    foreach ($h in @($c.holes)) {
      if ($h -and [string]$h.id -eq $hid) {
        if ($kind -eq "hole_dia" -and $null -ne $h.diameter_mm) { $isResolved = $true }
        if ($kind -eq "hole_center" -and [string]$h.status -eq "ok" -and $null -ne $h.center_x_mm -and $null -ne $h.center_y_mm) { $isResolved = $true }
        if ($kind -eq "hole_depth" -and $null -ne $h.depth_mm) { $isResolved = $true }
        if ($kind -eq "hole_extra") {
          if ([string]$h.hole_type -eq "countersink" -and $null -ne $h.cs_dia_mm -and $null -ne $h.cs_depth_mm) { $isResolved = $true }
          if ([string]$h.hole_type -eq "counterbore" -and $null -ne $h.cb_dia_mm -and $null -ne $h.cb_depth_mm) { $isResolved = $true }
        }
      }
    }
  } elseif ($kind -eq "hollow_top" -and $null -ne $c -and $null -ne $c.hollow -and $null -ne $c.hollow.open_top) { $isResolved = $true }
  elseif ($kind -eq "cutout" -and $null -ne $c) {
    $tid = [string]$q.field -replace '^cutouts\.', ''
    foreach ($tt in @($c.cutouts)) {
      if ($tt -and [string]$tt.id -eq $tid) {
        $dOk = ($null -ne $tt.depth_mm -or [string]$tt.penetration -eq "through_wall")
        if ([string]$tt.status -eq "ok" -and $null -ne $tt.width_mm -and $null -ne $tt.length_mm -and $null -ne $tt.pos_x_mm -and $null -ne $tt.pos_y_mm -and $dOk) { $isResolved = $true }
      }
    }
  } elseif ($kind -eq "wall" -and $null -ne $c -and $null -ne $c.hollow -and $null -ne $c.hollow.wall_mm) { $isResolved = $true }
  elseif ($kind -eq "lid_height" -and $null -ne $c -and $null -ne $c.base -and $null -ne $c.base.height_mm) { $isResolved = $true }
  elseif (($kind -eq "clearance" -or $kind -eq "joint_clearance") -and $null -ne $c -and $null -ne $c.tolerance -and $null -ne $c.tolerance.clearance_mm) { $isResolved = $true }
  elseif (($kind -eq "rotate_axis" -and $null -eq $c.pending_rotate) -or ($kind -eq "mirror_axis" -and $c.pending_mirror -ne $true)) { $isResolved = $true }
  elseif ($kind -eq "edge_value") {
    $ek = ($tgt -split '\.')[-1]
    foreach ($e in @($c.edge_notes)) { if ($e -and [string]$e.kind -eq $ek -and $null -ne $e.value_mm) { $isResolved = $true } }
  }
  if ($isResolved) { $reasks.Add(([string]$q.question_id + " (" + $kind + ") cozulu property'yi tekrar soruyor")) }
}

$pct = 100
if ($facts.Count -gt 0) { $pct = [Math]::Round(100.0 * $resolved / $facts.Count, 1) }
$rep = [pscustomobject]@{
  facts = $facts.Count; resolved = $resolved; coverage_pct = $pct
  losses = @($losses.ToArray()); reasks = @($reasks.ToArray())
  mentions = $mentions.Count; unconsumed = @($unconsumed.ToArray())
}
if ($AsJson) { $rep | ConvertTo-Json -Depth 4 }
else {
  Write-Output ("COVERAGE: " + $resolved + "/" + $facts.Count + " (" + $pct + "%)")
  foreach ($e in $losses) { Write-Output ("  LOSS: " + $e) }
  foreach ($e in $reasks) { Write-Output ("  REASK: " + $e) }
  foreach ($e in $unconsumed) { Write-Output ("  UNCONSUMED: " + $e) }
}
exit 0
