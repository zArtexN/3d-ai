<#
.SYNOPSIS
  Phase 9: PRINT_READY kapi degerlendirmesi (saf kutuphane).
.DESCRIPTION
  Test-PrintReady: asama kayitlari + mesh/readiness durumundan
  PRINT_READY | NOT_PRINT_READY + reasons[] uretir. Deger URETMEZ, dosya YAZMAZ.
  Tum kosullar:
    geometry valid (mesh dosyasi var), mesh valid (watertight),
    kritik olculer biliniyor (design NEEDS_INPUT degil), printability checked,
    orientation selected, printer+filament+process+slicer hazir (readiness READY),
    slicer successful, output verified.
#>

function Get-PRStage($stages, $id) {
  foreach ($s in @($stages)) { if ([string]$s.stage -eq $id) { return $s } }
  return $null
}

function Test-PrintReady($Stages, $MeshPath, $MeshQuality, $Readiness) {
  $reasons = New-Object System.Collections.ArrayList
  $meshOk = @(
    (Get-PRStage $Stages "design"),
    (Get-PRStage $Stages "import_mesh"),
    (Get-PRStage $Stages "reconstruct")
  ) | Where-Object { $null -ne $_ -and ([string]$_.status -eq "OK") }
  if (@($meshOk).Count -eq 0 -or [string]$MeshPath -eq "" -or -not (Test-Path -LiteralPath ([string]$MeshPath))) {
    $reasons.Add("geometry invalid (mesh yok)") | Out-Null
  }
  if ($null -eq $MeshQuality -or [bool]$MeshQuality.watertight -ne $true) {
    $reasons.Add("mesh invalid (watertight degil)") | Out-Null
  }
  $des = Get-PRStage $Stages "design"
  if ($null -ne $des -and [string]$des.status -eq "NEEDS_INPUT") {
    $reasons.Add("kritik olculer bilinmiyor (NEEDS_INPUT)") | Out-Null
  }
  $pa = Get-PRStage $Stages "printability"
  if ($null -eq $pa -or [string]$pa.status -ne "OK") {
    $reasons.Add("printability checked degil") | Out-Null
  }
  $orn = Get-PRStage $Stages "orientation"
  if ($null -eq $orn -or [string]$orn.status -ne "OK") {
    $reasons.Add("orientation selected degil") | Out-Null
  }
  if ($null -eq $Readiness -or [string]$Readiness.status -ne "READY") {
    $reasons.Add("printer/filament/process/slicer hazir degil") | Out-Null
  }
  $sl = Get-PRStage $Stages "slice"
  if ($null -eq $sl -or [string]$sl.status -ne "OK") {
    $reasons.Add("slicer successful degil") | Out-Null
  }
  $ov = Get-PRStage $Stages "output_verify"
  if ($null -eq $ov -or [string]$ov.status -ne "OK") {
    $reasons.Add("output verified degil") | Out-Null
  }
  if ($reasons.Count -eq 0) { return @{ verdict = "PRINT_READY"; reasons = @() } }
  return @{ verdict = "NOT_PRINT_READY"; reasons = @($reasons.ToArray()) }
}
