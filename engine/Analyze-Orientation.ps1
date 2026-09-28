[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$SpecFile,

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
    throw "Spec file not found: $SpecFile (resolved: $ResolvedSpec). Run from project root, e.g. powershell -ExecutionPolicy Bypass -File .\engine\Analyze-Orientation.ps1 -SpecFile <path> -AsJson"
}

$Spec = Get-Content -Raw -Path $ResolvedSpec -Encoding UTF8 | ConvertFrom-Json

$Results = @()

$components = @()
if ($null -ne $Spec.components) { $components = @($Spec.components) }

foreach ($comp in $components) {
    $w = 0.0; $d = 0.0; $h = 0.0
    if ($null -ne $comp.base) {
        $w = if ($comp.base.width_mm) { [double]$comp.base.width_mm } elseif ($comp.base.diameter_mm) { [double]$comp.base.diameter_mm } else { 0.0 }
        $d = if ($comp.base.depth_mm) { [double]$comp.base.depth_mm } elseif ($comp.base.diameter_mm) { [double]$comp.base.diameter_mm } else { 0.0 }
        $h = if ($comp.base.height_mm) { [double]$comp.base.height_mm } elseif ($comp.base.diameter_mm) { [double]$comp.base.diameter_mm } else { 0.0 }
    }
    $compId = if ($comp.id) { $comp.id } else { "UNKNOWN" }

    $orientations = @()

    # Orientation A: Current (Z up) - deterministic heuristic: largest-face-down proxy.
    $orientations += @{
        name = "Orientation A (Default)"
        description = "Largest face down (current orientation)"
        bed_contact_area_mm2 = [Math]::Round($w * $d, 3)
        support_estimate = "low"
        support_note = "HEURISTIC from bbox faces; no slicer measurement, no printer constraints invented"
        layer_strength_direction = "Z"
        critical_dimensions_in_xy = "Width, Depth"
        print_height_mm = $h
        surface_quality_notes = "Top surface may have layer lines"
    }

    # Orientation B: Rotated 90 around X (Y up)
    $orientations += @{
        name = "Orientation B"
        description = "Rotated 90 deg around X (front face down)"
        bed_contact_area_mm2 = [Math]::Round($w * $h, 3)
        support_estimate = "medium"
        support_note = "HEURISTIC from bbox faces; no slicer measurement, no printer constraints invented"
        layer_strength_direction = "Y"
        critical_dimensions_in_xy = "Width, Height"
        print_height_mm = $d
        surface_quality_notes = "Front face will have good bed adhesion"
    }

    # Orientation C: Rotated 90 around Y (X up)
    $orientations += @{
        name = "Orientation C"
        description = "Rotated 90 deg around Y (side face down)"
        bed_contact_area_mm2 = [Math]::Round($d * $h, 3)
        support_estimate = "medium"
        support_note = "HEURISTIC from bbox faces; no slicer measurement, no printer constraints invented"
        layer_strength_direction = "X"
        critical_dimensions_in_xy = "Depth, Height"
        print_height_mm = $w
        surface_quality_notes = "Side face will have good bed adhesion"
    }

    # Deterministic recommendation: largest bed-contact area wins; ties prefer A, then B, then C.
    $maxArea = ($orientations | ForEach-Object { [double]$_.bed_contact_area_mm2 } | Measure-Object -Maximum).Maximum
    $recommended = "Orientation A (Default)"
    if (([double]$orientations[1].bed_contact_area_mm2) -eq $maxArea -and ([double]$orientations[0].bed_contact_area_mm2) -ne $maxArea) {
        $recommended = "Orientation B"
    } elseif (([double]$orientations[2].bed_contact_area_mm2) -eq $maxArea -and ([double]$orientations[0].bed_contact_area_mm2) -ne $maxArea -and ([double]$orientations[1].bed_contact_area_mm2) -ne $maxArea) {
        $recommended = "Orientation C"
    }

    $Results += @{
        component_id = $compId
        method = "deterministic bbox-face heuristic; no printer required, no printer limits invented"
        recommended = $recommended
        orientations = $orientations
    }
}

if ($AsJson) {
    # NOTE: No -EscapeHandling flag for Windows PowerShell 5.1 compat (flag exists only on PS 6+/7).
    $Results | ConvertTo-Json -Depth 5 -Compress
} else {
    $Results
}
