<#
.SYNOPSIS
  Proje version history kutuphanesi (Phase 3).
.DESCRIPTION
  SAF KUTUPHANE: param blogu yok, calisir kod yok.
  Duzen: <project>/versions/index.json + vNNN.json (meta + full snapshot).
  Full snapshot (reliability > storage). Version immutable: dosya olustuktan
  sonra degistirilmez; restore yeni version uretir (kaynak korunur).
  Yeni edit (non-tip): parent=current ile dal olusturur; eski gelecek korunur.
  Redo stack yeni editte temizlenir. Kilit: versions/.lock (bayat kilit asilir).
#>

function Get-VersionsDir($projectDir) { return (Join-Path $projectDir "versions") }
function Get-VersionsIndexPath($projectDir) { return (Join-Path (Get-VersionsDir $projectDir) "index.json") }

function Read-VersionsIndex($projectDir) {
  $p = Get-VersionsIndexPath $projectDir
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  return (Get-Content -LiteralPath $p -Raw | ConvertFrom-Json)
}

function Write-VersionsIndex($projectDir, $index) {
  $d = Get-VersionsDir $projectDir
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $index | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Get-VersionsIndexPath $projectDir) -Encoding UTF8
}

function Acquire-VersionLock($projectDir) {
  $d = Get-VersionsDir $projectDir
  New-Item -ItemType Directory -Force -Path $d | Out-Null
  $lp = Join-Path $d ".lock"
  if (Test-Path -LiteralPath $lp) {
    try {
      $lk = Get-Content -LiteralPath $lp -Raw | ConvertFrom-Json
      $age = 999999
      try { $age = ((Get-Date) - [datetime]$lk.ts).TotalSeconds } catch { }
      if ($age -lt 120 -and [int]$lk.pid -ne $PID) {
        return @{ ok = $false; message = ("kilitli (pid " + $lk.pid + ")") }
      }
    } catch { }
  }
  @{ pid = $PID; ts = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json | Set-Content -LiteralPath $lp -Encoding UTF8
  return @{ ok = $true; message = "ok" }
}

function Release-VersionLock($projectDir) {
  $lp = Join-Path (Get-VersionsDir $projectDir) ".lock"
  Remove-Item -LiteralPath $lp -Force -ErrorAction SilentlyContinue
}

function Initialize-Versions($projectDir, $spec, $summary) {
  if ($null -ne (Read-VersionsIndex $projectDir)) { return (Read-VersionsIndex $projectDir) }
  $lk = Acquire-VersionLock $projectDir
  if (-not $lk.ok) { throw ("version lock: " + $lk.message) }
  try {
    $v = [pscustomobject]@{
      version_id = "v001"; parent_version = $null; restore_from = $null
      created_at = (Get-Date).ToUniversalTime().ToString("o")
      change_summary = [string]$summary; patch = @(); validation = $null; measurement = $null
      spec = ($spec | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }
    $v | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path (Get-VersionsDir $projectDir) "v001.json") -Encoding UTF8
    $idx = [pscustomobject]@{
      current = "v001"; redo_stack = @()
      versions = @([pscustomobject]@{ id = "v001"; parent = $null; created = $v.created_at })
    }
    Write-VersionsIndex $projectDir $idx
    return $idx
  } finally { Release-VersionLock $projectDir }
}

function Get-VersionSpec($projectDir, $versionId) {
  $p = Join-Path (Get-VersionsDir $projectDir) ([string]$versionId + ".json")
  if (-not (Test-Path -LiteralPath $p)) { return $null }
  $v = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
  return $v.spec
}

function New-ProjectVersion($projectDir, $parentId, $spec, $summary, $patch, $validation, $measurement) {
  $lk = Acquire-VersionLock $projectDir
  if (-not $lk.ok) { throw ("version lock: " + $lk.message) }
  try {
    $idx = Read-VersionsIndex $projectDir
    if ($null -eq $idx) { throw "version store yok; once Initialize-Versions" }
    $maxN = 0
    foreach ($e in @($idx.versions)) {
      if ([string]$e.id -match '^v(\d+)$' -and [int]$Matches[1] -gt $maxN) { $maxN = [int]$Matches[1] }
    }
    $nid = ("v" + ([string]($maxN + 1)).PadLeft(3, '0'))
    $v = [pscustomobject]@{
      version_id = $nid; parent_version = [string]$parentId; restore_from = $null
      created_at = (Get-Date).ToUniversalTime().ToString("o")
      change_summary = [string]$summary; patch = @($patch)
      validation = $validation; measurement = $measurement
      spec = ($spec | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
    }
    $v | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path (Get-VersionsDir $projectDir) ($nid + ".json")) -Encoding UTF8
    $idx.versions = @(@($idx.versions) + @([pscustomobject]@{ id = $nid; parent = [string]$parentId; created = $v.created_at }))
    $idx.current = $nid
    $idx.redo_stack = @()
    Write-VersionsIndex $projectDir $idx
    return $nid
  } finally { Release-VersionLock $projectDir }
}

function Undo-ProjectVersion($projectDir) {
  $lk = Acquire-VersionLock $projectDir
  if (-not $lk.ok) { throw ("version lock: " + $lk.message) }
  try {
    $idx = Read-VersionsIndex $projectDir
    if ($null -eq $idx) { throw "version store yok" }
    $cur = [string]$idx.current
    $parent = $null
    foreach ($e in @($idx.versions)) {
      if ([string]$e.id -eq $cur) { $parent = $e.parent }
    }
    if ($null -eq $parent -or [string]$parent -eq "") { return @{ ok = $false; message = "geri gidilecek surum yok"; current = $cur } }
    $idx.redo_stack = @(@($cur) + @($idx.redo_stack))
    $idx.current = [string]$parent
    Write-VersionsIndex $projectDir $idx
    return @{ ok = $true; message = "ok"; current = [string]$parent }
  } finally { Release-VersionLock $projectDir }
}

function Redo-ProjectVersion($projectDir) {
  $lk = Acquire-VersionLock $projectDir
  if (-not $lk.ok) { throw ("version lock: " + $lk.message) }
  try {
    $idx = Read-VersionsIndex $projectDir
    if ($null -eq $idx) { throw "version store yok" }
    $stack = @($idx.redo_stack)
    if ($stack.Count -eq 0) { return @{ ok = $false; message = "ileri gidilecek surum yok"; current = [string]$idx.current } }
    $nxt = [string]$stack[0]
    $exists = $false
    foreach ($e in @($idx.versions)) { if ([string]$e.id -eq $nxt) { $exists = $true } }
    if (-not $exists) { return @{ ok = $false; message = "hedef surum yok"; current = [string]$idx.current } }
    $rest = @()
    for ($i = 1; $i -lt $stack.Count; $i++) { $rest += $stack[$i] }
    $idx.redo_stack = @($rest)
    $idx.current = $nxt
    Write-VersionsIndex $projectDir $idx
    return @{ ok = $true; message = "ok"; current = $nxt }
  } finally { Release-VersionLock $projectDir }
}

function Restore-ProjectVersion($projectDir, $targetId, $summary) {
  $spec = Get-VersionSpec $projectDir $targetId
  if ($null -eq $spec) { throw ("surum bulunamadi: " + $targetId) }
  $idx = Read-VersionsIndex $projectDir
  if ($null -eq $idx) { throw "version store yok" }
  $nid = New-ProjectVersion $projectDir ([string]$idx.current) $spec $summary @() $null $null
  $vp = Join-Path (Get-VersionsDir $projectDir) ($nid + ".json")
  $v = Get-Content -LiteralPath $vp -Raw | ConvertFrom-Json
  $v.restore_from = [string]$targetId
  $v | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $vp -Encoding UTF8
  return $nid
}
