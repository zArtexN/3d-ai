<#
.SYNOPSIS
  Engine contract dispatcher (Phase 5).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok.
  Invoke-EngineOp: kayitli adaptera yonlendirir; kayitsiz engine/op icin
  UNSUPPORTED doner (asla fake success uretmez). Sonuc shape dogrulanir.
#>

function Invoke-EngineOp($registry, $engineId, $op, $params) {
  $e = Get-Engine $registry $engineId
  if ($null -eq $e) {
    return @{ status = "UNSUPPORTED"; reason = ("bilinmeyen engine: " + $engineId) }
  }
  if ([string]$e.adapter -eq "") {
    return @{ status = "UNSUPPORTED"; reason = ("adapter yok (" + [string]$e.status + "): " + [string]$e.notes) }
  }
  $ad = Join-Path $PSScriptRoot ([string]$e.adapter)
  if (-not (Test-Path -LiteralPath $ad)) {
    return @{ status = "UNSUPPORTED"; reason = "adapter dosyasi yok" }
  }
  try {
    . $ad
    $fn = ([string]$engineId).Substring(0, 1).ToUpperInvariant() + ([string]$engineId).Substring(1) + "-Invoke"
    if ($engineId -eq "orcaslicer") { $fn = "Orca-Invoke" }
    $r = & $fn $op $params
    if ($null -eq $r -or $null -eq $r.status) {
      return @{ status = "UNSUPPORTED"; reason = "adapter sonuc sekli bozuk" }
    }
    return $r
  } catch {
    return @{ status = "BLOCKED"; reason = [string]$_.Exception.Message }
  }
}
