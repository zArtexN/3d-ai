<#
.SYNOPSIS
  OpenSCAD executable yolunu cozer (portable sira).
.DESCRIPTION
  Sira (§2):
    1. settings.local.json -> tools.openscad (makineye ozel, git disi)
    2. settings.json -> tools.openscad, sonra eski openScadExe anahtari
    3. $env:OPENSCAD_EXE
    4. proje ici tools/ klasoru (portable)
    5. Windows PATH
    6. bilinen standart kurulum konumlari
  Bulunamazsa manuel secim onerir (UI: Konum Sec). Cikti Export-Stl.ps1 -OpenScadExe icindir.
.EXAMPLE
  $exe = & scripts\Resolve-OpenScad.ps1
#>

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Get-ToolSetting($key, $legacy) {
  foreach ($f in @((Join-Path $Root "settings.local.json"), (Join-Path $Root "settings.json"))) {
    if (Test-Path -LiteralPath $f) {
      try {
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if ($j.tools -and $j.tools.$key) { return [string]$j.tools.$key }
        if ($legacy -and $j.$legacy) { return [string]$j.$legacy }
      } catch { }
    }
  }
  return $null
}

$candidates = New-Object System.Collections.Generic.List[string]
$s = Get-ToolSetting "openscad" "openScadExe"
if ($s) { $candidates.Add($s) }
if ($env:OPENSCAD_EXE) { $candidates.Add($env:OPENSCAD_EXE) }
$toolsDir = Join-Path $Root "tools"
foreach ($n in @("openscad.com", "openscad.exe")) {
  $p = Join-Path $toolsDir (Join-Path "openscad" $n)
  if (Test-Path -LiteralPath $p) { $candidates.Add($p) }
}
foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath $c)) { Write-Output $c; return }
}

$fromPath = Get-Command openscad -ErrorAction SilentlyContinue
if ($fromPath) { Write-Output $fromPath.Source; return }

foreach ($c in @("C:\Program Files (x86)\OpenSCAD\openscad.com", "C:\Program Files (x86)\OpenSCAD\openscad.exe", "C:\Program Files\OpenSCAD\openscad.com", "C:\Program Files\OpenSCAD\openscad.exe")) {
  if (Test-Path -LiteralPath $c) { Write-Output $c; return }
}

throw "OpenSCAD bulunamadi. CAD uretmek icin OpenSCAD kurulmali veya executable konumu secilmelidir (UI: Konum Sec / OPENSCAD_EXE)."
