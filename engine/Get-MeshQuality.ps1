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
$format = "unknown"
$facets = New-Object System.Collections.Generic.List[object]

$bytes = [System.IO.File]::ReadAllBytes($StlFile)
$head = ""
if ($fileSizeBytes -gt 0) {
    $head = [System.Text.Encoding]::ASCII.GetString($bytes, 0, [math]::Min(512, $fileSizeBytes))
}
if ($head.StartsWith("solid")) {
    $hasFacet = $false
    foreach ($l in [System.IO.File]::ReadLines($StlFile)) { if ($l.Trim().StartsWith("facet")) { $hasFacet = $true; break } }
    if ($hasFacet) {
        $format = "ascii"
        $nv = $null; $vs = New-Object System.Collections.Generic.List[object]
        foreach ($l in [System.IO.File]::ReadLines($StlFile)) {
            $t = $l.Trim()
            if ($t.StartsWith("facet normal")) {
                $p = $t.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($p.Count -ge 5) { $nv = @([double]$p[2], [double]$p[3], [double]$p[4]) }
                $vs = New-Object System.Collections.Generic.List[object]
            } elseif ($t.StartsWith("vertex")) {
                $p = $t.Split(" ", [System.StringSplitOptions]::RemoveEmptyEntries)
                if ($p.Count -ge 4) { $vs.Add(@([double]$p[1], [double]$p[2], [double]$p[3])) | Out-Null }
            } elseif ($t.StartsWith("endfacet")) {
                if ($null -ne $nv -and $vs.Count -eq 3) {
                    $facets.Add([pscustomobject]@{ n = $nv; v = @($vs.ToArray()) }) | Out-Null
                }
                $nv = $null
            }
        }
    }
}
if ($format -eq "unknown" -and $fileSizeBytes -ge 84) {
    $n = [System.BitConverter]::ToUInt32($bytes, 80)
    if ($fileSizeBytes -eq (84 + 50 * $n)) {
        $format = "binary"
        for ($i = 0; $i -lt $n; $i++) {
            $base = 84 + 50 * $i
            $nv = @([System.BitConverter]::ToSingle($bytes, $base), [System.BitConverter]::ToSingle($bytes, ($base + 4)), [System.BitConverter]::ToSingle($bytes, ($base + 8)))
            $vs = @()
            for ($v = 0; $v -lt 3; $v++) {
                $o = $base + 12 + 12 * $v
                $vs += ,@([System.BitConverter]::ToSingle($bytes, $o), [System.BitConverter]::ToSingle($bytes, ($o + 4)), [System.BitConverter]::ToSingle($bytes, ($o + 8)))
            }
            $facets.Add([pscustomobject]@{ n = $nv; v = $vs }) | Out-Null
        }
    }
}
if ($format -eq "unknown") { throw "VERIFY: FAIL - STL formati taninamadi: $StlFile" }

function VKey($v) {
    return ([math]::Round([double]$v[0], 4).ToString() + "," + [math]::Round([double]$v[1], 4).ToString() + "," + [math]::Round([double]$v[2], 4).ToString())
}
function VSub($a, $b) { return @(([double]$a[0] - [double]$b[0]), ([double]$a[1] - [double]$b[1]), ([double]$a[2] - [double]$b[2])) }
function VCross($a, $b) {
    return @(([double]$a[1] * [double]$b[2] - [double]$a[2] * [double]$b[1]),
             ([double]$a[2] * [double]$b[0] - [double]$a[0] * [double]$b[2]),
             ([double]$a[0] * [double]$b[1] - [double]$a[1] * [double]$b[0]))
}
function VLen($a) { return [math]::Sqrt([double]$a[0] * [double]$a[0] + [double]$a[1] * [double]$a[1] + [double]$a[2] * [double]$a[2]) }
function VDot($a, $b) { return ([double]$a[0] * [double]$b[0] + [double]$a[1] * [double]$b[1] + [double]$a[2] * [double]$b[2]) }

$triCount = $facets.Count
$bmin = @([double]::MaxValue, [double]::MaxValue, [double]::MaxValue)
$bmax = @([double]::MinValue, [double]::MinValue, [double]::MinValue)
$zeroArea = 0
$nanCount = 0
$degenNormals = 0
$dupVerts = 0
$vol6 = 0.0
$seen = @{}
$edgeUse = @{}
$parent = @{}
function Find-Root($x) {
    while ($parent[$x] -ne $x) { $parent[$x] = $parent[$parent[$x]]; $x = $parent[$x] }
    return $x
}
foreach ($f in $facets) {
    $vv = @($f.v)
    $nn = @($f.n)
    $badNum = $false
    foreach ($c in (@($vv[0]) + @($vv[1]) + @($vv[2]) + @($nn))) {
        if ([double]::IsNaN([double]$c) -or [double]::IsInfinity([double]$c)) { $badNum = $true }
    }
    if ($badNum) { $nanCount++ }
    foreach ($v in $vv) {
        for ($k = 0; $k -lt 3; $k++) {
            if ($v[$k] -lt $bmin[$k]) { $bmin[$k] = $v[$k] }
            if ($v[$k] -gt $bmax[$k]) { $bmax[$k] = $v[$k] }
        }
        $key = VKey $v
        if ($seen.ContainsKey($key)) { $dupVerts++ } else { $seen[$key] = $true }
        if (-not $parent.ContainsKey($key)) { $parent[$key] = $key }
    }
    $e1 = VSub $vv[1] $vv[0]
    $e2 = VSub $vv[2] $vv[0]
    $cr = VCross $e1 $e2
    $area2 = VDot $cr $cr
    if ($area2 -lt 1e-12) { $zeroArea++ }
    if ((VLen $nn) -lt 1e-9) { $degenNormals++ }
    $vol6 += (VDot $vv[0] $cr)
    $ks = @((VKey $vv[0]), (VKey $vv[1]), (VKey $vv[2]))
    $pairs = @(@($ks[0], $ks[1]), @($ks[1], $ks[2]), @($ks[2], $ks[0]))
    foreach ($pr in $pairs) {
        $a = $pr[0]; $b = $pr[1]
        if ([string]::Compare($a, $b) -gt 0) { $tmp = $a; $a = $b; $b = $tmp }
        $ek = ($a + "|" + $b)
        if ($edgeUse.ContainsKey($ek)) { $edgeUse[$ek] = [int]$edgeUse[$ek] + 1 } else { $edgeUse[$ek] = 1 }
        $ra = Find-Root $a; $rb = Find-Root $b
        if ($ra -ne $rb) { $parent[$ra] = $rb }
    }
}
$nonmanifold = 0
foreach ($k in $edgeUse.Keys) { if ([int]$edgeUse[$k] -ne 2) { $nonmanifold++ } }
$compRoots = @{}
foreach ($k in @($parent.Keys)) { $r = Find-Root $k; $compRoots[$r] = $true }
$components = $compRoots.Count
if ($triCount -eq 0) { $components = 0 }
$volume = [math]::Abs($vol6 / 6.0)
$bboxSize = @(([math]::Round($bmax[0] - $bmin[0], 4)), ([math]::Round($bmax[1] - $bmin[1], 4)), ([math]::Round($bmax[2] - $bmin[2], 4)))
$watertight = ($triCount -gt 0 -and $nonmanifold -eq 0 -and $nanCount -eq 0)

$failList = New-Object System.Collections.Generic.List[string]
if ($triCount -eq 0) { $failList.Add("mesh bos: facet sayisi 0") | Out-Null }
if ($nanCount -gt 0) { $failList.Add("NaN/Infinity koordinat: $nanCount facet") | Out-Null }
if ($zeroArea -gt 0) { $failList.Add("sifir-alanli ucgen: $zeroArea") | Out-Null }
if ($degenNormals -gt 0) { $failList.Add("gecersiz normal: $degenNormals") | Out-Null }
if ($nonmanifold -gt 0) { $failList.Add("manifold-olmayan kenar: $nonmanifold") | Out-Null }
if ($volume -le 0 -and $triCount -gt 0) { $failList.Add("hacim sifir/negatif") | Out-Null }

$status = "PASS"
if ($failList.Count -gt 0) { $status = "FAIL" }

$Checks = @()
$Checks += @{ id = "triangle_count"; status = "PASS"; message = "$triCount triangles" }
$zcStat = "PASS"; if ($zeroArea -gt 0) { $zcStat = "FAIL" }
$Checks += @{ id = "zero_area"; status = $zcStat; message = "$zeroArea degenerate triangles" }
$wtStat = "PASS"; if (-not $watertight) { $wtStat = "FAIL" }
$Checks += @{ id = "watertight"; status = $wtStat; message = $(if ($watertight) { "closed manifold mesh" } else { "not watertight (nonmanifold=$nonmanifold)" }) }
$volStat = "PASS"; if ($volume -le 0 -and $triCount -gt 0) { $volStat = "FAIL" }
$Checks += @{ id = "volume"; status = $volStat; message = "$volume mm3" }

$Result = @{
    status = $status
    file = $StlFile
    format = $format
    file_size_bytes = $fileSizeBytes
    triangle_count = $triCount
    bbox_min = @([math]::Round($bmin[0], 4), [math]::Round($bmin[1], 4), [math]::Round($bmin[2], 4))
    bbox_max = @([math]::Round($bmax[0], 4), [math]::Round($bmax[1], 4), [math]::Round($bmax[2], 4))
    bbox_size_mm = $bboxSize
    volume_mm3 = [math]::Round($volume, 3)
    volume_note = "ESTIMATE: signed-tetrahedra sum; assumes consistent outward orientation"
    zero_area_triangles = $zeroArea
    duplicate_vertices = $dupVerts
    nan_coordinates = $nanCount
    degenerate_normals = $degenNormals
    nonmanifold_edges = $nonmanifold
    connected_components = $components
    watertight = $watertight
    failures = @($failList.ToArray())
    checks = $Checks
}

if ($AsJson) {
    $Result | ConvertTo-Json -Depth 5 -Compress
} else {
    $Result
}
