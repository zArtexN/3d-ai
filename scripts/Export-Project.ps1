<#
.SYNOPSIS
  Phase 10: proje export (STL/3MF/arsiv/rapor; G-code SADECE kapi aciksa).
.DESCRIPTION
  Export-Project -ProjectDir <proje> -OutDir <hedef>:
  - model STL/3MF kopyalari (varsa oriented/mesh ciktilari)
  - STEP: donusturucu yoksa DURUSTce atlanir (uydurma yok)
  - proje arsivi (zip): spec, version history, measurements, models, reports,
    reproducibility config; HARIC: secrets, credentials, .cache, logs/output agirliklari
  - G-code: orchestration gate PRINT_READY + gcode dosyasi varsa kopyalanir, yoksa BLOCKED
  Donus: @{ status; exported[]; skipped[]; errors[] } (JSON stdout).
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [Parameter(Mandatory = $true)][string]$OutDir
)

$ErrorActionPreference = "Stop"

$exported = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList
$errors = New-Object System.Collections.ArrayList

if (-not (Test-Path -LiteralPath $ProjectDir)) {
  Write-Output '{"status":"FAILED","reason":"proje bulunamadi"}'
  exit 2
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Export-Copy($src, $dstName) {
  if ([string]$src -ne "" -and (Test-Path -LiteralPath ([string]$src))) {
    Copy-Item -LiteralPath ([string]$src) -Destination (Join-Path $OutDir $dstName) -Force
    $exported.Add($dstName) | Out-Null
    return $true
  }
  return $false
}

$oj = Join-Path $ProjectDir "orchestration.json"
$gate = ""
$gcode = ""
if (Test-Path -LiteralPath $oj) {
  try {
    $o = Get-Content -LiteralPath $oj -Raw | ConvertFrom-Json
    foreach ($s in @($o.stages)) {
      if ([string]$s.stage -eq "gate") { $gate = [string]$s.output }
      if ([string]$s.stage -eq "slice" -and [string]$s.status -eq "OK") { $gcode = [string]$s.output }
    }
  } catch { }
}
$mesh = $null
foreach ($c in @((Join-Path $ProjectDir "oriented.stl"), (Join-Path $ProjectDir "repaired.stl"))) {
  if (Test-Path -LiteralPath $c) { $mesh = $c; break }
}
if ($null -eq $mesh) {
  $od = Join-Path $ProjectDir "output"
  if (Test-Path -LiteralPath $od) {
    $f = Get-ChildItem -LiteralPath $od -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq ".stl" -or $_.Extension -eq ".3mf" } | Select-Object -First 1
    if ($f) { $mesh = $f.FullName }
  }
}
if ($null -ne $mesh) {
  $ext = ([System.IO.Path]::GetExtension($mesh)).ToLowerInvariant()
  Export-Copy $mesh ("model" + $ext) | Out-Null
} else { $skipped.Add("model (mesh yok)") | Out-Null }
$skipped.Add("STEP (donusturucu bagli degil)") | Out-Null

if ($gate -eq "PRINT_READY" -and $gcode -ne "" -and (Test-Path -LiteralPath $gcode)) {
  Export-Copy $gcode "model.gcode" | Out-Null
} else {
  $skipped.Add("G-code (gate kapali: " + $(if ($gate -eq "") { "kapi calismadi" } else { $gate }) + ")") | Out-Null
}

$zipTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("export-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $zipTmp | Out-Null
try {
  foreach ($n in @("spec.json", "measured-spec.json", "pipeline-result.json", "orchestration.json",
                   "printability.json", "support.json", "explicit-facts.json", "input.json")) {
    $f = Join-Path $ProjectDir $n
    if (Test-Path -LiteralPath $f) { Copy-Item -LiteralPath $f -Destination (Join-Path $zipTmp $n) -Force }
  }
  foreach ($dn in @("versions", "candidates")) {
    $d = Join-Path $ProjectDir $dn
    if (Test-Path -LiteralPath $d) {
      Copy-Item -LiteralPath $d -Destination (Join-Path $zipTmp $dn) -Recurse -Force
    }
  }
  if ($null -ne $mesh) { Copy-Item -LiteralPath $mesh -Destination (Join-Path $zipTmp ([System.IO.Path]::GetFileName($mesh))) -Force }
  $zipPath = Join-Path $OutDir "project-archive.zip"
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  [System.IO.Compression.ZipFile]::CreateFromDirectory($zipTmp, $zipPath)
  $exported.Add("project-archive.zip") | Out-Null
} catch {
  $errors.Add("arsiv yazilamadi: " + $_.Exception.Message) | Out-Null
} finally {
  Remove-Item -LiteralPath $zipTmp -Recurse -Force -ErrorAction SilentlyContinue
}

$st = "OK"
if (@($errors).Count -gt 0) { $st = "FAILED" }
[pscustomobject]@{ status = $st; exported = @($exported.ToArray()); skipped = @($skipped.ToArray()); errors = @($errors.ToArray()) } | ConvertTo-Json -Depth 5
if ($st -eq "FAILED") { exit 2 }
