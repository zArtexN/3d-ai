<#
.SYNOPSIS
  3D-AI-Designer EXE paketleme (hafif launcher, gomulu bagimlilik YOK).
.DESCRIPTION
  1. csc.exe arar (.NET Framework, derleme icin yeter; SDK gerekmez).
  2. Bulunamazsa: acik hata + dependency-free .cmd launcher yazar (sahte .exe YOK).
  3. Bulunursa: C# launcher derler -> dist/3D-AI-Designer.exe + portable agac kopyalanir:
     dist/3D-AI-Designer.exe, app/, engine/, scripts/, schemas/, templates/,
     printers/, materials/, projects/, docs/, settings.json, README.md, VERSION.
     OpenSCAD/FreeCAD/OrcaSlicer GOMULMEZ; calisma aninda resolver bulur.
  Calistirma: powershell -ExecutionPolicy Bypass -File ".\scripts\Build-Exe.ps1"
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
  $cmd = Join-Path $Root "3D-AI-Designer.cmd"
  '@echo off' | Set-Content -LiteralPath $cmd -Encoding ASCII
  'powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0app\DesignerV1.ps1"' | Add-Content -LiteralPath $cmd -Encoding ASCII
  Write-Output "BUILD: csc bulunamadi (EXE derlenemez)."
  Write-Output "BUILD: dependency-free baslatici yazildi: 3D-AI-Designer.cmd"
  Write-Output "BUILD: .NET Framework csc.exe kurulu PC'de tekrar calistir."
  if ($PreflightOnly) { exit 2 } else { exit 0 }
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
  static int Main() {
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
      ProcessStartInfo psi = new ProcessStartInfo();
      psi.FileName = pwsh;
      psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File \"" + app + "\"";
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
      if (code != 0) {
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
    if ($mz[0] -eq 77 -and $mz[1] -eq 90) { Write-Output "PREFLIGHT: PASS (derleme + PE dogrulandi)"; exit 0 }
  }
  Write-Output "PREFLIGHT: FAIL (derleme olmadi)"
  exit 1
}

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
$exe = Join-Path $Dist "3D-AI-Designer.exe"
if (Test-Path -LiteralPath $exe) { Remove-Item -LiteralPath $exe -Force }
& $csc /nologo /target:winexe /r:System.Windows.Forms.dll /r:System.Drawing.dll /out:$exe $tmpCs 2>&1 | Out-Null
Remove-Item -LiteralPath $tmpCs -Force -ErrorAction SilentlyContinue
if (-not (Test-Path -LiteralPath $exe)) { throw "Derleme basarisiz (exe olusmadi)." }
$age = ((Get-Date) - (Get-Item -LiteralPath $exe).LastWriteTime).TotalMinutes
if ($age -gt 2) { throw "Derleme basarisiz (exe guncellenmedi)." }
foreach ($d in @("app", "engine", "scripts", "schemas", "templates", "printers", "materials", "projects", "docs")) {
  $src = Join-Path $Root $d
  if (Test-Path -LiteralPath $src) {
    $dst = Join-Path $Dist $d
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force
  }
}
foreach ($f in @("settings.json", "README.md", "VERSION")) {
  $src = Join-Path $Root $f
  if (Test-Path -LiteralPath $src) { Copy-Item -LiteralPath $src -Destination (Join-Path $Dist $f) -Force }
}
$gitInDist = Join-Path $Dist ".git"
if (Test-Path -LiteralPath $gitInDist) { Remove-Item -LiteralPath $gitInDist -Recurse -Force }
$nm = Join-Path $Dist (Join-Path ".opencode" "node_modules")
if (Test-Path -LiteralPath $nm) { Remove-Item -LiteralPath $nm -Recurse -Force }
Write-Output ("BUILD: OK -> " + $exe)
Write-Output "Kullanim: dist klasorunu kopyala, 3D-AI-Designer.exe cift tikla."
Write-Output "Not: OpenSCAD/FreeCAD/OrcaSlicer gomulu degil; ilk acilista resolver bulur (Ayarlar > Konum Sec)."
