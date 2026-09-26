<#
.SYNOPSIS
  OrcaSlicer executable yolunu cozer. SADECE bulunabilirlik kontrolu icin.
.DESCRIPTION
  PATH'e guvenmez. Sira:
    1. $env:ORCASLICER_EXE (varsa)
    2. Bilinen Windows kurulum yollari
    3. PATH fallback (orca-slicer)
  Bulunamazsa acik hata verir.
  Bu asamada G-code URETILMEZ, profil secilmez, Slice.ps1 calistirilmaz.
.EXAMPLE
  $orca = & scripts\Resolve-OrcaSlicer.ps1
#>

$ErrorActionPreference = "Stop"

$candidates = New-Object System.Collections.Generic.List[string]
if ($env:ORCASLICER_EXE) { $candidates.Add($env:ORCASLICER_EXE) }
$candidates.Add("C:\Program Files\OrcaSlicer\orca-slicer.exe")
$candidates.Add("C:\Program Files\OrcaSlicer\OrcaSlicer.exe")

foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath $c)) { Write-Output $c; return }
}

$fromPath = Get-Command orca-slicer -ErrorAction SilentlyContinue
if ($fromPath) { Write-Output $fromPath.Source; return }

throw "OrcaSlicer bulunamadi. OrcaSlicer kurun veya ORCASLICER_EXE ortam degiskenine dogrudan yolu yazin."
