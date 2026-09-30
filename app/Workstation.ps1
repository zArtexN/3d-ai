<#
.SYNOPSIS
  3D-AI Workstation (Phase 10): tek masaustu yuzeyi.
.DESCRIPTION
  Motorlari CAGIRIR, yeniden yazmaz: orchestrator / export / engine scriptleri
  alt surecte kosar. Dashboard + pipeline + wireframe viewer + engine diagnostics
  + settings + logs. Print her zaman offline-hazirliktir (gonderme kodu YOK).
  Modlar: -SelfTest (kontrol envanteri), -ValidateUI (kurulum kontrolu).
#>
param(
  [switch]$SelfTest,
  [switch]$ValidateUI
)

$ErrorActionPreference = "Continue"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName Microsoft.VisualBasic

$WSRoot = Split-Path -Parent $PSScriptRoot
$WSEngine = Join-Path $WSRoot "engine"
$WSScripts = Join-Path $WSRoot "scripts"

$script:wsProject = ""
$script:wsMeshA = ""
$script:wsMeshB = ""
$script:wsYaw = 0.6; $script:wsPitch = 0.5; $script:wsZoom = 1.0
$script:wsPanX = 0; $script:wsPanY = 0
$script:wsFacets = $null
$script:wsDrag = $null
$script:wsJob = $null
$script:wsJobKind = ""

function WS-ProjectsRoot {
  $s = Join-Path $WSRoot "settings.json"
  $pdir = "projects"
  try {
    $sj = Get-Content -LiteralPath $s -Raw | ConvertFrom-Json
    if ([string]$sj.projectsDir -ne "") { $pdir = [string]$sj.projectsDir }
  } catch { }
  if (-not [System.IO.Path]::IsPathRooted($pdir)) { $pdir = Join-Path $WSRoot $pdir }
  return $pdir
}

function WS-ReadJson($path) {
  try {
    if (Test-Path -LiteralPath $path) { return (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json) }
  } catch { }
  return $null
}

function WS-ParseStl($path, $maxFacets) {
  $facets = New-Object System.Collections.Generic.List[object]
  try {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Length -eq 0) { return @() }
    $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [math]::Min(512, $bytes.Length))
    if ($head.StartsWith("solid")) {
      $hasFacet = $false
      foreach ($l in [System.IO.File]::ReadLines($path)) { if ($l.Trim().StartsWith("facet")) { $hasFacet = $true; break } }
      if ($hasFacet) {
        $vs = @()
        foreach ($l in [System.IO.File]::ReadLines($path)) {
          $t = $l.Trim()
          if ($t.StartsWith("vertex")) {
            $p = $t.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
            if ($p.Count -ge 4) { $vs += ,@([double]$p[1], [double]$p[2], [double]$p[3]) }
          } elseif ($t.StartsWith("endfacet")) {
            if (@($vs).Count -eq 3) { $facets.Add(@($vs)) | Out-Null }
            $vs = @()
          }
          if ($facets.Count -ge $maxFacets) { break }
        }
        return @($facets.ToArray())
      }
    }
    if ($bytes.Length -ge 84) {
      $n = [System.BitConverter]::ToUInt32($bytes, 80)
      if ($bytes.Length -eq (84 + 50 * $n)) {
        for ($i = 0; $i -lt $n -and $facets.Count -lt $maxFacets; $i++) {
          $base = 84 + 50 * $i
          $vs = @()
          for ($v = 0; $v -lt 3; $v++) {
            $o = $base + 12 + 12 * $v
            $vs += ,@([double][System.BitConverter]::ToSingle($bytes, $o),
                      [double][System.BitConverter]::ToSingle($bytes, ($o + 4)),
                      [double][System.BitConverter]::ToSingle($bytes, ($o + 8)))
          }
          $facets.Add(@($vs)) | Out-Null
        }
        return @($facets.ToArray())
      }
    }
  } catch { }
  return @($facets.ToArray())
}

function WS-ProjectMeshes($proj) {
  $out = @()
  foreach ($c in @((Join-Path $proj "oriented.stl"), (Join-Path $proj "repaired.stl"))) {
    if (Test-Path -LiteralPath $c) { $out += @($c) }
  }
  $od = Join-Path $proj "output"
  if (Test-Path -LiteralPath $od) {
    foreach ($f in (Get-ChildItem -LiteralPath $od -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq ".stl" })) { $out += @($f.FullName) }
  }
  $cd = Join-Path $proj "candidates"
  if (Test-Path -LiteralPath $cd) {
    foreach ($f in (Get-ChildItem -LiteralPath $cd -File -Recurse -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension -eq ".stl" } | Select-Object -First 5)) { $out += @($f.FullName) }
  }
  return $out
}

$C_OK = [System.Drawing.Color]::FromArgb(30, 140, 60)
$C_WARN = [System.Drawing.Color]::FromArgb(170, 120, 0)
$C_BAD = [System.Drawing.Color]::FromArgb(180, 40, 40)
$C_IDLE = [System.Drawing.Color]::FromArgb(100, 100, 100)

function WS-StatusColor($st) {
  $s = ([string]$st).ToUpperInvariant()
  if ($s -eq "PASS" -or $s -eq "OK" -or $s -eq "PRINT_READY" -or $s -eq "PREPARED" -or $s -eq "READY") { return $C_OK }
  if ($s -eq "WARNING" -or $s -eq "NEEDS_INPUT" -or $s -eq "CACHED" -or $s -eq "SKIPPED") { return $C_WARN }
  if ($s -eq "FAIL" -or $s -eq "FAILED" -or $s -eq "BLOCKED" -or $s -eq "NOT_PRINT_READY" -or $s -eq "UNSAFE") { return $C_BAD }
  return $C_IDLE
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "3D-AI Workstation"
$form.Size = New-Object System.Drawing.Size(1080, 720)

$top = New-Object System.Windows.Forms.Panel
$top.Dock = [System.Windows.Forms.DockStyle]::Top
$top.Height = 44
$form.Controls.Add($top)

$txtProject = New-Object System.Windows.Forms.TextBox
$txtProject.Location = New-Object System.Drawing.Point(10, 12)
$txtProject.Size = New-Object System.Drawing.Size(200, 22)
$txtProject.Name = "txtProject"
$top.Controls.Add($txtProject)

$bx = 220
foreach ($pair in @(("btnNew", "New"), ("btnOpen", "Open"), ("btnImport", "Import Model"),
                    ("btnText", "From Text"), ("btnPhoto", "From Photo(s)"))) {
  $b = New-Object System.Windows.Forms.Button
  $b.Name = $pair[0]; $b.Text = $pair[1]
  $b.Location = New-Object System.Drawing.Point($bx, 8)
  $b.Size = New-Object System.Drawing.Size(100, 26)
  $top.Controls.Add($b)
  $bx += 106
}

$actPanel = New-Object System.Windows.Forms.Panel
$actPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
$actPanel.Height = 44
$form.Controls.Add($actPanel)

$ax = 10
$script:wsActButtons = @{}
foreach ($pair in @(("btnRun", "Analyze"), ("btnRepair", "Repair"), ("btnPrint", "Printability"),
                    ("btnSlice", "Slice"), ("btnExport", "Export"), ("btnPrintJob", "Print (offline)"))) {
  $b = New-Object System.Windows.Forms.Button
  $b.Name = $pair[0]; $b.Text = $pair[1]
  $b.Location = New-Object System.Drawing.Point($ax, 8)
  $b.Size = New-Object System.Drawing.Size(110, 26)
  $actPanel.Controls.Add($b)
  $script:wsActButtons[$pair[0]] = $b
  $ax += 116
}
$lblTask = New-Object System.Windows.Forms.Label
$lblTask.Name = "lblTask"
$lblTask.Location = New-Object System.Drawing.Point($ax, 12)
$lblTask.Size = New-Object System.Drawing.Size(380, 22)
$actPanel.Controls.Add($lblTask)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabs.Name = "tabs"
$form.Controls.Add($tabs)

$tabDash = New-Object System.Windows.Forms.TabPage
$tabDash.Text = "Dashboard"
$tabDash.Name = "tabDash"
$tabs.TabPages.Add($tabDash)
$grid = New-Object System.Windows.Forms.DataGridView
$grid.Name = "gridDash"
$grid.Dock = [System.Windows.Forms.DockStyle]::Fill
$grid.ColumnCount = 2
$grid.Columns[0].Name = "Alan"
$grid.Columns[1].Name = "Deger"
$grid.Columns[1].Width = 600
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$tabDash.Controls.Add($grid)

$tabPipe = New-Object System.Windows.Forms.TabPage
$tabPipe.Text = "Pipeline"
$tabPipe.Name = "tabPipe"
$tabs.TabPages.Add($tabPipe)
$lstPipe = New-Object System.Windows.Forms.ListView
$lstPipe.Name = "lstPipe"
$lstPipe.Dock = [System.Windows.Forms.DockStyle]::Fill
$lstPipe.View = [System.Windows.Forms.View]::Details
$lstPipe.Columns.Add("Asama", 150) | Out-Null
$lstPipe.Columns.Add("Durum", 120) | Out-Null
$lstPipe.Columns.Add("Motor", 140) | Out-Null
$lstPipe.Columns.Add("Cikti", 500) | Out-Null
$tabPipe.Controls.Add($lstPipe)

$tabView = New-Object System.Windows.Forms.TabPage
$tabView.Text = "3D Viewer"
$tabView.Name = "tabView"
$tabs.TabPages.Add($tabView)
$cmbMesh = New-Object System.Windows.Forms.ComboBox
$cmbMesh.Name = "cmbMesh"
$cmbMesh.Dock = [System.Windows.Forms.DockStyle]::Top
$cmbMesh.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$tabView.Controls.Add($cmbMesh)
$lblMeas = New-Object System.Windows.Forms.Label
$lblMeas.Name = "lblMeas"
$lblMeas.Dock = [System.Windows.Forms.DockStyle]::Bottom
$lblMeas.Height = 26
$tabView.Controls.Add($lblMeas)
$pnlView = New-Object System.Windows.Forms.Panel
$pnlView.Name = "pnlView"
$pnlView.Dock = [System.Windows.Forms.DockStyle]::Fill
$pnlView.BackColor = [System.Drawing.Color]::White
$tabView.Controls.Add($pnlView)

$tabEng = New-Object System.Windows.Forms.TabPage
$tabEng.Text = "Engines"
$tabEng.Name = "tabEng"
$tabs.TabPages.Add($tabEng)
$gridEng = New-Object System.Windows.Forms.DataGridView
$gridEng.Name = "gridEng"
$gridEng.Dock = [System.Windows.Forms.DockStyle]::Fill
$gridEng.ColumnCount = 5
$gridEng.Columns[0].Name = "Motor"
$gridEng.Columns[1].Name = "Lisans"
$gridEng.Columns[2].Name = "Saglik"
$gridEng.Columns[3].Name = "Yetenekler"
$gridEng.Columns[4].Name = "Not"
$gridEng.Columns[4].Width = 420
$gridEng.ReadOnly = $true
$gridEng.AllowUserToAddRows = $false
$tabEng.Controls.Add($gridEng)

$tabSet = New-Object System.Windows.Forms.TabPage
$tabSet.Text = "Settings"
$tabSet.Name = "tabSet"
$tabs.TabPages.Add($tabSet)
$txtSet = New-Object System.Windows.Forms.TextBox
$txtSet.Name = "txtSet"
$txtSet.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtSet.Multiline = $true
$txtSet.ReadOnly = $true
$txtSet.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$tabSet.Controls.Add($txtSet)

$tabLog = New-Object System.Windows.Forms.TabPage
$tabLog.Text = "Logs"
$tabLog.Name = "tabLog"
$tabs.TabPages.Add($tabLog)
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Name = "txtLog"
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.Multiline = $true
$txtLog.ReadOnly = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Both
$tabLog.Controls.Add($txtLog)

function WS-RefreshAll {
  $proj = $txtProject.Text.Trim()
  if ($proj -eq "") { return }
  $pdir = $proj
  if (-not [System.IO.Path]::IsPathRooted($pdir)) { $pdir = Join-Path (WS-ProjectsRoot) $proj }
  if (-not (Test-Path -LiteralPath $pdir)) { $lblTask.Text = "proje yok: $proj"; return }
  $script:wsProject = $pdir
  $o = WS-ReadJson (Join-Path $pdir "orchestration.json")
  $pr = WS-ReadJson (Join-Path $pdir "pipeline-result.json")
  $grid.Rows.Clear()
  $rows = @(
    @("Proje", $proj),
    @("Surum", $(if ($null -ne $o) { "orch-9.0" } else { "pipeline" })),
    @("Durum", $(if ($null -ne $o) { [string]$o.status } elseif ($null -ne $pr) { [string]$pr.status } else { "UNKNOWN" })),
    @("Kapi", $(if ($null -ne $o) { $gt = @($o.stages) | Where-Object { [string]$_.stage -eq "gate" } | Select-Object -First 1; if ($null -ne $gt) { [string]$gt.output } else { "?" } } else { "?" }))
  )
  $mesh = WS-ProjectMeshes $pdir | Select-Object -First 1
  $rows += @(@("Model", $(if ($null -ne $mesh) { [System.IO.Path]::GetFileName($mesh) } else { "-" })))
  $dims = "-"
  if ($null -ne $o) {
    $ms = @($o.stages) | Where-Object { [string]$_.stage -eq "measure" } | Select-Object -First 1
    if ($null -ne $ms) { $dims = [string]$ms.output }
  }
  $rows += @(@("Olculer", $dims))
  $mq = "-"
  if ($null -ne $o) {
    $qs = @($o.stages) | Where-Object { [string]$_.stage -eq "mesh_qa" } | Select-Object -First 1
    if ($null -ne $qs) { $mq = [string]$qs.output }
  }
  $rows += @(@("Mesh", $mq))
  $pstat = "-"
  if ($null -ne $o) {
    $ps = @($o.stages) | Where-Object { [string]$_.stage -eq "printability" } | Select-Object -First 1
    if ($null -ne $ps) { $pstat = [string]$ps.output }
  }
  $rows += @(@("Printability", $pstat))
  $rstat = "-"
  if ($null -ne $o) {
    $rs = @($o.stages) | Where-Object { [string]$_.stage -eq "readiness" } | Select-Object -First 1
    if ($null -ne $rs) { $rstat = [string]$rs.output }
  }
  $rows += @(@("Dilime Hazirlik", $rstat))
  $warn = 0; $err = 0
  if ($null -ne $o) {
    foreach ($s in @($o.stages)) { $warn += @($s.warnings).Count; $err += @($s.errors).Count }
  }
  $rows += @(@("Uyarilar", $warn), @("Hatalar", $err))
  foreach ($r in $rows) { $grid.Rows.Add($r[0], $r[1]) | Out-Null }
  $lstPipe.Items.Clear()
  if ($null -ne $o) {
    foreach ($s in @($o.stages)) {
      $it = New-Object System.Windows.Forms.ListViewItem([string]$s.stage)
      $it.SubItems.Add([string]$s.status) | Out-Null
      $it.SubItems.Add([string]$s.engine) | Out-Null
      $it.SubItems.Add([string]$s.output) | Out-Null
      $it.ForeColor = (WS-StatusColor ([string]$s.status))
      $lstPipe.Items.Add($it) | Out-Null
    }
  }
  $meshes = @(WS-ProjectMeshes $pdir)
  $cmbMesh.Items.Clear()
  foreach ($m in $meshes) { $cmbMesh.Items.Add($m) | Out-Null }
  if (@($meshes).Count -gt 0) { $cmbMesh.SelectedIndex = 0 }
  $ops = Join-Path $pdir (Join-Path "logs" "ops.jsonl")
  if (Test-Path -LiteralPath $ops) {
    $lines = Get-Content -LiteralPath $ops | Select-Object -Last 60
    $txtLog.Text = ($lines -join "`r`n")
  } else { $txtLog.Text = "(ops.jsonl yok)" }
  $lblTask.Text = "yuklendi: $proj"
}

function WS-RefreshEngines {
  $gridEng.Rows.Clear()
  try {
    $reg = Get-Content -LiteralPath (Join-Path $WSEngine (Join-Path "Engines" "engines.json")) -Raw | ConvertFrom-Json
    foreach ($e in @($reg.engines)) {
      $h = "?"
      if ([string]$e.adapter -eq "") { $h = [string]$e.status }
      $gridEng.Rows.Add([string]$e.id, [string]$e.license_status, $h,
        ((@($e.capabilities) | ForEach-Object { [string]$_ }) -join ","), [string]$e.notes) | Out-Null
    }
  } catch { }
}

function WS-RefreshSettings {
  $sb = New-Object System.Text.StringBuilder
  $sj = WS-ReadJson (Join-Path $WSRoot "settings.json")
  $sl = WS-ReadJson (Join-Path $WSRoot "settings.local.json")
  [void]$sb.AppendLine("[tools]")
  if ($null -ne $sj -and $null -ne $sj.tools) {
    foreach ($p in @($sj.tools.PSObject.Properties)) { [void]$sb.AppendLine(("  " + $p.Name + " = " + [string]$p.Value)) }
  }
  [void]$sb.AppendLine("[local-overrides]")
  [void]$sb.AppendLine($(if ($null -ne $sl) { "  settings.local.json VAR (makine-ozel, gitlenmez)" } else { "  yok" }))
  [void]$sb.AppendLine("[python]")
  [void]$sb.AppendLine(("  env: " + (Join-Path (Split-Path -Parent $WSRoot) "3D-AI-External/envs/python312")))
  [void]$sb.AppendLine("[slicers]")
  $orca = ""
  try { $orca = & (Join-Path $WSScripts "Resolve-OrcaSlicer.ps1") 2>$null | Select-Object -Last 1 } catch { }
  [void]$sb.AppendLine(("  orcaslicer = " + $(if ([string]$orca -ne "") { [string]$orca } else { "bulunamadi (OPTIONAL)" })))
  [void]$sb.AppendLine("[printers/filaments/processes]")
  foreach ($dn in @("printers", "filaments", "processes")) {
    $dd = Join-Path $WSRoot $dn
    $names = @()
    if (Test-Path -LiteralPath $dd) {
      $names = @(Get-ChildItem -LiteralPath $dd -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    }
    [void]$sb.AppendLine(("  " + $dn + ": " + ($names -join ", ")))
  }
  [void]$sb.AppendLine("[dirs]")
  [void]$sb.AppendLine(("  projects = " + (WS-ProjectsRoot)))
  [void]$sb.AppendLine(("  cache = <proje>/.cache (guvenli anahtarli)"))
  [void]$sb.AppendLine(("  logs = <proje>/logs/ops.jsonl"))
  $txtSet.Text = $sb.ToString()
}

function WS-RunJob($kind, $argList) {
  if ($null -ne $script:wsJob -and $script:wsJob.State -eq "Running") {
    $lblTask.Text = "is zaten calisiyor"; return
  }
  $lblTask.Text = "RUNNING: $kind"
  $script:wsJobKind = $kind
  $script:wsJob = Start-Job -ScriptBlock {
    param($root, $args2)
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root "engine/Invoke-Orchestrator.ps1") @args2 2>$null | Out-String
  } -ArgumentList @($WSRoot, $argList)
  $timer.Start()
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 1000
$timer.Add_Tick({
  if ($null -eq $script:wsJob) { $timer.Stop(); return }
  if ($script:wsJob.State -eq "Running") { return }
  $timer.Stop()
  $res = Receive-Job $script:wsJob 2>$null | Out-String
  Remove-Job $script:wsJob -Force -ErrorAction SilentlyContinue
  $script:wsJob = $null
  $lblTask.Text = "bitti: " + $script:wsJobKind
  WS-RefreshAll
})

$pnlView.Add_Paint({
  param($s, $e)
  $g = $e.Graphics
  $g.Clear([System.Drawing.Color]::White)
  if ($null -eq $script:wsFacets -or @($script:wsFacets).Count -eq 0) { return }
  $w = $pnlView.Width; $h = $pnlView.Height
  if ($w -le 0 -or $h -le 0) { return }
  $cy = [math]::Cos($script:wsYaw); $sy = [math]::Sin($script:wsYaw)
  $cx = [math]::Cos($script:wsPitch); $sx = [math]::Sin($script:wsPitch)
  $pts3 = @()
  foreach ($f in @($script:wsFacets)) { foreach ($v in @($f)) { $pts3 += ,@($v) } }
  $cx0 = 0; $cy0 = 0; $cz0 = 0
  foreach ($p in $pts3) { $cx0 += [double]$p[0]; $cy0 += [double]$p[1]; $cz0 += [double]$p[2] }
  $n = @($pts3).Count
  if ($n -eq 0) { return }
  $cx0 /= $n; $cy0 /= $n; $cz0 /= $n
  $span = 1
  foreach ($p in $pts3) {
    $dx = [math]::Abs([double]$p[0] - $cx0); $dy = [math]::Abs([double]$p[1] - $cy0); $dz = [math]::Abs([double]$p[2] - $cz0)
    $m = [math]::Max($dx, [math]::Max($dy, $dz))
    if ($m -gt $span) { $span = $m }
  }
  if ($span -le 0) { $span = 1 }
  $scale = [math]::Min($w, $h) / 2.4 / $span * $script:wsZoom
  $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, 90, 160), 1)
  $i = 0
  foreach ($f in @($script:wsFacets)) {
    $pp = @()
    foreach ($v in @($f)) {
      $x = [double]$v[0] - $cx0; $y = [double]$v[1] - $cy0; $z = [double]$v[2] - $cz0
      $x1 = $x * $cy + $z * $sy; $z1 = -$x * $sy + $z * $cy
      $y1 = $y * $cx - $z1 * $sx
      $sx2 = $w / 2 + $x1 * $scale + $script:wsPanX
      $sy2 = $h / 2 - $y1 * $scale + $script:wsPanY
      $pp += New-Object System.Drawing.PointF($sx2, $sy2)
    }
    if (@($pp).Count -eq 3) { $g.DrawPolygon($pen, $pp) }
    $i++
  }
  $pen.Dispose()
})

$pnlView.Add_MouseDown({ param($s, $e) $script:wsDrag = @{ x = $e.X; y = $e.Y; btn = [string]$e.Button } })
$pnlView.Add_MouseMove({
  param($s, $e)
  if ($null -eq $script:wsDrag) { return }
  $dx = $e.X - $script:wsDrag.x; $dy = $e.Y - $script:wsDrag.y
  if ($script:wsDrag.btn -eq "Right") { $script:wsPanX += $dx; $script:wsPanY += $dy }
  else { $script:wsYaw += $dx * 0.01; $script:wsPitch += $dy * 0.01 }
  $script:wsDrag = @{ x = $e.X; y = $e.Y; btn = $script:wsDrag.btn }
  $pnlView.Invalidate()
})
$pnlView.Add_MouseUp({ param($s, $e) $script:wsDrag = $null })
$pnlView.Add_MouseWheel({
  param($s, $e)
  if ($e.Delta -gt 0) { $script:wsZoom *= 1.1 } else { $script:wsZoom /= 1.1 }
  $pnlView.Invalidate()
})
$pnlView.Add_DoubleClick({
  $script:wsYaw = 0.6; $script:wsPitch = 0.5; $script:wsZoom = 1.0; $script:wsPanX = 0; $script:wsPanY = 0
  $pnlView.Invalidate()
})

$cmbMesh.Add_SelectedIndexChanged({
  $m = [string]$cmbMesh.SelectedItem
  if ($m -eq "" -or -not (Test-Path -LiteralPath $m)) { return }
  $script:wsMeshA = $m
  $script:wsFacets = @(WS-ParseStl $m 4000)
  $n = @($script:wsFacets).Count
  $info = "yuzey: $n (gosterim, wireframe)"
  try {
    $q = & (Join-Path $WSEngine "Get-MeshQuality.ps1") -StlFile $m -AsJson 2>$null | Out-String | ConvertFrom-Json
    if ($null -ne $q) {
      $info = ("olcu=" + [string]$q.bbox_size_mm[0] + "x" + [string]$q.bbox_size_mm[1] + "x" + [string]$q.bbox_size_mm[2] +
               " ucgen=" + [string]$q.triangle_count + " watertight=" + [string]$q.watertight + " yuzey:" + $n)
    }
  } catch { }
  $lblMeas.Text = $info
  $pnlView.Invalidate()
})

$top.Controls["btnNew"].Add_Click({
  $n = $txtProject.Text.Trim()
  if ($n -eq "") { $lblTask.Text = "proje adi yazin"; return }
  $pdir = Join-Path (WS-ProjectsRoot) $n
  New-Item -ItemType Directory -Force -Path $pdir | Out-Null
  $lblTask.Text = "proje acildi: $n"
  WS-RefreshAll
})
$top.Controls["btnOpen"].Add_Click({ WS-RefreshAll; WS-RefreshEngines; WS-RefreshSettings })
$top.Controls["btnImport"].Add_Click({
  $d = New-Object System.Windows.Forms.OpenFileDialog
  $d.Filter = "Mesh (STL,OBJ,3MF)|*.stl;*.obj;*.3mf|Goruntu|*.png;*.jpg;*.jpeg|STEP|*.step;*.stp|Tumu|*.*"
  if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $n = $txtProject.Text.Trim()
    if ($n -eq "") { $n = [System.IO.Path]::GetFileNameWithoutExtension($d.FileName) + "-ws"; $txtProject.Text = $n }
    WS-RunJob "import" @("-Source", $d.FileName, "-ProjectName", $n)
  }
})
$top.Controls["btnText"].Add_Click({
  $t = [Microsoft.VisualBasic.Interaction]::InputBox("Tasarim cumlesi:", "From Text", "50x50x20 kutu")
  if ([string]$t -ne "") {
    $n = $txtProject.Text.Trim()
    if ($n -eq "") { $n = "ws-text"; $txtProject.Text = $n }
    WS-RunJob "text" @("-Source", $t, "-ProjectName", $n)
  }
})
$top.Controls["btnPhoto"].Add_Click({
  $d = New-Object System.Windows.Forms.OpenFileDialog
  $d.Filter = "Goruntu|*.png;*.jpg;*.jpeg"
  $d.Multiselect = $true
  if ($d.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
    $n = $txtProject.Text.Trim()
    if ($n -eq "") { $n = "ws-photo"; $txtProject.Text = $n }
    if (@($d.FileNames).Count -eq 1) { WS-RunJob "photo" @("-Source", $d.FileNames[0], "-ProjectName", $n) }
    else {
      $pd = Join-Path ([System.IO.Path]::GetTempPath()) ("wsphotos-" + [System.Guid]::NewGuid().ToString("N").Substring(0, 8))
      New-Item -ItemType Directory -Force -Path $pd | Out-Null
      foreach ($f in @($d.FileNames)) { Copy-Item -LiteralPath $f -Destination (Join-Path $pd ([System.IO.Path]::GetFileName($f))) -Force }
      WS-RunJob "multiphoto" @("-Source", $pd, "-ProjectName", $n)
    }
  }
})

$script:wsActButtons["btnRun"].Add_Click({
  $n = $txtProject.Text.Trim()
  if ($n -eq "") { $lblTask.Text = "once proje secin"; return }
  WS-RunJob "analyze" @("-Source", (Join-Path (WS-ProjectsRoot) $n), "-ProjectName", $n, "-Resume")
})
$script:wsActButtons["btnRepair"].Add_Click({ $lblTask.Text = "repair hatta dahildir (analyze kosun)" })
$script:wsActButtons["btnPrint"].Add_Click({ $lblTask.Text = "printability hatta dahildir (analyze kosun)" })
$script:wsActButtons["btnSlice"].Add_Click({
  $n = $txtProject.Text.Trim()
  if ($n -eq "") { $lblTask.Text = "once proje secin"; return }
  $lblTask.Text = "slice: profil yoksa gate kapali kalir (guvenli)"
  WS-RunJob "slice" @("-Source", (Join-Path (WS-ProjectsRoot) $n), "-ProjectName", $n, "-Resume")
})
$script:wsActButtons["btnExport"].Add_Click({
  $n = $txtProject.Text.Trim()
  if ($n -eq "") { $lblTask.Text = "once proje secin"; return }
  $pdir = Join-Path (WS-ProjectsRoot) $n
  $out = Join-Path $pdir "export"
  try {
    $r = & (Join-Path $WSScripts "Export-Project.ps1") -ProjectDir $pdir -OutDir $out 2>&1 | Out-String | ConvertFrom-Json
    $lblTask.Text = "export: " + [string]$r.status + " (" + ((@($r.exported) | ForEach-Object { [string]$_ }) -join ",") + ")"
  } catch { $lblTask.Text = "export hatasi" }
})
$script:wsActButtons["btnPrintJob"].Add_Click({
  $lblTask.Text = "OFFLINE: baski isi hazirlanir, yaziciya GONDERILMEZ (gonderme kodu yok)"
})

if ($SelfTest) {
  $names = @("txtProject", "btnNew", "btnOpen", "btnImport", "btnText", "btnPhoto",
             "btnRun", "btnRepair", "btnPrint", "btnSlice", "btnExport", "btnPrintJob",
             "tabs", "tabDash", "tabPipe", "tabView", "tabEng", "tabSet", "tabLog",
             "gridDash", "lstPipe", "cmbMesh", "pnlView", "lblMeas", "gridEng", "txtSet", "txtLog", "lblTask")
  $missing = @()
  foreach ($cn in $names) {
    $found = $false
    foreach ($c in @($form.Controls)) {
      if ($c.Name -eq $cn) { $found = $true; break }
      foreach ($cc in @($c.Controls)) { if ($cc.Name -eq $cn) { $found = $true; break } }
      if ($found) { break }
    }
    if (-not $found) {
      $deep = $form.Controls.Find($cn, $true)
      if (@($deep).Count -gt 0) { $found = $true }
    }
    if (-not $found) { $missing += @($cn) }
  }
  Write-Output ("WS-SELFTEST: controls=" + (@($names).Count - @($missing).Count) + "/" + @($names).Count)
  if (@($missing).Count -gt 0) { Write-Output ("WS-SELFTEST: MISSING " + ($missing -join ",")); exit 1 }
  Write-Output "WS-SELFTEST: PASS"
  exit 0
}

if ($ValidateUI) {
  try {
    WS-RefreshEngines
    $n = @($gridEng.Rows).Count
    if ($n -gt 5) { Write-Output "UI-STARTUP: PASS"; exit 0 }
    Write-Output "UI-STARTUP: FAIL"; exit 1
  } catch { Write-Output "UI-STARTUP: FAIL"; exit 1 }
}

WS-RefreshEngines
WS-RefreshSettings
[void]$form.ShowDialog()
