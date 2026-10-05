<#
.SYNOPSIS
  Phase 10: yol guvenligi (path traversal korumasi). Kok disina cikis YOK.
#>

function Test-PathSafe($RootDir, $CandidatePath) {
  if ([string]::IsNullOrWhiteSpace([string]$CandidatePath)) {
    return @{ ok = $false; resolved = ""; reason = "bos yol" }
  }
  try {
    $rootFull = [System.IO.Path]::GetFullPath([string]$RootDir)
    $sep = [string][System.IO.Path]::DirectorySeparatorChar
    $rootPrefix = $rootFull
    if (-not $rootPrefix.EndsWith($sep)) { $rootPrefix += $sep }
    $candFull = [System.IO.Path]::GetFullPath(
      [System.IO.Path]::Combine($rootFull, ([string]$CandidatePath)))
    if ($candFull.Equals($rootFull, [System.StringComparison]::OrdinalIgnoreCase)) {
      return @{ ok = $true; resolved = $candFull; reason = "" }
    }
    if (-not $candFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return @{ ok = $false; resolved = ""; reason = "kok disina cikis engellendi" }
    }
    return @{ ok = $true; resolved = $candFull; reason = "" }
  } catch {
    return @{ ok = $false; resolved = ""; reason = "yol cozulemedi" }
  }
}
