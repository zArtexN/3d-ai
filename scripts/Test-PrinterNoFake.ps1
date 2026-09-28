<#
.SYNOPSIS
  No-fake-printer regression testleri (UI/printer/engine/slice/gcode).
.DESCRIPTION
  T-PR-01 validation printersiz calisir | T-PR-02 printersiz geometri |
  T-PR-03 printersiz min-karsilastirma yok | T-PR-04 generic-fdm gercek sayilmaz |
  T-PR-05 UI bos deger uydurmaz (statik bekci) | T-PR-06 template null alanlar |
  T-PR-07 slicing printersiz BLOCKED | T-PR-08 gcode printersiz BLOCKED.
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-PrinterNoFake.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-PRResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-PRDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("pr-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-PRSpec($tag) {
  $d = New-PRDir $tag
  $body = [pscustomobject]@{
    id = "body"; label = "body"
    base = [pscustomobject]@{ shape = "box"; width_mm = 60; depth_mm = 40; height_mm = 20 }
    hollow = [pscustomobject]@{ wall_mm = 2; open_top = $true; bottom_thickness_mm = $null }
    holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
    tolerance = $null; expected_bbox = $null
  }
  $sp = [pscustomobject]@{ project_name = $tag; prompt = $tag; metadata = [pscustomobject]@{ spec_version = "2.1" }; components = @($body); assembly = $null; material = $null }
  $sf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
  return @{ dir = $d; file = $sf }
}

# T-PR-01: printersiz validation calisir (hata yok; limit karsilastirmasi yok).
$r = New-PRSpec "pr01"
$g1 = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile $r.file -AsJson 2>&1 | Out-String | ConvertFrom-Json
$noLimitWarn = $true
foreach ($w in @($g1.warnings)) {
  if ([string]$w -match "limit \d") { $noLimitWarn = $false }
}
Add-PRResult "T-PR-01" ((@($g1.errors).Count -eq 0) -and $noLimitWarn) "printersiz validation hatasiz, limit karsilastirmasi yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PR-02: printersiz geometri uretilebilir.
$r = New-PRSpec "pr02"
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $r.file -ProjectDir $r.dir 2>&1 | Out-Null
$stlOk = Test-Path -LiteralPath (Join-Path $r.dir (Join-Path "output" "body.stl"))
Add-PRResult "T-PR-02" $stlOk "printersiz STL uretildi"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PR-03: printersiz min wall/hole/feature karsilastirmasi yapilmaz.
$r = New-PRSpec "pr03"
$g3 = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile $r.file -AsJson 2>&1 | Out-String | ConvertFrom-Json
$hasMinCmp = $false
foreach ($w in @($g3.warnings)) {
  if ([string]$w -match "min delik \d|limit \d") { $hasMinCmp = $true }
}
Add-PRResult "T-PR-03" (-not $hasMinCmp) "min karsilastirma uyarisi yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PR-04: generic-fdm gercek printer kabul edilmez.
$r = New-PRSpec "pr04"
& (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $r.file -ProjectDir $r.dir -Printer "generic-fdm" 2>&1 | Out-Null
$vp = Join-Path $r.dir (Join-Path "validation" "body.validation.json")
$vv = $null
if (Test-Path -LiteralPath $vp) { $vv = Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json }
Add-PRResult "T-PR-04" (($null -ne $vv) -and ([string]$vv.printer -ne "generic-fdm")) "template printer sayilmadi"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-PR-05: UI kayit blogu bos degeri uydurmaz (statik bekci).
$ui = Get-Content -LiteralPath (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -Raw
$noFakeNz = ($ui -notmatch '\$nz = 0\.4')
$noDerive = ($ui -notmatch 'min_wall_mm = \[math\]::Round\(\$nz')
$hasNulls = ($ui -match 'min_wall_mm = \$null' -and $ui -match 'max_overhang_deg = \$null' -and $ui -match 'nozzle_mm = \$nz')
Add-PRResult "T-PR-05" ($noFakeNz -and $noDerive -and $hasNulls) "UI sahte default uretmiyor"

# T-PR-06: template tum kritik alanlarda null.
$pj = Get-Content -LiteralPath (Join-Path $Root (Join-Path "printers" "generic-fdm.json")) -Raw | ConvertFrom-Json
Add-PRResult "T-PR-06" (($null -eq $pj.nozzle_mm) -and ($null -eq $pj.bed_mm) -and ($null -eq $pj.min_wall_mm) -and ($null -eq $pj.min_feature_mm) -and ($null -eq $pj.min_hole_mm) -and ($null -eq $pj.max_overhang_deg) -and ($pj.usable_for_slicing -eq $false)) "template null + slicable=false"

# T-PR-07: slicing printersiz BLOCKED.
$d = New-PRDir "pr07"
$fake3mf = Join-Path $d "model.3mf"
"dummy" | Set-Content -LiteralPath $fake3mf -Encoding UTF8
$fakeExe = Join-Path $d "orca.exe"
"dummy" | Set-Content -LiteralPath $fakeExe -Encoding UTF8
$blk = $false
try {
  & (Join-Path $Root (Join-Path "scripts" "Slice.ps1")) -Input3mf $fake3mf -PrinterProfile "REPLACE_WITH_ORCA_PRINTER_PROFILE_NAME" -FilamentProfile "Generic PLA" -OutDir (Join-Path $d "slice") -OrcaExe $fakeExe 2>&1 | Out-Null
} catch {
  if ([string]$_.Exception.Message -match "^BLOCKED") { $blk = $true }
}
Add-PRResult "T-PR-07" $blk "placeholder ile slice BLOCKED"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

# T-PR-08: gcode printersiz BLOCKED (kucuk tam pipeline).
$d = New-PRDir "pr08"
$out = & (Join-Path $EngineDir "Invoke-Pipeline.ps1") -Prompt "40x30x10 kutu" -ProjectName "pr08" -ProjectDir $d 2>&1 | Out-String
$res = $out | ConvertFrom-Json
Add-PRResult "T-PR-08" (([string]$res.status -eq "PASS") -and ($res.gcode_available -eq $false) -and ([string]$res.gcode_note -match "printer profile required")) "gcode yok + not korunur"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("PRINTER SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
