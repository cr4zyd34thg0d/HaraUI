# AGENTS.md — HarathUI

## Scope
These instructions apply to this addon folder only.

## Priorities
- Preserve existing behavior; avoid sweeping refactors.
- Prefer minimal, targeted fixes over large rewrites.
- Keep Lua style consistent with the surrounding file.

## Workflow
- Search with `rg` for related modules and CVars before changing code.
- When touching module toggles, verify both Apply() and Disable() paths.
- Prefer small edits in existing files over new files.

## WoW AddOn notes
- This is a retail WoW addon.
- Avoid taint: do not modify protected frames or CVars in combat unless safe.
- If a change involves CVars, handle combat lockdown and restore on disable.

## Testing
- Use `/reload` after changes.
- If a module is toggleable, test: enable -> disable -> enable.
- Verify Blizzard UI elements are restored on disable.

## Communication
- Summarize changes by file path and intent.
- Call out any risks (e.g., combat lockdown timing).
