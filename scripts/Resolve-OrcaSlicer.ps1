<#
.SYNOPSIS
  OrcaSlicer yolunu cozer (portable sira). SADECE detection; G-code YOK, slicing YOK.
.DESCRIPTION
  Sira: settings.local.json -> settings.json (tools.orcaslicer, eski orcaSlicerExe) ->
  $env:ORCASLICER_EXE -> tools/ -> PATH (orca-slicer) -> bilinen konumlar.
  Bulunamazsa CAD/STL pipeline calismaya DEVAM eder (OPTIONAL / NOT READY).
.EXAMPLE
  $orca = & scripts\Resolve-OrcaSlicer.ps1
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
$s = Get-ToolSetting "orcaslicer" "orcaSlicerExe"
if ($s) { $candidates.Add($s) }
if ($env:ORCASLICER_EXE) { $candidates.Add($env:ORCASLICER_EXE) }
$toolsDir = Join-Path $Root "tools"
foreach ($n in @("orca-slicer.exe", "OrcaSlicer.exe")) {
  $p = Join-Path $toolsDir (Join-Path "orcaslicer" $n)
  if (Test-Path -LiteralPath $p) { $candidates.Add($p) }
}
foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath $c)) { Write-Output $c; return }
}

$fromPath = Get-Command orca-slicer -ErrorAction SilentlyContinue
if ($fromPath) { Write-Output $fromPath.Source; return }

foreach ($c in @("C:\Program Files\OrcaSlicer\orca-slicer.exe", "C:\Program Files\OrcaSlicer\OrcaSlicer.exe")) {
  if (Test-Path -LiteralPath $c) { Write-Output $c; return }
}

throw "OrcaSlicer bulunamadi (OPTIONAL / NOT READY). CAD/STL pipeline etkilenmez."
