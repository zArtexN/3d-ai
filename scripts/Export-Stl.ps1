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
  [string]$OpenScadExe = "openscad",
  [int]$TimeoutSec = 300
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $Scad)) { throw "SCAD bulunamadi: $Scad" }
if ([string]$Scad -match '"' -or [string]$OutDir -match '"') { throw "guvenlik: yolda tirnak karakteri reddedildi" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Invoke-WithTimeout($exe, $arguments, $timeoutSec, $label) {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $exe
  $psi.Arguments = $arguments
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.CreateNoWindow = $true
  $proc = [System.Diagnostics.Process]::Start($psi)
  if (-not $proc.WaitForExit($timeoutSec * 1000)) {
    try { $proc.Kill() } catch { }
    throw ($label + " zaman asimina ugradi (" + $timeoutSec + " sn); islem durduruldu.")
  }
  if ($proc.ExitCode -ne 0) {
    $err = ""
    try { $err = $proc.StandardError.ReadToEnd() } catch { }
    throw ($label + " basarisiz (kod " + $proc.ExitCode + "). " + $err)
  }
}

try { & $OpenScadExe --version 2>&1 | Out-Null }
catch { throw "OpenSCAD bulunamadi ('$OpenScadExe'). Lutfen OpenSCAD kurun ve PATH'e ekleyin." }

$stl = Join-Path $OutDir "model.stl"
$mf  = Join-Path $OutDir "model.3mf"

Invoke-WithTimeout $OpenScadExe ('-o "' + $stl + '" "' + $Scad + '"') $TimeoutSec "STL export"
try {
  Invoke-WithTimeout $OpenScadExe ('-o "' + $mf + '" "' + $Scad + '"') $TimeoutSec "3MF export"
} catch { Write-Warning ("3MF export atlandi: " + $_.Exception.Message) }

Write-Output "OK: $stl"
