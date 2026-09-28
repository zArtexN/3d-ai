<#
.SYNOPSIS
  DesignSpec kanonik okuyucu (Adim A, spec_version 2.1).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok; dot-source ile ice
  aktarilir, caller scope kirletmez.
  ConvertTo-CanonicalSpec: eski format (bagimsiz div* component'ler) ile
  yeni format (body.divider_pattern) arasinda okuyucu uyumlulugu.
  - body'de divider_pattern varsa: div* component'ler dusurulur.
  - div* varsa ama pattern yoksa: katlama yapilir (count = div adedi,
    thickness_mm = ilk dolu deger, top_gap_mm = ilk dolu deger ya da 0,
    orientation = along_length, status = thickness biliniyorsa ok).
  - metadata.spec_version pattern varsa "2.1" olur (yoksa degismez).
  Giris nesnesi degistirilmez; yeni nesne doner (idempotent).
.EXAMPLE
  . ./engine/CanonicalSpec.ps1
  $spec = ConvertTo-CanonicalSpec $spec
#>

function ConvertTo-CanonicalSpec($specObj) {
  if ($null -eq $specObj) { return $null }
  $copy = $specObj | ConvertTo-Json -Depth 12 | ConvertFrom-Json
  $comps = @($copy.components | Where-Object { $_ -ne $null })
  if ($comps.Count -eq 0) { return $copy }
  $body = $null
  foreach ($c in $comps) {
    if ($c -and [string]$c.id -eq "body") { $body = $c; break }
  }
  if ($null -eq $body) { $body = $comps[0] }
  $divs = @($comps | Where-Object { $_ -and [string]$_.id -like "div*" })
  $pat = $body.divider_pattern
  if ($null -eq $pat -and $divs.Count -gt 0) {
    $th = $null
    foreach ($d in $divs) {
      if ($null -ne $d.thickness_mm) { $th = [double]$d.thickness_mm; break }
    }
    $gap = 0
    $gapDerived = $true
    foreach ($d in $divs) {
      if ($null -ne $d.top_gap_mm) { $gap = [double]$d.top_gap_mm; $gapDerived = $false; break }
    }
    $st = "missing"
    if ($null -ne $th) { $st = "ok" }
    $pat = [pscustomobject]@{
      count = $divs.Count; thickness_mm = $th; top_gap_mm = $gap; top_gap_derived = $gapDerived
      orientation = "along_length"; status = $st
    }
    $body | Add-Member -NotePropertyName "divider_pattern" -NotePropertyValue $pat -Force
  }
  if ($null -ne $body.divider_pattern) {
    $copy.components = @($comps | Where-Object { $_ -and [string]$_.id -notlike "div*" })
    if ($null -eq $copy.metadata) {
      $copy | Add-Member -NotePropertyName "metadata" -NotePropertyValue ([pscustomobject]@{ spec_version = "2.1" }) -Force
    } else {
      $copy.metadata | Add-Member -NotePropertyName "spec_version" -NotePropertyValue "2.1" -Force
    }
  }
  return $copy
}
