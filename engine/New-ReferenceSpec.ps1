<#
.SYNOPSIS
  "Aynisini yap ama..." : referans olculer + degisiklik komutu -> DesignSpec v2.
.DESCRIPTION
  Referans JSON'daki GERCEK olculer (bbox) taban alinir; degisiklik promptu parser'dan
  gecer; delik/kesik/hollow/tolerans/transform/kenar degisiklikleri tabana uygulanir.
  Referansta bilinmeyen + promptta yoksa missing kalir (soru uretilir). Olcu UYDURULMAZ.
  Adet ("iki tane uret") metadata.quantity olarak saklanir (geometri kopyalanmaz).
.EXAMPLE
  powershell -File engine\New-ReferenceSpec.ps1 -ReferenceJson p\reference\reference.json -ModPrompt "deligi 8 mm yap" -ProjectName x -OutSpec p\spec.json
#>
param(
  [Parameter(Mandatory = $true)][string]$ReferenceJson,
  [Parameter(Mandatory = $true)][string]$ModPrompt,
  [Parameter(Mandatory = $true)][string]$ProjectName,
  [Parameter(Mandatory = $true)][string]$OutSpec
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
if (-not (Test-Path -LiteralPath $ReferenceJson)) { throw "Referans analiz sonucu bulunamadi." }
$ref = Get-Content -LiteralPath $ReferenceJson -Raw | ConvertFrom-Json

$base = [pscustomobject]@{
  id = "body"; label = "referans taban"
  base = [pscustomobject]@{ shape = "box"; width_mm = $null; depth_mm = $null; height_mm = $null }
  hollow = $null; holes = @(); cutouts = @(); edge_notes = @(); transforms = @()
  tolerance = $null; expected_bbox = $null; pending_rotate = $null; pending_mirror = $false
}
if ($ref.bbox_known -and $ref.bbox_min -and $ref.bbox_max) {
  $sx = [double]$ref.bbox_max[0] - [double]$ref.bbox_min[0]
  $sy = [double]$ref.bbox_max[1] - [double]$ref.bbox_min[1]
  $sz = [double]$ref.bbox_max[2] - [double]$ref.bbox_min[2]
  if ($sx -gt 0 -and $sy -gt 0 -and $sz -gt 0) {
    $base.base.width_mm = [math]::Round($sx, 3)
    $base.base.depth_mm = [math]::Round($sy, 3)
    $base.base.height_mm = [math]::Round($sz, 3)
  }
}

$tmpMod = Join-Path ([System.IO.Path]::GetTempPath()) ("refmod-" + $ProjectName + ".json")
& (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $ModPrompt -ProjectName $ProjectName -OutPath $tmpMod 2>&1 | Out-Null
$mod = Get-Content -LiteralPath $tmpMod -Raw | ConvertFrom-Json
Remove-Item -LiteralPath $tmpMod -Force -ErrorAction SilentlyContinue
$modBody = @($mod.components) | Where-Object { $_.id -eq "body" } | Select-Object -First 1
if ($modBody) {
  foreach ($h in @($modBody.holes)) { if ($h) { $base.holes = @(@($base.holes) + @($h)) } }
  foreach ($t in @($modBody.cutouts)) { if ($t) { $base.cutouts = @(@($base.cutouts) + @($t)) } }
  if ($modBody.hollow) { $base.hollow = $modBody.hollow }
  if ($modBody.tolerance) { $base.tolerance = $modBody.tolerance }
  foreach ($e in @($modBody.edge_notes)) { if ($e) { $base.edge_notes = @(@($base.edge_notes) + @($e)) } }
  foreach ($tr in @($modBody.transforms)) { if ($tr) { $base.transforms = @(@($base.transforms) + @($tr)) } }
  if ($modBody.pending_rotate) { $base.pending_rotate = $modBody.pending_rotate }
  if ($modBody.pending_mirror -eq $true) { $base.pending_mirror = $true }
  if ($modBody.base.width_mm -and $modBody.base.depth_mm -and $modBody.base.height_mm) {
    $base.base.width_mm = $modBody.base.width_mm
    $base.base.depth_mm = $modBody.base.depth_mm
    $base.base.height_mm = $modBody.base.height_mm
  }
}
$modExtra = @($mod.components) | Where-Object { $_.id -ne "body" }
$allComps = New-Object System.Collections.Generic.List[object]
$allComps.Add($base) | Out-Null
foreach ($c in $modExtra) { if ($c) { $allComps.Add($c) | Out-Null } }

$qty = $null
$qm = [regex]::Match($ModPrompt, '(\d+)\s*tane')
if ($qm.Success) { $qty = [int]$qm.Groups[1].Value }
elseif ($ModPrompt -match "iki\s*tane") { $qty = 2 }

$spec = [pscustomobject]@{
  project_name = $ProjectName
  prompt = ("referans (" + [string]$ref.type + ") + degisiklik: " + $ModPrompt)
  metadata = [pscustomobject]@{ spec_version = "2.0"; reference_type = [string]$ref.type; quantity = $qty }
  components = @($allComps.ToArray())
  assembly = $mod.assembly
  material = $null
}
$spec | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutSpec -Encoding UTF8
Write-Output "REFSPEC: $OutSpec (taban olculer: $(if ($base.base.width_mm) { 'referanstan' } else { 'eksik-sorulacak' }))"
