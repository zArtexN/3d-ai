<#
.SYNOPSIS
  3D AI Designer V1.3 - dark masaustu (PowerShell + WinForms, sifir ek bagimlilik).
.DESCRIPTION
  Mimari: UI -> Invoke-Pipeline (V1.1) / Analyze-Reference + New-ReferenceSpec -> engine -> OpenSCAD -> STL.
  Motorlar cagrilir, kopyalanmaz. Yollar relative (portable). G-code BUTONU YOK.
  Modlar: Tasarla | Referanstan Tasarla | Projeler | Ayarlar.
  -SelfTest: pencere acmadan parser + proje + resolver kontrolu.
.EXAMPLE
  powershell -File app\DesignerV1.ps1
  powershell -File app\DesignerV1.ps1 -SelfTest
#>
param([switch]$SelfTest, [switch]$ValidateUI)

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
    $hasScad = (Get-ChildItem -LiteralPath (Join-Path $d.FullName "cad") -Filter "*.scad" -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    $hasStl = (Get-ChildItem -LiteralPath (Join-Path $d.FullName "output") -Filter "*.stl" -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
    $hasVal = Test-Path -LiteralPath (Join-Path $d.FullName "validation")
    $list.Add([pscustomobject]@{ name = $d.Name; path = $d.FullName; scad = $hasScad; stl = $hasStl; validation = $hasVal })
  }
  return @($list)
}
function Convert-PromptToSpec($promptText, $projectName) {
  $spec = [pscustomobject]@{
    project_name = $projectName; prompt = $promptText
    body = $null; wall_thickness_mm = $null; holes = @()
    tolerance_mm = $null; material = $null; orientation = $null; special_requirements = @()
  }
  $m = [regex]::Match($promptText, '(\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(\d+(?:[.,]\d+)?)\s*[xX\u00d7]\s*(\d+(?:[.,]\d+)?)')
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

$C_BG = [System.Drawing.ColorTranslator]::FromHtml("#0B0F14")
$C_PANEL = [System.Drawing.ColorTranslator]::FromHtml("#111821")
$C_INPUT = [System.Drawing.ColorTranslator]::FromHtml("#161F2A")
$C_BORDER = [System.Drawing.ColorTranslator]::FromHtml("#253241")
$C_TEXT = [System.Drawing.ColorTranslator]::FromHtml("#E8EEF5")
$C_MUTED = [System.Drawing.ColorTranslator]::FromHtml("#8D9AAA")
$C_ACCENT = [System.Drawing.ColorTranslator]::FromHtml("#20D6C7")
$C_OK = [System.Drawing.ColorTranslator]::FromHtml("#35D07F")
$C_WARN = [System.Drawing.ColorTranslator]::FromHtml("#E5B94F")
$C_ERR = [System.Drawing.ColorTranslator]::FromHtml("#F05D6E")

$projectsDir = Get-ProjectsDir
$engineScript = Join-Path $Root (Join-Path "engine" "Invoke-DesignEngine.ps1")
$pipelineScript = Join-Path $Root (Join-Path "engine" "Invoke-Pipeline.ps1")
$refScript = Join-Path $Root (Join-Path "engine" "Analyze-Reference.ps1")
$refSpecScript = Join-Path $Root (Join-Path "engine" "New-ReferenceSpec.ps1")

$currentSpec = $null
$currentSpecPath = ""
$pendingQuestions = @()

function New-DLabel($txt, $x, $y, $w, $h, $sz) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $txt
  $l.Location = New-Object System.Drawing.Point($x, $y)
  $l.Size = New-Object System.Drawing.Size($w, $h)
  $l.ForeColor = $C_TEXT
  $l.BackColor = [System.Drawing.Color]::Transparent
  if ($sz -gt 0) { $l.Font = New-Object System.Drawing.Font("Segoe UI", $sz, [System.Drawing.FontStyle]::Bold) }
  else { $l.Font = New-Object System.Drawing.Font("Segoe UI", 9) }
  return $l
}
function New-DButton($txt, $x, $y, $w, $h) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $txt
  $b.Location = New-Object System.Drawing.Point($x, $y)
  $b.Size = New-Object System.Drawing.Size($w, $h)
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderColor = $C_BORDER
  $b.BackColor = $C_INPUT
  $b.ForeColor = $C_TEXT
  $b.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
  return $b
}
function New-DText($x, $y, $w, $h, $multi) {
  $t = New-Object System.Windows.Forms.TextBox
  $t.Location = New-Object System.Drawing.Point($x, $y)
  $t.Size = New-Object System.Drawing.Size($w, $h)
  $t.BackColor = $C_INPUT
  $t.ForeColor = $C_TEXT
  $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $t.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  if ($multi) { $t.Multiline = $true; $t.ScrollBars = "Vertical" }
  return $t
}
function New-DList($x, $y, $w, $h) {
  $l = New-Object System.Windows.Forms.ListBox
  $l.Location = New-Object System.Drawing.Point($x, $y)
  $l.Size = New-Object System.Drawing.Size($w, $h)
  $l.BackColor = $C_INPUT
  $l.ForeColor = $C_TEXT
  $l.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $l.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  return $l
}
function New-DBadge($txt, $x, $y, $w) {
  $l = New-DLabel $txt $x $y $w 24 0
  $l.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
  $l.BackColor = $C_BORDER
  return $l
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "3D AI Designer V1.3"
$form.Size = New-Object System.Drawing.Size(1120, 720)
$form.StartPosition = "CenterScreen"
$form.BackColor = $C_BG
$form.ForeColor = $C_TEXT

$side = New-Object System.Windows.Forms.Panel
$side.Location = New-Object System.Drawing.Point(0, 0)
$side.Size = New-Object System.Drawing.Size(180, 700)
$side.BackColor = $C_PANEL
$form.Controls.Add($side)

$sideTitle = New-DLabel "3D AI`nDESIGNER" 15 12 150 50 13
$side.Controls.Add($sideTitle)
$btnNavNew = New-DButton "Yeni Proje" 15 75 150 34
$btnNavDesign = New-DButton "Tasarla" 15 115 150 34
$btnNavRef = New-DButton "Referanstan Tasarla" 15 155 150 34
$btnNavProj = New-DButton "Projeler" 15 195 150 34
$btnNavSet = New-DButton "Ayarlar" 15 235 150 34
foreach ($b in @($btnNavNew, $btnNavDesign, $btnNavRef, $btnNavProj, $btnNavSet)) { $side.Controls.Add($b) }
$lblProvSide = New-DLabel "AI Provider:`nMOCK (test)" 15 620 150 50 0
$lblProvSide.ForeColor = $C_MUTED
$side.Controls.Add($lblProvSide)

$center = New-Object System.Windows.Forms.Panel
$center.Location = New-Object System.Drawing.Point(180, 0)
$center.Size = New-Object System.Drawing.Size(560, 700)
$center.BackColor = $C_BG
$form.Controls.Add($center)

$right = New-Object System.Windows.Forms.Panel
$right.Location = New-Object System.Drawing.Point(740, 0)
$right.Size = New-Object System.Drawing.Size(365, 700)
$right.BackColor = $C_PANEL
$form.Controls.Add($right)

function New-ModePanel {
  $p = New-Object System.Windows.Forms.Panel
  $p.Location = New-Object System.Drawing.Point(0, 0)
  $p.Size = New-Object System.Drawing.Size(560, 700)
  $p.BackColor = $C_BG
  $p.Visible = $false
  $center.Controls.Add($p)
  return $p
}
$pnlDesign = New-ModePanel
$pnlRef = New-ModePanel
$pnlProj = New-ModePanel
$pnlSet = New-ModePanel
$script:uiMode = ""
function Show-Mode($p) {
  foreach ($m in @($pnlDesign, $pnlRef, $pnlProj, $pnlSet)) { $m.Visible = $false }
  $p.Visible = $true
  if ($p -eq $pnlDesign) { $script:uiMode = "design" }
  elseif ($p -eq $pnlRef) { $script:uiMode = "ref" }
  elseif ($p -eq $pnlProj) { $script:uiMode = "proj" }
  else { $script:uiMode = "set" }
}

# ---- TASARLA ----
$pnlDesign.Controls.Add((New-DLabel "Tasarim Olustur" 20 12 500 32 15))
$pnlDesign.Controls.Add((New-DLabel "Dogal dil ile ne uretmek istiyorsun?" 20 50 500 20 0))
$txtPrompt = New-DText 20 74 520 86 $true
$txtPrompt.Text = "80x40x20 mm kutu yap, delik 25, duvar 2"
$pnlDesign.Controls.Add($txtPrompt)
$btnCreate = New-DButton "TASARLA" 20 168 520 40
$btnCreate.BackColor = $C_ACCENT
$btnCreate.ForeColor = [System.Drawing.Color]::Black
$pnlDesign.Controls.Add($btnCreate)
$lblStatus = New-DLabel "Durum: hazir" 20 214 520 20 0
$lblStatus.ForeColor = $C_MUTED
$pnlDesign.Controls.Add($lblStatus)
$pnlDesign.Controls.Add((New-DLabel "SORULAR" 20 240 520 20 0))
$txtQuestion = New-DText 20 262 520 56 $true
$txtQuestion.ReadOnly = $true
$pnlDesign.Controls.Add($txtQuestion)
$txtAnswer = New-DText 20 322 350 26 $false
$txtAnswer.Enabled = $false
$pnlDesign.Controls.Add($txtAnswer)
$btnContinue = New-DButton "DEVAM ET" 378 322 162 26
$btnContinue.Enabled = $false
$pnlDesign.Controls.Add($btnContinue)
$pnlDesign.Controls.Add((New-DLabel "PIPELINE DURUMU" 20 356 520 20 0))
$badgeSpec = New-DBadge "DesignSpec -" 20 380 120
$badgeCAD = New-DBadge "CAD -" 148 380 120
$badgeSTL = New-DBadge "STL -" 276 380 120
$badgeVal = New-DBadge "Validation -" 404 380 116
$pnlDesign.Controls.Add($badgeSpec)
$pnlDesign.Controls.Add($badgeCAD)
$pnlDesign.Controls.Add($badgeSTL)
$pnlDesign.Controls.Add($badgeVal)
$badgeGcode = New-DBadge "G-Code: NOT AVAILABLE" 20 408 500
$badgeGcode.BackColor = $C_BORDER
$badgeGcode.ForeColor = $C_MUTED
$pnlDesign.Controls.Add($badgeGcode)
$pnlDesign.Controls.Add((New-DLabel "DETAY" 20 438 520 20 0))
$lstResult = New-DList 20 460 520 200
$pnlDesign.Controls.Add($lstResult)

# ---- REFERANS ----
$pnlRef.Controls.Add((New-DLabel "Referanstan Tasarla" 20 12 500 32 15))
$pnlRef.Controls.Add((New-DLabel "REFERANS MODEL" 20 50 500 20 0))
$txtRefUrl = New-DText 20 72 520 26 $false
$pnlRef.Controls.Add($txtRefUrl)
$btnRefBrowse = New-DButton "Dosya Sec (STL/3MF/STEP)" 20 104 250 30
$pnlRef.Controls.Add($btnRefBrowse)
$lblRefFile = New-DLabel "dosya secilmedi" 278 104 242 30 0
$lblRefFile.ForeColor = $C_MUTED
$pnlRef.Controls.Add($lblRefFile)
$btnRefAnalyze = New-DButton "Referansi Analiz Et" 20 140 520 34
$btnRefAnalyze.BackColor = $C_ACCENT
$btnRefAnalyze.ForeColor = [System.Drawing.Color]::Black
$pnlRef.Controls.Add($btnRefAnalyze)
$lstRefResult = New-DList 20 182 520 150
$pnlRef.Controls.Add($lstRefResult)
$pnlRef.Controls.Add((New-DLabel "DEGISIKLIK KOMUTU (orn: aynisini yap ama deligi 8 mm olsun)" 20 340 520 20 0))
$txtRefMod = New-DText 20 362 520 60 $true
$txtRefMod.Text = "Bu parcanin aynisini yap."
$pnlRef.Controls.Add($txtRefMod)
$btnRefBuild = New-DButton "Referanstan Uret" 20 428 520 36
$btnRefBuild.Enabled = $false
$pnlRef.Controls.Add($btnRefBuild)
$pnlRef.Controls.Add((New-DLabel "Olcu bilinmiyorsa uydurulmaz, sorulur." 20 470 520 20 0))

# ---- PROJELER ----
$pnlProj.Controls.Add((New-DLabel "Projeler" 20 12 500 32 15))
$lstProjects = New-DList 20 50 520 200
$pnlProj.Controls.Add($lstProjects)
$txtDetail = New-DText 20 258 520 200 $true
$txtDetail.ReadOnly = $true
$pnlProj.Controls.Add($txtDetail)

# ---- AYARLAR ----
$pnlSet.Controls.Add((New-DLabel "Ayarlar" 20 12 500 32 15))
$lblToolOS = New-DLabel "OpenSCAD: denetlenmedi" 20 60 500 24 0
$lblToolFC = New-DLabel "FreeCAD: denetlenmedi (OPTIONAL)" 20 88 500 24 0
$lblToolOrca = New-DLabel "OrcaSlicer: denetlenmedi (OPTIONAL / NOT READY)" 20 116 500 24 0
$pnlSet.Controls.Add($lblToolOS)
$pnlSet.Controls.Add($lblToolFC)
$pnlSet.Controls.Add($lblToolOrca)
$btnToolsRefresh = New-DButton "ARACLARI DENETLE" 20 150 250 32
$pnlSet.Controls.Add($btnToolsRefresh)
$btnToolOS = New-DButton "OpenSCAD Konum Sec..." 278 150 242 32
$pnlSet.Controls.Add($btnToolOS)
$pnlSet.Controls.Add((New-DLabel "AI Provider: MOCK (test - gercek AI degil)" 20 200 500 24 0))
$pnlSet.Controls.Add((New-DLabel "Secimler settings.local.json dosyasina kaydolur (git disi)." 20 228 500 24 0))

# ---- SAG PANEL ----
$right.Controls.Add((New-DLabel "PROJE" 15 12 330 28 13))
$lblProjName = New-DLabel "-" 15 44 330 22 0
$lblProjName.ForeColor = $C_ACCENT
$right.Controls.Add($lblProjName)
$right.Controls.Add((New-DLabel "PARCALAR" 15 72 330 20 0))
$lstParts = New-DList 15 94 330 90
$right.Controls.Add($lstParts)
$right.Controls.Add((New-DLabel "VALIDATION" 15 190 330 20 0))
$lstValidation = New-DList 15 212 330 90
$right.Controls.Add($lstValidation)
$right.Controls.Add((New-DLabel "UYARILAR" 15 308 330 20 0))
$lstWarnings = New-DList 15 330 330 80
$right.Controls.Add($lstWarnings)
$right.Controls.Add((New-DLabel "SORU/CEVAP GECMISI" 15 416 330 20 0))
$txtHistory = New-DText 15 438 330 90 $true
$txtHistory.ReadOnly = $true
$right.Controls.Add($txtHistory)
$btnScad = New-DButton "SCAD'I AC" 15 536 105 30
$btnStl = New-DButton "STL'YI AC" 126 536 105 30
$btnFolder = New-DButton "KLASORU AC" 237 536 108 30
$btnScad.Enabled = $false; $btnStl.Enabled = $false; $btnFolder.Enabled = $false
$right.Controls.Add($btnScad)
$right.Controls.Add($btnStl)
$right.Controls.Add($btnFolder)

$script:lastProjectDir = ""
$script:lastScad = ""
$script:lastStl = ""
$script:pipeName = ""
$script:pipePrompt = ""
$script:pipeRefSpec = ""
$script:pipeQuestions = @()
$script:pipeAnswers = @{}
$script:history = New-Object System.Collections.Generic.List[string]
$script:refJson = ""
$script:refStage = ""

function Set-Status($t) { $lblStatus.Text = "Durum: $t"; $form.Refresh() }
function Add-History($t) {
  $script:history.Add($t)
  $txtHistory.Lines = $script:history.ToArray()
}
function Set-Badge($b, $txt, $color) {
  $b.Text = $txt
  $b.BackColor = $color
  if ($color -eq $C_BORDER) { $b.ForeColor = $C_MUTED } else { $b.ForeColor = [System.Drawing.Color]::Black }
  $form.Refresh()
}
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
  $fOS = ""; $fFC = ""; $fOrca = ""
  try { $fOS = & (Join-Path $Root (Join-Path "scripts" "Resolve-OpenScad.ps1")) 2>&1 | Select-Object -Last 1 } catch { }
  try { $fFC = & (Join-Path $Root (Join-Path "scripts" "Resolve-FreeCad.ps1")) 2>&1 | Select-Object -Last 1 } catch { }
  try { $fOrca = & (Join-Path $Root (Join-Path "scripts" "Resolve-OrcaSlicer.ps1")) 2>&1 | Select-Object -Last 1 } catch { }
  if ($fOS -and (Test-Path -LiteralPath ([string]$fOS))) { $lblToolOS.Text = "OpenSCAD: BULUNDU"; $lblToolOS.ForeColor = $C_OK }
  else { $lblToolOS.Text = "OpenSCAD: BULUNAMADI - CAD icin kur veya Konum Sec"; $lblToolOS.ForeColor = $C_ERR }
  if ($fFC -and (Test-Path -LiteralPath ([string]$fFC))) { $lblToolFC.Text = "FreeCAD: BULUNDU (OPTIONAL)"; $lblToolFC.ForeColor = $C_OK }
  else { $lblToolFC.Text = "FreeCAD: bulunamadi (OPTIONAL - WARNING sayilir)"; $lblToolFC.ForeColor = $C_WARN }
  if ($fOrca -and (Test-Path -LiteralPath ([string]$fOrca))) { $lblToolOrca.Text = "OrcaSlicer: BULUNDU (OPTIONAL / NOT READY)"; $lblToolOrca.ForeColor = $C_OK }
  else { $lblToolOrca.Text = "OrcaSlicer: bulunamadi (OPTIONAL / NOT READY)"; $lblToolOrca.ForeColor = $C_WARN }
  $form.Refresh()
}
function Show-ProjectPanels($pd) {
  $lstParts.Items.Clear(); $lstValidation.Items.Clear(); $lstWarnings.Items.Clear()
  $lblProjName.Text = Split-Path -Leaf $pd
  $pj = Join-Path $pd "project.json"
  if (Test-Path -LiteralPath $pj) {
    try {
      $p = Get-Content -LiteralPath $pj -Raw | ConvertFrom-Json
      foreach ($part in @($p.parts)) { [void]$lstParts.Items.Add("$($part.id): $($part.status)") }
      [void]$lstValidation.Items.Add("proje: $($p.validation_status)")
    } catch { }
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
        $vn = ([string]$f.BaseName -replace '\.validation$', '')
        [void]$lstValidation.Items.Add("$vn : $($v.status)")
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
function Friendly-Status($result) {
  if ($null -eq $result) { return "islem basarisiz (detay yok)" }
  $rs = ""
  if ($result.reason) { $rs = [string]$result.reason }
  if ($rs -match "OpenSCAD bulunamadi") { return "OpenSCAD bulunamadi. CAD uretmek icin OpenSCAD kurulmali veya Ayarlar > Araclar > Konum Sec ile gosterilmelidir." }
  if ($result.status -eq "NEEDS_INPUT") { return "eksik kritik bilgi var - soruyu cevapla, model uretilmedi" }
  if ($result.status -eq "BLOCKED") { return ("uretildi-BLOCKED: " + $rs) }
  if ($result.status -eq "FAILED") { return ("uretim basarisiz: " + $rs) }
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
  $vstat = "yok"
  if ($result) { $vstat = [string]$result.status }
  if ($stls.Count -gt 0) {
    Set-Badge $badgeCAD "CAD: PASS" $C_OK
    Set-Badge $badgeSTL ("STL: PASS (" + $stls.Count + ")") $C_OK
    [void]$lstResult.Items.Add("CAD: PASS")
    [void]$lstResult.Items.Add("STL: PASS (" + $stls.Count + " dosya)")
  } else {
    Set-Badge $badgeCAD "CAD: yok" $C_ERR
    Set-Badge $badgeSTL "STL: yok" $C_ERR
    [void]$lstResult.Items.Add("CAD: yok")
    [void]$lstResult.Items.Add("STL: yok")
  }
  if ($vstat -eq "PASS") { Set-Badge $badgeVal "Validation: PASS" $C_OK }
  elseif ($vstat -eq "WARNING") { Set-Badge $badgeVal "Validation: WARNING" $C_WARN }
  elseif ($vstat -eq "NEEDS_INPUT" -or $vstat -eq "BLOCKED" -or $vstat -eq "FAILED") { Set-Badge $badgeVal ("Validation: " + $vstat) $C_ERR }
  else { Set-Badge $badgeVal "Validation: -" $C_BORDER }
  Set-Badge $badgeSpec "DesignSpec: v2" $C_OK
  [void]$lstResult.Items.Add("VALIDATION: " + $vstat)
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
  $btnScad.Enabled = ($script:lastScad -ne "")
  $btnStl.Enabled = ($script:lastStl -ne "")
  $btnFolder.Enabled = $true
}
function Run-Pipeline($answersFile) {
  Set-Status "pipeline calisiyor (parser -> engine -> validation)..."
  try {
    $prompt = $txtPrompt.Text
    if ($script:pipePrompt -ne "") { $prompt = $script:pipePrompt }
    $pargs = @{ Prompt = $prompt; ProjectName = $script:pipeName; ProjectDir = $script:lastProjectDir }
    if ($script:pipeRefSpec -ne "") { $pargs.RefSpecFile = $script:pipeRefSpec }
    if ($answersFile -ne "") { $pargs.AnswersFile = $answersFile }
    $o = & $pipelineScript @pargs 2>&1 | Out-String
    $resPath = Join-Path $script:lastProjectDir "pipeline-result.json"
    $result = $null
    if (Test-Path -LiteralPath $resPath) {
      $rtxt = Get-Content -LiteralPath $resPath -Raw
      $result = $rtxt | ConvertFrom-Json
    }
    Fill-ProjectResult $script:lastProjectDir $result
    if ($result -and $result.status -eq "NEEDS_INPUT") {
      $qs = @()
      if ($result.questions) {
        if ($result.questions -is [array]) { $qs = $result.questions }
        else { $qs = @($result.questions) }
      }
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

$btnNavNew.Add_Click({
  $txtPrompt.Text = ""
  $script:pipePrompt = ""
  Show-Mode $pnlDesign
})
$btnNavDesign.Add_Click({ Show-Mode $pnlDesign })
$btnNavRef.Add_Click({ Show-Mode $pnlRef })
$btnNavProj.Add_Click({ Refresh-Projects; Show-Mode $pnlProj })
$btnNavSet.Add_Click({ Refresh-Tools; Show-Mode $pnlSet })

$btnCreate.Add_Click({
  $lstResult.Items.Clear()
  $lstParts.Items.Clear(); $lstValidation.Items.Clear(); $lstWarnings.Items.Clear()
  $btnScad.Enabled = $false; $btnStl.Enabled = $false; $btnFolder.Enabled = $false
  Set-Badge $badgeSpec "DesignSpec: ..." $C_BORDER
  Set-Badge $badgeCAD "CAD: ..." $C_BORDER
  Set-Badge $badgeSTL "STL: ..." $C_BORDER
  Set-Badge $badgeVal "Validation: ..." $C_BORDER
  $script:pipeName = ("proje-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  $script:pipePrompt = ""
  $script:pipeRefSpec = ""
  $script:lastProjectDir = Join-Path $projectsDir $script:pipeName
  $script:pipeAnswers = @{}
  Set-Status "analiz ediliyor..."
  Run-Pipeline ""
})

$btnContinue.Add_Click({
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
$btnToolsRefresh.Add_Click({ Refresh-Tools })
$btnToolOS.Add_Click({
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Filter = "OpenSCAD (openscad.com;openscad.exe)|openscad.com;openscad.exe|Tum dosyalar (*.*)|*.*"
  $dlg.Title = "OpenSCAD executable konumunu sec"
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    Save-LocalTool "openscad" $dlg.FileName
    Refresh-Tools
    Set-Status "OpenSCAD konumu kaydedildi (settings.local.json)"
  }
})

$lstProjects.Add_SelectedIndexChanged({
  if ($lstProjects.SelectedItem -eq $null) { return }
  $pd = Join-Path $projectsDir $lstProjects.SelectedItem.ToString()
  $lines = New-Object System.Collections.Generic.List[string]
  $ip = Join-Path $pd "input.md"; if (Test-Path -LiteralPath $ip) { $lines.Add("Prompt: " + ((Get-Content -LiteralPath $ip -Raw).Trim())) }
  $sp = Join-Path $pd "input.json"; if (Test-Path -LiteralPath $sp) { $lines.Add("DesignSpec: var") }
  $sp2 = Join-Path $pd "spec.json"; if (Test-Path -LiteralPath $sp2) { $lines.Add("DesignSpec v2: var") }
  $pj = Join-Path $pd "project.json"; if (Test-Path -LiteralPath $pj) { $lines.Add("project.json: var") }
  $rp = Join-Path $pd "reference"; if (Test-Path -LiteralPath $rp) { $lines.Add("referans: var") }
  $txtDetail.Lines = $lines.ToArray()
  Show-ProjectPanels $pd
})

$btnRefBrowse.Add_Click({
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Filter = "3D model (STL/3MF/STEP)|*.stl;*.3mf;*.step;*.stp|Tum dosyalar (*.*)|*.*"
  $dlg.Title = "Referans dosya sec (kopyalanir, degistirilmez)"
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $script:refFile = $dlg.FileName
    $script:refUrl = ""
    $lblRefFile.Text = [System.IO.Path]::GetFileName($dlg.FileName)
  }
})
$btnRefAnalyze.Add_Click({
  $lstRefResult.Items.Clear()
  $btnRefBuild.Enabled = $false
  $script:refStage = Join-Path ([System.IO.Path]::GetTempPath()) ("refstage-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  New-Item -ItemType Directory -Force -Path $script:refStage | Out-Null
  try {
    if ($txtRefUrl.Text.Trim() -ne "") {
      $o = & $refScript -Url $txtRefUrl.Text.Trim() -ProjectDir $script:refStage 2>&1 | Out-String
    } elseif ($script:refFile -and (Test-Path -LiteralPath $script:refFile)) {
      $o = & $refScript -File $script:refFile -ProjectDir $script:refStage 2>&1 | Out-String
    } else {
      [void]$lstRefResult.Items.Add("URL yapistir veya Dosya Sec.")
      return
    }
    foreach ($ln in ($o -split '\r\n|\r|\n')) {
      $t = $ln.Trim()
      if ($t -ne "") { [void]$lstRefResult.Items.Add($t) }
    }
    $rj = Join-Path $script:refStage (Join-Path "reference" "reference.json")
    if (Test-Path -LiteralPath $rj) {
      $script:refJson = $rj
      $btnRefBuild.Enabled = $true
    }
  } catch {
    [void]$lstRefResult.Items.Add("HATA: " + $_.Exception.Message)
  }
})
$btnRefBuild.Add_Click({
  if ($script:refJson -eq "" -or -not (Test-Path -LiteralPath $script:refJson)) { return }
  $script:pipeName = ("ref-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  $script:lastProjectDir = Join-Path $projectsDir $script:pipeName
  New-Item -ItemType Directory -Force -Path $script:lastProjectDir | Out-Null
  $specOut = Join-Path $script:lastProjectDir "spec.json"
  try {
    & $refSpecScript -ReferenceJson $script:refJson -ModPrompt $txtRefMod.Text -ProjectName $script:pipeName -OutSpec $specOut 2>&1 | Out-Null
    $refDst = Join-Path $script:lastProjectDir "reference"
    New-Item -ItemType Directory -Force -Path $refDst | Out-Null
    Copy-Item -LiteralPath $script:refJson -Destination $refDst -Force
    $rj = Get-Content -LiteralPath $script:refJson -Raw | ConvertFrom-Json
    if ($rj.local_path -and (Test-Path -LiteralPath ([string]$rj.local_path))) {
      Copy-Item -LiteralPath ([string]$rj.local_path) -Destination $refDst -Force
    }
    $script:pipeRefSpec = $specOut
    $script:pipePrompt = ""
    $script:pipeAnswers = @{}
    Show-Mode $pnlDesign
    Set-Status "referans spec olustu, pipeline calisiyor..."
    Run-Pipeline ""
  } catch {
    Set-Status ("hata: " + $_.Exception.Message)
  }
})

Show-Mode $pnlDesign
Refresh-Projects
Refresh-Tools
if ($ValidateUI) {
  $checks = New-Object System.Collections.Generic.List[string]
  foreach ($c in @($txtPrompt, $btnCreate, $txtQuestion, $txtAnswer, $btnContinue, $lstResult, $txtRefUrl, $btnRefBrowse, $btnRefAnalyze, $lstRefResult, $txtRefMod, $btnRefBuild, $lstProjects, $txtDetail, $lstParts, $lstValidation, $lstWarnings, $txtHistory, $btnScad, $btnStl, $btnFolder, $lblToolOS, $btnToolsRefresh, $btnToolOS)) {
    if ($null -eq $c) { $checks.Add("eksik-kontrol") }
  }
  $tabsOk = ($script:uiMode -eq "design")
  if ($checks.Count -eq 0 -and $tabsOk) { Write-Output "UI-STARTUP: PASS"; exit 0 }
  else { Write-Output "UI-STARTUP: FAIL"; exit 1 }
}
[void]$form.ShowDialog()
