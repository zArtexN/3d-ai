<#
.SYNOPSIS
  Adim B TDD testleri: iki yonlu olcu cozumu (MeasureParser).
.DESCRIPTION
  Spec-seviyesi (ConvertTo-GeometrySpec ciktisi) + birim (Find-Measure)
  testleri. Kapsam: sayi-once / anahtar-kelime-once / karisik sira,
  bolme kalinligi, kesik-ofseti/taban ayrisimi, yakinlik + esitlik kurali,
  tam-kelime, claim kaydi.
  Dosya ASCII-only; prompt'lar [char] ile kurulur.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-MeasureParser.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
$Lib = Join-Path $EngineDir "MeasureParser.ps1"

$results = New-Object System.Collections.Generic.List[object]
function Add-MPResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function Get-MPSpec($prompt, $tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("mp-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $sf = Join-Path $d "spec.json"
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $sf 2>&1 | Out-Null
  $spec = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
  Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
  return $spec
}
function NumEq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.0001) } catch { return $false }
}

# T-MP-01: sayi-once sira.
$spec = Get-MPSpec "80x40x20 kutu, 2.5 mm duvar, 3 mm taban, ustu acik" "mp01"
$b = $spec.components[0]
Add-MPResult "T-MP-01a" (NumEq $b.hollow.wall_mm 2.5) ("sayi-once duvar=" + $b.hollow.wall_mm + " (beklenen 2.5)")
Add-MPResult "T-MP-01b" (NumEq $b.hollow.bottom_thickness_mm 3) ("sayi-once taban=" + $b.hollow.bottom_thickness_mm + " (beklenen 3)")

# T-MP-02: anahtar-kelime-once sira (regresyon bekcisi).
$spec = Get-MPSpec "80x40x20 kutu, duvar 2.5 mm, taban 3 mm, ustu acik" "mp02"
$b = $spec.components[0]
Add-MPResult "T-MP-02a" (NumEq $b.hollow.wall_mm 2.5) ("kw-once duvar=" + $b.hollow.wall_mm + " (beklenen 2.5)")
Add-MPResult "T-MP-02b" (NumEq $b.hollow.bottom_thickness_mm 3) ("kw-once taban=" + $b.hollow.bottom_thickness_mm + " (beklenen 3)")

# T-MP-03: karisik sira (birimsiz sayi + sayi-once).
$spec = Get-MPSpec "80x40x20 kutu, duvar 2.5, 3 mm taban, ustu acik" "mp03"
$b = $spec.components[0]
Add-MPResult "T-MP-03a" (NumEq $b.hollow.wall_mm 2.5) ("karisik duvar=" + $b.hollow.wall_mm + " (beklenen 2.5)")
Add-MPResult "T-MP-03b" (NumEq $b.hollow.bottom_thickness_mm 3) ("karisik taban=" + $b.hollow.bottom_thickness_mm + " (beklenen 3)")

# T-MP-04: bolme kalinligi (bolmeden sonra gelen olcu).
$spec = Get-MPSpec "80x40x20 kutu, ustu acik, duvar 2 mm, 2 bolme 2 mm kalinliginda" "mp04"
$divs = @($spec.components | Where-Object { $_ -and [string]$_.id -like "div*" })
$thOk = ($divs.Count -eq 2)
foreach ($dv in $divs) { if (-not (NumEq $dv.thickness_mm 2)) { $thOk = $false } }
Add-MPResult "T-MP-04" $thOk ("bolme kalinligi (beklenen 2x div thickness=2)")

# T-MP-05: kesik ofseti taban ile cakismamali.
$spec = Get-MPSpec "80x40x20 kutu, duvar 2 mm, ustu acik, on yuzde 20x10 kesik tabandan 12 mm" "mp05a"
$b = $spec.components[0]
Add-MPResult "T-MP-05a" (NumEq $b.cutouts[0].pos_y_mm 12) ("tabandan-ofset pos_y=" + $b.cutouts[0].pos_y_mm + " (beklenen 12)")
Add-MPResult "T-MP-05b" ($null -eq $b.hollow.bottom_thickness_mm) ("taban calinmadi (beklenen null, mevcut=" + $b.hollow.bottom_thickness_mm + ")")
$spec = Get-MPSpec "80x40x20 kutu, duvar 2 mm, ustu acik, on yuzde 20x10 kesik alttan 12 mm" "mp05c"
$b = $spec.components[0]
Add-MPResult "T-MP-05c" (NumEq $b.cutouts[0].pos_y_mm 12) ("alttan-ofset pos_y=" + $b.cutouts[0].pos_y_mm + " (beklenen 12)")

# T-MP-06: ayni degerli uc sayi; herkes en yakinini alir.
$spec = Get-MPSpec "80x40x20 kutu, ustu acik, duvar 2 mm, bolme 2 adet, kalinlik 2 mm" "mp06"
$b = $spec.components[0]
$divs = @($spec.components | Where-Object { $_ -and [string]$_.id -like "div*" })
$thOk6 = ($divs.Count -gt 0)
foreach ($dv in $divs) { if (-not (NumEq $dv.thickness_mm 2)) { $thOk6 = $false } }
Add-MPResult "T-MP-06a" (NumEq $b.hollow.wall_mm 2) ("duvar ilk 2mm'yi aldi=" + $b.hollow.wall_mm)
Add-MPResult "T-MP-06b" $thOk6 ("kalinlik son 2mm'yi aldi")

# Birim testleri (kutuphane gerekir).
if (Test-Path -LiteralPath $Lib) { . $Lib } else { Add-MPResult "T-MP-00" $false "MeasureParser.ps1 yok" }
if (Get-Command Find-Measure -ErrorAction SilentlyContinue) {
  $lowTie = "2 mm duvar 3 mm"
  $rTie = Find-Measure $lowTie 'duvar'
  Add-MPResult "T-MP-10" ($null -ne $rTie -and (NumEq $rTie.value 3)) ("esitlikte kw-once kazanir (beklenen 3)")
  $rWord = Find-Measure "tabandan 12 mm" 'taban'
  Add-MPResult "T-MP-11" ($null -eq $rWord) ("tam-kelime: tabandan eslesmez")
  $reg = New-Object System.Collections.ArrayList
  $r1 = Find-Measure "duvar 2 mm taban" 'duvar' 60 $reg
  $r2 = Find-Measure "duvar 2 mm taban" 'taban' 60 $reg
  Add-MPResult "T-MP-12" (($null -ne $r1) -and ($null -eq $r2)) ("claim kaydi: ayni span iki key'e verilmez")
} else {
  Add-MPResult "T-MP-10" $false "Find-Measure yok"
  Add-MPResult "T-MP-11" $false "Find-Measure yok"
  Add-MPResult "T-MP-12" $false "Find-Measure yok"
}

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("MEASURE SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
