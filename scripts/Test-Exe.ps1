<#
.SYNOPSIS
  EXE testi: varlik + boyut + calistir + process dogrulama + kontrollu kapatma.
.DESCRIPTION
  1. dist/3D-AI-Designer.exe var mi, boyutu >0 mi (saglik siniri 10 KB).
  2. EXE'yi baslatir; dist\app\DesignerV1.ps1 calistiran powershell child beklenir (25 sn).
  3. Bulunursa PASS; child + launcher kontrollu kapatilir.
  4. Bulunamazsa FAIL; launcher kapatilir. Cikis kodu buna gore.
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
foreach ($k in $found) {
  Stop-Process -Id $k.ProcessId -Force -ErrorAction SilentlyContinue
}
if ($proc -and -not $proc.HasExited) {
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
Start-Sleep -Seconds 2
if ($okAll) { Write-TMsg "TEST EXE PASS"; exit 0 } else { Write-TMsg "TEST EXE FAIL"; exit 1 }
