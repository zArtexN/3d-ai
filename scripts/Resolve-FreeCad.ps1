<#
.SYNOPSIS
  FreeCAD executable yolunu cozer. Dogrudan path mekanizmasi (Resolve-OpenScad.ps1 ile ayni mantik).
.DESCRIPTION
  PATH'e guvenmez. Sira:
    1. $env:FREECAD_EXE (varsa)
    2. Bilinen Windows kurulum yollari (CLI olan freecadcmd.exe once, otomasyon icin)
    3. PATH fallback (freecadcmd, freecad)
  Bulunamazsa acik hata verir. Faz 3 kurali: OpenSCAD ile cozulebilen modelde FreeCAD zorunlu degil.
.EXAMPLE
  $fc = & scripts\Resolve-FreeCad.ps1
#>

$ErrorActionPreference = "Stop"

$candidates = New-Object System.Collections.Generic.List[string]
if ($env:FREECAD_EXE) { $candidates.Add($env:FREECAD_EXE) }
$candidates.Add("C:\Program Files\FreeCAD 1.1\bin\freecadcmd.exe")
$candidates.Add("C:\Program Files\FreeCAD 1.1\bin\freecad.exe")
foreach ($pat in @("C:\Program Files\FreeCAD*\bin\freecadcmd.exe", "C:\Program Files\FreeCAD*\bin\freecad.exe", "C:\Program Files (x86)\FreeCAD*\bin\freecadcmd.exe")) {
  foreach ($m in (Get-Item $pat -ErrorAction SilentlyContinue)) { $candidates.Add($m.FullName) }
}

foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath $c)) { Write-Output $c; return }
}

foreach ($n in @("freecadcmd", "freecad")) {
  $fromPath = Get-Command $n -ErrorAction SilentlyContinue
  if ($fromPath) { Write-Output $fromPath.Source; return }
}

throw "FreeCAD bulunamadi. FreeCAD kurun veya FREECAD_EXE ortam degiskenine dogrudan yolu yazin. Not: OpenSCAD ile cozulebilen parametrik modellerde FreeCAD zorunlu degildir."
