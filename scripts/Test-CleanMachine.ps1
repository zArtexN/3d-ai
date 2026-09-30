<#
.SYNOPSIS
  Phase 10: temiz-makine davranisi (eksik bilesen = yapisal cevap, cokus yok).
.DESCRIPTION
  Makineye dokunmaz; sadece yokluk senaryolarini cagirir:
  - python yok (bozuk THREE_D_AI_EXTERNAL) -> trimesh NOT_READY, throw yok
  - slicer yok (bogus exe) -> readiness BLOCKED + slicer missing
  - printer/filament/process yok -> readiness BLOCKED, her biri ayri missing
  - profil dosyasi bozuk -> valid=false, throw yok
  - STEP motoru yok -> cad_import FAILED + 5 alanli hata
#>
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
. (Join-Path $EngineDir (Join-Path "Engines" "EngineRegistry.ps1"))
. (Join-Path $EngineDir "Test-SliceReadiness.ps1")
. (Join-Path $EngineDir "Test-Profiles.ps1")

$script:pass = 0; $script:fail = 0
function Add-CMResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

# T-CM-01: python/env yok -> trimesh NOT_READY, istisna firlatmaz.
$cm1 = $false
try {
  $env:THREE_D_AI_EXTERNAL = "Z:\yok\boyle-bir-dizin"
  $reg = Get-EngineRegistry
  $h = Get-EngineHealth $reg "trimesh"
  $cm1 = ([string]$h.status -eq "NOT_READY")
} catch { $cm1 = $false } finally { $env:THREE_D_AI_EXTERNAL = $null }
Add-CMResult "T-CM-01" $cm1 "python yok -> NOT_READY"

# T-CM-02: slicer yok -> readiness BLOCKED + slicer missing (cokus yok).
$cm2 = $false
try {
  $r = Test-SliceReadiness -ModelStl "" -PrinterJson "" -FilamentJson "" -ProcessJson "" -OrcaExe "Z:\yok\orca.exe"
  $ids = @(@($r.missing) | ForEach-Object { [string]$_.id })
  $cm2 = ([string]$r.status -eq "BLOCKED" -and ($ids -contains "slicer"))
} catch { $cm2 = $false }
Add-CMResult "T-CM-02" $cm2 "slicer yok -> BLOCKED"

# T-CM-03: profil yokluklari ayri missing id'leri.
$cm3 = $false
try {
  $r = Test-SliceReadiness -ModelStl "" -PrinterJson "" -FilamentJson "" -ProcessJson "" -OrcaExe ""
  $ids = @(@($r.missing) | ForEach-Object { [string]$_.id })
  $cm3 = (($ids -contains "printer") -and ($ids -contains "filament") -and ($ids -contains "process"))
} catch { $cm3 = $false }
Add-CMResult "T-CM-03" $cm3 "printer/filament/process missing"

# T-CM-04: bozuk profil dosyasi -> valid=false, throw yok.
$cm4 = $false
try {
  $bad = Join-Path ([System.IO.Path]::GetTempPath()) "cm-bad.json"
  Set-Content -LiteralPath $bad -Value "{bozuk" -Encoding ASCII
  $v = Test-PrinterProfile $bad
  $cm4 = (-not [bool]$v.valid -and @($v.errors).Count -gt 0)
  Remove-Item -LiteralPath $bad -Force -ErrorAction SilentlyContinue
} catch { $cm4 = $false }
Add-CMResult "T-CM-04" $cm4 "bozuk profil -> invalid"

# T-CM-05: STEP: binary olsa bile donusturucu bagli degil -> yapisal FAILED (cokus yok).
$cm5 = $false
try {
  $stepD = Join-Path ([System.IO.Path]::GetTempPath()) ("cmstep-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
  New-Item -ItemType Directory -Force -Path $stepD | Out-Null
  $stepF = Join-Path $stepD "p.step"
  Set-Content -LiteralPath $stepF -Value "ISO-10303-21;" -Encoding ASCII
  $oj = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Orchestrator.ps1") `
    -Source $stepF -ProjectName "cm-step-probe" 2>$null | Out-String | ConvertFrom-Json
  $cad = $null
  foreach ($s in @($oj.stages)) { if ([string]$s.stage -eq "cad_import") { $cad = $s } }
  $cm5 = ($null -ne $cad -and (@("FAILED", "BLOCKED") -contains [string]$cad.status) -and @($cad.errors).Count -gt 0)
  Remove-Item -LiteralPath $stepD -Recurse -Force -ErrorAction SilentlyContinue
  $pp = Join-Path $Root (Join-Path "projects" "cm-step-probe")
  if (Test-Path -LiteralPath $pp) { Remove-Item -LiteralPath $pp -Recurse -Force -ErrorAction SilentlyContinue }
} catch { $cm5 = $false }
Add-CMResult "T-CM-05" $cm5 "STEP donusturucu yok -> yapisal FAILED"

# T-CM-06: AI motoru yok -> reconstruction secimi mock'suz BLOCKED mesaji (health stub).
$cm6 = $false
try {
  $reg = Get-EngineRegistry
  $h = Get-EngineHealth $reg "trellis"
  $cm6 = ([string]$h.status -ne "READY")
} catch { $cm6 = $false }
Add-CMResult "T-CM-06" $cm6 "AI motoru MACHINE_LIMITED"

Write-Output "----------------------------------------"
Write-Output ("CLEANMACHINE SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
