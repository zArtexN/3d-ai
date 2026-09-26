<#
.SYNOPSIS
  V1.2 uretim hatti: prompt -> parser/AI -> sorular -> geometry engine -> OpenSCAD -> STL -> validation.
.DESCRIPTION
  Akis:
    1. AI/provider (varsayilan MOCK) DesignSpec v2 uretir. AI dogrudan SCAD/STL/G-code URETEMEZ.
    2. Spec gate: JSON zorunlu alan + Test-GeometrySpec (guvenilmez cikti BLOCKED olur, CAD yok).
    3. Kritik eksik varsa NEEDS_INPUT + sorular doner (model URETILMEZ). -Answers ile cevaplar uygulanir.
    4. Eksik yoksa Invoke-GeometryEngine calisir (tek gecis; retry engine icinde max 3).
    5. logs/parser.log, logs/engine.log, logs/validation.log yazilir (spam yok, kisa satirlar).
    6. Sonuc JSON: status PASS/WARNING/BLOCKED/NEEDS_INPUT/FAILED + parts + validation + gcode_available:false.
  G-code URETILMEZ. Yollar root'a goreceli (portable).
.EXAMPLE
  powershell -File engine\Invoke-Pipeline.ps1 -Prompt "..." -ProjectName demo
  powershell -File engine\Invoke-Pipeline.ps1 -Prompt "..." -ProjectName demo -AnswersJson '{"q1":"15,15"}'
#>
param(
  [Parameter(Mandatory = $true)][string]$Prompt,
  [Parameter(Mandatory = $true)][string]$ProjectName,
  [string]$Provider = "MOCK",
  [string]$ProjectDir = "",
  [string]$AnswersJson = "",
  [string]$AnswersFile = "",
  [string]$RefSpecFile = "",
  [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir

function Get-PSettings {
  $p = Join-Path $Root "settings.json"
  if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }
  return $null
}
function Write-PLog($dir, $name, $line) {
  $ld = Join-Path $dir "logs"
  New-Item -ItemType Directory -Force -Path $ld | Out-Null
  ((Get-Date).ToUniversalTime().ToString("o") + " " + $line) | Add-Content -LiteralPath (Join-Path $ld $name) -Encoding UTF8
}

$psettings = Get-PSettings
if ($ProjectDir -eq "") {
  $pdir = "projects"
  if ($psettings -and $psettings.projectsDir) { $pdir = $psettings.projectsDir }
  if (-not [System.IO.Path]::IsPathRooted($pdir)) { $pdir = Join-Path $Root $pdir }
  $ProjectDir = Join-Path $pdir $ProjectName
}
New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
$specPath = Join-Path $ProjectDir "spec.json"
$qPath = [System.IO.Path]::ChangeExtension($specPath, ".questions.json")

function Write-PResult($obj, $code) {
  $obj | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ProjectDir "pipeline-result.json") -Encoding UTF8
  $obj | ConvertTo-Json -Depth 6
  exit $code
}

# 1. AI/provider -> DesignSpec (veya hazir referans spec)
$providerName = $Provider
if ($RefSpecFile -ne "") {
  if (-not (Test-Path -LiteralPath $RefSpecFile)) { throw "Referans spec bulunamadi: $RefSpecFile" }
  if ([System.IO.Path]::GetFullPath($RefSpecFile) -ne [System.IO.Path]::GetFullPath($specPath)) {
    Copy-Item -LiteralPath $RefSpecFile -Destination $specPath -Force
  }
  $providerName = "REF"
  Write-PLog $ProjectDir "parser.log" "REF-OK spec=spec.json (referans tabanli)"
} else {
try {
  $aiTxt = & (Join-Path $EngineDir "AIProvider.ps1") -Provider $Provider -Prompt $Prompt -ProjectName $ProjectName -OutSpec $specPath 2>&1 | Out-String
  $ai = $aiTxt | ConvertFrom-Json
} catch {
  Write-PLog $ProjectDir "parser.log" ("AI-FAIL " + $_.Exception.Message)
  Write-PResult ([pscustomobject]@{
    status = "BLOCKED"; stage = "ai"; provider = $Provider; reason = $_.Exception.Message
    questions = @(); parts = @(); gcode_available = $false
  }) 2
}
$providerName = [string]$ai.provider
Write-PLog $ProjectDir "parser.log" ("AI-OK provider=" + $providerName + " spec=spec.json")
}

# 2. Sorular (guncel spec) + cevaplar (varsa)
function Save-Questions {
  $qsTxt = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $specPath -AsJson 2>&1 | Out-String
  $qsRaw = $qsTxt | ConvertFrom-Json
  $qsArr = @($qsRaw | Where-Object { $_ -ne $null })
  @($qsArr) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qPath -Encoding UTF8
  return $qsArr
}
$qsNow = Save-Questions
if ($AnswersFile -ne "") {
  if (-not (Test-Path -LiteralPath $AnswersFile)) { throw "Cevap dosyasi bulunamadi: $AnswersFile" }
  $AnswersJson = Get-Content -LiteralPath $AnswersFile -Raw
}
if ($AnswersJson -ne "") {
  try { $ansMap = $AnswersJson | ConvertFrom-Json } catch { throw "Cevap JSON okunamadi: $_" }
  $ansErrors = New-Object System.Collections.Generic.List[string]
  foreach ($prop in $ansMap.PSObject.Properties) {
    try {
      & (Join-Path $EngineDir "Update-SpecAnswer.ps1") -SpecFile $specPath -QuestionId $prop.Name -Answer ([string]$prop.Value) 2>&1 | Out-Null
      Write-PLog $ProjectDir "parser.log" ("CEVAP " + $prop.Name + "=" + [string]$prop.Value)
    } catch {
      $msg = [string]$_.Exception.Message
      Write-PLog $ProjectDir "parser.log" ("CEVAP-HATA " + $prop.Name + ": " + $msg)
      $ansErrors.Add($prop.Name + ": " + $msg)
    }
  }
  $qsNow = Save-Questions
  if ($ansErrors.Count -gt 0) {
    Write-PResult ([pscustomobject]@{
      status = "NEEDS_INPUT"; stage = "answers"; provider = $providerName
      reason = "Bazi cevaplar anlasilmadi; ayni sorular ornek formata uygun cevapla tekrar soruluyor"
      errors = @($ansErrors.ToArray()); questions = @($qsNow)
      parts = @(); gcode_available = $false
    }) 3
  }
}

# 3. Spec gate: guvenilmez-cikti denetimi (sorular cevaplandiysa geometri de gecerli olmali)
$gateErrors = New-Object System.Collections.Generic.List[string]
try { $gateSpec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json } catch { $gateSpec = $null }
if ($null -eq $gateSpec) { $gateErrors.Add("spec JSON okunamadi") }
else {
  if ($null -eq $gateSpec.project_name) { $gateErrors.Add("project_name eksik") }
  if ($null -eq $gateSpec.components -or @($gateSpec.components).Count -eq 0) { $gateErrors.Add("components eksik") }
}
if ($gateErrors.Count -eq 0) {
  $gvTxt = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile $specPath -AsJson 2>&1 | Out-String
  $gv = $gvTxt | ConvertFrom-Json
  foreach ($e in @($gv.errors)) { $gateErrors.Add([string]$e) }
}
if ($gateErrors.Count -gt 0) {
  $st = "BLOCKED"
  if (@($qsNow).Count -gt 0) { $st = "NEEDS_INPUT" }
  elseif ($NonInteractive) { $st = "BLOCKED" }
  Write-PLog $ProjectDir "parser.log" ("GATE-" + $st + " hata=" + $gateErrors.Count)
  foreach ($qq in $qsNow) { Write-PLog $ProjectDir "parser.log" ("SORU " + $qq.question_id + ": " + $qq.question) }
  Write-PResult ([pscustomobject]@{
    status = $st; stage = "gate"; provider = $providerName
    reason = $(if ($st -eq "NEEDS_INPUT") { "kritik eksik var; model uretilmedi" } else { "cozulemeyen hata; model uretilmedi" })
    errors = @($gateErrors.ToArray()); questions = @($qsNow)
    parts = @(); gcode_available = $false
  }) 3
}

# 4. Geometry engine (tek gecis)
Write-PLog $ProjectDir "engine.log" "ENGINE-START"
$engOut = & (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $specPath -ProjectDir $ProjectDir 2>&1 | Out-String
$engCode = $LASTEXITCODE
Write-PLog $ProjectDir "engine.log" ("ENGINE-EXIT kod=" + $engCode)
foreach ($ln in ($engOut -split '\r\n|\r|\n' | Where-Object { $_ -match "GENGINE|WARNING|ERROR" } | Select-Object -First 20)) {
  Write-PLog $ProjectDir "engine.log" $ln.Trim()
}

# 5. Sonuc toplama
$parts = New-Object System.Collections.Generic.List[object]
$worst = "PASS"
$vd = Join-Path $ProjectDir "validation"
if (Test-Path -LiteralPath $vd) {
  foreach ($f in (Get-ChildItem -LiteralPath $vd -Filter "*.validation.json")) {
    try {
      $v = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
      $pid = ([string]$f.BaseName -replace '\.validation$', '')
      $parts.Add([pscustomobject]@{ id = $pid; status = [string]$v.status })
      if ($v.status -eq "BLOCKED" -or $v.status -eq "FAILED_AFTER_RETRIES" -or $v.status -eq "FAIL") { $worst = "FAILED" }
      elseif ($v.status -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
      Write-PLog $ProjectDir "validation.log" ($f.BaseName + " " + [string]$v.status)
    } catch { }
  }
}
$finalStatus = $worst
if ($engCode -ne 0 -and $worst -eq "PASS") { $finalStatus = "FAILED" }
if ($finalStatus -eq "FAILED" -and $parts.Count -eq 0) { $finalStatus = "BLOCKED" }

Write-PResult ([pscustomobject]@{
  status = $finalStatus; stage = "done"; provider = $providerName
  reason = $(if ($finalStatus -eq "PASS" -or $finalStatus -eq "WARNING") { "proje tamamlandi" } else { "uretim basarisiz; detay validation dosyalari" })
  questions = @(); parts = @($parts.ToArray()); gcode_available = $false
  gcode_note = "NOT AVAILABLE - printer profile required"
}) $(if ($finalStatus -eq "PASS" -or $finalStatus -eq "WARNING") { 0 } else { 2 })
