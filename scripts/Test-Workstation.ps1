<#
.SYNOPSIS
  Phase 10: Workstation UI headless testleri.
#>
param()
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root (Join-Path "app" "Workstation.ps1")

$results = New-Object System.Collections.Generic.List[object]
function Add-WResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}

try {
  $o = & $App -SelfTest 2>&1 | Out-String
  Add-WResult "WUI-01-selftest" ($o -match "WS-SELFTEST: PASS") "kontroller"
} catch { Add-WResult "WUI-01-selftest" $false $_.Exception.Message }

try {
  $o = & $App -ValidateUI 2>&1 | Out-String
  Add-WResult "WUI-02-startup" ($o -match "UI-STARTUP: PASS") "motor grid"
} catch { Add-WResult "WUI-02-startup" $false $_.Exception.Message }

try {
  $t = Get-Content -LiteralPath $App -Raw
  $noSend = ($t -notmatch "Send-|Start-Print|Upload-Gcode")
  $hasOffline = ($t -match "GONDERILMEZ")
  Add-WResult "WUI-03-offline" ($noSend -and $hasOffline) "print offline"
} catch { Add-WResult "WUI-03-offline" $false $_.Exception.Message }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "WS-UI SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
