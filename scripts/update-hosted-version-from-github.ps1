param(
  [string]$Owner = "cr4zyd34thg0d",
  [string]$Repo = "HaraUI",
  [string]$OutputPath,
  [string]$Token = $env:GITHUB_TOKEN
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-GitHubJson {
  param(
    [string]$Url,
    [string]$AuthToken
  )
  $headers = @{
    Accept = "application/vnd.github+json"
    "User-Agent" = "HaraUI-Release-Script"
  }
  if ($AuthToken -and $AuthToken.Trim() -ne "") {
    $headers["Authorization"] = "Bearer $AuthToken"
  }
  return Invoke-RestMethod -Method Get -Uri $Url -Headers $headers -TimeoutSec 30
}

function Normalize-VersionTag {
  param([string]$Tag)
  if (-not $Tag -or $Tag.Trim() -eq "") { return $null }
  $m = [regex]::Match($Tag, "(\d+(?:\.\d+)+)")
  if ($m.Success) {
    return $m.Groups[1].Value
  }
  return $Tag.Trim()
}

function To-LuaStringOrNil {
  param([string]$Value)
  if ($null -eq $Value -or $Value.Trim() -eq "") {
    return "nil"
  }
  $escaped = $Value.Replace('\', '\\').Replace('"', '\"')
  return "`"$escaped`""
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $scriptDir
if (-not $OutputPath -or $OutputPath.Trim() -eq "") {
  $OutputPath = Join-Path $repoDir "HarathUI\Generated\HostedVersion.lua"
}

$repoInfo = Invoke-GitHubJson -Url ("https://api.github.com/repos/{0}/{1}" -f $Owner, $Repo) -AuthToken $Token
$defaultBranch = [string]$repoInfo.default_branch
if (-not $defaultBranch -or $defaultBranch.Trim() -eq "") {
  $defaultBranch = "main"
}

$release = $null
$releaseTag = $null
$releaseDate = $null
try {
  $release = Invoke-GitHubJson -Url ("https://api.github.com/repos/{0}/{1}/releases/latest" -f $Owner, $Repo) -AuthToken $Token
  if ($release) {
    $releaseTag = [string]$release.tag_name
    $releaseDate = [string]$release.published_at
  }
} catch {
  Write-Warning ("Failed to query latest release for {0}/{1}: {2}" -f $Owner, $Repo, $_.Exception.Message)
}

$tags = @()
try {
  $tagsRaw = Invoke-GitHubJson -Url ("https://api.github.com/repos/{0}/{1}/tags?per_page=100" -f $Owner, $Repo) -AuthToken $Token
  if ($tagsRaw) {
    $tags = @($tagsRaw)
  }
} catch {
  Write-Warning ("Failed to query tags for {0}/{1}: {2}" -f $Owner, $Repo, $_.Exception.Message)
}

$selectedTag = $null
if (($releaseTag -and $releaseTag.Trim() -ne "") -and $tags.Count -gt 0) {
  foreach ($tag in $tags) {
    if ($tag.name -eq $releaseTag) {
      $selectedTag = $tag
      break
    }
  }
}
if (-not $selectedTag -and $tags.Count -gt 0) {
  $selectedTag = $tags[0]
}

$tagName = if ($selectedTag) { [string]$selectedTag.name } else { $null }
$version = Normalize-VersionTag -Tag $tagName
if ((-not $version -or $version.Trim() -eq "") -and $releaseTag -and $releaseTag.Trim() -ne "") {
  $version = Normalize-VersionTag -Tag $releaseTag
}

$fullCommit = if ($selectedTag) { [string]($selectedTag.commit.sha) } else { $null }
$commit = $null
if ($fullCommit -and $fullCommit.Trim() -ne "") {
  $trimmed = $fullCommit.Trim()
  $commit = if ($trimmed.Length -ge 7) { $trimmed.Substring(0, 7) } else { $trimmed }
}

$buildDate = $null
if ($releaseDate -and $releaseDate.Trim() -ne "") {
  try {
    $buildDate = ([DateTime]::Parse($releaseDate)).ToString("yyyy-MM-dd")
  } catch {
    $buildDate = $null
  }
}

$sourceLabel = if ($releaseTag -and $releaseTag.Trim() -ne "") {
  "GitHub release $releaseTag"
} elseif ($tagName -and $tagName.Trim() -ne "") {
  "GitHub tag $tagName"
} else {
  "GitHub branch $defaultBranch"
}

if ((-not $version -or $version.Trim() -eq "") -or (-not $commit -or $commit.Trim() -eq "")) {
  $commitsRaw = Invoke-GitHubJson -Url ("https://api.github.com/repos/{0}/{1}/commits?sha={2}&per_page=1" -f $Owner, $Repo, $defaultBranch) -AuthToken $Token
  $commits = @($commitsRaw)
  if ($commits.Count -gt 0) {
    $firstCommit = $commits[0]
    if ((-not $commit -or $commit.Trim() -eq "") -and $firstCommit.sha) {
      $sha = [string]$firstCommit.sha
      $commit = if ($sha.Length -ge 7) { $sha.Substring(0, 7) } else { $sha }
    }
    if ((-not $buildDate -or $buildDate.Trim() -eq "") -and $firstCommit.commit -and $firstCommit.commit.author -and $firstCommit.commit.author.date) {
      try {
        $buildDate = ([DateTime]::Parse([string]$firstCommit.commit.author.date)).ToString("yyyy-MM-dd")
      } catch {
        $buildDate = $null
      }
    }
  }
}

if (-not $version -or $version.Trim() -eq "") {
  try {
    $tocUrl = "https://raw.githubusercontent.com/{0}/{1}/{2}/HarathUI/HarathUI.toc" -f $Owner, $Repo, $defaultBranch
    $tocText = (Invoke-WebRequest -UseBasicParsing -Uri $tocUrl -TimeoutSec 30).Content
    $m = [regex]::Match($tocText, "(?im)^##\s*Version\s*:\s*(.+)$")
    if ($m.Success) {
      $version = $m.Groups[1].Value.Trim()
    }
  } catch {
    Write-Warning ("Failed to derive version from hosted TOC on branch '{0}': {1}" -f $defaultBranch, $_.Exception.Message)
  }
}

if (-not $version -or $version.Trim() -eq "") {
  throw ("Unable to derive hosted version from GitHub for {0}/{1}." -f $Owner, $Repo)
}

$content = @"
local ADDON, NS = ...
if not NS or type(NS.SetHostedVersionInfo) ~= "function" then return end

NS:SetHostedVersionInfo({
  version = $(To-LuaStringOrNil $version),
  commit = $(To-LuaStringOrNil $commit),
  buildDate = $(To-LuaStringOrNil $buildDate),
  sourceLabel = $(To-LuaStringOrNil $sourceLabel),
})
"@

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path -Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($OutputPath, $content, $utf8NoBom)

Write-Host ("Updated hosted version feed: {0}" -f $OutputPath)
Write-Host ("  Source:    {0}" -f $sourceLabel)
Write-Host ("  Version:   {0}" -f $version)
if ($commit -and $commit.Trim() -ne "") {
  Write-Host ("  Commit:    {0}" -f $commit)
} else {
  Write-Host "  Commit:    n/a"
}
if ($buildDate -and $buildDate.Trim() -ne "") {
  Write-Host ("  BuildDate: {0}" -f $buildDate)
} else {
  Write-Host "  BuildDate: n/a"
}
