<#
.SYNOPSIS
  Blender executable yolunu cozer (portable sira).
.DESCRIPTION
  Sira:
    1. settings.local.json -> tools.blender
    2. settings.json       -> tools.blender
    3. $env:BLENDER_EXE
    4. proje ici tools/blender/ klasoru (portable)
    5. Windows PATH
    6. bilinen standart kurulum konumlari
  Bulunamazsa hic cikti vermeden calismayi bitirir (exit 1).
  Bulunamazsa caller NOT_AVAILABLE olarak isleyebilir.
.EXAMPLE
  $exe = & scripts\Resolve-Blender.ps1 2>$null
  if (!$exe) { "Blender NOT_AVAILABLE" }
#>

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

function Get-ToolSetting($key) {
  foreach ($f in @((Join-Path $Root "settings.local.json"), (Join-Path $Root "settings.json"))) {
    if (Test-Path -LiteralPath $f) {
      try {
        $j = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json
        if ($j.tools -and $j.tools.$key -and [string]$j.tools.$key -ne "") { return [string]$j.tools.$key }
      } catch { }
    }
  }
  return $null
}

$candidates = New-Object System.Collections.Generic.List[string]

$s = Get-ToolSetting "blender"
if ($s) { $candidates.Add($s) }

if ($env:BLENDER_EXE) { $candidates.Add($env:BLENDER_EXE) }

$toolsDir = Join-Path $Root "tools"
foreach ($n in @("blender.exe", "blender")) {
  $p = Join-Path $toolsDir (Join-Path "blender" $n)
  if (Test-Path -LiteralPath $p) { $candidates.Add($p) }
}

foreach ($c in $candidates) {
  if ($c -and (Test-Path -LiteralPath ([string]$c))) { Write-Output $c; exit 0 }
}

$fromPath = Get-Command blender -ErrorAction SilentlyContinue
if ($fromPath) { Write-Output $fromPath.Source; exit 0 }

# Bilinen standart kurulum konumlari (Blender versiyonlari)
$knownPaths = @(
  "C:\Program Files\Blender Foundation\Blender 4.3\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 4.1\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 4.0\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 3.6\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 3.5\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 3.4\blender.exe",
  "C:\Program Files\Blender Foundation\Blender 3.3\blender.exe",
  "C:\Program Files\Blender Foundation\Blender\blender.exe"
)
foreach ($c in $knownPaths) {
  if (Test-Path -LiteralPath $c) { Write-Output $c; exit 0 }
}

# Wildcard arama (Program Files altinda herhangi bir Blender klasoru)
foreach ($pfDir in @("C:\Program Files", "C:\Program Files (x86)")) {
  if (Test-Path -LiteralPath $pfDir) {
    $found = Get-ChildItem -LiteralPath $pfDir -Recurse -Depth 3 -Filter "blender.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { Write-Output $found.FullName; exit 0 }
  }
}

# Bulunamadi
exit 1
