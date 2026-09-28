[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$SpecFile,

    [Parameter(Mandatory=$false)]
    [string]$StlFile,

    [Parameter(Mandatory=$false)]
    [string]$MaterialId = "pla",

    [Parameter(Mandatory=$false)]
    [int]$InfillPct = 20,

    [Parameter(Mandatory=$false)]
    [double]$PricePerKg = 0,

    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

# Resolve SpecFile robustly: absolute, CWD-relative, then project-root-relative.
$ResolvedSpec = $SpecFile
if (-not [System.IO.Path]::IsPathRooted($ResolvedSpec)) {
    $cwdCandidate = Join-Path (Get-Location).Path $ResolvedSpec
    if (Test-Path -LiteralPath $cwdCandidate) {
        $ResolvedSpec = $cwdCandidate
    } else {
        $rootCandidate = Join-Path $Root $ResolvedSpec
        if (Test-Path -LiteralPath $rootCandidate) {
            $ResolvedSpec = $rootCandidate
        }
    }
}

if (-not (Test-Path -LiteralPath $ResolvedSpec)) {
    throw "Spec file not found: $SpecFile (resolved: $ResolvedSpec). Run from project root, e.g. powershell -ExecutionPolicy Bypass -File .\engine\Estimate-Print.ps1 -SpecFile <path> -AsJson"
}

$MaterialsPath = Join-Path $Root "knowledge/materials.json"
$Density = 1.24 # fallback when knowledge base / material unknown
$DensityNote = "FALLBACK: materials.json lookup failed; 1.24 g/cm3 (PLA) assumed - NEEDS_INPUT for other materials"
$MaterialName = $MaterialId.ToUpper()
$MaterialKnown = $false
$CostEst = $null
$CostNote = "UNKNOWN: Price per kg not specified (NEEDS_INPUT). No cost fabricated."

if (Test-Path $MaterialsPath) {
    $Materials = Get-Content -Raw -Path $MaterialsPath -Encoding UTF8 | ConvertFrom-Json
    $MatInfo = $null
    foreach ($m in $Materials) {
        if ($m.id -eq $MaterialId -or $m.name -match $MaterialId) {
            $MatInfo = $m
            break
        }
    }
    if ($MatInfo) {
        if ($MatInfo.density_g_cm3) { $Density = [double]$MatInfo.density_g_cm3; $DensityNote = "KNOWN: density from knowledge/materials.json" }
        if ($MatInfo.name) { $MaterialName = $MatInfo.name }
        $MaterialKnown = $true
    } else {
        $MaterialName = $MaterialId
    }
}

# Deterministic bbox volume from spec geometry (mm -> cm3). No fake constants.
# Sums per-component bbox w*d*h; falls back to diameter_mm when width/depth/height missing.
$Spec = Get-Content -Raw -Path $ResolvedSpec -Encoding UTF8 | ConvertFrom-Json
$VolumeBboxMm3 = 0.0
$VolumeKnown = $false
if ($null -ne $Spec.components) {
    foreach ($comp in $Spec.components) {
        if ($null -eq $comp.base) { continue }
        $w = if ($comp.base.width_mm) { [double]$comp.base.width_mm } elseif ($comp.base.diameter_mm) { [double]$comp.base.diameter_mm } else { 0.0 }
        $d = if ($comp.base.depth_mm) { [double]$comp.base.depth_mm } elseif ($comp.base.diameter_mm) { [double]$comp.base.diameter_mm } else { 0.0 }
        $h = if ($comp.base.height_mm) { [double]$comp.base.height_mm } elseif ($comp.base.diameter_mm) { [double]$comp.base.diameter_mm } else { 0.0 }
        if ($w -gt 0 -and $d -gt 0 -and $h -gt 0) {
            $VolumeBboxMm3 += ($w * $d * $h)
            $VolumeKnown = $true
        }
    }
}
if ($VolumeKnown) {
    $VolumeCm3 = $VolumeBboxMm3 / 1000.0
} else {
    $VolumeCm3 = 0.0
}

$VolumeEstCm3 = $VolumeCm3 * ($InfillPct / 100.0)
$WeightEstG = $VolumeEstCm3 * $Density
# Filament length assumes 1.75 mm filament (area ~= 2.405 mm2): length_m = volume_cm3 / 2.405. ESTIMATE only.
$FilamentLengthM = ($WeightEstG / $Density) / 2.405

if (-not $VolumeKnown) {
    $VolumeEstCm3 = 0.0
    $WeightEstG = 0.0
    $FilamentLengthM = 0.0
}

if ($PricePerKg -gt 0 -and $WeightEstG -gt 0) {
    $CostEst = ($WeightEstG / 1000.0) * $PricePerKg
    $CostNote = "ESTIMATE from weight and supplied price"
}

$VolumeNote = "ESTIMATE: sum of component bbox volumes * infill fraction; NOT a slicer measurement"
if (-not $VolumeKnown) { $VolumeNote = "UNKNOWN: no usable width/depth/height or diameter_mm in spec (NEEDS_INPUT)" }
$WeightNote = "ESTIMATE based on approximate bbox volume and material density"
if (-not $VolumeKnown) { $WeightNote = "UNKNOWN: volume unknown (NEEDS_INPUT)" }
$LengthNote = "ESTIMATE assuming 1.75 mm filament"
if (-not $VolumeKnown) { $LengthNote = "UNKNOWN: volume unknown (NEEDS_INPUT)" }

$Result = @{
    status = "ESTIMATE"
    method = "deterministic bbox approximation; no slicer, no printer required"
    material = $MaterialName
    material_known = $MaterialKnown
    density_g_cm3 = $Density
    density_note = $DensityNote
    volume_bbox_cm3 = [Math]::Round($VolumeCm3, 3)
    volume_estimated_cm3 = [Math]::Round($VolumeEstCm3, 3)
    volume_note = $VolumeNote
    weight_estimated_g = [Math]::Round($WeightEstG, 3)
    weight_note = $WeightNote
    filament_length_estimated_m = [Math]::Round($FilamentLengthM, 3)
    filament_length_note = $LengthNote
    cost_estimated = $CostEst
    cost_note = $CostNote
    print_time = "ESTIMATE_UNAVAILABLE"
    print_time_note = "UNKNOWN: nozzle/speed/flow not supplied and never fabricated; slicer required"
    print_speed_note = "UNKNOWN: no speed fabricated (NEEDS_INPUT)"
    infill_pct = $InfillPct
}

if ($AsJson) {
    # NOTE: No -EscapeHandling flag for Windows PowerShell 5.1 compat (flag exists only on PS 6+/7).
    $Result | ConvertTo-Json -Depth 5 -Compress
} else {
    $Result
}
