# Local Patch Profiles

This repo keeps local compatibility patches that can be reapplied after upstream addon updates.

## Patch names

- `platynator-no-friendly`
  - Removes Platynator's friendly nameplate functionality and UI controls.
  - Prevents Platynator from toggling global `nameplateShowAll`.
  - Keeps enemy nameplate functionality.
  - Includes the rect nil-width safety fix in `Platynator/Core/Initialize.lua`.
  - Sanitizes imported profiles to strip/disable incompatible friendly settings.

## Reapply command

From repo root:

```powershell
.\scripts\reapply-local-patches.ps1 -Patch platynator-no-friendly
```

## Useful options

```powershell
# List available patch profiles
.\scripts\reapply-local-patches.ps1 -List

# Verify patch state only (no file edits)
.\scripts\reapply-local-patches.ps1 -Patch platynator-no-friendly -VerifyOnly

# Dry run only (checks if patch can apply)
.\scripts\reapply-local-patches.ps1 -Patch platynator-no-friendly -DryRun
```

## Workflow after upstream update

1. Pull or replace updated addon files.
2. Run patch command above.
3. Check working tree and test in-game.
