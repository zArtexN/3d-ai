<#
.SYNOPSIS
  Phase 8: slicer + printer registry + G-code gate + print-job testleri (TDD).
.DESCRIPTION
  Test profilleri SADECE $env:TEMP altinda uretilir (source=test_fixture);
  printers/filaments/processes altina sahte profil YAZILMAZ. Tum fixture
  degerleri acikca TEST etiketlidir.
#>
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
. (Join-Path $EngineDir "Test-Profiles.ps1")
. (Join-Path $EngineDir "Test-SliceReadiness.ps1")
. (Join-Path $EngineDir "New-PrintJob.ps1")

$script:pass = 0; $script:fail = 0
function Add-SLCResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("slc-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
try {
  $printerFx = Join-Path $base "printer.json"
  @{ id = "TEST-printer"; label = "TEST printer (fixture)"; usable_for_slicing = $true;
     manufacturer = "TEST"; model = "TEST"; nozzle_mm = 0.4; bed_mm = @(220, 220, 250);
     bed_shape = "rectangular"; firmware = "TEST"; min_wall_mm = 0.8;
     orca_profiles = @{ printer = "TEST_Printer"; filament = "TEST_Filament"; process = "TEST_Process" };
     notes = "test fixture"; source = "test_fixture"; created_at = $null } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $printerFx -Encoding UTF8
  $filamentFx = Join-Path $base "filament.json"
  @{ id = "TEST-pla"; material = "PLA"; brand = "TEST"; diameter_mm = 1.75;
     nozzle_temp_min_c = 200; nozzle_temp_max_c = 210; bed_temp_min_c = 60; bed_temp_max_c = 60;
     profile_source = "test_fixture"; notes = "test fixture"; created_at = $null } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $filamentFx -Encoding UTF8
  $processFx = Join-Path $base "process.json"
  @{ id = "TEST-proc"; layer_height_mm = 0.2; print_speed_mm_s = 60; support_enabled = $false;
     orca_profile = "TEST_Process"; notes = "test fixture"; source = "test_fixture"; created_at = $null } |
    ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $processFx -Encoding UTF8
  $modelFx = Join-Path $base "model.stl"
  Set-Content -LiteralPath $modelFx -Value "solid test`nendsolid test" -Encoding ASCII
  $fakeExe = Join-Path $base "orca-fake.exe"
  New-Item -ItemType File -Force -Path $fakeExe | Out-Null

  # T-SLICE-01: gecerli profiller dogrulanir.
  $pv = Test-PrinterProfile $printerFx
  $fv = Test-FilamentProfile $filamentFx
  $cv = Test-ProcessProfile $processFx
  Add-SLCResult "T-SLICE-01" ($pv.valid -and $pv.slicable -and $fv.valid -and $fv.slicable -and $cv.valid -and $cv.slicable) "uc profil valid+slicable"

  # T-SLICE-02: yazici eksik -> BLOCKED + missing=printer.
  $r2 = Test-SliceReadiness -ModelStl $modelFx -PrinterJson "" -FilamentJson $filamentFx -ProcessJson $processFx -OrcaExe $fakeExe
  Add-SLCResult "T-SLICE-02" ($r2.status -eq "BLOCKED" -and @(@($r2.missing) | Where-Object { $_.id -eq "printer" }).Count -eq 1) "yazici yok"

  # T-SLICE-03: filament eksik.
  $r3 = Test-SliceReadiness -ModelStl $modelFx -PrinterJson $printerFx -FilamentJson "" -ProcessJson $processFx -OrcaExe $fakeExe
  Add-SLCResult "T-SLICE-03" ($r3.status -eq "BLOCKED" -and @(@($r3.missing) | Where-Object { $_.id -eq "filament" }).Count -eq 1) "filament yok"

  # T-SLICE-04: process eksik.
  $r4 = Test-SliceReadiness -ModelStl $modelFx -PrinterJson $printerFx -FilamentJson $filamentFx -ProcessJson "" -OrcaExe $fakeExe
  Add-SLCResult "T-SLICE-04" ($r4.status -eq "BLOCKED" -and @(@($r4.missing) | Where-Object { $_.id -eq "process" }).Count -eq 1) "process yok"

  # T-SLICE-05: slicer ulasilamaz.
  $r5 = Test-SliceReadiness -ModelStl $modelFx -PrinterJson $printerFx -FilamentJson $filamentFx -ProcessJson $processFx -OrcaExe (Join-Path $base "yok.exe")
  $slcMiss = @(@($r5.missing) | Where-Object { $_.id -eq "slicer" })
  $slcBlocked = ($r5.status -eq "BLOCKED" -and $slcMiss.Count -eq 1)
  if ($slcBlocked -and $fakeExe -and (Test-Path -LiteralPath $fakeExe)) {
    # Bu makinede gercek Orca cozulebilir; o zaman bogus-exe yine de BLOCKED vermeli (cozucu atlandi cunku exe verildi ama yok).
    $slcBlocked = ($slcMiss[0].message -match "unavailable|bulunamadi")
  }
  Add-SLCResult "T-SLICE-05" $slcBlocked "slicer unavailable"

  # T-SLICE-06: model gecersiz.
  $r6 = Test-SliceReadiness -ModelStl (Join-Path $base "yok.stl") -PrinterJson $printerFx -FilamentJson $filamentFx -ProcessJson $processFx -OrcaExe $fakeExe
  Add-SLCResult "T-SLICE-06" ($r6.status -eq "BLOCKED" -and @(@($r6.missing) | Where-Object { $_.id -eq "model" }).Count -eq 1) "model yok"

  # T-SLICE-07: cikti yok -> FAIL.
  $o7 = Test-SliceOutput -GcodePath (Join-Path $base "yok.gcode")
  Add-SLCResult "T-SLICE-07" ($o7.status -eq "FAIL" -and $o7.errors.Count -gt 0) "output missing"

  # T-SLICE-08: G-code gate (sablon set BLOCKED; Slice.ps1 placeholder'i reddeder; job BLOCKED+gcode null).
  $tplP = Join-Path $Root (Join-Path "printers" "generic-fdm.json")
  $tplF = Join-Path $Root (Join-Path "filaments" "_template.json")
  $tplC = Join-Path $Root (Join-Path "processes" "_template.json")
  $r8 = Test-SliceReadiness -ModelStl $modelFx -PrinterJson $tplP -FilamentJson $tplF -ProcessJson $tplC -OrcaExe $fakeExe
  $sliceBlocked = $false
  try {
    & (Join-Path $Root (Join-Path "scripts" "Slice.ps1")) -Input3mf $modelFx `
      -PrinterProfile "REPLACE_WITH_ORCA_PRINTER_PROFILE_NAME" -FilamentProfile "Generic PLA" `
      -OutDir (Join-Path $base "slice") -OrcaExe $fakeExe 2>&1 | Out-Null
  } catch { if ([string]$_.Exception.Message -match "BLOCKED") { $sliceBlocked = $true } }
  $proj8 = Join-Path $base "proj8"; New-Item -ItemType Directory -Force -Path $proj8 | Out-Null
  $j8 = New-PrintJob -ProjectDir $proj8 -JobId "job-gate" -ModelStl $modelFx `
    -PrinterJson $tplP -FilamentJson $tplF -ProcessJson $tplC -OrcaExe $fakeExe
  $j8raw = Get-Content -LiteralPath $j8.path -Raw | ConvertFrom-Json
  $gateOk = ($r8.status -eq "BLOCKED" -and $sliceBlocked -and $j8.status -eq "BLOCKED" -and $null -eq $j8raw.artifact.gcode)
  Add-SLCResult "T-SLICE-08" $gateOk "G-code gate kapali"

  # T-SLICE-09: print-job yapisi (9 alan + status).
  $proj9 = Join-Path $base "proj9"; New-Item -ItemType Directory -Force -Path $proj9 | Out-Null
  $j9 = New-PrintJob -ProjectDir $proj9 -JobId "job-ok" -ModelStl $modelFx `
    -PrinterJson $printerFx -FilamentJson $filamentFx -ProcessJson $processFx -OrcaExe $fakeExe
  $j9raw = Get-Content -LiteralPath $j9.path -Raw | ConvertFrom-Json
  $need = @("model", "printer", "filament", "process", "orientation", "supports", "slicer", "artifact", "validation", "status")
  $hasAll = $true
  foreach ($k in $need) { if ($null -eq $j9raw.PSObject.Properties[$k]) { $hasAll = $false } }
  Add-SLCResult "T-SLICE-09" ($j9.status -eq "PREPARED" -and $hasAll) "job yapisi tam"

  # T-SLICE-10: otomatik baski YOK (status kumesinde gonderme yok + gonderme fonksiyonu yok).
  $sendFns = @()
  foreach ($f in (Get-ChildItem -Path $EngineDir -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue)) {
    $hits = Select-String -LiteralPath $f.FullName -Pattern "function Send-", "function Start-Print", "function Upload-Gcode" -ErrorAction SilentlyContinue
    foreach ($h in $hits) { $sendFns += @($f.Name + ":" + $h.LineNumber) }
  }
  $sf = Join-Path $Root (Join-Path "scripts" "Slice.ps1")
  $hits2 = Select-String -LiteralPath $sf -Pattern "function Send-", "function Start-Print", "function Upload-Gcode" -ErrorAction SilentlyContinue
  foreach ($h in $hits2) { $sendFns += @("Slice.ps1:" + $h.LineNumber) }
  $noSend = ($sendFns.Count -eq 0 -and ($j9.status -in @("PREPARED", "BLOCKED")) -and ($j8.status -in @("PREPARED", "BLOCKED")))
  Add-SLCResult "T-SLICE-10" $noSend "gonderme kodu yok"
} finally {
  if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

Write-Output "----------------------------------------"
Write-Output ("SLICE SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
