<#
.SYNOPSIS
  Ham prompt'taki sayi ifadelerini (mention) cikaran bagimsiz adim (Adim D).
.DESCRIPTION
  Turler: triple (160x100x45), pair (20x10), diameter (O4.2),
  measure (2.5 mm), count (2 bolme / 4 delik / 3 adet / 4 montaj noktasi).
  Olcu olmayan sayilar elenir: 3MF, M4, STL/G-code baglami, derece.
  Her mention: id (m1..), kind, raw, span_start, span_length, value, unit.
  Deger UYDURMAZ; sadece ham metni listeler. Tuketim karari coverage'indir
  (Test-FactCoverage UNCONSUMED sinifi).
  Dosya ASCII-only tutulur (not: PS 5.1 BOM'suz dosyalari 1254 okur);
  Turkce harfler regex icinde \uXXXX ile yazilir.
.EXAMPLE
  powershell -File engine\Get-NumericMentions.ps1 -Prompt "160x100x45 mm kutu" -AsJson
#>
param(
  [string]$Prompt = "",
  [string]$OutPath = "",
  [switch]$AsJson
)

$ErrorActionPreference = "Stop"

function Get-MNum($s) { return [double]([string]$s -replace ',', '.') }

function Test-SpanFree($taken, $s, $e) {
  # Not: dolu Generic.List uzerinde @() PS 5.1'de patlar; direkt dongu kullanilir.
  foreach ($t in $taken) { if ($s -lt $t.e -and $t.s -lt $e) { return $false } }
  return $true
}

function Add-Mention($list, $taken, $kind, $idx, $len, $raw, $val, $unit) {
  if (-not (Test-SpanFree $taken $idx ($idx + $len))) { return }
  $taken.Add(@{ s = $idx; e = ($idx + $len) }) | Out-Null
  $list.Add([pscustomobject]@{
    id = ("m" + ($list.Count + 1)); kind = $kind
    raw = $raw; span_start = $idx; span_length = $len
    value = $val; unit = $unit
  }) | Out-Null
}

function Get-Mentions([string]$RawPrompt) {
  $low = $RawPrompt.ToLowerInvariant() -replace ([char]0x307), ""
  $list = New-Object System.Collections.Generic.List[object]
  $taken = New-Object System.Collections.Generic.List[object]
  $sepRx = '(?:[xX\*\u00d7\u2715\u2716\u2a2f]|[c\u00e7]arp[i\u0131])'
  $numRx = '(\d+(?:[.,]\d+)?)'

  # 1) triple: govde olcusu adayi (icindeki ikililer/sayilar ayri mention olmaz).
  $triplePat = $numRx + '\s*(?:mm\s*)?' + $sepRx + '\s*' + $numRx + '\s*(?:mm\s*)?' + $sepRx + '\s*' + $numRx
  foreach ($m in [regex]::Matches($low, $triplePat)) {
    $v = @((Get-MNum $m.Groups[1].Value), (Get-MNum $m.Groups[2].Value), (Get-MNum $m.Groups[3].Value))
    Add-Mention $list $taken "triple" $m.Index $m.Length $m.Value.Trim() $v "mm"
  }
  # 2) pair: kesik/temas olcusu adayi (uclunun parcasi olamaz; virgul ondalik sayilir, ayirac degil).
  $pairPat = $numRx + '\s*(?:mm\s*)?' + $sepRx + '\s*' + $numRx + '(?!\s*(?:mm\s*)?' + $sepRx + '\s*\d)'
  foreach ($m in [regex]::Matches($low, $pairPat)) {
    $v = @((Get-MNum $m.Groups[1].Value), (Get-MNum $m.Groups[2].Value))
    Add-Mention $list $taken "pair" $m.Index $m.Length $m.Value.Trim() $v "mm"
  }
  # 3) diameter: cap isareti + sayi.
  foreach ($m in [regex]::Matches($low, '[\u00d8\u00f8]\s*' + $numRx)) {
    Add-Mention $list $taken "diameter" $m.Index $m.Length $m.Value.Trim() (Get-MNum $m.Groups[1].Value) "mm"
  }
  # 4) measure: sayi + birim (cm/inch mm'ye cevrilir; parser ile ayni kural).
  #    Elenir: harfe yapisik sayi (3MF, M4mm gibi), birimsiz sayi.
  foreach ($m in [regex]::Matches($low, ($numRx + '\s*(mm|cm|inch|in[c\u00e7])\b'))) {
    if ($m.Index -gt 0 -and [regex]::IsMatch($low.Substring($m.Index - 1, 1), '[A-Za-z]')) { continue }
    $v = Get-MNum $m.Groups[1].Value
    $u = "mm"
    if ($m.Groups[2].Value -eq "cm") { $v = $v * 10 }
    elseif ($m.Groups[2].Value -ne "mm") { $v = [Math]::Round($v * 25.4, 3) }
    Add-Mention $list $taken "measure" $m.Index $m.Length $m.Value.Trim() $v $u
  }
  # 5) count: sayi + ozellik ismi (bitisik; uzak baglam sayilmaz).
  $nounRx = '((?:kapak\s+)?montaj\snokta\w*|b[o\u00f6]lme\w*|deli[k\u011f]\w*|par[c\u00e7]a\w*|kesik|slot|kanal|temas\w*|kapak|adet)'
  foreach ($m in [regex]::Matches($low, ('(\d+)\s*' + $nounRx))) {
    if ($m.Index -gt 0 -and [regex]::IsMatch($low.Substring($m.Index - 1, 1), '[A-Za-z0-9]')) { continue }
    Add-Mention $list $taken "count" $m.Index $m.Length $m.Value.Trim() ([int]$m.Groups[1].Value) "adet"
  }
  return @($list.ToArray() | Sort-Object { $_.span_start })
}

if ($MyInvocation.InvocationName -ne '.') {
  if ([string]::IsNullOrEmpty($Prompt)) { throw "Prompt gerekli." }
  $ms = @(Get-Mentions $Prompt)
  if ($OutPath -ne "") {
    $dir = Split-Path -Parent $OutPath
    if ($dir -ne "" -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    (@{ mentions = @($ms) } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath $OutPath -Encoding UTF8
    Write-Output ("MENTIONS: $OutPath (" + $ms.Count + " mention)")
  }
  if ($AsJson -or $OutPath -eq "") { @($ms) | ConvertTo-Json -Depth 5 }
}
