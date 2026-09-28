<#
.SYNOPSIS
  3D-AI-Designer EXE paketleme. BUILD -> VERIFY -> SMOKE TEST
.DESCRIPTION
  1. Staging directory olusturur.
  2. C# launcher derler (argumanlari destekler).
  3. Gerekli dosyalari kopyalar.
  4. PE header dogrular.
  5. Smoke test calistirir (-ValidateUI argumaniyla).
  6. Basarili olursa dist klasorunu gunceller.
#>
param([switch]$PreflightOnly)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$Dist = Join-Path $Root "dist"

function Find-Csc {
  foreach ($p in @(
    "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe",
    "C:\Windows\Microsoft.NET\Framework64\v3.5\csc.exe"
  )) {
    if (Test-Path -LiteralPath $p) { return $p }
  }
  $c = Get-Command csc.exe -ErrorAction SilentlyContinue
  if ($c) { return $c.Source }
  return $null
}

$csc = Find-Csc
if (-not $csc) {
  Write-Output "BUILD: csc bulunamadi (EXE derlenemez)."
  if ($PreflightOnly) { exit 2 } else { exit 1 }
}
Write-Output ("BUILD: derleyici: " + $csc)

$cs = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
class Launcher {
  [STAThread]
  static int Main(string[] args) {
    try {
      string dir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
      string app = Path.Combine(dir, "app" + Path.DirectorySeparatorChar + "DesignerV1.ps1");
      if (!File.Exists(app)) {
        MessageBox.Show("Uygulama bulunamadi:\n" + app + "\n\nEXE yaninda proje klasoru (app/, engine/, ...) olmali.",
          "3D AI Designer", MessageBoxButtons.OK, MessageBoxIcon.Error);
        return 2;
      }
      string pwsh = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell" + Path.DirectorySeparatorChar + "v1.0" + Path.DirectorySeparatorChar + "powershell.exe");
      if (!File.Exists(pwsh)) { pwsh = "powershell.exe"; }
      
      string arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + app + "\"";
      if (args.Length > 0) {
        foreach(string a in args) {
          arguments += " \"" + a.Replace("\"", "\\\"") + "\"";
        }
      }
      
      ProcessStartInfo psi = new ProcessStartInfo();
      psi.FileName = pwsh;
      psi.Arguments = arguments;
      psi.WorkingDirectory = dir;
      psi.UseShellExecute = false;
      psi.RedirectStandardOutput = true;
      psi.RedirectStandardError = true;
      psi.CreateNoWindow = true;
      Process p = null;
      try { p = Process.Start(psi); }
      catch (Exception ex2) {
        MessageBox.Show("PowerShell baslatilamadi:\n" + ex2.Message,
          "3D AI Designer", MessageBoxButtons.OK, MessageBoxIcon.Error);
        return 3;
      }
      p.WaitForExit();
      int code = p.ExitCode;
      if (code != 0 && args.Length == 0) {
        string err = "";
        try { err = p.StandardError.ReadToEnd(); } catch { }
        if (err == null) { err = ""; }
        if (err.Length > 2000) { err = err.Substring(err.Length - 2000); }
        MessageBox.Show("Uygulama hata ile kapandi (kod " + code + "):\n" + err + "\n\nOpenSCAD bulunamazsa: Ayarlar > Araclar > Konum Sec.",
          "3D AI Designer", MessageBoxButtons.OK, MessageBoxIcon.Error);
      }
      return code;
    } catch (Exception ex) {
      try {
        MessageBox.Show("Baslatma hatasi:\n" + ex.Message + "\n\nOpenSCAD bulunamazsa: Ayarlar > Araclar > Konum Sec.",
          "3D AI Designer", MessageBoxButtons.OK, MessageBoxIcon.Error);
      } catch { }
      return 1;
    }
  }
}
'@
$tmpCs = Join-Path ([System.IO.Path]::GetTempPath()) "designer-launcher.cs"
$cs | Set-Content -LiteralPath $tmpCs -Encoding UTF8

if ($PreflightOnly) {
  $tmpExe = Join-Path ([System.IO.Path]::GetTempPath()) "designer-preflight.exe"
  & $csc /nologo /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:$tmpExe $tmpCs 2>&1 | Out-Null
  if ((Test-Path -LiteralPath $tmpExe) -and ((Get-Item -LiteralPath $tmpExe).Length -gt 1024)) {
    $fs = [System.IO.File]::OpenRead($tmpExe)
    $mz = New-Object byte[] 2
    [void]$fs.Read($mz, 0, 2)
    $fs.Close()
    Remove-Item -LiteralPath $tmpExe -Force -ErrorAction SilentlyContinue
    if ($mz[0] -eq 77 -and $mz[1] -eq 90) { Write-Output "PREFLIGHT: PASS (derleme dogrulandi)"; exit 0 }
  }
  Write-Output "PREFLIGHT: FAIL"
  exit 1
}

$guid = [guid]::NewGuid().ToString().Substring(0,8)
# Bayat staging artiklarini temizle (yarim kalmis build kalintisi; kullanici verisi icermez).
foreach ($st in (Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^dist_staging_" })) {
  try { Remove-Item -LiteralPath $st.FullName -Recurse -Force -ErrorAction Stop } catch { Write-Output ("BUILD: eski staging silinemedi (kilitli olabilir): " + $st.Name) }
}
$Stage = Join-Path $Root "dist_staging_$guid"
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

$exe = Join-Path $Stage "3D-AI-Designer.exe"
$iconArg = @()
$iconFile = Join-Path $Root (Join-Path "assets" "app.ico")
if (Test-Path -LiteralPath $iconFile) { $iconArg = @("/win32icon:$iconFile"); Write-Output "BUILD: ikon gomuluyor (assets/app.ico)" }
else { Write-Output "BUILD: ikon bulunamadi, ikonsuz derleniyor (scripts\New-AppIcon.ps1 calistir)" }
& $csc /nologo /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:$exe @iconArg $tmpCs 2>&1 | Out-Null
Remove-Item -LiteralPath $tmpCs -Force -ErrorAction SilentlyContinue

Write-Output "BUILD: Kopyalama basliyor..."
foreach ($d in @("app", "engine", "scripts", "schemas", "templates", "printers", "materials", "projects", "docs", "knowledge", "assets")) {
  $src = Join-Path $Root $d
  if (Test-Path -LiteralPath $src) {
    Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $d) -Recurse -Force
  }
}
foreach ($f in @("settings.json", "README.md", "VERSION")) {
  $src = Join-Path $Root $f
  if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $Stage $f) -Force }
}
$gitInDist = Join-Path $Stage ".git"
if (Test-Path -LiteralPath $gitInDist) { Remove-Item -LiteralPath $gitInDist -Recurse -Force }
$nm = Join-Path $Stage (Join-Path ".opencode" "node_modules")
if (Test-Path -LiteralPath $nm) { Remove-Item -LiteralPath $nm -Recurse -Force }

Write-Output "VERIFY: EXE olusumu kontrol ediliyor..."
if (-not (Test-Path -LiteralPath $exe)) { 
  Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
  throw "Derleme basarisiz (exe olusmadi)." 
}
$fs = [System.IO.File]::OpenRead($exe)
$mz = New-Object byte[] 2
[void]$fs.Read($mz, 0, 2)
$fs.Close()
if ($mz[0] -ne 77 -or $mz[1] -ne 90) {
  Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
  throw "Derleme basarisiz (gecersiz PE header)."
}
Write-Output "VERIFY: PASS"

Write-Output "SMOKE TEST: EXE calistiriliyor (-ValidateUI)..."
$smoke = & $exe -ValidateUI 2>&1 | Out-String
$smokeCode = $LASTEXITCODE
if ($smokeCode -eq 0) {
  Write-Output "SMOKE TEST: PASS"
} else {
  Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
  Write-Output "SMOKE TEST CIKTISI: $smoke"
  throw "SMOKE TEST: FAIL (Code $smokeCode). EXE bozuk."
}

# Calisan uygulama tespiti: dist kilitliyse anlasilir BLOCKED ver (kilit kirma yok).
$running = @(Get-Process -Name "3D-AI-Designer" -ErrorAction SilentlyContinue)
if ($running.Count -gt 0) {
  Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
  throw "BUILD BLOCKED: 3D-AI-Designer su an calisiyor (PID $($running[0].Id)). Once uygulamayi kapatip tekrar calistir. Staging temizlendi, mevcut dist degistirilmedi."
}
if (Test-Path -LiteralPath $Dist) {
  $trash = Join-Path $Root "dist_trash_$guid"
  $swapped = $false
  for ($ri = 0; $ri -lt 6 -and -not $swapped; $ri++) {
    try {
      [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
      Rename-Item -Path $Dist -NewName $trash -ErrorAction Stop
      $swapped = $true
    } catch {
      if ($ri -eq 5) {
        Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
        throw ("BUILD BLOCKED: dist klasoru kilitli (baska islem kullaniyor olabilir). Staging temizlendi, mevcut dist degistirilmedi. Hata: " + $_.Exception.Message)
      }
      Start-Sleep -Seconds 3
    }
  }
  $trashCount = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match "^dist_trash_" }).Count
  Write-Output ("BUILD: eski dist yedeklendi (trash sayisi: " + $trashCount + "; kullanici projeleri trash icinde korunur, otomatik silinmez)")
}
Rename-Item -Path $Stage -NewName "dist" -ErrorAction Stop
Write-Output ("BUILD: OK -> " + (Join-Path $Dist "3D-AI-Designer.exe"))
