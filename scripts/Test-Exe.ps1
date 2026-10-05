<#
.SYNOPSIS
  EXE testi: varlik + boyut + calistir + process + GORUNURLUK dogrulama + kontrollu kapatma.
.DESCRIPTION
  1. dist/3D-AI-Designer.exe var mi, boyutu >0 mi (saglik siniri 10 KB).
  2. EXE'yi baslatir; dist\app\DesignerV1.ps1 calistiran powershell child beklenir (25 sn).
  3. Child gorunurse Win32 ile gercek pencere gorunurlugu dogrulanir (20 sn):
     gorunur top-level pencere + sifirdan buyuk boyut + opak (layered ise alpha>0).
     Sadece process/handle varligi PASS sayilmaz (Opacity=0 regresyonu icin).
  4. Hepsi PASS ise child + launcher kontrollu kapatilir; degilse FAIL.
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File ".\scripts\Test-Exe.ps1"
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$Exe = Join-Path $Root (Join-Path "dist" "3D-AI-Designer.exe")

function Write-TMsg($t) { Write-Output $t }
$okAll = $true

if (-not (Test-Path -LiteralPath $Exe)) {
  Write-TMsg "[FAIL] EXE yok: $Exe (once Build-Exe.ps1 calistir)"
  exit 1
}
$len = (Get-Item -LiteralPath $Exe).Length
if ($len -le 0) { Write-TMsg "[FAIL] EXE boyutu 0"; exit 1 }
$fs = [System.IO.File]::OpenRead($Exe)
$mz = New-Object byte[] 2
[void]$fs.Read($mz, 0, 2)
$fs.Close()
if ($mz[0] -ne 77 -or $mz[1] -ne 90) { Write-TMsg "[FAIL] PE imzasi yok (MZ)"; exit 1 }
Write-TMsg ("[PASS] EXE var ($len bayt, PE dogrulandi)")

$before = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Select-Object -ExpandProperty ProcessId)
$proc = $null
try {
  $proc = Start-Process -FilePath $Exe -PassThru
} catch {
  Write-TMsg ("[FAIL] baslatilamadi: " + $_.Exception.Message)
  exit 1
}

$found = @()
for ($i = 0; $i -lt 25 -and $found.Count -eq 0; $i++) {
  Start-Sleep -Seconds 1
  $found = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object {
    ($before -notcontains $_.ProcessId) -and ($_.ProcessId -ne $PID) -and ([string]$_.CommandLine -match "dist\\app\\DesignerV1")
  })
}
if ($found.Count -gt 0) {
  Write-TMsg ("[PASS] uygulama acildi (powershell PID " + $found[0].ProcessId + ")")
} else {
  $okAll = $false
  Write-TMsg "[FAIL] uygulama processi gorulmedi (25 sn)"
}
# GORUNURLUK: child process varligi yetmez; pencere gercekten opak + gorunur olmali.
$visOk = $false
$visInfo = ""
if ($found.Count -gt 0) {
  $visCs = @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class WinVis {
  public delegate bool EnumWin(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWin f, IntPtr l);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool GetLayeredWindowAttributes(IntPtr h, out uint key, out byte alpha, out uint flags);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L,T,R,B; }
  public static string hit = "";
  public static void Run(uint pid) {
    hit = "";
    EnumWindows(delegate(IntPtr h, IntPtr l) {
      uint p; GetWindowThreadProcessId(h, out p);
      if (p != pid) return true;
      RECT r; GetWindowRect(h, out r);
      int w = r.R - r.L, hh = r.B - r.T;
      if (w < 100 || hh < 100) return true;
      if (!IsWindowVisible(h)) return true;
      int ex = GetWindowLong(h, -20);
      bool layered = (ex & 0x80000) != 0;
      int alpha = 255;
      if (layered) { uint k; byte a; uint f; if (GetLayeredWindowAttributes(h, out k, out a, out f)) alpha = (int)a; else alpha = -1; }
      if (layered && alpha <= 0) return true;
      hit = "HWND=" + h + " W=" + w + " H=" + hh + " LAYERED=" + layered + " ALPHA=" + alpha;
      return false;
    }, IntPtr.Zero);
  }
}
'@
  try { Add-Type -TypeDefinition $visCs -Language CSharp -ErrorAction Stop } catch { }
  $childPid = [uint32]$found[0].ProcessId
  for ($w = 0; $w -lt 20 -and -not $visOk; $w++) {
    Start-Sleep -Seconds 1
    try { [WinVis]::Run($childPid) } catch { }
    $visInfo = [WinVis]::hit
    if ($visInfo -ne "") { $visOk = $true }
  }
}
if ($found.Count -gt 0) {
  if ($visOk) {
    Write-TMsg ("[PASS] pencere gorunur + opak (" + $visInfo + ")")
    Start-Sleep -Seconds 3
    $alive = @(Get-CimInstance Win32_Process -Filter ("ProcessId=" + $found[0].ProcessId))
    if ($alive.Count -gt 0) { Write-TMsg "[PASS] uygulama alive (gorunurluk sonrasi 3 sn)" }
    else { $okAll = $false; Write-TMsg "[FAIL] uygulama gorunurluk sonrasi yasamiyor" }
  } else {
    $okAll = $false
    Write-TMsg "[FAIL] gorunur/opak pencere yok (20 sn; seffaf Opacity=0 olabilir)"
  }
}
foreach ($k in $found) {
  Stop-Process -Id $k.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($proc -and -not $proc.HasExited) {
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
if ($okAll) { Write-TMsg "TEST EXE PASS"; exit 0 } else { Write-TMsg "TEST EXE FAIL"; exit 1 }
