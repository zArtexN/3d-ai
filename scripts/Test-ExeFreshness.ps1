<#
.SYNOPSIS
  EXE tazelik testi (Test-ExeFreshness.ps1)
.DESCRIPTION
  Uygulama kaynak kodu (app/DesignerV1.ps1) degistirildiginde EXE'nin stale
  kaldigini tespit eder ve Build-Exe.ps1'i calistirarak EXE'nin guncel
  hale gelip gelmedigini dogrular.
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$AppFile = Join-Path $Root "app\DesignerV1.ps1"
$ExeFile = Join-Path $Root "dist\3D-AI-Designer.exe"
$DistAppFile = Join-Path $Root "dist\app\DesignerV1.ps1"

Write-Output "--- EXE FRESHNESS TEST ---"

if (-not (Test-Path -LiteralPath $ExeFile)) {
    Write-Output "[FAIL] EXE bulunamadi, test yapilamiyor."
    exit 1
}

# 1. Kaynak dosyaya dummy bir yorum satiri ekleyerek degistirelim.
Write-Output "1. Kaynak dosya degistiriliyor ($AppFile)..."
Add-Content -LiteralPath $AppFile -Value "# DUMMY TEST COMMENT $(Get-Date)"
Start-Sleep -Seconds 2

# 2. EXE stale mi kontrol edelim.
$appTime = (Get-Item -LiteralPath $AppFile).LastWriteTime
$exeTime = (Get-Item -LiteralPath $ExeFile).LastWriteTime
$distAppTime = (Get-Item -LiteralPath $DistAppFile).LastWriteTime

if ($exeTime -lt $appTime -or $distAppTime -lt $appTime) {
    Write-Output "[PASS] Stale EXE basariyla tespit edildi (exe/distApp < app)."
} else {
    Write-Output "[FAIL] Stale EXE tespit edilemedi! EXE/distApp daha yeni veya esit zamanli."
    exit 1
}

# 3. Build-Exe.ps1 calistir.
Write-Output "2. Build-Exe.ps1 calistiriliyor..."
$buildOut = & (Join-Path $Root "scripts\Build-Exe.ps1") 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
    Write-Output "[FAIL] Build-Exe.ps1 basarisiz oldu!"
    Write-Output $buildOut
    exit 1
}
Write-Output "[PASS] Build-Exe.ps1 basariyla tamamladi."

# 4. Yeni EXE ve paket taze mi?
$newExeTime = (Get-Item -LiteralPath $ExeFile).LastWriteTime
$newDistAppTime = (Get-Item -LiteralPath $DistAppFile).LastWriteTime
$appTime = (Get-Item -LiteralPath $AppFile).LastWriteTime # Tekrar okuyalim garanti olsun

if ($newExeTime -ge $appTime -and $newDistAppTime -ge $appTime) {
    Write-Output "[PASS] Yeni EXE ve dist paketi guncel (taze)."
} else {
    Write-Output "[FAIL] Yeni EXE hala eski! Build-Exe.ps1 kaynak kodunu pakete eklemedi."
    Write-Output "App: $appTime | Exe: $newExeTime | DistApp: $newDistAppTime"
    exit 1
}

# 5. PE Dogrulama
$fs = [System.IO.File]::OpenRead($ExeFile)
$mz = New-Object byte[] 2
[void]$fs.Read($mz, 0, 2)
$fs.Close()
if ($mz[0] -eq 77 -and $mz[1] -eq 90) {
    Write-Output "[PASS] Yeni EXE gecerli bir PE dosyasi (MZ)."
} else {
    Write-Output "[FAIL] Yeni EXE gecersiz."
    exit 1
}

Write-Output "--- FRESHNESS TEST: ALL PASS ---"
exit 0
