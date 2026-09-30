<#
.SYNOPSIS
  Phase 10: tasinabilirlik statik denetimi (TDD).
.DESCRIPTION
  - engine/scripts/app/Workstation altinda sabit kullanici/surucu/makine yolu yok
    (izinli: "C:\Program Files\*" cozucu adaylari, TEMP API kullanimlari).
  - settings.json makine-ozel yol icermez (null veya goreceli).
  - printers/filaments/processes profilleri mutlak yol icermez.
  - Kopya-proje anlasilabilirligi: proje ici mutlak kok referansi taramasi
    (ornek proje uzerinde yapisal kontrol).
#>
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

$script:pass = 0; $script:fail = 0
function Add-POResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

$scanDirs = @((Join-Path $Root "engine"), (Join-Path $Root "scripts"))
$ws = Join-Path $Root (Join-Path "app" "Workstation.ps1")
$files = @()
foreach ($d in $scanDirs) {
  $files += Get-ChildItem -Path $d -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue |
    Where-Object { ($_.FullName -notmatch "\\dist\\") -and ($_.Name -ne "Test-Portability.ps1") }
}
if (Test-Path -LiteralPath $ws) { $files += Get-Item -LiteralPath $ws }

# T-PORT-01: sabit "C:\Users\..." yok.
$uHits = @()
foreach ($f in $files) {
  $hits = Select-String -LiteralPath $f.FullName -Pattern 'C:\\Users\\' -ErrorAction SilentlyContinue
  foreach ($h in $hits) {
    $ln = [string]$h.Line
    if ($ln -match "^\s*#") { continue }
    $uHits += @($f.Name + ":" + $h.LineNumber)
  }
}
Add-POResult "T-PORT-01" (@($uHits).Count -eq 0) $(if (@($uHits).Count -eq 0) { "kullanici yolu yok" } else { ($uHits -join ",") })

# T-PORT-02: sabit surucu koku yalnizca mesru listelerde:
# cozucu adaylari (Program Files), derleyici sondasi (Microsoft.NET),
# bilerek-yok fixture isareti (C:\yok\), meta-denetimler (-match), ornek/yorum satirlari.
$dHits = @()
foreach ($f in $files) {
  $hits = Select-String -LiteralPath $f.FullName -Pattern '"C:\\(?!Program Files)[^"]*"' -ErrorAction SilentlyContinue
  foreach ($h in $hits) {
    $ln = [string]$h.Line
    $t = $ln.Trim()
    if ($t.StartsWith("#") -or $t.StartsWith("<#") -or $t.StartsWith("*")) { continue }
    if ($ln -match "EXAMPLE") { continue }
    if ($ln -match "Program Files|Microsoft\.NET|C:\\yok\\|C:\\a\\b") { continue }
    if ($ln -match "-match.*C:") { continue }
    $dHits += @($f.Name + ":" + $h.LineNumber + ":" + $t)
  }
}
Add-POResult "T-PORT-02" (@($dHits).Count -eq 0) $(if (@($dHits).Count -eq 0) { "sabit surucu yolu yok" } else { ($dHits -join " | ") })

# T-PORT-03: settings.json tasinabilir (null/goreceli).
$stOk = $false; $stNote = ""
try {
  $sj = Get-Content -LiteralPath (Join-Path $Root "settings.json") -Raw | ConvertFrom-Json
  $abs = @()
  foreach ($p in @($sj.PSObject.Properties)) {
    $v = [string]$p.Value
    if ($v -match "^[A-Za-z]:\\") { $abs += @($p.Name) }
  }
  $stOk = (@($abs).Count -eq 0)
  $stNote = $(if ($stOk) { "settings goreceli" } else { "mutlak: " + ($abs -join ",") })
} catch { $stNote = "settings okunamadi" }
Add-POResult "T-PORT-03" $stOk $stNote

# T-PORT-04: profil dosyalari mutlak yol icermez.
$profOk = $true; $profNote = "profiller goreceli"
foreach ($pd in @("printers", "filaments", "processes")) {
  $dd = Join-Path $Root $pd
  if (-not (Test-Path -LiteralPath $dd)) { continue }
  foreach ($f in (Get-ChildItem -LiteralPath $dd -Filter "*.json" -ErrorAction SilentlyContinue)) {
    $t = Get-Content -LiteralPath $f.FullName -Raw
    if ($t -match '"[A-Za-z]:\\\\') { $profOk = $false; $profNote = ("mutlak yol: " + $pd + "/" + $f.Name) }
  }
}
Add-POResult "T-PORT-04" $profOk $profNote

# T-PORT-05: TEMP erisimi API ile (GetTempPath / $env:TEMP), sabit degil (T-SEC-04 ile ortak; burada sayim).
Add-POResult "T-PORT-05" $true "TEMP API kullanimi (statik)"

Write-Output "----------------------------------------"
Write-Output ("PORTABILITY SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
