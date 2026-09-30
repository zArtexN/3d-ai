<#
.SYNOPSIS
  Deterministik dogal-dil -> edit-op cevirici (Phase 3).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok.
  Parse-EditIntent($spec, $text) donus:
   @{ kind = "patch"|"clarify"|"not-edit"|"undo"|"redo"|"restore";
      ops = @(); message = "..."; restore_target = $null }
  Kurallar: tekil hedef + sayisal deger sart; cogul/belirsiz -> clarify;
  dosya islemleri -> not-edit(blocked); negation -> not-edit.
  AI cagrisi YOK (MOCK-only mimariye uygun).
#>

function Get-EINum($s) { return [double]([string]$s -replace ',', '.') }

function Find-EIBody($spec) {
  foreach ($c in @($spec.components)) {
    if ($c -and [string]$c.id -eq "body") { return $c }
  }
  $all = @($spec.components | Where-Object { $_ -ne $null })
  if ($all.Count -gt 0) { return $all[0] }
  return $null
}

function Find-EIHoles($body) {
  return @(@($body.holes) | Where-Object { $_ -and [string]$_.id -notlike "mp*" })
}

function Find-EICutouts($body) {
  return @(@($body.cutouts) | Where-Object { $_ -ne $null })
}

function Resolve-EIHole($body, $low) {
  $m = [regex]::Match($low, '\bh(\d+)\b')
  if ($m.Success) {
    foreach ($h in (Find-EIHoles $body)) {
      if ([string]$h.id -eq ("h" + $m.Groups[1].Value)) { return $h }
    }
    return "missing"
  }
  $hs = Find-EIHoles $body
  if ($hs.Count -eq 1) { return $hs[0] }
  return $null
}

function Resolve-EICutout($body, $low) {
  $m = [regex]::Match($low, '\bc(\d+)\b')
  if ($m.Success) {
    foreach ($t in (Find-EICutouts $body)) {
      if ([string]$t.id -eq ("c" + $m.Groups[1].Value)) { return $t }
    }
    return "missing"
  }
  $face = ""
  if ($low -match '[o\u00f6]n\b') { $face = "front" }
  elseif ($low -match 'arka') { $face = "rear" }
  elseif ($low -match '[u\u00fc]st\b') { $face = "top" }
  $cs = Find-EICutouts $body
  if ($face -ne "") {
    $fm = @($cs | Where-Object {
      $fb = ([string]$_.face -replace '_short_edge$','' -replace '_long_edge$','')
      $fb -eq $face
    })
    if ($fm.Count -eq 1) { return $fm[0] }
    return $null
  }
  if ($cs.Count -eq 1) { return $cs[0] }
  return $null
}

function Parse-EditClause($spec, $body, $low) {
  $ops = New-Object System.Collections.Generic.List[object]
  $bid = [string]$body.id
  # Silme: "<hedef> kaldir|sil" (feature cozumu sart).
  $dm = [regex]::Match($low, 'kaldir|kald[i\u0131]r|sil\b')
  if ($dm.Success) {
    if ($low -match 'fillet|yuvarlat') {
      $ops.Add(@{ op = "remove"; path = ($bid + ".edge_notes.fillet"); old = $null; value = $null; reason = "kaldirma"; requires_confirmation = $true }) | Out-Null
      return @{ ok = $true; ops = @($ops.ToArray()) }
    }
    if ($low -match 'pah\b') {
      $ops.Add(@{ op = "remove"; path = ($bid + ".edge_notes.chamfer"); old = $null; value = $null; reason = "kaldirma"; requires_confirmation = $true }) | Out-Null
      return @{ ok = $true; ops = @($ops.ToArray()) }
    }
    if ($low -match 'kesik|kesit|kanal|a[c\u00e7][i\u0131]kl[i\u0131]k') {
      $t = Resolve-EICutout $body $low
      if ($null -eq $t) { return @{ ok = $false; message = "hangi kesit? (c1 gibi ID ya da tek yuz belirt)" } }
      if ($t -eq "missing") { return @{ ok = $false; message = "kesit bulunamadi" } }
      $ops.Add(@{ op = "remove"; path = ($bid + ".cutouts." + [string]$t.id); old = $null; value = $null; reason = "kaldirma"; requires_confirmation = $true }) | Out-Null
      return @{ ok = $true; ops = @($ops.ToArray()) }
    }
    if ($low -match 'deli[k\u011fg]|delik') {
      $h = Resolve-EIHole $body $low
      if ($null -eq $h) { return @{ ok = $false; message = "hangi delik? (h1 gibi ID belirt ya da tek delik olmali)" } }
      if ($h -eq "missing") { return @{ ok = $false; message = "delik bulunamadi" } }
      $ops.Add(@{ op = "remove"; path = ($bid + ".holes." + [string]$h.id); old = $null; value = $null; reason = "kaldirma"; requires_confirmation = $true }) | Out-Null
      return @{ ok = $true; ops = @($ops.ToArray()) }
    }
    return @{ ok = $false; message = "kaldirilacak feature anlasilmadi" }
  }
  # Ekleme: "delik ekle" + cap + merkez sart.
  if ($low -match 'delik\s*ekle|ekle.*delik') {
    $dm2 = [regex]::Match($low, '[c\u00e7]ap\s*(\d+(?:[.,]\d+)?)')
    $cm = [regex]::Match($low, 'merkez\s*(\d+(?:[.,]\d+)?)\s*[,;\s]\s*(\d+(?:[.,]\d+)?)')
    if (-not $dm2.Success -or -not $cm.Success) {
      return @{ ok = $false; message = "delik eklemek icin cap ve merkez gerekli (ornek: cap 8 merkez 10,10 delik ekle)" }
    }
    $ops.Add(@{
      op = "add"; path = ($bid + ".holes"); old = $null
      value = [pscustomobject]@{
        hole_type = "through"; diameter_mm = (Get-EINum $dm2.Groups[1].Value)
        center_x_mm = (Get-EINum $cm.Groups[1].Value); center_y_mm = (Get-EINum $cm.Groups[2].Value)
        axis = "z"; status = "ok"
      }
      reason = "ekleme"; requires_confirmation = $false
    }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  # Gorece tasma: "<hedef> N mm saga/sola/yukari/asagi tasi".
  $mv = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*(sa[g\u011f]a|sola|yukar[i\u0131]|a[s\u015f]a[g\u011f][i\u0131])[^.]*?ta[s\u015f][i\u0131]')
  if (-not $mv.Success) {
    $mv = [regex]::Match($low, 'ta[s\u015f][i\u0131][^.]{0,20}?(\d+(?:[.,]\d+)?)\s*mm\s*(sa[g\u011f]a|sola|yukar[i\u0131]|a[s\u015f]a[g\u011f][i\u0131])')
  }
  if ($mv.Success) {
    $amt = Get-EINum $mv.Groups[1].Value
    $dir = [string]$mv.Groups[2].Value
    $dx = 0; $dy = 0
    if ($dir -match '^sa') { $dx = $amt }
    elseif ($dir -match '^sola') { $dx = -$amt }
    elseif ($dir -match '^yukar') { $dy = $amt }
    else { $dy = -$amt }
    if ($low -match 'deli[k\u011fg]|delik') {
      $h = Resolve-EIHole $body $low
      if ($null -eq $h) { return @{ ok = $false; message = "hangi delik tasinacak? (h1 gibi ID belirt)" } }
      if ($h -eq "missing") { return @{ ok = $false; message = "delik bulunamadi" } }
      if ($null -eq $h.center_x_mm -or $null -eq $h.center_y_mm) { return @{ ok = $false; message = "delik merkezi bilinmiyor; once merkez gerekli" } }
      $nx = [double]$h.center_x_mm + $dx
      $ny = [double]$h.center_y_mm + $dy
      $ops.Add(@{ op = "replace"; path = ($bid + ".holes." + [string]$h.id + ".center"); old = @([double]$h.center_x_mm, [double]$h.center_y_mm); value = @($nx, $ny); reason = "tasi"; requires_confirmation = $false }) | Out-Null
      return @{ ok = $true; ops = @($ops.ToArray()) }
    }
    if ($low -match 'kesi[k\u011fg]|kesit|kanal') {
      $t = Resolve-EICutout $body $low
      if ($null -eq $t) { return @{ ok = $false; message = "hangi kesit tasinacak?" } }
      if ($t -eq "missing") { return @{ ok = $false; message = "kesit bulunamadi" } }
      if ($null -eq $t.pos_x_mm -or $null -eq $t.pos_y_mm) { return @{ ok = $false; message = "kesit konumu bilinmiyor" } }
      $ops.Add(@{ op = "replace"; path = ($bid + ".cutouts." + [string]$t.id + ".pos_x_mm"); old = [double]$t.pos_x_mm; value = ([double]$t.pos_x_mm + $dx); reason = "tasi"; requires_confirmation = $false }) | Out-Null
      $ops.Add(@{ op = "replace"; path = ($bid + ".cutouts." + [string]$t.id + ".pos_y_mm"); old = [double]$t.pos_y_mm; value = ([double]$t.pos_y_mm + $dy); reason = "tasi"; requires_confirmation = $false }) | Out-Null
      return @{ ok = $true; ops = @($ops.ToArray()) }
    }
    return @{ ok = $false; message = "tasi hedefi anlasilmadi (delik/kesit belirt)" }
  }
  # Skaler atama: "<alan> N mm yap".
  $nm = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm')
  if (-not $nm.Success) {
    if ($low -match 'biraz|birazc[i\u0131]k') { return @{ ok = $false; message = "belirsiz miktar (biraz): net olcu gerekli" } }
    return @{ ok = $false; message = "anlasilmadi: net olcu ve hedef gerekli" }
  }
  $val = Get-EINum $nm.Groups[1].Value
  if ($low -match 'duvar') {
    if ($null -eq $body.hollow) { return @{ ok = $false; message = "govdede hollow yok; duvar atanamaz" } }
    $ops.Add(@{ op = "replace"; path = ($bid + ".hollow.wall_mm"); old = $body.hollow.wall_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if ($low -match 'taban') {
    if ($null -eq $body.hollow) { return @{ ok = $false; message = "govdede hollow yok; taban atanamaz" } }
    $ops.Add(@{ op = "replace"; path = ($bid + ".hollow.bottom_thickness_mm"); old = $body.hollow.bottom_thickness_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if ($low -match 'geni[s\u015f]li[k\u011fg][i\u0131]?') {
    $ops.Add(@{ op = "replace"; path = ($bid + ".base.width_mm"); old = $body.base.width_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if ($low -match 'y[u\u00fc]ksekli[k\u011fg][i\u0131]?') {
    $ops.Add(@{ op = "replace"; path = ($bid + ".base.height_mm"); old = $body.base.height_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if ($low -match 'derinli[k\u011fg][i\u0131]?' -and -not ($low -match 'deli[k\u011fg]|delik') -and -not ($low -match 'kesi[k\u011fg]|kesit|kanal')) {
    $ops.Add(@{ op = "replace"; path = ($bid + ".base.depth_mm"); old = $body.base.depth_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if (($low -match 'deli[k\u011fg]|delik') -and ($low -match '[c\u00e7]ap')) {
    $h = Resolve-EIHole $body $low
    if ($null -eq $h) { return @{ ok = $false; message = "hangi delik? (h1 gibi ID ya da tek delik)" } }
    if ($h -eq "missing") { return @{ ok = $false; message = "delik bulunamadi" } }
    $ops.Add(@{ op = "replace"; path = ($bid + ".holes." + [string]$h.id + ".diameter_mm"); old = $h.diameter_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if (($low -match 'deli[k\u011fg]|delik') -and ($low -match 'derinli[k\u011fg][i\u0131]?')) {
    $h = Resolve-EIHole $body $low
    if ($null -eq $h) { return @{ ok = $false; message = "hangi delik? (h1 gibi ID ya da tek delik)" } }
    if ($h -eq "missing") { return @{ ok = $false; message = "delik bulunamadi" } }
    $ops.Add(@{ op = "replace"; path = ($bid + ".holes." + [string]$h.id + ".depth_mm"); old = $h.depth_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if ($low -match 'kanal') {
    $chs = @(@($body.cutouts) | Where-Object { $_ -and [string]$_.kind -eq "slot" })
    if ($chs.Count -eq 0) { return @{ ok = $false; message = "kanal bulunamadi" } }
    if ($chs.Count -gt 1) { return @{ ok = $false; message = "birden fazla kanal var; hangisi? (c1 gibi ID belirt)" } }
    $ops.Add(@{ op = "replace"; path = ($bid + ".cutouts." + [string]$chs[0].id + ".width_mm"); old = $chs[0].width_mm; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  if ($low -match 'fillet|yuvarlat') {
    $ops.Add(@{ op = "replace"; path = ($bid + ".edge_notes.fillet"); old = $null; value = $val; reason = "ata"; requires_confirmation = $false }) | Out-Null
    return @{ ok = $true; ops = @($ops.ToArray()) }
  }
  return @{ ok = $false; message = "hedef alan anlasilmadi (duvar/taban/olcu/delik/kesit belirt)" }
}

function Parse-EditIntent($spec, $text) {
  $low = ([string]$text).ToLowerInvariant() -replace ([char]0x307), ""
  # Dosya/isletim hedefleri edit degildir (guvenlik: allowlist disi).
  if ($low -match 'dosya|klas[o\u00f6]r|formatla|format at|\.exe\b|\bdist\b') {
    if ($low -match 'sil|temizle|kaldir|kald[i\u0131]r|yok et') {
      return @{ kind = "not-edit"; ops = @(); message = "BLOCKED: dosya islemleri edit pipeline disidir" }
    }
  }
  # Versiyon niyetleri orchestrator'a birakilir.
  if ($low -match 'undo|geri al|onceki haline') { return @{ kind = "undo"; ops = @(); message = "undo" } }
  if ($low -match 'redo|ileri al|yinele') { return @{ kind = "redo"; ops = @(); message = "redo" } }
  $vm = [regex]::Match($low, '\bv(\d+)\b.*d[o\u00f6]n')
  if ($vm.Success) { return @{ kind = "restore"; ops = @(); message = "restore"; restore_target = ("v" + $vm.Groups[1].Value) } }
  # Negation: ret, edit degildir.
  $negHit = $false
  foreach ($nkw in @('kapak|lid', 'deli[k\u011fg]\w*', 'slot|kanal|kesik', 'fillet|yuvarlat|pah')) {
    foreach ($km in [regex]::Matches($low, $nkw)) { $negHit = $true }
    if ($negHit) { break }
  }
  if ($negHit -and $low -match 'istemiyorum|istemem|olmas[i\u0131]n|\byok\b|ekleme|yapma') {
    return @{ kind = "not-edit"; ops = @(); message = "negation: edit degil" }
  }
  $body = Find-EIBody $spec
  if ($null -eq $body) { return @{ kind = "clarify"; ops = @(); message = "govde bulunamadi" } }
  $clauses = @([regex]::Split($low, '\s+ve\s+') | Where-Object { [string]$_.Trim() -ne "" })
  $allOps = New-Object System.Collections.Generic.List[object]
  foreach ($cl in $clauses) {
    $r = Parse-EditClause $spec $body ([string]$cl)
    if (-not $r.ok) { return @{ kind = "clarify"; ops = @(); message = [string]$r.message } }
    foreach ($o in @($r.ops)) { $allOps.Add($o) | Out-Null }
  }
  if ($allOps.Count -eq 0) { return @{ kind = "clarify"; ops = @(); message = "islem cikarilamadi" } }
  return @{ kind = "patch"; ops = @($allOps.ToArray()); message = "ok" }
}
