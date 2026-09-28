<#
.SYNOPSIS
  Tek komutla tum testler: syntax + V1 + geometry + UI selftest + resolver.
.DESCRIPTION
  Siralama: syntax -> V1 (Run-Tests) -> geometry (Run-GeometryTests) -> UI selftest -> resolver.
  Ozet: TOTAL / PASS / FAIL + gozlemlenen WARNING / BLOCKED sayilari.
  Cikis: 0 = tum suitler gecti.
.EXAMPLE
  powershell -File scripts\Run-AllTests.ps1
#>

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
$scriptsDir = Join-Path $Root "scripts"

$totalPass = 0
$totalFail = 0
$warnSeen = 0
$blockedSeen = 0
$suitesOk = $true

function Count-Results($lines) {
  $p = 0; $f = 0
  foreach ($ln in $lines) {
    $s = [string]$ln
    if ($s -match "^\[PASS\]") { $p++ }
    elseif ($s -match "^\[FAIL\]") { $f++ }
    elseif ($s -match "GOZLEM:\s*(\d+)\s*WARNING,\s*(\d+)\s*BLOCKED") {
      $script:warnSeen += [int]$Matches[1]
      $script:blockedSeen += [int]$Matches[2]
    }
  }
  return @{ pass = $p; fail = $f }
}

Write-Output "=== 1/11 SYNTAX ==="
$synBad = 0; $synOk = 0
$files = Get-ChildItem $Root -Include "*.ps1" -Recurse | Where-Object { ($_.FullName -notmatch "node_modules") -and ($_.FullName -notmatch "\\dist\\") }
foreach ($f in $files) {
  $errs = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errs)
  if ($errs.Count -gt 0) { $synBad++; Write-Output "[FAIL] syntax: $($f.Name)" }
  else { $synOk++ }
}
$totalPass += $synOk; $totalFail += $synBad
if ($synBad -gt 0) { $suitesOk = $false }
Write-Output "syntax: $synOk OK, $synBad bozuk"

Write-Output "=== 2/11 V1 TESTS ==="
$v1 = & (Join-Path $scriptsDir "Run-Tests.ps1") 2>&1
$c = Count-Results $v1
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "V1: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 3/11 GEOMETRY TESTS ==="
$geo = & (Join-Path $scriptsDir "Run-GeometryTests.ps1") 2>&1
$c = Count-Results $geo
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "geometry: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 4/11 PIPELINE TESTS ==="
$pipe = & (Join-Path $scriptsDir "Run-PipelineTests.ps1") 2>&1
$c = Count-Results $pipe
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "pipeline: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 5/11 PARSER TESTS ==="
$par = & (Join-Path $scriptsDir "Run-ParserTests.ps1") 2>&1
$c = Count-Results $par
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "parser: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 6/11 V13 TESTS ==="
$v13 = & (Join-Path $scriptsDir "Run-V13Tests.ps1") 2>&1
$c = Count-Results $v13
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "v13: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 7/11 QA TESTS ==="
$qa = & (Join-Path $scriptsDir "Test-QA.ps1") 2>&1
$c = Count-Results $qa
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "qa: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 8/11 QA-UI TESTS ==="
$qaui = & (Join-Path $scriptsDir "Test-QA-UI.ps1") 2>&1
$c = Count-Results $qaui
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "qa-ui: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 9/11 UI SELFTEST ==="
$ui = & (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -SelfTest 2>&1 | Out-String
if ($ui -match "SELFTEST: PASS") { $totalPass++; Write-Output "UI selftest: PASS" }
else { $totalFail++; $suitesOk = $false; Write-Output "UI selftest: FAIL" }

Write-Output "=== 10/11 RESOLVER ==="
foreach ($r in @("Resolve-OpenScad.ps1", "Resolve-FreeCad.ps1", "Resolve-OrcaSlicer.ps1")) {
  try {
    $v = & (Join-Path $scriptsDir $r) 2>&1 | Select-Object -Last 1
    if ($v -and (Test-Path -LiteralPath ([string]$v))) { $totalPass++; Write-Output "[PASS] $r" }
    else { $totalFail++; $suitesOk = $false; Write-Output "[FAIL] $r" }
  } catch { $totalFail++; $suitesOk = $false; Write-Output "[FAIL] $r" }
}

Write-Output "=== 11/13 PORTABLE ==="
$port = & (Join-Path $scriptsDir "Run-PortableTest.ps1") 2>&1
$c = Count-Results $port
$totalPass += $c.pass; $totalFail += $c.fail
$portOk = (@($port | Where-Object { [string]$_ -match "PORTABLE TEST PASS" }).Count -gt 0)
if ($c.fail -gt 0 -or -not $portOk) { $suitesOk = $false }
Write-Output "portable: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 12/13 PRINT TESTS ==="
$pt = & (Join-Path $scriptsDir "Run-PrintTests.ps1") 2>&1
$c = Count-Results $pt
$totalPass += $c.pass; $totalFail += $c.fail
if ($c.fail -gt 0) { $suitesOk = $false }
Write-Output "print: $($c.pass) PASS, $($c.fail) FAIL"

Write-Output "=== 13/13 UI V2 STARTUP ==="
$ui2 = & (Join-Path $Root (Join-Path "app" "DesignerV1.ps1")) -ValidateUI 2>&1 | Out-String
if ($ui2 -match "UI-STARTUP: PASS") { $totalPass++; Write-Output "UI V2 startup: PASS" }
else { $totalFail++; $suitesOk = $false; Write-Output "UI V2 startup: FAIL" }

$total = ($totalPass + $totalFail)
Write-Output "========================================"
Write-Output "TOTAL: $total | PASS: $totalPass | FAIL: $totalFail"
Write-Output "GOZLEM: $warnSeen WARNING, $blockedSeen BLOCKED"
if ($suitesOk) { exit 0 } else { exit 1 }
