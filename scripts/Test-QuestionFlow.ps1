<#
.SYNOPSIS
  NEEDS_INPUT -> question -> UI soru akisi regression testleri (QF-A..QF-D).
.DESCRIPTION
   Wall-mount repro promptu (planner wall_plate + olcusuz kablo kesiti c1)
   uzerinden dogrular (wall_station promptu planner ile PASS urettiginden
   NEEDS_INPUT repro'su wall_plate niyetine tasindi):
    QF-B: pipeline question contract (NEEDS_INPUT, body-cutout-c1, CAD/STL yok).
    QF-A: orchestrator design-stage warnings bos degil, gercek question_id + soru.
    QF-C: proje-tekrar-acma hidrasyonu (sakli pipeline-result.json -> soru state +
          mevcut render mekanizmasi baglantisi statik olarak).
    QF-D: organizer davranisi bozulmadi (PASS, soru yok, STL var).
  Mock/fake YOK. NEEDS_INPUT PASS'e cevrilmez; CAD/STL uretimi denenmez.
.EXAMPLE
  powershell -File scripts\Test-QuestionFlow.ps1
#>
param()

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"

$script:pass = 0; $script:fail = 0
function QF-Result($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

$wallPrompt = "Duvar icin montaj aparati tasarla, kablo kanali olsun"
$orgPrompt = "Masam icin bolmeli bir organizer tasarla. Kalemler icin bolum, telefon icin egimli yuva ve sarj kablosu icin kanal olsun. Ustu acik, desteksiz basilsin."

function Invoke-Pipe($name, $prompt) {
  $dd = Join-Path $Root (Join-Path "projects" $name)
  if (Test-Path -LiteralPath $dd) { Remove-Item -LiteralPath $dd -Recurse -Force -ErrorAction SilentlyContinue }
  $o = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Pipeline.ps1") `
    -Prompt $prompt -ProjectName $name 2>&1 | Out-String
  $rp = Join-Path $Root (Join-Path "projects" (Join-Path $name "pipeline-result.json"))
  if (-not (Test-Path -LiteralPath $rp)) { return $null }
  return (Get-Content -LiteralPath $rp -Raw | ConvertFrom-Json)
}

# ---- QF-B: pipeline question contract ----
try {
  $res = Invoke-Pipe "_ptest-q-wall" $wallPrompt
  $bok = $false; $bnote = "sonuc yok"
  if ($null -ne $res) {
    $qs = @($res.questions)
    $q0 = $null; if ($qs.Count -gt 0) { $q0 = $qs[0] }
    $pdir = Join-Path $Root (Join-Path "projects" "_ptest-q-wall")
    $scads = @(Get-ChildItem -LiteralPath (Join-Path $pdir "cad") -Filter "*.scad" -ErrorAction SilentlyContinue)
    $stls = @(Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" -ErrorAction SilentlyContinue)
    $contractOk = ($null -ne $q0 -and [string]$q0.question_id -ne "" -and [string]$q0.question -ne "" `
      -and [string]$q0.component -ne "" -and [string]$q0.field -ne "" -and [string]$q0.target -ne "" `
      -and [string]$q0.kind -ne "" -and [string]$q0.reason -ne "" -and [string]$q0.displayId -ne "" `
      -and [string]$q0.parser -ne "" -and $null -ne $q0.required -and $null -ne $q0.priority)
    if ([string]$res.status -eq "NEEDS_INPUT" -and $qs.Count -ge 1 `
        -and [string]$q0.question_id -eq "body-cutout-c1" -and [string]$q0.question -ne "" `
        -and $contractOk -and @($scads).Count -eq 0 -and @($stls).Count -eq 0) {
      $bok = $true; $bnote = ("NEEDS_INPUT, soru=" + [string]$q0.question_id + ", contract 11 alan OK, CAD/STL yok")
    } else {
      $bnote = ("status=" + [string]$res.status + " soru=" + @($res.questions).Count + " scad=" + @($scads).Count + " stl=" + @($stls).Count)
    }
  }
  QF-Result "QF-B-pipe-contract" $bok $bnote
} catch { QF-Result "QF-B-pipe-contract" $false $_.Exception.Message }

# ---- QF-A: orchestrator question warnings ----
try {
  $oo = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineDir "Invoke-Orchestrator.ps1") `
    -Source $wallPrompt -ProjectName "_ptest-q-orch" 2>&1 | Out-String
  $oj = Join-Path $Root (Join-Path "projects" (Join-Path "_ptest-q-orch" "orchestration.json"))
  $aok = $false; $anote = "orchestration.json yok"
  if (Test-Path -LiteralPath $oj) {
    $o = Get-Content -LiteralPath $oj -Raw | ConvertFrom-Json
    $ds = $null
    foreach ($s in @($o.stages)) { if ([string]$s.stage -eq "design") { $ds = $s; break } }
    $ws = @()
    if ($null -ne $ds) { $ws = @($ds.warnings) }
    $blank = @($ws | Where-Object { [string]$_ -match "soru:\s*-\s*$" })
    $good = @($ws | Where-Object { [string]$_ -match "soru: body-cutout-c1 - Kesik" })
    if ([string]$o.status -eq "NEEDS_INPUT" -and @($o.questions).Count -ge 1 -and $blank.Count -eq 0 -and $good.Count -ge 1) {
      $aok = $true; $anote = ("NEEDS_INPUT, warnings soru-id+metin iceriyor, bos 'soru:  - ' yok")
    } else {
      $anote = ("status=" + [string]$o.status + " soru=" + @($o.questions).Count + " blank=" + $blank.Count + " good=" + $good.Count)
    }
  }
  QF-Result "QF-A-orch-warnings" $aok $anote
} catch { QF-Result "QF-A-orch-warnings" $false $_.Exception.Message }

# ---- QF-C: project reload hydration (veri yolu + mevcut render baglantisi) ----
try {
  $pdir = Join-Path $Root (Join-Path "projects" "_ptest-q-wall")
  $selResPath = Join-Path $pdir "pipeline-result.json"
  $selSpecPath = Join-Path $pdir "spec.json"
  # Handler ile AYNI ifadeler (DesignerV1.ps1 proje-secim hidrasyon blogu).
  $selQs = @()
  $selPrompt = ""
  if (Test-Path -LiteralPath $selSpecPath) {
    $selSpecObj = Get-Content -LiteralPath $selSpecPath -Raw | ConvertFrom-Json
    if ($null -ne $selSpecObj.prompt -and [string]$selSpecObj.prompt -ne "") { $selPrompt = [string]$selSpecObj.prompt }
  }
  if (Test-Path -LiteralPath $selResPath) {
    $selResult = Get-Content -LiteralPath $selResPath -Raw | ConvertFrom-Json
    if ($null -ne $selResult -and [string]$selResult.status -eq "NEEDS_INPUT" -and $null -ne $selResult.questions) {
      if ($selResult.questions -is [array]) { $selQs = @($selResult.questions) }
      else { $selQs = @($selResult.questions) }
    }
  }
  $hydrated = @($selQs | Where-Object { $_ -ne $null })
  # Get-DisplayQuestion ile AYNI alan okuma (DesignerV1.ps1 satir ~845-856).
  $dqText = ""; $dqOk = $false
  if ($hydrated.Count -gt 0) {
    $first = $hydrated[0]
    $dqText = ("[" + "q1" + "] " + [string]$first.question + " (tur: " + [string]$first.kind + ")")
    $dqOk = ([string]$first.question_id -eq "body-cutout-c1" -and $dqText -match "Kesik")
  }
  # Statik baglanti: secim-olayinda hidrasyon -> mevcut Show-CurrentQuestion cagrisi.
  $dv = [System.IO.File]::ReadAllText((Join-Path $Root (Join-Path "app" "DesignerV1.ps1")))
  $selIdx = $dv.IndexOf('$lstProjects.Add_SelectedIndexChanged({')
  $hydIdx = $dv.IndexOf('$script:pipeQuestions = @($selQs', $selIdx)
  $showIdx = $dv.IndexOf('Show-CurrentQuestion', $selIdx)
  $wired = ($selIdx -ge 0 -and $hydIdx -gt $selIdx -and $showIdx -gt $hydIdx)
  $cok = ($hydrated.Count -ge 1 -and $dqOk -and $selPrompt -ne "" -and $wired)
  QF-Result "QF-C-reload-hydration" $cok ("hydrate=" + $hydrated.Count + " render-metin=" + $dqOk + " prompt=" + ($selPrompt -ne "") + " baglanti=" + $wired)
} catch { QF-Result "QF-C-reload-hydration" $false $_.Exception.Message }

# ---- QF-D: organizer regression (davranis bozulmadi) ----
try {
  $res = Invoke-Pipe "_ptest-f-org" $orgPrompt
  $dok = $false; $dnote = "sonuc yok"
  if ($null -ne $res) {
    $pdir = Join-Path $Root (Join-Path "projects" "_ptest-f-org")
    $stl = Get-ChildItem -LiteralPath (Join-Path $pdir "output") -Filter "*.stl" -ErrorAction SilentlyContinue | Select-Object -First 1
    if (([string]$res.status -eq "PASS" -or [string]$res.status -eq "WARNING") -and @($res.questions).Count -eq 0 -and $null -ne $stl -and $stl.Length -gt 1000) {
      $dok = $true; $dnote = ("status=" + [string]$res.status + " sorusuz, stl=" + $stl.Length)
    } else {
      $dnote = ("status=" + [string]$res.status + " soru=" + @($res.questions).Count)
    }
  }
  QF-Result "QF-D-organizer" $dok $dnote
} catch { QF-Result "QF-D-organizer" $false $_.Exception.Message }

Write-Output "----------------------------------------"
Write-Output ("SORU-AKIS SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
