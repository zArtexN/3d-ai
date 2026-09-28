<#
.SYNOPSIS
  Iki yonlu olcu cozumu paylasilan kutuphane (Adim B).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok; dot-source ile ice
  aktarilir, caller scope kirletmez (Adim D dot-source dersi).
  Find-Measure: anahtar kelime + sayi eslesmesi.
  Kurallar:
  - Iki yon: anahtar-kelime-once (forward) ve sayi-once (backward).
  - En yakin kazanir; esitlikte anahtar-kelime-once kazanir (determinizm).
  - Bir mention yalnizca bir anahtar kelimeye atanir: -Claimed kaydi;
    cakisan aday atlanir, kaybeden diger cagrilara kalir.
  - Tam-kelime: (?<!\w)...(?!\w) (taban/tabandan ayrisimi).
  - Cumle-ici pencere: keyword ve sayi ayni cumlede olmali + -Window.
  - Ileri yonde birim sartsiz (baglam yeterli); geri yonde birim ZORUNLU.
  - Birim normalizasyonu tek yerde: ConvertTo-Mm.
  Donus: @{value(mm); raw; span_start; span_length; direction} ya da $null.
.EXAMPLE
  . ./engine/MeasureParser.ps1
  $m = Find-Measure $low 'duvar(?:lar)?[i\u0131]?'
#>

function ConvertTo-Mm($numStr, $unitStr) {
  $v = [double]([string]$numStr -replace ',', '.')
  if ([string]$unitStr -eq "cm") { $v = $v * 10 }
  elseif ([string]$unitStr -ne "" -and [string]$unitStr -ne "mm") { $v = [Math]::Round($v * 25.4, 3) }
  return $v
}

function Find-Measure(
  [string]$Low,
  [string]$KeywordInner,
  [int]$Window = 60,
  [System.Collections.IList]$Claimed = $null,
  [string]$ContextInner = "",
  [int]$ContextWindow = 70,
  [array]$ExcludeSpans = @()
) {
  if ([string]::IsNullOrEmpty($Low) -or [string]::IsNullOrEmpty($KeywordInner)) { return $null }
  $kwRx = '(?<!\w)(?:' + $KeywordInner + ')(?!\w)'
  $numRx = '(?<num>\d+(?:[.,]\d+)?)(?:\s*(?<unit>mm|cm|inch|in[c\u00e7]))?'
  $numGuardPre = '(?<![\w\d.,])'
  $numGuardPost = '(?![\w])'
  $ctxRx = ''
  if ($ContextInner -ne "") { $ctxRx = '(?<!\w)(?:' + $ContextInner + ')(?!\w)' }

  $best = $null; $bestDist = 999999; $bestFwd = $false
  # Cumle bolme: ondalik ayiriciyi bolmez ("2.5" tek parca kalir).
  foreach ($sm in [regex]::Matches($Low, '(?s).+?(?:(?<!\d)[.!?;](?!\d)|[\n\r]|$)')) {
    $stext = $sm.Value; $base = $sm.Index
    $kws = @()
    foreach ($km in [regex]::Matches($stext, $kwRx)) {
      $kAbs = $base + $km.Index
      if ($ctxRx -ne "") {
        $ctxOk = $false
        foreach ($cm in [regex]::Matches($Low, $ctxRx)) {
          if ([Math]::Abs($cm.Index - $kAbs) -le $ContextWindow) { $ctxOk = $true; break }
        }
        if (-not $ctxOk) { continue }
      }
      $kws += @{ s = $kAbs; e = ($kAbs + $km.Length) }
    }
    if ($kws.Count -eq 0) { continue }
    $toks = @()
    foreach ($nm in [regex]::Matches($stext, ($numGuardPre + $numRx + $numGuardPost))) {
      $tAbs = $base + $nm.Index; $tEnd = $tAbs + $nm.Length
      $skip = $false
      foreach ($ex in $ExcludeSpans) {
        if ($null -eq $ex) { continue }
        $xs = $ex.s; $xe = $ex.e
        if ($null -eq $xs -and $null -ne $ex.index) { $xs = $ex.index; $xe = ($ex.index + $ex.length) }
        if ($null -eq $xs -or $null -eq $xe) { continue }
        if ($tAbs -lt $xe -and $xs -lt $tEnd) { $skip = $true; break }
      }
      if ($skip) { continue }
      if ($null -ne $Claimed) {
        foreach ($cl in $Claimed) {
          if ($tAbs -lt $cl.e -and $cl.s -lt $tEnd) { $skip = $true; break }
        }
      }
      if ($skip) { continue }
      $hasUnit = ($nm.Groups["unit"].Success -and $nm.Groups["unit"].Value -ne "")
      $toks += @{ s = $tAbs; e = $tEnd; raw = $nm.Value.Trim(); num = $nm.Groups["num"].Value; unit = $(if ($hasUnit) { $nm.Groups["unit"].Value } else { "" }); hasUnit = $hasUnit }
    }
    foreach ($kw in $kws) {
      foreach ($tk in $toks) {
        # forward: keyword-once (birim sartsiz).
        if ($tk.s -ge $kw.e) {
          $d = $tk.s - $kw.e
          if ($d -le $Window) {
            if ($d -lt $bestDist -or ($d -eq $bestDist -and -not $bestFwd)) {
              $bestDist = $d; $bestFwd = $true
              $best = @{ value = (ConvertTo-Mm $tk.num $tk.unit); raw = $tk.raw; span_start = $tk.s; span_length = ($tk.e - $tk.s); direction = "forward" }
            }
          }
        }
        # backward: sayi-once (birim ZORUNLU).
        if ($tk.e -le $kw.s -and $tk.hasUnit) {
          $d = $kw.s - $tk.e
          if ($d -le $Window) {
            if ($d -lt $bestDist) {
              $bestDist = $d; $bestFwd = $false
              $best = @{ value = (ConvertTo-Mm $tk.num $tk.unit); raw = $tk.raw; span_start = $tk.s; span_length = ($tk.e - $tk.s); direction = "backward" }
            }
          }
        }
      }
    }
  }
  if ($null -ne $best -and $null -ne $Claimed) {
    $Claimed.Add(@{ s = $best.span_start; e = ($best.span_start + $best.span_length) }) | Out-Null
  }
  if ($null -eq $best) { return $null }
  return ([pscustomobject]$best)
}
