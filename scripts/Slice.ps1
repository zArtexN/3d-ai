<#
.SYNOPSIS
  OrcaSlicer profilleriyle dilimler. SADECE slicing asamasi, modelleme bitmeden calismaz.
.DESCRIPTION
  G-code AI tarafindan uretilmez; OrcaSlicer CLI + yazici/filament profili zorunludur.
  Profil adlari printers/<yazici>.json dosyasindaki orca_profiles ile birebir ayni olmalidir.
.EXAMPLE
  powershell -File scripts\Slice.ps1 -Input3mf projects\ornek\output\model.3mf -PrinterProfile "MyPrinter 0.4" -FilamentProfile "Generic PLA" -OutDir projects\ornek\slice
#>
param(
  [Parameter(Mandatory = $true)][string]$Input3mf,
  [Parameter(Mandatory = $true)][string]$PrinterProfile,
  [Parameter(Mandatory = $true)][string]$FilamentProfile,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [string]$ProcessProfile = "",
  [string]$OrcaExe = "C:\Program Files\OrcaSlicer\orca-slicer.exe",
  [string]$PrinterJson = ""
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Input3mf)) { throw "Giris dosyasi bulunamadi: $Input3mf" }
if (-not (Test-Path -LiteralPath $OrcaExe)) { throw "OrcaSlicer bulunamadi: $OrcaExe" }
# BLOCKED: gercek profiller yoksa dilimleme baslamaz (placeholder/ bos deger yasak).
if ([string]::IsNullOrWhiteSpace($PrinterProfile) -or $PrinterProfile -like "REPLACE*") { throw "BLOCKED: gecerli bir OrcaSlicer yazici profili verin (printers/*.json). Placeholder ile dilimleme yasak." }
if ([string]::IsNullOrWhiteSpace($FilamentProfile) -or $FilamentProfile -like "REPLACE*") { throw "BLOCKED: gecerli bir OrcaSlicer filament profili verin. Placeholder ile dilimleme yasak." }
if ([string]::IsNullOrWhiteSpace($ProcessProfile) -or $ProcessProfile -like "REPLACE*") { throw "BLOCKED: gecerli bir OrcaSlicer process profili verin. Placeholder ile dilimleme yasak." }
if ($PrinterJson -ne "") {
  if (-not (Test-Path -LiteralPath $PrinterJson)) { throw "BLOCKED: yazici profil dosyasi bulunamadi: $PrinterJson" }
  $pjSlice = Get-Content -LiteralPath $PrinterJson -Raw | ConvertFrom-Json
  if ([string]$pjSlice.source -eq "template" -or $pjSlice.usable_for_slicing -eq $false) { throw "BLOCKED: '$($pjSlice.id)' sablon profildir; gercek yazici profili olmadan dilimleme yasak." }
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# Not: OrcaSlicer CLI surume gore degisir; gecerli komut profillerinle dogrulanmadan G-code uretme.
throw "Slice.ps1 henuz makinedeki OrcaSlicer profillerinle eslestirilmedi. Once OrcaSlicer'da yazici+filament profilini ac, profil adlarini printers/*.json'a isle, sonra bu scriptteki CLI komutunu o surume gore tamamla. Tahmini G-code uretme."
