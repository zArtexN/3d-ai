<#
.SYNOPSIS
  Explicit-fact ledger: user promptundaki acik bilgileri canonical fact'lere cevirir.
.DESCRIPTION
  Parser'dan BAGIMSIZ ikinci goz (coverage/regression icin). Her fact:
  factType (dimension|feature|relation|material), target, property, value, unit,
  source (prompttaki ham metin), confidence (1 = explicit).
  Cikti: facts dizisi (ekranda / -OutPath ile). Deger UYDURMAZ; bulamadigini yazmaz.
  Kullanim: coverage (Test-FactCoverage) + trace (pipeline-trace.json).
.EXAMPLE
  powershell -File engine\Get-ExplicitFacts.ps1 -Prompt "160x100x45 mm kutu" -AsJson
#>
param(
  [Parameter(Mandatory = $true)][string]$Prompt,
  [string]$OutPath = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Get-FNum($s) { return [double]([string]$s -replace ',', '.') }

$low = $Prompt.ToLowerInvariant() -replace ([char]0x307), ""
# Birim normalizasyonu (parser ile ayni kural): cm -> mm.
$low = [regex]::Replace($low, '(\d+(?:[.,]\d+)?)\s*cm\b', { param($m) ((Get-FNum $m.Groups[1].Value) * 10).ToString() + " mm" })

$facts = New-Object System.Collections.Generic.List[object]
function Add-Fact($type, $target, $prop, $val, $unit, $src) {
  $facts.Add([pscustomobject]@{
    factType = $type; target = $target; property = $prop
    value = $val; unit = $unit; source = $src; confidence = 1
  })
}

$sepRx = '[xX\*\u00d7\u2715\u2716\u2a2f]|çarp[i\u0131]'
$tm = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?(?:' + $sepRx + ')\s*(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?(?:' + $sepRx + ')\s*(\d+(?:[.,]\d+)?)')
if ($tm.Success) {
  Add-Fact "dimension" "body" "width" (Get-FNum $tm.Groups[1].Value) "mm" $tm.Value.Trim()
  Add-Fact "dimension" "body" "depth" (Get-FNum $tm.Groups[2].Value) "mm" $tm.Value.Trim()
  Add-Fact "dimension" "body" "height" (Get-FNum $tm.Groups[3].Value) "mm" $tm.Value.Trim()
}

$wl = [regex]::Match($low, 'duvar(?:lar)?[i\u0131]?(?:\s*kal[i\u0131]nl[i\u0131][g\u011f][i\u0131])?\s*(\d+(?:[.,]\d+)?)')
if ($wl.Success) { Add-Fact "feature" "body.hollow" "wall_mm" (Get-FNum $wl.Groups[1].Value) "mm" $wl.Value.Trim() }
$bt = [regex]::Match($low, 'taban\w*\s*kal[i\u0131]nl[i\u0131][g\u011f][i\u0131]?\s*(\d+(?:[.,]\d+)?)')
if ($bt.Success) { Add-Fact "feature" "body.hollow" "bottom_thickness_mm" (Get-FNum $bt.Groups[1].Value) "mm" $bt.Value.Trim() }
if ($low -match "[u\u00fc]st[u\u00fc]\s*a[c\u00e7][i\u0131]k|[u\u00fc]stten\s*a[c\u00e7][i\u0131]k|[u\u00fc]st\s*k[i\u0131]sm[i\u0131]\s*a[c\u00e7][i\u0131]k|kapaks[i\u0131]z") {
  Add-Fact "feature" "body.hollow" "open_top" $true "" $Matches[0].Trim()
}

$om = [regex]::Match($low, '[\u00d8\u00f8]\s*(\d+(?:[.,]\d+)?)')
if ($om.Success) { Add-Fact "feature" "body.holes" "diameter_mm" (Get-FNum $om.Groups[1].Value) "mm" $om.Value.Trim() }
else {
  $cm = [regex]::Match($low, '(?<!\w)[c\u00e7]ap[i\u0131]?\s*(\d+(?:[.,]\d+)?)')
  if ($cm.Success) { Add-Fact "feature" "body.holes" "diameter_mm" (Get-FNum $cm.Groups[1].Value) "mm" $cm.Value.Trim() }
}
$stemIdxs = @()
foreach ($smx in [regex]::Matches($low, 'deli[k\u011fg]\w*')) { $stemIdxs += $smx.Index }
$bestAdet = $null; $bestAdetDist = 999999
foreach ($amx in [regex]::Matches($low, '(\d+)\s*adet')) {
  foreach ($si in $stemIdxs) {
    $ddd = [Math]::Abs($amx.Index - $si)
    if ($ddd -lt $bestAdetDist -and $ddd -le 60) { $bestAdetDist = $ddd; $bestAdet = $amx }
  }
}
if ($null -ne $bestAdet) { Add-Fact "feature" "body.holes" "count" ([int]$bestAdet.Groups[1].Value) "adet" $bestAdet.Value.Trim() }
else {
  # Adetsiz sayi: "4 delik" (parser ConvertTo-GeometrySpec.ps1:258 ile ayni kural).
  $hmN = [regex]::Match($low, '(\d+)\s*deli[k\u011fg]\w*')
  if ($hmN.Success) { Add-Fact "feature" "body.holes" "count" ([int]$hmN.Groups[1].Value) "adet" $hmN.Value.Trim() }
}
if ($low -match "ge[c\u00e7]i[s\u015f]li|ge[c\u00e7]sin\w*") { Add-Fact "feature" "body.holes" "hole_type" "through" "" $Matches[0].Trim() }
$bestEo = $null; $bestEoDist = 999999
foreach ($emx in [regex]::Matches($low, '(?:kenar(?:lardan|dan)|k[o\u00f6][s\u015f]e\w*den)\s*(\d+(?:[.,]\d+)?)')) {
  foreach ($si in $stemIdxs) {
    $ddd = [Math]::Abs($emx.Index - $si)
    if ($ddd -lt $bestEoDist -and $ddd -le 60) { $bestEoDist = $ddd; $bestEo = $emx }
  }
}
if ($null -ne $bestEo) { Add-Fact "relation" "body.holes" "edge_offset_mm" (Get-FNum $bestEo.Groups[1].Value) "mm" $bestEo.Value.Trim() }
if ($low -match 'k[o\u00f6][s\u015f]e|her\s*deli|simetrik') { Add-Fact "relation" "body.holes" "layout" "corner_pattern" "" $Matches[0].Trim() }
$cbm = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*[c\u00e7]ap[i\u0131]nda')
if ($cbm.Success -and ($low -match "counterbore|g[o\u00f6]mme")) { Add-Fact "feature" "body.holes" "cb_dia_mm" (Get-FNum $cbm.Groups[1].Value) "mm" $cbm.Value.Trim() }
$dbm = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*derinli[k\u011fg]\w*')
if ($dbm.Success -and ($low -match "counterbore|g[o\u00f6]mme")) { Add-Fact "feature" "body.holes" "cb_depth_mm" (Get-FNum $dbm.Groups[1].Value) "mm" $dbm.Value.Trim() }

$tmBody = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?(?:' + $sepRx + ')\s*(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?(?:' + $sepRx + ')\s*(\d+(?:[.,]\d+)?)')
$pmBest = $null; $pmBestDist = 999999
foreach ($pmm in [regex]::Matches($low, '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?(?:' + $sepRx + ')\s*(\d+(?:[.,]\d+)?)(?!\s*(?:mm\s*)?(?:' + $sepRx + ')\s*\d)')) {
  if ($null -ne $tmBody -and $tmBody.Success -and $pmm.Index -ge $tmBody.Index -and ($pmm.Index + $pmm.Length) -le ($tmBody.Index + $tmBody.Length)) { continue }
  $slotNear = $false
  foreach ($km in [regex]::Matches($low, 'slot|kanal|kesik|a[c\u00e7][i\u0131]kl[i\u0131][k\u011fg]|kablo')) {
    if ([Math]::Abs($pmm.Index - $km.Index) -le 60) { $slotNear = $true }
  }
  if (-not $slotNear) { continue }
  $ddd = 999999
  foreach ($km in [regex]::Matches($low, 'slot|kanal|kesik|a[c\u00e7][i\u0131]kl[i\u0131][k\u011fg]|kablo')) {
    $dd2 = [Math]::Abs($pmm.Index - $km.Index)
    if ($dd2 -lt $ddd) { $ddd = $dd2 }
  }
  if ($ddd -lt $pmBestDist) { $pmBestDist = $ddd; $pmBest = $pmm }
}
if ($null -ne $pmBest) {
  Add-Fact "feature" "body.c1" "width_mm" (Get-FNum $pmBest.Groups[1].Value) "mm" $pmBest.Value.Trim()
  Add-Fact "feature" "body.c1" "length_mm" (Get-FNum $pmBest.Groups[2].Value) "mm" $pmBest.Value.Trim()
}
if ($low -match "ortas[i\u0131]nda|ortada|merkezinde") { Add-Fact "relation" "body.c1" "horizontal" "center" "" $Matches[0].Trim() }
$by = [regex]::Match($low, '(?:alttan|alt\s*kenar(?:dan|[i\u0131]\w*)\s*(?:tabandan\s*)?)(\d+(?:[.,]\d+)?)')
if ($by.Success) { Add-Fact "relation" "body.c1" "bottom_offset_mm" (Get-FNum $by.Groups[1].Value) "mm" $by.Value.Trim() }

$dv = [regex]::Match($low, '(\d+)\s*adet\s*(?:ayr[i\u0131]\s*)?b[o\u00f6]lme')
if ($dv.Success) { Add-Fact "feature" "dividers" "count" ([int]$dv.Groups[1].Value) "adet" $dv.Value.Trim() }
else {
  # Adetsiz sayi: "2 bolme" (parser ConvertTo-GeometrySpec.ps1:576 ile ayni kural).
  $dv2 = [regex]::Match($low, '(\d+)\s*b[o\u00f6]lme')
  if ($dv2.Success) { Add-Fact "feature" "dividers" "count" ([int]$dv2.Groups[1].Value) "adet" $dv2.Value.Trim() }
  else {
    # Uzakta kalan adet: "2 adet, ... bolme" (parser :586-594 yakinlik kurali, 80 karakter).
    $bestDiv = $null; $bestDivDist = 999999
    foreach ($am in [regex]::Matches($low, '(\d+)\s*adet')) {
      foreach ($bm in [regex]::Matches($low, 'b[o\u00f6]lme')) {
        $ddd = [Math]::Abs($am.Index - $bm.Index)
        if ($ddd -lt $bestDivDist -and $ddd -le 80) { $bestDivDist = $ddd; $bestDiv = $am }
      }
    }
    if ($null -ne $bestDiv) { Add-Fact "feature" "dividers" "count" ([int]$bestDiv.Groups[1].Value) "adet" $bestDiv.Value.Trim() }
  }
}
$dth = [regex]::Match($low, 'b[o\u00f6]lme\w*\s*kal[i\u0131]nl[i\u0131][g\u011f][i\u0131]?\s*(\d+(?:[.,]\d+)?)')
if ($dth.Success) { Add-Fact "feature" "dividers" "thickness_mm" (Get-FNum $dth.Groups[1].Value) "mm" $dth.Value.Trim() }
else {
  # Ters sira: "2 mm kalinliginda ... bolme" (parser :625-635 ile ayni kural, 70 karakter penceresi).
  $bestTh = $null
  foreach ($tm in [regex]::Matches($low, '(\d+(?:[.,]\d+)?)\s*mm\s*kal[i\u0131]nl[i\u0131][g\u011f][i\u0131]\w*')) {
    foreach ($bm in [regex]::Matches($low, 'b[o\u00f6]lme')) {
      $ddd = $tm.Index - $bm.Index
      if ($ddd -lt 0 -and (-$ddd) -le 70) { $bestTh = $tm }
    }
  }
  if ($null -ne $bestTh) { Add-Fact "feature" "dividers" "thickness_mm" (Get-FNum $bestTh.Groups[1].Value) "mm" $bestTh.Value.Trim() }
}
# Bolme ust-boslugu: bolme baglamindaki "ust kenardan 5 mm" (parser :644-656 ile ayni kural).
foreach ($gm in [regex]::Matches($low, '[u\u00fc]st\s*kenardan\s*(\d+(?:[.,]\d+)?)')) {
  foreach ($bm in [regex]::Matches($low, 'b[o\u00f6]lme')) {
    if ([Math]::Abs($gm.Index - $bm.Index) -le 50) {
      Add-Fact "feature" "dividers" "top_gap_mm" (Get-FNum $gm.Groups[1].Value) "mm" $gm.Value.Trim()
      break
    }
  }
}
# Montaj noktasi sayisi: "4 kapak montaj noktasi" (parser :373 ile ayni kural).
$mpm = [regex]::Match($low, '(\d+)\s*(?:kapak\s+)?montaj\s*nokta')
if ($mpm.Success) { Add-Fact "feature" "mounting" "count" ([int]$mpm.Groups[1].Value) "adet" $mpm.Value.Trim() }
# Temas alani: "10x10 mm temas" (parser :524 ile ayni kural; slot baglami aranmaz).
$padPair = $null
foreach ($pmm in [regex]::Matches($low, '(\d+(?:[.,]\d+)?)\s*(?:mm\s*)?(?:' + $sepRx + ')\s*(\d+(?:[.,]\d+)?)(?!\s*(?:mm\s*)?(?:' + $sepRx + ')\s*\d)')) {
  foreach ($km in [regex]::Matches($low, 'temas')) {
    if ([Math]::Abs($pmm.Index - $km.Index) -le 60) { $padPair = $pmm }
  }
}
if ($null -ne $padPair) { Add-Fact "feature" "pads" "pair" ((Get-FNum $padPair.Groups[1].Value).ToString() + "x" + (Get-FNum $padPair.Groups[2].Value).ToString()) "mm" $padPair.Value.Trim() }

$rd = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*yar[i\u0131][c\u00e7]ap\w*')
if (-not $rd.Success) { $rd = [regex]::Match($low, 'yar[i\u0131][c\u00e7]ap[i\u0131]?\s*(\d+(?:[.,]\d+)?)') }
if ($rd.Success) { Add-Fact "feature" "body.edge" "fillet_mm" (Get-FNum $rd.Groups[1].Value) "mm" $rd.Value.Trim() }
$ch = [regex]::Match($low, '(\d+(?:[.,]\d+)?)\s*mm\s*pah')
if ($ch.Success) { Add-Fact "feature" "body.edge" "chamfer_mm" (Get-FNum $ch.Groups[1].Value) "mm" $ch.Value.Trim() }

$matList = @("pla", "petg", "abs", "asa", "tpu", "naylon|nylon", "polikarbon|pc\b", "pp\b", "hips", "pctg")
foreach ($mn in $matList) {
  $mm = [regex]::Match($low, '\b(' + $mn + ')\b')
  if ($mm.Success) {
    $mname = $mm.Groups[1].Value.ToUpperInvariant()
    if ($mname -eq "NAYLON") { $mname = "NYLON" }
    if ($mname -eq "POLIKARBON") { $mname = "PC" }
    Add-Fact "material" "project" "material" $mname "" $mm.Value.Trim()
    break
  }
}

$arr = @($facts.ToArray())
# mention_id eslemesi (Adim D): her fact, uretildigi sayi ifadesine baglanir.
# Kural (coverage ile ayni): metin-kesisimi, yoksa deger+sinif eslesmesi.
function Find-MentionId($f, $ml) {
  $fs = [string]$f.source
  $fv = $f.value
  $fp = [string]$f.property
  foreach ($m in @($ml)) {
    if ($null -eq $m) { continue }
    $mr = [string]$m.raw
    if ($fs -ne "" -and $mr -ne "" -and ($fs.Contains($mr) -or $mr.Contains($fs))) { return [string]$m.id }
  }
  foreach ($m in @($ml)) {
    if ($null -eq $m) { continue }
    $eq = $false
    try { $eq = ([Math]::Abs([double]$fv - [double]$m.value) -lt 0.0001) } catch { $eq = ([string]$fv -eq [string]$m.value) }
    if (-not $eq) { continue }
    $mk = [string]$m.kind
    if ($mk -eq "count" -and $fp -eq "count") { return [string]$m.id }
    if ($mk -eq "diameter" -and ($fp -eq "diameter_mm" -or $fp -eq "cb_dia_mm")) { return [string]$m.id }
    if ($mk -eq "measure" -and $fp -ne "count") { return [string]$m.id }
    if (($mk -eq "triple" -or $mk -eq "pair") -and $fs -ne "") { return [string]$m.id }
  }
  return $null
}
$mentionList = @()
try {
  # Not: dot-source KULLANILMAZ (callee param blogu caller scope'taki $Prompt/$OutPath'i ezer).
  $menTxt = & (Join-Path $PSScriptRoot "Get-NumericMentions.ps1") -Prompt $Prompt -AsJson 2>&1 | Out-String
  $menParsed = $menTxt | ConvertFrom-Json
  $mentionList = @($menParsed | Where-Object { $_ -ne $null })
} catch { $mentionList = @() }
foreach ($f in $arr) {
  $f | Add-Member -NotePropertyName "mention_id" -NotePropertyValue (Find-MentionId $f $mentionList) -Force
}
if ($OutPath -ne "") {
  $dir = Split-Path -Parent $OutPath
  if ($dir -ne "" -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  (@{ facts = $arr } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
  Write-Output ("FACTS: $OutPath (" + $arr.Count + " fact)")
}
if ($AsJson -or $OutPath -eq "") { $arr | ConvertTo-Json -Depth 5 }
