<#
.SYNOPSIS
  Trimesh mesh-analysis adapter (Phase 5).
.DESCRIPTION
  Izole env python + trimesh kullanir (3D-AI-External/envs).
  Op destekleri: Analyze. Diger op -> UNSUPPORTED.
  Spec dosyasina dokunmaz; cikti yalnizca verilen dosyaya yazilir.
#>

function Get-TrimeshPython {
  $root = $null
  $ev = [System.Environment]::GetEnvironmentVariable("THREE_D_AI_EXTERNAL")
  if (-not [string]::IsNullOrWhiteSpace($ev)) { $root = $ev }
  else {
    $adaptersDir = $PSScriptRoot
    $enginesDir = Split-Path -Parent $adaptersDir
    $engineDir = Split-Path -Parent $enginesDir
    $repoRoot = Split-Path -Parent $engineDir
    $root = Join-Path (Split-Path -Parent $repoRoot) "3D-AI-External"
  }
  return (Join-Path $root (Join-Path "envs" (Join-Path "python312" "python.exe")))
}

function Trimesh-Health {
  $py = Get-TrimeshPython
  if (-not (Test-Path -LiteralPath $py)) {
    return @{ status = "NOT_READY"; reason = "izole python yok" }
  }
  try {
    $o = & $py -c "import trimesh, numpy" 2>&1 | Out-String
    return @{ status = "READY"; reason = "python+trimesh hazir"; python = $py }
  } catch {
    return @{ status = "NOT_READY"; reason = ("trimesh import basarisiz: " + [string]$_.Exception.Message) }
  }
}

function Trimesh-Invoke($op, $params) {
  if ([string]$op -ne "Analyze") {
    return @{ status = "UNSUPPORTED"; reason = ("desteklenmeyen op: " + $op) }
  }
  $h = Trimesh-Health
  if ([string]$h.status -ne "READY") { return $h }
  $stl = [string]$params.Stl
  if ([string]::IsNullOrWhiteSpace($stl) -or -not (Test-Path -LiteralPath $stl)) {
    return @{ status = "BLOCKED"; reason = "STL bulunamadi" }
  }
  $py = Get-TrimeshPython
  $envsDir = Split-Path -Parent (Split-Path -Parent $py)
  $script = Join-Path $envsDir "meshinfo.py"
  if (-not (Test-Path -LiteralPath $script)) {
    return @{ status = "BLOCKED"; reason = "meshinfo.py yok" }
  }
  try {
    $o = & $py $script $stl 2>&1 | Out-String
    $m = $o | ConvertFrom-Json
    if ($null -eq $m -or $null -eq $m.bbox_min) {
      return @{ status = "BLOCKED"; reason = "trimesh ciktisi okunamadi" }
    }
    $out = [string]$params.OutJson
    if (-not [string]::IsNullOrWhiteSpace($out)) {
      $m | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $out -Encoding UTF8
    }
    return @{
      status = "OK"; engine = "trimesh"
      watertight = [bool]$m.watertight; volume_mm3 = $m.volume
      bbox_min = @($m.bbox_min); bbox_max = @($m.bbox_max)
      faces = [int]$m.faces; euler = [int]$m.euler
    }
  } catch {
    return @{ status = "BLOCKED"; reason = [string]$_.Exception.Message }
  }
}
