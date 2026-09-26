<#
.SYNOPSIS
  UI handler regression: gercek Tasarla/Devam handler'lari headless surulur.
.DESCRIPTION
  DesignerV1.ps1 -UITest calistirir (open_top->center->PASS, displayId/stabil ayrim,
  prompt korunumu, reset). Ayrica -ValidateUI startup kontrolu yapar.
  Cikis: 0 = hepsi gecti.
.EXAMPLE
  powershell -File scripts\Test-QA-UI.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$App = Join-Path $Root (Join-Path "app" "DesignerV1.ps1")

$results = New-Object System.Collections.Generic.List[object]
function Add-UResult($name, $ok, $detail) {
  $label = "FAIL"; if ($ok) { $label = "PASS" }
  $results.Add([pscustomobject]@{ test = $name; result = $label; detail = $detail })
  Write-Output "[$label] $name -- $detail"
}

try {
  $o = & $App -UITest 2>&1 | Out-String
  $ok = ($o -match "UI-TEST: PASS")
  $hasTransition = ($o -match "stableId=body-hollow_top" -and $o -match "stableId=body-hole-h1-center")
  $hasStl = ($o -match "stl=True")
  Add-UResult "UQA-01-ui-flow" ($ok -and $hasTransition -and $hasStl) $(if ($ok) { "open_top->center->STL" } else { $o })
} catch { Add-UResult "UQA-01-ui-flow" $false $_.Exception.Message }

try {
  $o = & $App -ValidateUI 2>&1 | Out-String
  Add-UResult "UQA-02-ui-startup" ($o -match "UI-STARTUP: PASS") "form kuruldu"
} catch { Add-UResult "UQA-02-ui-startup" $false $_.Exception.Message }

try {
  $left = @(Get-ChildItem -LiteralPath (Join-Path $Root "projects") -Directory | Where-Object { $_.Name -match "^proje-" })
  Add-UResult "UQA-03-no-leftover" ($left.Count -eq 0) $(if ($left.Count -eq 0) { "artik proje yok" } else { "kalan: $(@($left | ForEach-Object { $_.Name }) -join ',')" })
} catch { Add-UResult "UQA-03-no-leftover" $false $_.Exception.Message }

$passed = @($results | Where-Object { $_.result -eq "PASS" }).Count
Write-Output "----------------------------------------"
Write-Output "QA-UI SONUC: $passed / $($results.Count) test gecti"
if ($passed -ne $results.Count) { exit 1 } else { exit 0 }
