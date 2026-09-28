<#
.SYNOPSIS
  3D AI Designer V2.0 - FDM 3D Baski Muhendisi Asistani (PowerShell + WinForms).
.DESCRIPTION
  Mimari: UI -> Invoke-Pipeline (V1.1) / Analyze-Reference + New-ReferenceSpec -> engine -> OpenSCAD -> STL.
  Yeni V2.0: Printability Analyzer, Orientation Advisor, Mesh Quality, Cost Estimation,
  Printer Setup Wizard, Material Browser, Troubleshooting, Knowledge Base.
  Motorlar cagrilir, kopyalanmaz. Yollar relative (portable). G-code BUTONU YOK.
  Modlar: Ana Sayfa | Tasarla | Referanstan Tasarla | Projeler | Yazicilar | Filamentler | Baski Analizi | Ayarlar.
  -SelfTest: pencere acmadan parser + proje + resolver kontrolu.
.EXAMPLE
  powershell -File app\DesignerV1.ps1
  powershell -File app\DesignerV1.ps1 -SelfTest
#>
param([switch]$SelfTest, [switch]$ValidateUI, [switch]$UITest)

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

# ========== RENK PALETI ==========
$C_BG       = [System.Drawing.ColorTranslator]::FromHtml("#0A0E13")
$C_PANEL    = [System.Drawing.ColorTranslator]::FromHtml("#0F1520")
$C_SIDEBAR  = [System.Drawing.ColorTranslator]::FromHtml("#0C1018")
$C_INPUT    = [System.Drawing.ColorTranslator]::FromHtml("#141D28")
$C_BORDER   = [System.Drawing.ColorTranslator]::FromHtml("#1E2D3D")
$C_TEXT     = [System.Drawing.ColorTranslator]::FromHtml("#E0E8F0")
$C_MUTED    = [System.Drawing.ColorTranslator]::FromHtml("#6B7A8D")
$C_ACCENT   = [System.Drawing.ColorTranslator]::FromHtml("#00D4AA")
$C_ACCENT2  = [System.Drawing.ColorTranslator]::FromHtml("#0099FF")
$C_OK       = [System.Drawing.ColorTranslator]::FromHtml("#2ECC71")
$C_WARN     = [System.Drawing.ColorTranslator]::FromHtml("#F39C12")
$C_ERR      = [System.Drawing.ColorTranslator]::FromHtml("#E74C3C")
$C_CARD     = [System.Drawing.ColorTranslator]::FromHtml("#121A25")
$C_HOVER    = [System.Drawing.ColorTranslator]::FromHtml("#1A2636")

$projectsDir = Get-ProjectsDir
$engineScript = Join-Path $Root (Join-Path "engine" "Invoke-DesignEngine.ps1")
$pipelineScript = Join-Path $Root (Join-Path "engine" "Invoke-Pipeline.ps1")
$refScript = Join-Path $Root (Join-Path "engine" "Analyze-Reference.ps1")
$refSpecScript = Join-Path $Root (Join-Path "engine" "New-ReferenceSpec.ps1")
$printabilityScript = Join-Path $Root (Join-Path "engine" "Analyze-Printability.ps1")
$orientationScript = Join-Path $Root (Join-Path "engine" "Analyze-Orientation.ps1")
$meshQualityScript = Join-Path $Root (Join-Path "engine" "Get-MeshQuality.ps1")
$estimateScript = Join-Path $Root (Join-Path "engine" "Estimate-Print.ps1")
$slicerScript = Join-Path $Root (Join-Path "engine" "Invoke-Slicer.ps1")

$currentSpec = $null
$currentSpecPath = ""
$pendingQuestions = @()

# ========== UI YARDIMCI FONKSIYONLARI ==========
function New-DLabel($txt, $x, $y, $w, $h, $sz) {
  $l = New-Object System.Windows.Forms.Label
  $l.Text = $txt; $l.Location = New-Object System.Drawing.Point($x, $y)
  $l.Size = New-Object System.Drawing.Size($w, $h)
  $l.ForeColor = $C_TEXT; $l.BackColor = [System.Drawing.Color]::Transparent
  if ($sz -gt 0) { $l.Font = New-Object System.Drawing.Font("Segoe UI", $sz, [System.Drawing.FontStyle]::Bold) }
  else { $l.Font = New-Object System.Drawing.Font("Segoe UI", 9) }
  return $l
}
function New-DButton($txt, $x, $y, $w, $h) {
  $b = New-Object System.Windows.Forms.Button
  $b.Text = $txt; $b.Location = New-Object System.Drawing.Point($x, $y)
  $b.Size = New-Object System.Drawing.Size($w, $h)
  $b.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
  $b.FlatAppearance.BorderColor = $C_BORDER
  $b.FlatAppearance.MouseOverBackColor = $C_HOVER
  $b.BackColor = $C_INPUT; $b.ForeColor = $C_TEXT
  $b.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
  $b.Cursor = [System.Windows.Forms.Cursors]::Hand
  return $b
}
function New-DText($x, $y, $w, $h, $multi) {
  $t = New-Object System.Windows.Forms.TextBox
  $t.Location = New-Object System.Drawing.Point($x, $y)
  $t.Size = New-Object System.Drawing.Size($w, $h)
  $t.BackColor = $C_INPUT; $t.ForeColor = $C_TEXT
  $t.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
  $t.Font = New-Object System.Drawing.Font("Segoe UI", 9)
  if ($multi) { $t.Multiline = $true; $t.ScrollBars = "Vertical" }
  return $t
}
function New-DList($x, $y, $w, $h) {
  $l = New-Object System.Windows.Forms.ListBox
  $l.Location = New-Object System.Drawing.Point($x, $y)
  $l.Size = New-Object System.Drawing.Size($w, $h)
  $l.BackColor = $C_INPUT; $l.ForeColor = $C_TEXT
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
function New-DCard($x, $y, $w, $h) {
  $p = New-Object System.Windows.Forms.Panel
  $p.Location = New-Object System.Drawing.Point($x, $y)
  $p.Size = New-Object System.Drawing.Size($w, $h)
  $p.BackColor = $C_CARD
  $p.BorderStyle = [System.Windows.Forms.BorderStyle]::None
  return $p
}

# ========== ANA FORM ==========
$versionFile = Join-Path $Root "VERSION"
$appVersion = "V2.0"
if (Test-Path -LiteralPath $versionFile) { $appVersion = (Get-Content -LiteralPath $versionFile -Raw).Trim() }

$form = New-Object System.Windows.Forms.Form
$form.Text = "3D AI Designer $appVersion"
try {
  $iconPath = Join-Path $Root (Join-Path "assets" "app.ico")
  if (Test-Path -LiteralPath $iconPath) { $form.Icon = New-Object System.Drawing.Icon($iconPath) }
} catch { }
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.StartPosition = "CenterScreen"
$form.BackColor = $C_BG
$form.ForeColor = $C_TEXT
$form.MinimumSize = New-Object System.Drawing.Size(1100, 700)

# ========== SIDEBAR ==========
$side = New-Object System.Windows.Forms.Panel
$side.Dock = [System.Windows.Forms.DockStyle]::Left
$side.Width = 200
$side.BackColor = $C_SIDEBAR
$form.Controls.Add($side)

$sideTitle = New-DLabel "3D AI`nDESIGNER" 18 14 170 48 14
$sideTitle.ForeColor = $C_ACCENT
$side.Controls.Add($sideTitle)

$lblVersion = New-DLabel $appVersion 18 62 170 18 0
$lblVersion.ForeColor = $C_MUTED
$side.Controls.Add($lblVersion)

$btnNavHome    = New-DButton "  Ana Sayfa"       12 92  176 34
$btnNavNew     = New-DButton "  Yeni Tasarim"    12 130 176 34
$btnNavDesign  = New-DButton "  Tasarla"         12 168 176 34
$btnNavRef     = New-DButton "  Referanstan"     12 206 176 34
$btnNavProj    = New-DButton "  Projeler"        12 244 176 34
$btnNavPrint   = New-DButton "  Yazicilar"       12 290 176 34
$btnNavFilam   = New-DButton "  Filamentler"     12 328 176 34
$btnNavAnalyze = New-DButton "  Baski Analizi"   12 366 176 34
$btnNavSet     = New-DButton "  Ayarlar"         12 412 176 34

# Sidebar button style
foreach ($b in @($btnNavHome, $btnNavNew, $btnNavDesign, $btnNavRef, $btnNavProj, $btnNavPrint, $btnNavFilam, $btnNavAnalyze, $btnNavSet)) {
  $b.FlatAppearance.BorderSize = 0
  $b.BackColor = [System.Drawing.Color]::Transparent
  $b.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
  $b.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
  $side.Controls.Add($b)
}

$lblProvSide = New-DLabel "AI: MOCK (test)" 18 700 170 30 0
$lblProvSide.ForeColor = $C_MUTED
$lblProvSide.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left
$side.Controls.Add($lblProvSide)

# ========== CENTER + RIGHT PANELS ==========
$center = New-Object System.Windows.Forms.Panel
$center.Location = New-Object System.Drawing.Point(200, 0)
$center.Size = New-Object System.Drawing.Size(680, 770)
$center.BackColor = $C_BG
$center.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
$form.Controls.Add($center)

$right = New-Object System.Windows.Forms.Panel
$right.Location = New-Object System.Drawing.Point(880, 0)
$right.Size = New-Object System.Drawing.Size(385, 770)
$right.BackColor = $C_PANEL
$right.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right -bor [System.Windows.Forms.AnchorStyles]::Bottom
$form.Controls.Add($right)

function New-ModePanel {
  $p = New-Object System.Windows.Forms.Panel
  $p.Location = New-Object System.Drawing.Point(0, 0)
  $p.Size = New-Object System.Drawing.Size(680, 770)
  $p.BackColor = $C_BG
  $p.Visible = $false
  $p.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Right
  $center.Controls.Add($p)
  return $p
}
$pnlHome    = New-ModePanel
$pnlDesign  = New-ModePanel
$pnlRef     = New-ModePanel
$pnlProj    = New-ModePanel
$pnlPrinter = New-ModePanel
$pnlFilam   = New-ModePanel
$pnlAnalyze = New-ModePanel
$pnlSet     = New-ModePanel
$script:uiMode = ""
$script:activeNavBtn = $null

function Show-Mode($p, $navBtn) {
  foreach ($m in @($pnlHome, $pnlDesign, $pnlRef, $pnlProj, $pnlPrinter, $pnlFilam, $pnlAnalyze, $pnlSet)) { $m.Visible = $false }
  $p.Visible = $true
  # Reset sidebar highlight
  foreach ($b in @($btnNavHome, $btnNavNew, $btnNavDesign, $btnNavRef, $btnNavProj, $btnNavPrint, $btnNavFilam, $btnNavAnalyze, $btnNavSet)) {
    $b.BackColor = [System.Drawing.Color]::Transparent
    $b.ForeColor = $C_TEXT
  }
  if ($null -ne $navBtn) {
    $navBtn.BackColor = $C_HOVER
    $navBtn.ForeColor = $C_ACCENT
    $script:activeNavBtn = $navBtn
  }
  if ($p -eq $pnlHome) { $script:uiMode = "home" }
  elseif ($p -eq $pnlDesign) { $script:uiMode = "design" }
  elseif ($p -eq $pnlRef) { $script:uiMode = "ref" }
  elseif ($p -eq $pnlProj) { $script:uiMode = "proj" }
  elseif ($p -eq $pnlPrinter) { $script:uiMode = "printer" }
  elseif ($p -eq $pnlFilam) { $script:uiMode = "filam" }
  elseif ($p -eq $pnlAnalyze) { $script:uiMode = "analyze" }
  else { $script:uiMode = "set" }
}

# ========== ANA SAYFA ==========
$pnlHome.Controls.Add((New-DLabel "3D AI Designer" 30 20 600 40 18))
$lblHomeSub = New-DLabel "FDM 3D Baski Muhendisi Asistani" 30 62 600 24 0
$lblHomeSub.ForeColor = $C_MUTED
$pnlHome.Controls.Add($lblHomeSub)

$lblHomePrompt = New-DLabel "Ne yapmak istiyorsun?" 30 110 600 30 13
$pnlHome.Controls.Add($lblHomePrompt)
$txtHomePrompt = New-DText 30 148 620 80 $true
$txtHomePrompt.Font = New-Object System.Drawing.Font("Segoe UI", 11)
$pnlHome.Controls.Add($txtHomePrompt)

$btnHomeGo = New-DButton "TASARLA" 30 236 620 42
$btnHomeGo.BackColor = $C_ACCENT
$btnHomeGo.ForeColor = [System.Drawing.Color]::Black
$btnHomeGo.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$pnlHome.Controls.Add($btnHomeGo)

# Quick Actions
$pnlHome.Controls.Add((New-DLabel "HIZLI ISLEMLER" 30 300 600 22 0))
$btnQNew   = New-DButton "Yeni Parca"     30  328 146 50
$btnQRef   = New-DButton "Referanstan"     184 328 146 50
$btnQStl   = New-DButton "STL Analiz Et"  338 328 146 50
$btnQPrint = New-DButton "Baskiya Hazirla" 492 328 158 50
foreach ($qb in @($btnQNew, $btnQRef, $btnQStl, $btnQPrint)) {
  $qb.BackColor = $C_CARD
  $pnlHome.Controls.Add($qb)
}

$pnlHome.Controls.Add((New-DLabel "SON PROJELER" 30 400 600 22 0))
$lstHomeProj = New-DList 30 426 620 200
$pnlHome.Controls.Add($lstHomeProj)

# ========== TASARLA ==========
$pnlDesign.Controls.Add((New-DLabel "Tasarim Olustur" 20 12 600 32 15))
$pnlDesign.Controls.Add((New-DLabel "Dogal dil ile ne uretmek istiyorsun?" 20 50 600 20 0))
$txtPrompt = New-DText 20 74 640 86 $true
$txtPrompt.Text = "80x40x20 mm kutu yap, delik 25, duvar 2"
$pnlDesign.Controls.Add($txtPrompt)
$btnCreate = New-DButton "TASARLA" 20 168 640 40
$btnCreate.BackColor = $C_ACCENT
$btnCreate.ForeColor = [System.Drawing.Color]::Black
$pnlDesign.Controls.Add($btnCreate)
$lblStatus = New-DLabel "Durum: hazir" 20 214 640 20 0
$lblStatus.ForeColor = $C_MUTED
$pnlDesign.Controls.Add($lblStatus)
$pnlDesign.Controls.Add((New-DLabel "SORULAR" 20 240 640 20 0))
$txtQuestion = New-DText 20 262 640 56 $true
$txtQuestion.ReadOnly = $true
$pnlDesign.Controls.Add($txtQuestion)
$txtAnswer = New-DText 20 322 470 26 $false
$txtAnswer.Enabled = $false
$pnlDesign.Controls.Add($txtAnswer)
$btnContinue = New-DButton "DEVAM ET" 498 322 162 26
$btnContinue.Enabled = $false
$pnlDesign.Controls.Add($btnContinue)

# Pipeline badges
$pnlDesign.Controls.Add((New-DLabel "PIPELINE" 20 356 640 20 0))
$badgeSpec  = New-DBadge "Spec -"       20  380 95
$badgeCAD   = New-DBadge "CAD -"        120 380 95
$badgeSTL   = New-DBadge "STL -"        220 380 95
$badgeVal   = New-DBadge "Valid. -"     320 380 95
$badgePrint = New-DBadge "Print. -"     420 380 95
$badgeSlicer = New-DBadge "Slicer: N/A" 520 380 140
$pnlDesign.Controls.Add($badgeSpec);  $pnlDesign.Controls.Add($badgeCAD)
$pnlDesign.Controls.Add($badgeSTL);   $pnlDesign.Controls.Add($badgeVal)
$pnlDesign.Controls.Add($badgePrint); $pnlDesign.Controls.Add($badgeSlicer)

$pnlDesign.Controls.Add((New-DLabel "DETAY" 20 412 640 20 0))
$lstResult = New-DList 20 434 640 240
$pnlDesign.Controls.Add($lstResult)

# ========== REFERANS ==========
$pnlRef.Controls.Add((New-DLabel "Referanstan Tasarla" 20 12 600 32 15))
$pnlRef.Controls.Add((New-DLabel "REFERANS MODEL" 20 50 600 20 0))
$txtRefUrl = New-DText 20 72 640 26 $false
$pnlRef.Controls.Add($txtRefUrl)
$btnRefBrowse = New-DButton "Dosya Sec (STL/3MF/STEP)" 20 104 250 30
$pnlRef.Controls.Add($btnRefBrowse)
$lblRefFile = New-DLabel "dosya secilmedi" 278 104 362 30 0
$lblRefFile.ForeColor = $C_MUTED
$pnlRef.Controls.Add($lblRefFile)
$btnRefAnalyze = New-DButton "Referansi Analiz Et" 20 140 640 34
$btnRefAnalyze.BackColor = $C_ACCENT
$btnRefAnalyze.ForeColor = [System.Drawing.Color]::Black
$pnlRef.Controls.Add($btnRefAnalyze)
$lstRefResult = New-DList 20 182 640 150
$pnlRef.Controls.Add($lstRefResult)
$pnlRef.Controls.Add((New-DLabel "DEGISIKLIK KOMUTU (orn: aynisini yap ama deligi 8 mm olsun)" 20 340 640 20 0))
$txtRefMod = New-DText 20 362 640 60 $true
$txtRefMod.Text = "Bu parcanin aynisini yap."
$pnlRef.Controls.Add($txtRefMod)
$btnRefBuild = New-DButton "Referanstan Uret" 20 428 640 36
$btnRefBuild.Enabled = $false
$pnlRef.Controls.Add($btnRefBuild)
$pnlRef.Controls.Add((New-DLabel "Olcu bilinmiyorsa uydurulmaz, sorulur." 20 470 640 20 0))

# ========== PROJELER ==========
$pnlProj.Controls.Add((New-DLabel "Projeler" 20 12 600 32 15))
$lstProjects = New-DList 20 50 640 250
$pnlProj.Controls.Add($lstProjects)
$txtDetail = New-DText 20 308 640 250 $true
$txtDetail.ReadOnly = $true
$pnlProj.Controls.Add($txtDetail)

# ========== YAZICILAR ==========
$pnlPrinter.Controls.Add((New-DLabel "Yazici Yonetimi" 20 12 600 32 15))
$pnlPrinter.Controls.Add((New-DLabel "Kayitli yazici profilleri:" 20 50 600 20 0))
$lstPrinters = New-DList 20 74 640 120
$pnlPrinter.Controls.Add($lstPrinters)

$pnlPrinter.Controls.Add((New-DLabel "YAZICI EKLE" 20 204 640 26 11))
$pnlPrinter.Controls.Add((New-DLabel "Marka:" 20 236 80 22 0))
$txtPrtMfr = New-DText 100 234 250 24 $false
$pnlPrinter.Controls.Add($txtPrtMfr)
$pnlPrinter.Controls.Add((New-DLabel "Model:" 360 236 80 22 0))
$txtPrtModel = New-DText 440 234 220 24 $false
$pnlPrinter.Controls.Add($txtPrtModel)

$pnlPrinter.Controls.Add((New-DLabel "Nozul (mm):" 20 268 90 22 0))
  $txtPrtNozzle = New-DText 120 266 80 24 $false
  $txtPrtNozzle.Text = ""
$pnlPrinter.Controls.Add($txtPrtNozzle)
$pnlPrinter.Controls.Add((New-DLabel "Tabla X:" 210 268 60 22 0))
$txtPrtBedX = New-DText 270 266 70 24 $false
$pnlPrinter.Controls.Add($txtPrtBedX)
$pnlPrinter.Controls.Add((New-DLabel "Y:" 348 268 20 22 0))
$txtPrtBedY = New-DText 370 266 70 24 $false
$pnlPrinter.Controls.Add($txtPrtBedY)
$pnlPrinter.Controls.Add((New-DLabel "Z:" 448 268 20 22 0))
$txtPrtBedZ = New-DText 470 266 70 24 $false
$pnlPrinter.Controls.Add($txtPrtBedZ)

$pnlPrinter.Controls.Add((New-DLabel "Firmware:" 20 300 80 22 0))
$txtPrtFw = New-DText 120 298 200 24 $false
$pnlPrinter.Controls.Add($txtPrtFw)
$pnlPrinter.Controls.Add((New-DLabel "Ekstruder:" 340 300 80 22 0))
$cmbPrtExtruder = New-Object System.Windows.Forms.ComboBox
$cmbPrtExtruder.Location = New-Object System.Drawing.Point(430, 298)
$cmbPrtExtruder.Size = New-Object System.Drawing.Size(150, 24)
$cmbPrtExtruder.BackColor = $C_INPUT; $cmbPrtExtruder.ForeColor = $C_TEXT
$cmbPrtExtruder.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbPrtExtruder.Items.AddRange(@("Bilinmiyor", "Direct Drive", "Bowden"))
$cmbPrtExtruder.SelectedIndex = 0
$pnlPrinter.Controls.Add($cmbPrtExtruder)

$pnlPrinter.Controls.Add((New-DLabel "Tabla tipi:" 20 332 80 22 0))
$txtPrtPlate = New-DText 120 330 200 24 $false
$pnlPrinter.Controls.Add($txtPrtPlate)

$pnlPrinter.Controls.Add((New-DLabel "Malzemeler:" 20 364 90 22 0))
$txtPrtMaterials = New-DText 120 362 540 24 $false
$txtPrtMaterials.Text = "PLA, PETG"
$pnlPrinter.Controls.Add($txtPrtMaterials)

$btnPrtSave = New-DButton "YAZICIYI KAYDET" 20 400 250 36
$btnPrtSave.BackColor = $C_ACCENT
$btnPrtSave.ForeColor = [System.Drawing.Color]::Black
$pnlPrinter.Controls.Add($btnPrtSave)
$lblPrtStatus = New-DLabel "" 280 408 380 22 0
$lblPrtStatus.ForeColor = $C_MUTED
$pnlPrinter.Controls.Add($lblPrtStatus)

$pnlPrinter.Controls.Add((New-DLabel "Bilinmeyen degerler bos birakilir (null = UNKNOWN). Deger UYDURULMAZ." 20 450 640 20 0))

# ========== FILAMENTLER ==========
$pnlFilam.Controls.Add((New-DLabel "Malzeme Rehberi" 20 12 600 32 15))
$pnlFilam.Controls.Add((New-DLabel "FDM 3D baski malzemeleri (genel bilgi, yaziciya ozel degil)" 20 48 640 20 0))
$lstFilamMat = New-DList 20 74 200 400
$pnlFilam.Controls.Add($lstFilamMat)
$txtFilamDetail = New-DText 228 74 432 400 $true
$txtFilamDetail.ReadOnly = $true
$txtFilamDetail.Font = New-Object System.Drawing.Font("Consolas", 9)
$pnlFilam.Controls.Add($txtFilamDetail)

$pnlFilam.Controls.Add((New-DLabel "KULLANIM AMACI" 20 486 200 20 0))
$cmbFilamUse = New-Object System.Windows.Forms.ComboBox
$cmbFilamUse.Location = New-Object System.Drawing.Point(20, 508)
$cmbFilamUse.Size = New-Object System.Drawing.Size(200, 24)
$cmbFilamUse.BackColor = $C_INPUT; $cmbFilamUse.ForeColor = $C_TEXT
$cmbFilamUse.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
[void]$cmbFilamUse.Items.AddRange(@("Tumu", "Prototipleme", "Mekanik", "Esnek", "Isiya dayanikli", "Dis ortam", "Yuk tasiyan"))
$cmbFilamUse.SelectedIndex = 0
$pnlFilam.Controls.Add($cmbFilamUse)
$txtFilamWhy = New-DText 228 486 432 56 $true
$txtFilamWhy.ReadOnly = $true
$pnlFilam.Controls.Add($txtFilamWhy)

# ========== BASKI ANALIZI ==========
$pnlAnalyze.Controls.Add((New-DLabel "Baski Analizi" 20 12 600 32 15))
$pnlAnalyze.Controls.Add((New-DLabel "STL veya son proje secin:" 20 48 640 20 0))
$btnAnalyzeFile = New-DButton "STL Dosya Sec" 20 72 200 30
$pnlAnalyze.Controls.Add($btnAnalyzeFile)
$btnAnalyzeProj = New-DButton "Son Projeyi Analiz Et" 228 72 220 30
$pnlAnalyze.Controls.Add($btnAnalyzeProj)
$lblAnalyzeFile = New-DLabel "" 456 78 204 20 0
$lblAnalyzeFile.ForeColor = $C_MUTED
$pnlAnalyze.Controls.Add($lblAnalyzeFile)

$pnlAnalyze.Controls.Add((New-DLabel "MESH KALITESI" 20 114 300 22 0))
$lstMeshQ = New-DList 20 138 310 120
$pnlAnalyze.Controls.Add($lstMeshQ)

$pnlAnalyze.Controls.Add((New-DLabel "BASILABILIRLIK" 340 114 320 22 0))
$lstPrintability = New-DList 340 138 320 120
$pnlAnalyze.Controls.Add($lstPrintability)

$pnlAnalyze.Controls.Add((New-DLabel "BASKI YONU ONERILERI" 20 268 640 22 0))
$lstOrientation = New-DList 20 292 640 120
$pnlAnalyze.Controls.Add($lstOrientation)

$pnlAnalyze.Controls.Add((New-DLabel "MALIYET / AGIRLIK TAHMINI" 20 422 300 22 0))
$lstEstimate = New-DList 20 446 310 100
$pnlAnalyze.Controls.Add($lstEstimate)

$pnlAnalyze.Controls.Add((New-DLabel "SORUN GIDERME" 340 422 320 22 0))
$lstTrouble = New-DList 340 446 320 100
$pnlAnalyze.Controls.Add($lstTrouble)

$pnlAnalyze.Controls.Add((New-DLabel "Tum tahminler ESTIMATE etiketlidir. Gercek degerler icin slicer ve yazici profili gereklidir." 20 556 640 20 0))

# ========== AYARLAR ==========
$pnlSet.Controls.Add((New-DLabel "Ayarlar" 20 12 600 32 15))
$lblToolOS = New-DLabel "OpenSCAD: denetlenmedi" 20 60 600 24 0
$lblToolFC = New-DLabel "FreeCAD: denetlenmedi (OPTIONAL)" 20 88 600 24 0
$lblToolOrca = New-DLabel "OrcaSlicer: denetlenmedi (OPTIONAL)" 20 116 600 24 0
$pnlSet.Controls.Add($lblToolOS)
$pnlSet.Controls.Add($lblToolFC)
$pnlSet.Controls.Add($lblToolOrca)
$btnToolsRefresh = New-DButton "ARACLARI DENETLE" 20 150 250 32
$pnlSet.Controls.Add($btnToolsRefresh)
$btnToolOS = New-DButton "OpenSCAD Konum Sec..." 278 150 300 32
$pnlSet.Controls.Add($btnToolOS)

$pnlSet.Controls.Add((New-DLabel "AI Provider: MOCK (test - gercek AI degil)" 20 200 600 24 0))
$pnlSet.Controls.Add((New-DLabel "Secimler settings.local.json dosyasina kaydolur (git disi)." 20 228 600 24 0))

$pnlSet.Controls.Add((New-DLabel "PROJE DIZINI" 20 270 600 22 0))
$lblProjDir = New-DLabel $projectsDir 20 294 600 22 0
$lblProjDir.ForeColor = $C_MUTED
$pnlSet.Controls.Add($lblProjDir)

$pnlSet.Controls.Add((New-DLabel "HAKKINDA" 20 340 600 22 0))
$lblAbout = New-DLabel "3D AI Designer $appVersion - FDM 3D Baski Muhendisi Asistani`nPowerShell + WinForms | OpenSCAD | OrcaSlicer`nKritik olculer UYDURULMAZ. Bilinmeyen = UNKNOWN / NEEDS_INPUT." 20 364 600 60 0
$lblAbout.ForeColor = $C_MUTED
$pnlSet.Controls.Add($lblAbout)

# ========== SAG PANEL ==========
$right.Controls.Add((New-DLabel "PROJE" 15 12 350 28 13))
$lblProjName = New-DLabel "-" 15 44 350 22 0
$lblProjName.ForeColor = $C_ACCENT
$right.Controls.Add($lblProjName)
$right.Controls.Add((New-DLabel "PARCALAR" 15 72 350 20 0))
$lstParts = New-DList 15 94 355 90
$right.Controls.Add($lstParts)
$right.Controls.Add((New-DLabel "VALIDATION" 15 190 350 20 0))
$lstValidation = New-DList 15 212 355 90
$right.Controls.Add($lstValidation)
$right.Controls.Add((New-DLabel "UYARILAR" 15 308 350 20 0))
$lstWarnings = New-DList 15 330 355 80
$right.Controls.Add($lstWarnings)
$right.Controls.Add((New-DLabel "SORU/CEVAP GECMISI" 15 416 350 20 0))
$txtHistory = New-DText 15 438 355 120 $true
$txtHistory.ReadOnly = $true
$right.Controls.Add($txtHistory)
$btnScad = New-DButton "SCAD'I AC" 15 566 112 30
$btnStl = New-DButton "STL'YI AC" 132 566 112 30
$btnFolder = New-DButton "KLASORU AC" 249 566 121 30
$btnScad.Enabled = $false; $btnStl.Enabled = $false; $btnFolder.Enabled = $false
$right.Controls.Add($btnScad)
$right.Controls.Add($btnStl)
$right.Controls.Add($btnFolder)

# ========== DURUM DEGISKENLERI ==========
$script:lastProjectDir = ""
$script:lastScad = ""
$script:lastStl = ""
$script:pipeName = ""
$script:pipePrompt = ""
$script:pipeRefSpec = ""
$script:pipeQuestions = @()
$script:pipeAnswers = @{}
$script:OriginalPrompt = ""
$script:CurrentQ = $null
$script:history = New-Object System.Collections.Generic.List[string]
$script:refJson = ""
$script:refStage = ""
$script:analyzeStlPath = ""

# ========== YARDIMCI FONKSIYONLAR ==========
function Set-Status($t) { $lblStatus.Text = "Durum: $t"; $form.Refresh() }
function Reset-QAState {
  $script:OriginalPrompt = ""
  $script:CurrentQ = $null
  $script:pipeQuestions = @()
  $script:pipeAnswers = @{}
  $script:pipePrompt = ""
  $script:pipeRefSpec = ""
  $txtQuestion.Text = ""
  $txtAnswer.Text = ""
  $txtAnswer.Enabled = $false; $btnContinue.Enabled = $false
}
function Get-DisplayQuestion {
  $list = @($script:pipeQuestions)
  if ($list.Count -eq 0) { return $null }
  $first = $list[0]
  return [pscustomobject]@{
    displayId = "q1"
    stableId = [string]$first.question_id
    type = [string]$first.kind
    target = [string]$first.target
    text = [string]$first.question
    reason = [string]$first.reason
  }
}
function Show-CurrentQuestion {
  $dq = Get-DisplayQuestion
  $script:CurrentQ = $dq
  if ($null -eq $dq) { return $false }
  $txtQuestion.Text = "[" + $dq.displayId + "] " + $dq.text + " (tur: " + $dq.type + ")"
  $histLine = ("SORU [" + $dq.displayId + "/" + $dq.stableId + "/" + $dq.type + "]: " + $dq.text)
  if ($dq.reason -ne "") { $histLine += " (Neden gerekli: " + $dq.reason + ")" }
  Add-History $histLine
  $txtAnswer.Enabled = $true; $btnContinue.Enabled = $true
  return $true
}
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
  else { $lblToolFC.Text = "FreeCAD: bulunamadi (OPTIONAL)"; $lblToolFC.ForeColor = $C_WARN }
  if ($fOrca -and (Test-Path -LiteralPath ([string]$fOrca))) { $lblToolOrca.Text = "OrcaSlicer: BULUNDU (OPTIONAL)"; $lblToolOrca.ForeColor = $C_OK }
  else { $lblToolOrca.Text = "OrcaSlicer: bulunamadi (OPTIONAL)"; $lblToolOrca.ForeColor = $C_WARN }
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
  $lstHomeProj.Items.Clear()
  foreach ($p in (Get-ProjectList)) {
    [void]$lstProjects.Items.Add($p.name)
    [void]$lstHomeProj.Items.Add($p.name)
  }
}
function Refresh-Printers {
  $lstPrinters.Items.Clear()
  $pd = Join-Path $Root "printers"
  if (Test-Path -LiteralPath $pd) {
    foreach ($f in (Get-ChildItem -LiteralPath $pd -Filter "*.json")) {
      try {
        $pj = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json
        [void]$lstPrinters.Items.Add("$($pj.id) - $($pj.label)")
      } catch { [void]$lstPrinters.Items.Add($f.BaseName) }
    }
  }
}
function Load-Materials {
  $matFile = Join-Path $Root (Join-Path "knowledge" "materials.json")
  if (Test-Path -LiteralPath $matFile) {
    try { return (Get-Content -LiteralPath $matFile -Raw | ConvertFrom-Json) }
    catch { return @() }
  }
  return @()
}
function Refresh-Materials {
  $lstFilamMat.Items.Clear()
  $mats = Load-Materials
  foreach ($m in @($mats)) {
    if ($null -eq $m) { continue }
    [void]$lstFilamMat.Items.Add([string]$m.name)
  }
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
  if ($vstat -eq "PASS") { Set-Badge $badgeVal "Valid: PASS" $C_OK }
  elseif ($vstat -eq "WARNING") { Set-Badge $badgeVal "Valid: WARN" $C_WARN }
  elseif ($vstat -eq "NEEDS_INPUT" -or $vstat -eq "BLOCKED" -or $vstat -eq "FAILED") { Set-Badge $badgeVal ("Valid: " + $vstat) $C_ERR }
  else { Set-Badge $badgeVal "Valid: -" $C_BORDER }
  Set-Badge $badgeSpec "Spec: v2" $C_OK
  Set-Badge $badgeSlicer "Slicer: N/A" $C_BORDER
  # Printability
  if ($stls.Count -gt 0 -and (Test-Path -LiteralPath $printabilityScript)) {
    try {
      $specF = Join-Path $pd "spec.json"
      if (Test-Path -LiteralPath $specF) {
        $paOut = & $printabilityScript -SpecFile $specF -AsJson 2>&1 | Out-String
        $paObj = $paOut | ConvertFrom-Json
        if ($paObj.status -eq "PASS") { Set-Badge $badgePrint "Print: PASS" $C_OK }
        elseif ($paObj.status -eq "WARNING") { Set-Badge $badgePrint "Print: WARN" $C_WARN }
        else { Set-Badge $badgePrint ("Print: " + $paObj.status) $C_ERR }
        [void]$lstResult.Items.Add("PRINTABILITY: " + $paObj.status)
      } else { Set-Badge $badgePrint "Print: -" $C_BORDER }
    } catch { Set-Badge $badgePrint "Print: ERR" $C_ERR }
  } else { Set-Badge $badgePrint "Print: -" $C_BORDER }
  [void]$lstResult.Items.Add("VALIDATION: " + $vstat)
  [void]$lstResult.Items.Add("G-CODE: NOT AVAILABLE (printer profile required)")
  if ($result -and $result.reason) { [void]$lstResult.Items.Add("NOT: " + [string]$result.reason) }
  Show-ProjectPanels $pd
  $first = $stls | Select-Object -First 1
  $script:lastScad = ""
  $script:lastStl = ""
  if ($first) {
    $script:lastStl = $first.FullName
    $script:analyzeStlPath = $first.FullName
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
    $prompt = $script:OriginalPrompt
    if ($script:pipeRefSpec -ne "" -and $prompt.Trim() -eq "") { $prompt = "referans proje" }
    if ($prompt.Trim() -eq "") {
      Set-Status "Tasarim prompt'u bulunamadi. Yeni proje baslatin."
      return
    }
    $pargs = @{ Prompt = $prompt; ProjectName = $script:pipeName; ProjectDir = $script:lastProjectDir }
    if ($script:pipeRefSpec -ne "") { $pargs.RefSpecFile = $script:pipeRefSpec }
    if ($answersFile -ne "") { $pargs.AnswersFile = $answersFile }
    $resPath = Join-Path $script:lastProjectDir "pipeline-result.json"
    if (Test-Path -LiteralPath $resPath) { Remove-Item -LiteralPath $resPath -Force }
    $o = & $pipelineScript @pargs 2>&1 | Out-String
    $result = $null
    if (Test-Path -LiteralPath $resPath) {
      $rtxt = Get-Content -LiteralPath $resPath -Raw
      $result = $rtxt | ConvertFrom-Json
    } else {
      $txtQuestion.Text = ""
      $txtAnswer.Enabled = $false; $btnContinue.Enabled = $false
      $script:pipeQuestions = @()
      Fill-ProjectResult $script:lastProjectDir $null
      Set-Status "pipeline sonucu uretilemedi (calisma basarisiz); soru gosterilmiyor"
      Refresh-Projects
      return
    }
    Fill-ProjectResult $script:lastProjectDir $result
    if ($result -and $result.status -eq "NEEDS_INPUT") {
      $qs = @()
      if ($result.questions) {
        if ($result.questions -is [array]) { $qs = $result.questions }
        else { $qs = @($result.questions) }
      }
      $script:pipeQuestions = $qs
      Show-CurrentQuestion | Out-Null
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

# ========== OLAY BAGLANTILARI ==========
$btnNavHome.Add_Click({ Refresh-Projects; Show-Mode $pnlHome $btnNavHome })
$btnNavNew.Add_Click({
  $txtPrompt.Text = ""
  Reset-QAState
  $script:history.Clear()
  $txtHistory.Clear()
  $script:pipeName = ""
  $script:lastProjectDir = ""
  Show-Mode $pnlDesign $btnNavDesign
  Set-Status "hazir"
})
$btnNavDesign.Add_Click({ Show-Mode $pnlDesign $btnNavDesign })
$btnNavRef.Add_Click({ Show-Mode $pnlRef $btnNavRef })
$btnNavProj.Add_Click({ Refresh-Projects; Show-Mode $pnlProj $btnNavProj })
$btnNavPrint.Add_Click({ Refresh-Printers; Show-Mode $pnlPrinter $btnNavPrint })
$btnNavFilam.Add_Click({ Refresh-Materials; Show-Mode $pnlFilam $btnNavFilam })
$btnNavAnalyze.Add_Click({ Show-Mode $pnlAnalyze $btnNavAnalyze })
$btnNavSet.Add_Click({ Refresh-Tools; Show-Mode $pnlSet $btnNavSet })

# Home quick actions
$btnHomeGo.Add_Click({
  if ($txtHomePrompt.Text.Trim() -ne "") {
    $txtPrompt.Text = $txtHomePrompt.Text
    Show-Mode $pnlDesign $btnNavDesign
    Invoke-CreateFlow | Out-Null
  }
})
$btnQNew.Add_Click({ $txtPrompt.Text = ""; Reset-QAState; Show-Mode $pnlDesign $btnNavDesign; Set-Status "hazir" })
$btnQRef.Add_Click({ Show-Mode $pnlRef $btnNavRef })
$btnQStl.Add_Click({ Show-Mode $pnlAnalyze $btnNavAnalyze })
$btnQPrint.Add_Click({ Show-Mode $pnlAnalyze $btnNavAnalyze })

function Invoke-CreateFlow {
  if ($txtPrompt.Text.Trim() -eq "") {
    Set-Status "Once prompt yaz. Ornek: 80x40x20 kutu, delik 25 merkez 15,15."
    return "EMPTY_PROMPT"
  }
  $lstResult.Items.Clear()
  $lstParts.Items.Clear(); $lstValidation.Items.Clear(); $lstWarnings.Items.Clear()
  $btnScad.Enabled = $false; $btnStl.Enabled = $false; $btnFolder.Enabled = $false
  Set-Badge $badgeSpec "Spec: ..." $C_BORDER
  Set-Badge $badgeCAD "CAD: ..." $C_BORDER
  Set-Badge $badgeSTL "STL: ..." $C_BORDER
  Set-Badge $badgeVal "Valid: ..." $C_BORDER
  Set-Badge $badgePrint "Print: ..." $C_BORDER
  Set-Badge $badgeSlicer "Slicer: N/A" $C_BORDER
  $script:pipeName = ("proje-" + (Get-Date -Format "yyyyMMdd-HHmmss"))
  $script:lastProjectDir = Join-Path $projectsDir $script:pipeName
  Reset-QAState
  $script:OriginalPrompt = $txtPrompt.Text
  Set-Status "analiz ediliyor..."
  Run-Pipeline ""
  return "STARTED"
}
function Invoke-ContinueFlow {
  if ($txtAnswer.Text.Trim() -eq "") { Set-Status "once cevabi yaz"; return "EMPTY_ANSWER" }
  $dq = Get-DisplayQuestion
  if ($null -eq $dq) { Set-Status "bekleyen soru yok"; return "NO_QUESTION" }
  Add-History ("CEVAP [" + $dq.displayId + "/" + $dq.stableId + "/" + $dq.type + "]: " + $txtAnswer.Text)
  $script:pipeAnswers[$dq.stableId] = $txtAnswer.Text
  $ansFile = Join-Path ([System.IO.Path]::GetTempPath()) ($script:pipeName + "-cevap.json")
  $ansObj = [pscustomobject]@{}
  foreach ($k in $script:pipeAnswers.Keys) { $ansObj | Add-Member -NotePropertyName $k -NotePropertyValue ([string]$script:pipeAnswers[$k]) }
  $ansObj | ConvertTo-Json | Set-Content -LiteralPath $ansFile -Encoding UTF8
  $txtAnswer.Text = ""
  Run-Pipeline $ansFile
  return "SENT"
}

$btnCreate.Add_Click({ Invoke-CreateFlow | Out-Null })
$btnContinue.Add_Click({ Invoke-ContinueFlow | Out-Null })

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

# ========== REFERANS OLAYLARI ==========
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
    $script:OriginalPrompt = $txtRefMod.Text
    $script:pipeAnswers = @{}
    Show-Mode $pnlDesign $btnNavDesign
    Set-Status "referans spec olustu, pipeline calisiyor..."
    Run-Pipeline ""
  } catch {
    Set-Status ("hata: " + $_.Exception.Message)
  }
})

# ========== YAZICI KAYDET ==========
$btnPrtSave.Add_Click({
  $mfr = $txtPrtMfr.Text.Trim()
  $mdl = $txtPrtModel.Text.Trim()
  if ($mfr -eq "" -and $mdl -eq "") { $lblPrtStatus.Text = "Marka veya model girin."; return }
  $pid = (($mfr + "-" + $mdl) -replace '[^a-zA-Z0-9]', '-').ToLowerInvariant() -replace '-+', '-' -replace '^-|-$', ''
  if ($pid -eq "") { $pid = "printer-" + (Get-Date -Format "yyyyMMddHHmmss") }
  $nz = $null
  try { if ($txtPrtNozzle.Text.Trim() -ne "") { $nz = [double]($txtPrtNozzle.Text -replace ',', '.') } } catch { $nz = $null }
  if ($null -ne $nz -and $nz -le 0) { $nz = $null }
  $bx = $null; $by = $null; $bz = $null
  try { if ($txtPrtBedX.Text.Trim() -ne "") { $bx = [double]($txtPrtBedX.Text -replace ',', '.') } } catch { $bx = $null }
  try { if ($txtPrtBedY.Text.Trim() -ne "") { $by = [double]($txtPrtBedY.Text -replace ',', '.') } } catch { $by = $null }
  try { if ($txtPrtBedZ.Text.Trim() -ne "") { $bz = [double]($txtPrtBedZ.Text -replace ',', '.') } } catch { $bz = $null }
  if ($null -eq $bx -or $bx -le 0) { $bx = $null }; if ($null -eq $by -or $by -le 0) { $by = $null }; if ($null -eq $bz -or $bz -le 0) { $bz = $null }
  $bedArr = $null
  if ($null -ne $bx -or $null -ne $by -or $null -ne $bz) { $bedArr = @($bx, $by, $bz) }
  $ext = $null
  if ($cmbPrtExtruder.SelectedIndex -eq 1) { $ext = "direct_drive" }
  elseif ($cmbPrtExtruder.SelectedIndex -eq 2) { $ext = "bowden" }
  $matList = $null
  if ($txtPrtMaterials.Text.Trim() -ne "") {
    $matList = @($txtPrtMaterials.Text -split '[,;]' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" })
  }
  $prtObj = [pscustomobject]@{
    id = $pid
    label = ($(if ($mfr) { $mfr } else { "UNKNOWN" }) + " " + $(if ($mdl) { $mdl } else { "UNKNOWN" }))
    manufacturer = $(if ($mfr -ne "") { $mfr } else { $null })
    model = $(if ($mdl -ne "") { $mdl } else { $null })
    nozzle_mm = $nz
    bed_mm = $bedArr
    bed_shape = $null
    extruder_type = $ext
    build_plate = $(if ($txtPrtPlate.Text.Trim() -ne "") { $txtPrtPlate.Text.Trim() } else { $null })
    max_temp_nozzle_c = $null; max_temp_bed_c = $null
    recommended_materials = $matList
    min_layer_height_mm = $null; max_layer_height_mm = $null
    max_volumetric_flow_mm3s = $null; max_speed_mm_s = $null; max_acceleration_mm_s2 = $null
    firmware = $(if ($txtPrtFw.Text.Trim() -ne "") { $txtPrtFw.Text.Trim() } else { $null })
    coordinate_system = $null; origin = $null; auto_bed_leveling = $null
    min_wall_mm = $null
    min_feature_mm = $null
    min_hole_mm = $null
    max_overhang_deg = $null
    default_clearance_mm = $null
    orca_profiles = [pscustomobject]@{ printer = "REPLACE_WITH_ORCA_PRINTER_PROFILE_NAME"; filament = "REPLACE_WITH_ORCA_FILAMENT_PROFILE_NAME"; process = "REPLACE_WITH_ORCA_PROCESS_PROFILE_NAME" }
    notes = "Kullanici tarafindan eklendi. Bilinmeyen degerler null = UNKNOWN."
    source = "user_input"
    created_at = (Get-Date).ToUniversalTime().ToString("o")
  }
  $prtDir = Join-Path $Root "printers"
  New-Item -ItemType Directory -Force -Path $prtDir | Out-Null
  $prtFile = Join-Path $prtDir ($pid + ".json")
  $prtObj | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $prtFile -Encoding UTF8
  $msgExtra = ""
  if ($null -eq $nz -or $null -eq $bedArr) { $msgExtra = " (eksik teknik degerler UNKNOWN)" }
  $lblPrtStatus.Text = "Kaydedildi: $prtFile" + $msgExtra
  $lblPrtStatus.ForeColor = $C_OK
  Refresh-Printers
})

# ========== FILAMENT OLAYLARI ==========
$lstFilamMat.Add_SelectedIndexChanged({
  if ($lstFilamMat.SelectedItem -eq $null) { return }
  $mats = Load-Materials
  $sel = $lstFilamMat.SelectedItem.ToString()
  $m = $null
  foreach ($mat in @($mats)) { if ($null -ne $mat -and [string]$mat.name -eq $sel) { $m = $mat; break } }
  if ($null -eq $m) { return }
  $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("=== " + [string]$m.name + " (" + [string]$m.full_name + ") ===")
  $lines.Add("")
  $lines.Add("Kategori     : " + [string]$m.category)
  $lines.Add("Yogunluk     : " + [string]$m.density_g_cm3 + " g/cm3")
  if ($m.glass_transition_c) { $lines.Add("Cam gecisi   : " + [string]$m.glass_transition_c + " C") }
  if ($m.nozzle_temp_range_c) { $lines.Add("Nozul sicak. : " + ($m.nozzle_temp_range_c -join " - ") + " C") }
  if ($m.bed_temp_range_c) { $lines.Add("Tabla sicak. : " + ($m.bed_temp_range_c -join " - ") + " C") }
  $lines.Add("Nem duyarli  : " + $(if ($m.moisture_sensitive) { "EVET" } else { "Hayir" }))
  if ($m.drying) { $lines.Add("Kurutma      : " + $(if ($m.drying.required) { "Gerekli" } else { "Opsiyonel" }) + " (" + [string]$m.drying.temp_c + "C, " + [string]$m.drying.hours + " saat)") }
  $lines.Add("")
  $lines.Add("Mukavemet    : " + [string]$m.strength)
  $lines.Add("Esneklik     : " + [string]$m.flexibility)
  $lines.Add("Isi direnci  : " + [string]$m.heat_resistance)
  $lines.Add("Dis ortam    : " + $(if ($m.outdoor_suitable) { "Uygun" } else { "Uygun degil" }))
  $lines.Add("Baski kolayligi: " + [string]$m.ease_of_printing)
  $lines.Add("")
  if ($m.recommended_for) { $lines.Add("Onerilen: " + ($m.recommended_for -join ", ")) }
  if ($m.not_recommended_for) { $lines.Add("Onerilmez: " + ($m.not_recommended_for -join ", ")) }
  $lines.Add("")
  if ($m.advantages) { $lines.Add("Avantajlar: " + ($m.advantages -join ", ")) }
  if ($m.disadvantages) { $lines.Add("Dezavantajlar: " + ($m.disadvantages -join ", ")) }
  if ($m.notes) { $lines.Add(""); $lines.Add("Not: " + [string]$m.notes) }
  $txtFilamDetail.Lines = $lines.ToArray()
})

$cmbFilamUse.Add_SelectedIndexChanged({
  $use = $cmbFilamUse.SelectedItem.ToString()
  $mats = Load-Materials
  $reasons = New-Object System.Collections.Generic.List[string]
  $lstFilamMat.Items.Clear()
  $useMap = @{
    "Prototipleme" = "prototyping"; "Mekanik" = "mechanical"; "Esnek" = "flexible"
    "Isiya dayanikli" = "high-temp"; "Dis ortam" = "outdoor"; "Yuk tasiyan" = "load-bearing"
  }
  foreach ($m in @($mats)) {
    if ($null -eq $m) { continue }
    if ($use -eq "Tumu") {
      [void]$lstFilamMat.Items.Add([string]$m.name)
    } else {
      $uk = $useMap[$use]
      if ($m.recommended_for -and $m.recommended_for -contains $uk) {
        [void]$lstFilamMat.Items.Add([string]$m.name)
        $reasons.Add([string]$m.name + ": " + [string]$m.notes)
      }
    }
  }
  if ($reasons.Count -gt 0) { $txtFilamWhy.Lines = $reasons.ToArray() }
  elseif ($use -ne "Tumu") { $txtFilamWhy.Text = "Bu kullanim alani icin onerilen malzeme bulunamadi." }
  else { $txtFilamWhy.Text = "" }
})

# ========== BASKI ANALIZI OLAYLARI ==========
$btnAnalyzeFile.Add_Click({
  $dlg = New-Object System.Windows.Forms.OpenFileDialog
  $dlg.Filter = "STL dosyasi (*.stl)|*.stl|Tum dosyalar (*.*)|*.*"
  $dlg.Title = "STL dosya sec"
  if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $script:analyzeStlPath = $dlg.FileName
    $lblAnalyzeFile.Text = [System.IO.Path]::GetFileName($dlg.FileName)
    Run-Analysis
  }
})
$btnAnalyzeProj.Add_Click({
  if ($script:lastStl -ne "" -and (Test-Path -LiteralPath $script:lastStl)) {
    $script:analyzeStlPath = $script:lastStl
    $lblAnalyzeFile.Text = [System.IO.Path]::GetFileName($script:lastStl)
    Run-Analysis
  } else {
    $lblAnalyzeFile.Text = "Henuz STL uretilmedi"
  }
})

function Run-Analysis {
  $lstMeshQ.Items.Clear(); $lstPrintability.Items.Clear(); $lstOrientation.Items.Clear()
  $lstEstimate.Items.Clear(); $lstTrouble.Items.Clear()
  # Mesh Quality
  if ($script:analyzeStlPath -ne "" -and (Test-Path -LiteralPath $script:analyzeStlPath) -and (Test-Path -LiteralPath $meshQualityScript)) {
    try {
      $mqOut = & $meshQualityScript -StlFile $script:analyzeStlPath -AsJson 2>&1 | Out-String
      $mq = $mqOut | ConvertFrom-Json
      [void]$lstMeshQ.Items.Add("Durum: " + $mq.status)
      [void]$lstMeshQ.Items.Add("Format: " + $mq.format + " (" + $mq.file_size_bytes + " bayt)")
      [void]$lstMeshQ.Items.Add("Ucgen: " + $mq.triangle_count)
      [void]$lstMeshQ.Items.Add("Boyut: " + ($mq.bbox_size_mm -join " x ") + " mm")
      [void]$lstMeshQ.Items.Add("Zero-area: " + $mq.zero_area_triangles)
      [void]$lstMeshQ.Items.Add("Duplicate vtx: " + $mq.duplicate_vertices)
    } catch {
      [void]$lstMeshQ.Items.Add("Mesh analizi basarisiz: " + $_.Exception.Message)
    }
  } else { [void]$lstMeshQ.Items.Add("STL dosyasi veya mesh analyzer bulunamadi") }
  # Printability
  $specF = ""
  if ($script:lastProjectDir -ne "") { $specF = Join-Path $script:lastProjectDir "spec.json" }
  if ($specF -ne "" -and (Test-Path -LiteralPath $specF) -and (Test-Path -LiteralPath $printabilityScript)) {
    try {
      $paOut = & $printabilityScript -SpecFile $specF -AsJson 2>&1 | Out-String
      $pa = $paOut | ConvertFrom-Json
      [void]$lstPrintability.Items.Add("Genel: " + $pa.status)
      foreach ($ch in @($pa.checks)) {
        if ($null -ne $ch) { [void]$lstPrintability.Items.Add("  " + $ch.id + ": " + $ch.status + " - " + $ch.message) }
      }
    } catch {
      [void]$lstPrintability.Items.Add("Basilabilirlik analizi basarisiz")
    }
  } else { [void]$lstPrintability.Items.Add("Spec dosyasi veya analyzer bulunamadi") }
  # Orientation
  if ($specF -ne "" -and (Test-Path -LiteralPath $specF) -and (Test-Path -LiteralPath $orientationScript)) {
    try {
      $orOut = & $orientationScript -SpecFile $specF -AsJson 2>&1 | Out-String
      $or = $orOut | ConvertFrom-Json
      foreach ($ori in @($or.orientations)) {
        if ($null -ne $ori) {
          [void]$lstOrientation.Items.Add($ori.name + ": destek=" + $ori.support_estimate + " yatak=" + [string]$ori.bed_contact_area_mm2 + "mm2 yukseklik=" + [string]$ori.print_height_mm + "mm")
        }
      }
    } catch {
      [void]$lstOrientation.Items.Add("Yon analizi basarisiz")
    }
  } else { [void]$lstOrientation.Items.Add("Spec dosyasi veya analyzer bulunamadi") }
  # Estimate
  if ($specF -ne "" -and (Test-Path -LiteralPath $specF) -and (Test-Path -LiteralPath $estimateScript)) {
    try {
      $esArgs = @{ SpecFile = $specF; AsJson = $true }
      if ($script:analyzeStlPath -ne "" -and (Test-Path -LiteralPath $script:analyzeStlPath)) { $esArgs.StlFile = $script:analyzeStlPath }
      $esOut = & $estimateScript @esArgs 2>&1 | Out-String
      $es = $esOut | ConvertFrom-Json
      [void]$lstEstimate.Items.Add("Malzeme: " + $es.material)
      [void]$lstEstimate.Items.Add("Agirlik (TAHMIN): " + [string]$es.weight_estimated_g + " g")
      [void]$lstEstimate.Items.Add("Hacim (TAHMIN): " + [string]$es.volume_estimated_cm3 + " cm3")
      [void]$lstEstimate.Items.Add("Baski suresi: " + [string]$es.print_time)
    } catch {
      [void]$lstEstimate.Items.Add("Tahmin basarisiz")
    }
  } else { [void]$lstEstimate.Items.Add("Spec dosyasi veya estimator bulunamadi") }
  # Troubleshooting
  $trFile = Join-Path $Root (Join-Path "knowledge" "troubleshooting.json")
  if (Test-Path -LiteralPath $trFile) {
    try {
      $trData = Get-Content -LiteralPath $trFile -Raw | ConvertFrom-Json
      [void]$lstTrouble.Items.Add("Bilinen problemler: " + @($trData).Count)
      foreach ($t in @($trData) | Select-Object -First 5) {
        if ($null -ne $t) { [void]$lstTrouble.Items.Add("  " + $t.name + " (" + $t.category + ")") }
      }
      [void]$lstTrouble.Items.Add("  ...")
    } catch {
      [void]$lstTrouble.Items.Add("Troubleshooting verisi yuklenemedi")
    }
  } else { [void]$lstTrouble.Items.Add("Troubleshooting knowledge base bulunamadi") }
}

# ========== BASLANGIC ==========
Show-Mode $pnlHome $btnNavHome
Refresh-Projects
Refresh-Tools

# ========== UI TEST MODU ==========
if ($UITest) {
  $uit = New-Object System.Collections.Generic.List[string]
  function Write-UIT($t) { $uit.Add($t); Write-Output $t }
  $txtPrompt.Text = "50x50x10 kutu, icini bosalt duvar 2, delik 10"
  Show-Mode $pnlDesign $btnNavDesign
  $r0 = Invoke-CreateFlow
  $dq0 = Get-DisplayQuestion
  Write-UIT ("UI1 create=" + $r0 + " displayId=" + $dq0.displayId + " stableId=" + $dq0.stableId + " type=" + $dq0.type)
  $u1ok = ($dq0.stableId -eq "body-hollow_top" -and $dq0.type -eq "hollow_top")
  $txtAnswer.Text = "kapali"
  $r1 = Invoke-ContinueFlow
  $dq1 = Get-DisplayQuestion
  Write-UIT ("UI2 continue=" + $r1 + " displayId=" + $dq1.displayId + " stableId=" + $dq1.stableId + " type=" + $dq1.type + " target=" + $dq1.target)
  Write-UIT ("UI2 prompt-preserved=" + ($script:OriginalPrompt -eq "50x50x10 kutu, icini bosalt duvar 2, delik 10"))
  Write-UIT ("UI2 raw-answer=kapali parser-selected=" + $dq1.type)
  $u2ok = ($dq1.stableId -eq "body-hole-h1-center" -and $dq1.type -eq "hole_center" -and $script:OriginalPrompt -ne "")
  $txtAnswer.Text = "15,15"
  $r2 = Invoke-ContinueFlow
  $stlHere = Test-Path -LiteralPath (Join-Path $script:lastProjectDir (Join-Path "output" "body.stl"))
  Write-UIT ("UI3 continue=" + $r2 + " stl=" + $stlHere)
  $u3ok = ($stlHere -and ($lblStatus.Text -match "tamamlandi"))
  Reset-QAState
  $script:history.Clear()
  $u4ok = ($script:OriginalPrompt -eq "" -and (@($script:pipeQuestions).Count -eq 0) -and $script:CurrentQ -eq $null)
  Write-UIT ("UI4 reset=" + $u4ok)
  [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
  Remove-Item -LiteralPath $script:lastProjectDir -Recurse -Force -ErrorAction SilentlyContinue
  for ($uir = 0; $uir -lt 8 -and (Test-Path -LiteralPath $script:lastProjectDir); $uir++) {
    [System.GC]::Collect(); [System.GC]::WaitForPendingFinalizers()
    Start-Sleep -Milliseconds 800
    Remove-Item -LiteralPath $script:lastProjectDir -Recurse -Force -ErrorAction SilentlyContinue
  }
  if ($u1ok -and $u2ok -and $u3ok -and $u4ok) { Write-UIT "UI-TEST: PASS"; exit 0 }
  else { Write-UIT "UI-TEST: FAIL"; exit 1 }
}
if ($ValidateUI) {
  $checks = New-Object System.Collections.Generic.List[string]
  foreach ($c in @($txtPrompt, $btnCreate, $txtQuestion, $txtAnswer, $btnContinue, $lstResult, $txtRefUrl, $btnRefBrowse, $btnRefAnalyze, $lstRefResult, $txtRefMod, $btnRefBuild, $lstProjects, $txtDetail, $lstParts, $lstValidation, $lstWarnings, $txtHistory, $btnScad, $btnStl, $btnFolder, $lblToolOS, $btnToolsRefresh, $btnToolOS)) {
    if ($null -eq $c) { $checks.Add("eksik-kontrol") }
  }
  $tabsOk = ($script:uiMode -eq "home")
  if ($checks.Count -eq 0 -and $tabsOk) { Write-Output "UI-STARTUP: PASS"; exit 0 }
  else { Write-Output "UI-STARTUP: FAIL"; exit 1 }
}
[void]$form.ShowDialog()
