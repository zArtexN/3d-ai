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

function Get-Num($s) { return [double]($s -replace ',', '.') }
function Find-Dims($t) {
  $m = [regex]::Match($t, '(\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(\d+(?:[.,]\d+)?)')
  if ($m.Success) { return @((Get-Num $m.Groups[1].Value), (Get-Num $m.Groups[2].Value), (Get-Num $m.Groups[3].Value)) }
  return $null
}
function Find-One($t, $pat) {
  $m = [regex]::Match($t, $pat)
  if ($m.Success) { return (Get-Num $m.Groups[1].Value) }
  return $null
}

$low = $Prompt.ToLowerInvariant() -replace "\u0307", ""
$questions = New-Object System.Collections.Generic.List[string]

$components = New-Object System.Collections.Generic.List[object]
$comp = [pscustomobject]@{
  id = "body"; label = "ana govde"
  base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }
  hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null
}

$handled = $false
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
  $dims = Find-Dims $low
  if ($null -eq $dims) { $questions.Add("Govde olculeri anlasilmadi. Ornek: 80x40x20 (mm). Govde olcusu nedir?") }
  else { $comp.base.width_mm = $dims[0]; $comp.base.depth_mm = $dims[1]; $comp.base.height_mm = $dims[2] }
}

if ($low -match "i[c\u00e7]ini bo[s\u015f]alt" -or $low -match "i[c\u00e7]i bo[s\u015f]") {
  $wl = Find-One $low 'duvar(?:lar)?[i\u0131]?(?:\s*kal[i\u0131]nl[i\u0131][g\u011f][i\u0131])?\s*(\d+(?:[.,]\d+)?)'
  if ($null -eq $wl) { $questions.Add("Duvar kalinligi nedir? (ornek: duvar 2.5). Uydurulamaz.") }
  $openTop = $null
  if ($low -match "[u\u00fc]st[u\u00fc]\s*a[c\u00e7][i\u0131]k") { $openTop = $true }
  elseif ($low -match "kapal[i\u0131]") { $openTop = $false }
  $comp.hollow = [pscustomobject]@{ wall_mm = $wl; open_top = $openTop }
} else {
  $wlOnly = Find-One $low 'duvar(?:lar)?[i\u0131]?(?:\s*kal[i\u0131]nl[i\u0131][g\u011f][i\u0131])?\s*(\d+(?:[.,]\d+)?)'
  if ($null -ne $wlOnly) {
    $comp.hollow = [pscustomobject]@{ wall_mm = $wlOnly; open_top = $null }
  }
}

$hm = [regex]::Match($low, 'delik\s*(\d+(?:[.,]\d+)?)')
$diaVal = $null
if ($hm.Success) { $diaVal = (Get-Num $hm.Groups[1].Value) }
else {
  $hm2 = [regex]::Match($low, 'delikleri?\s*(\d+(?:[.,]\d+)?)')
  if ($hm2.Success) { $diaVal = (Get-Num $hm2.Groups[1].Value) }
  else {
    $hm3 = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*[c\u00e7]ap[i\u0131]nda\s*delik')
    if ($hm3.Success) { $diaVal = (Get-Num $hm3.Groups[1].Value) }
  }
}
$typeKw = $null
if ($low -match "k[o\u00f6]r") { $typeKw = "blind" }
elseif ($low -match "hav[s\u015f]a") { $typeKw = "countersink" }
elseif ($low -match "g[o\u00f6]mme") { $typeKw = "counterbore" }
$mentionsHole = ($low -match "delik") -or ($low -match "kenardan")
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
    $questions.Add("Delik merkezi eksik (kritik olcu, uydurulamaz). Ornek: merkez 15,15 (referans koseden mm).")
  }
  if ($htype -eq "blind") {
    $bd = Find-One $low 'derinlik\s*(\d+(?:[.,]\d+)?)'
    if ($null -eq $bd) { $questions.Add("Kor deligin derinligi nedir? (ornek: derinlik 5)") }
    else { $hole.depth_mm = $bd }
  }
  $sm = [regex]::Match($low, '\b(m\d+)\b')
  if ($sm.Success) { $hole.screw = $sm.Groups[1].Value.ToUpperInvariant() }
  $comp.holes = @($hole)
}

if ($low -match "slot" -or $low -match "kanal" -or $low -match "kesik" -or $low -match "a[c\u00e7][i\u0131]kl[i\u0131]k") {
  $sd = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(\d+(?:[.,]\d+)?)')
  $cut = [pscustomobject]@{ id = "c1"; kind = "rect"; face = "front"; pos_x_mm = $null; pos_y_mm = $null; width_mm = $null; length_mm = $null; depth_mm = $null; status = "missing" }
  if ($low -match "slot" -or $low -match "kanal") { $cut.kind = "slot" }
  if ($low -match "[u\u00fc]st") { $cut.face = "top" }
  if ($sd.Success) { $cut.width_mm = (Get-Num $sd.Groups[1].Value); $cut.length_mm = (Get-Num $sd.Groups[2].Value) }
  else { $questions.Add("Kesigin olcusu nedir? (ornek: 20x10 mm)") }
  $pm = [regex]::Match($low, 'konum\s*(\d+(?:[.,]\d+)?)\s*[,;]\s*(\d+(?:[.,]\d+)?)')
  if ($pm.Success) { $cut.pos_x_mm = (Get-Num $pm.Groups[1].Value); $cut.pos_y_mm = (Get-Num $pm.Groups[2].Value); $cut.depth_mm = 10 }
  else { $questions.Add("Kesigin konumu ve derinligi nedir? (ornek: konum 5,5 derinlik 8)") }
  if ($null -ne $cut.width_mm -and $null -ne $cut.pos_x_mm) { $cut.status = "ok" }
  $comp.cutouts = @($cut)
}

$rm = [regex]::Match($low, 'yuvarlat?\s*(\d+(?:[.,]\d+)?)')
if ($rm.Success) { $comp.edge_notes = @([pscustomobject]@{ kind = "fillet"; value_mm = (Get-Num $rm.Groups[1].Value); target = "kenarlar" }) }
elseif ($low -match "yuvarla") { $comp.edge_notes = @([pscustomobject]@{ kind = "fillet"; value_mm = $null; target = "kenarlar" }) }
$cm = [regex]::Match($low, 'pah(?:\s*k[i\u0131]r)?\s*(\d+(?:[.,]\d+)?)')
if ($cm.Success) { $comp.edge_notes = @($comp.edge_notes) + @([pscustomobject]@{ kind = "chamfer"; value_mm = (Get-Num $cm.Groups[1].Value); target = "kenarlar" }) }
elseif ($low -match "pah") { $comp.edge_notes = @($comp.edge_notes) + @([pscustomobject]@{ kind = "chamfer"; value_mm = $null; target = "kenarlar" }) }

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
if ($low -match "kapak" -or $low -match "iki par[c\u00e7]a" -or ($low -match "taban" -and $low -match "destek")) {
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
  $assembly = [pscustomobject]@{
    parts = @("body", "lid")
    joints = @([pscustomobject]@{ id = "j1"; type = "sliding_fit"; part_a = "body"; part_b = "lid"; clearance_mm = $lc; screw = $null })
  }
}

$specObj2 = [pscustomobject]@{
  project_name = $ProjectName; prompt = $Prompt
  metadata = [pscustomobject]@{ spec_version = "2.0" }
  components = @($components.ToArray()); assembly = $assembly; material = $null
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
