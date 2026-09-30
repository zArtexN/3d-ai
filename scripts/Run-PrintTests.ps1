<#
.SYNOPSIS
  V2.0 3D printing feature testleri: printer profile, material, printability, mesh quality, cost estimation, orientation.
.DESCRIPTION
  Her test PASS/FAIL ciktilar. Mevcut testlere dokunmaz.
.EXAMPLE
  powershell -File scripts\Run-PrintTests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$engineDir = Join-Path $Root "engine"
$knowledgeDir = Join-Path $Root "knowledge"
$printersDir = Join-Path $Root "printers"

$pass = 0; $fail = 0

function Assert-Test($name, $cond) {
  if ($cond) { Write-Output "[PASS] $name"; $script:pass++ }
  else { Write-Output "[FAIL] $name"; $script:fail++ }
}

# === 1. PRINTER PROFILE ===
Write-Output "--- PRINTER PROFILE ---"
$pf = Join-Path $printersDir "generic-fdm.json"
Assert-Test "printer-profile-exists" (Test-Path -LiteralPath $pf)
if (Test-Path -LiteralPath $pf) {
  $pj = Get-Content -LiteralPath $pf -Raw | ConvertFrom-Json
  Assert-Test "printer-has-id" ($pj.id -eq "generic-fdm")
  Assert-Test "printer-template-no-nozzle" ($null -eq $pj.nozzle_mm)
  Assert-Test "printer-template-no-bed" ($null -eq $pj.bed_mm)
  Assert-Test "printer-template-no-limits" ($null -eq $pj.min_wall_mm -and $null -eq $pj.min_feature_mm -and $null -eq $pj.min_hole_mm -and $null -eq $pj.max_overhang_deg)
  Assert-Test "printer-template-source" ([string]$pj.source -eq "template")
  Assert-Test "printer-template-not-slicable" ($pj.usable_for_slicing -eq $false)
  Assert-Test "printer-manufacturer-null" ($null -eq $pj.manufacturer)
  Assert-Test "printer-model-null" ($null -eq $pj.model)
  Assert-Test "printer-no-fake-temps" ($null -eq $pj.max_temp_nozzle_c)
}

# === 2. FILAMENT SCHEMA ===
Write-Output "--- FILAMENT SCHEMA ---"
$fs = Join-Path $Root (Join-Path "schemas" "filament.schema.json")
Assert-Test "filament-schema-exists" (Test-Path -LiteralPath $fs)
if (Test-Path -LiteralPath $fs) {
  $fj = Get-Content -LiteralPath $fs -Raw | ConvertFrom-Json
  Assert-Test "filament-schema-has-material" ($null -ne $fj.properties.material)
  Assert-Test "filament-schema-has-density" ($null -ne $fj.properties.density_g_cm3)
  Assert-Test "filament-schema-has-drying" ($null -ne $fj.properties.drying_required)
}

# === 3. KNOWLEDGE BASE ===
Write-Output "--- KNOWLEDGE BASE ---"
foreach ($kf in @("materials.json", "fits.json", "threads.json", "heat-set-inserts.json", "troubleshooting.json", "printing-guidelines.json")) {
  $kp = Join-Path $knowledgeDir $kf
  Assert-Test "kb-$kf-exists" (Test-Path -LiteralPath $kp)
  if (Test-Path -LiteralPath $kp) {
    try {
      $kd = Get-Content -LiteralPath $kp -Raw | ConvertFrom-Json
      Assert-Test "kb-$kf-valid-json" ($null -ne $kd)
    } catch {
      Assert-Test "kb-$kf-valid-json" $false
    }
  }
}

# Materials content check
$matFile = Join-Path $knowledgeDir "materials.json"
if (Test-Path -LiteralPath $matFile) {
  $mats = Get-Content -LiteralPath $matFile -Raw | ConvertFrom-Json
  $matNames = @($mats | ForEach-Object { $_.name })
  Assert-Test "mat-has-PLA" ($matNames -contains "PLA")
  Assert-Test "mat-has-PETG" ($matNames -contains "PETG")
  Assert-Test "mat-has-ABS" ($matNames -contains "ABS")
  Assert-Test "mat-has-TPU" ($matNames -contains "TPU")
  $pla = $mats | Where-Object { $_.name -eq "PLA" } | Select-Object -First 1
  if ($pla) {
    Assert-Test "mat-pla-density" ($pla.density_g_cm3 -gt 1.0 -and $pla.density_g_cm3 -lt 1.5)
    Assert-Test "mat-pla-has-nozzle-range" ($null -ne $pla.nozzle_temp_range_c)
  }
}

# Threads content check
$thrFile = Join-Path $knowledgeDir "threads.json"
if (Test-Path -LiteralPath $thrFile) {
  $thr = Get-Content -LiteralPath $thrFile -Raw | ConvertFrom-Json
  $thrSizes = @($thr | ForEach-Object { $_.size })
  Assert-Test "thread-has-M3" ($thrSizes -contains "M3")
  Assert-Test "thread-has-M5" ($thrSizes -contains "M5")
  $m3 = $thr | Where-Object { $_.size -eq "M3" } | Select-Object -First 1
  if ($m3) {
    Assert-Test "thread-m3-pitch" ($m3.pitch_mm -eq 0.5)
    Assert-Test "thread-m3-major" ($m3.major_diameter_mm -eq 3.0)
  }
}

# === 4. PRINTABILITY ANALYZER ===
Write-Output "--- PRINTABILITY ANALYZER ---"
$paScript = Join-Path $engineDir "Analyze-Printability.ps1"
Assert-Test "printability-script-exists" (Test-Path -LiteralPath $paScript)
if (Test-Path -LiteralPath $paScript) {
  # Create temp spec for testing
  $tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ptest-" + (Get-Date -Format "yyyyMMddHHmmss"))
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $testSpec = [pscustomobject]@{
    project_name = "printtest"
    prompt = "test"
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    components = @([pscustomobject]@{
      id = "body"
      base = [pscustomobject]@{ shape = "box"; width_mm = 50; depth_mm = 50; height_mm = 10 }
      hollow = [pscustomobject]@{ wall_mm = 2; open_top = $false }
      holes = @([pscustomobject]@{ id = "h1"; diameter_mm = 10; center_x_mm = 25; center_y_mm = 25; hole_type = "through"; status = "ok" })
      cutouts = @(); edge_notes = @(); transforms = @()
      tolerance = $null
    })
    assembly = $null
    material = "PLA"
  }
  $specFile = Join-Path $tmpDir "spec.json"
  $testSpec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $specFile -Encoding UTF8
  try {
    $paOut = & $paScript -SpecFile $specFile -AsJson 2>&1 | Out-String
    $paObj = $paOut | ConvertFrom-Json
    Assert-Test "printability-returns-status" ($null -ne $paObj.status)
    Assert-Test "printability-has-checks" ($null -ne $paObj.checks -and @($paObj.checks).Count -gt 0)
    Assert-Test "printability-has-summary" ($null -ne $paObj.summary)
  } catch { Write-Output "ERROR: $($_.Exception.Message)"; Assert-Test "printability-runs" $false }
  Remove-Item -LiteralPath $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
}

# === 5. ORIENTATION ADVISOR ===
Write-Output "--- ORIENTATION ADVISOR ---"
$orScript = Join-Path $engineDir "Analyze-Orientation.ps1"
Assert-Test "orientation-script-exists" (Test-Path -LiteralPath $orScript)
if (Test-Path -LiteralPath $orScript) {
  $tmpDir2 = Join-Path ([System.IO.Path]::GetTempPath()) ("otest-" + (Get-Date -Format "yyyyMMddHHmmss"))
  New-Item -ItemType Directory -Force -Path $tmpDir2 | Out-Null
  $testSpec2 = [pscustomobject]@{
    project_name = "ortest"; prompt = "test"
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    components = @([pscustomobject]@{
      id = "body"
      base = [pscustomobject]@{ shape = "box"; width_mm = 80; depth_mm = 40; height_mm = 20 }
      hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @(); tolerance = $null
    })
    assembly = $null; material = $null
  }
  $specFile2 = Join-Path $tmpDir2 "spec.json"
  $testSpec2 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $specFile2 -Encoding UTF8
  try {
    $orOut = & $orScript -SpecFile $specFile2 -AsJson 2>&1 | Out-String
    $orObj = $orOut | ConvertFrom-Json
    Assert-Test "orientation-has-orientations" ($null -ne $orObj.orientations -and @($orObj.orientations).Count -ge 3)
    $oA = @($orObj.orientations) | Where-Object { $_.name -match "A" } | Select-Object -First 1
    if ($oA) {
      Assert-Test "orientation-A-has-bed-contact" ($oA.bed_contact_area_mm2 -gt 0)
      Assert-Test "orientation-A-has-support" ($null -ne $oA.support_estimate)
    }
  } catch { Write-Output "ERROR: $($_.Exception.Message)"; Assert-Test "orientation-runs" $false }
  Remove-Item -LiteralPath $tmpDir2 -Recurse -Force -ErrorAction SilentlyContinue
}

# === 6. MESH QUALITY ===
Write-Output "--- MESH QUALITY ---"
$mqScript = Join-Path $engineDir "Get-MeshQuality.ps1"
Assert-Test "meshquality-script-exists" (Test-Path -LiteralPath $mqScript)

# === 7. COST ESTIMATION ===
Write-Output "--- COST ESTIMATION ---"
$esScript = Join-Path $engineDir "Estimate-Print.ps1"
Assert-Test "estimate-script-exists" (Test-Path -LiteralPath $esScript)
if (Test-Path -LiteralPath $esScript) {
  $tmpDir3 = Join-Path ([System.IO.Path]::GetTempPath()) ("etest-" + (Get-Date -Format "yyyyMMddHHmmss"))
  New-Item -ItemType Directory -Force -Path $tmpDir3 | Out-Null
  $testSpec3 = [pscustomobject]@{
    project_name = "estest"; prompt = "test"
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    components = @([pscustomobject]@{
      id = "body"
      base = [pscustomobject]@{ shape = "box"; width_mm = 50; depth_mm = 50; height_mm = 10 }
      hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @(); tolerance = $null
    })
    assembly = $null; material = $null
  }
  $specFile3 = Join-Path $tmpDir3 "spec.json"
  $testSpec3 | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $specFile3 -Encoding UTF8
  try {
    $esOut = & $esScript -SpecFile $specFile3 -AsJson 2>&1 | Out-String
    $esObj = $esOut | ConvertFrom-Json
    Assert-Test "estimate-returns-status" ($esObj.status -eq "ESTIMATE")
    Assert-Test "estimate-has-weight" ($esObj.weight_estimated_g -gt 0)
    Assert-Test "estimate-print-time-unavailable" ($esObj.print_time -eq "ESTIMATE_UNAVAILABLE")
  } catch { Write-Output "ERROR: $($_.Exception.Message)"; Assert-Test "estimate-runs" $false }
  Remove-Item -LiteralPath $tmpDir3 -Recurse -Force -ErrorAction SilentlyContinue
}

# === 8. SLICER INTEGRATION ===
Write-Output "--- SLICER INTEGRATION ---"
$slScript = Join-Path $engineDir "Invoke-Slicer.ps1"
Assert-Test "slicer-script-exists" (Test-Path -LiteralPath $slScript)

# === 9. VERSION ===
Write-Output "--- VERSION ---"
$vf = Join-Path $Root "VERSION"
Assert-Test "version-file-exists" (Test-Path -LiteralPath $vf)
if (Test-Path -LiteralPath $vf) {
  $ver = (Get-Content -LiteralPath $vf -Raw).Trim()
  Assert-Test "version-is-semver" ($ver -match "^\d+\.\d+\.\d+$")
}

# === SUMMARY ===
$total = ($pass + $fail)
Write-Output "========================================"
Write-Output "PRINT TESTS: TOTAL=$total PASS=$pass FAIL=$fail"
if ($fail -gt 0) { exit 1 } else { exit 0 }
