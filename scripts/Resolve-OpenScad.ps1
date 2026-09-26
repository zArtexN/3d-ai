<#
.SYNOPSIS
  OpenSCAD executable yolunu cozer. Dogrudan path mekanizmasi (Faz 3 kural 17).
.DESCRIPTION
  PATH'e guvenmez. Sira:
    1. $env:OPENSCAD_EXE (varsa)
    2. Bilinen kurulum yollari (bu makinede dogrulanan once)
    3. PATH fallback (Get-Command openscad)
  Bulunamazsa hata verir. Cikti, Export-Stl.ps1'e -OpenScadExe olarak verilir.
  Export-Stl.ps1'e DOKUNMAZ.
.EXAMPLE
  $exe = & scripts\Resolve-OpenScad.ps1
  powershell -File scripts\Export-Stl.ps1 -Scad projects\x\cad\model.scad -OutDir projects\x\output -OpenScadExe $exe
#>

$ErrorActionPreference = "Stop"

$candidates = New-Object System.Collections.Generic.List[string]
if ($env:OPENSCAD_EXE) { $candidates.Add($env:OPENSCAD_EXE) }
$candidates.Add("C:\Program Files (x86)\OpenSCAD\openscad.com")
$candidates.Add("C:\Program Files (x86)\OpenSCAD\openscad.exe")
$candidates.Add("C:\Program Files\OpenSCAD\openscad.com")
$candidates.Add("C:\Program Files\OpenSCAD\openscad.exe")

foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath $c)) { Write-Output $c; return }
}

$fromPath = Get-Command openscad -ErrorAction SilentlyContinue
if ($fromPath) { Write-Output $fromPath.Source; return }

throw "OpenSCAD bulunamadi. OpenSCAD kurun veya OPENSCAD_EXE ortam degiskenine dogrudan yolu yazin."
