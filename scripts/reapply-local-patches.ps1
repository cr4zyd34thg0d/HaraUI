param(
  [string]$Patch = 'platynator-tahoma-override',
  [switch]$List,
  [switch]$DryRun,
  [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchMap = @{
  'platynator-tahoma-override' = 'patches/platynator-tahoma-override.patch'
}

function Test-PlatynatorTahomaOverridePatch {
  param([string]$Root)

  $checks = @(
    @{ Path = 'Platynator/Core/Config.lua'; Pattern = 'FRIENDLY_NAME_ONLY_FONT_OVERRIDE'; ExpectPresent = $true; Note = 'Config option for font override is present' },
    @{ Path = 'Platynator/Locales.lua'; Pattern = 'FRIENDLY_NAME_ONLY_FONT_OVERRIDE.*Overwrite to Tahoma'; ExpectPresent = $true; Note = 'Locale string for font override is present' },
    @{ Path = 'Platynator/CustomiseDialog/Main.lua'; Pattern = 'friendlyFontOverride'; ExpectPresent = $true; Note = 'Checkbox UI for font override is present' },
    @{ Path = 'Platynator/Display/Initialize.lua'; Pattern = 'FRIENDLY_NAME_ONLY_FONT_OVERRIDE'; ExpectPresent = $true; Note = 'Font override logic in UpdateFriendlyFont is present' },
    @{ Path = 'Platynator/Display/Initialize.lua'; Pattern = 'Tahoma Bold'; ExpectPresent = $true; Note = 'Tahoma Bold font reference is present' },
    @{ Path = 'Platynator/Design.lua'; Pattern = '_name-only-no-guild'; ExpectPresent = $true; Note = 'Name Only (No Guild) style is present' },
    @{ Path = 'Platynator/Locales.lua'; Pattern = 'NAME_ONLY_NO_GUILD'; ExpectPresent = $true; Note = 'Locale string for Name Only (No Guild) is present' }
  )

  $ok = $true
  foreach ($check in $checks) {
    $fullPath = Join-Path $Root $check.Path
    if (-not (Test-Path $fullPath)) {
      Write-Host "[FAIL] Missing file: $($check.Path)" -ForegroundColor Red
      $ok = $false
      continue
    }

    $found = Select-String -Path $fullPath -Pattern $check.Pattern -Quiet
    if ($check.ExpectPresent -and -not $found) {
      Write-Host "[FAIL] $($check.Note)" -ForegroundColor Red
      $ok = $false
    } elseif (-not $check.ExpectPresent -and $found) {
      Write-Host "[FAIL] $($check.Note)" -ForegroundColor Red
      $ok = $false
    } else {
      Write-Host "[OK]   $($check.Note)" -ForegroundColor Green
    }
  }

  return $ok
}

if ($List) {
  Write-Host 'Available patches:'
  $patchMap.Keys | Sort-Object | ForEach-Object { Write-Host " - $_" }
  exit 0
}

if (-not $patchMap.ContainsKey($Patch)) {
  Write-Host "Unknown patch profile: $Patch" -ForegroundColor Red
  Write-Host 'Use -List to see valid names.'
  exit 1
}

if ($VerifyOnly) {
  if ($Patch -eq 'platynator-tahoma-override') {
    if (Test-PlatynatorTahomaOverridePatch -Root $repoRoot) {
      exit 0
    }
    exit 1
  }
}

$patchRelPath = $patchMap[$Patch]
$patchPath = Join-Path $repoRoot $patchRelPath
if (-not (Test-Path $patchPath)) {
  Write-Host "Patch file not found: $patchRelPath" -ForegroundColor Red
  exit 1
}

Push-Location $repoRoot
try {
  if ($DryRun) {
    & git apply --check $patchRelPath
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Dry run succeeded for $Patch" -ForegroundColor Green
      exit 0
    }

    & git apply --3way --check $patchRelPath
    if ($LASTEXITCODE -eq 0) {
      Write-Host "Dry run (3-way) succeeded for $Patch" -ForegroundColor Green
      exit 0
    }

    Write-Host "Dry run failed for $Patch" -ForegroundColor Red
    exit 1
  }

  & git apply $patchRelPath
  if ($LASTEXITCODE -ne 0) {
    Write-Host "Direct apply failed, trying 3-way merge..." -ForegroundColor Yellow
    & git apply --3way $patchRelPath
    if ($LASTEXITCODE -ne 0) {
      Write-Host "Failed to apply patch: $Patch" -ForegroundColor Red
      exit 1
    }
  }

  Write-Host "Applied patch profile: $Patch" -ForegroundColor Green

  if ($Patch -eq 'platynator-tahoma-override') {
    if (-not (Test-PlatynatorTahomaOverridePatch -Root $repoRoot)) {
      Write-Host 'Patch applied, but verification failed. Inspect files before release.' -ForegroundColor Red
      exit 1
    }
  }
}
finally {
  Pop-Location
}
