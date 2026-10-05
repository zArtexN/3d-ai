<#
.SYNOPSIS
  Design Planner v2.0: urun-tasarim niyetini eksiksiz DesignSpec'e cevirir.
.DESCRIPTION
  Genel prensiplerle calisir (hardcoded urun listesi degil):
    container (ici-bos govde) / stand (kama+dudak) / plate (plaka+delik) / tray (sig hollow)
   Niyetler: organizer, phone_stand, pen_holder, tray, caddy, box(+lid), bracket, cable_clip, wall_plate.
  Tetik: govde olculeri yok + niyet eslesmesi + belirli telefon modeli yok (telefon icerenlerde).
  HER varsayim spec.planner.assumptions'da. Kritik olcu sessizce uydurulmaz.
  Geometri: yalnizca dogrulanmis DesignSpec engine'e gider (partitions/wedges/holes/cutouts).
.EXAMPLE
  powershell -File engine\Invoke-DesignPlanner.ps1 -SpecFile projects\x\spec.json -Prompt "..."
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [Parameter(Mandatory = $true)][string]$Prompt
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir

function Planner-Report($applied, $reason, $needsInput, $decisions) {
  return ([pscustomobject]@{
    applied = $applied; reason = $reason; needs_input = $needsInput
    decisions = @($decisions)
  } | ConvertTo-Json -Depth 6 -Compress)
}
function Get-PNum($s) { return [double]([string]$s -replace ',', '.') }

if (-not (Test-Path -LiteralPath $SpecFile)) { throw "Spec bulunamadi: $SpecFile" }
$spec = Get-Content -LiteralPath $SpecFile -Raw | ConvertFrom-Json
$low = $Prompt.ToLowerInvariant() -replace ([char]0x307), ""

$comps = @($spec.components | Where-Object { $_ -ne $null })
if ($comps.Count -eq 0) { Write-Output (Planner-Report $false "bilesen yok" "" @()); exit 0 }
$body = $null
foreach ($c in $comps) { if ($c -and [string]$c.id -eq "body") { $body = $c; break } }
if ($null -eq $body) { $body = $comps[0] }
if ($null -ne $body.base -and $null -ne $body.base.width_mm -and $null -ne $body.base.depth_mm -and $null -ne $body.base.height_mm) {
  Write-Output (Planner-Report $false "acik govde olculeri var; planner devre disi" "" @()); exit 0
}
$userWall = $null
if ($null -ne $body.hollow -and $null -ne $body.hollow.wall_mm) { $userWall = [double]$body.hollow.wall_mm }
$dpTh = $null
if ($null -ne $body.divider_pattern -and $null -ne $body.divider_pattern.thickness_mm -and [double]$body.divider_pattern.thickness_mm -gt 0) {
  $dpTh = [double]$body.divider_pattern.thickness_mm
}
$guideNote = "knowledge/printing-guidelines.json"
$wall = 3.0
if ($null -ne $userWall) { $wall = $userWall }

# Belirli telefon modeli taramasi (telefon iceren niyetlerde NEEDS_INPUT).
$modelRx = 'iphone|samsung|galaxy|pixel|xiaomi|redmi|huawei|oneplus|oppo|vivo|realme|motorola|nokia|honor|nothing\s*phone|pro\s*max|ultra\b|mate\s*\d|p\d+\s*pro'
function Test-PhoneModel($t) { return ([regex]::IsMatch($t, $modelRx)) }

# Egitim-acisi cozumu: acik "N derece/egim" yakinligi, yoksa varsayim.
function Get-Angle($t, $def) {
  $ang = [double]$def; $prov = "varsayim"
  foreach ($m in [regex]::Matches($t, '(\d+(?:[.,]\d+)?)\s*(?:derece|\u00b0)?\s*e[g\u011f]im|e[g\u011f]im\w*\s*(\d+(?:[.,]\d+)?)|yakla[s\u015f][i\u0131]k\s*(\d+(?:[.,]\d+)?)')) {
    foreach ($g in @(1, 2, 3)) {
      if ($m.Groups[$g].Success -and $m.Groups[$g].Value -ne "") {
        $v = Get-PNum $m.Groups[$g].Value
        if ($v -gt 0 -and $v -le 45) { $ang = $v; $prov = "kullanici"; break }
      }
    }
    if ($prov -eq "kullanici") { break }
  }
  return @{ angle = $ang; provenance = $prov }
}

# --- niyet tespiti (oncelik sirali; genel prensip adlari) ---
$hasOrg = ($low -match 'organizer' -or $low -match 'organayzer' -or $low -match 'd[u\u00fc]zenleyici')
$hasPen = ($low -match 'kalem')
$hasPhone = ($low -match 'telefon')
$intent = ""
if ($hasOrg -and $hasPen -and $hasPhone) { $intent = "organizer" }
elseif ($hasPhone -and ($low -match 'stand|ayak|dayama|dock') -and -not $hasPen) { $intent = "phone_stand" }
elseif ($hasPen -and ($low -match 'kalemlik|tutucu|bardak|hazne') -and -not $hasPhone) { $intent = "pen_holder" }
elseif ($low -match 'tepsi|tray') { $intent = "tray" }
elseif ((($low -match 's[uü]nger') -or ($low -match 'f[iı]r[cç]a') -or ($low -match 'bula[sş][iı]k') -or ($low -match 'drenaj')) -and (($low -match 'b[oö]lme') -or ($low -match 'organizer') -or ($low -match 'organayzer') -or ($low -match 'd[uü]zenleyici') -or ($low -match 'hazne') -or ($low -match 'sepet'))) { $intent = "caddy" }
elseif ($low -match 'braket|dirsek|L\s*profil|kose\s*destek|duvar\s*destegi') { $intent = "bracket" }
elseif (($low -match 'kablo') -and ($low -match 'tutucu|klips|duzenleyici|toplayici|kanal\s*parca')) { $intent = "cable_clip" }
elseif (($low -match 'telefon') -and ($low -match 'duvar') -and ($low -match 'montaj|monte|ask[i\u0131]') -and ($low -match 'kanca|kulakl[i\u0131]k')) { $intent = "wall_station" }
  elseif (($low -match 'duvar') -and ($low -match 'aparat|aski|ask aparat|montaj|raf')) { $intent = "wall_plate" }
elseif (($low -match 'saklama|muhafaza|enclosure|kapakl') -or ($low -match 'kutu' -and $low -match 'kapak|cekmece|tasarla|duzenle|sakla|organize')) { $intent = "box" }
if ($intent -eq "") { Write-Output (Planner-Report $false "planner niyeti yok" "" @()); exit 0 }
if (($intent -eq "organizer" -or $intent -eq "phone_stand" -or $intent -eq "wall_station" -or $intent -eq "caddy") -and (Test-PhoneModel $low)) {
  $mm = [regex]::Match($low, $modelRx).Value
  Write-Output (Planner-Report $false "belirli telefon modeli" ("Telefon modeli belirtildi (" + $mm + "); olcusunden emin olunamadi. NEEDS_INPUT: telefonun tam modeli ve dis olculeri (genislik x derinlik x kalinlik mm) gerekli.") @())
  exit 0
}

# --- ortak zarf degiskenleri ---
$parts = New-Object System.Collections.Generic.List[object]
$wedges = New-Object System.Collections.Generic.List[object]
$cutouts = New-Object System.Collections.Generic.List[object]
$holes = New-Object System.Collections.Generic.List[object]
$assumptions = New-Object System.Collections.Generic.List[string]
$W = 0; $D = 0; $H = 0; $bottom = 3.0; $shape = "rounded_box"; $radius = 3.0
$openTop = $null; $bayKinds = @(); $phoneAngle = $null; $lidH = $null; $lidClear = $null

switch ($intent) {
  "organizer" {
    $wantSmall = ($low -match 'kucuk\s*esya|aksesuar|kucuk\s*parca|toka|anahtar|kart')
    $bk = @("pen", "phone"); if ($wantSmall) { $bk += @("small") }
    $bayKinds = $bk
    $nPart = $bk.Count - 1
    $a = Get-Angle $low 15
    $phoneAngle = $a
    if ($bk.Count -eq 2) { $W = 150.0; $D = 100.0; $H = 65.0 } else { $W = 180.0; $D = 105.0; $H = 75.0 }
    $partTh = 2.4; $penW = 55.0; $phoneW = 80.0
    if ($null -ne $dpTh) { $partTh = $dpTh }
    $need = 2 * $wall + $nPart * $partTh + $penW + $phoneW
    if ($bk.Count -gt 2) { $need += 45.0 }
    if ($need -gt $W) { $W = [math]::Ceiling($need) }
    $widths = @($penW, $phoneW)
    if ($bk.Count -gt 2) { $widths += @($W - 2 * $wall - $nPart * $partTh - $penW - $phoneW) }
    $acc = $wall; $pi = 1
    for ($bi = 0; $bi -lt ($bk.Count - 1); $bi++) {
      $acc += $widths[$bi]
      $parts.Add([pscustomobject]@{ id = ("p" + $pi); axis = "y"; x_mm = [math]::Round($acc, 3); y_mm = $wall; z0_mm = ($bottom - 0.1); thickness_mm = $partTh; length_mm = [math]::Round(($D - 2 * $wall + 0.1), 3); height_mm = [math]::Round(($H - $bottom + 0.1), 3) }) | Out-Null
      $pi++; $acc += $partTh
    }
    $phoneX0 = $wall + $penW + $partTh
    $wh = $H - 15.0; if ($wh -lt 30) { $wh = $H - 10.0 }
    $wy1 = $D - $wall - 4.0
    $wedges.Add([pscustomobject]@{ id = "w1"; x0_mm = ($phoneX0 + 0.5); x1_mm = ($phoneX0 + $phoneW - 0.5); y0_mm = 0; y1_mm = $wy1; z0_mm = ($bottom - 0.1); height_mm = [math]::Round($wh, 3); angle_deg = $a.angle; angle_driven = $true }) | Out-Null
    $parts.Add([pscustomobject]@{ id = "lip1"; axis = "x"; x_mm = ($phoneX0 + 0.5); y_mm = $wall; z0_mm = ($bottom - 0.1); thickness_mm = 2.4; length_mm = ($phoneW - 1.0); height_mm = 10.0 }) | Out-Null
    $cutouts.Add([pscustomobject]@{ id = "c1"; kind = "rect"; face = "front"; pos_x_mm = [math]::Round(($phoneX0 + ($phoneW - 14.0) / 2), 3); pos_y_mm = 6.0; width_mm = 14.0; length_mm = 10.0; depth_mm = $null; penetration = "through_wall"; status = "ok" }) | Out-Null
    $openTop = $true
    $assumptions.Add("overall ${W}x${D}x${H} mm (varsayim; kompakt masaustu)") | Out-Null
    $assumptions.Add("duvar ${wall} mm, taban ${bottom} mm (varsayim; $guideNote)") | Out-Null
    $assumptions.Add("bolme kalinligi ${partTh} mm x ${nPart} adet; konumlar ic bosluktan turetim ($($bk -join ','))") | Out-Null
    $assumptions.Add("telefon zarfi 78x10x165 mm (varsayim; jenerik, model degil)") | Out-Null
    $assumptions.Add("telefon egimi $($a.angle) derece ($($a.provenance); dikeyden geriye, aci-gudumlu kama)") | Out-Null
    $assumptions.Add("kablo kanali 14x10 mm on duvarda telefon bolmesine acilir (through_wall)") | Out-Null
  }
  "phone_stand" {
    $a = Get-Angle $low 20
    $phoneAngle = $a
    $W = 100.0; $D = 85.0; $H = 6.0; $shape = "box"; $radius = $null
    $wh = 58.0
    $wy1 = $D - 8.0
    $wedges.Add([pscustomobject]@{ id = "w1"; x0_mm = 11.0; x1_mm = ($W - 11.0); y0_mm = 0; y1_mm = $wy1; z0_mm = ($H - 0.1); height_mm = $wh; angle_deg = $a.angle; angle_driven = $true }) | Out-Null
    $parts.Add([pscustomobject]@{ id = "lip1"; axis = "x"; x_mm = 11.0; y_mm = 6.0; z0_mm = ($H - 0.1); thickness_mm = 3.0; length_mm = ($W - 22.0); height_mm = 12.0 }) | Out-Null
    if ($low -match 'kablo|kanal|slot') {
      $cutouts.Add([pscustomobject]@{ id = "c1"; kind = "slot"; face = "top"; pos_x_mm = 20.0; pos_y_mm = 30.0; width_mm = 8.0; length_mm = 8.0; depth_mm = $H; status = "ok" }) | Out-Null
      $assumptions.Add("kablo slotu 8x8 taban plakasinda kama onunde (varsayim)") | Out-Null
    }
    $assumptions.Add("stand tabani ${W}x${D}x${H} mm (varsayim)") | Out-Null
    $assumptions.Add("telefon egimi $($a.angle) derece ($($a.provenance); aci-gudumlu kama, tabana birlesik)") | Out-Null
    $assumptions.Add("telefon zarfi 78x10x165 mm (varsayim; jenerik)") | Out-Null
  }
  "pen_holder" {
    $W = 85.0; $D = 85.0; $H = 105.0; $bottom = 4.0
    $parts.Add([pscustomobject]@{ id = "p1"; axis = "y"; x_mm = ($wall + ($W - 2 * $wall - 2.4) / 2); y_mm = $wall; z0_mm = ($bottom - 0.1); thickness_mm = 2.4; length_mm = ($D - 2 * $wall + 0.1); height_mm = ($H - $bottom - 20.0) }) | Out-Null
    $openTop = $true
    $assumptions.Add("kalemlik ${W}x${D}x${H} mm, taban ${bottom} mm (varsayim; kalem boylu)") | Out-Null
    $assumptions.Add("tek ara bolme ustten 20 mm alcak (varsayim; kalem erisimi)") | Out-Null
  }
  "tray" {
    $W = 160.0; $D = 110.0; $H = 28.0
    $openTop = $true
    $assumptions.Add("tepsi ${W}x${D}x${H} mm sig duvarli (varsayim)") | Out-Null
  }
  "caddy" {
    # Mutfak/banyo caddy: sunger + firca icin 2 bolme, tabana yakin on/arka
    # drenaj slotlari, ustu acik, desteksiz basim. Kama/dudak/kanca yok.
    # Ayak izleri govde X-Y icinde; slotlar bolme iziyle cakismaz.
    $W = 170.0; $D = 110.0; $H = 90.0; $bottom = 4.0
    $spongeW = 115.0
    $partTh = 2.4
    if ($null -ne $dpTh) { $partTh = $dpTh }
    $need = 2 * $wall + $partTh + $spongeW + 40.0
    if ($need -gt $W) { $W = [math]::Ceiling($need) }
    $partX = $wall + $spongeW
    $parts.Add([pscustomobject]@{ id = "p1"; axis = "y"; x_mm = [math]::Round($partX, 3); y_mm = $wall; z0_mm = ($bottom - 0.1); thickness_mm = $partTh; length_mm = [math]::Round(($D - 2 * $wall + 0.1), 3); height_mm = [math]::Round(($H - $bottom + 0.1), 3) }) | Out-Null
    $bayKinds = @("sponge", "brush")
    # Drenaj: on duvarda sunger bolmesinde 2 slot, arka duvarda 1+1 (bolme onu bos birakilir).
    $slotY = 6.0; $slotL = 8.0; $slotW = 30.0
    $cutouts.Add([pscustomobject]@{ id = "d1"; kind = "rect"; face = "front"; pos_x_mm = 15.0; pos_y_mm = $slotY; width_mm = $slotW; length_mm = $slotL; depth_mm = $null; penetration = "through_wall"; status = "ok" }) | Out-Null
    $cutouts.Add([pscustomobject]@{ id = "d2"; kind = "rect"; face = "front"; pos_x_mm = 60.0; pos_y_mm = $slotY; width_mm = $slotW; length_mm = $slotL; depth_mm = $null; penetration = "through_wall"; status = "ok" }) | Out-Null
    $cutouts.Add([pscustomobject]@{ id = "d3"; kind = "rect"; face = "rear"; pos_x_mm = 15.0; pos_y_mm = $slotY; width_mm = $slotW; length_mm = $slotL; depth_mm = $null; penetration = "through_wall"; status = "ok" }) | Out-Null
    $brushX0 = $partX + $partTh + 5.0
    $cutouts.Add([pscustomobject]@{ id = "d4"; kind = "rect"; face = "rear"; pos_x_mm = [math]::Round($brushX0, 3); pos_y_mm = $slotY; width_mm = $slotW; length_mm = $slotL; depth_mm = $null; penetration = "through_wall"; status = "ok" }) | Out-Null
    $openTop = $true
    $assumptions.Add("caddy ${W}x${D}x${H} mm, taban ${bottom} mm (su icin kalin taban, varsayim)") | Out-Null
    $assumptions.Add("duvar ${wall} mm, taban ${bottom} mm (varsayim; $guideNote)") | Out-Null
    $assumptions.Add("sunger bolmesi ${spongeW} mm + firca bolmesi (kalan), ara duvar ${partTh} mm x=${partX} (varsayim; jenerik sunger/firca)") | Out-Null
    $assumptions.Add("drenaj 4x ${slotW}x${slotL} mm on/arka duvar tabaninda (through_wall; bolme iziyle cakismaz)") | Out-Null
  }
  "box" {
    $W = 120.0; $D = 80.0; $H = 60.0
    $openTop = $true
    $assumptions.Add("saklama kutusu ${W}x${D}x${H} mm (varsayim)") | Out-Null
    if ($low -match 'kapak') {
      $lidH = 8.0; $lidClear = 0.4
      $assumptions.Add("kapak yuksekligi ${lidH} mm, gecme payi ${lidClear} mm (varsayim; FDM genel tolerans)") | Out-Null
    }
  }
  "bracket" {
    $W = 60.0; $D = 40.0; $H = 6.0; $shape = "box"; $radius = $null
    $parts.Add([pscustomobject]@{ id = "p1"; axis = "x"; x_mm = 2.0; y_mm = ($D - 3.0 - 4.0); z0_mm = ($H - 0.1); thickness_mm = 4.0; length_mm = ($W - 4.0); height_mm = 30.0 }) | Out-Null
    $holes.Add([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = 5.5; center_x_mm = 10.0; center_y_mm = 10.0; axis = "z"; status = "ok" }) | Out-Null
    $holes.Add([pscustomobject]@{ id = "h2"; hole_type = "through"; diameter_mm = 5.5; center_x_mm = ($W - 10.0); center_y_mm = 10.0; axis = "z"; status = "ok" }) | Out-Null
    $assumptions.Add("L-braket taban ${W}x${D}x${H} mm + 30 mm dikey duvar (varsayim)") | Out-Null
    $assumptions.Add("2x M5 montaj deligi simetrik (varsayim; duvar onunde serbest alan)") | Out-Null
  }
  "cable_clip" {
    $W = 40.0; $D = 24.0; $H = 12.0; $shape = "box"; $radius = $null
    $cutouts.Add([pscustomobject]@{ id = "c1"; kind = "slot"; face = "top"; pos_x_mm = 8.0; pos_y_mm = 4.0; width_mm = 8.0; length_mm = 16.0; depth_mm = $H; status = "ok" }) | Out-Null
    $assumptions.Add("kablo tutucu ${W}x${D}x${H} mm blok + 24x8 gecis slotu (varsayim)") | Out-Null
  }
  "wall_plate" {
    $W = 80.0; $D = 60.0; $H = 6.0; $shape = "box"; $radius = $null
    $mx = 12.0; $my = 12.0
    $holes.Add([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = 5.5; center_x_mm = $mx; center_y_mm = $my; axis = "z"; status = "ok" }) | Out-Null
    $holes.Add([pscustomobject]@{ id = "h2"; hole_type = "through"; diameter_mm = 5.5; center_x_mm = ($W - $mx); center_y_mm = $my; axis = "z"; status = "ok" }) | Out-Null
    $holes.Add([pscustomobject]@{ id = "h3"; hole_type = "through"; diameter_mm = 5.5; center_x_mm = $mx; center_y_mm = ($D - $my); axis = "z"; status = "ok" }) | Out-Null
    $holes.Add([pscustomobject]@{ id = "h4"; hole_type = "through"; diameter_mm = 5.5; center_x_mm = ($W - $mx); center_y_mm = ($D - $my); axis = "z"; status = "ok" }) | Out-Null
    $assumptions.Add("duvar plakasi ${W}x${D}x${H} mm + 4x M5 kose deligi 12 mm kenar payli (varsayim)") | Out-Null
  }
  "wall_station" {
    # Duvara monte kulaklik + telefon istasyonu: dolu plaka + 2 dikey delik +
    # aci-gudumlu telefon kamasi + dudak + kanca kolonu + kablo slotu.
    # Geometri kurallari: tum ayak izleri govde X-Y icinde (validator planEps),
    # z0 plaka-ustu kaynak payli, kesikler once oyulur sonra eklenir
    # (Invoke-GeometryEngine Carve-G -> Merge-G sirasi), izler ayrik tutulur.
    $a = Get-Angle $low 12
    $phoneAngle = $a
    $W = 140.0; $D = 100.0; $H = 10.0; $shape = "box"; $radius = $null
    # Montaj: 2 through delik, ayni X (monte halde dikey hizali), Y-simetrik.
    $holeDia = 5.5; $holeX = $W / 2
    $holes.Add([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = $holeDia; center_x_mm = $holeX; center_y_mm = 25.0; axis = "z"; status = "ok" }) | Out-Null
    $holes.Add([pscustomobject]@{ id = "h2"; hole_type = "through"; diameter_mm = $holeDia; center_x_mm = $holeX; center_y_mm = ($D - 25.0); axis = "z"; status = "ok" }) | Out-Null
    # Telefon besigi: kama + dudak (organizer/phone_stand deseni).
    $wh = 55.0
    $wy1 = $D - 8.0
    $wedges.Add([pscustomobject]@{ id = "w1"; x0_mm = 15.0; x1_mm = 95.0; y0_mm = 0; y1_mm = $wy1; z0_mm = ($H - 0.1); height_mm = $wh; angle_deg = $a.angle; angle_driven = $true }) | Out-Null
    $parts.Add([pscustomobject]@{ id = "lip1"; axis = "x"; x_mm = 15.0; y_mm = 8.0; z0_mm = ($H - 0.1); thickness_mm = 3.0; length_mm = 80.0; height_mm = 12.0 }) | Out-Null
    # Kulaklik kancasi: dikey kolon (baskida +Z, montede odaya yatay uzanir).
    $hookX0 = 105.0; $hookY0 = 44.0
    $parts.Add([pscustomobject]@{ id = "hook1"; axis = "x"; x_mm = $hookX0; y_mm = $hookY0; z0_mm = ($H - 0.1); thickness_mm = 12.0; length_mm = 30.0; height_mm = 45.0 }) | Out-Null
    # Kablo slotu: acik-serit kurali (dudak-ustu +2, kanca-onu -11); plaka boyu deler.
    $slotW = 14.0; $slotL = 10.0
    $slotX0 = ($hookX0 - 11.0) - $slotW
    $slotY0 = (8.0 + 3.0) + 2.0
    $cutouts.Add([pscustomobject]@{ id = "c1"; kind = "slot"; face = "top"; pos_x_mm = $slotX0; pos_y_mm = $slotY0; width_mm = $slotW; length_mm = $slotL; depth_mm = $H; status = "ok" }) | Out-Null
    $assumptions.Add("duvar istasyonu plakasi ${W}x${D}x${H} mm dolu govde (varsayim; kompakt duvar tipi)") | Out-Null
    $assumptions.Add("montaj deligi capi ${holeDia} mm M5 emsali (varsayim); 2 delik ayni X=${holeX} (monte-dikey hizali), Y merkeze simetrik +-25 (kural)") | Out-Null
    $assumptions.Add("telefon zarfi 78x10x165 mm (varsayim; jenerik, model degil)") | Out-Null
    $assumptions.Add("telefon egimi $($a.angle) derece ($($a.provenance); aci-gudumlu kama, tabana birlesik)") | Out-Null
    $assumptions.Add("kablo slotu ${slotW}x${slotL} mm ust yuzde, derinlik plaka boyu ${H} mm (through; kural)") | Out-Null
    $assumptions.Add("slot konumu X=${slotX0} (kanca-onu -11 eksi slot genisligi), Y=${slotY0} (dudak-ustu +2); delik/kama/dudak/kanca izleriyle cakismaz (kural)") | Out-Null
    $assumptions.Add("kulaklik kancasi 30x12x45 mm dikey kolon (varsayim; jenerik bant icin)") | Out-Null
  }
}

# --- spec'e yaz: body taze kurulur (PS5.1 mutasyon tuhafliklarindan kacinilir) ---
if ($shape -eq "rounded_box") {
  $baseObj = [pscustomobject]@{ shape = $shape; width_mm = $W; depth_mm = $D; height_mm = $H; radius_mm = $radius }
} else {
  $baseObj = [pscustomobject]@{ shape = $shape; width_mm = $W; depth_mm = $D; height_mm = $H }
}
$nbHash = [ordered]@{ id = [string]$body.id }
foreach ($pn in @($body.PSObject.Properties.Name)) {
  if ([string]$pn -eq "id") { continue }
  if ([string]$pn -eq "divider_pattern" -and $parts.Count -gt 0) {
    $assumptions.Add("parser bolme niyeti planner partisyonlarina katildi (cift duvar onlendi)") | Out-Null
    continue
  }
  $nbHash[[string]$pn] = $body.$pn
}
$nbHash["base"] = $baseObj
if ($null -ne $openTop) {
  $nbHash["hollow"] = ([pscustomobject]@{ wall_mm = $wall; open_top = $openTop; bottom_thickness_mm = $bottom })
}
if ($parts.Count -gt 0) { $nbHash["partitions"] = $parts.ToArray() }
if ($wedges.Count -gt 0) { $nbHash["wedges"] = $wedges.ToArray() }
if ($cutouts.Count -gt 0) { $nbHash["cutouts"] = $cutouts.ToArray() }
$keptParserHoles = New-Object System.Collections.Generic.List[object]
$droppedGhost = $false
foreach ($h in @($body.holes)) {
  if ($null -eq $h) { continue }
  $ghost = ([string]$h.status -eq "missing" -and $null -eq $h.diameter_mm -and $null -eq $h.center_x_mm -and $null -eq $h.center_y_mm)
  if ($ghost) {
    $droppedGhost = $true
    $assumptions.Add("parser hayalet deligi atildi (olcusuz/konumsuz " + [string]$h.id + ")") | Out-Null
    continue
  }
  $keptParserHoles.Add($h) | Out-Null
}
if ($holes.Count -gt 0 -and $keptParserHoles.Count -eq 0) { $nbHash["holes"] = $holes.ToArray() }
else {
  if ($holes.Count -gt 0 -and $keptParserHoles.Count -gt 0) {
    $assumptions.Add("kullanici deligi korundu; planner standart delikleri uygulanmadi") | Out-Null
  }
  $nbHash["holes"] = $keptParserHoles.ToArray()
}
if ($shape -eq "rounded_box") {
  $nbHash["edge_notes"] = @()
} elseif ($null -eq $body.edge_notes -or @($body.edge_notes).Count -eq 0) {
  $nbHash["edge_notes"] = @([pscustomobject]@{ kind = "fillet"; value_mm = 3.0; target = "dis koseler (planner onerisi; engine uygulamaz, WARNING)" })
}
$newBody = [pscustomobject]$nbHash
$oldLid = $null
foreach ($c in $comps) {
  if ($c -and [string]$c.id -eq "lid") { $oldLid = $c; break }
}
if ($null -ne $lidH -and $null -ne $oldLid) {
  if ($null -ne $oldLid.base -and $null -ne $oldLid.base.height_mm -and [double]$oldLid.base.height_mm -gt 0) {
    $lidH = [double]$oldLid.base.height_mm
    $assumptions.Add("kapak yuksekligi kullanicidan alindi (${lidH} mm)") | Out-Null
  }
  if ($null -ne $oldLid.tolerance -and $null -ne $oldLid.tolerance.clearance_mm -and [double]$oldLid.tolerance.clearance_mm -ge 0) {
    $lidClear = [double]$oldLid.tolerance.clearance_mm
    $assumptions.Add("gecme payi kullanicidan alindi (${lidClear} mm)") | Out-Null
  }
}
$newComps = New-Object System.Collections.Generic.List[object]
foreach ($c in $comps) {
  if ($c -and [string]$c.id -eq [string]$body.id) { $newComps.Add($newBody) | Out-Null }
  elseif ($c -and [string]$c.id -eq "lid" -and $null -ne $lidH) { }
  else { $newComps.Add($c) | Out-Null }
}
$assumptions.Add("duvar ${wall} mm karari $guideNote kilavuzundan (varsayim)") | Out-Null
$assumptions.Add("baski yonu: genis taban tezgahta; tum cikintilar <=45 derece oldugundan destek gerekmez") | Out-Null
$phoneModelTxt = "jenerik (belirli model yok)"
$phoneEnvArr = @(78.0, 10.0, 165.0)
if ($intent -eq "caddy") {
  $phoneModelTxt = "yok (telefon icermez)"
  $phoneEnvArr = $null
}
$plannerObj = [pscustomobject]@{
  designer = "design-planner/2.0"; intent = $intent
  compartments = @($bayKinds); phone_model = $phoneModelTxt
  phone_envelope_mm = $phoneEnvArr
  phone_angle_deg = $(if ($null -ne $phoneAngle) { $phoneAngle.angle } else { $null })
  angle_provenance = $(if ($null -ne $phoneAngle) { $phoneAngle.provenance } else { $null })
  guidelines = $guideNote; orientation = "base_on_bed"; support = "not_required"
  assumptions = $assumptions.ToArray()
}
$specHash = [ordered]@{}
foreach ($sn in @($spec.PSObject.Properties.Name)) {
  if ([string]$sn -eq "components" -or [string]$sn -eq "planner" -or [string]$sn -eq "assembly") { continue }
  $specHash[[string]$sn] = $spec.$sn
}
$specHash["components"] = $newComps.ToArray()
$specHash["planner"] = $plannerObj
if ($null -ne $lidH) {
  $lidBase = [pscustomobject]@{ shape = $shape; width_mm = $W; depth_mm = $D; height_mm = $lidH }
  if ($shape -eq "rounded_box") {
    $lidBase = [pscustomobject]@{ shape = $shape; width_mm = $W; depth_mm = $D; height_mm = $lidH; radius_mm = $radius }
  }
  $lid = [pscustomobject]@{
    id = "lid"; label = "kapak"
    base = $lidBase
    hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = [pscustomobject]@{ type = "clearance_fit"; clearance_mm = $lidClear; fit_to = "body"; status = "ok" }
    expected_bbox = $null
  }
  $specHash["components"] = @($newComps.ToArray() + @($lid))
  $specHash["assembly"] = ([pscustomobject]@{
    parts = @("body", "lid")
    joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = $lidClear; screw = $null })
  })
} elseif ($null -ne $spec.assembly) {
  $specHash["assembly"] = $spec.assembly
}
if ($null -eq $spec.metadata) {
  $specHash["metadata"] = ([pscustomobject]@{ spec_version = "2.0" })
}
$spec = [pscustomobject]$specHash
$spec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $SpecFile -Encoding UTF8
$planPath = Join-Path (Split-Path -Parent $SpecFile) "planner.json"
[pscustomobject]@{ designer = "design-planner/2.0"; intent = $intent; applied = $true; spec = $SpecFile; assumptions = $assumptions.ToArray() } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

Write-Output (Planner-Report $true ($intent + " plani uygulandi (varsayimlar spec.planner'da)") "" $assumptions.ToArray())
exit 0
