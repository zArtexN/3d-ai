<#
.SYNOPSIS
  Kullanicinin cevabini DesignSpec v2'ye isler (ince sarmalayici; mantik QA-Contract'tadir).
.DESCRIPTION
  Akis: spec yukle -> Resolve-CurrentQuestion (stable ID) -> Invoke-QuestionParser
  -> damga (answer/source/asked_at) -> spec + soru dosyasini kaydet.
  Sayisal deger oldugu gibi korunur. Cevap gecersizse throw (pipeline NEEDS_INPUT dondurur).
.EXAMPLE
  powershell -File engine\Update-SpecAnswer.ps1 -SpecFile s.json -QuestionId body-hole-h1-center -Answer "15,15"
#>
param(
  [Parameter(Mandatory = $true)][string]$SpecFile,
  [Parameter(Mandatory = $true)][string]$QuestionId,
  [Parameter(Mandatory = $true)][string]$Answer
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "QA-Contract.ps1")

if (-not (Test-Path -LiteralPath $SpecFile)) { throw "Spec bulunamadi: $SpecFile" }
$uspecObj = Get-Content -LiteralPath $SpecFile -Raw | ConvertFrom-Json

$qfile = [System.IO.Path]::ChangeExtension($SpecFile, ".questions.json")
$q = Resolve-CurrentQuestion $SpecFile $QuestionId
if ($null -eq $q) { throw "Soru bulunamadi: $QuestionId" }
$kind = [string]$q.kind

$res = Invoke-QuestionParser $uspecObj $q $Answer
if (-not $res.ok) { throw [string]$res.message }

$q.answer = $Answer
$q.source = "user"
$q.asked_at = (Get-Date).ToUniversalTime().ToString("o")

$uspecObj | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $SpecFile -Encoding UTF8
if (Test-Path -LiteralPath $qfile) {
  $qraw = Get-Content -LiteralPath $qfile -Raw | ConvertFrom-Json
  $qlist = New-Object System.Collections.Generic.List[object]
  if ($null -ne $qraw) {
    if ($qraw -is [array]) { foreach ($e in $qraw) { $qlist.Add($e) } }
    else { $qlist.Add($qraw) }
  }
  $found = $false
  foreach ($e in $qlist) {
    if ([string]$e.question_id -eq $QuestionId) {
      $e.answer = $Answer; $e.source = "user"; $e.asked_at = $q.asked_at
      $found = $true
    }
  }
  if (-not $found) { $qlist.Add($q) }
  $qlist | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $qfile -Encoding UTF8
}
Write-Output "CEVAP-ISLEDI: $QuestionId ($kind)"
