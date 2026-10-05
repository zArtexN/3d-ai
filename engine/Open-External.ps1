<#
.SYNOPSIS
  Harici uygulama ile acma (External Application / Open With).
.DESCRIPTION
  3D-AI cikti dosyalarini (STL/SCAD/3MF/OBJ/STEP/STP/BLEND) harici uygulamalarla acar.
  - Uygulama cozumu icin mevcut scripts/Resolve-*.ps1 mimarisi kullanilir
    (settings.local -> settings -> environment -> tools -> PATH -> bilinen yollar).
  - Tum girisler Test-Path -LiteralPath ile dogrulanir; dosya yoksa hicbir sey baslatilmaz.
  - Start-Process cagrilarinda yollar argument array olarak verilir.
  - Uygulama kurulu degilse sonuc nesnesi dondurur; crash vermez, sahte basari uretmez.
  - Dosya donusumu yapmaz; mevcut gercek ciktilari acar.
  Donus sozlesmesi: PSCustomObject @{ Ok=[bool]; Code=[string]; Action=[string];
    Target=[string]; Tool=[string]; Message=[string] }
  Code degerleri: LAUNCHED | FILE_MISSING | DIR_MISSING | APP_MISSING |
    UNKNOWN_TOOL | LAUNCH_FAILED
#>

function Get-OpenExternalRoot {
  try {
    $r = $PSScriptRoot
    if ([string]::IsNullOrEmpty($r)) { return "" }
    $p = Split-Path -Parent $r
    if ([string]::IsNullOrEmpty($p)) { return $r }
    return $p
  } catch { return "" }
}

function Get-ExternalToolResolver($toolName) {
  $t = ([string]$toolName).ToLowerInvariant()
  if ($t -eq "openscad") { return "Resolve-OpenScad.ps1" }
  if ($t -eq "blender") { return "Resolve-Blender.ps1" }
  if ($t -eq "freecad") { return "Resolve-FreeCad.ps1" }
  if ($t -eq "orcaslicer") { return "Resolve-OrcaSlicer.ps1" }
  return ""
}

function New-OpenResult($ok, $code, $action, $target, $tool, $message) {
  return [pscustomobject]@{
    Ok = [bool]$ok
    Code = [string]$code
    Action = [string]$action
    Target = [string]$target
    Tool = [string]$tool
    Message = [string]$message
  }
}

function Get-ExternalToolPath($toolName) {
  try {
    $resName = Get-ExternalToolResolver $toolName
    if ([string]::IsNullOrEmpty($resName)) { return "" }
    $root = Get-OpenExternalRoot
    if ([string]::IsNullOrEmpty($root)) { return "" }
    $resPs1 = Join-Path $root (Join-Path "scripts" $resName)
    if (-not (Test-Path -LiteralPath $resPs1)) { return "" }
    $out = @(& $resPs1 2>$null | Select-Object -Last 1)
    if ($out.Count -eq 0 -or $null -eq $out[0]) { return "" }
    $cand = ([string]$out[0]).Trim()
    if ([string]::IsNullOrEmpty($cand)) { return "" }
    if (Test-Path -LiteralPath $cand) { return $cand }
    return ""
  } catch { return "" }
}

function Get-ToolForExtension($extension) {
  $e = ([string]$extension).ToLowerInvariant()
  if ($e -eq ".scad") { return "openscad" }
  if ($e -eq ".blend") { return "blender" }
  if ($e -eq ".step" -or $e -eq ".stp") { return "freecad" }
  if ($e -eq ".3mf") { return "orcaslicer" }
  if ($e -eq ".stl") { return "orcaslicer" }
  return ""
}

function Get-AppMissingHint($toolName) {
  $t = ([string]$toolName).ToLowerInvariant()
  if ($t -eq "openscad") { return "Ayarlar > Araclar > Konum Sec veya settings.local.json -> tools.openscad" }
  if ($t -eq "blender") { return "settings.local.json -> tools.blender veya BLENDER_EXE ortam degiskeni" }
  if ($t -eq "freecad") { return "settings.local.json -> tools.freecad veya FREECAD_EXE ortam degiskeni" }
  if ($t -eq "orcaslicer") { return "settings.local.json -> tools.orcaslicer veya ORCASLICER_EXE ortam degiskeni" }
  return "ilgili resolver scriptini kontrol edin (scripts/Resolve-*.ps1)"
}

function Open-PathDefault($filePath) {
  $fp = [string]$filePath
  if ([string]::IsNullOrEmpty($fp)) {
    return (New-OpenResult $false "FILE_MISSING" "default" "" "" "Dosya bulunamadi (bos yol); hicbir sey baslatilmadi.")
  }
  try {
    if (-not (Test-Path -LiteralPath $fp)) {
      return (New-OpenResult $false "FILE_MISSING" "default" $fp "" ("Dosya bulunamadi: " + $fp + "; hicbir sey baslatilmadi."))
    }
  } catch {
    return (New-OpenResult $false "FILE_MISSING" "default" $fp "" ("Dosya dogrulanamadi: " + $fp + "; hicbir sey baslatilmadi."))
  }
  try {
    Start-Process -FilePath $fp -ErrorAction Stop | Out-Null
    return (New-OpenResult $true "LAUNCHED" "default" $fp "" ("Acildi (varsayilan uygulama): " + $fp))
  } catch {
    return (New-OpenResult $false "LAUNCH_FAILED" "default" $fp "" ("Acilamadi: " + $fp + " :: " + $_.Exception.Message))
  }
}

function Open-OutputFolder($dirPath) {
  $dp = [string]$dirPath
  if ([string]::IsNullOrEmpty($dp)) {
    return (New-OpenResult $false "DIR_MISSING" "folder" "" "" "Klasor bulunamadi (bos yol); hicbir sey baslatilmadi.")
  }
  try {
    if (-not (Test-Path -LiteralPath $dp -PathType Container)) {
      return (New-OpenResult $false "DIR_MISSING" "folder" $dp "" ("Klasor bulunamadi: " + $dp + "; hicbir sey baslatilmadi."))
    }
  } catch {
    return (New-OpenResult $false "DIR_MISSING" "folder" $dp "" ("Klasor dogrulanamadi: " + $dp + "; hicbir sey baslatilmadi."))
  }
  try {
    Start-Process -FilePath $dp -ErrorAction Stop | Out-Null
    return (New-OpenResult $true "LAUNCHED" "folder" $dp "" ("Klasor acildi: " + $dp))
  } catch {
    return (New-OpenResult $false "LAUNCH_FAILED" "folder" $dp "" ("Klasor acilamadi: " + $dp + " :: " + $_.Exception.Message))
  }
}

function Open-FileWithTool($filePath, $toolName) {
  $fp = [string]$filePath
  $tn = ([string]$toolName).ToLowerInvariant()
  if ([string]::IsNullOrEmpty($fp)) {
    return (New-OpenResult $false "FILE_MISSING" "tool" "" $tn "Dosya bulunamadi (bos yol); hicbir sey baslatilmadi.")
  }
  try {
    if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) {
      return (New-OpenResult $false "FILE_MISSING" "tool" $fp $tn ("Dosya bulunamadi: " + $fp + "; hicbir sey baslatilmadi."))
    }
  } catch {
    return (New-OpenResult $false "FILE_MISSING" "tool" $fp $tn ("Dosya dogrulanamadi: " + $fp + "; hicbir sey baslatilmadi."))
  }
  $resName = Get-ExternalToolResolver $tn
  if ([string]::IsNullOrEmpty($resName)) {
    return (New-OpenResult $false "UNKNOWN_TOOL" "tool" $fp $tn ("Bilinmeyen arac: " + $tn + "; hicbir sey baslatilmadi."))
  }
  $exe = Get-ExternalToolPath $tn
  if ([string]::IsNullOrEmpty($exe)) {
    return (New-OpenResult $false "APP_MISSING" "tool" $fp $tn ("Uygulama bulunamadi: " + $tn + ". " + (Get-AppMissingHint $tn)))
  }
  try {
    Start-Process -FilePath $exe -ArgumentList @($fp) -ErrorAction Stop | Out-Null
    return (New-OpenResult $true "LAUNCHED" "tool" $fp $tn ("Aciliyor (" + $tn + "): " + $fp))
  } catch {
    return (New-OpenResult $false "LAUNCH_FAILED" "tool" $fp $tn ("Acilamadi (" + $tn + "): " + $fp + " :: " + $_.Exception.Message))
  }
}

function Open-FileWithDialog($filePath) {
  $fp = [string]$filePath
  if ([string]::IsNullOrEmpty($fp)) {
    return (New-OpenResult $false "FILE_MISSING" "openwith" "" "" "Dosya bulunamadi (bos yol); hicbir sey baslatilmadi.")
  }
  try {
    if (-not (Test-Path -LiteralPath $fp -PathType Leaf)) {
      return (New-OpenResult $false "FILE_MISSING" "openwith" $fp "" ("Dosya bulunamadi: " + $fp + "; hicbir sey baslatilmadi."))
    }
  } catch {
    return (New-OpenResult $false "FILE_MISSING" "openwith" $fp "" ("Dosya dogrulanamadi: " + $fp + "; hicbir sey baslatilmadi."))
  }
  try {
    Start-Process -FilePath "rundll32.exe" -ArgumentList @("shell32.dll,OpenAs_RunDLL", $fp) -ErrorAction Stop | Out-Null
    return (New-OpenResult $true "LAUNCHED" "openwith" $fp "" ("Birlikte ac penceresi acildi: " + $fp))
  } catch {
    return (New-OpenResult $false "LAUNCH_FAILED" "openwith" $fp "" ("Birlikte ac acilamadi: " + $fp + " :: " + $_.Exception.Message))
  }
}

function Open-DesignFile($filePath) {
  $fp = [string]$filePath
  if ([string]::IsNullOrEmpty($fp)) {
    return (New-OpenResult $false "FILE_MISSING" "auto" "" "" "Dosya bulunamadi (bos yol); hicbir sey baslatilmadi.")
  }
  $ext = ""
  try { $ext = ([System.IO.Path]::GetExtension($fp)).ToLowerInvariant() } catch { $ext = "" }
  $tool = Get-ToolForExtension $ext
  if ([string]::IsNullOrEmpty($tool)) {
    return (Open-PathDefault $fp)
  }
  if ($ext -eq ".stl") {
    $orca = Get-ExternalToolPath "orcaslicer"
    if ([string]::IsNullOrEmpty($orca)) {
      return (Open-PathDefault $fp)
    }
  }
  return (Open-FileWithTool $fp $tool)
}
