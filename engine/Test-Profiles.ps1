<#
.SYNOPSIS
  Phase 8: yazici/filament/process profil dogrulama (registry validation).
.DESCRIPTION
  printers/*.json, filaments/*.json, processes/*.json dosyalarini sema kurallarina
  + placeholder/usable kontrollerine gore degerlendirir. Deger URETMEZ; sadece
  raporlar: @{ valid, slicable, errors[], warnings[], id, kind }.
  valid = sema hatasi yok. slicable = dilimleme icin kullanilabilir
  (sablon degil, placeholder yok, kritikler null degil).
#>

function Read-ProfileJson($path) {
  if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
    return @{ ok = $false; data = $null; error = "profil dosyasi yok: $path" }
  }
  try {
    $d = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    return @{ ok = $true; data = $d; error = "" }
  } catch {
    return @{ ok = $false; data = $null; error = ("JSON parse hatasi: " + $_.Exception.Message) }
  }
}

function New-ProfileVerdict($kind, $id) {
  return @{ kind = $kind; id = $id; valid = $true; slicable = $true;
            errors = @(); warnings = @() }
}

function Add-PError($v, $msg) { $v.errors += @($msg); $v.valid = $false; $v.slicable = $false }
function Add-PWarn($v, $msg) { $v.warnings += @($msg) }
function Mark-NotSlicable($v, $msg) { $v.slicable = $false; $v.warnings += @($msg) }

function Test-IsPlaceholder($s) {
  if ([string]::IsNullOrWhiteSpace([string]$s)) { return $true }
  return ([string]$s -like "REPLACE*")
}

function Test-PrinterProfile([string]$Path) {
  $r = Read-ProfileJson $Path
  $v = New-ProfileVerdict "printer" ""
  if (-not $r.ok) { Add-PError $v $r.error; return $v }
  $p = $r.data
  $v.id = [string]$p.id
  if ([string]::IsNullOrWhiteSpace($v.id)) { Add-PError $v "printer.id zorunlu" }
  if ([string]::IsNullOrWhiteSpace([string]$p.label)) { Add-PError $v "printer.label zorunlu" }
  if (-not $p.orca_profiles) { Add-PError $v "printer.orca_profiles zorunlu {printer,filament,process}" }
  else {
    foreach ($k in @("printer", "filament", "process")) {
      $n = [string]$p.orca_profiles.$k
      if (Test-IsPlaceholder $n) { Add-PError $v ("orca_profiles." + $k + " eslestirilmemis (placeholder/bos)") }
    }
  }
  if ($p.usable_for_slicing -ne $true) {
    Mark-NotSlicable $v "usable_for_slicing != true (sablon veya gercek profil degil)"
  }
  if ($null -eq $p.manufacturer) { Add-PWarn $v "manufacturer UNKNOWN" }
  if ($null -eq $p.model) { Add-PWarn $v "model UNKNOWN" }
  if ($null -eq $p.nozzle_mm) { Add-PWarn $v "nozzle_mm UNKNOWN" }
  if ($null -eq $p.bed_mm) { Add-PWarn $v "bed_mm UNKNOWN (build volume bilinmiyor)" }
  if ($null -eq $p.firmware) { Add-PWarn $v "firmware UNKNOWN" }
  if ([string]$p.source -eq "template") { Mark-NotSlicable $v "source=template" }
  return $v
}

function Test-FilamentProfile([string]$Path) {
  $r = Read-ProfileJson $Path
  $v = New-ProfileVerdict "filament" ""
  if (-not $r.ok) { Add-PError $v $r.error; return $v }
  $f = $r.data
  $v.id = [string]$f.id
  if ([string]::IsNullOrWhiteSpace($v.id)) { Add-PError $v "filament.id zorunlu" }
  if ([string]::IsNullOrWhiteSpace([string]$f.material)) { Add-PError $v "filament.material zorunlu" }
  $src = [string]$f.profile_source
  if ([string]::IsNullOrWhiteSpace($src) -or $src -eq "belirtilmedi") {
    Mark-NotSlicable $v "profile_source belirtilmemis (Orca profili eslesmedi)"
  }
  if ($null -eq $f.diameter_mm) { Add-PWarn $v "diameter_mm UNKNOWN" }
  if ($null -eq $f.nozzle_temp_min_c -and $null -eq $f.nozzle_temp_max_c) {
    Add-PWarn $v "nozul sicakligi UNKNOWN (slicer profilinden alinmali)"
  }
  if ($null -eq $f.bed_temp_min_c -and $null -eq $f.bed_temp_max_c) {
    Add-PWarn $v "tabla sicakligi UNKNOWN (slicer profilinden alinmali)"
  }
  if ($src -eq "template") { Mark-NotSlicable $v "source=template" }
  if ($src -eq "test_fixture") { Add-PWarn $v "source=test_fixture (gercek profil degil)" }
  return $v
}

function Test-ProcessProfile([string]$Path) {
  $r = Read-ProfileJson $Path
  $v = New-ProfileVerdict "process" ""
  if (-not $r.ok) { Add-PError $v $r.error; return $v }
  $p = $r.data
  $v.id = [string]$p.id
  if ([string]::IsNullOrWhiteSpace($v.id)) { Add-PError $v "process.id zorunlu" }
  if ([string]::IsNullOrWhiteSpace([string]$p.source)) { Add-PError $v "process.source zorunlu" }
  if (Test-IsPlaceholder ([string]$p.orca_profile)) {
    Mark-NotSlicable $v "orca_profile eslestirilmemis (placeholder/bos)"
  }
  if ($null -eq $p.layer_height_mm) { Add-PWarn $v "layer_height_mm UNKNOWN" }
  if ($null -eq $p.print_speed_mm_s) { Add-PWarn $v "print_speed_mm_s UNKNOWN" }
  if ($null -eq $p.support_enabled) { Add-PWarn $v "support_enabled UNKNOWN" }
  if ([string]$p.source -eq "template") { Mark-NotSlicable $v "source=template" }
  if ([string]$p.source -eq "test_fixture") { Add-PWarn $v "source=test_fixture (gercek profil degil)" }
  return $v
}
