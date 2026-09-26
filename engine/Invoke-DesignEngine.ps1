<#
.SYNOPSIS
  3D AI Designer - Design Engine. spec -> SCAD -> STL -> validation (max 3 tur retry).
.DESCRIPTION
  Akis:
    1. input.json + design validation (Test-DesignSpec.ps1). Hata varsa BLOCKED yaz, MODEL URETME.
    2. Desteklenen geometri: kutu govde + tam gecisli delikler. Desteklenmeyen -> BLOCKED.
    3. Parametrik model.scad uret (sadece kullanilan parametreler).
    4. OpenSCAD resolver -> Export-Stl.ps1 (DEGISTIRILMEDI, sadece cagrilir).
    5. Verify-Stl.ps1 -> validation/validation.json yaz.
    6. FAIL ise en fazla MaxRetries tur tekrar dene; cozulmezse FAILED_AFTER_RETRIES.
  Tum yollar proje root'una GORECELI cozulur (portable). G-code URETMEZ.
  NOT: $Spec (dosya yolu) ile $specObj (parse edilmis veri) bilerek farkli adlardadir;
  PowerShell buyuk/kucuk harf duyarsiz oldugu icin ayni ada izin verilmez.
.EXAMPLE
  powershell -File engine\Invoke-DesignEngine.ps1 -Spec projects\demo\input.json
#>
param(
  [Parameter(Mandatory = $true)][string]$Spec,
  [string]$ProjectDir = "",
  [string]$Printer = "",
  [int]$MaxRetries = 3
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir

function Get-Settings {
  $p = Join-Path $Root "settings.json"
  if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }
  return $null
}
function Write-ValidationJson($dir, $obj) {
  $vdir = Join-Path $dir "validation"
  New-Item -ItemType Directory -Force -Path $vdir | Out-Null
  $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $vdir "validation.json") -Encoding UTF8
}
function Write-Utf8NoBom($path, [string[]]$lines) {
  # OpenSCAD 2021.01 BOM gorunce "syntax error line 1" verir; SCAD her zaman BOM-suz yazilir.
  [System.IO.File]::WriteAllLines($path, $lines, (New-Object System.Text.UTF8Encoding $false))
}
function Run-Verify([hashtable]$VArgs) {
  try {
    $o = & $verifyScript @VArgs 2>&1 | Out-String
    return @{ code = 0; text = $o }
  } catch {
    return @{ code = 1; text = $_.Exception.Message }
  }
}

if (-not (Test-Path -LiteralPath $Spec)) { throw "Spec bulunamadi: $Spec" }
$specObj = Get-Content -LiteralPath $Spec -Raw | ConvertFrom-Json
$settings = Get-Settings

if ($ProjectDir -eq "") {
  $pdir = "projects"
  if ($settings -and $settings.projectsDir) { $pdir = $settings.projectsDir }
  if (-not [System.IO.Path]::IsPathRooted($pdir)) { $pdir = Join-Path $Root $pdir }
  $ProjectDir = Join-Path $pdir $specObj.project_name
}
if ($Printer -eq "") {
  $Printer = "generic-fdm"
  if ($settings -and $settings.defaultPrinter) { $Printer = $settings.defaultPrinter }
}
$printerPath = $Printer
if (-not [System.IO.Path]::IsPathRooted($printerPath)) { $printerPath = Join-Path $Root (Join-Path "printers" ($Printer + ".json")) }

# 1. Design validation
$dvOut = & (Join-Path $EngineDir "Test-DesignSpec.ps1") -Spec $Spec -Printer $printerPath -AsJson 2>&1
$dvCode = $LASTEXITCODE
$dv = $dvOut | Out-String | ConvertFrom-Json
if ($dvCode -ne 0) {
  New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
  Write-ValidationJson $ProjectDir ([pscustomobject]@{
    status = "BLOCKED"; reason = "design validation hatalari"; errors = @($dv.errors); warnings = @($dv.warnings); retries = 0; printer = $Printer
  })
  Write-Output "ENGINE: BLOCKED - kritik hata var, model uretilmedi."
  foreach ($e in $dv.errors) { Write-Output "  ERROR: $e" }
  exit 2
}

# 2. Geometri destegi: kutu + tam gecisli delikler
$unsupported = New-Object System.Collections.Generic.List[string]
foreach ($h in @($specObj.holes)) { if ($h -and -not $h.through) { $unsupported.Add("delik '" + $h.id + "' tam gecisli degil (desteklenmiyor)") } }
if (@($specObj.cuts | Where-Object { $_ -ne $null }).Count -gt 0) { $unsupported.Add("cuts desteklenmiyor") }
if ($null -ne $specObj.walls) { $unsupported.Add("walls (ici bos govde) desteklenmiyor") }
if (@($specObj.assemblies | Where-Object { $_ -ne $null }).Count -gt 0) { $unsupported.Add("assemblies desteklenmiyor") }
if ($unsupported.Count -gt 0) {
  New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
  Write-ValidationJson $ProjectDir ([pscustomobject]@{
    status = "BLOCKED"; reason = "desteklenmeyen geometri"; errors = @($unsupported); warnings = @($dv.warnings); retries = 0; printer = $Printer
  })
  Write-Output "ENGINE: BLOCKED - desteklenmeyen geometri."
  foreach ($e in $unsupported) { Write-Output "  ERROR: $e" }
  exit 2
}

# 3. SCAD uret
$cadDir = Join-Path $ProjectDir "cad"
New-Item -ItemType Directory -Force -Path $cadDir | Out-Null
$w = [double]$specObj.body.width_mm; $d = [double]$specObj.body.depth_mm; $hgt = [double]$specObj.body.height_mm
$scad = New-Object System.Collections.Generic.List[string]
$scad.Add("// $($specObj.project_name) - Design Engine uretimi, tum olculer mm.")
$scad.Add("// Kaynak: input.json (kullanici degerleri degistirilmedi).")
$scad.Add("")
$scad.Add("// PARAM")
$scad.Add("width = $w;")
$scad.Add("depth = $d;")
$scad.Add("height = $hgt;")
if ($null -ne $specObj.wall_thickness_mm) { $scad.Add("wall_thickness = $([double]$specObj.wall_thickness_mm);") }
$holes = @($specObj.holes | Where-Object { $_ -ne $null })
if ($holes.Count -gt 0) {
  $h0 = $holes[0]
  $scad.Add("hole_diameter = $([double]$h0.diameter_mm);")
  $scad.Add("hole_x = $([double]$h0.center_x_mm);")
  $scad.Add("hole_y = $([double]$h0.center_y_mm);")
}
$scad.Add("")
$scad.Add('$fn = 96;')
$scad.Add("")
$scad.Add("difference() {")
$scad.Add("    cube([width, depth, height]);")
foreach ($h in $holes) {
  $scad.Add("    translate([$([double]$h.center_x_mm), $([double]$h.center_y_mm), -1])")
  $scad.Add("        cylinder(d = $([double]$h.diameter_mm), h = height + 2);")
}
$scad.Add("}")
$scadPath = Join-Path $cadDir "model.scad"
Write-Utf8NoBom $scadPath $scad.ToArray()

if ($null -ne $specObj.prompt) { $specObj.prompt | Set-Content -LiteralPath (Join-Path $ProjectDir "input.md") -Encoding UTF8 }
$destJson = Join-Path $ProjectDir "input.json"
if ([System.IO.Path]::GetFullPath($Spec) -ne [System.IO.Path]::GetFullPath($destJson)) {
  Copy-Item -LiteralPath $Spec -Destination $destJson -Force
}

# 4. OpenSCAD coz + export
$openScad = $null
if ($settings -and $settings.openScadExe) { $openScad = $settings.openScadExe }
if (-not $openScad) { $openScad = & (Join-Path $Root (Join-Path "scripts" "Resolve-OpenScad.ps1")) 2>&1 | Select-Object -Last 1 }
$outDir = Join-Path $ProjectDir "output"
$exportScript = Join-Path $Root (Join-Path "scripts" "Export-Stl.ps1")
$verifyScript = Join-Path $Root (Join-Path "scripts" "Verify-Stl.ps1")

# 5-6. Export + verify + retry (max MaxRetries tur)
$attempt = 0
$finalStatus = "FAIL"
$lastVerify = ""
$holeResults = @()
do {
  $attempt++
  $expOk = $true
  try { & $exportScript -Scad $scadPath -OutDir $outDir -OpenScadExe $openScad 2>&1 | Out-Null }
  catch { $expOk = $false; $lastVerify = $_.Exception.Message }
  if (-not $expOk) { $finalStatus = "FAIL"; continue }
  $stl = Join-Path $outDir "model.stl"
  $holeResults = @()
  $worst = "PASS"
  $baseArgs = @{ Stl = $stl; ExpMinX = 0; ExpMinY = 0; ExpMinZ = 0; ExpMaxX = $w; ExpMaxY = $d; ExpMaxZ = $hgt }
  if ($holes.Count -eq 0) {
    $res = Run-Verify $baseArgs
    $lastVerify = $res.text
    if ($res.code -ne 0) { $worst = "FAIL" } elseif ($lastVerify -match "WARNING") { $worst = "WARNING" }
  } else {
    foreach ($h in $holes) {
      $hargs = $baseArgs.Clone()
      $hargs.CheckHole = $true
      $hargs.HoleCX = [double]$h.center_x_mm
      $hargs.HoleCY = [double]$h.center_y_mm
      $hargs.HoleDiameter = [double]$h.diameter_mm
      $res = Run-Verify $hargs
      $txt = $res.text
      $r = "PASS"; if ($res.code -ne 0) { $r = "FAIL" } elseif ($txt -match "WARNING") { $r = "WARNING" }
      $holeResults += [pscustomobject]@{ id = $h.id; result = $r; detail = $txt.Trim() }
      if ($r -eq "FAIL") { $worst = "FAIL" } elseif ($r -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
      $lastVerify = $txt
    }
  }
  $finalStatus = $worst
} while ($finalStatus -eq "FAIL" -and $attempt -lt $MaxRetries)

if ($finalStatus -eq "FAIL") { $finalStatus = "FAILED_AFTER_RETRIES" }

$stlInfo = Get-Item -LiteralPath (Join-Path $outDir "model.stl") -ErrorAction SilentlyContinue
$valObj = [pscustomobject]@{
  status = $finalStatus
  bbox = [pscustomobject]@{ x = $w; y = $d; z = $hgt }
  facet_info = @($lastVerify -split '\r\n|\r|\n' | Where-Object { $_ -match "facet|rim|bbox" })
  last_output_head = ($lastVerify -split '\r\n|\r|\n' | Select-Object -First 3) -join " | "
  file_bytes = $(if ($stlInfo) { $stlInfo.Length } else { 0 })
  hole_checks = @($holeResults)
  design_warnings = @($dv.warnings)
  retries = ($attempt - 1)
  printer = $Printer
}
Write-ValidationJson $ProjectDir $valObj

# README (sablon bolumleri)
$rm = New-Object System.Collections.Generic.List[string]
$rm.Add("# $($specObj.project_name) (Design Engine)")
$rm.Add("")
$rm.Add("## Kaynak prompt (degistirilmeden)")
$rm.Add("> $($specObj.prompt)")
$rm.Add("")
$rm.Add("## Kullanilan olculer (mm)")
$rm.Add("| Olcu | Deger | Kaynak |")
$rm.Add("| ---- | ----- | ------ |")
$rm.Add("| Govde | ${w} x ${d} x ${hgt} | kullanici |")
if ($null -ne $specObj.wall_thickness_mm) { $rm.Add("| Duvar kalinligi | $([double]$specObj.wall_thickness_mm) | kullanici |") }
foreach ($h in $holes) { $rm.Add("| Delik $($h.id) | cap $([double]$h.diameter_mm), merkez ($([double]$h.center_x_mm),$([double]$h.center_y_mm)) | kullanici |") }
$rm.Add("")
$rm.Add("## Dogrulama sonuclari")
$rm.Add("- Engine status: $finalStatus (tur sayisi: $attempt)")
$rm.Add("- Design validation: $($dv.status)")
foreach ($wrn in @($dv.warnings)) { $rm.Add("  - $wrn") }
$rm.Add("- STL verify ciktisi asagida; detay: validation/validation.json")
$rm.Add("---")
foreach ($ln in ($lastVerify -split '\r\n|\r|\n')) { $rm.Add($ln.TrimEnd()) }
$rm.Add("---")
$rm.Add("")
$rm.Add("## Dosyalar")
$rm.Add("- input.md (orijinal prompt), input.json (normalize veri)")
$rm.Add("- cad/model.scad (parametrik kaynak)")
$rm.Add("- output/model.stl, output/model.3mf")
$rm.Add("- validation/validation.json (makine raporu)")
$rm.Add("- slice/ : yok (G-code uretilmedi)")
$rm.Add("")
$rm.Add("## Malzeme")
if ($null -ne $specObj.material) { $rm.Add("- $($specObj.material)") } else { $rm.Add("- belirtilmedi") }
$rm | Set-Content -LiteralPath (Join-Path $ProjectDir "README.md") -Encoding UTF8

Write-Output "ENGINE: $finalStatus (tur: $attempt)"
if ($finalStatus -eq "FAILED_AFTER_RETRIES") { exit 2 } else { exit 0 }
