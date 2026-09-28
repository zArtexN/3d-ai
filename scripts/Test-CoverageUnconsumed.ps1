<#
.SYNOPSIS
  Adim D regresyon testi: tuketilmemis sayi ifadeleri UNCONSUMED raporlanir.
.DESCRIPTION
  Issue prompt'unda (duzeltme yokken) 2.5 mm (duvar), 3 mm (taban) ve
  2 mm (bolme kalinligi) UNCONSUMED gorunmeli; triple/delik/cap tuketilmis
  olmali. Rapor bilgi-amaclidir, pipeline status degistirmez.
  Dosya ASCII-only tutulur; prompt [char] ile kurulur.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-CoverageUnconsumed.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-UResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}

$T = [char]0xD7
$O = [char]0xD8
$uu = [char]0xFC
$cc = [char]0xE7
$ii = [char]0x131
$oo = [char]0xF6
$gg = [char]0x11F
$prompt = "160" + $T + "100" + $T + "45 mm kutu, " + $uu + "st" + $uu + " a" + $cc + $ii + "k, " +
  "2.5 mm duvar, 3 mm taban, 2 b" + $oo + "lme 2 mm kal" + $ii + "nl" + $ii + $gg + $ii + "nda, " +
  "4 delik " + $O + "4.2 kenardan 8 mm"

$d = Join-Path ([System.IO.Path]::GetTempPath()) "unc-d"
if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
New-Item -ItemType Directory -Force -Path $d | Out-Null
$specF = Join-Path $d "spec.json"
$factsF = Join-Path $d "facts.json"
$qsF = Join-Path $d "qs.json"
$menF = Join-Path $d "mentions.json"

try {
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName "uncd" -OutPath $specF 2>&1 | Out-Null
  & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $specF -AsJson 2>&1 | Out-String | Set-Content -LiteralPath $qsF -Encoding UTF8
  & (Join-Path $EngineDir "Get-ExplicitFacts.ps1") -Prompt $prompt -OutPath $factsF 2>&1 | Out-Null
  & (Join-Path $EngineDir "Get-NumericMentions.ps1") -Prompt $prompt -OutPath $menF 2>&1 | Out-Null
  $covTxt = & (Join-Path $EngineDir "Test-FactCoverage.ps1") -SpecFile $specF -FactsFile $factsF -QuestionsFile $qsF -MentionsFile $menF -AsJson 2>&1 | Out-String
  $cov = $covTxt | ConvertFrom-Json
  $un = @($cov.unconsumed)
  $fx = @((Get-Content -LiteralPath $factsF -Raw | ConvertFrom-Json).facts)

  # Adim B sonrasi beklenti: duvar/taban/bolme-kalinligi TUKETILMIS olmali.
  $has25 = (@($un | Where-Object { $_ -match "\[measure\]" -and $_ -match "2\.5" }).Count -eq 0)
  $wallFx = (@($fx | Where-Object { [string]$_.property -eq "wall_mm" -and [double]$_.value -eq 2.5 }).Count -gt 0)
  Add-UResult "T-UNC-01" ($has25 -and $wallFx) ("2.5 mm duvar tuketildi (fact=" + $wallFx + ")")
  $has3 = (@($un | Where-Object { $_ -match "\[measure\]" -and $_ -match "\b3 mm" }).Count -eq 0)
  $botFx = (@($fx | Where-Object { [string]$_.property -eq "bottom_thickness_mm" -and [double]$_.value -eq 3 }).Count -gt 0)
  Add-UResult "T-UNC-02" ($has3 -and $botFx) ("3 mm taban tuketildi (fact=" + $botFx + ")")
  $has2 = (@($un | Where-Object { $_ -match "\[measure\]" -and $_ -match "\b2 mm" }).Count -eq 0)
  $thFx = (@($fx | Where-Object { [string]$_.property -eq "thickness_mm" -and [double]$_.value -eq 2 }).Count -gt 0)
  Add-UResult "T-UNC-03" ($has2 -and $thFx) ("2 mm bolme-kalinligi tuketildi (fact=" + $thFx + ")")

  $triFree = (@($un | Where-Object { $_ -match "\[triple\]" }).Count -eq 0)
  Add-UResult "T-UNC-04" $triFree $(if ($triFree) { "triple tuketilmis" } else { "asiri rapor: " + ($un -join "|") })
  $holeFree = (@($un | Where-Object { $_ -match "delik|4\.2|8 mm" }).Count -eq 0)
  Add-UResult "T-UNC-05" $holeFree $(if ($holeFree) { "delik/cap/ofset tuketilmis" } else { "asiri rapor: " + ($un -join "|") })

  $menCount = 0
  try { $menCount = @((Get-Content -LiteralPath $menF -Raw | ConvertFrom-Json).mentions).Count } catch { }
  Add-UResult "T-UNC-06" ($menCount -ge 7) ("mention sayisi=" + $menCount + " (beklenen>=7: triple, 2.5, 3, 2 bolme, 2 mm, 4 delik, O4.2, 8 mm)")
} catch {
  Add-UResult "T-UNC-00" $false $_.Exception.Message
}

Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("UNCONSUMED SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
