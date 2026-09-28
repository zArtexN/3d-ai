<#
.SYNOPSIS
  Negative-intent TDD testleri (istenmeyen feature uretilmemeli).
.DESCRIPTION
  T-LID-NEGATIVE-01..05 | T-HOLE-NEGATIVE-01..07 (07: ciplak kenardan).
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-NegativeIntent.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-NEGResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-NEGDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("neg-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function Get-NEGParse($prompt, $tag) {
  $d = New-NEGDir $tag
  $sf = Join-Path $d "spec.json"
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $sf 2>&1 | Out-Null
  $spec = Get-Content -LiteralPath $sf -Raw | ConvertFrom-Json
  $qs = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $sf -AsJson 2>&1 | Out-String | ConvertFrom-Json
  return @{ spec = $spec; qs = @($qs | Where-Object { $_ -ne $null }); dir = $d }
}
function Get-Comps($spec) { return @(@($spec.components) | ForEach-Object { [string]$_.id }) }
function Get-LidQs($qs) {
  return @($qs | Where-Object { [string]$_.component -eq "lid" -or [string]$_.target -like "lid.*" })
}
function Get-HoleQs($qs) {
  return @($qs | Where-Object { [string]$_.kind -like "hole_*" })
}

# T-LID-NEGATIVE-01: acik ret -> lid yok.
$r = Get-NEGParse "80x40x20 kutu, kapak istemiyorum" "nlid01"
Add-NEGResult "T-LID-NEGATIVE-01" ((Get-Comps $r.spec) -notcontains "lid") "kapak istemiyorum -> lid yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-LID-NEGATIVE-02: bahsedilmemis -> lid yok.
$r = Get-NEGParse "80x40x20 kutu" "nlid02"
Add-NEGResult "T-LID-NEGATIVE-02" ((Get-Comps $r.spec) -notcontains "lid") "lid bahsi yok -> lid yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-LID-NEGATIVE-03: lid yokken lid sorusu yok.
$r = Get-NEGParse "80x40x20 kutu, kapak istemiyorum" "nlid03"
Add-NEGResult "T-LID-NEGATIVE-03" ((Get-LidQs $r.qs).Count -eq 0) "lid sorusu yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-LID-NEGATIVE-04: lid geometrisi uretilmez.
$r = Get-NEGParse "80x40x20 kutu, kapak istemiyorum" "nlid04"
$d = $r.dir
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile (Join-Path $d "spec.json") -ProjectDir $d 2>&1 | Out-Null
$lidStl = Test-Path -LiteralPath (Join-Path $d (Join-Path "output" "lid.stl"))
$lidVal = Test-Path -LiteralPath (Join-Path $d (Join-Path "validation" "lid.validation.json"))
Add-NEGResult "T-LID-NEGATIVE-04" ((-not $lidStl) -and (-not $lidVal)) "lid STL/validation yok"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
# T-LID-NEGATIVE-05: lid yokken clearance sorusu yok.
$r = Get-NEGParse "80x40x20 kutu, kapak istemiyorum" "nlid05"
$clrQ = @($r.qs | Where-Object { ([string]$_.kind -eq "clearance" -or [string]$_.kind -eq "joint_clearance") -and [string]$_.component -eq "lid" })
Add-NEGResult "T-LID-NEGATIVE-05" ($clrQ.Count -eq 0) "lid clearance sorusu yok"
$dis = @($r.spec.disabled_features)
Add-NEGResult "T-LID-NEGATIVE-06" ($dis -contains "lid") "disabled_features lid korur"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-HOLE-NEGATIVE-01: delik bahsi yok -> delik yok.
$r = Get-NEGParse "80x40x20 kutu" "nhole01"
$hs = @(@($r.spec.components[0].holes) | Where-Object { $_ -ne $null })
Add-NEGResult "T-HOLE-NEGATIVE-01" ($hs.Count -eq 0) "delik bahsi yok -> delik yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-HOLE-NEGATIVE-02: acik ret -> delik yok.
$r = Get-NEGParse "80x40x20 kutu, delik istemiyorum" "nhole02"
$hs = @(@($r.spec.components[0].holes) | Where-Object { $_ -ne $null })
Add-NEGResult "T-HOLE-NEGATIVE-02" ($hs.Count -eq 0) "delik istemiyorum -> delik yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-HOLE-NEGATIVE-03: delik yokken delik sorusu yok.
$r = Get-NEGParse "80x40x20 kutu, delik istemiyorum" "nhole03"
Add-NEGResult "T-HOLE-NEGATIVE-03" ((Get-HoleQs $r.qs).Count -eq 0) "delik sorusu yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-HOLE-NEGATIVE-04: h1 default yok.
$r = Get-NEGParse "80x40x20 kutu, delik istemiyorum" "nhole04"
$ids = @(@($r.spec.components[0].holes) | Where-Object { $_ -ne $null } | ForEach-Object { [string]$_.id })
Add-NEGResult "T-HOLE-NEGATIVE-04" ($ids -notcontains "h1") "h1 uretilmedi"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-HOLE-NEGATIVE-05: taze spec tasima yapmaz.
$r = Get-NEGParse "80x40x20 kutu" "nhole05"
$hs = @(@($r.spec.components[0].holes) | Where-Object { $_ -ne $null })
Add-NEGResult "T-HOLE-NEGATIVE-05" ($hs.Count -eq 0) "stale delik yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-HOLE-NEGATIVE-06: acik niyet delik uretir (asiri bloklama yok).
$r = Get-NEGParse "80x40x20 kutu, delik 10 merkez 15,15" "nhole06"
$hs = @(@($r.spec.components[0].holes) | Where-Object { $_ -ne $null })
Add-NEGResult "T-HOLE-NEGATIVE-06" (($hs.Count -eq 1) -and ([string]$hs[0].status -eq "ok")) "acik niyet delik uretir"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-HOLE-NEGATIVE-07: ciplak kenardan delik kaniti degildir.
$r = Get-NEGParse "80x40x20 kutu, kenardan 8 mm bosluk birak" "nhole07"
$hs = @(@($r.spec.components[0].holes) | Where-Object { $_ -ne $null })
Add-NEGResult "T-HOLE-NEGATIVE-07" ($hs.Count -eq 0) "ciplak kenardan -> delik yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-NEG-SLOT-01: acik ret -> kesik yok.
$r = Get-NEGParse "80x40x20 kutu, slot istemiyorum" "nslot01"
$cs = @(@($r.spec.components[0].cutouts) | Where-Object { $_ -ne $null })
Add-NEGResult "T-NEG-SLOT-01" ($cs.Count -eq 0) "slot istemiyorum -> kesik yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue
# T-NEG-FILLET-01: acik ret -> fillet notu yok.
$r = Get-NEGParse "80x40x20 kutu, koseleri yuvarlatma" "nfil01"
$en = @(@($r.spec.components[0].edge_notes) | Where-Object { $_ -and [string]$_.kind -eq "fillet" })
Add-NEGResult "T-NEG-FILLET-01" ($en.Count -eq 0) "yuvarlatma -> fillet yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("NEGATIVE SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
