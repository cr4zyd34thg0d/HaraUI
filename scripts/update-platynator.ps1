param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePath,
  [string]$Patch = 'platynator-no-friendly',
  [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$targetPath = Join-Path $repoRoot 'Platynator'

$resolvedSource = (Resolve-Path -Path $SourcePath).Path
if (-not (Test-Path -Path $resolvedSource -PathType Container)) {
  throw "Source path is not a folder: $SourcePath"
}
if (-not (Test-Path -Path (Join-Path $resolvedSource 'Platynator.toc') -PathType Leaf)) {
  throw "Source path does not look like a Platynator addon folder (missing Platynator.toc): $resolvedSource"
}

if (-not (Test-Path -Path $targetPath -PathType Container)) {
  throw "Target folder is missing: $targetPath"
}

Push-Location $repoRoot
try {
  Write-Host "Repo root:   $repoRoot"
  Write-Host "Source:      $resolvedSource"
  Write-Host "Destination: $targetPath"
  Write-Host "Patch:       $Patch"

  if ($DryRun) {
    Write-Host 'Dry run mode: no files will be copied.'
    & powershell -ExecutionPolicy Bypass -File "$repoRoot\scripts\reapply-local-patches.ps1" -Patch $Patch -VerifyOnly
    if ($LASTEXITCODE -ne 0) {
      throw "Patch verification failed for profile '$Patch'."
    }
    Write-Host 'Dry run completed successfully.'
    exit 0
  }

  Write-Host 'Mirroring upstream Platynator into repo...'
  & robocopy $resolvedSource $targetPath /MIR /XD ".git" ".github" ".vscode" "AssetsRaw" /XF ".pkgmeta" /R:2 /W:1 /NFL /NDL /NJH /NJS /NP
  $rc = $LASTEXITCODE
  if ($rc -gt 7) {
    throw "robocopy failed with exit code $rc"
  }

  Write-Host 'Reapplying local patch profile...'
  & powershell -ExecutionPolicy Bypass -File "$repoRoot\scripts\reapply-local-patches.ps1" -Patch $Patch
  if ($LASTEXITCODE -ne 0) {
    throw "Patch apply failed for profile '$Patch'."
  }

  Write-Host 'Running patch verification...'
  & powershell -ExecutionPolicy Bypass -File "$repoRoot\scripts\reapply-local-patches.ps1" -Patch $Patch -VerifyOnly
  if ($LASTEXITCODE -ne 0) {
    throw "Patch verification failed for profile '$Patch'."
  }

  Write-Host 'Update flow completed. Current git status:'
  & git status --short
}
finally {
  Pop-Location
}
