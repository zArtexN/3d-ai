<#
.SYNOPSIS
  Delik yerlesim matematigi paylasilan kutuphane (Adim C).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok; dot-source ile ice
  aktarilir, caller scope kirletmez.
  Get-PatternCenters: TEK deterministik kaynak (parser tahmin etmez,
  compiler bu fonksiyonla uretir).
  corner_pattern: (off,off),(w-off,off),(off,d-off),(w-off,d-off).
  mid_edge: (w/2,off),(w/2,d-off),(off,d/2),(w-off,d/2).
  Donus: 4 elemanli @(@(x,y),...) ya da desteklenmeyen tipte $null.
.EXAMPLE
  . ./engine/HoleLayout.ps1
  $c = Get-PatternCenters "corner_pattern" 160 100 8
#>

function Get-PatternCenters([string]$Type, [double]$W, [double]$D, [double]$Off) {
  if ([double]$W -le 0 -or [double]$D -le 0 -or [double]$Off -le 0) { return $null }
  if ([string]$Type -eq "corner_pattern") {
    return @(@($Off, $Off), @(([double]$W - $Off), $Off), @($Off, ([double]$D - $Off)), @(([double]$W - $Off), ([double]$D - $Off)))
  } elseif ([string]$Type -eq "mid_edge") {
    return @(@(([double]$W / 2), $Off), @(([double]$W / 2), ([double]$D - $Off)), @($Off, ([double]$D / 2)), @(([double]$W - $Off), ([double]$D / 2)))
  }
  return $null
}
