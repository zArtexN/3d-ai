<#
.SYNOPSIS
  Engine registry loader (Phase 5).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok.
  Dis kok: THREE_D_AI_EXTERNAL env, yoksa repo-root kardesi 3D-AI-External.
#>

function Get-ExternalRoot {
  $ev = [System.Environment]::GetEnvironmentVariable("THREE_D_AI_EXTERNAL")
  if (-not [string]::IsNullOrWhiteSpace($ev)) { return $ev }
  $enginesDir = $PSScriptRoot
  $engineDir = Split-Path -Parent $enginesDir
  $root = Split-Path -Parent $engineDir
  $parent = Split-Path -Parent $root
  return (Join-Path $parent "3D-AI-External")
}

function Get-EngineRegistry {
  $p = Join-Path $PSScriptRoot "engines.json"
  if (-not (Test-Path -LiteralPath $p)) { throw "engine registry bulunamadi" }
  return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json)
}

function Get-Engine($registry, $id) {
  foreach ($e in @($registry.engines)) {
    if ([string]$e.id -eq [string]$id) { return $e }
  }
  return $null
}

function Get-EngineHealth($registry, $id) {
  $e = Get-Engine $registry $id
  if ($null -eq $e) {
    return @{ status = "UNSUPPORTED"; reason = ("bilinmeyen engine: " + $id) }
  }
  if ([string]$e.adapter -eq "") {
    return @{ status = [string]$e.status; reason = [string]$e.notes }
  }
  $ad = Join-Path $PSScriptRoot ([string]$e.adapter)
  if (-not (Test-Path -LiteralPath $ad)) {
    return @{ status = "NOT_READY"; reason = "adapter dosyasi yok" }
  }
  try {
    . $ad
    $fn = ([string]$id).Substring(0, 1).ToUpperInvariant() + ([string]$id).Substring(1) + "-Health"
    if ($id -eq "orcaslicer") { $fn = "Orca-Health" }
    $h = & $fn
    return $h
  } catch {
    return @{ status = "NOT_READY"; reason = [string]$_.Exception.Message }
  }
}
