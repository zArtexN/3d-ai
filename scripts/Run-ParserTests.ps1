<#
.SYNOPSIS
  TR parser ornek testleri (§15). Hizli (OpenSCAD yok). Deger uydurma ihtimaline karsi soru davranisi dgrulanir.
.DESCRIPTION
  Her ornek: prompt -> spec + sorular; beklenen deger/soru sayisi karsilastirilir.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Run-ParserTests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Parser = Join-Path $Root (Join-Path "engine" "ConvertTo-GeometrySpec.ps1")
$GQ = Join-Path $Root (Join-Path "engine" "Get-SpecQuestions.ps1")

$results = New-Object System.Collections.Generic.List[object]
function Add-XResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function Invoke-ParserCase($name, $prompt, $check) {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("ptest-" + ($name -replace '[^A-Za-z0-9]+', '-') + ".json")
  try {
    & $Parser -Prompt $prompt -ProjectName $name -OutPath $tmp 2>&1 | Out-Null
    $spec = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
    $qsTxt = & $GQ -SpecFile $tmp -AsJson 2>&1 | Out-String
    $qsParsed = $qsTxt | ConvertFrom-Json
    $qs = @($qsParsed | Where-Object { $_ -ne $null })
    $r = & $check $spec $qs
    Add-XResult $name $r.ok $r.detail
  } catch { Add-XResult $name $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}

Invoke-ParserCase "P1-kutu" "120x80x40 mm kutu yap." {
  param($s, $q)
  $b = $s.components[0].base
  $dOk = ([double]$b.width_mm -eq 120 -and [double]$b.depth_mm -eq 80 -and [double]$b.height_mm -eq 40)
  $nq = @($q).Count
  $ok = ($dOk -and $nq -eq 0)
  return @{ ok = $ok; detail = $(if ($ok) { "olculer aynen" } else { "sapma" }) }
}
Invoke-ParserCase "P2-duvar" "120x80x40 kutu, duvar kalinligi 2 mm olsun." {
  param($s, $q)
  $h = $s.components[0].hollow
  $wOk = ([double]$h.wall_mm -eq 2)
  $nq = @($q | Where-Object { $_.kind -eq "hollow_top" }).Count
  $ok = ($wOk -and $nq -eq 1)
  return @{ ok = $ok; detail = $(if ($ok) { "duvar 2 + acik/kapali sorusu" } else { "wall=$($h.wall_mm) nq=$nq" }) }
}
Invoke-ParserCase "P3-ust-delik" "Kutunun ustune 30 mm capinda delik ac." {
  param($s, $q)
  $h = $s.components[0].holes[0]
  $dOk = ([double]$h.diameter_mm -eq 30)
  $nq = @($q | Where-Object { $_.kind -eq "hole_center" }).Count
  $ok = ($dOk -and $nq -ge 1)
  return @{ ok = $ok; detail = $(if ($ok) { "cap 30 + merkez sorusu" } else { "eksik" }) }
}
Invoke-ParserCase "P4-bosalt" "Icini bosalt ve duvarlari 2 mm birak." {
  param($s, $q)
  $h = $s.components[0].hollow
  $wOk = ([double]$h.wall_mm -eq 2)
  $nq = @($q | Where-Object { $_.kind -eq "hollow_top" }).Count
  $ok = ($wOk -and $nq -eq 1)
  return @{ ok = $ok; detail = $(if ($ok) { "duvar 2 + yon sorusu" } else { "wall=$($h.wall_mm) nq=$nq" }) }
}
Invoke-ParserCase "P5-kapak" "60x40x20 kutu, bir kapak ekle." {
  param($s, $q)
  $lid = @($s.components) | Where-Object { $_.id -eq "lid" } | Select-Object -First 1
  $nq = @($q).Count
  $ok = ($lid -and $nq -ge 2)
  return @{ ok = $ok; detail = $(if ($ok) { "kapak + sorular" } else { "lid=$($null -ne $lid) nq=$nq" }) }
}
Invoke-ParserCase "P6-bosluk" "60x40x20 kutu, kapakta 0.2 mm bosluk birak." {
  param($s, $q)
  $t = $s.components[0].tolerance
  $ok = ([double]$t.clearance_mm -eq 0.2)
  return @{ ok = $ok; detail = $(if ($ok) { "0.2 aynen" } else { "sapma" }) }
}
Invoke-ParserCase "P7-kanal" "Yan tarafa 10x30 mm kanal ac." {
  param($s, $q)
  $c = $s.components[0].cutouts[0]
  $kOk = ($c.kind -eq "slot")
  $dOk = ([double]$c.width_mm -eq 10 -and [double]$c.length_mm -eq 30)
  $nq = @($q | Where-Object { $_.kind -eq "cutout" }).Count
  $ok = ($kOk -and $dOk -and $nq -ge 1)
  return @{ ok = $ok; detail = $(if ($ok) { "slot 10x30 + konum sorusu" } else { "eksik" }) }
}
Invoke-ParserCase "P8-havsa" "Deligi havsali yap." {
  param($s, $q)
  $h = $s.components[0].holes[0]
  $isCs = ($h.hole_type -eq "countersink")
  $nq = @($q).Count
  $ok = ($isCs -and $nq -ge 2)
  return @{ ok = $ok; detail = $(if ($ok) { "havsa + cap/merkez sorusu" } else { "type=$($h.hole_type) nq=$nq" }) }
}
Invoke-ParserCase "P9-dondur" "80x40x20 kutu, parcayi 90 derece dondur." {
  param($s, $q)
  $c = $s.components[0]
  $nq = @($q).Count
  $nm = @($q | Where-Object { $_.kind -eq "rotate_axis" }).Count
  $ok = ([double]$c.pending_rotate -eq 90 -and $nm -eq 1)
  return @{ ok = $ok; detail = $(if ($ok) { "aci 90 + eksen sorusu" } else { "pend=$($c.pending_rotate) nq=$nq nm=$nm kinds=$(@($q | ForEach-Object { $_.kind }) -join '|')" }) }
}
Invoke-ParserCase "P10-simetri" "80x40x20 kutu, simetrisini al." {
  param($s, $q)
  $c = $s.components[0]
  $pm = ($c.pending_mirror -eq $true)
  $nq = @($q | Where-Object { $_.kind -eq "mirror_axis" }).Count
  $ok = ($pm -and $nq -eq 1)
  return @{ ok = $ok; detail = $(if ($ok) { "ayna + eksen sorusu" } else { "pm=$($c.pending_mirror) nq=$nq" }) }
}
Invoke-ParserCase "P11-yuvarlat" "80x40x20 kutu, keskin kenarlari yuvarlat." {
  param($s, $q)
  $e = $s.components[0].edge_notes[0]
  $isFil = ($e.kind -eq "fillet")
  $vNull = ($null -eq $e.value_mm)
  $nq = @($q | Where-Object { $_.kind -eq "edge_value" }).Count
  $ok = ($isFil -and $vNull -and $nq -eq 1)
  return @{ ok = $ok; detail = $(if ($ok) { "kenar + olcu sorusu" } else { "kind=$($e.kind) nq=$nq" }) }
}
Invoke-ParserCase "P12-kenardan" "80x40x20 kutu, delik kenardan 15 mm iceride olsun." {
  param($s, $q)
  $h = $s.components[0].holes[0]
  $nq = @($q | Where-Object { $_.kind -eq "hole_center" -or $_.kind -eq "hole_dia" }).Count
  $ok = ($h -and $nq -ge 1)
  return @{ ok = $ok; detail = $(if ($ok) { "konum uydurulmadi, soruldu" } else { "eksik" }) }
}
Invoke-ParserCase "P13-iki-parca" "80x40x20 kutu, kutuyu iki parcaya ayir." {
  param($s, $q)
  $lid = @($s.components) | Where-Object { $_.id -eq "lid" } | Select-Object -First 1
  $nq = @($q).Count
  $ok = ($lid -and $nq -ge 1)
  return @{ ok = $ok; detail = $(if ($ok) { "2. parca + sorular" } else { "eksik" }) }
}
Invoke-ParserCase "P14-cogul-delik" "80x40x20 kutu, delikleri 5 mm capinda yap, merkez 20,20." {
  param($s, $q)
  $h = $s.components[0].holes[0]
  $ok = ([double]$h.diameter_mm -eq 5 -and [double]$h.center_x_mm -eq 20)
  return @{ ok = $ok; detail = $(if ($ok) { "cogul kalip okundu" } else { "eksik" }) }
}
Invoke-ParserCase "P15-z-dondur" "80x40x20 kutu, Z ekseninde 90 derece dondur." {
  param($s, $q)
  $t = $s.components[0].transforms[0]
  $ok = ($t.op -eq "rotate" -and [double]$t.z -eq 90)
  return @{ ok = $ok; detail = $(if ($ok) { "rotate z90" } else { "eksik" }) }
}
Invoke-ParserCase "P16-deger-koruma" "120 mm kutu yok; 120x80x40 kutu, 0.2 mm bosluk." {
  param($s, $q)
  $b = $s.components[0].base
  $ok = ([double]$b.width_mm -eq 120)
  return @{ ok = $ok; detail = $(if ($ok) { "120 aynen korundu" } else { "degisti!" }) }
}

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "PARSER SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
