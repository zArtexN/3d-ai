<#
.SYNOPSIS
  Phase 10: guvenli onbellek anahtari (girdi-hash + motor-surum + config + spec-surum).
#>

function Get-CacheKey($InputPath, $EngineId, $EngineVersion, $ConfigText = "", $SpecVersion = "") {
  $h = ""
  if ($InputPath -ne "" -and (Test-Path -LiteralPath ([string]$InputPath))) {
    try {
      $md5 = [System.Security.Cryptography.MD5]::Create()
      $fs = [System.IO.File]::OpenRead([string]$InputPath)
      try { $h = ([System.BitConverter]::ToString($md5.ComputeHash($fs)) -replace '-', '') }
      finally { $fs.Close() }
    } catch { $h = "" }
  }
  $raw = ("in=" + $h + "|eng=" + [string]$EngineId + "|ver=" + [string]$EngineVersion +
          "|cfg=" + [string]$ConfigText + "|spec=" + [string]$SpecVersion)
  $md5b = [System.Security.Cryptography.MD5]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
  return ([System.BitConverter]::ToString($md5b.ComputeHash($bytes)) -replace '-', '')
}
