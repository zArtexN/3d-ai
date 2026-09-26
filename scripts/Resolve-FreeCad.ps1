<#
.SYNOPSIS
  FreeCAD executable yolunu cozer (portable sira). OPTIONAL arac; yoksa CAD pipeline BLOCKED olmaz.
.DESCRIPTION
  Sira: settings.local.json -> settings.json (tools.freecad, eski freeCadExe) ->
  $env:FREECAD_EXE -> tools/ -> PATH (freecadcmd, freecad) -> bilinen konumlar.
  Bulunamazsa acik hata verir; cagiran OPTIONAL olarak ele alir (WARNING).
.EXAMPLE
  $fc = & scripts\Resolve-FreeCad.ps1
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
$s = Get-ToolSetting "freecad" "freeCadExe"
if ($s) { $candidates.Add($s) }
if ($env:FREECAD_EXE) { $candidates.Add($env:FREECAD_EXE) }
$toolsDir = Join-Path $Root "tools"
foreach ($n in @("freecadcmd.exe", "freecad.exe")) {
  $p = Join-Path $toolsDir (Join-Path "freecad" $n)
  if (Test-Path -LiteralPath $p) { $candidates.Add($p) }
}
foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath $c)) { Write-Output $c; return }
}

foreach ($n in @("freecadcmd", "freecad")) {
  $fromPath = Get-Command $n -ErrorAction SilentlyContinue
  if ($fromPath) { Write-Output $fromPath.Source; return }
}

foreach ($pat in @("C:\Program Files\FreeCAD*\bin\freecadcmd.exe", "C:\Program Files\FreeCAD*\bin\freecad.exe", "C:\Program Files (x86)\FreeCAD*\bin\freecadcmd.exe")) {
  foreach ($m in (Get-Item $pat -ErrorAction SilentlyContinue)) {
    Write-Output $m.FullName; return
  }
}

throw "FreeCAD bulunamadi (OPTIONAL). OpenSCAD ile cozulebilen parametrik modellerde zorunlu degildir."
