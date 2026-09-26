<#
.SYNOPSIS
  3D AI Designer V1 otomatik test paketi. Mevcut Faz 2/3 testlerini BOZMAZ (sadece okur).
.DESCRIPTION
  TEST 1: 50x50x10 prizma + 10mm delik (merkez 15,15) -> VERIFY PASS bekleniyor
  TEST 2: 80x40x20 govde + 25mm delik (merkez 15,15, duvar 2) -> VERIFY PASS bekleniyor
  TEST 3: bilerek yanlis bbox -> VERIFY FAIL bekleniyor
  TEST 4: bilerek yanlis delik capi -> VERIFY FAIL bekleniyor
  TEST 5: eksik kritik olcu (delik merkezi missing) -> ENGINE BLOCKED, MODEL URETILMEMELI
  TEST 6: ince duvar (0.6mm) -> DESIGN WARNING (FAIL degil, deger korunur)
  TEST 7: engine uctan uca (gecici proje) -> ENGINE PASS + validation.json
  Her test sonucu yazilir; basarisiz testin nedeni acikca belirtilir. Cikis: 0 = hepsi gecti.
  NOT: Verify/Design throw ile hata verir (exit degil); Engine exit kodu verir.
  Bu yuzden T1-T4 throw yakalar, T5-T6 exit kodu okur.
.EXAMPLE
  powershell -File scripts\Run-Tests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Verify = Join-Path $Root (Join-Path "scripts" "Verify-Stl.ps1")
$Design = Join-Path $Root (Join-Path "engine" "Test-DesignSpec.ps1")
$Engine = Join-Path $Root (Join-Path "engine" "Invoke-DesignEngine.ps1")
$F2 = Join-Path $Root (Join-Path "projects" (Join-Path "faz2-test" (Join-Path "output" "model.stl")))
$F3 = Join-Path $Root (Join-Path "projects" (Join-Path "faz3-test" (Join-Path "output" "model.stl")))

$results = New-Object System.Collections.Generic.List[pscustomobject]
function Add-Result($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}

# TEST 1 (throw yok + PASS metni = basari)
try {
  $o = & $Verify -Stl $F2 -ExpMinX 0 -ExpMinY 0 -ExpMinZ 0 -ExpMaxX 50 -ExpMaxY 50 -ExpMaxZ 10 -CheckHole -HoleCX 15 -HoleCY 15 -HoleDiameter 10 2>&1 | Out-String
  $ok = ($o -match "VERIFY: PASS")
  Add-Result "TEST 1 (faz2 bbox+delik PASS)" $ok $(if ($ok) { "faz2-test dogrulandi" } else { $o.Trim() })
} catch { Add-Result "TEST 1 (faz2 bbox+delik PASS)" $false $_.Exception.Message }

# TEST 2
try {
  $o = & $Verify -Stl $F3 -ExpMinX 0 -ExpMinY 0 -ExpMinZ 0 -ExpMaxX 80 -ExpMaxY 40 -ExpMaxZ 20 -CheckHole -HoleCX 15 -HoleCY 15 -HoleDiameter 25 2>&1 | Out-String
  $ok = ($o -match "VERIFY: PASS")
  Add-Result "TEST 2 (faz3 bbox+delik PASS)" $ok $(if ($ok) { "faz3-test dogrulandi" } else { $o.Trim() })
} catch { Add-Result "TEST 2 (faz3 bbox+delik PASS)" $false $_.Exception.Message }

# TEST 3 (throw + FAIL metni = basari)
try {
  $o = & $Verify -Stl $F3 -ExpMinX 0 -ExpMinY 0 -ExpMinZ 0 -ExpMaxX 80 -ExpMaxY 40 -ExpMaxZ 25 -CheckHole -HoleCX 15 -HoleCY 15 -HoleDiameter 25 2>&1 | Out-String
  Add-Result "TEST 3 (yanlis bbox -> FAIL)" $false ("FAIL uretilemedi: " + $o.Trim())
} catch {
  $ok = ($_.Exception.Message -match "VERIFY: FAIL")
  Add-Result "TEST 3 (yanlis bbox -> FAIL)" $ok $(if ($ok) { "hatali olcu yakalandi" } else { $_.Exception.Message })
}

# TEST 4 (throw + FAIL metni = basari)
try {
  $o = & $Verify -Stl $F3 -ExpMinX 0 -ExpMinY 0 -ExpMinZ 0 -ExpMaxX 80 -ExpMaxY 40 -ExpMaxZ 20 -CheckHole -HoleCX 15 -HoleCY 15 -HoleDiameter 20 2>&1 | Out-String
  Add-Result "TEST 4 (yanlis delik capi -> FAIL)" $false ("FAIL uretilemedi: " + $o.Trim())
} catch {
  $ok = ($_.Exception.Message -match "VERIFY: FAIL")
  Add-Result "TEST 4 (yanlis delik capi -> FAIL)" $ok $(if ($ok) { "hatali delik yakalandi" } else { $_.Exception.Message })
}

# TEST 5 (engine exit 2 + modelsiz + BLOCKED json = basari)
$tmpDir = Join-Path $Root (Join-Path "projects" "_test5-tmp")
try {
  if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $spec5 = [pscustomobject]@{
    project_name = "_test5-tmp"
    prompt = "TEST 5: delik merkezi eksik spec"
    body = [pscustomobject]@{ width_mm = 60; depth_mm = 30; height_mm = 10 }
    wall_thickness_mm = 2
    holes = @([pscustomobject]@{ id = "h1"; diameter_mm = 10; center_x_mm = $null; center_y_mm = $null; through = $true; status = "missing" })
    tolerance_mm = $null; material = $null
  }
  $spec5Path = Join-Path $tmpDir "input.json"
  $spec5 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $spec5Path -Encoding UTF8
  $o = & $Engine -Spec $spec5Path -ProjectDir $tmpDir 2>&1 | Out-String
  $engCode = $LASTEXITCODE
  $noScad = -not (Test-Path -LiteralPath (Join-Path $tmpDir (Join-Path "cad" "model.scad")))
  $noStl = -not (Test-Path -LiteralPath (Join-Path $tmpDir (Join-Path "output" "model.stl")))
  $valPath = Join-Path $tmpDir (Join-Path "validation" "validation.json")
  $blocked = $false
  if (Test-Path -LiteralPath $valPath) { $blocked = ((Get-Content -LiteralPath $valPath -Raw | ConvertFrom-Json).status -eq "BLOCKED") }
  $ok = (($engCode -eq 2) -and $noScad -and $noStl -and $blocked)
  Add-Result "TEST 5 (eksik olcu -> BLOCKED, modelsiz)" $ok $(if ($ok) { "model uretilmedi, BLOCKED yazildi" } else { "exit=$engCode noScad=$noScad noStl=$noStl blocked=$blocked" })
} catch { Add-Result "TEST 5 (eksik olcu -> BLOCKED, modelsiz)" $false $_.Exception.Message }
finally { if (Test-Path -LiteralPath $tmpDir) { Remove-Item -LiteralPath $tmpDir -Recurse -Force } }

# TEST 6 (exit 0 + WARNING metni = basari)
$tmpSpec6 = Join-Path ([System.IO.Path]::GetTempPath()) "test6-spec.json"
try {
  $spec6 = [pscustomobject]@{
    project_name = "test6"
    prompt = "TEST 6: ince duvar uyarisi"
    body = [pscustomobject]@{ width_mm = 40; depth_mm = 20; height_mm = 10 }
    wall_thickness_mm = 0.6
    holes = @([pscustomobject]@{ id = "h1"; diameter_mm = 5; center_x_mm = 10; center_y_mm = 10; through = $true; status = "ok" })
    tolerance_mm = $null; material = $null
  }
  $spec6 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $tmpSpec6 -Encoding UTF8
  $o = & $Design -Spec $tmpSpec6 2>&1 | Out-String
  $desCode = $LASTEXITCODE
  $ok = (($desCode -eq 0) -and ($o -match "WARNING"))
  Add-Result "TEST 6 (ince duvar -> WARNING)" $ok $(if ($ok) { "uyari uretildi, FAIL yok, deger korunur" } else { "exit=$desCode" })
} catch { Add-Result "TEST 6 (ince duvar -> WARNING)" $false $_.Exception.Message }
finally { if (Test-Path -LiteralPath $tmpSpec6) { Remove-Item -LiteralPath $tmpSpec6 -Force } }

# TEST 7 (engine uctan uca PASS + validation.json; gecici dizin temizlenir)
$tmpDir7 = Join-Path $Root (Join-Path "projects" "_test7-tmp")
try {
  if (Test-Path -LiteralPath $tmpDir7) { Remove-Item -LiteralPath $tmpDir7 -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $tmpDir7 | Out-Null
  $spec7 = [pscustomobject]@{
    project_name = "_test7-tmp"
    prompt = "TEST 7: engine uctan uca"
    body = [pscustomobject]@{ width_mm = 30; depth_mm = 20; height_mm = 10 }
    wall_thickness_mm = 2
    holes = @([pscustomobject]@{ id = "h1"; diameter_mm = 6; center_x_mm = 10; center_y_mm = 10; through = $true; status = "ok" })
    tolerance_mm = $null; material = $null
  }
  $spec7Path = Join-Path $tmpDir7 "input.json"
  $spec7 | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $spec7Path -Encoding UTF8
  $o = & $Engine -Spec $spec7Path -ProjectDir $tmpDir7 2>&1 | Out-String
  $engCode7 = $LASTEXITCODE
  $val7 = Join-Path $tmpDir7 (Join-Path "validation" "validation.json")
  $stl7ok = Test-Path -LiteralPath (Join-Path $tmpDir7 (Join-Path "output" "model.stl"))
  $pass7 = $false
  if (Test-Path -LiteralPath $val7) { $pass7 = ((Get-Content -LiteralPath $val7 -Raw | ConvertFrom-Json).status -eq "PASS") }
  $ok = (($engCode7 -eq 0) -and $stl7ok -and $pass7)
  Add-Result "TEST 7 (engine uctan uca PASS)" $ok $(if ($ok) { "SCAD+STL+validation.json uretildi" } else { "exit=$engCode7 stl=$stl7ok pass=$pass7" })
} catch { Add-Result "TEST 7 (engine uctan uca PASS)" $false $_.Exception.Message }
finally { if (Test-Path -LiteralPath $tmpDir7) { Remove-Item -LiteralPath $tmpDir7 -Recurse -Force } }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
