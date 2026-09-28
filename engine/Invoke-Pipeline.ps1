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
  [string]$Prompt = "",
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

if ($Prompt.Trim() -eq "" -and $RefSpecFile -eq "") {
  $msg = "Tasarim prompt'u bulunamadi. Yeni proje baslatin."
  [pscustomobject]@{
    status = "BLOCKED"; stage = "prompt"; provider = $Provider; reason = $msg
    questions = @(); parts = @(); gcode_available = $false
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $ProjectDir "pipeline-result.json") -Encoding UTF8
  Write-Output $msg
  exit 2
}

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

# 1a. Kanonik model (Adim A, spec 2.1): eski div* component'ler divider_pattern'e
# katlanir ve dosyaya geri yazilir (sonraki asamalara kanonik spec girer).
. (Join-Path $EngineDir "CanonicalSpec.ps1")
try {
  $canonSpec = ConvertTo-CanonicalSpec (Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json)
  $canonSpec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $specPath -Encoding UTF8
  Write-PLog $ProjectDir "parser.log" "CANONICAL spec=spec.json"
} catch {
  Write-PLog $ProjectDir "parser.log" ("CANONICAL-FAIL " + $_.Exception.Message)
}

# Stale tespiti (uyari; silme YOK, kullanici dosyalarina dokunulmaz):
# spec'te olmayan div* uretim dosyalari (eski model kalintisi) raporlanir.
$staleList = New-Object System.Collections.Generic.List[string]
try {
  $specIds = @(@($canonSpec.components) | Where-Object { $_ -ne $null } | ForEach-Object { [string]$_.id })
  $specDivN = 0
  $specBody = @(@($canonSpec.components) | Where-Object { $_ -and [string]$_.id -eq "body" })
  if ($specBody.Count -gt 0 -and $null -ne $specBody[0].divider_pattern -and $null -ne $specBody[0].divider_pattern.count) {
    $specDivN = [int]$specBody[0].divider_pattern.count
  }
  foreach ($sd in @(@{ d = "output"; f = "*.stl" }, @{ d = "cad"; f = "*.scad" }, @{ d = "validation"; f = "*.validation.json" })) {
    $dd = Join-Path $ProjectDir $sd.d
    if (-not (Test-Path -LiteralPath $dd)) { continue }
    foreach ($fl in (Get-ChildItem -LiteralPath $dd -Filter $sd.f -ErrorAction SilentlyContinue)) {
      $bn = [string]$fl.BaseName -replace '\.validation$', ''
      if ($bn -like "divider_*") {
        # Yeni model urunu: pattern yoksa ya da numarasi adedi asiyorsa stale.
        $dm = [regex]::Match($bn, 'divider_(\d+)$')
        $dn = 0
        if ($dm.Success) { $dn = [int]$dm.Groups[1].Value }
        if ($specDivN -eq 0 -or $dn -gt $specDivN -or $dn -lt 1) { $staleList.Add(($sd.d + "/" + $fl.Name)) | Out-Null }
      } elseif ($bn -like "div*" -and $specIds -notcontains $bn) {
        $staleList.Add(($sd.d + "/" + $fl.Name)) | Out-Null
      }
    }
  }
  if ($staleList.Count -gt 0) { Write-PLog $ProjectDir "parser.log" ("STALE " + ($staleList -join "; ")) }
} catch {
  Write-PLog $ProjectDir "parser.log" ("STALE-FAIL " + $_.Exception.Message)
}

# 1b. Explicit-fact ledger + trace (bilgi-kaybi mimarisi: parse asamasinda fact'ler cikarilir).
$factsPath = Join-Path $ProjectDir "explicit-facts.json"
$mentionsPath = Join-Path $ProjectDir "explicit-mentions.json"
$traceScript = Join-Path $EngineDir "Write-PipelineTrace.ps1"
function Write-Trace($stage, $obj) {
  try {
    $j = ($obj | ConvertTo-Json -Depth 6 -Compress)
    & $traceScript -ProjectDir $ProjectDir -Stage $stage -DataJson $j 2>&1 | Out-Null
  } catch { }
}
try {
  $factsTxt = & (Join-Path $EngineDir "Get-ExplicitFacts.ps1") -Prompt $Prompt -OutPath $factsPath 2>&1 | Out-String
  $factsObj = $null
  if (Test-Path -LiteralPath $factsPath) { $factsObj = Get-Content -LiteralPath $factsPath -Raw | ConvertFrom-Json }
  $fc = 0
  if ($factsObj -and $factsObj.facts) { $fc = @($factsObj.facts).Count }
  Write-Trace "parse" ([pscustomobject]@{ spec = "spec.json"; facts = $fc; facts_file = "explicit-facts.json" })
  Write-PLog $ProjectDir "parser.log" ("FACTS n=" + $fc)
} catch {
  Write-PLog $ProjectDir "parser.log" ("FACTS-FAIL " + $_.Exception.Message)
}
# Adim D: bagimsiz mention cikarimi (ham metindeki sayi ifadeleri; advisory).
try {
  $menObj = $null
  if ($Prompt.Trim() -ne "") {
    & (Join-Path $EngineDir "Get-NumericMentions.ps1") -Prompt $Prompt -OutPath $mentionsPath 2>&1 | Out-Null
    if (Test-Path -LiteralPath $mentionsPath) { $menObj = Get-Content -LiteralPath $mentionsPath -Raw | ConvertFrom-Json }
  }
  $mc = 0
  if ($menObj -and $menObj.mentions) { $mc = @($menObj.mentions).Count }
  Write-PLog $ProjectDir "parser.log" ("MENTIONS n=" + $mc)
} catch {
  Write-PLog $ProjectDir "parser.log" ("MENTIONS-FAIL " + $_.Exception.Message)
}

# 2. Sorular (guncel spec) + cevaplar (varsa)
function Save-Questions {
  $qsTxt = & (Join-Path $EngineDir "Get-SpecQuestions.ps1") -SpecFile $specPath -AsJson 2>&1 | Out-String
  $qsRaw = $qsTxt | ConvertFrom-Json
  $qsArr = @($qsRaw | Where-Object { $_ -ne $null })
  @($qsArr) | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qPath -Encoding UTF8
  return $qsArr
}
function Trace-Questions($qsArr, $tag) {
  try {
    $specNow = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
    $items = New-Object System.Collections.Generic.List[object]
    foreach ($qq in @($qsArr)) {
      if ($null -eq $qq) { continue }
      $mp = [string]$qq.kind
      if ([string]$qq.kind -eq "cutout") {
        $parts = @()
        $c0 = $null
        foreach ($cc in @($specNow.components)) {
          if ($cc -and [string]$cc.id -eq [string]$qq.component) { $c0 = $cc; break }
        }
        if ($null -ne $c0) {
          $tid = ([string]$qq.field -replace '^cutouts\.', '')
          foreach ($tt in @($c0.cutouts)) {
            if ($tt -and [string]$tt.id -eq $tid) {
              if ($null -eq $tt.width_mm -or $null -eq $tt.length_mm) { $parts += "size" }
              if ($null -eq $tt.pos_x_mm) { $parts += "pos_x" }
              if ($null -eq $tt.pos_y_mm) { $parts += "pos_y" }
              if ($null -eq $tt.depth_mm -and [string]$tt.penetration -ne "through_wall") { $parts += "depth" }
            }
          }
        }
        if ($parts.Count -gt 0) { $mp = ("cutout:" + ($parts -join ",")) }
      }
      $items.Add([pscustomobject]@{
        question_id = [string]$qq.question_id; type = [string]$qq.kind; target = [string]$qq.target
        missing_property = $mp; question = [string]$qq.question
      })
    }
    Write-Trace ("questions-" + $tag) ([pscustomobject]@{ count = @($qsArr).Count; questions = @($items.ToArray()) })
  } catch { }
}
function Trace-Coverage($tag) {
  try {
    $covArgs = @{ SpecFile = $specPath; FactsFile = $factsPath; QuestionsFile = $qPath; AsJson = $true }
    if (Test-Path -LiteralPath $mentionsPath) { $covArgs["MentionsFile"] = $mentionsPath }
    $covTxt = & (Join-Path $EngineDir "Test-FactCoverage.ps1") @covArgs 2>&1 | Out-String
    $cov = $covTxt | ConvertFrom-Json
    if ($null -ne $cov) { Write-Trace ("coverage-" + $tag) $cov }
  } catch { }
}
$qsNow = Save-Questions
Trace-Questions $qsNow "initial"
Trace-Coverage "initial"
if ($AnswersFile -ne "") {
  if (-not (Test-Path -LiteralPath $AnswersFile)) { throw "Cevap dosyasi bulunamadi: $AnswersFile" }
  $AnswersJson = Get-Content -LiteralPath $AnswersFile -Raw
}
if ($AnswersJson -ne "") {
  try { $ansMap = $AnswersJson | ConvertFrom-Json } catch { throw "Cevap JSON okunamadi: $_" }
  $prevAnswers = @{}
  try {
    $qPrevRaw = Get-Content -LiteralPath $qPath -Raw | ConvertFrom-Json
    foreach ($qe in @($qPrevRaw)) {
      if ($qe -and $qe.question_id -and $null -ne $qe.answer) { $prevAnswers[[string]$qe.question_id] = [string]$qe.answer }
    }
  } catch { }
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
  Trace-Questions $qsNow "after-answers"
  try {
    $apd = New-Object System.Collections.Generic.List[object]
    foreach ($prop in $ansMap.PSObject.Properties) { $apd.Add(([string]$prop.Name + "=" + [string]$prop.Value)) }
    Write-Trace "answers" ([pscustomobject]@{ applied = @($apd.ToArray()); errors = @($ansErrors.ToArray()) })
  } catch { }
  Trace-Coverage "after-answers"
  # Soru-cevap dongu tespiti: ayni soruya ust uste AYNI cevap verilip soru acik kalirsa
  # NEEDS_INPUT + acik dongu nedeni (trace'e de yazilir). Farkli deger = ilerleme, dongu degil.
  $loopHits = New-Object System.Collections.Generic.List[string]
  if ($AnswersJson -ne "") {
    foreach ($prop in $ansMap.PSObject.Properties) {
      $pv = ""
      if ($prevAnswers.ContainsKey([string]$prop.Name)) { $pv = $prevAnswers[[string]$prop.Name] }
      if ($pv -ne "" -and $pv -eq [string]$prop.Value) {
        foreach ($qn in @($qsNow)) {
          if ($qn -and [string]$qn.question_id -eq [string]$prop.Name) {
            $loopHits.Add(([string]$prop.Name + " (target=" + [string]$qn.target + ", tur=" + [string]$qn.kind + ")"))
          }
        }
      }
    }
  }
  if ($loopHits.Count -gt 0) {
    Write-Trace "loop-detected" ([pscustomobject]@{ questions = @($loopHits.ToArray()) })
    Write-PLog $ProjectDir "parser.log" ("DONGU " + ($loopHits -join "; "))
  }
  if ($ansErrors.Count -gt 0) {
    $firstErr = [string]($ansErrors.ToArray() | Select-Object -First 1)
    Write-PResult ([pscustomobject]@{
      status = "NEEDS_INPUT"; stage = "answers"; provider = $providerName
      reason = ("Cevap islenemedi: " + $firstErr + " (ornek formata uygun cevapla tekrar soruluyor)")
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
  $gateReason = $(if ($st -eq "NEEDS_INPUT") { "kritik eksik var; model uretilmedi" } else { "cozulemeyen hata; model uretilmedi" })
  if ($loopHits.Count -gt 0) { $gateReason += " DONGU TESPITI (ayni cevap cozmedi): " + ($loopHits -join "; ") }
  Write-Trace "gate" ([pscustomobject]@{ status = $st; errors = @($gateErrors.ToArray()) })
  Write-PResult ([pscustomobject]@{
    status = $st; stage = "gate"; provider = $providerName
    reason = $gateReason
    errors = @($gateErrors.ToArray()); questions = @($qsNow)
    parts = @(); gcode_available = $false
    stale_artifacts = @($staleList.ToArray())
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
      # Stale kalinti sayilmaz (uyari olarak raporlanir; silinmez).
      if (@($staleList) -contains ("validation/" + $f.Name)) {
        Write-PLog $ProjectDir "validation.log" ("STALE-SKIP " + $f.Name + " (sayilmadi)")
        continue
      }
      $v = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
      $partId = ([string]$f.BaseName -replace '\.validation$', '')
      $parts.Add([pscustomobject]@{ id = $partId; status = [string]$v.status })
      if ($v.status -eq "BLOCKED" -or $v.status -eq "FAILED_AFTER_RETRIES" -or $v.status -eq "FAIL") { $worst = "FAILED" }
      elseif ($v.status -eq "WARNING" -and $worst -eq "PASS") { $worst = "WARNING" }
      Write-PLog $ProjectDir "validation.log" ($f.BaseName + " " + [string]$v.status)
    } catch { }
  }
}
$finalStatus = $worst
if ($engCode -ne 0 -and $worst -eq "PASS") { $finalStatus = "FAILED" }
if ($finalStatus -eq "FAILED" -and $parts.Count -eq 0) { $finalStatus = "BLOCKED" }

Write-Trace "done" ([pscustomobject]@{ status = $finalStatus; parts = @($parts.ToArray() | ForEach-Object { $_.id }) })
Write-PResult ([pscustomobject]@{
  status = $finalStatus; stage = "done"; provider = $providerName
  reason = $(if ($finalStatus -eq "PASS" -or $finalStatus -eq "WARNING") { "proje tamamlandi" } else { "uretim basarisiz; detay validation dosyalari" })
  questions = @(); parts = @($parts.ToArray()); gcode_available = $false
  stale_artifacts = @($staleList.ToArray())
  gcode_note = "NOT AVAILABLE - printer profile required"
}) $(if ($finalStatus -eq "PASS" -or $finalStatus -eq "WARNING") { 0 } else { 2 })
