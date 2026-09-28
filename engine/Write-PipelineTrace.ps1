<#
.SYNOPSIS
  Pipeline trace: her asamanin girdisi/ciktisi logs/pipeline-trace.json'a eklenir.
.DESCRIPTION
  Asama kaydi: stage, input, output, recognizedFacts, missingFacts, questions[].
  Soru kaydi: question_id/type/target/missing_property/current_value/source.
  Secret yok (prompt zaten input.md'de), binary yok, dosya kompakt tutulur.
  Cikis: 0 = ok.
.EXAMPLE
  powershell -File engine\Write-PipelineTrace.ps1 -ProjectDir projects\x -Stage parse -DataJson '{"spec":"spec.json"}'
#>
param(
  [Parameter(Mandatory = $true)][string]$ProjectDir,
  [Parameter(Mandatory = $true)][string]$Stage,
  [string]$DataJson = "{}"
)

$ErrorActionPreference = "Continue"
$here = $ProjectDir
if (-not [System.IO.Path]::IsPathRooted($here)) {
  $here = Join-Path (Split-Path -Parent $PSScriptRoot) $here
}
$ld = Join-Path $here "logs"
New-Item -ItemType Directory -Force -Path $ld | Out-Null
$tp = Join-Path $ld "pipeline-trace.json"

$trace = @()
if (Test-Path -LiteralPath $tp) {
  try {
    $raw = Get-Content -LiteralPath $tp -Raw | ConvertFrom-Json
    if ($null -ne $raw) {
      if ($raw -is [array]) { $trace = @($raw) } else { $trace = @($raw) }
    }
  } catch { $trace = @() }
}
$data = $null
try { $data = $DataJson | ConvertFrom-Json } catch { $data = [pscustomobject]@{ raw = $DataJson } }
$entry = [pscustomobject]@{
  at = (Get-Date).ToUniversalTime().ToString("o")
  stage = $Stage
  data = $data
}
$trace += $entry
if ($trace.Count -gt 60) { $trace = @($trace[($trace.Count - 60)..($trace.Count - 1)]) }
$trace | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $tp -Encoding UTF8
Write-Output ("TRACE: " + $Stage)
exit 0
