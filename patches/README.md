# Local Patch Profiles

This repo keeps local compatibility patches that can be reapplied after upstream addon updates.

## Patch names

- `platynator-tahoma-override`
  - Adds a "Overwrite to Tahoma" checkbox under the "Show friendly in instances" dropdown.
  - When enabled, the friendly "Name only (players)" font uses Tahoma Bold instead of the profile's default.
  - Adds a "Name Only (No Guild)" built-in style using Tahoma Bold.
  - No upstream functionality is removed — all original friendly nameplate features remain intact.

## Reapply command

From repo root:

```powershell
.\scripts\reapply-local-patches.ps1 -Patch platynator-tahoma-override
```

## Useful options

```powershell
# List available patch profiles
.\scripts\reapply-local-patches.ps1 -List

# Verify patch state only (no file edits)
.\scripts\reapply-local-patches.ps1 -Patch platynator-tahoma-override -VerifyOnly

# Dry run only (checks if patch can apply)
.\scripts\reapply-local-patches.ps1 -Patch platynator-tahoma-override -DryRun
```

## Workflow after upstream update

1. Pull or replace updated addon files.
2. Run patch command above.
3. Check working tree and test in-game.
