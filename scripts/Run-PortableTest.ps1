<#
.SYNOPSIS
  PORTABLE TEST: proje baska klasore kopyalanir, resolver + engine + validation calisir.
.DESCRIPTION
  1. engine/scripts/schemas/printers/templates + settings.json gecici dizine kopyalanir (baska PC simulasyonu).
  2. Kopyada resolver OpenSCAD'i bulur (absolute proje yolu kullanilmaz).
  3. Demo spec ile geometry engine calisir, STL + validation uretilir.
  4. Ciktilarda kaynak absolute path yoktur.
  5. Gecici dizin temizlenir. Sonuc: PORTABLE TEST PASS/FAIL. Cikis kodu buna gore.
.EXAMPLE
  powershell -File scripts\Run-PortableTest.ps1
#>

$ErrorActionPreference = "Continue"
$SrcRoot = Split-Path -Parent $PSScriptRoot
$DstRoot = Join-Path ([System.IO.Path]::GetTempPath()) "3D-AI-portable-test"

function Write-PMsg($t) { Write-Output $t }
$okAll = $true

try {
  if (Test-Path -LiteralPath $DstRoot) { Remove-Item -LiteralPath $DstRoot -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $DstRoot | Out-Null
  foreach ($d in @("engine", "scripts", "schemas", "printers", "templates")) {
    Copy-Item -LiteralPath (Join-Path $SrcRoot $d) -Destination (Join-Path $DstRoot $d) -Recurse -Force
  }
  Copy-Item -LiteralPath (Join-Path $SrcRoot "settings.json") -Destination (Join-Path $DstRoot "settings.json") -Force
  Write-PMsg "[PASS] kopyalama (baska PC simulasyonu)"
} catch { Write-PMsg "[FAIL] kopyalama: $($_.Exception.Message)"; exit 1 }

try {
  $exe = & (Join-Path $DstRoot (Join-Path "scripts" "Resolve-OpenScad.ps1")) 2>&1 | Select-Object -Last 1
  if ($exe -and (Test-Path -LiteralPath ([string]$exe))) { Write-PMsg "[PASS] resolver (OpenSCAD bulundu)" }
  else { $okAll = $false; Write-PMsg "[FAIL] resolver OpenSCAD bulamadi" }
} catch { $okAll = $false; Write-PMsg "[FAIL] resolver: $($_.Exception.Message)" }

try {
  $spec = [pscustomobject]@{
    project_name = "portable-demo"; prompt = "portable demo"
    metadata = [pscustomobject]@{ spec_version = "2.0" }
    assembly = $null; material = $null
    components = @([pscustomobject]@{
      id = "body"; label = "body"
      base = [pscustomobject]@{ shape = "box"; width_mm = 50; depth_mm = 30; height_mm = 20 }
      hollow = $null
      holes = @([pscustomobject]@{ id = "h1"; hole_type = "through"; diameter_mm = 10; center_x_mm = 15; center_y_mm = 15; axis = "z"; depth_mm = $null; cs_dia_mm = $null; cs_depth_mm = $null; cb_dia_mm = $null; cb_depth_mm = $null; screw = $null; status = "ok" })
      cutouts = @(); edge_notes = @(); transforms = @()
      tolerance = $null; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
    })
  }
  $sp = Join-Path $DstRoot "demo-spec.json"
  $spec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $sp -Encoding UTF8
  $pd = Join-Path $DstRoot (Join-Path "projects" "portable-demo")
  $o = & (Join-Path $DstRoot (Join-Path "engine" "Invoke-GeometryEngine.ps1")) -SpecFile $sp -ProjectDir $pd 2>&1 | Out-String
  $stlOk = Test-Path -LiteralPath (Join-Path $pd (Join-Path "output" "body.stl"))
  $valOk = $false
  $vp = Join-Path $pd (Join-Path "validation" "body.validation.json")
  if (Test-Path -LiteralPath $vp) { $valOk = ((Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json).status -eq "PASS") }
  if ($stlOk -and $valOk) { Write-PMsg "[PASS] demo STL + validation" }
  else { $okAll = $false; Write-PMsg "[FAIL] demo uretim (stl=$stlOk validation=$valOk)" }
  $hits = New-Object System.Collections.Generic.List[string]
  foreach ($f in (Get-ChildItem -LiteralPath $pd -Recurse -File | Where-Object { $_.Extension -match "json|md|scad|log" })) {
    $t = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if ($t -and $t.Contains($SrcRoot)) { $hits.Add($f.Name) }
  }
  if ($hits.Count -eq 0) { Write-PMsg "[PASS] absolute kaynak yolu yok" }
  else { $okAll = $false; Write-PMsg "[FAIL] kaynak yolu sizmis: $($hits -join ',')" }
} catch { $okAll = $false; Write-PMsg "[FAIL] demo: $($_.Exception.Message)" }
finally {
  for ($i = 0; $i -lt 5 -and (Test-Path -LiteralPath $DstRoot); $i++) {
    try {
      [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
      Remove-Item -LiteralPath $DstRoot -Recurse -Force -ErrorAction Stop
    } catch { Start-Sleep -Milliseconds 800 }
  }
}

if ($okAll) { Write-PMsg "PORTABLE TEST PASS"; exit 0 } else { Write-PMsg "PORTABLE TEST FAIL"; exit 1 }
