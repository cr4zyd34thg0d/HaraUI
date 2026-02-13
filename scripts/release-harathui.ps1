param(
  [string]$Version,
  [string]$GitVersion,
  [string]$CommitRef = "HEAD",
  [string]$LatestCommit,
  [string]$TocPath,
  [string]$GitHubOwner = "cr4zyd34thg0d",
  [string]$GitHubRepo = "HaraUI",
  [string]$GitHubToken = $env:GITHUB_TOKEN,
  [switch]$SkipGitHubHostedSync,
  [switch]$RequireGitHubHostedSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Split-Path -Parent $scriptDir
$stampScript = Join-Path $repoDir "HarathUI\tools\stamp-version-metadata.ps1"
$hostedScript = Join-Path $repoDir "scripts\update-hosted-version-from-github.ps1"

if (-not (Test-Path -Path $stampScript)) {
  throw "Missing stamp script: $stampScript"
}

$buildCommit = (& git -C $repoDir rev-parse --short=7 $CommitRef 2>$null)
if ($LASTEXITCODE -ne 0 -or -not $buildCommit) {
  throw "Unable to resolve git commit for ref '$CommitRef'."
}
$buildCommit = $buildCommit.Trim()

if (-not $LatestCommit -or $LatestCommit.Trim() -eq "") {
  $LatestCommit = $buildCommit
}

$args = @(
  "-ExecutionPolicy", "Bypass",
  "-File", $stampScript,
  "-BuildCommit", $buildCommit,
  "-LatestCommit", $LatestCommit
)

if ($Version -and $Version.Trim() -ne "") {
  $args += @("-Version", $Version)
}
if ($GitVersion -and $GitVersion.Trim() -ne "") {
  $args += @("-GitVersion", $GitVersion)
}
if ($TocPath -and $TocPath.Trim() -ne "") {
  $args += @("-TocPath", $TocPath)
}

Write-Host ("Stamping HarathUI metadata from ref '{0}' ({1})..." -f $CommitRef, $buildCommit)
& powershell @args

if (-not $SkipGitHubHostedSync) {
  if (-not (Test-Path -Path $hostedScript)) {
    if ($RequireGitHubHostedSync) {
      throw "Missing hosted-version sync script: $hostedScript"
    }
    Write-Warning "Hosted-version sync script not found; skipping GitHub feed update."
  } else {
    Write-Host ("Syncing hosted version feed from GitHub ({0}/{1})..." -f $GitHubOwner, $GitHubRepo)
    try {
      $hostedArgs = @(
        "-ExecutionPolicy", "Bypass",
        "-File", $hostedScript,
        "-Owner", $GitHubOwner,
        "-Repo", $GitHubRepo
      )
      if ($GitHubToken -and $GitHubToken.Trim() -ne "") {
        $hostedArgs += @("-Token", $GitHubToken)
      }
      & powershell @hostedArgs
    } catch {
      if ($RequireGitHubHostedSync) {
        throw
      }
      Write-Warning ("GitHub hosted-version sync failed: {0}" -f $_.Exception.Message)
    }
  }
}

Write-Host ""
Write-Host "Release metadata updated."
Write-Host "Recommended next step: package and distribute this exact working tree."
