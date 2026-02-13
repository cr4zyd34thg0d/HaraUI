param(
  [string]$Patch = 'platynator-no-friendly',
  [switch]$List,
  [switch]$DryRun,
  [switch]$VerifyOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$patchMap = @{
  'platynator-no-friendly' = 'patches/platynator-no-friendly.patch'
}

function Test-PlatynatorNoFriendlyPatch {
  param([string]$Root)

  $checks = @(
    @{ Path = 'Platynator/Display/Initialize.lua'; Pattern = 'SetCVar\("nameplateShowAll"'; ExpectPresent = $false; Note = 'No global nameplateShowAll writes' },
    @{ Path = 'Platynator/Display/Initialize.lua'; Pattern = 'NamePlateType\.Friendly'; ExpectPresent = $false; Note = 'No friendly hit-test edits' },
    @{ Path = 'Platynator/Display/Initialize.lua'; Pattern = 'SetNamePlateFriendly'; ExpectPresent = $false; Note = 'No friendly size/click-through edits' },
    @{ Path = 'Platynator/Display/Initialize.lua'; Pattern = 'if not UnitCanAttack\("player", unit\) then'; ExpectPresent = $true; Note = 'Friendly units are skipped on install/hook' },
    @{ Path = 'Platynator/CustomiseDialog/Main.lua'; Pattern = 'friendlyInInstancesDropdown'; ExpectPresent = $false; Note = 'No friendly in-instance UI control' },
    @{ Path = 'Platynator/CustomiseDialog/Main.lua'; Pattern = 'ENABLE_FRIENDLY_NAMEPLATES'; ExpectPresent = $false; Note = 'No friendly module checkbox UI' },
    @{ Path = 'Platynator/Core/Initialize.lua'; Pattern = 'baseWidth = asset\.width or asset\.height or 0'; ExpectPresent = $true; Note = 'Rect calculation nil-width fix is present' },
    @{ Path = 'Platynator/Display/Widgets.lua'; Pattern = 'local function GetBarBackgroundDetails\('; ExpectPresent = $true; Note = 'Bar texture fallback helper is present' },
    @{ Path = 'Platynator/Display/Widgets.lua'; Pattern = 'Interface/AddOns/Platynator/Assets/Special/white\.png'; ExpectPresent = $true; Note = 'Bar texture nil-asset fallback is present' },
    @{ Path = 'Platynator/Display/Widgets.lua'; Pattern = 'local absorbDetails = GetBarBackgroundDetails\('; ExpectPresent = $true; Note = 'Absorb texture fallback is present' },
    @{ Path = 'Platynator/CustomiseDialog/ImportExport.lua'; Pattern = 'local function SanitizeImportedProfile'; ExpectPresent = $true; Note = 'Imported profile sanitizer is present' },
    @{ Path = 'Platynator/CustomiseDialog/ImportExport.lua'; Pattern = 'import\.show_friendly_in_instances_1 = "never"'; ExpectPresent = $true; Note = 'Imported friendly-instances settings are disabled' },
    @{ Path = 'Platynator/CustomiseDialog/ImportExport.lua'; Pattern = 'SanitizeImportedProfile\(import\)'; ExpectPresent = $true; Note = 'Profile import path applies sanitizer' }
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
  if ($Patch -eq 'platynator-no-friendly') {
    if (Test-PlatynatorNoFriendlyPatch -Root $repoRoot) {
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

  if ($Patch -eq 'platynator-no-friendly') {
    if (-not (Test-PlatynatorNoFriendlyPatch -Root $repoRoot)) {
      Write-Host 'Patch applied, but verification failed. Inspect files before release.' -ForegroundColor Red
      exit 1
    }
  }
}
finally {
  Pop-Location
}
