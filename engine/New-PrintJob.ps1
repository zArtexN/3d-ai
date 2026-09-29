<#
.SYNOPSIS
  Phase 8: baski-isi kaydi olusturur (hazirlik / offline). YAZICIYA GONDERMEZ.
.DESCRIPTION
  New-PrintJob: <ProjectDir>/jobs/<jobid>/job.json yazar:
  { model, printer, filament, process, orientation, supports, slicer, artifact,
    validation, status }.
  status = PREPARED (readiness READY) veya BLOCKED (eksikler validation.missing[]).
  Bu dosyada gonderme/upload/transmit kodu YOKTUR; offline modda is her zaman
  hazirlikta kalir. artifact.gcode=null ise G-code uretilmemistir.
#>
param()

$PrintJobDir = $PSScriptRoot
. (Join-Path $PrintJobDir "Test-SliceReadiness.ps1")

function Get-ProfileId($path) {
  if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) { return $null }
  try { return [string]((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json).id) }
  catch { return $null }
}

function New-PrintJob(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [string]$JobId = "",
  [string]$ModelStl = "",
  [string]$PrinterJson = "",
  [string]$FilamentJson = "",
  [string]$ProcessJson = "",
  [string]$OrcaExe = "",
  $Orientation = $null,
  $Supports = $null
) {
  if ([string]::IsNullOrWhiteSpace($JobId)) {
    $JobId = ("job-" + (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"))
  }
  if ([string]::IsNullOrWhiteSpace($ModelStl)) {
    $cand = Join-Path $ProjectDir "model.stl"
    if (Test-Path -LiteralPath $cand) { $ModelStl = $cand }
  }
  $ready = Test-SliceReadiness -ModelStl $ModelStl -PrinterJson $PrinterJson `
    -FilamentJson $FilamentJson -ProcessJson $ProcessJson -OrcaExe $OrcaExe
  $status = "BLOCKED"
  if ($ready.status -eq "READY") { $status = "PREPARED" }
  $jobDir = Join-Path $ProjectDir (Join-Path "jobs" $JobId)
  New-Item -ItemType Directory -Force -Path $jobDir | Out-Null
  $job = [pscustomobject]@{
    job_id    = $JobId
    created_at = ((Get-Date).ToUniversalTime().ToString("o"))
    mode      = "offline"
    model     = [pscustomobject]@{ stl = $ModelStl }
    printer   = [pscustomobject]@{ profile = $PrinterJson; id = (Get-ProfileId $PrinterJson) }
    filament  = [pscustomobject]@{ profile = $FilamentJson; id = (Get-ProfileId $FilamentJson) }
    process   = [pscustomobject]@{ profile = $ProcessJson; id = (Get-ProfileId $ProcessJson) }
    orientation = $(if ($null -eq $Orientation) {
      [pscustomobject]@{ source = "pending"; note = "oryantasyon analizi henuz uretilmedi" }
    } else { $Orientation })
    supports = $(if ($null -eq $Supports) {
      [pscustomobject]@{ source = "pending"; note = "destek karari henuz uretilmedi" }
    } else { $Supports })
    slicer    = [pscustomobject]@{ name = "OrcaSlicer"; exe = $ready.slicer_exe;
                  available = ([string]$ready.slicer_exe -ne "") }
    artifact  = [pscustomobject]@{ gcode = $null; note = "G-code uretilmedi (gate kapali veya slice calismadi)" }
    validation = [pscustomobject]@{ readiness = $ready.status; missing = @($ready.missing) }
    status    = $status
  }
  $jp = Join-Path $jobDir "job.json"
  $job | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jp -Encoding UTF8
  return [pscustomobject]@{ job_id = $JobId; path = $jp; status = $status; missing = @($ready.missing) }
}
