<#
.SYNOPSIS
  Cutout centered-placement TDD testleri (ortalanmis = explicit).
.DESCRIPTION
  T-CT-01..09 pozitif (placement/vertical/face/depth/soru-0) |
  T-CT-10 negatif (ortalanmis yoksa yatay sorulur, uydurulmaz).
  Not: yatay merkez repo konvansiyonu (body_width-cutW)/2 ile hesaplanir
  (G1 cutx=70 emsali); 160 genislikte 20 genislik icin x=70.
  Dosya ASCII-only; ozel karakterler [char] ile kurulur.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-CutoutCentered.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-CTResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-CTDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("ct-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function Get-CTParse($prompt, $tag) {
  $d = New-CTDir $tag
  $sf = Join-Path $d "spec.json"
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $sf 2>&1 | Out-Null
  $spec = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
  $qs = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $sf -AsJson 2>&1 | Out-String | ConvertFrom-Json
  return @{ spec = $spec; qs = @($qs | Where-Object { $_ -ne $null }); dir = $d }
}
function NumEq($a, $b) {
  try { return ([Math]::Abs([double]$a - [double]$b) -lt 0.0001) } catch { return $false }
}

$T = [char]0xD7
$oo = [char]0xF6
$ii = [char]0x131
$ss = [char]0x15F
$cc = [char]0xE7
$posP = "160x100x45 mm g" + $oo + "vde, arka k" + $ii + "sa kenarda ortalanm" + $ii + $ss + " 20" + $T + "10 mm a" + $cc + $ii + "kl" + $ii + "k, alt kenar" + $ii + " tabandan 12 mm, through-wall."
$negP = "160x100x45 mm g" + $oo + "vde, arka k" + $ii + "sa kenarda 20" + $T + "10 mm a" + $cc + $ii + "kl" + $ii + "k, alt kenar" + $ii + " tabandan 12 mm, through-wall."

$r = Get-CTParse $posP "ct01"
$c = @($r.spec.components | Where-Object { [string]$_.id -eq "body" })[0].cutouts[0]
Add-CTResult "T-CT-01" ($null -ne $c) "cutout exists"
Add-CTResult "T-CT-02" ((NumEq $c.width_mm 20) -and (NumEq $c.length_mm 10)) ("olcu=" + $c.width_mm + "x" + $c.length_mm)
Add-CTResult "T-CT-03" ([string]$c.face -eq "rear_short_edge") ("face=" + $c.face)
$pl = $c.placement
Add-CTResult "T-CT-04" ($null -ne $pl -and [string]$pl.type -eq "centered") "placement.type=centered"
Add-CTResult "T-CT-05" ($null -ne $pl -and [string]$pl.provenance -eq "explicit") "placement explicit (derived degil)"
$vx = $c.vertical
Add-CTResult "T-CT-06" ($null -ne $vx -and [string]$vx.type -eq "edge_offset" -and [string]$vx.reference -eq "bottom" -and (NumEq $vx.value 12) -and [string]$vx.provenance -eq "explicit") "vertical bottom=12 explicit"
Add-CTResult "T-CT-07" ([string]$c.penetration -eq "through_wall") ("depth=" + $c.penetration)
$hcQ = @($r.qs | Where-Object { [string]$_.question -match "yatay konum" })
Add-CTResult "T-CT-08" ($hcQ.Count -eq 0) "yatay soru yok"
Add-CTResult "T-CT-09" ($r.qs.Count -eq 0 -and (NumEq $c.pos_x_mm 70)) ("toplam soru=" + $r.qs.Count + " pos_x=" + $c.pos_x_mm + " (beklenen 70)")
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

$r = Get-CTParse $negP "ct10"
$c = @($r.spec.components | Where-Object { [string]$_.id -eq "body" })[0].cutouts[0]
$hcQ = @($r.qs | Where-Object { [string]$_.question -match "yatay konum" })
$noCen = ($null -eq $c.placement -or [string]$c.placement.type -ne "centered")
Add-CTResult "T-CT-10" (($null -eq $c.pos_x_mm) -and ($hcQ.Count -gt 0) -and $noCen) "ortalanmis yoksa yatay sorulur, uydurulmaz"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("CUTOUT SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
