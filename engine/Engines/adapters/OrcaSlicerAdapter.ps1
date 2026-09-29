<#
.SYNOPSIS
  OrcaSlicer harici-binary adapter (Phase 5).
.DESCRIPTION
  Binary baglanmaz; resolver ile bulunur. Op destekleri: Detect, Slice.
  Slice gercek profiller olmadan BLOCKED doner. Diger op -> UNSUPPORTED.
  AGPL notu: yalnizca harici arac cagrisi, link/bundle yok.
#>

function Get-OrcaExe {
  $Root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
  $rs = Join-Path $Root (Join-Path "scripts" "Resolve-OrcaSlicer.ps1")
  if (Test-Path -LiteralPath $rs) {
    try {
      $v = & $rs 2>&1 | Select-Object -Last 1
      if ($v -and (Test-Path -LiteralPath ([string]$v))) { return [string]$v }
    } catch { }
  }
  return ""
}

function Orca-Health {
  $exe = Get-OrcaExe
  if ($exe -eq "") { return @{ status = "NOT_READY"; reason = "OrcaSlicer binary bulunamadi" } }
  return @{ status = "READY"; reason = "binary cozumlendi"; exe = $exe }
}

function Orca-Invoke($op, $params) {
  if ([string]$op -eq "Detect") { return (Orca-Health) }
  if ([string]$op -ne "Slice") {
    return @{ status = "UNSUPPORTED"; reason = ("desteklenmeyen op: " + $op) }
  }
  $h = Orca-Health
  if ([string]$h.status -ne "READY") { return $h }
  $model = [string]$params.Model
  if ([string]::IsNullOrWhiteSpace($model) -or -not (Test-Path -LiteralPath $model)) {
    return @{ status = "BLOCKED"; reason = "model dosyasi bulunamadi" }
  }
  foreach ($k in @("PrinterProfile", "FilamentProfile", "ProcessProfile")) {
    $v = [string]$params.$k
    if ([string]::IsNullOrWhiteSpace($v) -or $v -like "REPLACE*") {
      return @{ status = "BLOCKED"; reason = ("gercek profil gerekli: " + $k) }
    }
  }
  $exe = [string]$h.exe
  $outDir = [string]$params.OutDir
  if ([string]::IsNullOrWhiteSpace($outDir)) {
    $outDir = Join-Path ([System.IO.Path]::GetTempPath()) "orca-slice"
  }
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $outG = Join-Path $outDir "model.gcode"
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '--slice "' + $model + '" --output "' + $outG + '"'
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $pr = [System.Diagnostics.Process]::Start($psi)
    $done = $pr.WaitForExit(120000)
    if (-not $done) { try { $pr.Kill() } catch { }; return @{ status = "BLOCKED"; reason = "slicer timeout (120sn)" } }
    $so = $pr.StandardOutput.ReadToEnd()
    $se = $pr.StandardError.ReadToEnd()
    if ($pr.ExitCode -eq 0 -and (Test-Path -LiteralPath $outG) -and ((Get-Item -LiteralPath $outG).Length -gt 0)) {
      return @{ status = "OK"; engine = "orcaslicer"; gcode = $outG; stdout = $so; stderr = $se; exit_code = $pr.ExitCode }
    }
    return @{ status = "BLOCKED"; reason = "slicer G-code uretmedi"; stdout = $so; stderr = $se; exit_code = $pr.ExitCode }
  } catch {
    return @{ status = "BLOCKED"; reason = [string]$_.Exception.Message }
  }
}
