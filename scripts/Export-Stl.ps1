<#
.SYNOPSIS
  OpenSCAD modelini STL (+ mumkunse 3MF) formatina cevirir. SADECE modelleme asamasi.
.DESCRIPTION
  AI G-code uretmez, elle STL yazmaz. OpenSCAD CLI yoksa hata verip durur.
.EXAMPLE
  powershell -File scripts\Export-Stl.ps1 -Scad projects\ornek\cad\model.scad -OutDir projects\ornek\output
#>
param(
  [Parameter(Mandatory = $true)][string]$Scad,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [string]$OpenScadExe = "openscad"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Scad)) { throw "SCAD bulunamadi: $Scad" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

try { & $OpenScadExe --version 2>&1 | Out-Null }
catch { throw "OpenSCAD bulunamadi ('$OpenScadExe'). Lutfen OpenSCAD kurun ve PATH'e ekleyin." }

$stl = Join-Path $OutDir "model.stl"
$mf  = Join-Path $OutDir "model.3mf"

& $OpenScadExe -o $stl $Scad
if ($LASTEXITCODE -ne 0) { throw "STL export basarisiz." }

try {
  & $OpenScadExe -o $mf $Scad
  if ($LASTEXITCODE -ne 0) { Write-Warning "3MF export atlandi (OpenSCAD surumu desteklemiyor olabilir)." }
} catch { Write-Warning "3MF export atlandi: $_" }

Write-Output "OK: $stl"
