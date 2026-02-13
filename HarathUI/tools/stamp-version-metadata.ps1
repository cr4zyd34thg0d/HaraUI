param(
  [string]$TocPath,
  [string]$Version,
  [string]$GitVersion,
  [string]$BuildCommit,
  [string]$LatestCommit,
  [string]$BuildDate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-MetadataValue {
  param(
    [string[]]$Lines,
    [string]$Key
  )
  $pattern = '^##\s*' + [regex]::Escape($Key) + '\s*:\s*(.*)$'
  foreach ($line in $Lines) {
    $m = [regex]::Match($line, $pattern)
    if ($m.Success) {
      return $m.Groups[1].Value.Trim()
    }
  }
  return $null
}

function Set-MetadataValue {
  param(
    [string[]]$Lines,
    [string]$Key,
    [string]$Value
  )
  $pattern = '^##\s*' + [regex]::Escape($Key) + '\s*:'
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -match $pattern) {
      $Lines[$i] = ("## {0}: {1}" -f $Key, $Value)
      return ,$Lines
    }
  }

  $insertAt = $Lines.Count
  for ($i = 0; $i -lt $Lines.Count; $i++) {
    if ($Lines[$i] -notmatch '^##') {
      $insertAt = $i
      break
    }
  }

  if ($insertAt -le 0) {
    return @(("## {0}: {1}" -f $Key, $Value)) + $Lines
  }

  if ($insertAt -ge $Lines.Count) {
    return $Lines + @(("## {0}: {1}" -f $Key, $Value))
  }

  $head = $Lines[0..($insertAt - 1)]
  $tail = $Lines[$insertAt..($Lines.Count - 1)]
  return @($head + @(("## {0}: {1}" -f $Key, $Value)) + $tail)
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$addonDir = Split-Path -Parent $scriptDir
$repoDir = Split-Path -Parent $addonDir

if (-not $TocPath -or $TocPath.Trim() -eq "") {
  $TocPath = Join-Path $addonDir "HarathUI.toc"
}

$resolvedToc = Resolve-Path -Path $TocPath -ErrorAction SilentlyContinue
if (-not $resolvedToc) {
  throw "TOC file not found: $TocPath"
}
$resolvedToc = $resolvedToc.Path

$lines = [System.IO.File]::ReadAllLines($resolvedToc)
if (-not $lines -or $lines.Count -eq 0) {
  throw "TOC file is empty: $resolvedToc"
}

$gitHead = $null
try {
  $gitHead = (& git -C $repoDir rev-parse --short=7 HEAD 2>$null)
  if ($LASTEXITCODE -ne 0) { $gitHead = $null }
} catch {
  $gitHead = $null
}
if ($gitHead) {
  $gitHead = $gitHead.Trim()
}

$currentVersion = Get-MetadataValue -Lines $lines -Key "Version"
$currentGitVersion = Get-MetadataValue -Lines $lines -Key "X-GitVersion"
$currentBuildCommit = Get-MetadataValue -Lines $lines -Key "X-Build-Commit"
$currentLatestCommit = Get-MetadataValue -Lines $lines -Key "X-Git-Commit"

if (-not $Version -or $Version.Trim() -eq "") {
  $Version = $currentVersion
}
if (-not $GitVersion -or $GitVersion.Trim() -eq "") {
  if ($currentGitVersion -and $currentGitVersion.Trim() -ne "") {
    $GitVersion = $currentGitVersion
  } else {
    $GitVersion = $Version
  }
}
if (-not $BuildCommit -or $BuildCommit.Trim() -eq "") {
  if ($gitHead -and $gitHead -ne "") {
    $BuildCommit = $gitHead
  } else {
    $BuildCommit = $currentBuildCommit
  }
}
if (-not $LatestCommit -or $LatestCommit.Trim() -eq "") {
  if ($BuildCommit -and $BuildCommit.Trim() -ne "") {
    # Keep latest commit aligned with stamped build commit unless explicitly overridden.
    $LatestCommit = $BuildCommit
  } elseif ($currentLatestCommit -and $currentLatestCommit.Trim() -ne "") {
    $LatestCommit = $currentLatestCommit
  } elseif ($gitHead -and $gitHead -ne "") {
    $LatestCommit = $gitHead
  }
}
if (-not $BuildDate -or $BuildDate.Trim() -eq "") {
  $BuildDate = (Get-Date).ToString("yyyy-MM-dd")
}

if (-not $Version -or $Version.Trim() -eq "") {
  throw "Version is required (missing existing Version metadata and no -Version passed)."
}
if (-not $GitVersion -or $GitVersion.Trim() -eq "") {
  throw "GitVersion is required (missing existing X-GitVersion metadata and no -GitVersion passed)."
}
if (-not $BuildCommit -or $BuildCommit.Trim() -eq "") {
  throw "BuildCommit is required (git unavailable and no existing X-Build-Commit metadata)."
}
if (-not $LatestCommit -or $LatestCommit.Trim() -eq "") {
  throw "LatestCommit is required (git unavailable and no existing X-Git-Commit metadata)."
}

$lines = Set-MetadataValue -Lines $lines -Key "Version" -Value $Version
$lines = Set-MetadataValue -Lines $lines -Key "X-GitVersion" -Value $GitVersion
$lines = Set-MetadataValue -Lines $lines -Key "X-Build-Commit" -Value $BuildCommit
$lines = Set-MetadataValue -Lines $lines -Key "X-Git-Commit" -Value $LatestCommit
$lines = Set-MetadataValue -Lines $lines -Key "X-Build-Date" -Value $BuildDate

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllLines($resolvedToc, $lines, $utf8NoBom)

Write-Host "Stamped metadata in $resolvedToc"
Write-Host ("  Version:        {0}" -f $Version)
Write-Host ("  X-GitVersion:   {0}" -f $GitVersion)
Write-Host ("  X-Build-Commit: {0}" -f $BuildCommit)
Write-Host ("  X-Git-Commit:   {0}" -f $LatestCommit)
Write-Host ("  X-Build-Date:   {0}" -f $BuildDate)
