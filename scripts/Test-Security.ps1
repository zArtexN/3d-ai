<#
.SYNOPSIS
  Phase 10: guvenlik statik denetimi (TDD).
.DESCRIPTION
  - AI ciktisi keyfi shell calistiramaz: engine/scripts altinda AI degiskeniyle
    Invoke-Expression/iex/cmd calistirma taramasi.
  - AI uretimi mutlaka parse->validate->normalize->kontrollu calisma zincirinden
    gecer (pipeline spec parse + geometry gate yapisal kontrolu).
  - Secret taramasi: password/api_key/token kalibi repoda yok.
  - Gecici dosyalar onayli koklerdedir (TEMP / proje / output).
  - Path traversal korumasi Test-PathSafe ile covered (birim).
#>
param()

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$EngineDir = Join-Path $Root "engine"
. (Join-Path $EngineDir "Test-PathSafe.ps1")

$script:pass = 0; $script:fail = 0
function Add-SECResult($id, $ok, $note) {
  if ($ok) { $script:pass++; Write-Output ("[PASS] " + $id + " -- " + $note) }
  else { $script:fail++; Write-Output ("[FAIL] " + $id + " -- " + $note) }
}

$psFiles = Get-ChildItem -Path $EngineDir -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue |
  Where-Object { ($_.FullName -notmatch "\\dist\\") -and ($_.Name -ne "Test-Security.ps1") }
$psFiles += Get-ChildItem -Path (Join-Path $Root "scripts") -Filter "*.ps1" -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -ne "Test-Security.ps1" }

# T-SEC-01: AI verisiyle Invoke-Expression / iex / cmd calistirma yok.
# (freecadcmd.exe gibi binary ADLARI eslesmemeli: \b sinirli regex.)
$dangerExpr = @()
foreach ($f in $psFiles) {
  $hits = Select-String -LiteralPath $f.FullName -Pattern "Invoke-Expression", "\biex\b", "\bcmd\.exe", "cmd /c" -ErrorAction SilentlyContinue
  foreach ($h in $hits) {
    $ln = [string]$h.Line
    if ($ln -match "^\s*#") { continue }
    $dangerExpr += @($f.Name + ":" + $h.LineNumber)
  }
}
Add-SECResult "T-SEC-01" (@($dangerExpr).Count -eq 0) $(if (@($dangerExpr).Count -eq 0) { "keyfi calistirma yok" } else { ($dangerExpr -join ",") })

# T-SEC-02: zincir yapisal (parse + gate).
$pipeText = Get-Content -LiteralPath (Join-Path $EngineDir "Invoke-Pipeline.ps1") -Raw
$hasParse = ($pipeText -match "ConvertFrom-Json")
$hasGate = ($pipeText -match "Test-GeometrySpec")
$hasQuestions = ($pipeText -match "Get-SpecQuestions|NEEDS_INPUT")
Add-SECResult "T-SEC-02" ($hasParse -and $hasGate -and $hasQuestions) "parse->validate->sor zinciri"

# T-SEC-03: secret kalibi yok (password=, api_key, secret=, token= atamalari).
$secretHits = @()
foreach ($f in $psFiles) {
  $hits = Select-String -LiteralPath $f.FullName -Pattern 'password\s*=|api_key\s*=|secret\s*=|private_token\s*=' -ErrorAction SilentlyContinue
  foreach ($h in $hits) {
    $ln = [string]$h.Line
    if ($ln -match "^\s*#") { continue }
    $secretHits += @($f.Name + ":" + $h.LineNumber)
  }
}
Add-SECResult "T-SEC-03" (@($secretHits).Count -eq 0) $(if (@($secretHits).Count -eq 0) { "secret yok" } else { ($secretHits -join ",") })

# T-SEC-04: gecici dosya kokleri onayli (GetTempPath / TEMP env / proje-altı).
$tmpHits = @()
foreach ($f in $psFiles) {
  $hits = Select-String -LiteralPath $f.FullName -Pattern 'C:\\Temp|C:/Temp|"C:\\Windows\\Temp' -ErrorAction SilentlyContinue
  foreach ($h in $hits) { $tmpHits += @($f.Name + ":" + $h.LineNumber) }
}
Add-SECResult "T-SEC-04" (@($tmpHits).Count -eq 0) $(if (@($tmpHits).Count -eq 0) { "sabit temp yolu yok" } else { ($tmpHits -join ",") })

# T-SEC-05: traversal korumasi birim (kacis engellenir, ic yol gecer).
$root = Join-Path $Root "projects"
$t1 = Test-PathSafe $root "demo"
$t2 = Test-PathSafe $root "..\disari"
$t3 = Test-PathSafe $root "a\..\..\disari"
Add-SECResult "T-SEC-05" ([bool]$t1.ok -and -not [bool]$t2.ok -and -not [bool]$t3.ok) "traversal guard"

# T-SEC-06: dis proses cagrilari string-komut degil, arguman-dizisi formunda
# (ornek kotu kalip: powershell "...$kullanici...").
$concatHits = @()
foreach ($f in $psFiles) {
  $hits = Select-String -LiteralPath $f.FullName -Pattern 'powershell "' -ErrorAction SilentlyContinue
  foreach ($h in $hits) {
    $ln = [string]$h.Line
    if ($ln -match "^\s*#") { continue }
    $concatHits += @($f.Name + ":" + $h.LineNumber)
  }
}
Add-SECResult "T-SEC-06" (@($concatHits).Count -eq 0) $(if (@($concatHits).Count -eq 0) { "string-komut yok" } else { ($concatHits -join ",") })

Write-Output "----------------------------------------"
Write-Output ("SECURITY SONUC: " + $script:pass + " / " + ($script:pass + $script:fail) + " test gecti")
if ($script:fail -gt 0) { exit 1 }
