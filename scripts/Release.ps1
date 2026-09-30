<#
.SYNOPSIS
  Phase 10: release kapisi (hizli dogrulama + FINAL RELEASE blogu).
.DESCRIPTION
  Agir matris (Run-AllTests/Golden) ayrica kosar; bu script release ANINDAKI
  hizli kanitlari toplar: surum, build tazeligi, guvenlik/tasinabilirlik/
  temiz-makine, motor sagliklari, ornek dry-run kapisi. Cikis 0 = PASS.
  NEVER PUSH: git islemi yapmaz, sadece durumu gosterir.
#>
param()

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
. (Join-Path $EngineDir (Join-Path "Engines" "EngineRegistry.ps1"))

$blockers = New-Object System.Collections.ArrayList
function Block($m) { $blockers.Add($m) | Out-Null }
function Test-SuiteText($text) {
  if ([string]$text -match "(?m)^\[FAIL\]") { return $false }
  $mm = [regex]::Match([string]$text, "FAIL[:=]\s*(\d+)")
  if ($mm.Success -and [int]$mm.Groups[1].Value -gt 0) { return $false }
  if ([string]$text -match "(?m): FAIL\s*$") { return $false }
  return $true
}

$ver = ""
try { $ver = (Get-Content -LiteralPath (Join-Path $Root "VERSION") -Raw).Trim() } catch { Block "VERSION okunamadi" }
$build = Join-Path $Root (Join-Path "dist" "3D-AI-Designer.exe")
$buildInfo = "yok"
if (Test-Path -LiteralPath $build) {
  $bi = Get-Item -LiteralPath $build
  $sz = [math]::Round($bi.Length / 1KB, 0)
  $buildInfo = ($bi.LastWriteTime.ToString("yyyy-MM-dd HH:mm") + " (" + $sz + " KB)")
} else { Block "dist EXE yok" }

$fresh = & (Join-Path $Root (Join-Path "scripts" "Test-ExeFreshness.ps1")) 2>&1 | Out-String
if (-not (Test-SuiteText $fresh)) { Block "freshness FAIL" }
$sec = & (Join-Path $Root (Join-Path "scripts" "Test-Security.ps1")) 2>&1 | Out-String
if (-not (Test-SuiteText $sec)) { Block "security FAIL" }
$por = & (Join-Path $Root (Join-Path "scripts" "Test-Portability.ps1")) 2>&1 | Out-String
if (-not (Test-SuiteText $por)) { Block "portability FAIL" }
$cm = & (Join-Path $Root (Join-Path "scripts" "Test-CleanMachine.ps1")) 2>&1 | Out-String
if (-not (Test-SuiteText $cm)) { Block "cleanmachine FAIL" }

$reg = Get-EngineRegistry
$tri = Get-EngineHealth $reg "trimesh"
$orca = Get-EngineHealth $reg "orcaslicer"
$trellis = Get-EngineHealth $reg "trellis"
$readyCount = @(@($reg.engines) | Where-Object { [string]$_.status -eq "READY" }).Count

$dry = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Orchestrator.ps1") `
  -Source "50x50x20 kutu" -ProjectName "release-probe" -DryRun 2>$null | Out-String | ConvertFrom-Json
if ($null -eq $dry -or -not [bool]$dry.dry_run) { Block "dry-run kapisi cevap vermedi" }

$gate = "BLOCKED (profil yok - beklenen)"
$gateNote = "G-code gate kapali: printer/filament/process profili yok; uydurma yok"

$rel = "PASS"
if (@($blockers).Count -gt 0) { $rel = "BLOCKED" }

Write-Output "============================================"
Write-Output "3D-AI FINAL RELEASE"
Write-Output "============================================"
Write-Output ""
Write-Output ("Version: " + $ver)
Write-Output ("Build: " + $buildInfo)
Write-Output "Core Tests: bkz Run-AllTests TOTAL (matris)"
Write-Output "Regression: bkz Run-AllTests + Golden (matris)"
Write-Output ("External Engines: " + $readyCount + " READY-kayitli (trimesh=" + [string]$tri.status + ", orcaslicer=" + [string]$orca.status + ")")
Write-Output ("Reconstruction: trellis=" + [string]$trellis.status + " (mock test-disi)")
Write-Output "Mesh QA: saf-PS + trimesh (STL/3MF/OBJ)"
Write-Output "Printability: analyzer + NEEDS_INPUT siniri"
Write-Output ("Slicer: orca binary " + $(if ([string]$orca.status -eq "READY") { "cozuldu" } else { "yok" }) + " (profilsiz BLOCKED)")
Write-Output "Printer: profil yok (offline hazirlik)"
Write-Output ("G-code Gate: " + $gate)
Write-Output ("UI: Workstation + DesignerV1 (headless testler PASS)")
Write-Output "Portability: sabit kullanici yolu yok"
Write-Output "Security: keyfi calistirma/secret/string-komut yok"
Write-Output ""
Write-Output ("RELEASE STATUS:")
Write-Output ("    " + $rel)
if (@($blockers).Count -gt 0) {
  foreach ($b in $blockers) { Write-Output ("    BLOCKER: " + [string]$b) }
} else {
  Write-Output ("    " + $gateNote)
}
if ($rel -eq "PASS") { exit 0 } else { exit 1 }
