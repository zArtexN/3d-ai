[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$InputFile,

    [Parameter(Mandatory=$true)]
    [string]$PrinterProfile,

    [Parameter(Mandatory=$true)]
    [string]$OutputDir,

    [Parameter(Mandatory=$false)]
    [string]$OrcaSlicerExe,

    [Parameter(Mandatory=$false)]
    [int]$Timeout = 300,

    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $InputFile)) {
    throw "Input file not found: $InputFile"
}

$ResolvedExe = $OrcaSlicerExe
if (-not $ResolvedExe) {
    $ResolveScript = Join-Path $Root "scripts/Resolve-OrcaSlicer.ps1"
    if (Test-Path $ResolveScript) {
        $ResolvedExe = & $ResolveScript
    }
}

if (-not $ResolvedExe -or -not (Test-Path $ResolvedExe)) {
    $Result = @{
        status = "BLOCKED"
        reason = "OrcaSlicer bulunamadi"
        slicer_exe = $null
        printer_profile = $PrinterProfile
        input_file = $InputFile
        output_dir = $OutputDir
        prepared_command = $null
        gcode_file = $null
        gcode_note = "FAKE G-CODE URETILMEZ"
    }
    if ($AsJson) { return $Result | ConvertTo-Json -Depth 5 -Compress } else { return $Result }
}

$ProfilePath = Join-Path $Root "printers/$PrinterProfile.json"
if (-not (Test-Path $ProfilePath)) {
    $Result = @{
        status = "BLOCKED"
        reason = "Slicing için printer profile gerekiyor"
        slicer_exe = $ResolvedExe
        printer_profile = $PrinterProfile
        input_file = $InputFile
        output_dir = $OutputDir
        prepared_command = $null
        gcode_file = $null
        gcode_note = "FAKE G-CODE URETILMEZ"
    }
    if ($AsJson) { return $Result | ConvertTo-Json -Depth 5 -Compress } else { return $Result }
}

$ProfileData = Get-Content -Raw -Path $ProfilePath -Encoding UTF8 | ConvertFrom-Json
if (-not $ProfileData.orca_profiles -or $ProfileData.orca_profiles -match "REPLACE_WITH") {
    $Result = @{
        status = "BLOCKED"
        reason = "Slicing için printer profile gerekiyor"
        slicer_exe = $ResolvedExe
        printer_profile = $PrinterProfile
        input_file = $InputFile
        output_dir = $OutputDir
        prepared_command = $null
        gcode_file = $null
        gcode_note = "FAKE G-CODE URETILMEZ"
    }
    if ($AsJson) { return $Result | ConvertTo-Json -Depth 5 -Compress } else { return $Result }
}

$Command = "& `"$ResolvedExe`" --slice `"$InputFile`" --output `"$OutputDir`""

$Result = @{
    status = "READY"
    reason = $null
    slicer_exe = $ResolvedExe
    printer_profile = $PrinterProfile
    input_file = $InputFile
    output_dir = $OutputDir
    prepared_command = $Command
    gcode_file = $null
    gcode_note = "FAKE G-CODE URETILMEZ"
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 5 -Compress
} else {
    $Result
}
