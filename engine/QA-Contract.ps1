<#
.SYNOPSIS
  Q&A merkezi sozlesme: soru cozuleme + parser yonlendirme (tek authoritative implementation).
.DESCRIPTION
  Get-QuestionByStableId: liste icinden stable ID ile bulur (bulunamazsa $null, throw YOK).
  Resolve-CurrentQuestion: spec dosyasindan soru dosyasini yukler, stable ID ile dondurur.
  Invoke-QuestionParser: question.parser/type alanina gore DOGRU parseri cagirir.
    center -> Parse-Center (asla Parse-Pair/open_top'a dusmez).
  Donus: @{ ok = bool; message = string }. Hata durumunda throw YOK (cagiran karar verir).
  KURALLAR: PowerShell case-insensitive -> $Spec* / $spec* adlari karistirilmaz.
  Array literal icinde aritmetik parantezli; ConvertFrom-Json ciktisi ayni ifadede @() ile sarilmaz.
#>

function Get-NumU($s) { return [double]([string]$s -replace ',', '.') }
function Parse-Pair($t) {
  $m = [regex]::Match($t, '(-?\d+(?:[.,]\d+)?)\s*[,;xX\s]\s*(-?\d+(?:[.,]\d+)?)')
  if (-not $m.Success) { throw "Cevap anlasilmadi. Iki sayi bekleniyor (ornek: 15,15 veya 15 15). Girilen: $t" }
  return @((Get-NumU $m.Groups[1].Value), (Get-NumU $m.Groups[2].Value))
}
function Parse-Triple($t) {
  # Govde olcusu cevabi: "160x100x45" kesin kabul; ayrica x/X/* ve U+00D7/U+2715/U+2716/U+2A2F
  # ayiraclari, sayi-arasi "mm" ("160mm x 100mm x 45mm") ve tum-cevap virgul/noktali-virgul/
  # bosluk uculeri ("160, 100, 45" / "160 100 45") kabul edilir. Uc sayi da pozitif olmali.
  $s = [string]$t
  $s = $s -replace '[\u2715\u2716\u2a2f\u00d7\*]', 'x'
  $s = $s -replace '(?i)[c\u00e7]arp[i\u0131]', 'x'
  $s = $s -replace '(?i)(?<=\d)\s*mm\b|\bmm\b', ' '
  $s = [regex]::Replace($s, '(-?\d+(?:[.,]\d+)?)\s*cm\b', { param($m) ((Get-NumU $m.Groups[1].Value) * 10).ToString() } )
  $m = [regex]::Match($s, '(-?\d+(?:[.,]\d+)?)\s*[xX]\s*(-?\d+(?:[.,]\d+)?)\s*[xX]\s*(-?\d+(?:[.,]\d+)?)')
  if (-not $m.Success) {
    $m = [regex]::Match($s.Trim(), '^(-?\d+(?:[.,]\d+)?)\s*[,;\s]\s*(-?\d+(?:[.,]\d+)?)\s*[,;\s]\s*(-?\d+(?:[.,]\d+)?)$')
  }
  if (-not $m.Success) { throw "Govde olcusu anlasilmadi. Uc pozitif olcu bekleniyor (ornek: 80x40x20 veya '80, 40, 20'). Girilen: $t" }
  $d = @((Get-NumU $m.Groups[1].Value), (Get-NumU $m.Groups[2].Value), (Get-NumU $m.Groups[3].Value))
  if ($d[0] -le 0 -or $d[1] -le 0 -or $d[2] -le 0) { throw "Olculer pozitif olmali (ornek: 80x40x20). Girilen: $t" }
  return $d
}
function Parse-One($t) {
  $m = [regex]::Match($t, '(-?\d+(?:[.,]\d+)?)')
  if (-not $m.Success) { throw "Cevap anlasilmadi. Sayi bekleniyor. Girilen: $t" }
  $v = Get-NumU $m.Groups[1].Value
  if ($v -le 0) { throw "Olcu pozitif olmali. Girilen: $t" }
  return $v
}
function Parse-Center($t, $bw, $bd) {
  # Deterministik koordinat parseri: SADECE center turu sorular kullanir.
  # Kabul: 15,15 | 15 15 | 15 mm, 15 mm | 15 mm 15 mm | merkez 15,15 | merkez 15 15 | 15.5, 20.5
  # Red: tek sayi, sayisiz metin, belirsiz ondalik ("15,5"), kutu disi ve SINIR deger
  # (sinir: capi >0 olan delik kenara tasacagi icin 0 ve dis kenar kabul edilmez).
  $s = [string]$t
  $s = $s -replace '(?i)\bmerkez\b', ' '
  $s = $s -replace '(?i)\bmm\b', ' '
  $s = $s.Trim()
  if ($s -eq "") { throw "Cevap anlasilmadi. Iki sayi bekleniyor (ornek: 15,15 veya 15 15). Girilen: $t" }
  if ($s -match '^\s*-?\d+\s*,\s*\d\s*$') { throw "Belirsiz cevap: ondalik mi koordinat mi anlasilmiyor. Koordinat icin '15, 15', tek ondalik icin '15.5' yaz. Girilen: $t" }
  $m = [regex]::Match($s, '(-?\d+(?:\.\d+)?)\s*[,;/\s]\s*(-?\d+(?:\.\d+)?)')
  if (-not $m.Success) { throw "Cevap anlasilmadi. Iki sayi bekleniyor (ornek: 15,15 veya 15 15). Girilen: $t" }
  $x = [double]$m.Groups[1].Value
  $y = [double]$m.Groups[2].Value
  if ($bw -gt 0 -and $bd -gt 0) {
    if ($x -le 0 -or $x -ge $bw -or $y -le 0 -or $y -ge $bd) {
      throw "Merkez govde disinda/sinirda: ($x,$y) 0..$bw x 0..$bd acik araliginda olmali (sinir delik tasirir). Girilen: $t"
    }
  }
  return @($x, $y)
}
function Parse-OpenTop($t) {
  $a = ([string]$t).ToLowerInvariant()
  if ($a -match "acik" -or $a -match "a[c\u00e7]ik") { return $true }
  if ($a -match "kapali") { return $false }
  throw "Cevap anlasilmadi. 'acik' veya 'kapali' yaz. Girilen: $t"
}
function Parse-Axis($t) {
  $a = ([string]$t).ToLowerInvariant()
  if ($a -match "\bx\b") { return "x" }
  if ($a -match "\by\b") { return "y" }
  if ($a -match "\bz\b") { return "z" }
  throw "Eksen anlasilmadi. X / Y / Z yaz. Girilen: $t"
}

function Get-QuestionByStableId($questions, $stableId) {
  if ($null -eq $questions) { return $null }
  foreach ($qi in $questions) {
    if ($null -ne $qi -and [string]$qi.question_id -eq [string]$stableId) { return $qi }
  }
  return $null
}
function Resolve-CurrentQuestion($specFile, $stableId) {
  $qfile = [System.IO.Path]::ChangeExtension($specFile, ".questions.json")
  if (-not (Test-Path -LiteralPath $qfile)) { return $null }
  $raw = Get-Content -LiteralPath $qfile -Raw | ConvertFrom-Json
  $list = New-Object System.Collections.Generic.List[object]
  if ($null -ne $raw) {
    if ($raw -is [array]) { foreach ($e in $raw) { $list.Add($e) } }
    else { $list.Add($raw) }
  }
  return (Get-QuestionByStableId $list $stableId)
}

function Invoke-QuestionParser($specObj, $question, $answer) {
  $kind = [string]$question.kind
  $target = [string]$question.target
  $cid = [string]$question.component
  $comp = $null
  foreach ($c in @($specObj.components)) {
    if ($c -and [string]$c.id -eq $cid) { $comp = $c; break }
  }
  if ($null -eq $comp -and $kind -ne "joint_clearance") {
    return @{ ok = $false; message = ("Bilesen bulunamadi: " + $cid) }
  }
  try {
    if ($kind -eq "dims") {
      $d = Parse-Triple $answer
      $comp.base.width_mm = $d[0]; $comp.base.depth_mm = $d[1]; $comp.base.height_mm = $d[2]
    } elseif ($kind -eq "lid_height") {
      $comp.base.height_mm = Parse-One $answer
    } elseif ($kind -eq "wall") {
      $comp.hollow.wall_mm = Parse-One $answer
    } elseif ($kind -eq "hollow_top") {
      $comp.hollow.open_top = Parse-OpenTop $answer
    } elseif ($kind -eq "rotate_axis") {
      $ax = Parse-Axis $answer
      $t = [pscustomobject]@{ op = "rotate"; x = 0; y = 0; z = 0 }
      $ang = [double]$comp.pending_rotate
      $am = [regex]::Match([string]$answer, '(-?\d+(?:[.,]\d+)?)')
      if ($am.Success -and [double]($am.Groups[1].Value -replace ',', '.') -ne 0) {
        $ang = [double]($am.Groups[1].Value -replace ',', '.')
      }
      if ($ax -eq "x") { $t.x = $ang } elseif ($ax -eq "y") { $t.y = $ang } else { $t.z = $ang }
      $comp.transforms = @($comp.transforms | Where-Object { $_ -ne $null }) + @($t)
      $comp.pending_rotate = $null
    } elseif ($kind -eq "mirror_axis") {
      $ax = Parse-Axis $answer
      $comp.transforms = @($comp.transforms | Where-Object { $_ -ne $null }) + @([pscustomobject]@{ op = "mirror"; axis = $ax })
      $comp.pending_mirror = $false
    } elseif ($kind -eq "edge_value") {
      $ekind = ($target -split '\.')[-1]
      $e = $null
      foreach ($en in @($comp.edge_notes)) {
        if ($en -and [string]$en.kind -eq $ekind) { $e = $en; break }
      }
      if ($null -eq $e) { return @{ ok = $false; message = ("Kenar islemi bulunamadi: " + $ekind) } }
      $e.value_mm = Parse-One $answer
    } elseif ($kind -eq "hole_center") {
      $hid = ($target -split '\.')[-2]
      $h = $null
      foreach ($hh in @($comp.holes)) {
        if ($hh -and [string]$hh.id -eq $hid) { $h = $hh; break }
      }
      if ($null -eq $h) { return @{ ok = $false; message = ("Delik bulunamadi: " + $hid) } }
      $cbw = 0; $cbd = 0
      if ($comp.base -and ($comp.base.shape -eq "box" -or $comp.base.shape -eq "rounded_box")) {
        $cbw = [double]$comp.base.width_mm; $cbd = [double]$comp.base.depth_mm
      }
      $p = Parse-Center $answer $cbw $cbd
      $h.center_x_mm = $p[0]; $h.center_y_mm = $p[1]; $h.status = "ok"
    } elseif ($kind -eq "hole_dia") {
      $hid = ($target -split '\.')[-2]
      $h = $null
      foreach ($hh in @($comp.holes)) {
        if ($hh -and [string]$hh.id -eq $hid) { $h = $hh; break }
      }
      if ($null -eq $h) { return @{ ok = $false; message = ("Delik bulunamadi: " + $hid) } }
      $h.diameter_mm = Parse-One $answer; $h.status = "ok"
    } elseif ($kind -eq "hole_depth") {
      $hid = ($target -split '\.')[-2]
      $h = $null
      foreach ($hh in @($comp.holes)) {
        if ($hh -and [string]$hh.id -eq $hid) { $h = $hh; break }
      }
      if ($null -eq $h) { return @{ ok = $false; message = ("Delik bulunamadi: " + $hid) } }
      $h.depth_mm = Parse-One $answer; $h.status = "ok"
    } elseif ($kind -eq "hole_extra") {
      $hid = ($target -split '\.')[-2]
      $h = $null
      foreach ($hh in @($comp.holes)) {
        if ($hh -and [string]$hh.id -eq $hid) { $h = $hh; break }
      }
      if ($null -eq $h) { return @{ ok = $false; message = ("Delik bulunamadi: " + $hid) } }
      $p = Parse-Pair $answer
      if ($h.hole_type -eq "countersink") { $h.cs_dia_mm = $p[0]; $h.cs_depth_mm = $p[1] }
      else { $h.cb_dia_mm = $p[0]; $h.cb_depth_mm = $p[1] }
      $h.status = "ok"
    } elseif ($kind -eq "cutout") {
      $tid = [string]$question.field -replace '^cutouts\.', ''
      $t = $null
      foreach ($tt in @($comp.cutouts)) {
        if ($tt -and [string]$tt.id -eq $tid) { $t = $tt; break }
      }
      if ($null -eq $t) { return @{ ok = $false; message = ("Kesik bulunamadi: " + $tid) } }
      $ansN = ([string]$answer -replace '[\u2715\u2716\u2a2f\u00d7\*]', 'x') -replace '(?i)[c\u00e7]arp[i\u0131]', 'x'
      $dm = [regex]::Match($ansN, '(-?\d+(?:[.,]\d+)?)\s*[xX]\s*(-?\d+(?:[.,]\d+)?)')
      if ($dm.Success) { $t.width_mm = Get-NumU $dm.Groups[1].Value; $t.length_mm = Get-NumU $dm.Groups[2].Value }
      elseif ($null -eq $t.width_mm -or $null -eq $t.length_mm) { return @{ ok = $false; message = ("Kesik olcusu anlasilmadi (ornek: 20x10). Girilen: " + $answer) } }
      $pm = [regex]::Match([string]$answer, 'konum\s*(-?\d+(?:[.,]\d+)?)\s*[,;]\s*(-?\d+(?:[.,]\d+)?)')
      if ($pm.Success) { $t.pos_x_mm = Get-NumU $pm.Groups[1].Value; $t.pos_y_mm = Get-NumU $pm.Groups[2].Value }
      else {
        $pm1 = [regex]::Match([string]$answer, 'konum\s*(-?\d+(?:[.,]\d+)?)')
        if ($pm1.Success -and $null -eq $t.pos_x_mm) { $t.pos_x_mm = Get-NumU $pm1.Groups[1].Value }
      }
      $dep = [regex]::Match([string]$answer, 'derinlik\s*(-?\d+(?:[.,]\d+)?)')
      if ($dep.Success) { $t.depth_mm = Get-NumU $dep.Groups[1].Value }
      # Olcusu bilinen kesikte yalın sayı ilk eksige yazilir: pos_x, pos_y, depth sirasiyla.
      if (-not $dm.Success -and -not $pm.Success -and -not $dep.Success -and $pm1 -eq $null) {
        $solo = [regex]::Match([string]$answer, '^\s*(-?\d+(?:[.,]\d+)?)\s*(?:mm)?\s*$')
        if ($solo.Success) {
          $sv = Get-NumU $solo.Groups[1].Value
          if ($sv -le 0) { return @{ ok = $false; message = ("Konum/derinlik pozitif olmali. Girilen: " + $answer) } }
          if ($null -eq $t.pos_x_mm) { $t.pos_x_mm = $sv }
          elseif ($null -eq $t.pos_y_mm) { $t.pos_y_mm = $sv }
          elseif ($null -eq $t.depth_mm -and [string]$t.penetration -ne "through_wall") { $t.depth_mm = $sv }
          else { return @{ ok = $false; message = ("Kesikte eksik sayisal alan yok; cevap islenemedi. Girilen: " + $answer) } }
        } else {
          return @{ ok = $false; message = ("Kesik cevabi anlasilmadi (ornek: 20x10, konum 5,5, derinlik 8 - veya yalniz eksik sayi). Girilen: " + $answer) }
        }
      }
      $depthFilled = ($null -ne $t.depth_mm -or [string]$t.penetration -eq "through_wall")
      if ($null -ne $t.width_mm -and $null -ne $t.length_mm -and $null -ne $t.pos_x_mm -and $null -ne $t.pos_y_mm -and $depthFilled) { $t.status = "ok" }
    } elseif ($kind -eq "divider_thickness") {
      if ($null -eq $comp.divider_pattern) { return @{ ok = $false; message = "Bolme deseni bulunamadi." } }
      $comp.divider_pattern.thickness_mm = Parse-One $answer
      $comp.divider_pattern.status = "ok"
    } elseif ($kind -eq "clearance") {
      $v = Parse-One $answer
      $comp.tolerance.clearance_mm = $v; $comp.tolerance.status = "ok"
      foreach ($j in @($specObj.assembly.joints)) {
        if ($j -and ([string]$j.part_b -eq $cid -or [string]$j.part_a -eq $cid) -and $null -eq $j.clearance_mm) {
          $j.clearance_mm = $v
        }
      }
    } elseif ($kind -eq "joint_clearance") {
      $jid = ($target -split '\.')[-1]
      $j = $null
      foreach ($jj in @($specObj.assembly.joints)) {
        if ($jj -and [string]$jj.id -eq $jid) { $j = $jj; break }
      }
      if ($null -eq $j) { return @{ ok = $false; message = ("Baglanti bulunamadi: " + $jid) } }
      $j.clearance_mm = Parse-One $answer
    } else {
      return @{ ok = $false; message = ("Bilinmeyen soru turu: " + $kind) }
    }
  } catch {
    return @{ ok = $false; message = [string]$_.Exception.Message }
  }
  return @{ ok = $true; message = "ok" }
}
