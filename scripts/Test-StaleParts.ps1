<#
.SYNOPSIS
  Stale-parca toplama TDD testi (holefix-2).
.DESCRIPTION
  T-SP-01: eski div1.validation.json FAIL icerse bile taze model sonucunu
  etkilemez (parts disi + STALE-SKIP satiri + stale_artifacts listesi).
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-StaleParts.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-SPResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}

$d = Join-Path ([System.IO.Path]::GetTempPath()) "sp-01"
if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
New-Item -ItemType Directory -Force -Path $d | Out-Null
$vd = Join-Path $d "validation"
New-Item -ItemType Directory -Force -Path $vd | Out-Null
@{ status = "FAIL"; part = "div1"; detail_head = "eski model kalintisi" } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $vd "div1.validation.json") -Encoding UTF8

$out = & (Join-Path $EngineDir "Invoke-Pipeline.ps1") -Prompt "60x40x20 kutu, delik 12 merkez 20,20" -ProjectName "sp01" -ProjectDir $d 2>&1 | Out-String
$res = $out | ConvertFrom-Json
$ids = @(@($res.parts) | ForEach-Object { [string]$_.id })
Add-SPResult "T-SP-01a" ([string]$res.status -eq "PASS") ("STATUS=" + $res.status + " (beklenen PASS)")
Add-SPResult "T-SP-01b" ($ids -notcontains "div1") ("parts div1 icermez: " + ($ids -join ","))
Add-SPResult "T-SP-01c" ((@($res.stale_artifacts) -join "|") -match "div1") ("stale_artifacts div1 listeler")
$vlog = ""
if (Test-Path -LiteralPath (Join-Path $d (Join-Path "logs" "validation.log"))) {
  $vlog = Get-Content -LiteralPath (Join-Path $d (Join-Path "logs" "validation.log")) -Raw
}
Add-SPResult "T-SP-01d" ($vlog -match "STALE-SKIP") "validation.log STALE-SKIP satiri"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("STALE SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
