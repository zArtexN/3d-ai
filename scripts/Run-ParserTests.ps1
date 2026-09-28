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
Invoke-ParserCase "P17-complex-body" "160x100x45 mm dis olculerinde organizer yap. Duvar kalinligi 3 mm olsun. On yuze 20x10 mm kanal ac. 4.2 mm capinda delik olsun." {
  param($s, $q)
  $b = $s.components[0].base
  $dOk = ([double]$b.width_mm -eq 160 -and [double]$b.depth_mm -eq 100 -and [double]$b.height_mm -eq 45)
  $noBodyQ = (@($q | Where-Object { $_.component -eq "body" -and $_.kind -eq "dims" }).Count -eq 0)
  $c = $s.components[0].cutouts
  $slotOk = ($null -ne $c -and @($c).Count -gt 0 -and [double]$c[0].width_mm -eq 20 -and [double]$c[0].length_mm -eq 10)
  $ok = ($dOk -and $noBodyQ -and $slotOk)
  return @{ ok = $ok; detail = $(if ($ok) { "body 160/100/45, soru yok, slot 20x10" } else { "body=$($b.width_mm),$($b.depth_mm),$($b.height_mm) noBodyQ=$noBodyQ slotOk=$slotOk" }) }
}
Invoke-ParserCase "P18-yildiz" "160*100*45 mm kutu yap." {
  param($s, $q)
  $b = $s.components[0].base
  $dOk = ([double]$b.width_mm -eq 160 -and [double]$b.depth_mm -eq 100 -and [double]$b.height_mm -eq 45)
  $nq = @($q).Count
  $ok = ($dOk -and $nq -eq 0)
  return @{ ok = $ok; detail = $(if ($ok) { "yildiz ayirac okundu" } else { "body=$($b.width_mm) nq=$nq" }) }
}
Invoke-ParserCase "P19-birimli" "160mm x 100mm x 45mm kutu yap." {
  param($s, $q)
  $b = $s.components[0].base
  $dOk = ([double]$b.width_mm -eq 160 -and [double]$b.depth_mm -eq 100 -and [double]$b.height_mm -eq 45)
  $nq = @($q).Count
  $ok = ($dOk -and $nq -eq 0)
  return @{ ok = $ok; detail = $(if ($ok) { "sayi-arasi birim okundu" } else { "body=$($b.width_mm) nq=$nq" }) }
}
$multCh = [char]0xD7
Invoke-ParserCase "P20-carpma-complex" ("Dis olculer 160 " + $multCh + " 100 " + $multCh + " 45 mm olan organizer yap. Duvar 3 mm. 20x10 kanal ac. 8 mm derinlikte delik olsun.") {
  param($s, $q)
  $b = $s.components[0].base
  $dOk = ([double]$b.width_mm -eq 160 -and [double]$b.depth_mm -eq 100 -and [double]$b.height_mm -eq 45)
  $noBodyQ = (@($q | Where-Object { $_.component -eq "body" -and $_.kind -eq "dims" }).Count -eq 0)
  $c = $s.components[0].cutouts
  $slotOk = ($null -ne $c -and @($c).Count -gt 0 -and [double]$c[0].width_mm -eq 20 -and [double]$c[0].length_mm -eq 10)
  $ok = ($dOk -and $noBodyQ -and $slotOk)
  return @{ ok = $ok; detail = $(if ($ok) { "carpma isareti + celendiriciler atlatildi" } else { "body=$($b.width_mm),$($b.depth_mm),$($b.height_mm) noBodyQ=$noBodyQ slotOk=$slotOk" }) }
}
Invoke-ParserCase "P21-eksik-sorulsun" "Duvar kalinligi 3 mm olan organizer yap." {
  param($s, $q)
  $nq = @($q | Where-Object { $_.component -eq "body" -and $_.kind -eq "dims" }).Count
  $ok = ($nq -eq 1)
  return @{ ok = $ok; detail = $(if ($ok) { "gercekten eksikse soruluyor" } else { "body-dims sorusu yok!" }) }
}
$odCh = [char]0xD8
$p23a = "160x100x45 mm govde yap. Ustu acik olsun. Duvar kalinligi 2.5 mm olsun. Ayni geometri korunarak temiz govde olsun. Delikler tabandan tamamen gecsin. Uste " + $odCh + "8 mm capinda 3 mm derinliginde counterbore olsun. Taban uzerinde 4 adet " + $odCh + "4.2 mm gecisli vida deligi olsun, kenarlardan 8 mm iceride. On yuze 20x10 mm kablo acikligi ac, alt kenari tabandan 12 mm yukarida olsun. Dis kose 5 mm yaricapla yuvarlatilsin. Kablo kenarinda 2 mm pah gerekiyorsa degerlendir. Altta 1 mm pah kullan."
Invoke-ParserCase "P23-org-realpROMPT" $p23a {
  param($s, $q)
  $b = $s.components[0]
  $dOk = ([double]$b.base.width_mm -eq 160 -and [double]$b.base.depth_mm -eq 100 -and [double]$b.base.height_mm -eq 45)
  $hOk = ([double]$b.hollow.wall_mm -eq 2.5 -and $b.hollow.open_top -eq $true)
  $noDiaQ = (@($q | Where-Object { $_.kind -eq "hole_dia" }).Count -eq 0)
  $noTopQ = (@($q | Where-Object { $_.kind -eq "hollow_top" }).Count -eq 0)
  $noBodyQ = (@($q | Where-Object { $_.component -eq "body" -and $_.kind -eq "dims" }).Count -eq 0)
  $hs = @($b.holes)
  $holesOk = ($hs.Count -eq 4)
  foreach ($h in $hs) {
    if ([double]$h.diameter_mm -ne 4.2 -or [string]$h.hole_type -ne "through" -or [double]$h.edge_offset_mm -ne 8 -or [double]$h.cb_dia_mm -ne 8 -or [double]$h.cb_depth_mm -ne 3) { $holesOk = $false }
  }
  $c = $b.cutouts[0]
  $cutOk = ([double]$c.width_mm -eq 20 -and [double]$c.length_mm -eq 10 -and [double]$c.pos_y_mm -eq 12)
  $fil = @($b.edge_notes | Where-Object { $_.kind -eq "fillet" } | Select-Object -First 1)
  $chm = @($b.edge_notes | Where-Object { $_.kind -eq "chamfer" } | Select-Object -First 1)
  $edgeOk = ([double]$fil[0].value_mm -eq 5 -and [double]$chm[0].value_mm -eq 1)
  $ok = ($dOk -and $hOk -and $noDiaQ -and $noTopQ -and $noBodyQ -and $holesOk -and $cutOk -and $edgeOk)
  return @{ ok = $ok; detail = $(if ($ok) { "gercek prompt tuzaklari atlatildi" } else { "d=$dOk h=$hOk noDia=$noDiaQ noTop=$noTopQ noBody=$noBodyQ holes=$holesOk cut=$cutOk edge=$edgeOk" }) }
}
Invoke-ParserCase "P24-kor-siniri" "80x40x20 kutu delik 10 merkez 20,20, ayni geometri korunarak modellensin." {
  param($s, $q)
  $h = $s.components[0].holes[0]
  $ok = ([string]$h.hole_type -eq "through" -and [double]$h.diameter_mm -eq 10)
  return @{ ok = $ok; detail = $(if ($ok) { "korunarak blind sanilmadi" } else { "type=$($h.hole_type)" }) }
}
$odC = [char]0xD8
$p25 = "160x100x45 mm govde yap. Ustu acik olsun. Duvar 2.5 mm olsun. Her deligin merkezi dis kenarlardan 8 mm iceride 4 adet " + $odC + "4.2 mm delik olsun."
Invoke-ParserCase "P25-kose-yerlesim" $p25 {
  param($s, $q)
  $hs = @($s.components[0].holes)
  $nq = @($q | Where-Object { $_.kind -eq "hole_center" }).Count
  $exp = @("8,8", "152,8", "8,92", "152,92")
  $got = @($hs | ForEach-Object { ([string]$_.center_x_mm + "," + [string]$_.center_y_mm) })
  $ok = ($hs.Count -eq 4 -and $nq -eq 0 -and (($got -join "|") -eq ($exp -join "|")) -and [string]$hs[0].placement.type -eq "corner_pattern")
  return @{ ok = $ok; detail = $(if ($ok) { "4 kose deterministik" } else { "got=$($got -join '|') nq=$nq" }) }
}
Invoke-ParserCase "P26-kapaksiz" "80x40x20 kapaksiz kutu yap." {
  param($s, $q)
  $b = $s.components[0]
  $noLid = (@($s.components | Where-Object { $_.id -eq "lid" }).Count -eq 0)
  $noTopQ = (@($q | Where-Object { $_.kind -eq "hollow_top" }).Count -eq 0)
  $ok = ($b.hollow.open_top -eq $true -and $noLid -and $noTopQ)
  return @{ ok = $ok; detail = $(if ($ok) { "kapaksiz: acik + lid yok" } else { "open=$($b.hollow.open_top) noLid=$noLid" }) }
}
Invoke-ParserCase "P26b-ustten" "80x40x20 kutu yap, ustten acik olsun, duvar 2 mm olsun." {
  param($s, $q)
  $b = $s.components[0]
  $nq = @($q).Count
  $ok = ($b.hollow.open_top -eq $true -and $nq -eq 0)
  return @{ ok = $ok; detail = $(if ($ok) { "ustten acik sorusuz" } else { "open=$($b.hollow.open_top) nq=$nq" }) }
}
Invoke-ParserCase "P27-butunlesik" "120x80x40 kutu yap. Icinde 2 adet bolme olsun, ayri parca olarak modellenmesin." {
  param($s, $q)
  # Adim A: component/integrated ayrimi kalkti; her bolme govde ozelligi (tek davranis).
  $divs = @($s.components | Where-Object { $_.id -like "div*" })
  $dp = @($s.components | Where-Object { $_.id -eq "body" })[0].divider_pattern
  $ok = ($divs.Count -eq 0 -and [int]$dp.count -eq 2)
  return @{ ok = $ok; detail = $(if ($ok) { "bolme govde ozelligi (component yok)" } else { "divs=$($divs.Count)" }) }
}
Invoke-ParserCase "P27b-ayri" "120x80x40 kutu yap. Icinde 2 adet ayri bolme olsun." {
  param($s, $q)
  # Adim A: "ayri" sozu artik component uretmez; geometri ayni (govde-ici panel).
  $divs = @($s.components | Where-Object { $_.id -like "div*" })
  $dp = @($s.components | Where-Object { $_.id -eq "body" })[0].divider_pattern
  $ok = ($divs.Count -eq 0 -and [int]$dp.count -eq 2)
  return @{ ok = $ok; detail = $(if ($ok) { "ayri sozu component uretmez" } else { "divs=$($divs.Count)" }) }
}
$p22 = "160x100x45 mm dis olculerinde organizer yap. Ustu acik olsun. Duvar kalinligi 2.5 mm, taban kalinligi 3 mm olsun. Dis kose yaricapi 5 mm olsun. Icinde 2 adet bolme olsun, bolme kalinligi 2 mm. On yuze 20x10 mm kablo acikligi ac, alt kenardan 12 mm yukarida olsun. Taban uzerinde 4 adet " + $odCh + "4.2 mm gecisli vida deligi olsun, kenarlardan 8 mm iceride. Deliklerin ustunde 8 mm capinda 3 mm derinliginde counterbore gomme olsun. Taban altinda 10x10 mm temas alanlari olsun. Kenarlara 1 mm pah kir."
Invoke-ParserCase "P22-org-holes" $p22 {
  param($s, $q)
  $b = $s.components[0]
  $dOk = ([double]$b.base.width_mm -eq 160 -and [double]$b.base.depth_mm -eq 100 -and [double]$b.base.height_mm -eq 45)
  $hOk = ([double]$b.hollow.wall_mm -eq 2.5 -and $b.hollow.open_top -eq $true -and [double]$b.hollow.bottom_thickness_mm -eq 3)
  $noDiaQ = (@($q | Where-Object { $_.kind -eq "hole_dia" }).Count -eq 0)
  $noTopQ = (@($q | Where-Object { $_.kind -eq "hollow_top" }).Count -eq 0)
  $hs = @($b.holes)
  $hOk = ($hs.Count -eq 4)
  foreach ($h in $hs) {
    if ([double]$h.diameter_mm -ne 4.2 -or [string]$h.hole_type -ne "through" -or [double]$h.edge_offset_mm -ne 8 -or [double]$h.cb_dia_mm -ne 8 -or [double]$h.cb_depth_mm -ne 3) { $hOk = $false }
  }
  # Adim A: kalinlik artik body.divider_pattern'de (bagimsiz div component yok).
  $dp = $b.divider_pattern
  $divOk = ($null -ne $dp -and [int]$dp.count -eq 2 -and [double]$dp.thickness_mm -eq 2)
  $c = $b.cutouts[0]
  $cutOk = ([double]$c.width_mm -eq 20 -and [double]$c.length_mm -eq 10 -and [double]$c.pos_y_mm -eq 12)
  $padOk = ($null -ne $b.contact_pads -and [double]$b.contact_pads[0].width_mm -eq 10 -and [double]$b.contact_pads[0].length_mm -eq 10)
  $fil = @($b.edge_notes | Where-Object { $_.kind -eq "fillet" } | Select-Object -First 1)
  $chm = @($b.edge_notes | Where-Object { $_.kind -eq "chamfer" } | Select-Object -First 1)
  $edgeOk = ([double]$fil[0].value_mm -eq 5 -and [double]$chm[0].value_mm -eq 1)
  $ok = ($dOk -and $hOk -and $noDiaQ -and $noTopQ -and $hOk -and $divOk -and $cutOk -and $padOk -and $edgeOk)
  return @{ ok = $ok; detail = $(if ($ok) { "complex organizer tam parse" } else { "d=$dOk h=$hOk noDia=$noDiaQ noTop=$noTopQ holes=$hOk div=$divOk cut=$cutOk pad=$padOk edge=$edgeOk" }) }
}

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "PARSER SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
