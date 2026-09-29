[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$SpecFile,

    [Parameter(Mandatory=$false)]
    [string]$PrinterFile,

    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

# Resolve SpecFile / PrinterFile robustly: absolute, CWD-relative, then project-root-relative.
function Resolve-ProjectPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    $cwdCandidate = Join-Path (Get-Location).Path $Path
    if (Test-Path -LiteralPath $cwdCandidate) { return $cwdCandidate }
    $rootCandidate = Join-Path $Root $Path
    if (Test-Path -LiteralPath $rootCandidate) { return $rootCandidate }
    return $Path
}

$SpecFile = Resolve-ProjectPath $SpecFile
if ($PrinterFile) { $PrinterFile = Resolve-ProjectPath $PrinterFile }

if (-not (Test-Path -LiteralPath $SpecFile)) {
    throw "Spec file not found: $SpecFile. Run from project root, e.g. powershell -ExecutionPolicy Bypass -File .\engine\Analyze-Printability.ps1 -SpecFile <path> -AsJson"
}

$Spec = Get-Content -Raw -Path $SpecFile -Encoding UTF8 | ConvertFrom-Json

$Printer = $null
if ($PrinterFile -and (Test-Path -LiteralPath $PrinterFile)) {
    $Printer = Get-Content -Raw -Path $PrinterFile -Encoding UTF8 | ConvertFrom-Json
}

$Checks = @()
$Summary = @{ pass = 0; warning = 0; needs_input = 0; blocked = 0; fail = 0 }
$GlobalStatus = "PASS"

function Add-Check {
    param($Id, $Status, $Message, $Value = $null, $Limit = $null, $Component = "", $Requirement = "", $Severity = "")
    $Check = @{ id = $Id; status = $Status; message = $Message }
    if ($null -ne $Value) { $Check.value = [double]$Value }
    if ($null -ne $Limit) { $Check.limit = [double]$Limit }
    if ([string]$Component -ne "") { $Check.component = [string]$Component }
    if ([string]$Requirement -ne "") { $Check.requirement_source = [string]$Requirement }
    if ([string]$Severity -ne "") { $Check.severity = [string]$Severity }
    
    $script:Checks += $Check

    # Use ToLowerInvariant: tr-TR locale turns "NEEDS_INPUT"/"WARNING" into dotless-i keys otherwise.
    $key = $Status.ToLowerInvariant()
    if ($Summary.ContainsKey($key)) { $Summary[$key]++ } else { $Summary[$key] = 1 }
    
    if ($Status -eq "BLOCKED") { $script:GlobalStatus = "BLOCKED" }
    elseif ($Status -eq "FAIL" -and $script:GlobalStatus -ne "BLOCKED") { $script:GlobalStatus = "FAIL" }
    elseif ($Status -eq "NEEDS_INPUT" -and $script:GlobalStatus -notmatch "BLOCKED|FAIL") { $script:GlobalStatus = "NEEDS_INPUT" }
    elseif ($Status -eq "WARNING" -and $script:GlobalStatus -notmatch "BLOCKED|FAIL|NEEDS_INPUT") { $script:GlobalStatus = "WARNING" }
}

# 1. min_wall (konum: bilesen bazinda; gereksinim kaynagi belirtilir)
$hollowComps = @()
$hasHollow = $false
$minWallMm = $null
foreach ($comp in $Spec.components) {
    if ($comp.hollow) {
        $hollowComps += $comp
        $hasHollow = $true
        if ($null -eq $minWallMm -or $comp.hollow.wall_mm -lt $minWallMm) {
            $minWallMm = $comp.hollow.wall_mm
        }
    }
}
if ($hollowComps.Count -eq 0) {
    Add-Check -Id "min_wall" -Status "PASS" -Message "No hollow components found"
} else {
    foreach ($comp in $hollowComps) {
        $cid = [string]$comp.id
        $minWallMm = $comp.hollow.wall_mm
        $reqSrc = "none"
        if ($null -ne $Printer) { $reqSrc = [string]$Printer.id }
        if ($null -eq $Printer) {
            Add-Check -Id "min_wall" -Status "NEEDS_INPUT" -Message "Printer profile required for wall check ($cid wall ${minWallMm}mm, uncompared)" -Value $minWallMm -Component $cid -Requirement $reqSrc
        } else {
            $pMinWall = $Printer.min_wall_mm
            if ($null -ne $pMinWall) {
                if ($minWallMm -ge $pMinWall) {
                    Add-Check -Id "min_wall" -Status "PASS" -Message "Wall $($minWallMm.ToString([cultureinfo]::InvariantCulture))mm >= min $($pMinWall.ToString([cultureinfo]::InvariantCulture))mm ($cid)" -Value $minWallMm -Limit $pMinWall -Component $cid -Requirement $reqSrc
                } else {
                    Add-Check -Id "min_wall" -Status "WARNING" -Message "Wall $($minWallMm.ToString([cultureinfo]::InvariantCulture))mm < min $($pMinWall.ToString([cultureinfo]::InvariantCulture))mm ($cid)" -Value $minWallMm -Limit $pMinWall -Component $cid -Requirement $reqSrc
                }
            } else {
                Add-Check -Id "min_wall" -Status "NEEDS_INPUT" -Message "Printer profile missing min_wall_mm ($cid wall ${minWallMm}mm, uncompared)" -Value $minWallMm -Component $cid -Requirement $reqSrc
            }
        }
    }
}

# 2. hole_size (tip/eksen/tolerans bilgisiyle; gereksinim kaynagi belirtilir)
$hasHoles = $false
$minHoleMm = $null
$holeDescs = New-Object System.Collections.Generic.List[string]
foreach ($comp in $Spec.components) {
    if ($comp.holes) {
        $hasHoles = $true
        foreach ($hole in $comp.holes) {
            if ($null -eq $minHoleMm -or $hole.diameter_mm -lt $minHoleMm) {
                $minHoleMm = $hole.diameter_mm
            }
            $ht = "through"; if ($hole.hole_type) { $ht = [string]$hole.hole_type }
            $ax = "z"; if ($hole.axis) { $ax = [string]$hole.axis }
            $holeDescs.Add(([string]$hole.id + ":" + [string]$hole.diameter_mm + "mm/" + $ht + "/" + $ax)) | Out-Null
        }
    }
}
$tolNote = "tolerans yok"
$tolVals = New-Object System.Collections.Generic.List[string]
foreach ($comp in $Spec.components) {
    if ($null -ne $comp.tolerance -and $null -ne $comp.tolerance.clearance_mm) {
        $tolVals.Add(([string]$comp.id + ":" + [string]$comp.tolerance.clearance_mm + "mm")) | Out-Null
    }
}
if ($tolVals.Count -gt 0) { $tolNote = ("clearance " + ($tolVals -join ", ")) }

if ($hasHoles) {
    $reqSrc = "none"
    if ($null -ne $Printer) { $reqSrc = [string]$Printer.id }
    if ($null -eq $Printer) {
        Add-Check -Id "hole_size" -Status "NEEDS_INPUT" -Message ("Printer profile required for hole size check (" + ($holeDescs -join ", ") + "; " + $tolNote + ")") -Requirement $reqSrc
    } else {
        $pMinHole = $Printer.min_hole_mm
        if ($null -ne $pMinHole) {
            if ($minHoleMm -ge $pMinHole) {
                Add-Check -Id "hole_size" -Status "PASS" -Message ("Hole $($minHoleMm.ToString([cultureinfo]::InvariantCulture))mm >= min $($pMinHole.ToString([cultureinfo]::InvariantCulture))mm (" + ($holeDescs -join ", ") + "; " + $tolNote + ")") -Value $minHoleMm -Limit $pMinHole -Requirement $reqSrc
            } else {
                Add-Check -Id "hole_size" -Status "WARNING" -Message ("Hole $($minHoleMm.ToString([cultureinfo]::InvariantCulture))mm < min $($pMinHole.ToString([cultureinfo]::InvariantCulture))mm (" + ($holeDescs -join ", ") + "; " + $tolNote + ")") -Value $minHoleMm -Limit $pMinHole -Requirement $reqSrc
            }
        } else {
            Add-Check -Id "hole_size" -Status "NEEDS_INPUT" -Message ("Printer profile missing min_hole_mm (" + ($holeDescs -join ", ") + ")") -Requirement $reqSrc
        }
    }
}

# 3. overhang_estimate (aday bolgeler; yazici davranisi iddia edilmez)
$hasOverhangRisk = $false
$overhangLocs = New-Object System.Collections.Generic.List[string]
foreach ($comp in $Spec.components) {
    if ($comp.base.shape -eq "cylinder") {
        foreach ($t in $comp.transforms) {
            if ($t.type -eq "rotate" -and ($t.axis -eq "x" -or $t.axis -eq "y") -and $t.angle_deg -ne 0 -and $t.angle_deg -ne 180) {
                $hasOverhangRisk = $true
                $overhangLocs.Add(([string]$comp.id + ": rotated cylinder")) | Out-Null
            }
        }
    }
    foreach ($h in @($comp.holes)) {
        if ($h -and $h.axis -and [string]$h.axis -ne "z") {
            $hasOverhangRisk = $true
            $overhangLocs.Add(([string]$comp.id + "." + [string]$h.id + ": axis " + [string]$h.axis)) | Out-Null
        }
    }
}
if ($hasOverhangRisk) {
    Add-Check -Id "overhang_estimate" -Status "WARNING" -Message ("Overhang candidates: " + ($overhangLocs -join "; ") + " (candidate regions only; printer behavior unknown without profile)") -Severity "medium"
} else {
    Add-Check -Id "overhang_estimate" -Status "PASS" -Message "Low overhang risk" -Severity "low"
}

# 4. bed_contact
$bedContactRisk = $false
foreach ($comp in $Spec.components) {
    if ($comp.base.shape -eq "sphere") {
        $bedContactRisk = $true
    }
}
if ($bedContactRisk) {
    Add-Check -Id "bed_contact" -Status "WARNING" -Message "Sphere shape detected, poor bed contact"
} else {
    Add-Check -Id "bed_contact" -Status "PASS" -Message "Good bed contact (box/cylinder-z)"
}

# 5. first_layer_risk
if ($hasHollow -and $minWallMm -lt 2) {
    Add-Check -Id "first_layer_risk" -Status "WARNING" -Message "Thin walls on hollow model, potential first layer adhesion risk"
} else {
    Add-Check -Id "first_layer_risk" -Status "PASS" -Message "First layer risk low"
}

# 6. elephant_foot_risk
Add-Check -Id "elephant_foot_risk" -Status "WARNING" -Message "Always present for FDM"

# 7. warping_risk
if ($Spec.material) {
    $mat = $Spec.material.ToLowerInvariant()
    if ($mat -in @("abs", "asa", "nylon")) {
        Add-Check -Id "warping_risk" -Status "WARNING" -Message "High warping risk for $mat"
    } elseif ($mat -eq "petg") {
        Add-Check -Id "warping_risk" -Status "PASS" -Message "Medium warping risk for $mat"
    } else {
        Add-Check -Id "warping_risk" -Status "PASS" -Message "Low warping risk for $mat"
    }
} else {
    Add-Check -Id "warping_risk" -Status "NEEDS_INPUT" -Message "Material not specified"
}

# 8. thin_walls
$hasThinWall = $false
if ($hasHollow -and $minWallMm -lt 1.2) { $hasThinWall = $true }
if ($hasThinWall) {
    Add-Check -Id "thin_walls" -Status "WARNING" -Message "Wall thickness < 1.2mm detected"
} else {
    Add-Check -Id "thin_walls" -Status "PASS" -Message "No excessively thin walls detected"
}

# 9. tolerance_check
if ($Spec.tolerance) {
    $clearance = $Spec.tolerance.clearance_mm
    if ($null -ne $clearance) {
        if ($clearance -gt 0 -and $clearance -lt 5) {
            Add-Check -Id "tolerance_check" -Status "PASS" -Message "Reasonable clearance: $($clearance.ToString([cultureinfo]::InvariantCulture))mm" -Value $clearance
        } else {
            Add-Check -Id "tolerance_check" -Status "WARNING" -Message "Clearance $($clearance.ToString([cultureinfo]::InvariantCulture))mm out of reasonable range (>0, <5mm)" -Value $clearance
        }
    }
}

# 10. bridging_risk (aciklik + bolme acikligi; surec bagimliligi belirtilir)
$bridgingRisk = $false
$bridgeSpans = New-Object System.Collections.Generic.List[string]
foreach ($comp in $Spec.components) {
    if ($comp.hollow -and $comp.hollow.open_top -and $comp.base.width_mm -gt 15) {
        $bridgingRisk = $true
        $bridgeSpans.Add(([string]$comp.id + ": open width " + [string]$comp.base.width_mm + "mm")) | Out-Null
    }
    if ($null -ne $comp.divider_pattern -and $null -ne $comp.base -and $null -ne $comp.base.depth_mm -and $null -ne $comp.hollow -and $null -ne $comp.hollow.wall_mm) {
        $span = [double]$comp.base.depth_mm - 2 * [double]$comp.hollow.wall_mm
        if ($span -gt 10) {
            $bridgingRisk = $true
            $bridgeSpans.Add(([string]$comp.id + ": divider span " + [string]$span + "mm (material/cooling dependent)")) | Out-Null
        }
    }
}
if ($bridgingRisk) {
    Add-Check -Id "bridging_risk" -Status "WARNING" -Message ("Bridge candidates: " + ($bridgeSpans -join "; ")) -Severity "medium"
} else {
    Add-Check -Id "bridging_risk" -Status "PASS" -Message "No significant bridging risk" -Severity "low"
}

# 11. support_estimate (geometriden ayri; geometriyi degistirmez)
if ($hasOverhangRisk) {
    Add-Check -Id "support_estimate" -Status "WARNING" -Message "Supports likely required due to overhangs (settings separate from geometry)" -Severity "medium"
} else {
    Add-Check -Id "support_estimate" -Status "PASS" -Message "Supports likely not required" -Severity "low"
}

# 12. bed_size_check (accepts bed_size_mm or legacy bed_mm; never invents printer limits)
$BedDims = $null
if ($null -ne $Printer) {
    if ($Printer.bed_size_mm) { $BedDims = $Printer.bed_size_mm }
    elseif ($Printer.bed_mm) { $BedDims = $Printer.bed_mm }
}
if ($null -eq $Printer) {
    Add-Check -Id "bed_size_check" -Status "NEEDS_INPUT" -Message "Printer profile required for bed size check"
} elseif ($BedDims -and @($BedDims).Count -ge 2) {
    $maxWidth = 0; $maxDepth = 0
    foreach ($comp in $Spec.components) {
        if ($null -eq $comp.base) { continue }
        $w = if ($comp.base.width_mm) { $comp.base.width_mm } elseif ($comp.base.diameter_mm) { $comp.base.diameter_mm } else { 0 }
        $d = if ($comp.base.depth_mm) { $comp.base.depth_mm } elseif ($comp.base.diameter_mm) { $comp.base.diameter_mm } else { 0 }
        if ($w -gt $maxWidth) { $maxWidth = $w }
        if ($d -gt $maxDepth) { $maxDepth = $d }
    }
    $bedX = [double]$BedDims[0]
    $bedY = [double]$BedDims[1]
    if ($maxWidth -le $bedX -and $maxDepth -le $bedY) {
        Add-Check -Id "bed_size_check" -Status "PASS" -Message "Component fits within bed size"
    } else {
        Add-Check -Id "bed_size_check" -Status "WARNING" -Message "Component may exceed bed size"
    }
} else {
    Add-Check -Id "bed_size_check" -Status "NEEDS_INPUT" -Message "Printer profile missing bed_size_mm/bed_mm"
}

$Result = @{
    status = $GlobalStatus
    method = "deterministic spec-based heuristic; no full STL mesh scan, no slicer, no printer required"
    analysis_scope = "wall/hole limits vs printer profile when supplied; overhang/support/bed-contact/thin-wall/small-feature/bridging heuristics from spec shapes and transforms; UNKNOWN reported as NEEDS_INPUT, never fabricated"
    printer = if ($Printer) { $Printer.id } else { "NONE" }
    checks = $Checks
    summary = $Summary
}

if ($AsJson) {
    # NOTE: No -EscapeHandling flag for Windows PowerShell 5.1 compat (flag exists only on PS 6+/7).
    $Result | ConvertTo-Json -Depth 5 -Compress
} else {
    $Result
}
