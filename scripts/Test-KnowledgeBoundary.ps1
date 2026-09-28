<#
.SYNOPSIS
  Knowledge-boundary leakage testleri (reference vs profil).
.DESCRIPTION
  T-KB-01 template null kritikler | T-KB-02 slicer knowledge okumaz |
  T-KB-03 UI kayit knowledge cekmez | T-KB-04/05 printersiz/template NEEDS_INPUT |
  T-KB-06 estimate sicaklik/hiz uretmez | T-KB-07 requires_printer_profile bayragi |
  T-KB-08 troubleshooting uygulanmaz | T-KB-09 provenance mevcut |
  T-KB-10 sicaklik araliklari tuketilmez.
  Dosya ASCII-only. Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-KnowledgeBoundary.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Add-KBResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function New-KBDir($tag) {
  $d = Join-Path ([System.IO.Path]::GetTempPath()) ("kb-" + $tag)
  if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  return $d
}
function New-KBSpec($tag) {
  $d = New-KBDir $tag
  $sp = [pscustomobject]@{
    project_name = $tag; prompt = $tag; metadata = [pscustomobject]@{ spec_version = "2.1" }
    components = @([pscustomobject]@{
      id = "body"; label = "body"
      base = [pscustomobject]@{ shape = "box"; width_mm = 50; depth_mm = 50; height_mm = 10 }
      hollow = [pscustomobject]@{ wall_mm = 2; open_top = $false; bottom_thickness_mm = $null }
      holes = @([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = 10; center_x_mm = 25; center_y_mm = 25; axis = "z"; depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null; screw = $null; status = "ok" })
      cutouts = @(); edge_notes = @(); transforms = @(); tolerance = $null
    })
    assembly = $null; material = "PLA"
  }
  $sf = Join-Path $d "spec.json"
  $sp | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sf -Encoding UTF8
  return @{ dir = $d; file = $sf }
}

# T-KB-01: template profillerde kritik alanlar null.
$tplOk = $true; $tplN = 0
foreach ($pf in (Get-ChildItem -LiteralPath (Join-Path $Root "printers") -Filter "*.json")) {
  $pj = Get-Content -LiteralPath $pf.FullName -Raw | ConvertFrom-Json
  if ([string]$pj.source -eq "template") {
    $tplN++
    if ($null -ne $pj.nozzle_mm -or $null -ne $pj.bed_mm -or $null -ne $pj.min_wall_mm -or $null -ne $pj.min_feature_mm -or $null -ne $pj.min_hole_mm -or $null -ne $pj.max_overhang_deg) { $tplOk = $false }
    if ($pj.usable_for_slicing -ne $false) { $tplOk = $false }
  }
}
Add-KBResult "T-KB-01" ($tplOk -and $tplN -gt 0) ("template dosya=" + $tplN + ", kritikler null")

# T-KB-02: slicer yolu knowledge okumaz.
$sliceTxt = Get-Content -LiteralPath (Join-Path $Root (Join-Path "scripts" "Slice.ps1")) -Raw
$invSliceTxt = Get-Content -LiteralPath (Join-Path $EngineDir "Invoke-Slicer.ps1") -Raw
$expTxt = Get-Content -LiteralPath (Join-Path $Root (Join-Path "scripts" "Export-Stl.ps1")) -Raw
Add-KBResult "T-KB-02" (($sliceTxt -notmatch "knowledge") -and ($invSliceTxt -notmatch "knowledge") -and ($expTxt -notmatch "knowledge")) "slicer knowledge referansi yok"

# T-KB-03: UI printer-kayit blogu knowledge cekmez.
$ui = Get-Content -LiteralPath (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -Raw
$i0 = $ui.IndexOf("YAZICI KAYDET")
$i1 = $ui.IndexOf("FILAMENT OLAYLARI")
$saveRegion = ""
if ($i0 -ge 0 -and $i1 -gt $i0) { $saveRegion = $ui.Substring($i0, ($i1 - $i0)) }
Add-KBResult "T-KB-03" ($saveRegion -ne "" -and ($saveRegion -notmatch "knowledge")) "kayit blogu knowledge bagimsiz"

# T-KB-04: printersiz analiz NEEDS_INPUT (uydurma limit yok).
$r = New-KBSpec "kb04"
$pa = & (Join-Path $EngineDir "Analyze-Printability.ps1") -SpecFile $r.file -AsJson 2>&1 | Out-String | ConvertFrom-Json
$mw = @(@($pa.checks) | Where-Object { [string]$_.id -eq "min_wall" })
$mwOk = ($mw.Count -gt 0 -and [string]$mw[0].status -eq "NEEDS_INPUT")
Add-KBResult "T-KB-04" $mwOk "printersiz min_wall NEEDS_INPUT"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-KB-05: template profil gercek sayilmaz (ayni NEEDS_INPUT).
$r = New-KBSpec "kb05"
$pf = Join-Path $Root (Join-Path "printers" "generic-fdm.json")
$pa = & (Join-Path $EngineDir "Analyze-Printability.ps1") -SpecFile $r.file -PrinterFile $pf -AsJson 2>&1 | Out-String | ConvertFrom-Json
$mw = @(@($pa.checks) | Where-Object { [string]$_.id -eq "min_wall" })
Add-KBResult "T-KB-05" ($mw.Count -gt 0 -and [string]$mw[0].status -eq "NEEDS_INPUT") "template ile min_wall NEEDS_INPUT"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-KB-06: estimate sicaklik/hiz/nozul/tabla uretmez.
$r = New-KBSpec "kb06"
$es = & (Join-Path $EngineDir "Estimate-Print.ps1") -SpecFile $r.file -AsJson 2>&1 | Out-String | ConvertFrom-Json
$esKeys = @()
foreach ($pn in @($es.PSObject.Properties)) { $esKeys += [string]$pn.Name }
$badKeys = @("nozzle_temp_c", "bed_temp_c", "print_speed_mm_s", "layer_height_mm", "nozzle_diameter_mm", "bed_size_mm", "acceleration_mm_s2", "flow_rate", "nozzle_temp_range_c", "bed_temp_range_c")
$keyHit = $false
foreach ($bk in $badKeys) { if ($esKeys -contains $bk) { $keyHit = $true } }
Add-KBResult "T-KB-06" ((-not $keyHit) -and [string]$es.print_time -eq "ESTIMATE_UNAVAILABLE") "estimate slicer parametresi yok"
Remove-Item -LiteralPath $r.dir -Recurse -Force -ErrorAction SilentlyContinue

# T-KB-07: troubleshooting bayraklari tam.
$tr = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "troubleshooting.json")) -Raw | ConvertFrom-Json
$flagOk = (@($tr).Count -gt 0)
foreach ($t in @($tr)) {
  if ($null -eq $t.requires_printer_profile -or ($t.requires_printer_profile -ne $true -and $t.requires_printer_profile -ne $false)) { $flagOk = $false }
}
Add-KBResult "T-KB-07" $flagOk "requires_printer_profile tum kayitlarda boolean"

# T-KB-08: troubleshooting cozumleri engine/scripts tarafindan uygulanmaz.
# (varlik gecerliligi testleri sayilmaz.)
$tbRefs = @()
foreach ($f in (Get-ChildItem -LiteralPath $EngineDir -Filter "*.ps1")) {
  $hit = Select-String -LiteralPath $f.FullName -Pattern "troubleshooting" -SimpleMatch -ErrorAction SilentlyContinue
  if ($null -ne $hit) { $tbRefs += $f.Name }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1")) {
  if ([string]$f.Name -eq "Test-KnowledgeBoundary.ps1" -or [string]$f.Name -eq "Run-PrintTests.ps1") { continue }
  $hit = Select-String -LiteralPath $f.FullName -Pattern "troubleshooting" -SimpleMatch -ErrorAction SilentlyContinue
  if ($null -ne $hit) { $tbRefs += $f.Name }
}
Add-KBResult "T-KB-08" (@($tbRefs).Count -eq 0) ("engine/scripts uygulamiyor: " + ($tbRefs -join ","))

# T-KB-09: provenance tum knowledge dosyalarinda mevcut.
$gl = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "printing-guidelines.json")) -Raw | ConvertFrom-Json
$mats = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "materials.json")) -Raw | ConvertFrom-Json
$fits = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "fits.json")) -Raw | ConvertFrom-Json
$thrs = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "threads.json")) -Raw | ConvertFrom-Json
$inss = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "heat-set-inserts.json")) -Raw | ConvertFrom-Json
$trs = Get-Content -LiteralPath (Join-Path $Root (Join-Path "knowledge" "troubleshooting.json")) -Raw | ConvertFrom-Json
$provOk = ($null -ne $gl._provenance -and $gl._provenance.may_drive_gcode -eq $false)
foreach ($m in @($mats)) { if ($null -eq $m.provenance -or $m.provenance.may_drive_gcode -ne $false) { $provOk = $false } }
foreach ($f in @($fits)) { if ($null -eq $f.provenance -or $f.provenance.may_drive_gcode -ne $false) { $provOk = $false } }
foreach ($t in @($thrs)) { if ($null -eq $t.provenance -or $t.provenance.may_drive_gcode -ne $false) { $provOk = $false } }
foreach ($it in @($inss)) { if ($null -eq $it.provenance -or $it.provenance.may_drive_gcode -ne $false) { $provOk = $false } }
foreach ($t in @($trs)) { if ($null -eq $t.provenance -or $t.provenance.may_drive_gcode -ne $false) { $provOk = $false } }
Add-KBResult "T-KB-09" $provOk "6 dosyada provenance isaretli, may_drive_gcode=false"

# T-KB-10: boundary ihlali yok + sicaklik araliklari tuketilmiyor.
$boundOk = $true
if ($gl._provenance.printer_specific -ne $false -or $gl._provenance.filament_specific -ne $false) { $boundOk = $false }
foreach ($rec in (@($mats) + @($fits) + @($thrs) + @($inss) + @($trs))) {
  if ($null -eq $rec.provenance) { $boundOk = $false; continue }
  if ($rec.provenance.may_drive_gcode -ne $false -or $rec.provenance.printer_specific -ne $false -or $rec.provenance.filament_specific -ne $false) { $boundOk = $false }
}
$tempRefs = @()
foreach ($f in (Get-ChildItem -LiteralPath $EngineDir -Filter "*.ps1")) {
  $hit = Select-String -LiteralPath $f.FullName -Pattern "nozzle_temp_range|bed_temp_range" -SimpleMatch -ErrorAction SilentlyContinue
  if ($null -ne $hit) { $tempRefs += $f.Name }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1")) {
  if ([string]$f.Name -eq "Test-KnowledgeBoundary.ps1") { continue }
  $hit = Select-String -LiteralPath $f.FullName -Pattern "nozzle_temp_range|bed_temp_range" -SimpleMatch -ErrorAction SilentlyContinue
  if ($null -ne $hit) { $tempRefs += $f.Name }
}
Add-KBResult "T-KB-10" ($boundOk -and @($tempRefs).Count -eq 0) ("boundary ihlali yok; sicaklik araliklari tuketilmiyor: " + ($tempRefs -join ","))

# T-KB-11: threads/heat-set/guidelines/fits dosya adlari mantik kodunda gecmez
# (katman yuksekligi vb. slicer parametresi olarak okunamaz).
$refFiles = @("threads.json", "heat-set-inserts.json", "printing-guidelines.json", "fits.json")
$refHits = @()
foreach ($f in (Get-ChildItem -LiteralPath $EngineDir -Filter "*.ps1")) {
  foreach ($rf in $refFiles) {
    $hit = Select-String -LiteralPath $f.FullName -Pattern $rf -SimpleMatch -ErrorAction SilentlyContinue
    if ($null -ne $hit) { $refHits += ($f.Name + ":" + $rf) }
  }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1")) {
  if ([string]$f.Name -eq "Test-KnowledgeBoundary.ps1" -or [string]$f.Name -eq "Run-PrintTests.ps1") { continue }
  foreach ($rf in $refFiles) {
    $hit = Select-String -LiteralPath $f.FullName -Pattern $rf -SimpleMatch -ErrorAction SilentlyContinue
    if ($null -ne $hit) { $refHits += ($f.Name + ":" + $rf) }
  }
}
$appHits = @()
$appTxt = Get-Content -LiteralPath (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -Raw
foreach ($rf in $refFiles) {
  if ($appTxt -match [regex]::Escape($rf)) { $appHits += $rf }
}
Add-KBResult "T-KB-11" ((@($refHits).Count -eq 0) -and (@($appHits).Count -eq 0)) ("katman/FDM degerleri okunmuyor: " + ($refHits -join "," + $appHits -join ","))

# T-KB-12: heat-set degerleri manufacturer/reference bilgisi (datasheet notu korunur).
$insOk = $true
foreach ($it in @($inss)) {
  if ([string]$it.source -notmatch "manufacturer|typical" -or [string]$it.note -notmatch "datasheet") { $insOk = $false }
  if ([string]$it.provenance.status -ne "reference" -or $it.provenance.may_drive_gcode -ne $false) { $insOk = $false }
}
Add-KBResult "T-KB-12" $insOk "heat-set manufacturer/reference"

# T-KB-13: troubleshooting cozum/alan okuma engine/scripts/app mantiginda yok.
# (goruntu listesi ve varlik testleri sayilmaz.)
$fldHits = @()
foreach ($f in (Get-ChildItem -LiteralPath $EngineDir -Filter "*.ps1")) {
  $hit = Select-String -LiteralPath $f.FullName -Pattern "\.solutions|requires_printer_profile" -ErrorAction SilentlyContinue
  if ($null -ne $hit) { $fldHits += $f.Name }
}
foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $Root "scripts") -Filter "*.ps1")) {
  if ([string]$f.Name -eq "Test-KnowledgeBoundary.ps1" -or [string]$f.Name -eq "Run-PrintTests.ps1") { continue }
  $hit = Select-String -LiteralPath $f.FullName -Pattern "\.solutions|requires_printer_profile" -ErrorAction SilentlyContinue
  if ($null -ne $hit) { $fldHits += $f.Name }
}
$appFld = $false
if (($appTxt -match ".solutions") -or ($appTxt -match "requires_printer_profile")) { $appFld = $true }
Add-KBResult "T-KB-13" ((@($fldHits).Count -eq 0) -and (-not $appFld)) ("cozumler uygulanmiyor: " + ($fldHits -join ","))

# T-KB-14: yalnizca knowledge ile G-code uretilemez (uc placeholder + template).
$d = New-KBDir "kb14"
$fake3mf = Join-Path $d "model.3mf"
"dummy" | Set-Content -LiteralPath $fake3mf -Encoding UTF8
$fakeExe = Join-Path $d "orca.exe"
"dummy" | Set-Content -LiteralPath $fakeExe -Encoding UTF8
$blk = $false
$noGcode = $true
try {
  & (Join-Path $Root (Join-Path "scripts" "Slice.ps1")) -Input3mf $fake3mf -PrinterProfile "REPLACE_WITH_ORCA_PRINTER_PROFILE_NAME" -FilamentProfile "REPLACE_WITH_ORCA_FILAMENT_PROFILE_NAME" -ProcessProfile "REPLACE_WITH_ORCA_PROCESS_PROFILE_NAME" -PrinterJson (Join-Path $Root (Join-Path "printers" "generic-fdm.json")) -OutDir (Join-Path $d "slice") -OrcaExe $fakeExe 2>&1 | Out-Null
} catch {
  if ([string]$_.Exception.Message -match "^BLOCKED") { $blk = $true }
}
foreach ($gf in (Get-ChildItem -LiteralPath $d -Filter "*.gcode" -Recurse -ErrorAction SilentlyContinue)) { $noGcode = $false }
Add-KBResult "T-KB-14" ($blk -and $noGcode) "knowledge-only G-code uretilemez"
Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output ("KNOWLEDGE SONUC: $passed / $($results.Count) test gecti")
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
