<#
.SYNOPSIS
  DesignSpec edit orkestratoru (Phase 3).
.DESCRIPTION
  Akis: Parse-EditIntent -> Test-PatchOp (hepsi) -> candidate (atomic) ->
  gate -> geometry engine -> measurement/regression karsilastirma ->
  accept (version) / reject (state degismez).
  Undo/redo/restore geometry calistirmaz (snapshot zaten validasyonluydu).
  -AutoAccept olmadan requires_confirmation op uygulanmaz.
.EXAMPLE
  powershell -File engine\Invoke-SpecEdit.ps1 -ProjectDir projects\x -Instruction "duvari 4 mm yap" -AutoAccept
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [Parameter(Mandatory = $true)][string]$Instruction,
  [switch]$AutoAccept
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
. (Join-Path $EngineDir "DesignSpecPatch.ps1")
. (Join-Path $EngineDir "EditIntent.ps1")
. (Join-Path $EngineDir "ProjectVersions.ps1")
. (Join-Path $EngineDir "CanonicalSpec.ps1")
. (Join-Path $EngineDir "Write-OpLog.ps1")

function Write-EditResult($obj, $code) {
  $obj | ConvertTo-Json -Depth 8
  exit $code
}

if (-not (Test-Path -LiteralPath $ProjectDir)) {
  New-Item -ItemType Directory -Force -Path $ProjectDir | Out-Null
}
$specPath = Join-Path $ProjectDir "spec.json"

$idx = Read-VersionsIndex $ProjectDir
if ($null -eq $idx) {
  if (-not (Test-Path -LiteralPath $specPath)) {
    Write-EditResult ([pscustomobject]@{
      status = "BLOCKED"; reason = "spec.json yok ve version store yok"
      version = $null; questions = @(); gcode_available = $false
    }) 2
  }
  $baseSpec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
  $idx = Initialize-Versions $ProjectDir $baseSpec "initial import"
}
$currentId = [string]$idx.current
$currentSpec = Get-VersionSpec $ProjectDir $currentId
if ($null -eq $currentSpec) {
  Write-EditResult ([pscustomobject]@{
    status = "BLOCKED"; reason = "current version okunamadi"; version = $currentId
    questions = @(); gcode_available = $false
  }) 2
}

$intent = Parse-EditIntent $currentSpec $Instruction
if ([string]$intent.kind -eq "clarify") {
  Write-EditResult ([pscustomobject]@{
    status = "NEEDS_INPUT"; reason = "clarification required"; message = [string]$intent.message
    version = $currentId; questions = @(); gcode_available = $false
  }) 3
}
if ([string]$intent.kind -eq "not-edit") {
  Write-EditResult ([pscustomobject]@{
    status = "BLOCKED"; reason = [string]$intent.message
    version = $currentId; questions = @(); gcode_available = $false
  }) 2
}
if ([string]$intent.kind -eq "undo") {
  $r = Undo-ProjectVersion $ProjectDir
  Write-EditResult ([pscustomobject]@{
    status = $(if ($r.ok) { "OK" } else { "BLOCKED" }); reason = [string]$r.message
    version = [string]$r.current; questions = @(); gcode_available = $false
  }) $(if ($r.ok) { 0 } else { 2 })
}
if ([string]$intent.kind -eq "redo") {
  $r = Redo-ProjectVersion $ProjectDir
  Write-EditResult ([pscustomobject]@{
    status = $(if ($r.ok) { "OK" } else { "BLOCKED" }); reason = [string]$r.message
    version = [string]$r.current; questions = @(); gcode_available = $false
  }) $(if ($r.ok) { 0 } else { 2 })
}
if ([string]$intent.kind -eq "restore") {
  try {
    $nid = Restore-ProjectVersion $ProjectDir ([string]$intent.restore_target) ("restore " + [string]$intent.restore_target)
    Write-EditResult ([pscustomobject]@{
      status = "OK"; reason = "restored"; version = $nid; questions = @(); gcode_available = $false
    }) 0
  } catch {
    Write-EditResult ([pscustomobject]@{
      status = "BLOCKED"; reason = [string]$_.Exception.Message
      version = $currentId; questions = @(); gcode_available = $false
    }) 2
  }
}

$ops = @($intent.ops)
if ($ops.Count -eq 0) {
  Write-EditResult ([pscustomobject]@{
    status = "BLOCKED"; reason = "islem cikarilamadi"
    version = $currentId; questions = @(); gcode_available = $false
  }) 2
}
$needConfirm = $false
foreach ($o in $ops) { if ($o.requires_confirmation -eq $true) { $needConfirm = $true } }
if ($needConfirm -and -not $AutoAccept) {
  Write-EditResult ([pscustomobject]@{
    status = "NEEDS_CONFIRMATION"; reason = "kaldirma islemi onay gerektirir"
    version = $currentId; ops = @($ops); questions = @(); gcode_available = $false
  }) 3
}
foreach ($o in $ops) {
  $vr = Test-PatchOp $currentSpec $o
  if (-not $vr.ok) {
    Write-EditResult ([pscustomobject]@{
      status = "REJECTED"; reason = ("patch validation: " + [string]$vr.message)
      version = $currentId; questions = @(); gcode_available = $false
    }) 2
  }
}

$candSpec = $currentSpec | ConvertTo-Json -Depth 12 | ConvertFrom-Json
foreach ($o in $ops) { $candSpec = Invoke-PatchOp $candSpec $o }
$diff = Compare-Spec $currentSpec $candSpec
$allowedPaths = @($ops | ForEach-Object { [string]$_.path })
$unexpected = @()
foreach ($p in @($diff.changed_paths)) {
  if ($allowedPaths -notcontains $p) { $unexpected += $p }
}
if ($unexpected.Count -gt 0) {
  Write-EditResult ([pscustomobject]@{
    status = "REJECTED"; reason = ("beklenmeyen degisiklik: " + ($unexpected -join ", "))
    version = $currentId; questions = @(); gcode_available = $false
  }) 2
}

$candDir = Join-Path $ProjectDir (Join-Path "candidates" ([System.Guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Force -Path $candDir | Out-Null
$candSpecFile = Join-Path $candDir "spec.json"
try {
  $candSpec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $candSpecFile -Encoding UTF8
  $gvTxt = & (Join-Path $EngineDir "Test-GeometrySpec.ps1") -SpecFile $candSpecFile -AsJson 2>&1 | Out-String
  $gv = $gvTxt | ConvertFrom-Json
  if (@($gv.errors).Count -gt 0) { throw ("gate: " + ((@($gv.errors) | Select-Object -First 3) -join " | ")) }
  $engOut = & (Join-Path $EngineDir "Invoke-GeometryEngine.ps1") -SpecFile $candSpecFile -ProjectDir $candDir 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) { throw ("geometry: exit " + $LASTEXITCODE) }
  $partsOk = $true
  $vdDir = Join-Path $candDir "validation"
  if (Test-Path -LiteralPath $vdDir) {
    foreach ($vf in (Get-ChildItem -LiteralPath $vdDir -Filter "*.validation.json")) {
      try {
        $vv = Get-Content -LiteralPath $vf.FullName -Raw | ConvertFrom-Json
        if ([string]$vv.status -eq "FAIL" -or [string]$vv.status -eq "FAILED_AFTER_RETRIES" -or [string]$vv.status -eq "BLOCKED") { $partsOk = $false }
      } catch { $partsOk = $false }
    }
  } else { $partsOk = $false }
  if (-not $partsOk) { throw "measurement: candidate validation basarisiz" }
  $measSummary = [pscustomobject]@{ parts_checked = $true; status = "PASS" }
  $critLines = Format-CriticalDiff $diff
  $sumLines = @()
  foreach ($o in $ops) { $sumLines += ([string]$o.path + " -> " + (($o.value | ConvertTo-Json -Compress))) }
  $nid = New-ProjectVersion $ProjectDir $currentId $candSpec ("edit: " + ($sumLines -join "; ")) $ops $null $measSummary
  $candSpec | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $specPath -Encoding UTF8
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-OpLog $ProjectDir "edit" "Invoke-SpecEdit" $Instruction 0 "OK" ""
  Write-EditResult ([pscustomobject]@{
    status = "OK"; reason = "accepted"; version = $nid
    diff_changed = @($diff.changed); diff_report = @($critLines)
    questions = @(); gcode_available = $false
  }) 0
} catch {
  Remove-Item -LiteralPath $candDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-OpLog $ProjectDir "edit" "Invoke-SpecEdit" $Instruction 0 "REJECTED" ([string]$_.Exception.Message)
  Write-EditResult ([pscustomobject]@{
    status = "REJECTED"; reason = [string]$_.Exception.Message
    version = $currentId; questions = @(); gcode_available = $false
  }) 2
}
