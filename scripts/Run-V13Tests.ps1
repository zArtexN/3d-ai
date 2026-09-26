<#
.SYNOPSIS
  V1.3 testleri: parser kenar konumlari + reference workflow + UI startup + EXE preflight.
.DESCRIPTION
  P17 kenarlardan->(15,15) | P18 koseden | P19 sagdan/alttan | P20 muglak->soru
  R21 STL import+bbox | R22 gecersiz URL semasi | R23 kayip dosya | R24 aynisini-parsing
  R25 bilinmeyen olcu -> BLOCKED | R26 UI startup | R27 EXE preflight | R28 file:// red
  Internet gerektirmez (ag testi yok). Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Run-V13Tests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$results = New-Object System.Collections.Generic.List[object]
function Remove-VTemp($dir) {
  for ($i = 0; $i -lt 6 -and (Test-Path -LiteralPath $dir); $i++) {
    try {
      [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
      Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction Stop
    } catch { Start-Sleep -Milliseconds 800 }
  }
}
function Add-VResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}
function Invoke-ParserOne($prompt, $tag) {
  $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("v13-" + $tag + ".json")
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $prompt -ProjectName $tag -OutPath $tmp 2>&1 | Out-Null
  $s = Get-Content -LiteralPath $tmp -Raw | ConvertFrom-Json
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  return $s
}

try {
  $s = Invoke-ParserOne "50x50x10 kutu, delik 10, merkezi kenarlardan 15 mm iceride." "p17"
  $h = $s.components[0].holes[0]
  $ok = ([double]$h.center_x_mm -eq 15 -and [double]$h.center_y_mm -eq 15 -and $h.status -eq "ok")
  Add-VResult "P17-kenarlardan" $ok $(if ($ok) { "center 15,15" } else { "cozulmedi" })
} catch { Add-VResult "P17-kenarlardan" $false $_.Exception.Message }
try {
  $s = Invoke-ParserOne "50x50x10 kutu, delik 10, koseden 10 mm." "p18"
  $h = $s.components[0].holes[0]
  $ok = ([double]$h.center_x_mm -eq 10 -and [double]$h.center_y_mm -eq 10)
  Add-VResult "P18-koseden" $ok $(if ($ok) { "center 10,10" } else { "cozulmedi" })
} catch { Add-VResult "P18-koseden" $false $_.Exception.Message }
try {
  $s = Invoke-ParserOne "100x60x20 kutu, delik 10, sagdan 20 mm, alttan 10 mm." "p19"
  $h = $s.components[0].holes[0]
  $ok = ([double]$h.center_x_mm -eq 80 -and [double]$h.center_y_mm -eq 10)
  Add-VResult "P19-sag-alttan" $ok $(if ($ok) { "center 80,10" } else { "cozulmedi" })
} catch { Add-VResult "P19-sag-alttan" $false $_.Exception.Message }
try {
  $s = Invoke-ParserOne "50x50x10 kutu, delik 10, biraz iceride." "p20"
  $st = [string]$s.components[0].holes[0].status
  $ok = ($st -eq "missing")
  Add-VResult "P20-muglak" $ok $(if ($ok) { "uydurulmadi, sorulacak" } else { "status=$st" })
} catch { Add-VResult "P20-muglak" $false $_.Exception.Message }

$refTmp = Join-Path ([System.IO.Path]::GetTempPath()) "v13-ref"
try {
  Remove-VTemp $refTmp
  New-Item -ItemType Directory -Force -Path $refTmp | Out-Null
  $o = & (Join-Path $EngineDir "Analyze-Reference.ps1") -File (Join-Path $Root (Join-Path "projects" (Join-Path "faz2-test" (Join-Path "output" "model.stl")))) -ProjectDir $refTmp 2>&1 | Out-String
  $rj = Get-Content -LiteralPath (Join-Path $refTmp (Join-Path "reference" "reference.json")) -Raw | ConvertFrom-Json
  $bb = (@($rj.bbox_max)[0] - @($rj.bbox_min)[0])
  $ok = ($rj.bbox_known -eq $true -and [math]::Abs($bb - 50) -lt 0.01 -and $rj.facet_count -gt 0)
  Add-VResult "R21-stl-import" $ok $(if ($ok) { "bbox+facet okundu" } else { "okunamadi" })
} catch { Add-VResult "R21-stl-import" $false $_.Exception.Message }
finally { Remove-VTemp $refTmp }

try {
  $t2 = Join-Path ([System.IO.Path]::GetTempPath()) "v13-ref2"
  Remove-VTemp $t2
  New-Item -ItemType Directory -Force -Path $t2 | Out-Null
  & (Join-Path $EngineDir "Analyze-Reference.ps1") -Url "ftp://ornek/dosya.stl" -ProjectDir $t2 2>&1 | Out-Null
  Add-VResult "R22-gecersiz-url" $false "reddedilmedi"
} catch {
  $ok = ($_.Exception.Message -match "http")
  Add-VResult "R22-gecersiz-url" $ok $(if ($ok) { "guvenli red" } else { $_.Exception.Message })
} finally { Remove-VTemp $t2 }

try {
  $t3 = Join-Path ([System.IO.Path]::GetTempPath()) "v13-ref3"
  Remove-VTemp $t3
  New-Item -ItemType Directory -Force -Path $t3 | Out-Null
  & (Join-Path $EngineDir "Analyze-Reference.ps1") -File "C:\yok\dosya.stl" -ProjectDir $t3 2>&1 | Out-Null
  Add-VResult "R23-kayip-dosya" $false "hata vermedi"
} catch { Add-VResult "R23-kayip-dosya" $true "temiz hata" }
finally { Remove-VTemp $t3 }

try {
  $t4 = Join-Path ([System.IO.Path]::GetTempPath()) "v13-ref4"
  Remove-VTemp $t4
  New-Item -ItemType Directory -Force -Path $t4 | Out-Null
  & (Join-Path $EngineDir "Analyze-Reference.ps1") -File (Join-Path $Root (Join-Path "projects" (Join-Path "faz2-test" (Join-Path "output" "model.stl")))) -ProjectDir $t4 2>&1 | Out-Null
  $rj = Join-Path $t4 (Join-Path "reference" "reference.json")
  $sp = Join-Path $t4 "spec.json"
  & (Join-Path $EngineDir "New-ReferenceSpec.ps1") -ReferenceJson $rj -ModPrompt "Bu parcanin aynisini yap ama deligi 8 mm olsun." -ProjectName "r24" -OutSpec $sp 2>&1 | Out-Null
  $s = Get-Content -LiteralPath $sp -Raw | ConvertFrom-Json
  $b = $s.components[0]
  $ok = ([double]$b.base.width_mm -eq 50 -and [double]$b.holes[0].diameter_mm -eq 8)
  Add-VResult "R24-aynisini" $ok $(if ($ok) { "ref olcu + yeni delik" } else { "birlesmedi" })
} catch { Add-VResult "R24-aynisini" $false $_.Exception.Message }
finally { Remove-VTemp $t4 }

try {
  $t5 = Join-Path ([System.IO.Path]::GetTempPath()) "v13-ref5"
  Remove-VTemp $t5
  New-Item -ItemType Directory -Force -Path $t5 | Out-Null
  $rj = [pscustomobject]@{ type = "photo"; bbox_known = $false }
  $rj | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $t5 "ref.json") -Encoding UTF8
  $sp = Join-Path $t5 "spec.json"
  & (Join-Path $EngineDir "New-ReferenceSpec.ps1") -ReferenceJson (Join-Path $t5 "ref.json") -ModPrompt "Aynisini yap." -ProjectName "r25" -OutSpec $sp 2>&1 | Out-Null
  $o = & (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $sp -ProjectDir (Join-Path $t5 "proj") 2>&1 | Out-String
  $stls = @(Get-ChildItem -LiteralPath (Join-Path $t5 "proj") -Recurse -Filter "*.stl" -ErrorAction SilentlyContinue)
  $ok = ($stls.Count -eq 0)
  Add-VResult "R25-bilinmeyen-olcu" $ok $(if ($ok) { "model uretilmedi (BLOCKED)" } else { "uydurulmus olabilir!" })
} catch { Add-VResult "R25-bilinmeyen-olcu" $false $_.Exception.Message }
finally { Remove-VTemp $t5 }

try {
  $o = & (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -ValidateUI 2>&1 | Out-String
  $ok = ($o -match "UI-STARTUP: PASS")
  Add-VResult "R26-ui-startup" $ok $(if ($ok) { "form kuruldu" } else { "kurulmadi" })
} catch { Add-VResult "R26-ui-startup" $false $_.Exception.Message }

try {
  $o = & (Join-Path $Root (Join-Path "scripts" "Build-Exe.ps1")) -PreflightOnly 2>&1 | Out-String
  $ok = ($o -match "PREFLIGHT: PASS")
  Add-VResult "R27-exe-preflight" $ok $(if ($ok) { "derleme hazir" } else { "arac eksik" })
} catch { Add-VResult "R27-exe-preflight" $false $_.Exception.Message }

try {
  $t8 = Join-Path ([System.IO.Path]::GetTempPath()) "v13-ref8"
  Remove-VTemp $t8
  New-Item -ItemType Directory -Force -Path $t8 | Out-Null
  & (Join-Path $EngineDir "Analyze-Reference.ps1") -Url "file:///C:/a.stl" -ProjectDir $t8 2>&1 | Out-Null
  Add-VResult "R28-file-scheme" $false "reddedilmedi"
} catch { Add-VResult "R28-file-scheme" $true "guvenli red" }
finally { Remove-VTemp $t8 }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "V13 SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
