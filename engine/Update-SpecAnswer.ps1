<#
.SYNOPSIS
  Kullanicinin cevabini DesignSpec v2'ye isler. Sayisal degeri oldugu gibi korur (donusum/yuvarlama yok).
.DESCRIPTION
  kind'e gore hedef alani doldurur ve status=ok yapar:
    dims (WxDxH) | lid_height (tek sayi) | wall | hole_center (x,y) | hole_dia |
    hole_depth | hole_extra (cs/cb: dia,depth) | cutout (WxL + konum + derinlik) |
    clearance | joint_clearance
  Cevap parse edilemezse anlasilir hata verir (UI gosterir). Cevaba soru kimligi,
  zaman ve source=user islenir (kayit pipeline tarafindan questions.json'a yazilir).
.EXAMPLE
  powershell -File engine\Update-SpecAnswer.ps1 -SpecFile s.json -QuestionId q1 -Answer "15,15"
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [Parameter(Mandatory = $true)][string]$QuestionId,
  [Parameter(Mandatory = $true)][string]$Answer
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $SpecFile)) { throw "Spec bulunamadi: $SpecFile" }
$uspecObj = Get-Content -LiteralPath $SpecFile -Raw | ConvertFrom-Json

function Get-NumU($s) { return [double]([string]$s -replace ',', '.') }
function Parse-Pair($t) {
  $m = [regex]::Match($t, '(-?\d+(?:[.,]\d+)?)\s*[,;xX\s]\s*(-?\d+(?:[.,]\d+)?)')
  if (-not $m.Success) { throw "Cevap anlasilmadi. Iki sayi bekleniyor (ornek: 15,15 veya 15 15). Girilen: $t" }
  return @((Get-NumU $m.Groups[1].Value), (Get-NumU $m.Groups[2].Value))
}
function Parse-Triple($t) {
  $m = [regex]::Match($t, '(-?\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(-?\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(-?\d+(?:[.,]\d+)?)')
  if (-not $m.Success) { throw "Cevap anlasilmadi. Uc olcu bekleniyor (ornek: 80x40x20). Girilen: $t" }
  return @((Get-NumU $m.Groups[1].Value), (Get-NumU $m.Groups[2].Value), (Get-NumU $m.Groups[3].Value))
}
function Parse-One($t) {
  $m = [regex]::Match($t, '(-?\d+(?:[.,]\d+)?)')
  if (-not $m.Success) { throw "Cevap anlasilmadi. Sayi bekleniyor. Girilen: $t" }
  $v = Get-NumU $m.Groups[1].Value
  if ($v -le 0) { throw "Olcu pozitif olmali. Girilen: $t" }
  return $v
}

$qfile = [System.IO.Path]::ChangeExtension($SpecFile, ".questions.json")
$qs = @()
if (Test-Path -LiteralPath $qfile) {
  $qsRawFile = Get-Content -LiteralPath $qfile -Raw | ConvertFrom-Json
  if ($null -eq $qsRawFile) { $qs = @() }
  elseif ($qsRawFile -is [array]) { $qs = $qsRawFile }
  else { $qs = @($qsRawFile) }
}
$q = $qs | Where-Object { $_.question_id -eq $QuestionId } | Select-Object -First 1
if ($null -eq $q) { throw "Soru bulunamadi: $QuestionId" }
$kind = [string]$q.kind
$target = [string]$q.target
$cid = [string]$q.component

$comp = @($uspecObj.components) | Where-Object { [string]$_.id -eq $cid } | Select-Object -First 1
if ($null -eq $comp -and $kind -ne "joint_clearance") { throw "Bilesen bulunamadi: $cid" }

if ($kind -eq "dims") {
  $d = Parse-Triple $Answer
  $comp.base.width_mm = $d[0]; $comp.base.depth_mm = $d[1]; $comp.base.height_mm = $d[2]
} elseif ($kind -eq "lid_height") {
  $comp.base.height_mm = Parse-One $Answer
} elseif ($kind -eq "wall") {
  $comp.hollow.wall_mm = Parse-One $Answer
} elseif ($kind -eq "hollow_top") {
  $a = $Answer.ToLowerInvariant()
  if ($a -match "acik" -or $a -match "a[c\u00e7]ik") { $comp.hollow.open_top = $true }
  elseif ($a -match "kapali") { $comp.hollow.open_top = $false }
  else { throw "Cevap anlasilmadi. 'acik' veya 'kapali' yaz. Girilen: $Answer" }
} elseif ($kind -eq "rotate_axis") {
  $a = $Answer.ToLowerInvariant()
  $ax = ""
  if ($a -match "\bx\b") { $ax = "x" } elseif ($a -match "\by\b") { $ax = "y" } elseif ($a -match "\bz\b") { $ax = "z" }
  if ($ax -eq "") { throw "Eksen anlasilmadi. X / Y / Z yaz. Girilen: $Answer" }
  $t = [pscustomobject]@{ op = "rotate"; x = 0; y = 0; z = 0 }
  $ang = [double]$comp.pending_rotate
  $am = [regex]::Match($Answer, '(-?\d+(?:[.,]\d+)?)')
  if ($am.Success -and [double]($am.Groups[1].Value -replace ',', '.') -ne 0) { $ang = [double]($am.Groups[1].Value -replace ',', '.') }
  if ($ax -eq "x") { $t.x = $ang } elseif ($ax -eq "y") { $t.y = $ang } else { $t.z = $ang }
  $comp.transforms = @(@($comp.transforms) + @($t))
  $comp.pending_rotate = $null
} elseif ($kind -eq "mirror_axis") {
  $a = $Answer.ToLowerInvariant()
  $ax = ""
  if ($a -match "\bx\b") { $ax = "x" } elseif ($a -match "\by\b") { $ax = "y" } elseif ($a -match "\bz\b") { $ax = "z" }
  if ($ax -eq "") { throw "Eksen anlasilmadi. X / Y / Z yaz. Girilen: $Answer" }
  $comp.transforms = @(@($comp.transforms) + @([pscustomobject]@{ op = "mirror"; axis = $ax }))
  $comp.pending_mirror = $false
} elseif ($kind -eq "edge_value") {
  $ekind = ($target -split '\.')[-1]
  $e = @($comp.edge_notes) | Where-Object { [string]$_.kind -eq $ekind } | Select-Object -First 1
  if ($null -eq $e) { throw "Kenar islemi bulunamadi: $ekind" }
  $e.value_mm = Parse-One $Answer
} elseif ($kind -eq "hole_center") {
  $hid = ($target -split '\.')[-2]
  $h = @($comp.holes) | Where-Object { [string]$_.id -eq $hid } | Select-Object -First 1
  if ($null -eq $h) { throw "Delik bulunamadi: $hid" }
  $p = Parse-Pair $Answer
  $h.center_x_mm = $p[0]; $h.center_y_mm = $p[1]; $h.status = "ok"
} elseif ($kind -eq "hole_dia") {
  $hid = ($target -split '\.')[-2]
  $h = @($comp.holes) | Where-Object { [string]$_.id -eq $hid } | Select-Object -First 1
  if ($null -eq $h) { throw "Delik bulunamadi: $hid" }
  $h.diameter_mm = Parse-One $Answer; $h.status = "ok"
} elseif ($kind -eq "hole_depth") {
  $hid = ($target -split '\.')[-2]
  $h = @($comp.holes) | Where-Object { [string]$_.id -eq $hid } | Select-Object -First 1
  if ($null -eq $h) { throw "Delik bulunamadi: $hid" }
  $h.depth_mm = Parse-One $Answer; $h.status = "ok"
} elseif ($kind -eq "hole_extra") {
  $hid = ($target -split '\.')[-2]
  $h = @($comp.holes) | Where-Object { [string]$_.id -eq $hid } | Select-Object -First 1
  if ($null -eq $h) { throw "Delik bulunamadi: $hid" }
  $p = Parse-Pair $Answer
  if ($h.hole_type -eq "countersink") { $h.cs_dia_mm = $p[0]; $h.cs_depth_mm = $p[1] }
  else { $h.cb_dia_mm = $p[0]; $h.cb_depth_mm = $p[1] }
  $h.status = "ok"
} elseif ($kind -eq "cutout") {
  $tid = [string]$q.field -replace '^cutouts\.', ''
  $t = @($comp.cutouts) | Where-Object { [string]$_.id -eq $tid } | Select-Object -First 1
  if ($null -eq $t) { throw "Kesik bulunamadi: $tid" }
  $dm = [regex]::Match($Answer, '(-?\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(-?\d+(?:[.,]\d+)?)')
  if (-not $dm.Success) { throw "Kesik olcusu anlasilmadi (ornek: 20x10). Girilen: $Answer" }
  $t.width_mm = Get-NumU $dm.Groups[1].Value; $t.length_mm = Get-NumU $dm.Groups[2].Value
  $pm = [regex]::Match($Answer, 'konum\s*(-?\d+(?:[.,]\d+)?)\s*[,;]\s*(-?\d+(?:[.,]\d+)?)')
  if ($pm.Success) { $t.pos_x_mm = Get-NumU $pm.Groups[1].Value; $t.pos_y_mm = Get-NumU $pm.Groups[2].Value }
  $dep = [regex]::Match($Answer, 'derinlik\s*(-?\d+(?:[.,]\d+)?)')
  if ($dep.Success) { $t.depth_mm = Get-NumU $dep.Groups[1].Value }
  if ($null -ne $t.pos_x_mm -and $null -ne $t.depth_mm) { $t.status = "ok" }
} elseif ($kind -eq "clearance") {
  $v = Parse-One $Answer
  $comp.tolerance.clearance_mm = $v; $comp.tolerance.status = "ok"
  foreach ($j in @($uspecObj.assembly.joints)) {
    if ($j -and ([string]$j.part_b -eq $cid -or [string]$j.part_a -eq $cid) -and $null -eq $j.clearance_mm) {
      $j.clearance_mm = $v
    }
  }
} elseif ($kind -eq "joint_clearance") {
  $jid = ($target -split '\.')[-1]
  $j = @($uspecObj.assembly.joints) | Where-Object { [string]$_.id -eq $jid } | Select-Object -First 1
  if ($null -eq $j) { throw "Baglanti bulunamadi: $jid" }
  $j.clearance_mm = Parse-One $Answer
} else { throw "Bilinmeyen soru turu: $kind" }

$q.answer = $Answer
$q.source = "user"
$q.asked_at = (Get-Date).ToUniversalTime().ToString("o")

$uspecObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SpecFile -Encoding UTF8
@($qs) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qfile -Encoding UTF8
Write-Output "CEVAP-ISLEDI: $QuestionId ($kind)"
