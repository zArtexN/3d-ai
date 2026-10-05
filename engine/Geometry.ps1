<#
.SYNOPSIS
  Geometry abstraction layer (V1.1). OpenSCAD kodu ureten saf fonksiyonlar; dosya yazmaz.
.DESCRIPTION
  Her geometri: @{ kind; scad (string); bmin [x,y,z]; bmax [x,y,z]; notes [] }.
  bbox tum transformlardan gecer (sadece tek-eksen 90-kati rotate kesin; cok-eksenlide yaklasik + uyari).
  Sayilar InvariantCulture ile formatlanir (tr locale ondalik virgule karsi).
  Kurallar: pozitiflik kontrolu ctor icinde (hata -> throw, acik mesaj); kritik olcu burada UYDURULMAZ.
.NOTLAR
  $G prefix'i degisken carpismasini onler. Cift tirnak icinde backtick YOK.
#>

function Format-Num($n) {
  return ([double]$n).ToString([System.Globalization.CultureInfo]::InvariantCulture)
}
function New-GObj($kind, $scad, $bmin, $bmax, $notes) {
  if ($null -eq $notes) { $notes = @() }
  return [pscustomobject]@{ kind = $kind; scad = $scad; bmin = $bmin; bmax = $bmax; notes = @($notes) }
}
function Assert-Pos($name, $v) {
  if ($null -eq $v -or [double]$v -le 0) { throw "geometry: $name pozitif olmali (mevcut: $v)" }
}

# ---- primitive ----
function New-GBox($w, $d, $h) {
  Assert-Pos "width" $w; Assert-Pos "depth" $d; Assert-Pos "height" $h
  $s = "cube([" + (Format-Num $w) + ", " + (Format-Num $d) + ", " + (Format-Num $h) + "]);"
  return (New-GObj "box" $s @(0, 0, 0) @([double]$w, [double]$d, [double]$h) $null)
}
function New-GCylinder($dia, $h, $axis) {
  Assert-Pos "diameter" $dia; Assert-Pos "height" $h
  if ($null -eq $axis -or $axis -eq "") { $axis = "z" }
  $r = [double]$dia / 2
  if ($axis -eq "z") {
    $s = "cylinder(d = " + (Format-Num $dia) + ", h = " + (Format-Num $h) + ");"
    return (New-GObj "cylinder" $s @(-$r, -$r, 0) @($r, $r, [double]$h) $null)
  } elseif ($axis -eq "x") {
    $s = "rotate([0, 90, 0]) cylinder(d = " + (Format-Num $dia) + ", h = " + (Format-Num $h) + ");"
    return (New-GObj "cylinder" $s @(0, -$r, -$r) @([double]$h, $r, $r) $null)
  } elseif ($axis -eq "y") {
    $s = "rotate([-90, 0, 0]) cylinder(d = " + (Format-Num $dia) + ", h = " + (Format-Num $h) + ");"
    return (New-GObj "cylinder" $s @(-$r, 0, -$r) @($r, [double]$h, $r) $null)
  } else { throw "geometry: eksen z/x/y olmali (mevcut: $axis)" }
}
function New-GSphere($dia) {
  Assert-Pos "diameter" $dia
  $r = [double]$dia / 2
  $s = "sphere(d = " + (Format-Num $dia) + ");"
  return (New-GObj "sphere" $s @(-$r, -$r, -$r) @($r, $r, $r) $null)
}
function New-GCone($dBottom, $dTop, $h) {
  Assert-Pos "dBottom" $dBottom; Assert-Pos "dTop" $dTop; Assert-Pos "height" $h
  $r = [math]::Max([double]$dBottom, [double]$dTop) / 2
  $s = "cylinder(d1 = " + (Format-Num $dBottom) + ", d2 = " + (Format-Num $dTop) + ", h = " + (Format-Num $h) + ");"
  return (New-GObj "cone" $s @(-$r, -$r, 0) @($r, $r, [double]$h) $null)
}
function New-GTube($od, $id, $h) {
  Assert-Pos "outer_diameter" $od; Assert-Pos "inner_diameter" $id; Assert-Pos "height" $h
  if ([double]$id -ge [double]$od) { throw "geometry: inner_diameter < outer_diameter olmali ($id >= $od)" }
  $r = [double]$od / 2
  $s = "difference() { cylinder(d = " + (Format-Num $od) + ", h = " + (Format-Num $h) + "); translate([0, 0, -1]) cylinder(d = " + (Format-Num $id) + ", h = " + (Format-Num ([double]$h + 2)) + "); }"
  return (New-GObj "tube" $s @(-$r, -$r, 0) @($r, $r, [double]$h) $null)
}
function New-GRoundedBox($w, $d, $h, $r) {
  Assert-Pos "width" $w; Assert-Pos "depth" $d; Assert-Pos "height" $h; Assert-Pos "radius" $r
  if (2 * [double]$r -gt [math]::Min([double]$w, [math]::Min([double]$d, [double]$h))) { throw "geometry: 2*radius en kucuk olcuden buyuk olamaz" }
  $iw = Format-Num ([double]$w - 2 * [double]$r)
  $id2 = Format-Num ([double]$d - 2 * [double]$r)
  $ih = Format-Num ([double]$h - 2 * [double]$r)
  $rr = Format-Num $r
  $s = "translate([" + $rr + ", " + $rr + ", " + $rr + "]) minkowski() { cube([" + $iw + ", " + $id2 + ", " + $ih + "]); sphere(r = " + $rr + "); }"
  return (New-GObj "rounded_box" $s @(0, 0, 0) @([double]$w, [double]$d, [double]$h) $null)
}

# ---- hole (§9): through / blind / countersink / counterbore / clearance ----
# $axis: "z" (ust/alt yuzey, varsayilan), "y" (on/arka yuzey). "y" ise $x=X, $y=Z, $bodyH=derinlik(Y).
function New-GHole($dia, $x, $y, $bodyH, $holeType, $extra, $axis) {
  Assert-Pos "diameter" $dia
  if ($null -eq $holeType -or $holeType -eq "") { $holeType = "through" }
  if ($null -eq $axis -or $axis -eq "") { $axis = "z" }
  $r = [double]$dia / 2
  if ($holeType -eq "through" -or $holeType -eq "clearance") {
    $hh = Format-Num ([double]$bodyH + 2)
    if ($axis -eq "y") {
      # On/arka yuzey deligi: Y ekseninde silindir. $x=X konum, $y=Z konum, $bodyH=Y derinlik.
      $s = "translate([" + (Format-Num $x) + ", -1, " + (Format-Num $y) + "]) rotate([-90, 0, 0]) cylinder(d = " + (Format-Num $dia) + ", h = " + $hh + ");"
      return (New-GObj "hole" $s @(([double]$x - $r), 0, ([double]$y - $r)) @(([double]$x + $r), [double]$bodyH, ([double]$y + $r)) $null)
    }
    $s = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", -1]) cylinder(d = " + (Format-Num $dia) + ", h = " + $hh + ");"
    return (New-GObj "hole" $s @(([double]$x - $r), ([double]$y - $r), 0) @(([double]$x + $r), ([double]$y + $r), [double]$bodyH) $null)
  } elseif ($holeType -eq "blind") {
    if ($null -eq $extra -or $null -eq $extra.depth) { throw "geometry: blind delikte depth sart" }
    Assert-Pos "depth" $extra.depth
    $topZ = [double]$bodyH
    $z0 = Format-Num ($topZ - [double]$extra.depth)
    $s = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", " + $z0 + "]) cylinder(d = " + (Format-Num $dia) + ", h = " + (Format-Num $extra.depth) + ");"
    return (New-GObj "hole-blind" $s @(([double]$x - $r), ([double]$y - $r), ($topZ - [double]$extra.depth)) @(([double]$x + $r), ([double]$y + $r), $topZ) $null)
  } elseif ($holeType -eq "countersink") {
    if ($null -eq $extra -or $null -eq $extra.cs_dia -or $null -eq $extra.cs_depth) { throw "geometry: countersink icin cs_dia + cs_depth sart" }
    $csR = [double]$extra.cs_dia / 2
    $topZ = [double]$bodyH
    $s1 = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", -1]) cylinder(d = " + (Format-Num $dia) + ", h = " + (Format-Num ($topZ + 2)) + ");"
    $s2 = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", " + (Format-Num ($topZ - [double]$extra.cs_depth)) + "]) cylinder(d1 = " + (Format-Num $dia) + ", d2 = " + (Format-Num $extra.cs_dia) + ", h = " + (Format-Num ([double]$extra.cs_depth + 1)) + ");"
    $s = $s1 + " " + $s2
    return (New-GObj "hole-countersink" $s @(([double]$x - $csR), ([double]$y - $csR), 0) @(([double]$x + $csR), ([double]$y + $csR), [double]$bodyH) $null)
  } elseif ($holeType -eq "counterbore") {
    if ($null -eq $extra -or $null -eq $extra.cb_dia -or $null -eq $extra.cb_depth) { throw "geometry: counterbore icin cb_dia + cb_depth sart" }
    $cbR = [double]$extra.cb_dia / 2
    $topZ = [double]$bodyH
    $s1 = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", -1]) cylinder(d = " + (Format-Num $dia) + ", h = " + (Format-Num ($topZ + 2)) + ");"
    $s2 = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", " + (Format-Num ($topZ - [double]$extra.cb_depth)) + "]) cylinder(d = " + (Format-Num $extra.cb_dia) + ", h = " + (Format-Num ([double]$extra.cb_depth + 1)) + ");"
    $s = $s1 + " " + $s2
    return (New-GObj "hole-counterbore" $s @(([double]$x - $cbR), ([double]$y - $cbR), 0) @(([double]$x + $cbR), ([double]$y + $cbR), [double]$bodyH) $null)
  } else { throw "geometry: delik tipi through/blind/countersink/counterbore/clearance olmali" }
}

# ---- slot + rectangular cutout (§4) ----
function New-GSlot($cx, $cy, $length, $width, $topZ, $depth) {
  Assert-Pos "length" $length; Assert-Pos "width" $width; Assert-Pos "depth" $depth
  $r = [double]$width / 2
  $x2 = [double]$cx + [double]$length
  $z0 = Format-Num ([double]$topZ - [double]$depth)
  $hh = Format-Num ([double]$depth + 1)
  $s = "translate([0, 0, " + $z0 + "]) hull() { translate([" + (Format-Num $cx) + ", " + (Format-Num $cy) + ", 0]) cylinder(d = " + (Format-Num $width) + ", h = " + $hh + "); translate([" + (Format-Num $x2) + ", " + (Format-Num $cy) + ", 0]) cylinder(d = " + (Format-Num $width) + ", h = " + $hh + "); }"
  $x0 = [math]::Min([double]$cx, $x2) - $r; $x1 = [math]::Max([double]$cx, $x2) + $r
  return (New-GObj "slot" $s @($x0, ([double]$cy - $r), ([double]$topZ - [double]$depth)) @($x1, ([double]$cy + $r), [double]$topZ) $null)
}
function New-GCutout($face, $px, $py, $w, $l, $depth, $bodyW, $bodyD, $bodyH) {
  Assert-Pos "width" $w; Assert-Pos "length" $l; Assert-Pos "depth" $depth
  if ($face -eq "top") {
    $s = "translate([" + (Format-Num $px) + ", " + (Format-Num $py) + ", " + (Format-Num ([double]$bodyH - [double]$depth)) + "]) cube([" + (Format-Num $w) + ", " + (Format-Num $l) + ", " + (Format-Num ([double]$depth + 1)) + "]);"
    return (New-GObj "cutout" $s @([double]$px, [double]$py, ([double]$bodyH - [double]$depth)) @(([double]$px + [double]$w), ([double]$py + [double]$l), [double]$bodyH) $null)
  } elseif ($face -eq "front") {
    $s = "translate([" + (Format-Num $px) + ", -1, " + (Format-Num $py) + "]) cube([" + (Format-Num $w) + ", " + (Format-Num ([double]$depth + 1)) + ", " + (Format-Num $l) + "]);"
    return (New-GObj "cutout" $s @([double]$px, 0, [double]$py) @(([double]$px + [double]$w), [double]$depth, ([double]$py + [double]$l)) $null)
  } elseif ($face -eq "rear") {
    $s = "translate([" + (Format-Num $px) + ", " + (Format-Num ([double]$bodyD - [double]$depth)) + ", " + (Format-Num $py) + "]) cube([" + (Format-Num $w) + ", " + (Format-Num ([double]$depth + 1)) + ", " + (Format-Num $l) + "]);"
    return (New-GObj "cutout" $s @([double]$px, ([double]$bodyD - [double]$depth), [double]$py) @(([double]$px + [double]$w), [double]$bodyD, ([double]$py + [double]$l)) $null)
  } else { throw "geometry: kesik yuzu top/front/rear olmali" }
}

# ---- hollow / shell (§5): ok=$false ise geometrik olarak imkansiz ----
# Taban kurali: floor = bottom ?? wall (kullanicinin degeri sessizce yok sayilmaz).
function Get-HollowFloor($wall, $bottom) {
  $fl = [double]$wall
  if ($null -ne $bottom -and [double]$bottom -gt 0) { $fl = [double]$bottom }
  return $fl
}
function New-GHollowBox($w, $d, $h, $wall, $openTop, $floor) {
  Assert-Pos "width" $w; Assert-Pos "depth" $d; Assert-Pos "height" $h; Assert-Pos "wall" $wall
  $ww = [double]$wall
  $fl = Get-HollowFloor $wall $floor
  if (2 * $ww -ge [double]$w -or 2 * $ww -ge [double]$d -or $ww -ge [double]$h -or $fl -ge [double]$h) {
    return [pscustomobject]@{ ok = $false; reason = "ici bos govde imkansiz: 2*duvar en/kal boyutu geciyor ya da taban yuksekligi asiyor (duvar $ww taban $fl, govde ${w}x${d}x${h})" }
  }
  $iw = Format-Num ([double]$w - 2 * $ww); $id2 = Format-Num ([double]$d - 2 * $ww)
  $flS = Format-Num $fl
  if ($openTop) {
    $ih = Format-Num ([double]$h - $fl + 1)
    $s = "difference() { cube([" + (Format-Num $w) + ", " + (Format-Num $d) + ", " + (Format-Num $h) + "]); translate([" + (Format-Num $ww) + ", " + (Format-Num $ww) + ", " + $flS + "]) cube([" + $iw + ", " + $id2 + ", " + $ih + "]); }"
  } else {
    $ih = Format-Num ([double]$h - $ww - $fl)
    $s = "difference() { cube([" + (Format-Num $w) + ", " + (Format-Num $d) + ", " + (Format-Num $h) + "]); translate([" + (Format-Num $ww) + ", " + (Format-Num $ww) + ", " + $flS + "]) cube([" + $iw + ", " + $id2 + ", " + $ih + "]); }"
  }
  $g = New-GObj "hollow_box" $s @(0, 0, 0) @([double]$w, [double]$d, [double]$h) $null
  $g | Add-Member -NotePropertyName "ok" $true
  return $g
}

# ---- rounded hollow box (v2.2, gercek radius): dis yuvarlak + ic keskin ----
# 2021.01 uyumlu (minkowski+sphere; BOSL2 yok). r <= duvar olmali (duvar korunur).
function New-GHollowRoundedBox($w, $d, $h, $wall, $r, $openTop, $floor) {
  Assert-Pos "width" $w; Assert-Pos "depth" $d; Assert-Pos "height" $h
  Assert-Pos "wall" $wall; Assert-Pos "radius" $r
  $ww = [double]$wall; $rr = [double]$r
  $fl = Get-HollowFloor $wall $floor
  if (2 * $ww -ge [double]$w -or 2 * $ww -ge [double]$d -or $ww -ge [double]$h -or $fl -ge [double]$h) {
    return [pscustomobject]@{ ok = $false; reason = "ici bos govde imkansiz: duvar/taban govdeye sigmiyor" }
  }
  if (2 * $rr -gt [math]::Min([double]$w, [math]::Min([double]$d, [double]$h))) {
    return [pscustomobject]@{ ok = $false; reason = "radius cok buyuk: 2*r en kucuk olcuyu asiyor" }
  }
  if ($rr -gt $ww + 2.0) {
    return [pscustomobject]@{ ok = $false; reason = "radius duvar kalinligini asiyor (r <= duvar+2); duvar korunamaz" }
  }
  $iw = Format-Num ([double]$w - 2 * $ww); $id2 = Format-Num ([double]$d - 2 * $ww)
  $flS = Format-Num $fl
  $ow = Format-Num ([double]$w - 2 * $rr); $od = Format-Num ([double]$d - 2 * $rr)
  $oh = Format-Num ([double]$h - 2 * $rr)
  $rrS = Format-Num $rr
  $outer = "translate([" + $rrS + ", " + $rrS + ", " + $rrS + "]) minkowski() { cube([" + $ow + ", " + $od + ", " + $oh + "]); sphere(r = " + $rrS + "); }"
  if ($openTop) { $ih = Format-Num ([double]$h - $fl + 1) }
  else { $ih = Format-Num ([double]$h - $ww - $fl) }
  $inner = "translate([" + (Format-Num $ww) + ", " + (Format-Num $ww) + ", " + $flS + "]) cube([" + $iw + ", " + $id2 + ", " + $ih + "]);"
  $s = "difference() { " + $outer + " " + $inner + " }"
  $g = New-GObj "hollow_rounded_box" $s @(0, 0, 0) @([double]$w, [double]$d, [double]$h) $null
  $g | Add-Member -NotePropertyName "ok" $true
  return $g
}

# ---- planner partitions/wedges (v1.0, additive): govde-ici elemanlar ----
# Kama: X boyunca ekstruzyonlu dik-ucgen prizma (polyhedron, 2021.01 uyumlu).
# Profil (Y-Z): A(y0,z0) on-alt -> B(y1,z0) arka-alt -> C(y1,z0+h) arka-ust.
# Yaslanma yuzu A->C; dikeyden aci = atan((y1-y0)/h).
function New-GWedge($x0, $x1, $y0, $y1, $z0, $h) {
  if ($null -eq $x0 -or $null -eq $x1 -or [double]$x1 -le [double]$x0) { throw "geometry: wedge x1 > x0 olmali" }
  if ($null -eq $y0 -or $null -eq $y1 -or [double]$y1 -le [double]$y0) { throw "geometry: wedge y1 > y0 olmali" }
  Assert-Pos "wedge-height" $h
  $pts = @(
    ("[" + (Format-Num $x0) + ", " + (Format-Num $y0) + ", " + (Format-Num $z0) + "]"),
    ("[" + (Format-Num $x1) + ", " + (Format-Num $y0) + ", " + (Format-Num $z0) + "]"),
    ("[" + (Format-Num $x1) + ", " + (Format-Num $y1) + ", " + (Format-Num $z0) + "]"),
    ("[" + (Format-Num $x0) + ", " + (Format-Num $y1) + ", " + (Format-Num $z0) + "]"),
    ("[" + (Format-Num $x1) + ", " + (Format-Num $y1) + ", " + (Format-Num ([double]$z0 + [double]$h)) + "]"),
    ("[" + (Format-Num $x0) + ", " + (Format-Num $y1) + ", " + (Format-Num ([double]$z0 + [double]$h)) + "]")
  )
  $s = "polyhedron(points=[" + ($pts -join ", ") + "], faces=[[0,2,1], [0,3,2], [2,3,5], [2,5,4], [0,1,4], [0,4,5], [0,5,3], [1,2,4]]);"
  return (New-GObj "wedge" $s @([double]$x0, [double]$y0, [double]$z0) @([double]$x1, [double]$y1, ([double]$z0 + [double]$h)) $null)
}

# ---- fillet / chamfer (§10): guvenli olan uygulanir, riskli olan WARNING olur ----
function New-GEdgeNote($kind, $value, $target) {
  return [pscustomobject]@{ kind = $kind; value_mm = [double]$value; target = $target; applied = $false; warning = "kenar islemi ($kind $value mm, hedef: $target) OpenSCAD'da guvenli uygulanamiyor; ana model korundu, islem uygulanmadi" }
}

# ---- transforms (§11) ----
function Move-G($g, $x, $y, $z) {
  $s = "translate([" + (Format-Num $x) + ", " + (Format-Num $y) + ", " + (Format-Num $z) + "]) { " + $g.scad + " }"
  $nb = @(([double]$g.bmin[0] + [double]$x), ([double]$g.bmin[1] + [double]$y), ([double]$g.bmin[2] + [double]$z))
  $xb = @(([double]$g.bmax[0] + [double]$x), ([double]$g.bmax[1] + [double]$y), ([double]$g.bmax[2] + [double]$z))
  return (New-GObj $g.kind $s $nb $xb $g.notes)
}
function Turn-G($g, $rx, $ry, $rz) {
  $s = "rotate([" + (Format-Num $rx) + ", " + (Format-Num $ry) + ", " + (Format-Num $rz) + "]) { " + $g.scad + " }"
  $nonzero = @($rx, $ry, $rz | Where-Object { ([double]$_ % 90) -ne 0 })
  if ($nonzero.Count -gt 0) {
    $n = @($g.notes) + @("WARNING: cok-eksenli/90-kati-olmayan rotate sonrasi bbox yaklasik hesaplandi")
    return (New-GObj $g.kind $s $g.bmin $g.bmax $n)
  }
  $pts = New-Object System.Collections.Generic.List[object]
  foreach ($cx in @($g.bmin[0], $g.bmax[0])) { foreach ($cy in @($g.bmin[1], $g.bmax[1])) { foreach ($cz in @($g.bmin[2], $g.bmax[2])) {
    $v = @([double]$cx, [double]$cy, [double]$cz)
    foreach ($ax in @( @{ a = [double]$rx; i = 1; j = 2 }, @{ a = [double]$ry; i = 2; j = 0 }, @{ a = [double]$rz; i = 0; j = 1 } )) {
      $t = [int]([math]::Round($ax.a / 90)) % 4
      for ($k = 0; $k -lt (($t + 4) % 4); $k++) { $tmp = $v[$ax.i]; $v[$ax.i] = -$v[$ax.j]; $v[$ax.j] = $tmp }
    }
    $pts.Add($v)
  } } }
  $nb = @((($pts | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum), ((($pts | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum)), ((($pts | ForEach-Object { $_[2] } | Measure-Object -Minimum).Minimum)))
  $xb = @((($pts | ForEach-Object { $_[0] } | Measure-Object -Maximum).Maximum), ((($pts | ForEach-Object { $_[1] } | Measure-Object -Maximum).Maximum)), ((($pts | ForEach-Object { $_[2] } | Measure-Object -Maximum).Maximum)))
  return (New-GObj $g.kind $s $nb $xb $g.notes)
}
function Mirror-G($g, $axis) {
  if ($axis -ne "x" -and $axis -ne "y" -and $axis -ne "z") { throw "geometry: ayna ekseni x/y/z olmali" }
  $vx = 0; $vy = 0; $vz = 0
  if ($axis -eq "x") { $vx = 1 } elseif ($axis -eq "y") { $vy = 1 } else { $vz = 1 }
  $s = "mirror([" + $vx + ", " + $vy + ", " + $vz + "]) { " + $g.scad + " }"
  $nb = @($g.bmin[0], $g.bmin[1], $g.bmin[2]); $xb = @($g.bmax[0], $g.bmax[1], $g.bmax[2])
  $idx = @{ x = 0; y = 1; z = 2 }[$axis]
  $nb[$idx] = -$g.bmax[$idx]; $xb[$idx] = -$g.bmin[$idx]
  return (New-GObj $g.kind $s $nb $xb $g.notes)
}

# ---- boolean (§3) ----
function Merge-G($parts) {
  $arr = @($parts)
  if ($arr.Count -eq 0) { throw "geometry: union icin en az 1 parca sart" }
  if ($arr.Count -eq 1) { return $arr[0] }
  $s = "union() { " + (($arr | ForEach-Object { $_.scad }) -join " ") + " }"
  $nb = @((($arr | ForEach-Object { $_.bmin[0] } | Measure-Object -Minimum).Minimum), ((($arr | ForEach-Object { $_.bmin[1] } | Measure-Object -Minimum).Minimum)), ((($arr | ForEach-Object { $_.bmin[2] } | Measure-Object -Minimum).Minimum)))
  $xb = @((($arr | ForEach-Object { $_.bmax[0] } | Measure-Object -Maximum).Maximum), ((($arr | ForEach-Object { $_.bmax[1] } | Measure-Object -Maximum).Maximum)), ((($arr | ForEach-Object { $_.bmax[2] } | Measure-Object -Maximum).Maximum)))
  $notes = @(); foreach ($p in $arr) { $notes += @($p.notes) }
  return (New-GObj "union" $s $nb $xb $notes)
}
function Carve-G($body, $cuts) {
  $arr = @($cuts)
  if ($arr.Count -eq 0) { return $body }
  $s = "difference() { " + $body.scad + " " + (($arr | ForEach-Object { $_.scad }) -join " ") + " }"
  $notes = @($body.notes); foreach ($c in $arr) { $notes += @($c.notes) }
  return (New-GObj "difference" $s $body.bmin $body.bmax $notes)
}
function Intersect-G($parts) {
  $arr = @($parts)
  if ($arr.Count -lt 2) { throw "geometry: intersection icin en az 2 parca sart" }
  $s = "intersection() { " + (($arr | ForEach-Object { $_.scad }) -join " ") + " }"
  $nb = @([math]::Max($arr[0].bmin[0], $arr[1].bmin[0]), [math]::Max($arr[0].bmin[1], $arr[1].bmin[1]), [math]::Max($arr[0].bmin[2], $arr[1].bmin[2]))
  $xb = @([math]::Min($arr[0].bmax[0], $arr[1].bmax[0]), [math]::Min($arr[0].bmax[1], $arr[1].bmax[1]), [math]::Min($arr[0].bmax[2], $arr[1].bmax[2]))
  return (New-GObj "intersection" $s $nb $xb $null)
}

# ---- SCAD belgesi (§12): PARAMETERS / GEOMETRY / BOOLEAN / ASSEMBLY / EXPORT ----
function Build-ScadDocument($title, [string[]]$paramLines, [string[]]$geometryLines, [string[]]$noteLines) {
  $doc = New-Object System.Collections.Generic.List[string]
  $doc.Add("// " + $title)
  $doc.Add("// 3D AI Designer V1.1 Geometry Engine uretimi - tum olculer mm.")
  $doc.Add("")
  $doc.Add("// ============ PARAMETERS ============")
  foreach ($ln in $paramLines) { $doc.Add($ln) }
  $doc.Add("")
  $doc.Add("// ============ GEOMETRY + BOOLEAN OPERATIONS ============")
  foreach ($ln in $geometryLines) { $doc.Add($ln) }
  if ($noteLines.Count -gt 0) {
    $doc.Add("")
    $doc.Add("// ============ ASSEMBLY / NOTLAR ============")
    foreach ($ln in $noteLines) { $doc.Add("// NOT: " + $ln) }
  }
  $doc.Add("")
  $doc.Add("// ============ EXPORT ============")
  $doc.Add("// Export harici arac ile yapilir (Export-Stl.ps1).")
  return @($doc)
}
