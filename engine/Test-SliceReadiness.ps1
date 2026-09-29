<#
.SYNOPSIS
  Phase 8: dilimleme hazirlik kapisi (G-code gate on-kosulu) + cikti dogrulama.
.DESCRIPTION
  Test-SliceReadiness: G-code BLOCKED kalir UNLESS model+yazici+filament+process+
  slicer+profil TAMAM. Donus: @{ status READY|BLOCKED; missing[] (@{id,message}) }.
  Test-SliceOutput: slice SONRASI artifact dogrulama: @{ status OK|FAIL; errors[] }.
  Deger URETMEZ, dosya YAZMAZ (saf okuma).
#>
param()

$SliceGateDir = $PSScriptRoot
. (Join-Path $SliceGateDir "Test-Profiles.ps1")

function Add-Missing($list, $id, $msg) {
  $list.Add([pscustomobject]@{ id = $id; message = $msg }) | Out-Null
}

function Resolve-SlicerExe([string]$OrcaExe) {
  if (-not [string]::IsNullOrWhiteSpace($OrcaExe)) {
    # Acikca verilen yol yoksa baska bir binary'ye sessizce DUSULMEZ (yanlis
    # profille dilimleme riski); slicer unavailable doner.
    if (Test-Path -LiteralPath $OrcaExe) { return $OrcaExe }
    return ""
  }
  $Root = Split-Path -Parent $SliceGateDir
  $rs = Join-Path $Root (Join-Path "scripts" "Resolve-OrcaSlicer.ps1")
  try {
    $found = & $rs 2>$null | Select-Object -Last 1
    if ($found -and (Test-Path -LiteralPath ([string]$found))) { return [string]$found }
  } catch { }
  return ""
}

function Test-SliceReadiness(
  [string]$ModelStl = "",
  [string]$PrinterJson = "",
  [string]$FilamentJson = "",
  [string]$ProcessJson = "",
  [string]$OrcaExe = ""
) {
  $missing = New-Object System.Collections.ArrayList
  if ([string]::IsNullOrWhiteSpace($ModelStl) -or -not (Test-Path -LiteralPath $ModelStl)) {
    Add-Missing $missing "model" "gecerli model yok (STL/3MF bulunamadi)"
  } else {
    try {
      $len = (Get-Item -LiteralPath $ModelStl).Length
      $ext = [System.IO.Path]::GetExtension($ModelStl).ToLowerInvariant()
      if ($len -le 0) { Add-Missing $missing "model" "model dosyasi bos" }
      elseif ($ext -ne ".stl" -and $ext -ne ".3mf") { Add-Missing $missing "model" "model formati desteklenmiyor: $ext" }
    } catch { Add-Missing $missing "model" "model okunamadi" }
  }
  if ([string]::IsNullOrWhiteSpace($PrinterJson)) {
    Add-Missing $missing "printer" "yazici profili secilmemis"
  } else {
    $pv = Test-PrinterProfile $PrinterJson
    if (-not $pv.valid) { Add-Missing $missing "printer" ("yazici profili gecersiz: " + ($pv.errors -join "; ")) }
    elseif (-not $pv.slicable) { Add-Missing $missing "printer" ("yazici dilimlemeye hazir degil: " + ($pv.warnings -join "; ")) }
  }
  if ([string]::IsNullOrWhiteSpace($FilamentJson)) {
    Add-Missing $missing "filament" "filament profili secilmemis"
  } else {
    $fv = Test-FilamentProfile $FilamentJson
    if (-not $fv.valid) { Add-Missing $missing "filament" ("filament profili gecersiz: " + ($fv.errors -join "; ")) }
    elseif (-not $fv.slicable) { Add-Missing $missing "filament" ("filament dilimlemeye hazir degil: " + ($fv.warnings -join "; ")) }
  }
  if ([string]::IsNullOrWhiteSpace($ProcessJson)) {
    Add-Missing $missing "process" "process profili secilmemis"
  } else {
    $cv = Test-ProcessProfile $ProcessJson
    if (-not $cv.valid) { Add-Missing $missing "process" ("process profili gecersiz: " + ($cv.errors -join "; ")) }
    elseif (-not $cv.slicable) { Add-Missing $missing "process" ("process dilimlemeye hazir degil: " + ($cv.warnings -join "; ")) }
  }
  $exe = Resolve-SlicerExe $OrcaExe
  if ($exe -eq "") { Add-Missing $missing "slicer" "OrcaSlicer binary bulunamadi (slicer unavailable)" }
  $st = "READY"
  if ($missing.Count -gt 0) { $st = "BLOCKED" }
  return [pscustomobject]@{ status = $st; missing = @($missing.ToArray()); slicer_exe = $exe }
}

function Test-SliceOutput([string]$GcodePath = "") {
  $errs = @()
  if ([string]::IsNullOrWhiteSpace($GcodePath) -or -not (Test-Path -LiteralPath $GcodePath)) {
    $errs += @("cikti yok (G-code uretilemedi/bulunamadi)")
  } else {
    try {
      $len = (Get-Item -LiteralPath $GcodePath).Length
      if ($len -le 0) { $errs += @("G-code dosyasi bos") }
    } catch { $errs += @("cikti okunamadi") }
  }
  $st = "OK"
  if ($errs.Count -gt 0) { $st = "FAIL" }
  return [pscustomobject]@{ status = $st; errors = $errs }
}
