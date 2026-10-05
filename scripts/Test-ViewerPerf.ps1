<#
.SYNOPSIS
  3D viewer performans + responsiveness testi.
.DESCRIPTION
  app/DesignerV1.ps1 -PerfStl ile gercek modellerde olcum yapar:
  - kickoff (UI bloklayan kisim) < 2 sn olmali
  - load + frame sureleri esik altinda olmali
  - display mesh dogru olmali (full/disp sayilari, bbox, nonbg piksel)
  - async timer yolu (gercek message pump) UI thread'i bloklamamali
  Cikis: [PASS]/[FAIL] satirlari (Run-AllTests sayar). INFO: sayilmaz.
#>
param([int]$Frames = 10)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

$script:pass = 0; $script:fail = 0
function Add-VPResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}
function Write-VPInfo($t) { Write-Output ("INFO: " + $t) }

function Get-PerfLines($stlPath, $frames) {
  $out = & (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -PerfStl $stlPath -PerfFrames $frames 2>&1 | Out-String
  $h = @{}
  foreach ($ln in ($out -split "`r?`n")) {
    $s = $ln.Trim()
    if ($s -match "^PERF-KICKOFF: ms=(\d+)") { $h.kick = [long]$Matches[1] }
    elseif ($s -match "^PERF-LOAD: ms=(\d+) full=(\d+) disp=(\d+)") { $h.load = [long]$Matches[1]; $h.full = [long]$Matches[2]; $h.disp = [long]$Matches[3] }
    elseif ($s -match "^PERF-BBOX: min=([^ ]+) max=([^ ]+)") { $h.bmin = $Matches[1]; $h.bmax = $Matches[2] }
    elseif ($s -match "^PERF-NONBG: n=(\d+) samples=(\d+)") { $h.nonbg = [long]$Matches[1]; $h.samples = [long]$Matches[2] }
    elseif ($s -match "^PERF-FRAME: avg=([\d\.]+) max=(\d+) n=(\d+)") { $h.avg = [double]$Matches[1]; $h.max = [long]$Matches[2]; $h.n = [long]$Matches[3] }
    elseif ($s -match "^PERF-MEM: mb=([\d\.]+)") { $h.mem = [double]$Matches[1] }
    elseif ($s -match "^PERFTEST: PASS") { $h.ok = $true }
  }
  return $h
}
function Test-BBoxSane($h) {
  try {
    $a = ([string]$h.bmin).Split(","); $b = ([string]$h.bmax).Split(",")
    if ($a.Count -ne 3 -or $b.Count -ne 3) { return $false }
    for ($k = 0; $k -lt 3; $k++) { if (-not ([double]$b[$k] -gt [double]$a[$k])) { return $false } }
    return $true
  } catch { return $false }
}
function Test-PerfModel($id, $stlPath, $expFull, $expDisp) {
  if (-not (Test-Path -LiteralPath $stlPath)) { Add-VPResult $id $false ("dosya yok: " + $stlPath); return }
  $h = Get-PerfLines $stlPath $Frames
  if (-not $h.ok) { Add-VPResult $id $false "PERFTEST gecemedi"; return }
  $ok = $true; $note = ""
  if ($h.kick -gt 2000) { $ok = $false; $note += "kickoff yavas " }
  if ($h.avg -gt 500 -or $h.max -gt 2000) { $ok = $false; $note += "frame yavas " }
  if ($h.full -le 0 -or $h.disp -le 0 -or $h.full -lt $h.disp -or $h.disp -gt 5000) { $ok = $false; $note += "sayi tutarsiz " }
  if ($expFull -gt 0 -and $h.full -ne $expFull) { $ok = $false; $note += "full beklenen degil " }
  if ($expDisp -gt 0 -and $h.disp -ne $expDisp) { $ok = $false; $note += "disp beklenen degil " }
  if (-not (Test-BBoxSane $h)) { $ok = $false; $note += "bbox bozuk " }
  if ($h.nonbg -le 0) { $ok = $false; $note += "render bos " }
  if ($note -eq "") { $note = ("kick=" + $h.kick + " load=" + $h.load + " avg=" + $h.avg + " max=" + $h.max + " full=" + $h.full + " disp=" + $h.disp + " nonbg=" + $h.nonbg + " mem=" + $h.mem) }
  Add-VPResult $id $ok $note.Trim()
}

$projDir = Join-Path $Root "projects"
Test-PerfModel "T-VP-01" (Join-Path $projDir "m1-acik-kutu\output\body.stl") 0 0
Test-PerfModel "T-VP-02" (Join-Path $projDir "m2-partition-kutu\output\body.stl") 0 0
Test-PerfModel "T-VP-03" (Join-Path $projDir "m4-hole-kutu\output\body.stl") 0 0
Test-PerfModel "T-VP-04" (Join-Path $projDir "bench-organizer-1\output\body.stl") 9696 4848
Test-PerfModel "T-VP-05" (Join-Path $projDir "bench-organizer-2\output\body.stl") 0 0

# --- 20k+ ve buyuk STL fixture (gercek organizer facet bloklarinin tekrari) ---
$srcStl = Join-Path $projDir "bench-organizer-1\output\body.stl"
$fixDir = Join-Path ([System.IO.Path]::GetTempPath()) "vperf-fix"
New-Item -ItemType Directory -Force -Path $fixDir | Out-Null
function New-RepFixture($name, $targetFacets) {
  $fp = Join-Path $fixDir $name
  $srcLines = [System.IO.File]::ReadAllLines($srcStl)
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("solid perf-fixture")
  $made = 0
  $rep = [math]::Max(1, [int][math]::Ceiling($targetFacets / 9000))
  for ($r = 0; $r -lt $rep -and $made -lt $targetFacets; $r++) {
    $inF = $false
    $block = New-Object System.Collections.Generic.List[string]
    foreach ($l in $srcLines) {
      $t = $l.Trim()
      if ($t.StartsWith("facet normal")) { $inF = $true; $block.Clear(); $block.Add($l) }
      elseif ($inF) {
        $block.Add($l)
        if ($t.StartsWith("endfacet")) {
          $inF = $false
          foreach ($b in $block) { [void]$sb.AppendLine($b) }
          $made++
          if ($made -ge $targetFacets) { break }
        }
      }
    }
  }
  [void]$sb.AppendLine("endsolid perf-fixture")
  [System.IO.File]::WriteAllText($fp, $sb.ToString(), [System.Text.Encoding]::ASCII)
  return $fp
}
$f20 = New-RepFixture "perf-20k.stl" 20000
$f60 = New-RepFixture "perf-60k.stl" 60000
Test-PerfModel "T-VP-06" $f20 20000 5000
Test-PerfModel "T-VP-07" $f60 60000 5000

# --- T-VP-08: async timer yolu + gercek message pump (UI thread bloklanmamali) ---
# Forms.Timer STA gerektirir; uretim kodunu STA child process'te calistirir.
try {
  $asyncChild = Join-Path ([System.IO.Path]::GetTempPath()) ("vpasync-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8) + ".ps1")
  $asyncTpl = @'
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$appFile = "@@APPFILE@@"
$stlFile = "@@STLFILE@@"
$appLines = Get-Content -LiteralPath $appFile -Encoding Unicode
$loadM = -1; $fitS = -1
for ($i = 0; $i -lt $appLines.Count; $i++) {
  if ($appLines[$i] -eq "# ---- STL Loader: chunked parse (UI thread never blocked) ----------------") { $loadM = $i }
  if ($appLines[$i] -eq "# ---- Project 3D -> 2D (orthographic) ------------------------------------") { $fitS = $i }
}
if ($loadM -lt 0 -or $fitS -le $loadM) { Write-Output "ASYNC-RESULT: harness-hata"; exit 1 }
$loaderSrc = ($appLines[$loadM..($fitS - 1)] -join "`r`n")
$script:wsDispMax = 5000
$script:wsFacets = $null
$script:wsDX = $null; $script:wsDN = $null; $script:wsDC = $null
$script:wsDispCount = 0; $script:wsFullCount = 0; $script:wsTriCount = 0
$script:wsOrder = $null; $script:wsDepths = $null
$script:wsSortYaw = [double]::NaN; $script:wsSortPitch = [double]::NaN
$script:wsLoading = $false; $script:wsLoadPct = 0; $script:wsLoadState = $null
$script:wsLoadTimer = $null; $script:wsLoadCancel = $false; $script:wsNoAsync = $false
$script:wsShadeBrushes = $null
$script:wsBBoxMin = @(0.0, 0.0, 0.0); $script:wsBBoxMax = @(0.0, 0.0, 0.0)
$script:wsStlPath = ""
$script:wsYaw = 0.6; $script:wsPitch = 0.5; $script:wsZoom = 1.0
$script:wsPanX = 0; $script:wsPanY = 0
$script:uiClosing = $false
$lblViewStatus = $null
$rawPnl = New-Object PSObject
$rawPnl | Add-Member -MemberType NoteProperty -Name Width -Value 800
$rawPnl | Add-Member -MemberType NoteProperty -Name Height -Value 500
$rawPnl | Add-Member -MemberType ScriptMethod -Name Invalidate -Value { }
Set-Variable -Name pnlView -Value $rawPnl -Scope Script
$sbx = [scriptblock]::Create($loaderSrc)
. $sbx
WS-LoadStl $stlFile
$kickFast = ($script:wsLoading -eq $true)
$wall = [System.Diagnostics.Stopwatch]::StartNew()
$sliceMax = [long]0
$done = $false
while ($wall.ElapsedMilliseconds -lt 120000) {
  $sl = [System.Diagnostics.Stopwatch]::StartNew()
  [System.Windows.Forms.Application]::DoEvents()
  $sl.Stop()
  if ($sl.ElapsedMilliseconds -gt $sliceMax) { $sliceMax = $sl.ElapsedMilliseconds }
  if (-not $script:wsLoading -and $script:wsDispCount -gt 0) { $done = $true; break }
  Start-Sleep -Milliseconds 20
}
$wall.Stop()
try { if ($null -ne $script:wsLoadTimer) { $script:wsLoadTimer.Stop() } } catch { }
Write-Output ("ASYNC-RESULT: done=" + $done + " full=" + $script:wsFullCount + " disp=" + $script:wsDispCount + " slicemax=" + $sliceMax + " wall=" + $wall.ElapsedMilliseconds)
if ($kickFast -and $done -and ($script:wsFullCount -eq 20000) -and ($script:wsDispCount -eq 5000) -and ($sliceMax -lt 2000)) { exit 0 } else { exit 1 }
'@
  $asyncCode = $asyncTpl.Replace("@@APPFILE@@", (Join-Path $Root "app\DesignerV1.ps1")).Replace("@@STLFILE@@", $f20)
  Set-Content -LiteralPath $asyncChild -Value $asyncCode -Encoding UTF8
  $aout = & powershell -NoProfile -STA -ExecutionPolicy Bypass -File $asyncChild 2>&1 | Out-String
  $acode = $LASTEXITCODE
  try { Remove-Item -LiteralPath $asyncChild -Force -ErrorAction SilentlyContinue } catch { }
  $aline = ""
  foreach ($ln in ($aout -split "`r?`n")) { if ($ln.Trim().StartsWith("ASYNC-RESULT:")) { $aline = $ln.Trim() } }
  Write-VPInfo ("async child exit=" + $acode + " " + $aline)
  Add-VPResult "T-VP-08" ($acode -eq 0) "STA timer+DoEvents: hicbir dilim 2 sn bloklamadi, tamamlandi"
} catch {
  Add-VPResult "T-VP-08" $false ("async harness hatasi: " + $_.Exception.Message)
}

if (Test-Path -LiteralPath $fixDir) { Remove-Item -LiteralPath $fixDir -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output "----------------------------------------"
Write-Output ("VIEWER-PERF SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
