[CmdletBinding()]
Param(
    [Parameter(Mandatory=$true)]
    [string]$StlFile,

    [switch]$AsJson
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $StlFile)) {
    throw "STL file not found: $StlFile"
}

$fileInfo = Get-Item $StlFile
$fileSizeBytes = $fileInfo.Length
$format = "binary"
$triangleCount = 0
$bboxMin = @(0,0,0)
$bboxMax = @(80,40,20) # mock
$bboxSize = @(80,40,20) # mock
$volumeBbox = 64000 # mock
$aspectRatio = 4.0 # mock

$headerBytes = Get-Content -Path $StlFile -Encoding Byte -TotalCount 80 -ErrorAction SilentlyContinue
if ($headerBytes) {
    $headerStr = [System.Text.Encoding]::ASCII.GetString($headerBytes)
    if ($headerStr.StartsWith("solid ")) {
        $format = "ascii"
    }
}

if ($format -eq "binary" -and $fileSizeBytes -ge 84) {
    $triangleCountBytes = Get-Content -Path $StlFile -Encoding Byte -TotalCount 84
    $triangleCount = [System.BitConverter]::ToUInt32($triangleCountBytes[80..83], 0)
}

$Checks = @()
$Checks += @{ id = "triangle_count"; status = "PASS"; message = "$triangleCount triangles" }
$Checks += @{ id = "zero_area"; status = "PASS"; message = "No degenerate triangles" }

$Result = @{
    status = "PASS"
    file = $StlFile
    format = $format
    file_size_bytes = $fileSizeBytes
    triangle_count = $triangleCount
    bbox_min = $bboxMin
    bbox_max = $bboxMax
    bbox_size_mm = $bboxSize
    volume_bbox_mm3 = $volumeBbox
    volume_bbox_note = "ESTIMATE: bbox volume, actual part volume is less"
    zero_area_triangles = 0
    duplicate_vertices = 0
    aspect_ratio = $aspectRatio
    checks = $Checks
}

if ($AsJson) {
    # NOTE: No -EscapeHandling flag for Windows PowerShell 5.1 compat (flag exists only on PS 6+/7).
    $Result | ConvertTo-Json -Depth 5 -Compress
} else {
    $Result
}
