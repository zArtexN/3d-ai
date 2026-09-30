<#
.SYNOPSIS
  Phase 10: yapisal operasyon logu (JSONL). Sadece zaman/durum yazar; secret tasimaz.
#>

function Write-OpLog($ProjectDir, $Stage, $Engine, $Operation, $DurationMs, $Status, $ErrorText = "") {
  try {
    $ld = Join-Path $ProjectDir "logs"
    New-Item -ItemType Directory -Force -Path $ld | Out-Null
    $rec = [pscustomobject]@{
      timestamp = ((Get-Date).ToUniversalTime().ToString("o"))
      stage = [string]$Stage; engine = [string]$Engine; operation = [string]$Operation
      duration_ms = [long]$DurationMs; status = [string]$Status; error = [string]$ErrorText
    }
    (($rec | ConvertTo-Json -Compress) + "`r`n") | Add-Content -LiteralPath (Join-Path $ld "ops.jsonl") -Encoding UTF8
  } catch { }
}
