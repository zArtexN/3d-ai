<#
.SYNOPSIS
  Turkce dogal dil -> DesignSpec v2. Bulamadigi kritik degeri missing birakir (UYDURMAZ).
.DESCRIPTION
  Anladigi kalipar (sayilar mm, ondalik nokta/virgul):
    govde: "80x40x20", "80x40x20 kutu/govde/blok"
    silindir: "silindir", "cap 30", "yukseklik/boy 40"
    boru/tube: "boru", "dis cap 30", "ic cap 20"
    delik: "delik 20" + "merkez 15,15"; "kor delik 10 derinlik 5"; "havsa"; "gomme"
    slot/kesik: "slot", "kanal", "kesik", "aciklik" + "20x10" + "on/ust"
    hollow: "icini bosalt"/"ici bos" + "duvar 2.5" + "ustu acik"
    kapak: "kapak" (+ "0.2 bosluk")
    tolerans: "0.2 mm bosluk", "tolerans 0.2", "biraz gevsek/siki" -> soru uretir
    transform: "Z ekseninde 90 derece dondur", "ayna X"
    kenar: "yuvarlat 5", "pah kir 2"
    cok parca: "iki parca", "kapak + govde", "taban + destek"
  Cikti: spec JSON (dosyaya -OutPath ile) + sorular (ekranda / -QuestionsJson ile).
  Belirsiz ama kritik ifade ("biraz gevsek") -> tolerans sorusu uretir, deger UYDURMAZ.
.EXAMPLE
  powershell -File engine\ConvertTo-GeometrySpec.ps1 -Prompt "80x40x20 kutu, delik 20" -ProjectName "deneme" -OutPath projects\deneme\spec.json
#>
param(
  [Parameter(Mandatory = $true)][string]$Prompt,
  [Parameter(Mandatory = $true)][string]$ProjectName,
  [string]$OutPath = "",
  [string]$QuestionsJson = ""
)

$ErrorActionPreference = "Stop"

# Adim B: ortak olcu cozucu (saf kutuphane; param blogu yok, scope kirletmez).
. (Join-Path $PSScriptRoot "MeasureParser.ps1")
# Adim C: delik yerlesim matematigi (tek deterministik kaynak; parser tahmin etmez).
. (Join-Path $PSScriptRoot "HoleLayout.ps1")
# Claim kaydi: bir mention yalnizca bir anahtar kelimeye atanir (ArrayList; @() kullanma).
$mpClaimed = New-Object System.Collections.ArrayList

function Get-Num($s) { return [double]($s -replace ',', '.') }
# Uclu govde olcusu kalibi (ASCII-safe): ayirac x X * U+00D7 U+2715 U+2716 U+2A2F + "carpi";
# sayi-arasi birim ("160mm x 100mm x 45mm") toleransli.
$DimSepRx = '(?:[xX\*\u00d7\u2715\u2716\u2a2f]|[c\u00e7]arp[i\u0131])'
$DimTriplePat = '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?' + $DimSepRx + '\s*(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?' + $DimSepRx + '\s*(\d+(?:[.,]\d+)?)'
function Find-BodyDims($t) {
  # Tum uclu adaylari topla, govde baglamina gore skorla (deterministik; ilk-eslesme degil).
  # Govde ipucu (+3): govde/body/kutu/organizer/kasa/blok/dis olcu/ana govde yakinligi.
  # Takip eden "mm" (+1). Feature baglami (-4): delik/vida/slot/kanal/kesik/duvar/bosluk/
  # derinlik/merkez/konum/cap yakinindaki uclu baska parcaya aittir, govde sanilmaz.
  # Esitlikte ilk aday kazanir. Donus: @{dims;index;length} ya da $null.
  $all = [regex]::Matches($t, $script:DimTriplePat)
  if ($all.Count -eq 0) { return $null }
  $bodyRx = 'g[o\u00f6]vde|body|organizer|kasa|blok|kutu|d[i\u0131][s\u015f]\s*[o\u00f6]l[c\u00e7][u\u00fc]|ana\s*(g[o\u00f6]vde|par[c\u00e7]a|kut|blok)'
  $featRx = 'delik|vida|\bm\d|slot|kanal|kesik|a[c\u00e7][i\u0131]kl[i\u0131]k|duvar|bo[s\u015f]luk|derinlik|merkez|konum|[c\u00e7]ap|hav[s\u015f]a|g[o\u00f6]mme|yiv'
  $best = $null; $bestScore = -9999
  foreach ($m in $all) {
    $score = 0
    $preStart = [Math]::Max(0, $m.Index - 45)
    $pre = $t.Substring($preStart, $m.Index - $preStart)
    $post = ""
    $postLen = [Math]::Min(35, $t.Length - ($m.Index + $m.Length))
    if ($postLen -gt 0) { $post = $t.Substring($m.Index + $m.Length, $postLen) }
    $nearPre = $pre
    if ($nearPre.Length -gt 15) { $nearPre = $nearPre.Substring($nearPre.Length - 15) }
    $nearPost = $post
    if ($nearPost.Length -gt 15) { $nearPost = $nearPost.Substring(0, 15) }
    $nearBoth = $nearPre + " " + $nearPost
    if ([regex]::IsMatch($nearBoth, $bodyRx)) { $score += 3 }
    elseif ([regex]::IsMatch($pre, $bodyRx) -or [regex]::IsMatch($post, $bodyRx)) { $score += 1 }
    if ([regex]::IsMatch($nearBoth, $featRx)) { $score -= 4 }
    if ($post -match '^\s*mm\b') { $score += 1 }
    if ($score -gt $bestScore) {
      $bestScore = $score
      $best = @{ dims = @((Get-Num $m.Groups[1].Value), (Get-Num $m.Groups[2].Value), (Get-Num $m.Groups[3].Value)); index = $m.Index; length = $m.Length }
    }
  }
  return $best
}
function Find-One($t, $pat) {
  $m = [regex]::Match($t, $pat)
  if ($m.Success) { return (Get-Num $m.Groups[1].Value) }
  return $null
}

$low = $Prompt.ToLowerInvariant() -replace "\u0307", ""
# Birim normalizasyonu (canonical mm): "16 cm" -> "160 mm". Nokta/virgul ondalik korunur.
$low = [regex]::Replace($low, '(\d+(?:[.,]\d+)?)\s*cm\b', { param($m) ((Get-Num $m.Groups[1].Value) * 10).ToString() + " mm" })
$low = [regex]::Replace($low, '(\d+(?:[.,]\d+)?)\s*(inch|in[c\u00e7])\b', { param($m) ([Math]::Round((Get-Num $m.Groups[1].Value) * 25.4, 3)).ToString() + " mm" })
$questions = New-Object System.Collections.Generic.List[string]

$components = New-Object System.Collections.Generic.List[object]
$comp = [pscustomobject]@{
  id = "body"; label = "ana govde"
  base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }
  hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
}

$handled = $false
$bodySpan = $null
if ($low -match "boru" -or $low -match "tube") {
  $od = Find-One $low 'dis\s*cap\s*(\d+(?:[.,]\d+)?)'
  $idv = Find-One $low 'i[c\u00e7]\s*cap\s*(\d+(?:[.,]\d+)?)'
  $hh = Find-One $low '(?:boy|y[u\u00fc]kseklik)\s*(\d+(?:[.,]\d+)?)'
  if ($null -eq $od) { $questions.Add("Borunun dis capi nedir? (ornek: dis cap 30)") }
  if ($null -eq $idv) { $questions.Add("Borunun ic capi nedir? (ornek: ic cap 20)") }
  if ($null -eq $hh) { $questions.Add("Borunun boyu/yuksekligi nedir? (ornek: boy 40)") }
  $comp.base = [pscustomobject]@{ shape = "tube"; outer_diameter_mm = $od; inner_diameter_mm = $idv; height_mm = $hh }
  $handled = $true
} elseif ($low -match "silindir") {
  $dd = Find-One $low '[c\u00e7]ap\s*(\d+(?:[.,]\d+)?)'
  $hh = Find-One $low '(?:boy|y[u\u00fc]kseklik)\s*(\d+(?:[.,]\d+)?)'
  if ($null -eq $dd) { $questions.Add("Silindirin capi nedir? (ornek: cap 30)") }
  if ($null -eq $hh) { $questions.Add("Silindirin yuksekligi nedir? (ornek: yukseklik 40)") }
  $comp.base = [pscustomobject]@{ shape = "cylinder"; diameter_mm = $dd; height_mm = $hh; axis = "z" }
  $handled = $true
}
if (-not $handled) {
  $found = Find-BodyDims $low
  if ($null -eq $found) { $questions.Add("Govde olculeri anlasilmadi. Ornek: 80x40x20 (mm). Govde olcusu nedir?") }
  else { $comp.base.width_mm = $found.dims[0]; $comp.base.depth_mm = $found.dims[1]; $comp.base.height_mm = $found.dims[2]; $bodySpan = @{ index = $found.index; length = $found.length } }
}

# UST-YON global: "Ustu acik/kapali olsun" duvar-dalinda da gecerli (hollow varsa uygulanir).
# Esdeger acik-ifadeler: "ustu acik olacak", "ust kismi acik", "ustten acik", "kapaksiz".
$openTop = $null
if ($low -match "[u\u00fc]st[u\u00fc]\s*a[c\u00e7][i\u0131]k" -or $low -match "[u\u00fc]stten\s*a[c\u00e7][i\u0131]k" -or $low -match "[u\u00fc]st\s*k[i\u0131]sm[i\u0131]\s*a[c\u00e7][i\u0131]k" -or $low -match "kapaks[i\u0131]z") { $openTop = $true }
elseif ($low -match "kapal[i\u0131]") { $openTop = $false }
$bottomTh = $null
$btmM = Find-Measure $low 'taban(?:[i\u0131]|n[i\u0131]|y[i\u0131]|[ae])?' 60 $mpClaimed "" 70 @($bodySpan)
if ($null -ne $btmM) { $bottomTh = [double]$btmM.value }

if ($low -match "i[c\u00e7]ini bo[s\u015f]alt" -or $low -match "i[c\u00e7]i bo[s\u015f]") {
  $wl = $null
  $wlM = Find-Measure $low 'duvar(?:lar)?[i\u0131]?' 60 $mpClaimed "" 70 @($bodySpan)
  if ($null -ne $wlM) { $wl = [double]$wlM.value }
  if ($null -eq $wl) { $questions.Add("Duvar kalinligi nedir? (ornek: duvar 2.5). Uydurulamaz.") }
  $comp.hollow = [pscustomobject]@{ wall_mm = $wl; open_top = $openTop; bottom_thickness_mm = $bottomTh }
} else {
  $wlOnly = $null
  $wlOnlyM = Find-Measure $low 'duvar(?:lar)?[i\u0131]?' 60 $mpClaimed "" 70 @($bodySpan)
  if ($null -ne $wlOnlyM) { $wlOnly = [double]$wlOnlyM.value }
  if ($null -ne $wlOnly) {
    $comp.hollow = [pscustomobject]@{ wall_mm = $wlOnly; open_top = $openTop; bottom_thickness_mm = $bottomTh }
  } elseif ($null -ne $openTop) {
    # "Ustu acik/kapali olsun" tek basina ici-bos govde gerektirir; duvar sorulur (uydurulmaz).
    $comp.hollow = [pscustomobject]@{ wall_mm = $null; open_top = $openTop; bottom_thickness_mm = $bottomTh }
    $questions.Add("Duvar kalinligi nedir? (ornek: duvar 2.5). Uydurulamaz.")
  } elseif ($null -ne $bottomTh) {
    $comp.hollow = [pscustomobject]@{ wall_mm = $null; open_top = $null; bottom_thickness_mm = $bottomTh }
    $questions.Add("Duvar kalinligi nedir? (ornek: duvar 2.5). Uydurulamaz.")
  }
}

$holeStemRx = 'deli[k\u011fg]\w*'
$cbCtxRx = 'counterbore|g[o\u00f6]mme'
$diaVal = $null
foreach ($om in [regex]::Matches($low, '[\u00d8\u00f8]\s*(\d+(?:[.,]\d+)?)')) {
  # Counterbore/havsa baglamindaki cap (örn. "Ø8 mm çapında ... counterbore") ana cap sanilmaz.
  $tail = ""
  if (($low.Length - $om.Index) -gt 1) { $tail = $low.Substring($om.Index + 1, [Math]::Min(60, $low.Length - $om.Index - 1)) }
  if ($tail -match '^\s*\d[\d.,]*\s*mm\s*([c\u00e7]ap[i\u0131]nda|derinli[k\u011fg])') { continue }
  if ($tail -match $cbCtxRx) { continue }
  $diaVal = (Get-Num $om.Groups[1].Value)
  break
}
if ($null -eq $diaVal) {
  foreach ($cm in [regex]::Matches($low, '(?<!\w)[c\u00e7]ap[i\u0131]?\s*(\d+(?:[.,]\d+)?)')) {
    # "cap 30 yukseklik 40 silindir" silindir capidir, delik degil: delik baglami sart.
    $cmCtx = $false
    foreach ($smx in [regex]::Matches($low, $holeStemRx)) {
      if ([Math]::Abs($cm.Index - $smx.Index) -le 40) { $cmCtx = $true }
    }
    if (-not $cmCtx) { continue }
    $cmWin = $low.Substring([Math]::Max(0, $cm.Index - 30), [Math]::Min(60, $low.Length - [Math]::Max(0, $cm.Index - 30)))
    if ($cmWin -match $cbCtxRx) { continue }
    $diaVal = (Get-Num $cm.Groups[1].Value)
    break
  }
}
if ($null -eq $diaVal) {
  $hm = [regex]::Match($low, $holeStemRx + '\s*(\d+(?:[.,]\d+)?)')
  if ($hm.Success) { $diaVal = (Get-Num $hm.Groups[1].Value) }
  else {
    $hm3 = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*[c\u00e7]ap[i\u0131]nda\s*(\w+\s+){0,5}deli[k\u011fg]\w*')
    if ($hm3.Success) { $diaVal = (Get-Num $hm3.Groups[1].Value) }
  }
}
$typeKw = $null
if ($low -match "ge[c\u00e7]i[s\u015f]li" -or $low -match "d[u\u00fc]z\s*ge[c\u00e7]i[s\u015f]" -or $low -match "tamamen\s*ge[c\u00e7]\w*" -or $low -match "ge[c\u00e7]sin\w*") { $typeKw = "through" }
elseif ($low -match "\bk[o\u00f6]r\w{0,2}\b") { $typeKw = "blind" }
elseif ($low -match "hav[s\u015f]a") { $typeKw = "countersink" }
elseif ($low -match "g[o\u00f6]mme" -or $low -match "counterbore") { $typeKw = "counterbore" }
$mentionsHole = ([regex]::IsMatch($low, $holeStemRx)) -or ($low -match "kenardan")
if ($null -eq $diaVal -and ($null -ne $typeKw -or $mentionsHole)) {
  $comp.holes = @([pscustomobject]@{
    id = "h1"; hole_type = $(if ($null -ne $typeKw) { $typeKw } else { "through" }); diameter_mm = $null
    center_x_mm = $null; center_y_mm = $null; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "missing"
  })
  $questions.Add("Delik capi ve merkezi nedir? Ornek: delik 20 merkez 15,15.")
}
if ($null -ne $diaVal) {
  $htype = "through"
  if ($null -ne $typeKw) { $htype = $typeKw }
  $mc = [regex]::Match($low, 'merkez\s*(\d+(?:[.,]\d+)?)\s*[,;]\s*(\d+(?:[.,]\d+)?)')
  $hole = [pscustomobject]@{
    id = "h1"; hole_type = $htype; diameter_mm = $diaVal
    center_x_mm = $null; center_y_mm = $null; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = "missing"
  }
  if ($mc.Success) {
    $hole.center_x_mm = (Get-Num $mc.Groups[1].Value); $hole.center_y_mm = (Get-Num $mc.Groups[2].Value); $hole.status = "ok"
  } else {
    $edgeDone = $false
    $edgeOffVal = $null
    # Kenar ofseti: tum "kenardan N" adaylarindan delik govdesine en yakin secilir
    # ("alt kenardan 12" kablo ofseti delik ofseti sanilmaz).
    $bestEo = $null; $bestEoDist = 999999
    $stemIdx2 = -1
    $stemM2 = [regex]::Match($low, $holeStemRx)
    if ($stemM2.Success) { $stemIdx2 = $stemM2.Index }
    foreach ($emc in [regex]::Matches($low, '(?:kenar(?:lardan|dan)|kenar\s*pay[i\u0131]|k[o\u00f6][s\u015f]e\w*den|iki\s*kenardan)\s*(\d+(?:[.,]\d+)?)')) {
      $dd = 0
      if ($stemIdx2 -ge 0) { $dd = [Math]::Abs($emc.Index - $stemIdx2) }
      if ($dd -lt $bestEoDist) { $bestEoDist = $dd; $bestEo = $emc }
    }
    if ($null -ne $bestEo) {
      $ev = Get-Num $bestEo.Groups[1].Value
      $hole.center_x_mm = $ev; $hole.center_y_mm = $ev; $hole.status = "ok"
      $edgeOffVal = $ev
      $edgeDone = $true
    }
    if (-not $edgeDone) {
      $sm2 = [regex]::Match($low, 'sa[g\u011f]dan\s*(\d+(?:[.,]\d+)?)[^.;]*?alttan\s*(\d+(?:[.,]\d+)?)')
      $sm3 = [regex]::Match($low, 'soldan\s*(\d+(?:[.,]\d+)?)[^.;]*?alttan\s*(\d+(?:[.,]\d+)?)')
      $sm4 = [regex]::Match($low, 'sa[g\u011f]dan\s*(\d+(?:[.,]\d+)?)[^.;]*?[u\u00fc]stten\s*(\d+(?:[.,]\d+)?)')
      $sm5 = [regex]::Match($low, 'soldan\s*(\d+(?:[.,]\d+)?)[^.;]*?[u\u00fc]stten\s*(\d+(?:[.,]\d+)?)')
      if ($sm2.Success -and $comp.base.width_mm) {
        $hole.center_x_mm = ([double]$comp.base.width_mm - (Get-Num $sm2.Groups[1].Value))
        $hole.center_y_mm = (Get-Num $sm2.Groups[2].Value); $hole.status = "ok"; $edgeDone = $true
      } elseif ($sm3.Success) {
        $hole.center_x_mm = (Get-Num $sm3.Groups[1].Value)
        $hole.center_y_mm = (Get-Num $sm3.Groups[2].Value); $hole.status = "ok"; $edgeDone = $true
      } elseif ($sm4.Success -and $comp.base.width_mm -and $comp.base.depth_mm) {
        $hole.center_x_mm = ([double]$comp.base.width_mm - (Get-Num $sm4.Groups[1].Value))
        $hole.center_y_mm = ([double]$comp.base.depth_mm - (Get-Num $sm4.Groups[2].Value)); $hole.status = "ok"; $edgeDone = $true
      } elseif ($sm5.Success -and $comp.base.depth_mm) {
        $hole.center_x_mm = (Get-Num $sm5.Groups[1].Value)
        $hole.center_y_mm = ([double]$comp.base.depth_mm - (Get-Num $sm5.Groups[2].Value)); $hole.status = "ok"; $edgeDone = $true
      }
    }
    if (-not $edgeDone) {
      $questions.Add("Delik merkezi eksik (kritik olcu, uydurulamaz). Ornek: merkez 15,15 (referans koseden mm).")
    }
  }
  if ($htype -eq "blind") {
    $bd = Find-One $low 'derinli[k\u011fg]\w*\s*(\d+(?:[.,]\d+)?)'
    if ($null -eq $bd) { $questions.Add("Kor deligin derinligi nedir? (ornek: derinlik 5)") }
    else { $hole.depth_mm = $bd }
  }
  $sm = [regex]::Match($low, '\b(m\d+)\b')
  if ($sm.Success) { $hole.screw = $sm.Groups[1].Value.ToUpperInvariant() }
  $comp.holes = @($hole)
  $holeN = $null
  $hmN = [regex]::Match($low, '(?<![\d.,])(\d+)\s*deli[k\u011fg]\w*')
  if ($hmN.Success) { $holeN = [int]$hmN.Groups[1].Value }
  else {
    # "4 adet ... deligi": adet sayisini HERHANGI delik govdesine en yakin olandan al (60 karakter icinde).
    $stemIdxs = @()
    foreach ($smx in [regex]::Matches($low, $holeStemRx)) { $stemIdxs += $smx.Index }
    $bestAdet = $null; $bestAdetDist = 999999
    foreach ($am in [regex]::Matches($low, '(\d+)\s*(?:adet|tane)')) {
      foreach ($si in $stemIdxs) {
        $dd = [Math]::Abs($am.Index - $si)
        if ($dd -lt $bestAdetDist -and $dd -le 60) { $bestAdetDist = $dd; $bestAdet = [int]$am.Groups[1].Value }
      }
    }
    if ($null -ne $bestAdet) { $holeN = $bestAdet }
  }
  if ($null -eq $holeN) {
    if ($low -match "iki\s*deli[k\u011fg]") { $holeN = 2 }
    elseif ($low -match "[u\u00fc][c\u00e7]\s*deli[k\u011fg]") { $holeN = 3 }
    elseif ($low -match "d[o\u00f6]rt\s*deli[k\u011fg]") { $holeN = 4 }
  }
  if ($null -ne $holeN -and $holeN -gt 1 -and $holeN -le 8) {
    $extra = New-Object System.Collections.Generic.List[object]
    $extra.Add($hole) | Out-Null
    for ($hi = 2; $hi -le $holeN; $hi++) {
      $clone = [pscustomobject]@{
        id = ("h" + $hi); hole_type = $hole.hole_type; diameter_mm = $hole.diameter_mm
        center_x_mm = $null; center_y_mm = $null; axis = "z"
        depth_mm = $hole.depth_mm; cs_dia_mm = $hole.cs_dia_mm; cs_depth_mm = $hole.cs_depth_mm
        cb_dia_mm = $hole.cb_dia_mm; cb_depth_mm = $hole.cb_depth_mm
        screw = $null; status = "missing"
      }
      $extra.Add($clone) | Out-Null
    }
    $comp.holes = $extra.ToArray()
  }
  # Counterbore olculeri: "8 mm capinda 3 mm derinliginde counterbore/gomme" ->
  # counterbore/gomme anahtarina en yakin cap + derinlik (40 karakter icinde).
  if ($low -match "counterbore" -or $low -match "g[o\u00f6]mme") {
    $cbDia = $null; $cbDep = $null; $bestCb = 999999
    foreach ($cm in [regex]::Matches($low, '(\d+(?:[.,]\d+)?)\s*mm\s*[c\u00e7]ap[i\u0131]nda')) {
      foreach ($km in [regex]::Matches($low, 'counterbore|g[o\u00f6]mme')) {
        $dd = [Math]::Abs($cm.Index - $km.Index)
        if ($dd -lt $bestCb -and $dd -le 40) { $bestCb = $dd; $cbDia = (Get-Num $cm.Groups[1].Value) }
      }
    }
    $bestCb = 999999
    foreach ($dm in [regex]::Matches($low, '(\d+(?:[.,]\d+)?)\s*mm\s*derinli[k\u011fg]\w*')) {
      foreach ($km in [regex]::Matches($low, 'counterbore|g[o\u00f6]mme')) {
        $dd = [Math]::Abs($dm.Index - $km.Index)
        if ($dd -lt $bestCb -and $dd -le 40) { $bestCb = $dd; $cbDep = (Get-Num $dm.Groups[1].Value) }
      }
    }
    if ($null -ne $cbDia -or $null -ne $cbDep) {
      foreach ($hh in @($comp.holes)) {
        if ($null -eq $hh) { continue }
        if ([string]$hh.id -like "mp*") { continue }
        if ($null -ne $cbDia) { $hh.cb_dia_mm = $cbDia }
        if ($null -ne $cbDep) { $hh.cb_depth_mm = $cbDep }
      }
    }
  }
  # Secilen kenar ofseti deliklere islenir (montaj-noktalari haric; kesin konum sorusu ayri kalir).
  if ($null -ne $edgeOffVal) {
    foreach ($hh in @($comp.holes)) {
      if ($null -eq $hh) { continue }
      if ([string]$hh.id -like "mp*") { continue }
      $hh | Add-Member -NotePropertyName "edge_offset_mm" -NotePropertyValue $edgeOffVal -Force
    }
  }
  # Semantic hole pattern (Adim C): baglam yeterliyse corner/mid-edge.
  # Oncelik: explicit mid-edge > explicit corner > derived corner.
  # "kenar ortalarinda/mid-edge" varken corner DERIVED edilmez; inkar cumlesi
  # ("koselerde degil") ayri mantik gerektirmez (explicit her zaman kazanir).
  # Koordinatlar burada TAHMIN edilmez; HoleLayout.ps1 deterministik uretir
  # (compiler ayni fonksiyonla yeniden uretir).
  if ($null -ne $holeN -and $holeN -eq 4 -and $null -ne $edgeOffVal -and $null -ne $comp.base -and ($comp.base.shape -eq "box" -or $comp.base.shape -eq "rounded_box")) {
    $bw = 0; $bd = 0
    if ($null -ne $comp.base.width_mm) { $bw = [double]$comp.base.width_mm }
    if ($null -ne $comp.base.depth_mm) { $bd = [double]$comp.base.depth_mm }
    $stemIdxs3 = @()
    foreach ($smx in [regex]::Matches($low, $holeStemRx)) { $stemIdxs3 += $smx.Index }
    $midExp = $false
    foreach ($km in [regex]::Matches($low, 'kenar\s*ortalar[i\u0131]nda|mid-edge|uzun\s*kenarlar[i\u0131]n\s*ortas[i\u0131]nda|yan\s*y[u\u00fc]zlerin\s*ortas[i\u0131]nda')) {
      foreach ($si in $stemIdxs3) {
        if ([Math]::Abs($km.Index - $si) -le 60) { $midExp = $true }
      }
    }
    $cornerExp = $false
    foreach ($km in [regex]::Matches($low, 'k[o\u00f6][s\u015f]e\w*')) {
      foreach ($si in $stemIdxs3) {
        if ([Math]::Abs($km.Index - $si) -le 50) { $cornerExp = $true }
      }
    }
    $offCtx = $false
    foreach ($km in [regex]::Matches($low, '(?:kenar(?:lardan|dan)|kenar\s*pay[i\u0131]|d[i\u0131][s\u015f]\s*kenarlardan|k[o\u00f6][s\u015f]e\w*den)\s*\d')) {
      foreach ($si in $stemIdxs3) {
        if ([Math]::Abs($km.Index - $si) -le 60) { $offCtx = $true }
      }
    }
    $symTrig = $false
    if ($low -match "her\s*deli") { $symTrig = $true }
    elseif ($low -match "simetrik") {
      foreach ($smx in [regex]::Matches($low, $holeStemRx)) {
        foreach ($kmx in [regex]::Matches($low, "simetrik")) {
          if ([Math]::Abs($smx.Index - $kmx.Index) -le 50) { $symTrig = $true }
        }
      }
    }
    $layType = $null; $layProv = ""; $layFrom = @()
    if ($midExp) { $layType = "mid_edge"; $layProv = "explicit"; $layFrom = @() }
    elseif ($cornerExp) { $layType = "corner_pattern"; $layProv = "explicit"; $layFrom = @() }
    elseif (($offCtx -or $symTrig) -and $bw -gt 0 -and $bd -gt 0) {
      $layType = "corner_pattern"; $layProv = "derived"
      $layFrom = @(("hole_count=" + $holeN), "rectangular_body", ("edge_offset=" + $edgeOffVal))
    }
    if ($null -ne $layType -and $bw -gt 0 -and $bd -gt 0) {
      $off = [double]$edgeOffVal
      $rr = 0
      if ($null -ne $hole.diameter_mm) { $rr = [double]$hole.diameter_mm / 2 }
      $centers = Get-PatternCenters $layType $bw $bd $off
      $fits = ($null -ne $centers -and $off -gt 0)
      foreach ($cn in $centers) {
        if (-not ($cn[0] - $rr -ge 0 -and $cn[0] + $rr -le $bw -and $cn[1] - $rr -ge 0 -and $cn[1] + $rr -le $bd)) { $fits = $false }
      }
      if ($fits) {
        $comp | Add-Member -NotePropertyName "hole_pattern" -NotePropertyValue ([pscustomobject]@{
          type = $layType; count = $holeN; diameter_mm = $hole.diameter_mm; edge_offset_mm = $off
          depth = [pscustomobject]@{ type = $htype }
          placement = [pscustomobject]@{ reference = "outer_body_rectangle" }
          provenance = $layProv; derived_from = @($layFrom)
        }) -Force
        $posNames = @("p1", "p2", "p3", "p4")
        if ($layType -eq "corner_pattern") { $posNames = @("bottom_left", "bottom_right", "top_left", "top_right") }
        else { $posNames = @("bottom_mid", "top_mid", "left_mid", "right_mid") }
        $ci = 0
        foreach ($hh in @($comp.holes)) {
          if ($null -eq $hh -or $ci -ge 4) { continue }
          if ([string]$hh.id -like "mp*") { continue }
          $hh.center_x_mm = $centers[$ci][0]; $hh.center_y_mm = $centers[$ci][1]; $hh.status = "ok"
          $hh | Add-Member -NotePropertyName "placement" -NotePropertyValue ([pscustomobject]@{ type = $layType; position = $posNames[$ci]; provenance = $layProv; edge_offset_mm = $off; rule = "deterministic: HoleLayout.ps1" }) -Force
          $ci++
        }
      }
    }
  }
}

# Montaj noktalari: "4 kapak montaj noktasi" bir kapak DEGIL, govde ozelligidir.
# Olcu/konum verilmedikce pilot-delik adayi olarak (capi+merkezi sorulur, thread uydurulmaz).
$mpm = [regex]::Match($low, '(\d+)\s*(?:kapak\s+)?montaj\s*nokta')
if ($mpm.Success) {
  $mpN = [int]$mpm.Groups[1].Value
  if ($mpN -ge 1 -and $mpN -le 8) {
    $mpList = @($comp.holes)
    for ($mpi = 1; $mpi -le $mpN; $mpi++) {
      $mpList += [pscustomobject]@{
        id = ("mp" + $mpi); hole_type = "through"; diameter_mm = $null
        center_x_mm = $null; center_y_mm = $null; axis = "z"
        depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
        screw = $null; status = "missing"; purpose = "mounting"
      }
    }
    $comp.holes = @($mpList)
  }
}

if ($low -match "slot" -or $low -match "kanal" -or $low -match "kesik" -or $low -match "a[c\u00e7][i\u0131]kl[i\u0131][k\u011fg]") {
  # Ikili olcu: govde uclusunun parcasi olamaz (lookahead), govde spaniyla cakisan
  # aday atilir; kalanlar icinden slot anahtar kelimesine en yakin secilir.
  $pairPat = '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?' + $DimSepRx + '\s*(\d+(?:[.,]\d+)?)(?!\s*(?:mm\s*)?' + $DimSepRx + '\s*\d)'
  $slotKwRx = 'slot|kanal|kesik|a[c\u00e7][i\u0131]kl[i\u0131][k\u011fg]'
  $bestPair = $null; $bestDist = 999999
  foreach ($cand in [regex]::Matches($low, $pairPat)) {
    $overlap = $false
    if ($null -ne $bodySpan) {
      $candEnd = $cand.Index + $cand.Length
      $bodyEnd = $bodySpan.index + $bodySpan.length
      if ($cand.Index -lt $bodyEnd -and $bodySpan.index -lt $candEnd) { $overlap = $true }
    }
    if ($overlap) { continue }
    $dist = 999999
    foreach ($km in [regex]::Matches($low, $slotKwRx)) {
      $dd = [Math]::Abs($cand.Index - $km.Index)
      if ($dd -lt $dist) { $dist = $dd }
    }
    if ($dist -lt $bestDist) { $bestDist = $dist; $bestPair = $cand }
  }
  $sd = $bestPair
  $cut = [pscustomobject]@{ id = "c1"; kind = "rect"; face = "front"; pos_x_mm = $null; pos_y_mm = $null; width_mm = $null; length_mm = $null; depth_mm = $null; status = "missing" }
  if ($low -match "slot" -or $low -match "kanal") { $cut.kind = "slot" }
  # Yuz cozumu: yuz anahtar kelimelerinden slot-bildirime en yakin (uzaktaki "Ustu acik" calinmaz).
  $faceCands = @()
  foreach ($fm in [regex]::Matches($low, '(?<!\w)[o\u00f6]n')) { $faceCands += @{ f = "front"; i = $fm.Index } }
  foreach ($fm in [regex]::Matches($low, '(?<!\w)arka')) { $faceCands += @{ f = "rear"; i = $fm.Index } }
  foreach ($fm in [regex]::Matches($low, '(?<!\w)[u\u00fc]st')) { $faceCands += @{ f = "top"; i = $fm.Index } }
  foreach ($fm in [regex]::Matches($low, '(?<!\w)yan')) { $faceCands += @{ f = "front"; i = $fm.Index } }
  $slotRefIdx = -1
  $slotRefM = [regex]::Match($low, $slotKwRx)
  if ($slotRefM.Success) { $slotRefIdx = $slotRefM.Index }
  $bestFace = "front"; $bestFaceDist = 999999
  foreach ($fc in $faceCands) {
    if ($slotRefIdx -ge 0) {
      $fdd = [Math]::Abs($fc.i - $slotRefIdx)
      if ($fdd -lt $bestFaceDist -and $fdd -le 60) { $bestFaceDist = $fdd; $bestFace = $fc.f }
    }
  }
  $cut.face = $bestFace
  # Kisa/uzun kenar baglami: on/arka yuzde yuz adina islenir (edge_*); geometri ayni kalir.
  if ($cut.face -eq "front" -or $cut.face -eq "rear") {
    $edgeCtx = ""
    if ($slotRefIdx -ge 0) {
      foreach ($km in [regex]::Matches($low, 'k[i\u0131]sa\s*kenar')) {
        if ([Math]::Abs($km.Index - $slotRefIdx) -le 50) { $edgeCtx = "short_edge" }
      }
      foreach ($km in [regex]::Matches($low, 'uzun\s*kenar')) {
        if ([Math]::Abs($km.Index - $slotRefIdx) -le 50 -and $edgeCtx -eq "") { $edgeCtx = "long_edge" }
      }
    }
    if ($edgeCtx -ne "") { $cut.face = [string]$cut.face + "_" + $edgeCtx }
  }
  $faceBase = ([string]$cut.face -replace '_short_edge$','' -replace '_long_edge$','')
  if ($null -ne $sd) { $cut.width_mm = (Get-Num $sd.Groups[1].Value); $cut.length_mm = (Get-Num $sd.Groups[2].Value) }
  else { $questions.Add("Kesik 'c1' olcusu belirtilmemis. Genişlik x yukseklik nedir? (ornek: 20x10 mm)") }
  $pm = [regex]::Match($low, 'konum\s*(\d+(?:[.,]\d+)?)\s*[,;]\s*(\d+(?:[.,]\d+)?)')
  if ($pm.Success) { $cut.pos_x_mm = (Get-Num $pm.Groups[1].Value); $cut.pos_y_mm = (Get-Num $pm.Groups[2].Value); $cut.depth_mm = 10 }
  else {
    # Kenar ofsetleri: "alt kenardan 12 mm" / "alttan 12 mm" / "tabandan 12 mm" -> pos_y;
    # "soldan 5 mm" -> pos_x (dogrudan referans). "tabandan" taban-kalinligi degildir (tam-kelime).
    # Ustten/sagdan hesaplanmaz (yon belirsizligi); eksikse soru sorulur (uydurulmaz).
    $by = [regex]::Match($low, '(?:alttan\s*|tabandan\s*|alt\s*kenar(?:dan|[i\u0131]\w*)\s*(?:tabandan\s*)?)(\d+(?:[.,]\d+)?)')
    if ($by.Success) {
      $cut.pos_y_mm = (Get-Num $by.Groups[1].Value)
      $cut | Add-Member -NotePropertyName "vertical" -NotePropertyValue ([pscustomobject]@{ type = "edge_offset"; reference = "bottom"; value = (Get-Num $by.Groups[1].Value); provenance = "explicit" }) -Force
    }
    $bx = [regex]::Match($low, 'soldan\s*(\d+(?:[.,]\d+)?)')
    if ($bx.Success) { $cut.pos_x_mm = (Get-Num $bx.Groups[1].Value) }
    $questions.Add("Kesigin konumu ve derinligi nedir? (ornek: konum 5,5 derinlik 8)")
  }
  # TURETIMLER (explicit geometric rules, tahmin degil):
  # 1) "ortasinda/ortada/merkezinde" + on/arka yuz + govde genisligi -> pos_x = (bw - cutW)/2.
  # 2) yan-yuz kesigi duvari deler -> penetration through_wall, depth = duvar kalinligi.
  $bw2 = 0
  if ($null -ne $comp.base -and $null -ne $comp.base.width_mm) { $bw2 = [double]$comp.base.width_mm }
  if ($null -eq $cut.pos_x_mm -and $null -ne $cut.width_mm -and $bw2 -gt 0 -and ($faceBase -eq "front" -or $faceBase -eq "rear")) {
    $centered = $false
    foreach ($smx in [regex]::Matches($low, $slotKwRx)) {
      foreach ($kmx in [regex]::Matches($low, "ortas[i\u0131]nda|ortada|merkezinde|ortalanm[i\u0131u\u00fc][s\u015f]")) {
        if ([Math]::Abs($smx.Index - $kmx.Index) -le 50) { $centered = $true }
      }
    }
    if ($centered) {
      $px = ($bw2 - [double]$cut.width_mm) / 2
      if ($px -ge 0 -and ($px + [double]$cut.width_mm) -le $bw2) {
        $cut.pos_x_mm = $px
        $edgeBase = ([string]$cut.face -replace '_short_edge$','' -replace '_long_edge$','')
        $edgeName = $edgeBase + "_edge"
        foreach ($smx in [regex]::Matches($low, $slotKwRx)) {
          foreach ($kmx in [regex]::Matches($low, "k[i\u0131]sa\s*kenar")) {
            if ([Math]::Abs($smx.Index - $kmx.Index) -le 50) { $edgeName = $edgeBase + "_short_edge" }
          }
          foreach ($kmx in [regex]::Matches($low, "uzun\s*kenar")) {
            if ([Math]::Abs($smx.Index - $kmx.Index) -le 50) { $edgeName = $edgeBase + "_long_edge" }
          }
        }
        $cut | Add-Member -NotePropertyName "placement" -NotePropertyValue ([pscustomobject]@{ type = "centered"; edge = $edgeName; horizontal = "center"; provenance = "explicit"; rule = "deterministic: (body_width - cut_width)/2" }) -Force
      }
    }
  }
  # Acik through-wall ifadesi: "through-wall" / "duvari tamamen kes" (slot yakininda).
  $twExp = $false
  foreach ($twm in [regex]::Matches($low, 'through-wall|duvar[i\u0131]\s*tamamen\s*kes\w*|duvar[i\u0131]\s*delip\s*ge[c\u00e7]\w*')) {
    if ($slotRefIdx -ge 0 -and [Math]::Abs($twm.Index - $slotRefIdx) -le 60) { $twExp = $true }
  }
  if ($twExp -and [string]$cut.penetration -ne "through_wall") {
    $cut | Add-Member -NotePropertyName "penetration" -NotePropertyValue "through_wall" -Force
  }
  if ($null -eq $cut.depth_mm -and ($faceBase -eq "front" -or $faceBase -eq "rear") -and $null -ne $comp.hollow -and $null -ne $comp.hollow.wall_mm -and [double]$comp.hollow.wall_mm -gt 0) {
    $cut.depth_mm = [double]$comp.hollow.wall_mm
    $cut | Add-Member -NotePropertyName "penetration" -NotePropertyValue "through_wall" -Force
  }
  $depthOk = ($null -ne $cut.depth_mm -or [string]$cut.penetration -eq "through_wall")
  if ($null -ne $cut.width_mm -and $null -ne $cut.length_mm -and $null -ne $cut.pos_x_mm -and $null -ne $cut.pos_y_mm -and $depthOk) { $cut.status = "ok" }
  $comp.cutouts = @($cut)
}

$rm = [regex]::Match($low, 'yuvarlat?\s*(\d+(?:[.,]\d+)?)')
if ($rm.Success) { $comp.edge_notes = @([pscustomobject]@{ kind = "fillet"; value_mm = (Get-Num $rm.Groups[1].Value); target = "kenarlar" }) }
elseif ($low -match "yuvarla") { $comp.edge_notes = @([pscustomobject]@{ kind = "fillet"; value_mm = $null; target = "kenarlar" }) }
# Pah: "pah 2" ve "2 mm pah" siralamalari; "gerekiyorsa" sartli ifadeler elenir,
# kesin ifade kazanir (hepsi sartliysa deterministik ilk aday).
$chCands = @()
foreach ($m in [regex]::Matches($low, 'pah(?:\s*k[i\u0131]r)?\s*(\d+(?:[.,]\d+)?)')) { $chCands += @{ v = (Get-Num $m.Groups[1].Value); i = $m.Index } }
foreach ($m in [regex]::Matches($low, '(\d+(?:[.,]\d+)?)\s*mm\s*pah')) { $chCands += @{ v = (Get-Num $m.Groups[1].Value); i = $m.Index } }
$chCands = @($chCands | Sort-Object { $_.i })
$chVal = $null
foreach ($cnd in $chCands) {
  # Sartlilik AYNI cumle icinde aranir ("... gerekiyorsa degerlendir." sartli, "1 mm pah kullan." kesin).
  $sEnd = $low.IndexOfAny(@('.', '!', '?', ';', "`n"), $cnd.i)
  if ($sEnd -lt 0) { $sEnd = $low.Length }
  $cw = $low.Substring($cnd.i, [Math]::Min(($sEnd - $cnd.i), 80))
  if ($cw -match "gerekiyorsa|gerekirse") { continue }
  $chVal = $cnd.v
  break
}
if ($null -eq $chVal -and $chCands.Count -gt 0) { $chVal = $chCands[0].v }
if ($null -ne $chVal) { $comp.edge_notes = @($comp.edge_notes) + @([pscustomobject]@{ kind = "chamfer"; value_mm = $chVal; target = "kenarlar" }) }
elseif ($low -match "pah") { $comp.edge_notes = @($comp.edge_notes) + @([pscustomobject]@{ kind = "chamfer"; value_mm = $null; target = "kenarlar" }) }
# Yaricap: "yaricap 5" ve "5 mm yaricapla" siralamalari; degersiz fillet varsa doldur.
$rad = Find-One $low '(?:d[i\u0131][s\u015f]\s*)?(?:k[o\u00f6][s\u015f]e\s*)?yar[i\u0131][c\u00e7]ap[i\u0131]?\s*(\d+(?:[.,]\d+)?)'
if ($null -eq $rad) { $rad = Find-One $low '(\d+(?:[.,]\d+)?)\s*mm\s*yar[i\u0131][c\u00e7]ap\w*' }
if ($null -ne $rad) {
  $filled = $false
  foreach ($en in @($comp.edge_notes)) {
    if (-not $filled -and $en -and [string]$en.kind -eq "fillet" -and $null -eq $en.value_mm) {
      $en.value_mm = $rad
      if ([string]$en.target -eq "kenarlar") { $en.target = "dis koseler" }
      $filled = $true
    }
  }
  if (-not $filled) {
    $hasFilVal = $false
    foreach ($en in @($comp.edge_notes)) { if ($en -and [string]$en.kind -eq "fillet" -and $null -ne $en.value_mm) { $hasFilVal = $true } }
    if (-not $hasFilVal) { $comp.edge_notes = @($comp.edge_notes) + @([pscustomobject]@{ kind = "fillet"; value_mm = $rad; target = "dis koseler" }) }
  }
}
# Temas alanlari: "10x10 mm temas" govdeye islenir (slot degil).
# "dort kose" baglami + govde olculeri varsa 4 kose deterministik yerlesir.
$padm = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?' + $DimSepRx + '\s*(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?temas')
if ($padm.Success) {
  $pw = (Get-Num $padm.Groups[1].Value); $pl = (Get-Num $padm.Groups[2].Value)
  $pads = @([pscustomobject]@{ width_mm = $pw; length_mm = $pl })
  $fourCorner = $false
  foreach ($km in [regex]::Matches($low, 'd[o\u00f6]rt\s*k[o\u00f6][s\u015f]e')) {
    if ([Math]::Abs($km.Index - $padm.Index) -le 60) { $fourCorner = $true }
  }
  $pbw = 0; $pbd = 0
  if ($null -ne $comp.base.width_mm) { $pbw = [double]$comp.base.width_mm }
  if ($null -ne $comp.base.depth_mm) { $pbd = [double]$comp.base.depth_mm }
  if ($fourCorner -and $pw -gt 0 -and $pl -gt 0 -and $pw -le $pbw -and $pl -le $pbd) {
    $pads = @(
      [pscustomobject]@{ width_mm = $pw; length_mm = $pl; pos_x_mm = 0; pos_y_mm = 0; corner = "bottom_left"; placement = "corner_pattern" },
      [pscustomobject]@{ width_mm = $pw; length_mm = $pl; pos_x_mm = ($pbw - $pw); pos_y_mm = 0; corner = "bottom_right"; placement = "corner_pattern" },
      [pscustomobject]@{ width_mm = $pw; length_mm = $pl; pos_x_mm = 0; pos_y_mm = ($pbd - $pl); corner = "top_left"; placement = "corner_pattern" },
      [pscustomobject]@{ width_mm = $pw; length_mm = $pl; pos_x_mm = ($pbw - $pw); pos_y_mm = ($pbd - $pl); corner = "top_right"; placement = "corner_pattern" }
    )
  }
  $comp | Add-Member -NotePropertyName "contact_pads" -NotePropertyValue $pads -Force
}

$tm = [regex]::Match($low, '([zZ])\s*ekseninde\s*(\d+)\s*derece\s*d[o\u00f6]nd[u\u00fc]r')
if ($tm.Success) {
  $comp.transforms = @([pscustomobject]@{ op = "rotate"; x = 0; y = 0; z = [double]$tm.Groups[2].Value })
} else {
  $tm2 = [regex]::Match($low, 'd[o\u00f6]nd[u\u00fc]r\s*([xXyYzZ])\s*(\d+)')
  if ($tm2.Success) {
    $ax = $tm2.Groups[1].Value.ToLowerInvariant(); $ang = [double]$tm2.Groups[2].Value
    $t = [pscustomobject]@{ op = "rotate"; x = 0; y = 0; z = 0 }
    if ($ax -eq "x") { $t.x = $ang } elseif ($ax -eq "y") { $t.y = $ang } else { $t.z = $ang }
    $comp.transforms = @($t)
  } elseif ($low -match "d[o\u00f6]nd[u\u00fc]r") {
    $am = [regex]::Match($low, '(\d+)\s*derece')
    if ($am.Success) { $comp | Add-Member -NotePropertyName "pending_rotate" -NotePropertyValue ([double]$am.Groups[1].Value) -Force }
  }
}
$mm = [regex]::Match($low, 'ayna\s*([xXyYzZ])')
if ($mm.Success) { $comp.transforms = @($comp.transforms) + @([pscustomobject]@{ op = "mirror"; axis = $mm.Groups[1].Value.ToLowerInvariant() }) }
elseif ($low -match "simetri") { $comp | Add-Member -NotePropertyName "pending_mirror" -NotePropertyValue $true -Force }

$tm3 = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*bo[s\u015f]luk')
if ($tm3.Success) {
  $comp.tolerance = [pscustomobject]@{ type = "clearance"; clearance_mm = (Get-Num $tm3.Groups[1].Value); fit_to = $null; status = "ok" }
} elseif ($low -match "biraz gev[s\u015f]ek" -or $low -match "biraz s[i\u0131]k[i\u0131]" -or $low -match "gev[s\u015f]ek yap") {
  $questions.Add("Bir tolerans degeri belirtir misin? Ornek: 0.2 mm. (belirsiz ifade icin deger uydurulamaz)")
}

$components.Add($comp)
$assembly = $null

$divN = $null
$dmNum = [regex]::Match($low, '(\d+)\s*b[o\u00f6]lme')
if ($dmNum.Success) { $divN = [int]$dmNum.Groups[1].Value }
else {
  $dmAdet = [regex]::Match($low, '(\d+)\s*adet\s*(?:ayr[i\u0131]\s*)?b[o\u00f6]lme')
  if ($dmAdet.Success) { $divN = [int]$dmAdet.Groups[1].Value }
  else {
    $dmAyr = [regex]::Match($low, '(\d+)\s*ayr[i\u0131]\s*b[o\u00f6]lme')
    if ($dmAyr.Success) { $divN = [int]$dmAyr.Groups[1].Value }
    else {
      # Isim-oncesi form: "2 adet, 2 mm kalinliginda ... bolme" -> bolmeye en yakin adet.
      $bestDiv = $null; $bestDivDist = 999999
    foreach ($am in [regex]::Matches($low, '(\d+)\s*(?:adet|tane)')) {
        foreach ($bm in [regex]::Matches($low, 'b[o\u00f6]lme')) {
          $ddd = [Math]::Abs($am.Index - $bm.Index)
          if ($ddd -lt $bestDivDist -and $ddd -le 80) { $bestDivDist = $ddd; $bestDiv = [int]$am.Groups[1].Value }
        }
      }
      if ($null -ne $bestDiv) { $divN = $bestDiv }
    }
  }
}
if ($null -eq $divN) {
  if ($low -match "iki\s*b[o\u00f6]lme") { $divN = 2 }
elseif ($low -match "[u\u00fc][c\u00e7]\s*b[o\u00f6]lme") { $divN = 3 }
elseif ($low -match "d[o\u00f6]rt\s*b[o\u00f6]lme") { $divN = 4 }
  elseif ($low -match "b[o\u00f6]lme") { $divN = 1 }
}
if ($null -ne $divN) {
  # Adim A (spec 2.1): bolmeler bagimsiz component DEGIL, govde-ici ozellik
  # (body.divider_pattern). Ic olculer govdeden turetilir; dis olcu sorulmaz.
  # Bolme kalinligi: ortak cozucu (bolme baglami sart; iki sira da yakalanir).
  $divTh = $null
  $divThM = Find-Measure $low 'kal[i\u0131]nl[i\u0131][kg\u011f][i\u0131]?\w*' 60 $mpClaimed 'b[o\u00f6]lme' 70 @($bodySpan)
  if ($null -ne $divThM) { $divTh = [double]$divThM.value }
  # Bolme ust-boslugu: bolme baglamindaki "ust kenardan 5 mm" -> top_gap_mm (yoksa 0, derived).
  $divGap = 0
  $divGapDerived = $true
  foreach ($gm in [regex]::Matches($low, '[u\u00fc]st\s*kenardan\s*(\d+(?:[.,]\d+)?)')) {
    foreach ($bm in [regex]::Matches($low, 'b[o\u00f6]lme')) {
      if ([Math]::Abs($gm.Index - $bm.Index) -le 50) { $divGap = (Get-Num $gm.Groups[1].Value); $divGapDerived = $false }
    }
  }
  $divStatus = "missing"
  if ($null -ne $divTh) { $divStatus = "ok" }
  $comp | Add-Member -NotePropertyName "divider_pattern" -NotePropertyValue ([pscustomobject]@{
    count = $divN; thickness_mm = $divTh; top_gap_mm = $divGap; top_gap_derived = $divGapDerived
    orientation = "along_length"; status = $divStatus
  }) -Force
  if ($null -eq $comp.hollow) {
    # Bolme ic hacim gerektirir: govde yoksa bos kabuk kurulur, degerler sorulur (uydurulmaz).
    $comp.hollow = [pscustomobject]@{ wall_mm = $null; open_top = $null; bottom_thickness_mm = $bottomTh }
    $questions.Add("Duvar kalinligi nedir? (ornek: duvar 2.5). Uydurulamaz.")
  }
}
# "kapaksiz" (kapak YOK) ve "kapak montaj noktasi" (montaj ozelligi, kapak DEGIL) lid uretmez.
if (($low -match "kapak" -and $low -notmatch "kapaks[i\u0131]z" -and $low -notmatch "kapak\s+montaj") -or $low -match "iki par[c\u00e7]a" -or ($low -match "taban" -and $low -match "destek")) {
  $lid = [pscustomobject]@{
    id = "lid"; label = "kapak"
    base = [pscustomobject]@{ shape = "box"; width_mm = $comp.base.width_mm; depth_mm = $comp.base.depth_mm; height_mm = $null }
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
  $lh = Find-One $low 'kapak[^.]{0,30}?(?:y[u\u00fc]kseklik|kal[i\u0131]nl[i\u0131]k)\s*(\d+(?:[.,]\d+)?)'
  if ($null -eq $lh) { $questions.Add("Kapagin yuksekligi/kalinligi nedir? (ornek: kapak yukseklik 5)") }
  else { $lid.base.height_mm = $lh }
  $lc = Find-One $low 'kapak[^.]{0,40}?(\d+(?:[.,]\d+)?)\s*mm\s*bo[s\u015f]luk'
  if ($null -eq $lc -and $null -ne $lh) { $questions.Add("Kapak-govde gecme boslugu nedir? (ornek: 0.2 mm bosluk). Kritik tolerans uydurulamaz.") }
  else { $lid.tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = $lc; fit_to = "body"; status = "ok" } }
  $components.Add($lid)
  if ($low -match "kapakta" -or $low -match "kapaktaki" -or $low -match "kapak\s+delik") {
    $lid.holes = @($comp.holes)
    $comp.holes = @()
  }
  $assembly = [pscustomobject]@{
    parts = @("body", "lid")
    joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = $lc; screw = $null })
  }
}

# Malzeme: bilgi-bankasindaki yedi malzeme kelimesi geciyorsa islenir (sadece isim; profil/sicaklik UYDURULMAZ).
$specMaterial = $null
foreach ($mk in @(@("pla", "PLA"), @("petg", "PETG"), @("abs", "ABS"), @("asa", "ASA"), @("tpu", "TPU"), @("naylon", "Nylon"), @("nylon", "Nylon"), @("polikarbon", "PC"))) {
  if ($low -match ('\b' + $mk[0] + '\b')) { $specMaterial = $mk[1]; break }
}
if ($null -eq $specMaterial -and $low -match '\bpc\b') { $specMaterial = "PC" }

$specVer = "2.0"
if ($null -ne $comp.divider_pattern) { $specVer = "2.1" }
$specObj2 = [pscustomobject]@{
  project_name = $ProjectName; prompt = $Prompt
  metadata = [pscustomobject]@{ spec_version = $specVer }
  components = @($components.ToArray()); assembly = $assembly; material = $specMaterial
}

if ($OutPath -ne "") {
  $dir = Split-Path -Parent $OutPath
  if ($dir -ne "" -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $specObj2 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutPath -Encoding UTF8
  Write-Output "SPEC: $OutPath"
}
if ($QuestionsJson -ne "") {
  (@($questions) | ConvertTo-Json) | Set-Content -LiteralPath $QuestionsJson -Encoding UTF8
}
Write-Output "SORU-SAYISI: $($questions.Count)"
foreach ($q in $questions) { Write-Output "SORU: $q" }
