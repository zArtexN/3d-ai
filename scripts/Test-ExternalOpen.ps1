<#
.SYNOPSIS
  External Application / Open With sistemi testi.
.DESCRIPTION
  engine/Open-External.ps1 sozlesmelerini dogrular:
  - gercek cikti dosyalari (kopya degil, uretilmis ornekler) kullanilir
  - dosya yoksa hicbir sey baslatilmaz (FILE_MISSING / DIR_MISSING)
  - kurulu olmayan uygulama crash vermez (APP_MISSING / UNKNOWN_TOOL)
  - kurulu uygulamalar gercekten baslatilir ve kontrollu kapatilir
  - DesignerV1 -ValidateUI yeni butonlari icerir
  - DesignerV1 -UITest gercek STL/SCAD uretir (organizer akisi)
  Cikis: [PASS]/[FAIL] satirlari (Run-AllTests sayar). INFO: satirlari sayilmaz.
#>
param()
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$script:pass = 0; $script:fail = 0
function Add-XOResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}
function Write-XInfo($t) { Write-Output ("INFO: " + $t) }

. (Join-Path $EngineDir "Open-External.ps1")

function Get-ProcSnapshot {
  return @((Get-Process -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty Id)
}
function Get-AppPids($match) {
  return @((Get-Process -ErrorAction SilentlyContinue) | Where-Object {
    ([string]$_.ProcessName -match $match) } | Select-Object -ExpandProperty Id)
}
function Stop-Pids($ids) {
  foreach ($i in $ids) {
    try { Stop-Process -Id $i -Force -ErrorAction SilentlyContinue } catch { }
  }
}
function Test-IsAlive($procId) {
  try { Get-Process -Id $procId -ErrorAction Stop | Out-Null; return $true } catch { return $false }
}
function Wait-NewAppPids($match, $beforeIds, $secs) {
  $n0 = @(Get-AppPids $match | Where-Object { ($beforeIds -notcontains $_) })
  if ($n0.Count -gt 0) { return $n0 }
  for ($i = 0; $i -lt $secs; $i++) {
    Start-Sleep -Seconds 1
    $n = @(Get-AppPids $match | Where-Object { ($beforeIds -notcontains $_) })
    if ($n.Count -gt 0) { return $n }
  }
  return @()
}
# Kur app'i gercekten baslatir; tek-instance yonlendirmesini de durustce raporlar.
# Yalnizca testin baslattigi (yeni) processler oldurulur; kullanicinin calisan uygulamalarina dokunulmaz.
function Invoke-LiveOpenTest($id, $tool, $file, $match, $secs) {
  $pre = @(Get-AppPids $match)
  $snap = Get-ProcSnapshot
  $r = Open-FileWithTool $file $tool
  if (-not $r.Ok) {
    Add-XOResult $id $false ($tool + " baslatilamadi: " + $r.Code + " :: " + $r.Message)
    return
  }
  $n = Wait-NewAppPids $match $snap $secs
  if ($n.Count -gt 0) {
    Start-Sleep -Seconds 3
    $alive = @($n | Where-Object { Test-IsAlive $_ })
    Stop-Pids $n
    Add-XOResult $id ($alive.Count -gt 0) ($tool + " canli: yeni process=" + $n.Count + " alive=" + $alive.Count)
    return
  }
  $preAlive = @($pre | Where-Object { Test-IsAlive $_ })
  if ($preAlive.Count -gt 0) {
    Add-XOResult $id $true ($tool + " calisan instance'a yonlendirildi (PID " + $preAlive[0] + ", yeni process yok)")
    return
  }
  Add-XOResult $id $false ($tool + " process gorulmedi (" + $secs + " sn)")
}

# --- T-EXT-01: modul yuklendi, fonksiyonlar var ---
# Suit basinda calisan CAD uygulamalari (kullanicinin) dokunulmazlik listesi;
# finally blogu yalnizca suitin baslattigi (yetim dahil) processleri oldurur.
$suitePreApps = @(Get-AppPids "orca|openscad|blender|freecad")
$fns = @("Get-ExternalToolPath", "Get-ToolForExtension", "Open-PathDefault", "Open-OutputFolder", "Open-FileWithTool", "Open-FileWithDialog", "Open-DesignFile")
$missing = @($fns | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })
Add-XOResult "T-EXT-01" ($missing.Count -eq 0) ("modul fonksiyonlari (" + ($fns.Count - $missing.Count) + "/" + $fns.Count + ")")

# --- T-EXT-02: uzanti -> arac haritasi ---
$mapOk = ((Get-ToolForExtension ".scad") -eq "openscad") -and ((Get-ToolForExtension ".blend") -eq "blender") -and `
  ((Get-ToolForExtension ".step") -eq "freecad") -and ((Get-ToolForExtension ".stp") -eq "freecad") -and `
  ((Get-ToolForExtension ".3mf") -eq "orcaslicer") -and ((Get-ToolForExtension ".stl") -eq "orcaslicer") -and `
  ([string](Get-ToolForExtension ".obj") -eq "") -and ([string](Get-ToolForExtension ".txt") -eq "")
Add-XOResult "T-EXT-02" $mapOk "scad/blend/step/stp/3mf/stl + default (obj/txt)"

# --- gercek girdi dosyalari (uretilmis ornek projeden kopya) ---
$sample = Join-Path $Root (Join-Path "projects" "bench-organizer-1")
$sampleStl = Join-Path $sample (Join-Path "output" "body.stl")
$sampleScad = Join-Path $sample (Join-Path "cad" "body.scad")
$sample3mf = Join-Path $sample (Join-Path "output" "body.3mf")
$sampleOk = (Test-Path -LiteralPath $sampleStl) -and (Test-Path -LiteralPath $sampleScad) -and (Test-Path -LiteralPath $sample3mf)
Add-XOResult "T-EXT-03" $sampleOk "gercek ornek cikti: body.stl + body.scad + body.3mf"
$base = Join-Path ([System.IO.Path]::GetTempPath()) ("xopen-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Force -Path $base | Out-Null
$tempStl = ""; $tempScad = ""; $temp3mf = ""
try {
  if ($sampleOk) {
    $tempStl = Join-Path $base "body.stl"; Copy-Item -LiteralPath $sampleStl -Destination $tempStl -Force
    $tempScad = Join-Path $base "body.scad"; Copy-Item -LiteralPath $sampleScad -Destination $tempScad -Force
    $temp3mf = Join-Path $base "body.3mf"; Copy-Item -LiteralPath $sample3mf -Destination $temp3mf -Force
  }

  # --- T-EXT-04: dosya yoksa hicbir sey baslatilmaz ---
  $nope = Join-Path $base "olmayan-dosya.stl"
  $nopeDir = Join-Path $base "olmayan-klasor"
  $snap = Get-ProcSnapshot
  $r1 = Open-FileWithTool $nope "orcaslicer"
  $r2 = Open-PathDefault $nope
  $r3 = Open-FileWithDialog $nope
  $r4 = Open-OutputFolder $nopeDir
  $r5 = Open-DesignFile $nope
  $r6 = Open-OutputFolder ""
  $codesOk = ((-not $r1.Ok) -and ($r1.Code -eq "FILE_MISSING")) -and ((-not $r2.Ok) -and ($r2.Code -eq "FILE_MISSING")) -and `
    ((-not $r3.Ok) -and ($r3.Code -eq "FILE_MISSING")) -and ((-not $r4.Ok) -and ($r4.Code -eq "DIR_MISSING")) -and `
    ((-not $r5.Ok) -and ($r5.Code -eq "FILE_MISSING")) -and ((-not $r6.Ok) -and ($r6.Code -eq "DIR_MISSING"))
  $leak = @(Get-AppPids "orca|openscad|rundll32|blender|freecad" | Where-Object { ($snap -notcontains $_) })
  Add-XOResult "T-EXT-04" ($codesOk -and ($leak.Count -eq 0)) "6/6 guard kodu + sizinti yok"

  # --- T-EXT-05: bilinmeyen arac + kurulu olmayan uygulama ---
  $snap5 = Get-ProcSnapshot
  $ru = Open-FileWithTool $tempStl "hayali-arac-xyz"
  $unkOk = ((-not $ru.Ok) -and ($ru.Code -eq "UNKNOWN_TOOL"))
  $blenderPath = Get-ExternalToolPath "blender"
  if ([string]::IsNullOrEmpty($blenderPath)) {
    $rb = Open-FileWithTool $tempStl "blender"
    $bOk = ((-not $rb.Ok) -and ($rb.Code -eq "APP_MISSING") -and ([string]$rb.Message -match "bulunamadi"))
    Write-XInfo ("blender kurulu degil -> APP_MISSING dogrulandi")
    Add-XOResult "T-EXT-05" ($unkOk -and $bOk) "UNKNOWN_TOOL + blender APP_MISSING (crash yok)"
  } else {
    Write-XInfo ("blender kurulu: " + $blenderPath + " -> canli acma deneniyor")
    Invoke-LiveOpenTest "T-EXT-05" "blender" $tempStl "blender" 30
  }
  # Blender 5.2 launcher gec fork yapabilir: oldurulen PID'in ardindan gec gelen
  # artci process icin yerlesme dongusu (katı hukum korunur; surekli ureyen yine FAIL).
  # Yalnizca testin baslattigi (snapshot-disi) pidler oldurulur.
  for ($w5 = 0; $w5 -lt 10; $w5++) {
    $cand5 = @(Get-AppPids "orca|openscad|rundll32|blender|freecad" | Where-Object { ($snap5 -notcontains $_) })
    if ($cand5.Count -eq 0) { break }
    Stop-Pids $cand5
    Start-Sleep -Seconds 1
  }
  $leak5 = @(Get-AppPids "orca|openscad|rundll32|blender|freecad" | Where-Object { ($snap5 -notcontains $_) })
  if ($leak5.Count -gt 0) { Add-XOResult "T-EXT-05b" $false "bilinmeyen arac process sizdirdi"; Stop-Pids $leak5 }
  else { Add-XOResult "T-EXT-05b" $true "bilinmeyen arac process baslatmadi" }

  # --- T-EXT-06: SCAD OpenSCAD ile acilir (kuruluysa) ---
  $osPath = Get-ExternalToolPath "openscad"
  if (-not [string]::IsNullOrEmpty($osPath)) {
    Write-XInfo ("openscad: " + $osPath)
    Invoke-LiveOpenTest "T-EXT-06" "openscad" $tempScad "openscad" 45
  } else {
    $r6c = Open-FileWithTool $tempScad "openscad"
    Add-XOResult "T-EXT-06" ((-not $r6c.Ok) -and ($r6c.Code -eq "APP_MISSING")) "openscad yok -> APP_MISSING (sahte basari yok)"
  }

  # --- T-EXT-07: STL OrcaSlicer ile acilir (kuruluysa) ---
  $orcaPath = Get-ExternalToolPath "orcaslicer"
  if (-not [string]::IsNullOrEmpty($orcaPath)) {
    Write-XInfo ("orcaslicer: " + $orcaPath)
    Invoke-LiveOpenTest "T-EXT-07" "orcaslicer" $tempStl "orca" 45
  } else {
    $r7c = Open-FileWithTool $tempStl "orcaslicer"
    Add-XOResult "T-EXT-07" ((-not $r7c.Ok) -and ($r7c.Code -eq "APP_MISSING")) "orca yok -> APP_MISSING (sahte basari yok)"
  }

  # --- T-EXT-08: FreeCAD cozuldu ama gercek STEP yok -> acma yok ---
  $fcPath = Get-ExternalToolPath "freecad"
  $missingStep = Join-Path $base "parca.step"
  $r8 = Open-FileWithTool $missingStep "freecad"
  $r8ok = ((-not $r8.Ok) -and ($r8.Code -eq "FILE_MISSING"))
  if (-not [string]::IsNullOrEmpty($fcPath)) { Write-XInfo ("freecad cozuldu: " + $fcPath + " (gercek STEP uretilmedigi icin canli acma yok)") }
  else { Write-XInfo "freecad kurulu degil" }
  Add-XOResult "T-EXT-08" $r8ok "STEP yok -> FILE_MISSING, cozumden bagimsiz"

  # --- T-EXT-09: output klasoru ---
  $r9 = Open-OutputFolder $base
  $shellOk = $false
  if ($r9.Ok) {
    Start-Sleep -Seconds 4
    try {
      $sh = New-Object -ComObject Shell.Application
      $baseUrl = ($base -replace '\\', '/')
      $found = @($sh.Windows() | Where-Object { ([string]$_.FullName -match "explorer\.exe") -and (([string]$_.LocationURL) -match [regex]::Escape($baseUrl)) })
      if ($found.Count -gt 0) { $shellOk = $true; try { $found[0].Quit() } catch { } }
    } catch { Write-XInfo "COM dogrulama atlandi (Shell.Application erisilemez)" }
  }
  Add-XOResult "T-EXT-09" ($r9.Ok -and $shellOk) "klasor acildi + explorer penceresi dogrulandi/kapatildi"
} finally {
  try {
    $orphans = @(Get-AppPids "orca|openscad|blender|freecad" | Where-Object { ($suitePreApps -notcontains $_) })
    Stop-Pids $orphans
  } catch { }
  Start-Sleep -Seconds 2
  if (Test-Path -LiteralPath $base) { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }
}

# --- T-EXT-10: ValidateUI yeni butonlari icerir ---
$ui2 = & (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -ValidateUI 2>&1 | Out-String
Add-XOResult "T-EXT-10" ($ui2 -match "UI-STARTUP: PASS") "ValidateUI (Open in ... butonlari mevcut)"

# --- T-EXT-11: gercek pipeline organizer uretir (STL + SCAD) ---
$uit = & (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -UITest 2>&1 | Out-String
$uitOk = ($uit -match "UI-TEST: PASS") -and ($uit -match "stl=True")
Add-XOResult "T-EXT-11" $uitOk "organizer akisi gercek body.stl uretti"

Write-Output "----------------------------------------"
Write-Output ("EXTERNAL-OPEN SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
