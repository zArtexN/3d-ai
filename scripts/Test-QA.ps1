<#
.SYNOPSIS
  Q&A cevap parser testleri (dogal cevaplar kabul, muglak/gecersiz red).
.DESCRIPTION
  T-QA-01 dia "10" -> PASS | T-QA-02 "10 mm" -> PASS | T-QA-03 "O10" -> PASS
  T-QA-04 center "15,15" -> PASS | T-QA-05 tolerance "0.2 mm" -> PASS
  T-QA-06 "biraz"/bos -> red (tekrar soru sinyali) | T-QA-07 "-5" -> red | T-QA-08 "0" -> red
  T-QA-09 center "15 15" (bosluklu) -> PASS | T-QA-10 stabil ID ile tekrar cevap -> PASS
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-QA.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-QAResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-QAHole($id, $dia, $cx, $cy, $st) {
  return [pscustomobject]@{
    id = $id; hole_type = "through"; diameter_mm = $dia
    center_x_mm = $cx; center_y_mm = $cy; axis = "z"
    depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null
    screw = $null; status = $st
  }
}
function New-QABody($holes, $tol) {
  return [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 60; depth_mm = 40; height_mm = 20 }
    hollow = $null; holes = $holes; cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $tol; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
  }
}
function New-QASpec($dir, $name, $comp) {
  $spec = [pscustomobject]@{
    project_name = $name; prompt = $name
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    components = @($comp); assembly = $null; material = $null
  }
  $sp = Join-Path $dir "spec.json"
  $spec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sp -Encoding UTF8
  $qsTxt = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $sp -AsJson 2>&1 | Out-String
  $qsObj = $qsTxt | ConvertFrom-Json
  $qf = Join-Path $dir "spec.questions.json"
  if ($null -eq $qsObj) { "[]" | Set-Content -LiteralPath $qf -Encoding UTF8 }
  else { @($qsObj) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qf -Encoding UTF8 }
  return $sp
}
function Invoke-QAAnswer($sp, $qid, $ans) {
  try {
    & (Join-Path $EngineDir "Update-SpecAnswer.ps1") -SpecFile $sp -QuestionId $qid -Answer $ans 2>&1 | Out-Null
    return @{ applied = $true; error = "" }
  } catch {
    return @{ applied = $false; error = [string]$_.Exception.Message }
  }
}
function New-QADir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("qa-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}

$diaId = "body-hole-h1-dia"
$cenId = "body-hole-h1-center"
$tolId = "body-clearance"

# T-QA-01/02/03: dogal cap cevaplari
foreach ($case in @(@("T-QA-01", "10"), @("T-QA-02", "10 mm"), @("T-QA-03", "Ø10"), @("T-QA-03b", "cap 10")) ) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
    $r = Invoke-QAAnswer $sp $diaId $case[1]
    $v = -1
    if ($r.applied) { $v = [double](Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0].diameter_mm }
    $ok = ($r.applied -and $v -eq 10)
    Add-QAResult $case[0] $ok $(if ($ok) { "cap=10 islendi" } else { "hata: $($r.error)" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-04: merkez
$d = New-QADir "T-QA-04"
try {
  $sp = New-QASpec $d "T-QA-04" (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
  $r = Invoke-QAAnswer $sp $cenId "15,15"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r.applied -and [double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15)
  Add-QAResult "T-QA-04" $ok $(if ($ok) { "merkez 15,15" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-04" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-05: tolerans
$d = New-QADir "T-QA-05"
try {
  $tol = [pscustomobject]@{ type = "clearance"; clearance_mm = $null; fit_to = $null; status = "missing" }
  $sp = New-QASpec $d "T-QA-05" (New-QABody @() $tol)
  $r = Invoke-QAAnswer $sp $tolId "0.2 mm"
  $v = -1
  if ($r.applied) { $v = [double](Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].tolerance.clearance_mm }
  $ok = ($r.applied -and $v -eq 0.2)
  Add-QAResult "T-QA-05" $ok $(if ($ok) { "tolerans 0.2" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-05" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-06: muglak + bos -> red
$d = New-QADir "T-QA-06"
try {
  $sp = New-QASpec $d "T-QA-06" (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
  $r1 = Invoke-QAAnswer $sp $diaId "biraz"
  $r2 = Invoke-QAAnswer $sp $diaId ""
  $ok = ((-not $r1.applied) -and (-not $r2.applied))
  Add-QAResult "T-QA-06" $ok $(if ($ok) { "muglak/bos reddedildi" } else { "yanlis kabul!" })
} catch { Add-QAResult "T-QA-06" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-07/08: negatif + sifir -> red
foreach ($case in @(@("T-QA-07", "-5"), @("T-QA-08", "0"))) {
  $d = New-QADir $case[0]
  try {
    $sp = New-QASpec $d $case[0] (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
    $r = Invoke-QAAnswer $sp $diaId $case[1]
    $ok = (-not $r.applied)
    Add-QAResult $case[0] $ok $(if ($ok) { "gecersiz red: $($r.error)" } else { "yanlis kabul!" })
  } catch { Add-QAResult $case[0] $false $_.Exception.Message }
  finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
}

# T-QA-09: bosluklu cift
$d = New-QADir "T-QA-09"
try {
  $sp = New-QASpec $d "T-QA-09" (New-QABody @((New-QAHole "h1" 10 $null $null "missing")) $null)
  $r = Invoke-QAAnswer $sp $cenId "15 15"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r.applied -and [double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15)
  Add-QAResult "T-QA-09" $ok $(if ($ok) { "bosluklu cift kabul" } else { "hata: $($r.error)" })
} catch { Add-QAResult "T-QA-09" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

# T-QA-10: stabil ID ile cift cevap (once yanlis sira riski yok)
$d = New-QADir "T-QA-10"
try {
  $sp = New-QASpec $d "T-QA-10" (New-QABody @((New-QAHole "h1" $null $null $null "missing")) $null)
  $r1 = Invoke-QAAnswer $sp $diaId "12"
  $r2 = Invoke-QAAnswer $sp $cenId "20,20"
  $h = (Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json).components[0].holes[0]
  $ok = ($r1.applied -and $r2.applied -and [double]$h.diameter_mm -eq 12 -and [double]$h.center_x_mm -eq 20)
  Add-QAResult "T-QA-10" $ok $(if ($ok) { "sirali cevaplar dogru alanlara" } else { "karisti" })
} catch { Add-QAResult "T-QA-10" $false $_.Exception.Message }
finally { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "QA SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
