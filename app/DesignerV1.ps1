<#
.SYNOPSIS
  3D AI Designer V1 - masaustu prototip (PowerShell + WinForms, sifir ek bagimlilik).
.DESCRIPTION
  Mimari: UI -> Design Engine (engine/Invoke-DesignEngine.ps1) -> OpenSCAD -> STL -> Validation.
  Motorun icine kopyalanmadi; engine scriptlerini relative path ile cagirir (portable).
  Akis: prompt yaz -> MODEL OLUSTUR -> kucuk parser spec uretir -> eksik kritik olcu
  varsa soru paneli acar -> CEVAP + DEVAM ET -> engine calisir -> sonuc paneli.
  G-code BUTONU YOK (bilerek eklenmedi).
  -SelfTest: pencere acmadan parser + proje listesi + resolver kontrolu yapar (otomatik test icin).
.EXAMPLE
  powershell -File app\DesignerV1.ps1
  powershell -File app\DesignerV1.ps1 -SelfTest
#>
param([switch]$SelfTest)

$ErrorActionPreference = "Stop"
$AppDir = $PSScriptRoot
$Root = Split-Path -Parent $AppDir

function Get-AppSettings {
  $p = Join-Path $Root "settings.json"
  if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json) }
  return $null
}
function Get-ProjectsDir {
  $s = Get-AppSettings
  $p = "projects"
  if ($s -and $s.projectsDir) { $p = $s.projectsDir }
  if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path $Root $p }
  return $p
}
function Get-ProjectList {
  $pd = Get-ProjectsDir
  $list = New-Object System.Collections.Generic.List[pscustomobject]
  if (-not (Test-Path -LiteralPath $pd)) { return @($list) }
  foreach ($d in (Get-ChildItem -LiteralPath $pd -Directory)) {
    if ($d.Name.StartsWith("_")) { continue }
    $hasScad = Test-Path -LiteralPath (Join-Path $d.FullName (Join-Path "cad" "model.scad"))
    $hasStl = Test-Path -LiteralPath (Join-Path $d.FullName (Join-Path "output" "model.stl"))
    $hasVal = Test-Path -LiteralPath (Join-Path $d.FullName (Join-Path "validation" "validation.json"))
    $list.Add([pscustomobject]@{ name = $d.Name; path = $d.FullName; scad = $hasScad; stl = $hasStl; validation = $hasVal })
  }
  return @($list)
}
function Convert-PromptToSpec($promptText, $projectName) {
  # V1 prototip parser: "80x40x20", "delik 25", "duvar 2", "merkez 15,15" kaliblarini okur.
  # Bulamadigi kritik degerleri missing birakir (UYDURMAZ).
  $spec = [pscustomobject]@{
    project_name = $projectName; prompt = $promptText
    body = $null; wall_thickness_mm = $null; holes = @()
    tolerance_mm = $null; material = $null; orientation = $null; special_requirements = @()
  }
  $m = [regex]::Match($promptText, '(\d+(?:[.,]\d+)?)\s*[xX×]\s*(\d+(?:[.,]\d+)?)\s*[xX×]\s*(\d+(?:[.,]\d+)?)')
  if ($m.Success) {
    $spec.body = [pscustomobject]@{
      width_mm = [double]($m.Groups[1].Value -replace ',', '.')
      depth_mm = [double]($m.Groups[2].Value -replace ',', '.')
      height_mm = [double]($m.Groups[3].Value -replace ',', '.')
    }
  }
  $md = [regex]::Match($promptText, 'delik\s*(\d+(?:[.,]\d+)?)')
  $wd = [regex]::Match($promptText, 'duvar\s*(\d+(?:[.,]\d+)?)')
  if ($wd.Success) { $spec.wall_thickness_mm = [double]($wd.Groups[1].Value -replace ',', '.') }
  if ($md.Success) {
    $mc = [regex]::Match($promptText, 'merkez\s*(\d+(?:[.,]\d+)?)\s*[,;]\s*(\d+(?:[.,]\d+)?)')
    $hole = [pscustomobject]@{
      id = "h1"
      diameter_mm = [double]($md.Groups[1].Value -replace ',', '.')
      center_x_mm = $null; center_y_mm = $null; through = $true; status = "missing"
    }
    if ($mc.Success) {
      $hole.center_x_mm = [double]($mc.Groups[1].Value -replace ',', '.')
      $hole.center_y_mm = [double]($mc.Groups[2].Value -replace ',', '.')
      $hole.status = "ok"
    }
    $spec.holes = @($hole)
  }
  return $spec
}
function Get-MissingQuestions($specObj) {
  $q = New-Object System.Collections.Generic.List[string]
  if ($null -eq $specObj.body) { $q.Add("Govde olculeri anlasilmadi. Ornek: 80x40x20 (mm). Govde olcusu nedir?") }
  foreach ($h in @($specObj.holes)) {
    if ($h -and ($h.status -eq "missing" -or $null -eq $h.center_x_mm)) { $q.Add("Delik merkezi eksik (kritik olcu, uydurulamaz). Ornek: merkez 15,15 (referans koseden mm). Delik merkezi nedir?") }
  }
  return @($q)
}

if ($SelfTest) {
  $out = New-Object System.Collections.Generic.List[string]
  $out.Add("SELFTEST: parser")
  $t = Convert-PromptToSpec "80x40x20 mm kutu yap, delik 25, duvar 2" "selftest-proje"
  $out.Add("  body=$($t.body.width_mm)x$($t.body.depth_mm)x$($t.body.height_mm) delik=$($t.holes[0].diameter_mm) merkez-status=$($t.holes[0].status)")
  $q = Get-MissingQuestions $t
  $out.Add("  soru-sayisi=$($q.Count) (beklenen: 1)")
  $t2 = Convert-PromptToSpec "80x40x20 kutu, delik 25 merkez 15,15" "selftest2"
  $q2 = Get-MissingQuestions $t2
  $out.Add("  tam-spec soru-sayisi=$($q2.Count) (beklenen: 0)")
  $out.Add("SELFTEST: projeler")
  foreach ($p in (Get-ProjectList)) { $out.Add("  - $($p.name) (scad=$($p.scad) stl=$($p.stl) validation=$($p.validation))") }
  $out.Add("SELFTEST: resolverlar")
  foreach ($r in @("Resolve-OpenScad.ps1", "Resolve-FreeCad.ps1", "Resolve-OrcaSlicer.ps1")) {
    try { $v = & (Join-Path $Root (Join-Path "scripts" $r)) 2>&1 | Select-Object -Last 1; $out.Add("  $r -> $v") }
    catch { $out.Add("  $r -> BULUNAMADI: $($_.Exception.Message)") }
  }
  $ok = ($t.body.width_mm -eq 80 -and $q.Count -eq 1 -and $q2.Count -eq 0)
  $out.Add($(if ($ok) { "SELFTEST: PASS" } else { "SELFTEST: FAIL" }))
  $out | ForEach-Object { Write-Output $_ }
  if ($ok) { exit 0 } else { exit 1 }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$projectsDir = Get-ProjectsDir
$engineScript = Join-Path $Root (Join-Path "engine" "Invoke-DesignEngine.ps1")
$pipelineScript = Join-Path $Root (Join-Path "engine" "Invoke-Pipeline.ps1")
$currentSpec = $null
$currentSpecPath = ""
$pendingQuestions = @()

$form = New-Object System.Windows.Forms.Form
$form.Text = "3D AI Designer V1.2 (prototip)"
$form.Size = New-Object System.Drawing.Size(720, 900)
$form.StartPosition = "CenterScreen"

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "3D AI DESIGNER"
$lblTitle.Font = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$lblTitle.Location = New-Object System.Drawing.Point(20, 10)
$lblTitle.Size = New-Object System.Drawing.Size(400, 35)
$form.Controls.Add($lblTitle)

$lblProvider = New-Object System.Windows.Forms.Label
$lblProvider.Text = "AI Provider: MOCK (test - gercek AI degil)"
$lblProvider.Location = New-Object System.Drawing.Point(480, 10)
$lblProvider.Size = New-Object System.Drawing.Size(200, 35)
$form.Controls.Add($lblProvider)

$lblAsk = New-Object System.Windows.Forms.Label
$lblAsk.Text = "Ne yapmak istiyorsun?"
$lblAsk.Location = New-Object System.Drawing.Point(20, 50)
$lblAsk.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblAsk)

$txtPrompt = New-Object System.Windows.Forms.TextBox
$txtPrompt.Multiline = $true
$txtPrompt.ScrollBars = "Vertical"
$txtPrompt.Location = New-Object System.Drawing.Point(20, 72)
$txtPrompt.Size = New-Object System.Drawing.Size(450, 90)
$txtPrompt.Text = "80x40x20 mm kutu yap, delik 25, duvar 2"
$form.Controls.Add($txtPrompt)

$btnCreate = New-Object System.Windows.Forms.Button
$btnCreate.Text = "MODEL OLUSTUR"
$btnCreate.Location = New-Object System.Drawing.Point(480, 72)
$btnCreate.Size = New-Object System.Drawing.Size(200, 40)
$form.Controls.Add($btnCreate)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = "Durum: hazir"
$lblStatus.Location = New-Object System.Drawing.Point(20, 170)
$lblStatus.Size = New-Object System.Drawing.Size(660, 20)
$form.Controls.Add($lblStatus)

$lblQ = New-Object System.Windows.Forms.Label
$lblQ.Text = "Sorular:"
$lblQ.Location = New-Object System.Drawing.Point(20, 195)
$lblQ.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblQ)

$txtQuestion = New-Object System.Windows.Forms.TextBox
$txtQuestion.Multiline = $true
$txtQuestion.ReadOnly = $true
$txtQuestion.ScrollBars = "Vertical"
$txtQuestion.Location = New-Object System.Drawing.Point(20, 217)
$txtQuestion.Size = New-Object System.Drawing.Size(450, 60)
$form.Controls.Add($txtQuestion)

$txtAnswer = New-Object System.Windows.Forms.TextBox
$txtAnswer.Location = New-Object System.Drawing.Point(20, 282)
$txtAnswer.Size = New-Object System.Drawing.Size(450, 23)
$txtAnswer.Enabled = $false
$form.Controls.Add($txtAnswer)

$btnContinue = New-Object System.Windows.Forms.Button
$btnContinue.Text = "DEVAM ET"
$btnContinue.Location = New-Object System.Drawing.Point(480, 282)
$btnContinue.Size = New-Object System.Drawing.Size(200, 30)
$btnContinue.Enabled = $false
$form.Controls.Add($btnContinue)

$lblResult = New-Object System.Windows.Forms.Label
$lblResult.Text = "Sonuc:"
$lblResult.Location = New-Object System.Drawing.Point(20, 315)
$lblResult.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblResult)

$lstResult = New-Object System.Windows.Forms.ListBox
$lstResult.Location = New-Object System.Drawing.Point(20, 337)
$lstResult.Size = New-Object System.Drawing.Size(450, 80)
$form.Controls.Add($lstResult)

$btnScad = New-Object System.Windows.Forms.Button
$btnScad.Text = "SCAD'I AC"
$btnScad.Location = New-Object System.Drawing.Point(480, 337)
$btnScad.Size = New-Object System.Drawing.Size(200, 30)
$btnScad.Enabled = $false
$form.Controls.Add($btnScad)

$btnStl = New-Object System.Windows.Forms.Button
$btnStl.Text = "STL'YI AC"
$btnStl.Location = New-Object System.Drawing.Point(480, 372)
$btnStl.Size = New-Object System.Drawing.Size(200, 30)
$btnStl.Enabled = $false
$form.Controls.Add($btnStl)

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = "PROJE KLASORU"
$btnFolder.Location = New-Object System.Drawing.Point(480, 407)
$btnFolder.Size = New-Object System.Drawing.Size(200, 30)
$btnFolder.Enabled = $false
$form.Controls.Add($btnFolder)

$lblProjects = New-Object System.Windows.Forms.Label
$lblProjects.Text = "Projects"
$lblProjects.Location = New-Object System.Drawing.Point(20, 425)
$lblProjects.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblProjects)

$lstProjects = New-Object System.Windows.Forms.ListBox
$lstProjects.Location = New-Object System.Drawing.Point(20, 447)
$lstProjects.Size = New-Object System.Drawing.Size(450, 120)
$form.Controls.Add($lstProjects)

$txtDetail = New-Object System.Windows.Forms.TextBox
$txtDetail.Multiline = $true
$txtDetail.ReadOnly = $true
$txtDetail.ScrollBars = "Vertical"
$txtDetail.Location = New-Object System.Drawing.Point(480, 447)
$txtDetail.Size = New-Object System.Drawing.Size(200, 120)
$form.Controls.Add($txtDetail)

$lblParts = New-Object System.Windows.Forms.Label
$lblParts.Text = "PARCALAR"
$lblParts.Location = New-Object System.Drawing.Point(20, 572)
$lblParts.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblParts)

$lstParts = New-Object System.Windows.Forms.ListBox
$lstParts.Location = New-Object System.Drawing.Point(20, 594)
$lstParts.Size = New-Object System.Drawing.Size(450, 60)
$form.Controls.Add($lstParts)

$lblVal = New-Object System.Windows.Forms.Label
$lblVal.Text = "VALIDATION"
$lblVal.Location = New-Object System.Drawing.Point(480, 572)
$lblVal.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($lblVal)

$lstValidation = New-Object System.Windows.Forms.ListBox
$lstValidation.Location = New-Object System.Drawing.Point(480, 594)
$lstValidation.Size = New-Object System.Drawing.Size(200, 60)
$form.Controls.Add($lstValidation)

$lblHist = New-Object System.Windows.Forms.Label
$lblHist.Text = "SORU/CEVAP GECMISI"
$lblHist.Location = New-Object System.Drawing.Point(20, 659)
$lblHist.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblHist)

$txtHistory = New-Object System.Windows.Forms.TextBox
$txtHistory.Multiline = $true
$txtHistory.ReadOnly = $true
$txtHistory.ScrollBars = "Vertical"
$txtHistory.Location = New-Object System.Drawing.Point(20, 681)
$txtHistory.Size = New-Object System.Drawing.Size(450, 60)
$form.Controls.Add($txtHistory)

$lblWarn = New-Object System.Windows.Forms.Label
$lblWarn.Text = "UYARILAR"
$lblWarn.Location = New-Object System.Drawing.Point(480, 659)
$lblWarn.Size = New-Object System.Drawing.Size(200, 20)
$form.Controls.Add($lblWarn)

$lstWarnings = New-Object System.Windows.Forms.ListBox
$lstWarnings.Location = New-Object System.Drawing.Point(480, 681)
$lstWarnings.Size = New-Object System.Drawing.Size(200, 60)
$form.Controls.Add($lstWarnings)

$lblTools = New-Object System.Windows.Forms.Label
$lblTools.Text = "ARACLAR (first-run denetimi)"
$lblTools.Location = New-Object System.Drawing.Point(20, 746)
$lblTools.Size = New-Object System.Drawing.Size(400, 20)
$form.Controls.Add($lblTools)

$lblToolOS = New-Object System.Windows.Forms.Label
$lblToolOS.Text = "OpenSCAD: denetlenmedi"
$lblToolOS.Location = New-Object System.Drawing.Point(20, 768)
$lblToolOS.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($lblToolOS)

$lblToolFC = New-Object System.Windows.Forms.Label
$lblToolFC.Text = "FreeCAD: denetlenmedi (OPTIONAL)"
$lblToolFC.Location = New-Object System.Drawing.Point(20, 790)
$lblToolFC.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($lblToolFC)

$lblToolOrca = New-Object System.Windows.Forms.Label
$lblToolOrca.Text = "OrcaSlicer: denetlenmedi (OPTIONAL / NOT READY)"
$lblToolOrca.Location = New-Object System.Drawing.Point(20, 812)
$lblToolOrca.Size = New-Object System.Drawing.Size(450, 20)
$form.Controls.Add($lblToolOrca)

$btnToolsRefresh = New-Object System.Windows.Forms.Button
$btnToolsRefresh.Text = "ARACLARI DENETLE"
$btnToolsRefresh.Location = New-Object System.Drawing.Point(480, 768)
$btnToolsRefresh.Size = New-Object System.Drawing.Size(200, 30)
$form.Controls.Add($btnToolsRefresh)

$btnToolOS = New-Object System.Windows.Forms.Button
$btnToolOS.Text = "OpenSCAD Konum Sec..."
$btnToolOS.Location = New-Object System.Drawing.Point(480, 803)
$btnToolOS.Size = New-Object System.Drawing.Size(200, 30)
$form.Controls.Add($btnToolOS)

$script:lastProjectDir = ""
$script:lastScad = ""
$script:lastStl = ""
$script:pipeName = ""
$script:pipeQuestions = @()
$script:pipeAnswers = @{}
$script:history = New-Object System.Collections.Generic.List[string]

function Add-History($t) {
  $script:history.Add($t)
  $txtHistory.Lines = $script:history.ToArray()
}
function Show-ProjectPanels($pd) {
  $lstParts.Items.Clear(); $lstValidation.Items.Clear(); $lstWarnings.Items.Clear()
  $pj = Join-Path $pd "project.json"
  if (Test-Path -LiteralPath $pj) {
    $p = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
    foreach ($part in @($p.parts)) { [void]$lstParts.Items.Add("$($part.id): $($part.status)") }
    [void]$lstValidation.Items.Add("proje: $($p.validation_status)")
  } else {
    foreach ($f in (Get-ChildItem -LiteralPath (Join-Path $pd "output") -Filter "*.stl" -ErrorAction SilentlyContinue)) {
      [void]$lstParts.Items.Add($f.Name)
    }
  }
  $vd = Join-Path $pd "validation"
  if (Test-Path -LiteralPath $vd) {
    foreach ($f in (Get-ChildItem -LiteralPath $vd -Filter "*.json")) {
      try {
        $v = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        [void]$lstValidation.Items.Add("$($f.BaseName): $($v.status)")
        if ($v.categories) {
          [void]$lstValidation.Items.Add("  GEO:$($v.categories.geometry) FEAT:$($v.categories.feature) ASM:$($v.categories.assembly) MFG:$($v.categories.manufacturability)")
        }
        foreach ($w in @($v.warnings)) { [void]$lstWarnings.Items.Add([string]$w) }
        foreach ($w in @($v.design_warnings)) { [void]$lstWarnings.Items.Add([string]$w) }
      } catch { }
    }
  }
}

function Refresh-Projects {
  $lstProjects.Items.Clear()
  foreach ($p in (Get-ProjectList)) { [void]$lstProjects.Items.Add($p.name) }
}
function Set-Status($t) { $lblStatus.Text = "Durum: $t"; $form.Refresh() }
function Save-LocalTool($toolName, $toolPath) {
  $lf = Join-Path $Root "settings.local.json"
  $obj = $null
  if (Test-Path -LiteralPath $lf) {
    try { $obj = Get-Content -LiteralPath $lf -Raw | ConvertFrom-Json } catch { $obj = $null }
  }
  if ($null -eq $obj) { $obj = [pscustomobject]@{ tools = [pscustomobject]@{} } }
  if ($null -eq $obj.tools) { $obj | Add-Member -NotePropertyName "tools" -NotePropertyValue ([pscustomobject]@{}) -Force }
  $obj.tools | Add-Member -NotePropertyName $toolName -NotePropertyValue ([string]$toolPath) -Force
  $obj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $lf -Encoding UTF8
}
function Refresh-Tools {
  $found = @{ openscad = ""; freecad = ""; orcaslicer = "" }
  try { $found.openscad = & (Join-Path $Root (Join-Path "scripts" "Resolve-OpenScad.ps1")) 2>&1 | Select-Object -Last 1 } catch { }
  try { $found.freecad = & (Join-Path $Root (Join-Path "scripts" "Resolve-FreeCad.ps1")) 2>&1 | Select-Object -Last 1 } catch { }
  try { $found.orcaslicer = & (Join-Path $Root (Join-Path "scripts" "Resolve-OrcaSlicer.ps1")) 2>&1 | Out-String } catch { }
  if ($found.openscad -and (Test-Path -LiteralPath ([string]$found.openscad))) { $lblToolOS.Text = "OpenSCAD: BULUNDU" }
  else { $lblToolOS.Text = "OpenSCAD: BULUNAMADI - CAD icin kur veya Konum Sec" }
  if ($found.freecad -and (Test-Path -LiteralPath ([string]$found.freecad))) { $lblToolFC.Text = "FreeCAD: BULUNDU (OPTIONAL)" }
  else { $lblToolFC.Text = "FreeCAD: bulunamadi (OPTIONAL - WARNING sayilir)" }
  if ($found.orcaslicer -and (Test-Path -LiteralPath ([string]$found.orcaslicer))) { $lblToolOrca.Text = "OrcaSlicer: BULUNDU (OPTIONAL / NOT READY)" }
  else { $lblToolOrca.Text = "OrcaSlicer: bulunamadi (OPTIONAL / NOT READY)" }
  $form.Refresh()
  return $found
}
function Friendly-Status($result) {
  if ($null -eq $result) { return "islem basarisiz (detay yok)" }
  $rs = ""
  if ($result.reason) { $rs = [string]$result.reason }
  if ($rs -match "OpenSCAD bulunamadi") { return "OpenSCAD bulunamadi. CAD uretmek icin OpenSCAD kurulmali veya executable konumu secilmelidir." }
  if ($result.status -eq "NEEDS_INPUT") { return "eksik kritik bilgi var - soruyu cevapla, model uretilmedi" }
  if ($result.status -eq "BLOCKED") { return ("uretildi-BLOCKED: " + [string]$result.reason) }
  if ($result.status -eq "FAILED") { return ("uretim basarisiz: " + [string]$result.reason) }
  return [string]$result.status
}
function Fill-ProjectResult($pd, $result) {
  $lstResult.Items.Clear()
  $nm = Split-Path -Leaf $pd
  [void]$lstResult.Items.Add("PROJECT: " + $nm)
  $nParts = 0
  if ($result -and $result.parts) { $nParts = @($result.parts).Count }
  [void]$lstResult.Items.Add("DESIGN: " + $nParts + " parca")
  $stls = @(Get-ChildItem -LiteralPath (Join-Path $pd "output") -Filter "*.stl" -ErrorAction SilentlyContinue)
  if ($stls.Count -gt 0) {
    [void]$lstResult.Items.Add("CAD: PASS")
    [void]$lstResult.Items.Add("STL: PASS (" + $stls.Count + " dosya)")
  } else {
    [void]$lstResult.Items.Add("CAD: yok")
    [void]$lstResult.Items.Add("STL: yok")
  }
  $vs = "yok"
  if ($result) { $vs = [string]$result.status }
  [void]$lstResult.Items.Add("VALIDATION: " + $vs)
  [void]$lstResult.Items.Add("G-CODE: NOT AVAILABLE (printer profile required)")
  if ($result -and $result.reason) { [void]$lstResult.Items.Add("NOT: " + [string]$result.reason) }
  Show-ProjectPanels $pd
  $first = $stls | Select-Object -First 1
  $script:lastScad = ""
  $script:lastStl = ""
  if ($first) {
    $script:lastStl = $first.FullName
    $maybeScad = Join-Path $pd (Join-Path "cad" ([System.IO.Path]::GetFileNameWithoutExtension($first.Name) + ".scad"))
    if (Test-Path -LiteralPath $maybeScad) { $script:lastScad = $maybeScad }
  }
  $hasFiles = ($script:lastStl -ne "")
  $btnScad.Enabled = ($script:lastScad -ne "")
  $btnStl.Enabled = $hasFiles
  $btnFolder.Enabled = $true
}
function Run-Pipeline($answersFile) {
  Set-Status "pipeline calisiyor (parser -> engine -> validation)..."
  try {
    $pargs = @("-Prompt", $txtPrompt.Text, "-ProjectName", $script:pipeName)
    if ($answersFile -ne "") { $pargs += @("-AnswersFile", $answersFile) }
    $o = & $pipelineScript @pargs 2>&1 | Out-String
    $resPath = Join-Path $script:lastProjectDir "pipeline-result.json"
    $result = $null
    if (Test-Path -LiteralPath $resPath) { $result = Get-Content -LiteralPath $resPath -Raw | ConvertFrom-Json }
    Fill-ProjectResult $script:lastProjectDir $result
    if ($result -and $result.status -eq "NEEDS_INPUT") {
      $qs = @($result.questions)
      $script:pipeQuestions = $qs
      if ($qs.Count -gt 0) {
        $txtQuestion.Text = "[" + [string]$qs[0].question_id + "] " + [string]$qs[0].question
        Add-History ("SORU [" + [string]$qs[0].question_id + "]: " + [string]$qs[0].question)
        $txtAnswer.Enabled = $true; $btnContinue.Enabled = $true
      }
      Set-Status (Friendly-Status $result)
    } elseif ($result -and ($result.status -eq "PASS" -or $result.status -eq "WARNING")) {
      $txtQuestion.Text = ""
      $txtAnswer.Enabled = $false; $btnContinue.Enabled = $false
      Set-Status "tamamlandi"
    } else {
      $txtAnswer.Enabled = $false; $btnContinue.Enabled = $false
      Set-Status (Friendly-Status $result)
    }
    Refresh-Projects
  } catch {
    Set-Status ("hata: " + $_.Exception.Message)
  }
}

$btnCreate.Add_Click({
  $lstResult.Items.Clear()
  $lstParts.Items.Clear(); $lstValidation.Items.Clear(); $lstWarnings.Items.Clear()
  $btnScad.Enabled = $false; $btnStl.Enabled = $false; $btnFolder.Enabled = $false
  $script:pipeName = ("proje-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  $script:lastProjectDir = Join-Path $projectsDir $script:pipeName
  $script:pipeAnswers = @{}
  Set-Status "analiz ediliyor..."
  Run-Pipeline ""
})

$btnContinue.Add_Click({
  # V1.1: ham cevap pipeline'a gider; parse + dogrulama engine tarafinda (uydurma yok).
  if ($txtAnswer.Text.Trim() -eq "") { Set-Status "once cevabi yaz"; return }
  if (@($script:pipeQuestions).Count -eq 0) { Set-Status "bekleyen soru yok"; return }
  $qid = [string]$script:pipeQuestions[0].question_id
  Add-History ("CEVAP [" + $qid + "]: " + $txtAnswer.Text)
  $script:pipeAnswers[$qid] = $txtAnswer.Text
  $ansFile = Join-Path ([System.IO.Path]::GetTempPath()) ($script:pipeName + "-cevap.json")
  $ansObj = [pscustomobject]@{}
  foreach ($k in $script:pipeAnswers.Keys) { $ansObj | Add-Member -NotePropertyName $k -NotePropertyValue ([string]$script:pipeAnswers[$k]) }
  $ansObj | ConvertTo-Json | Set-Content -LiteralPath $ansFile -Encoding UTF8
  $txtAnswer.Text = ""
  Run-Pipeline $ansFile
})

$btnScad.Add_Click({ if ($script:lastScad -ne "") { Start-Process -FilePath $script:lastScad } })
$btnStl.Add_Click({ if ($script:lastStl -ne "") { Start-Process -FilePath $script:lastStl } })
$btnFolder.Add_Click({ if ($script:lastProjectDir -ne "") { Start-Process -FilePath $script:lastProjectDir } })

$lstProjects.Add_SelectedIndexChanged({
  if ($lstProjects.SelectedItem -eq $null) { return }
  $pd = Join-Path $projectsDir $lstProjects.SelectedItem.ToString()
  $lines = New-Object System.Collections.Generic.List[string]
  $ip = Join-Path $pd "input.md"; if (Test-Path -LiteralPath $ip) { $lines.Add("Prompt: " + ((Get-Content -LiteralPath $ip -Raw).Trim())) }
  $sp = Join-Path $pd (Join-Path "cad" "model.scad"); if (Test-Path -LiteralPath $sp) { $lines.Add("SCAD: var") } else { $lines.Add("SCAD: yok") }
  $tp = Join-Path $pd (Join-Path "output" "model.stl"); if (Test-Path -LiteralPath $tp) { $lines.Add("STL: var") } else { $lines.Add("STL: yok") }
  $vp = Join-Path $pd (Join-Path "validation" "validation.json")
  if (Test-Path -LiteralPath $vp) { $lines.Add("Validation: " + (Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json).status) }
  $rp = Join-Path $pd "README.md"; if (Test-Path -LiteralPath $rp) { $lines.Add("README: var") } else { $lines.Add("README: yok") }
  $txtDetail.Lines = $lines.ToArray()
  Show-ProjectPanels $pd
})

$btnToolsRefresh.Add_Click({ Refresh-Tools | Out-Null })
$btnToolOS.Add_Click({
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Filter = "OpenSCAD (openscad.com;openscad.exe)|openscad.com;openscad.exe|Tum dosyalar (*.*)|*.*"
  $dlg.Title = "OpenSCAD executable konumunu sec"
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Save-LocalTool "openscad" $dlg.FileName
    Refresh-Tools | Out-Null
    Set-Status "OpenSCAD konumu kaydedildi (settings.local.json)"
  }
})

Refresh-Projects
Refresh-Tools | Out-Null
[void]$form.ShowDialog()
