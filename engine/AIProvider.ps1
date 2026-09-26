<#
.SYNOPSIS
  AI provider abstraction (V1.2). AI yalnizca structured DesignSpec v2 uretir; SCAD/STL/G-code URETMEZ.
.DESCRIPTION
  Provider interface: Invoke-AIProvider -Provider <ad> -Prompt <p> -ProjectName <n> -OutSpec <yol>
  Cikti: @{ provider; spec (yol); mock (bool) }.
  MOCK: test icin parser'i cagirir; provider=TEST/MOCK olarak etiketlenir (sahte AI izlenimi YASAK).
  OPENAI/CLAUDE/LOCAL/OLLAMA: henuz bagli degil -> acik hata (gizleme yok).
.EXAMPLE
  powershell -File engine\AIProvider.ps1 -Provider MOCK -Prompt "..." -ProjectName x -OutSpec s.json
#>
param(
  [string]$Provider = "MOCK",
  [Parameter(Mandatory = $true)][string]$Prompt,
  [Parameter(Mandatory = $true)][string]$ProjectName,
  [Parameter(Mandatory = $true)][string]$OutSpec
)

$ErrorActionPreference = "Stop"
$EngineDir = $PSScriptRoot
$Root = Split-Path -Parent $EngineDir
$up = $Provider.ToUpperInvariant()

if ($up -eq "MOCK" -or $up -eq "TEST") {
  & (Join-Path $EngineDir "ConvertTo-GeometrySpec.ps1") -Prompt $Prompt -ProjectName $ProjectName -OutPath $OutSpec 2>&1 | Out-Null
  $rep = [pscustomobject]@{ provider = "MOCK"; mock = $true; spec = $OutSpec; note = "test saglayicisi; parser ciktisi. Gercel AI degil." }
  $rep | ConvertTo-Json
  exit 0
}
throw "AI provider bagli degil: $Provider (hazir arayuz; su an yalnizca MOCK calisir). Destek plani: OPENAI/CLAUDE/LOCAL/OLLAMA."
