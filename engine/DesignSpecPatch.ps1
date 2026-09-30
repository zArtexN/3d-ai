<#
.SYNOPSIS
  DesignSpec patch kutuphanesi (Phase 3, Adim C- onceki adlarla karismasin).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok; dot-source ile ice
  aktarilir, caller scope kirletmez.
  Op formati: @{ op=replace|remove|add; path="body.base.width_mm";
    old=<beklenen mevcut>; value=<yeni>; reason="..."; requires_confirmation=$false }
  Kurallar: allowlist disi path REJECT; old uyusmazsa REJECT; tip/birim/aralik
  kontrolu; disabled_features celiskisi REJECT; sirali batch atomic uygulanir
  (orchestrator once hepsini validate eder).
  Birimler: yalnizca sayisal mm degerler kabul edilir (string birim REJECT).
#>

function Get-SpecPathValue($spec, $path) {
  $segs = @([string]$path -split '\.')
  if ($segs.Count -lt 2) { return @{ found = $false; value = $null } }
  $cid = $segs[0]
  $comp = $null
  foreach ($c in @($spec.components)) {
    if ($c -and [string]$c.id -eq $cid) { $comp = $c; break }
  }
  if ($null -eq $comp) { return @{ found = $false; value = $null } }
  $rest = $segs[1..($segs.Count - 1)]
  if ($rest.Count -eq 2 -and $rest[0] -in @("base", "hollow", "tolerance", "divider_pattern")) {
    $obj = $comp.($rest[0])
    if ($null -eq $obj) { return @{ found = $false; value = $null } }
    return @{ found = ($null -ne $obj.($rest[1])); value = $obj.($rest[1]) }
  }
  if ($rest.Count -eq 3 -and $rest[0] -in @("holes", "cutouts")) {
    $arr = @($comp.($rest[0]))
    foreach ($it in $arr) {
      if ($it -and [string]$it.id -eq $rest[1]) {
        return @{ found = ($null -ne $it.($rest[2])); value = $it.($rest[2]) }
      }
    }
    return @{ found = $false; value = $null }
  }
  if ($rest.Count -eq 2 -and $rest[0] -eq "edge_notes") {
    foreach ($en in @($comp.edge_notes)) {
      if ($en -and [string]$en.kind -eq $rest[1]) {
        return @{ found = ($null -ne $en.value_mm); value = $en.value_mm }
      }
    }
    return @{ found = $false; value = $null }
  }
  return @{ found = $false; value = $null }
}

function Test-PatchPathAllowed($path, $op) {
  $p = [string]$path
  if ($op -eq "remove") {
    if ($p -match '^[a-z0-9_]+\.cutouts\.[a-z0-9_]+$') { return $true }
    if ($p -match '^[a-z0-9_]+\.holes\.[a-z0-9_]+$') { return $true }
    if ($p -match '^[a-z0-9_]+\.edge_notes\.(fillet|chamfer)$') { return $true }
    return $false
  }
  if ($op -eq "add") {
    if ($p -match '^[a-z0-9_]+\.holes$') { return $true }
    return $false
  }
  if ($p -match '^[a-z0-9_]+\.base\.(width_mm|depth_mm|height_mm|diameter_mm)$') { return $true }
  if ($p -match '^[a-z0-9_]+\.hollow\.(wall_mm|bottom_thickness_mm)$') { return $true }
  if ($p -match '^[a-z0-9_]+\.holes\.[a-z0-9_]+\.(diameter_mm|depth_mm)$') { return $true }
  if ($p -match '^[a-z0-9_]+\.holes\.[a-z0-9_]+\.center$') { return $true }
  if ($p -match '^[a-z0-9_]+\.cutouts\.[a-z0-9_]+\.(width_mm|length_mm|pos_x_mm|pos_y_mm|depth_mm)$') { return $true }
  if ($p -match '^[a-z0-9_]+\.tolerance\.clearance_mm$') { return $true }
  if ($p -match '^[a-z0-9_]+\.divider_pattern\.(count|thickness_mm|top_gap_mm)$') { return $true }
  if ($p -match '^[a-z0-9_]+\.edge_notes\.(fillet|chamfer)$') { return $true }
  return $false
}

function Test-PatchValueNumber($v) {
  if ($null -eq $v) { return $false }
  try { [void][double]$v; return $true } catch { return $false }
}

function Test-PatchOp($spec, $op) {
  $opName = [string]$op.op
  $path = [string]$op.path
  if ($opName -ne "replace" -and $opName -ne "remove" -and $opName -ne "add") {
    return @{ ok = $false; message = ("bilinmeyen op: " + $opName) }
  }
  if (-not (Test-PatchPathAllowed $path $opName)) {
    return @{ ok = $false; message = ("izin verilmeyen path: " + $path) }
  }
  $dis = @()
  if ($null -ne $spec.disabled_features) { $dis = @($spec.disabled_features) }
  $segs = @($path -split '\.')
  $feat = ""
  if ($segs.Count -ge 2) {
    if ($segs[1] -eq "holes") { $feat = "hole" }
    elseif ($segs[1] -eq "cutouts") { $feat = "slot" }
    elseif ($segs[1] -eq "edge_notes" -and $segs.Count -ge 3) {
      if ($segs[2] -eq "fillet") { $feat = "fillet" }
      elseif ($segs[2] -eq "chamfer") { $feat = "chamfer" }
    }
    elseif ($segs[1] -eq "divider_pattern") { $feat = "slot" }
  }
  if ($opName -eq "add" -and $feat -ne "" -and $dis -contains $feat) {
    return @{ ok = $false; message = ("ret edilen feature eklenemez: " + $feat) }
  }
  if ($opName -eq "remove") {
    $cur = Get-SpecPathValue $spec $path
    if (-not $cur.found) { return @{ ok = $false; message = ("kaldirilacak hedef yok: " + $path) } }
    return @{ ok = $true; message = "ok" }
  }
  if ($opName -eq "add") {
    $hv = $op.value
    if ($null -eq $hv -or $null -eq $hv.diameter_mm) {
      return @{ ok = $false; message = "eklenecek hole eksik (diameter_mm sart)" }
    }
    if (-not (Test-PatchValueNumber $hv.diameter_mm) -or [double]$hv.diameter_mm -le 0) {
      return @{ ok = $false; message = "eklenecek hole capi pozitif olmali" }
    }
    return @{ ok = $true; message = "ok" }
  }
  $cur = Get-SpecPathValue $spec $path
  $creatable = ($path -match '\.edge_notes\.(fillet|chamfer)$')
  if (-not $creatable -and -not $cur.found) { return @{ ok = $false; message = ("hedef alan yok: " + $path) } }
  if ($null -ne $op.old) {
    $same = $false
    try {
      if ($op.old -is [array] -and $cur.value -is [array]) {
        $same = (([double]$op.old[0] -eq [double]$cur.value[0]) -and ([double]$op.old[1] -eq [double]$cur.value[1]))
      } else { $same = ([double]$op.old -eq [double]$cur.value) }
    } catch { $same = ([string]$op.old -eq [string]$cur.value) }
    if (-not $same) { return @{ ok = $false; message = ("old deger uyusmuyor: " + $path) } }
  }
  $nv = $op.value
  $isCenter = ($path -match '\.center$')
  $isCount = ($path -match 'divider_pattern\.count$')
  if ($isCenter) {
    if ($nv -isnot [array] -or @($nv).Count -ne 2) { return @{ ok = $false; message = "center [x,y] cifti olmali" } }
    foreach ($e in @($nv)) {
      if (-not (Test-PatchValueNumber $e)) { return @{ ok = $false; message = "center sayisal olmali" } }
    }
  } elseif ($isCount) {
    try { if ([int]$nv -lt 1) { return @{ ok = $false; message = "count pozitif tamsayi olmali" } } }
    catch { return @{ ok = $false; message = "count pozitif tamsayi olmali" } }
  } else {
    if (-not (Test-PatchValueNumber $nv)) { return @{ ok = $false; message = ("sayisal deger gerekli (birim mm): " + $path) } }
    $isClear = ($path -match 'clearance_mm$')
    if (-not $isClear -and [double]$nv -le 0) { return @{ ok = $false; message = ("pozitif olcu gerekli: " + $path) } }
    if ($isClear -and [double]$nv -lt 0) { return @{ ok = $false; message = ("clearance negatif olamaz: " + $path) } }
  }
  return @{ ok = $true; message = "ok" }
}

function Invoke-PatchOp($spec, $op) {
  $copy = $spec | ConvertTo-Json -Depth 12 | ConvertFrom-Json
  $opName = [string]$op.op
  $path = [string]$op.path
  $segs = @($path -split '\.')
  $comp = $null
  foreach ($c in @($copy.components)) {
    if ($c -and [string]$c.id -eq $segs[0]) { $comp = $c; break }
  }
  if ($null -eq $comp) { throw "component yok: $($segs[0])" }
  if ($opName -eq "remove") {
    if ($segs[1] -eq "holes" -or $segs[1] -eq "cutouts") {
      $arr = @(@($comp.($segs[1])) | Where-Object { $_ -and [string]$_.id -ne $segs[2] })
      $comp.($segs[1]) = @($arr)
    } elseif ($segs[1] -eq "edge_notes") {
      $arr = @(@($comp.edge_notes) | Where-Object { $_ -and [string]$_.kind -ne $segs[2] })
      $comp.edge_notes = @($arr)
    }
    return $copy
  }
  if ($opName -eq "add") {
    $hv = $op.value | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    $used = @()
    foreach ($h in @($comp.holes)) { if ($h -and $h.id -match '^h(\d+)$') { $used += [int]$Matches[1] } }
    $nid = 1
    while ($used -contains $nid) { $nid++ }
    $hv | Add-Member -NotePropertyName "id" -NotePropertyValue ("h" + $nid) -Force
    if ($null -eq $hv.status) { $hv | Add-Member -NotePropertyName "status" -NotePropertyValue "ok" -Force }
    $comp.holes = @(@($comp.holes) + @($hv))
    return $copy
  }
  $rest = $segs[1..($segs.Count - 1)]
  if ($rest.Count -eq 2 -and $rest[0] -in @("base", "hollow", "tolerance", "divider_pattern")) {
    $target = $comp.($rest[0])
    if ($null -eq $target) {
      $target = [pscustomobject]@{}
      $comp | Add-Member -NotePropertyName $rest[0] -NotePropertyValue $target -Force
    }
    $target.($rest[1]) = $op.value
    return $copy
  }
  if ($rest.Count -eq 3 -and $rest[0] -in @("holes", "cutouts")) {
    foreach ($it in @($comp.($rest[0]))) {
      if ($it -and [string]$it.id -eq $rest[1]) {
        if ($rest[2] -eq "center") {
          $it.center_x_mm = [double]@($op.value)[0]
          $it.center_y_mm = [double]@($op.value)[1]
        } else {
          $it.($rest[2]) = $op.value
        }
      }
    }
    return $copy
  }
  if ($rest.Count -eq 2 -and $rest[0] -eq "edge_notes") {
    $foundEn = $false
    foreach ($en in @($comp.edge_notes)) {
      if ($en -and [string]$en.kind -eq $rest[1]) { $en.value_mm = [double]$op.value; $foundEn = $true }
    }
    if (-not $foundEn) {
      $comp.edge_notes = @(@($comp.edge_notes) + @([pscustomobject]@{ kind = $rest[1]; value_mm = [double]$op.value; target = "kenarlar" }))
    }
    return $copy
  }
  throw ("uygulanamayan path: " + $path)
}

function Compare-Spec($a, $b) {
  $changed = New-Object System.Collections.Generic.List[object]
  $unchanged = 0
  $ja = $a | ConvertTo-Json -Depth 12 -Compress
  $jb = $b | ConvertTo-Json -Depth 12 -Compress
  if ($ja -eq $jb) { return @{ changed = @(); unchanged_count = -1; changed_paths = @() } }
  $paths = New-Object System.Collections.Generic.List[string]
  foreach ($c in @($b.components)) {
    if ($null -eq $c -or $null -eq $c.id) { continue }
    $cid = [string]$c.id
    foreach ($f in @("base.width_mm", "base.depth_mm", "base.height_mm", "base.diameter_mm", "hollow.wall_mm", "hollow.bottom_thickness_mm", "tolerance.clearance_mm", "divider_pattern.count", "divider_pattern.thickness_mm", "divider_pattern.top_gap_mm")) {
      $paths.Add(($cid + "." + $f)) | Out-Null
    }
    foreach ($h in @($c.holes)) {
      if ($h -and $h.id) {
        $paths.Add(($cid + ".holes." + [string]$h.id + ".diameter_mm")) | Out-Null
        $paths.Add(($cid + ".holes." + [string]$h.id + ".center")) | Out-Null
        $paths.Add(($cid + ".holes." + [string]$h.id + ".depth_mm")) | Out-Null
      }
    }
    foreach ($t in @($c.cutouts)) {
      if ($t -and $t.id) {
        foreach ($f in @("width_mm", "length_mm", "pos_x_mm", "pos_y_mm", "depth_mm")) {
          $paths.Add(($cid + ".cutouts." + [string]$t.id + "." + $f)) | Out-Null
        }
      }
    }
    foreach ($en in @($c.edge_notes)) {
      if ($en -and $en.kind) { $paths.Add(($cid + ".edge_notes." + [string]$en.kind)) | Out-Null }
    }
  }
  foreach ($p in $paths) {
    $va = Get-SpecPathValue $a $p
    $vb = Get-SpecPathValue $b $p
    $sa = ""; $sb = ""
    try { $sa = ($va.value | ConvertTo-Json -Compress) } catch { $sa = [string]$va.value }
    try { $sb = ($vb.value | ConvertTo-Json -Compress) } catch { $sb = [string]$vb.value }
    if ($va.found -or $vb.found) {
      if ($sa -ne $sb) {
        $changed.Add([pscustomobject]@{ path = $p; old = $va.value; new = $vb.value }) | Out-Null
      } else { $unchanged++ }
    }
  }
  return @{ changed = @($changed.ToArray()); unchanged_count = $unchanged; changed_paths = @($changed | ForEach-Object { $_.path }) }
}

function Get-CriticalPaths() {
  return @(
    '*.base.width_mm', '*.base.depth_mm', '*.base.height_mm', '*.base.diameter_mm',
    '*.hollow.wall_mm', '*.hollow.bottom_thickness_mm',
    '*.holes.*.diameter_mm', '*.holes.*.center', '*.holes.*.depth_mm',
    '*.divider_pattern.count', '*.divider_pattern.thickness_mm',
    '*.tolerance.clearance_mm',
    '*.cutouts.*.width_mm', '*.cutouts.*.length_mm', '*.cutouts.*.pos_x_mm',
    '*.cutouts.*.pos_y_mm', '*.cutouts.*.depth_mm'
  )
}

function Format-CriticalDiff($diff) {
  $lines = New-Object System.Collections.Generic.List[string]
  foreach ($ch in @($diff.changed)) {
    $o = [string]$ch.old; $n = [string]$ch.new
    $delta = ""
    try {
      if ($ch.old -is [array] -or $ch.new -is [array]) {
        $oa = @($ch.old); $na = @($ch.new)
        if ($oa.Count -eq 2 -and $na.Count -eq 2) {
          $dx = [math]::Round([double]$na[0] - [double]$oa[0], 4)
          $dy = [math]::Round([double]$na[1] - [double]$oa[1], 4)
          $delta = (" (delta " + $dx + "," + $dy + ")")
        }
      } else {
        $dd = [math]::Round([double]$n - [double]$o, 4)
        if ($dd -gt 0) { $delta = (" (delta +" + $dd + ")") }
        elseif ($dd -lt 0) { $delta = (" (delta " + $dd + ")") }
      }
    } catch { }
    $lines.Add(([string]$ch.path + ": " + $o + " -> " + $n + $delta + " mm")) | Out-Null
  }
  return @($lines.ToArray())
}
