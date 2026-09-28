<#
.SYNOPSIS
  Tasarim verisini (input.json) dogrular. SADECE kontrol eder; hicbir degeri DEGISTIRMEZ.
.DESCRIPTION
  Kontroller:
    HATA (model uretimini engeller):
      - govde olculeri pozitif degilse
      - duvar kalinligi verilmisse pozitif degilse
      - delik capi pozitif degilse
      - delik merkezi "missing" ise (kritik olcu eksik -> MODEL OLUSTURULMAZ)
      - delik govde disinda kaliyorsa (merkez +- yaricap govde disi)
    UYARI (uretim devam eder, otomatik degisiklik YOK):
      - duvar < yazici min_wall_mm (risk bildirimi, deger aynen korunur)
      - delik kenar boslugu < wall_thickness_mm
      - delik capi < yazici min_hole_mm
      - detay < min_feature_mm
      - tolerans belirtilmemisse (tolerance_mm null)
  Cikis: 0 = hata yok (uyari olabilir), 1 = hata var. -AsJson ile JSON rapor.
  NOT: $Spec (dosya yolu) ile $specObj (parse edilmis veri) bilerek farkli adlardadir;
  PowerShell buyuk/kucuk harf duyarsiz oldugu icin ayni ada izin verilmez.
.EXAMPLE
  powershell -File engine\Test-DesignSpec.ps1 -Spec projects\x\input.json -Printer printers\generic-fdm.json -AsJson
#>
param(
  [Parameter(Mandatory = $true)][string]$Spec,
  [string]$Printer = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Spec)) { throw "Spec bulunamadi: $Spec" }
$specObj = Get-Content -LiteralPath $Spec -Raw | ConvertFrom-Json

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$minWall = $null; $minFeature = $null; $minHole = $null
$printerId = ""
if ($Printer -ne "" -and (Test-Path -LiteralPath $Printer)) {
  try {
    $pj = Get-Content -LiteralPath $Printer -Raw | ConvertFrom-Json
    $printerId = $pj.id
    if ($null -ne $pj.min_wall_mm -and [double]$pj.min_wall_mm -gt 0) { $minWall = [double]$pj.min_wall_mm }
    if ($null -ne $pj.min_feature_mm -and [double]$pj.min_feature_mm -gt 0) { $minFeature = [double]$pj.min_feature_mm }
    if ($null -ne $pj.min_hole_mm -and [double]$pj.min_hole_mm -gt 0) { $minHole = [double]$pj.min_hole_mm }
  } catch { $warnings.Add("WARNING: yazici profili okunamadi ($Printer); yaziciya ozel limitler kontrol edilmedi") }
} else {
  $warnings.Add("WARNING: printer profili verilmedi; yaziciya ozel limitler kontrol edilmedi")
}

$b = $specObj.body
if ($null -eq $b) { $errors.Add("body (govde olculeri) eksik") }
else {
  foreach ($k in @("width_mm", "depth_mm", "height_mm")) {
    if ($null -eq $b.$k -or [double]$b.$k -le 0) { $errors.Add("body.$k pozitif olmali (mevcut: $($b.$k))") }
  }
}

$wall = $null
if ($null -ne $specObj.wall_thickness_mm) {
  $wall = [double]$specObj.wall_thickness_mm
  if ($wall -le 0) { $errors.Add("wall_thickness_mm pozitif olmali (mevcut: $wall)") }
  elseif ($null -ne $minWall -and $wall -lt $minWall) {
    $warnings.Add("WARNING: duvar kalinligi $wall mm, limit $minWall mm altinda. Riskli olabilir; deger KORUNDU, otomatik degistirilmedi.")
  }
}

foreach ($h in @($specObj.holes)) {
  if ($null -eq $h) { continue }
  $id = $h.id
  if ($null -eq $h.diameter_mm -or [double]$h.diameter_mm -le 0) { $errors.Add("delik '$id': cap pozitif olmali") ; continue }
  $d = [double]$h.diameter_mm
  if ($null -ne $minHole -and $d -lt $minHole) { $warnings.Add("WARNING: delik '$id' capi $d mm < min delik $minHole mm") }
  if ($h.status -eq "missing" -or $null -eq $h.center_x_mm -or $null -eq $h.center_y_mm) {
    $errors.Add("delik '$id': merkez kritik olcu eksik (status=missing) -> model olusturulamaz")
    continue
  }
  if ($null -ne $b -and [double]$b.width_mm -gt 0 -and [double]$b.depth_mm -gt 0) {
    $r = $d / 2
    $cx = [double]$h.center_x_mm; $cy = [double]$h.center_y_mm
    if (($cx - $r) -lt 0 -or ($cx + $r) -gt [double]$b.width_mm -or ($cy - $r) -lt 0 -or ($cy + $r) -gt [double]$b.depth_mm) {
      $errors.Add("delik '$id': govde disinda kaliyor (merkez $cx,$cy cap $d, govde $($b.width_mm)x$($b.depth_mm))")
    } elseif ($null -ne $wall) {
      $edge = [math]::Min([math]::Min($cx - $r, [double]$b.width_mm - ($cx + $r)), [math]::Min($cy - $r, [double]$b.depth_mm - ($cy + $r)))
      if ($edge -lt $wall) { $warnings.Add("WARNING: delik '$id' kenar boslugu $([math]::Round($edge,2)) mm < duvar $wall mm") }
      if ($null -ne $minFeature -and $edge -lt $minFeature) { $warnings.Add("WARNING: delik '$id' cevresi cok ince bolge iceriyor ($([math]::Round($edge,2)) mm)") }
    }
  }
}

if ($null -eq $specObj.tolerance_mm) { $warnings.Add("WARNING: tolerans belirtilmedi (tolerance_mm null); gecme payi gerekiyorsa sorulmali") }

$status = "OK"
if ($errors.Count -gt 0) { $status = "BLOCKED" }
elseif ($warnings.Count -gt 0) { $status = "OK_WITH_WARNINGS" }

$report = [pscustomobject]@{
  status = $status
  spec = $Spec
  printer = $printerId
  errors = @($errors)
  warnings = @($warnings)
}

if ($AsJson) { $report | ConvertTo-Json -Depth 5 }
else {
  Write-Output "DESIGN: $status"
  foreach ($e in $errors) { Write-Output "  ERROR: $e" }
  foreach ($w in $warnings) { Write-Output "  $w" }
}
if ($errors.Count -gt 0) { exit 1 } else { exit 0 }
