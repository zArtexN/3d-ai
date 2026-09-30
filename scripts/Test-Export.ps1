<#
.SYNOPSIS
  Phase 10: export testi (sentetik proje, hizli; pipeline kosmaz).
#>
param()
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$script:pass = 0; $script:fail = 0
function Add-EXResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("exp-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
try {
  . (Join-Path $EngineDir "AiReconstruct.ps1")
  $proj = Join-Path $base "proj"
  $od = Join-Path $proj "output"
  New-Item -ItemType Directory -Force -Path $od | Out-Null
  New-MockReconMesh (Join-Path $od "body.stl") 10 10 10 | Out-Null
  Set-Content -LiteralPath (Join-Path $proj "spec.json") -Value '{"source":"fixture"}' -Encoding ASCII
  [pscustomobject]@{
    status = "NOT_PRINT_READY"
    stages = @([pscustomobject]@{ stage = "gate"; status = "BLOCKED"; output = "NOT_PRINT_READY" },
               [pscustomobject]@{ stage = "slice"; status = "SKIPPED"; output = "skipped" })
  } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $proj "orchestration.json") -Encoding UTF8

  $outd = Join-Path $base "out"
  $r = & (Join-Path $Root (Join-Path "scripts" "Export-Project.ps1")) -ProjectDir $proj -OutDir $outd 2>&1 | Out-String | ConvertFrom-Json
  $exOk = ([string]$r.status -eq "OK" -and (Test-Path -LiteralPath (Join-Path $outd "model.stl")) -and (Test-Path -LiteralPath (Join-Path $outd "project-archive.zip")))
  Add-EXResult "T-EXP-01" $exOk "stl + arsiv"
  $noGcode = (-not (Test-Path -LiteralPath (Join-Path $outd "model.gcode")))
  $skipNote = ((@($r.skipped) | Where-Object { [string]$_ -match "G-code" }).Count -gt 0)
  Add-EXResult "T-EXP-02" ($noGcode -and $skipNote) "gcode gate kapali"
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $zip = [System.IO.Compression.ZipFile]::OpenRead((Join-Path $outd "project-archive.zip"))
  $names = @($zip.Entries | ForEach-Object { $_.FullName })
  $zip.Dispose()
  $hasSpec = ($names -contains "spec.json") -and ($names -contains "body.stl")
  $noCache = ((@($names) | Where-Object { $_ -match "\.cache|secret|credential" }).Count -eq 0)
  Add-EXResult "T-EXP-03" ($hasSpec -and $noCache) "arsiv icerigi temiz"
} finally {
  if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output "----------------------------------------"
Write-Output ("EXPORT SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
