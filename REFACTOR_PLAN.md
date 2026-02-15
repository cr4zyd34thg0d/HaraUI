# HaraUI 2.0 Refactor Plan

---

## 1. Current State Hypothesis

HaraUI is a ~15,000-line WoW Retail addon with 12 feature modules, a custom options UI, and bundled libraries. It's already partially refactored on the `refactor/haraui-2.0` branch (Core/ and Options/ extractions are done). Here is what I observe:

**Architecture:**
- **Flat namespace (`NS`)** serves as service locator, config store, module registry, and utility bag. Every file receives it via `local ADDON, NS = ...` and hangs state off it.
- **Module contract** is informal: `M.active`, `M:Apply()`, `M:Disable()`, `M:SetLocked()`, `M:Preview()`. Modules self-register via `NS:RegisterModule(name, M)`. There is no enforced interface — some modules omit `Preview`, some omit `SetLocked`.
- **Event handling** is per-module: each module creates its own `CreateFrame("Frame")` for event dispatch. There is no shared event bus; Core.lua's frame handles only startup + version-comm events.
- **Options UI** passes 10+ positional arguments to each page builder function (e.g. `Pages.BuildCastPage(pages, content, MakeModuleHeader, BuildStandardModuleCards, ApplyToggleSkin, MakeCheckbox, MakeButton, ...)`). This is the dominant source of coupling/fragility in the options layer.
- **CharacterSheet.lua** is 7,648 lines — half the entire addon. It contains its own layout engine, tooltip system, M+ renderer, gear display, stats panel, right-panel vault, and recursive-guard infrastructure. Multiple recent commits (5+) fix reentrancy loops.
- **SavedVariables** use a home-grown `DeepCopyDefaults` merge with additive migrations. Backward-compatible, but fragile — no schema validation, no per-module migration hooks.
- **Shared code is minimal:** `UIHelpers.lua` exports only `Clamp`. Common patterns (font application, frame creation with backdrop, event frame creation, debounced timers) are re-implemented in every module.

**Key Assumptions:**
1. The branch already has the Core/ and Options/ extraction done; those splits are stable.
2. CharacterSheet is the primary source of bugs and complexity.
3. The options UI's positional-argument threading is the biggest maintainability pain outside CharacterSheet.
4. No module currently lazy-loads; all 12 run their file-level code at addon load time.
5. All user-facing behavior (fonts, sizes, colors, layouts, animations, defaults) is the golden master and must not change.

---

## 2. Golden Master Checklist — What Must NOT Change

| Area | Invariant |
|------|-----------|
| **XP/Rep Bar** | Position, size, colors, text format, session rate display, hide-at-max behavior |
| **Cast Bar** | Position, size, colors, icon/shield/spark appearance, empower stage rendering |
| **Character Sheet** | Full custom layout, gear display, stats panel, right panel (vault/M+), tab switching behavior, model display |
| **Friendly Nameplates** | Font, size, class-color option, CVar backup/restore on enable/disable |
| **Rotation Helper** | Icon size, keybind text, C_AssistedCombat integration |
| **Minimap Bar** | Button discovery, ignore list, popout behavior, orientation, sizing |
| **Loot Toasts** | Toast appearance, pooling, item/money/currency parsing, stacking direction |
| **Game Menu** | Scale factor, resolution tracking |
| **Summons** | Auto-accept behavior, combat lockdown deferral |
| **CopyBattleTag** | Context menu integration |
| **Options UI** | All pages, all controls, nav bar, theme color picker, version indicator, preview buttons |
| **SavedVariables** | `HaraUI_DB` structure, all existing keys, migration compatibility |
| **Slash Commands** | `/hui`, `/haraui` |
| **Fonts/Media** | All 19 registered fonts, all textures, logo |
| **Frame Positions** | All saved anchor/x/y positions per module |

---

## 3. Sequential Refactor Plan

---

### Step 1 — Shared Utilities: Extract Common Patterns

**Objective:** Create a small `Shared/Frames.lua` and expand `Shared/UIHelpers.lua` with patterns that are duplicated across 5+ modules, reducing copy-paste and giving future steps a stable foundation.

**Files Impacted:**
- `Shared/UIHelpers.lua` (expand)
- NEW: `Shared/Frames.lua`
- `HaraUI.toc` (add new file to load order, after UIHelpers.lua)

**Tasks:**
1. Add to `UIHelpers.lua`:
   - `NS.UIHelpers.DebouncedTimer(interval, callback)` — returns a trigger function that coalesces calls within `interval` seconds. Replaces the hand-rolled debounce in XPBar, FriendlyNameplates, MinimapBar, LootToasts.
   - `NS.UIHelpers.ShallowCopy(t)` — single-level table copy (used in several modules for color tables).
2. Create `Shared/Frames.lua`:
   - `NS.Frames.CreateEventFrame(owner)` — creates a frame, returns it. Standardizes the `CreateFrame("Frame")` + SetScript("OnEvent") pattern.
   - `NS.Frames.SafeHide(frame)` / `NS.Frames.SafeShow(frame)` — nil-safe show/hide.
   - `NS.Frames.ApplyFont(fs, size, flags)` — thin wrapper around `NS:ApplyDefaultFont` that nil-checks (eliminates the per-module `ApplyBarFont`/`ApplyToastFont` wrappers).
3. Add `Shared/Frames.lua` to TOC after `Shared/UIHelpers.lua`.
4. Do NOT convert any module to use these yet — that happens in later steps.

**Acceptance Checks:**
- Addon loads without errors.
- `/hui` opens the options panel.
- No visual changes anywhere.
- New utilities are callable: `/run HaraUI_Test = NS.UIHelpers.DebouncedTimer ~= nil` (via debug).

**Diff Budget:** ~80 lines added across 2 files + 1 TOC line. No module files touched.

**Risk Level:** **Low.** Additive only — no existing code is modified.

**Rollback:** `git revert` the single commit; remove the TOC line.

---

### Step 2 — Module Base Mixin: Formalize the Module Contract

**Objective:** Create a lightweight mixin table (`NS.ModuleBase`) that provides default no-op implementations of the module interface methods, plus a standard `CreateEventFrame` helper. Modules that opt in get consistent behavior without boilerplate.

**Files Impacted:**
- NEW: `Core/ModuleBase.lua`
- `HaraUI.toc` (add after Core.lua, before Compat.lua)

**Tasks:**
1. Create `Core/ModuleBase.lua`:
   ```lua
   NS.ModuleBase = {
     active = false,
     Apply = function(self) end,
     Disable = function(self) end,
     SetLocked = function(self, locked) end,
     Preview = function(self) end,
   }
   function NS:NewModule(name)
     local M = setmetatable({}, { __index = NS.ModuleBase })
     NS:RegisterModule(name, M)
     return M
   end
   ```
2. `NS:NewModule(name)` creates, registers, and returns a module table with the mixin as metatable fallback.
3. Existing `NS:RegisterModule` remains unchanged — `NewModule` is opt-in sugar.
4. Do NOT convert any modules yet.

**Acceptance Checks:**
- Addon loads; all 12 modules still work (they still use the old `RegisterModule` path).
- `NS.ModuleBase` exists and has the expected keys.

**Diff Budget:** ~30 lines in 1 new file + 1 TOC line.

**Risk Level:** **Low.** Purely additive.

**Rollback:** Revert commit; remove TOC line.

---

### Step 3 — Options Dependency Injection: Replace Positional Args with Context Table

**Objective:** Eliminate the 10-15 positional arguments threaded through every `Pages.Build*Page()` call by passing a single `ctx` table. This is the highest-impact maintainability fix outside CharacterSheet.

**Files Impacted:**
- `Options.lua` (build the `ctx` table, change all `Pages.Build*` calls)
- `Options/Pages/General.lua`
- `Options/Pages/XP.lua`
- `Options/Pages/Cast.lua`
- `Options/Pages/Friendly.lua`
- `Options/Pages/Rotation.lua`
- `Options/Pages/Minimap.lua`
- `Options/Pages/Loot.lua`

**Tasks:**
1. In `Options.lua`, after the local alias block (lines 63-87), build a context table:
   ```lua
   local ctx = {
     db = db,
     NS = NS,
     Theme = Theme,
     Widgets = Widgets,
     ORANGE = ORANGE,
     -- all widget/theme functions...
   }
   ```
2. Change each `Pages.Build*Page(...)` call to `Pages.Build*Page(pages, content, ctx)`.
3. In each page file, update the function signature to `function Pages.Build*Page(pages, content, ctx)` and destructure `ctx` at the top of the function body into locals.
4. Keep `BuildStandardModuleCards` and `BuildStandardSliderRow` as they are — they move into `ctx` as well.
5. Each page file change is mechanical: replace parameter names with `ctx.X` references at the function top, then use the same locals throughout the body.

**Acceptance Checks:**
- Options panel opens with no errors.
- Every page renders identically (screenshot compare).
- Every toggle, slider, color picker, and preview button works.
- Theme color change propagates to all elements.

**Diff Budget:** ~200 lines changed across 8 files. No module (Modules/) files touched.

**Risk Level:** **Medium.** Touches every options page. Mitigate by doing one page at a time within the commit, testing after each.

**Rollback:** Revert the commit. The old positional-arg signatures are restored.

---

### Step 4 — Convert Simple Modules to Use Shared Utilities

**Objective:** Replace duplicated patterns in the 6 simplest modules with the shared utilities from Step 1, reducing boilerplate.

**Files Impacted:**
- `Modules/Summons.lua`
- `Modules/SmallerGameMenu.lua`
- `Modules/CopyBattleTag.lua`
- `Modules/TrackedBars.lua`
- `Modules/Fonts.lua`
- `Modules/RotationHelper.lua`
- `Modules/RotationHelper.Keybinds.lua`

**Tasks:**
1. Replace hand-rolled `CreateFrame("Frame")` + `SetScript("OnEvent")` with `NS.Frames.CreateEventFrame()` where applicable.
2. Replace per-module font wrappers (if any) with `NS.Frames.ApplyFont()`.
3. Optionally convert to `NS:NewModule(name)` from Step 2 (only if the module currently lacks `SetLocked`/`Preview` — the mixin provides safe no-ops).
4. Each module is a separate sub-commit within one overall commit.

**Acceptance Checks:**
- Each module's Apply/Disable/SetLocked/Preview still works.
- Summons auto-accepts.
- Game menu scales correctly.
- CopyBattleTag context menu appears.
- Rotation helper shows keybind.

**Diff Budget:** ~50 lines net reduction across 7 files. No new files.

**Risk Level:** **Low.** These are the smallest, simplest modules.

**Rollback:** Revert the commit.

---

### Step 5 — Convert Medium Modules to Use Shared Utilities

**Objective:** Same as Step 4 but for the mid-complexity modules: XPBar, CastBar, LootToasts, FriendlyNameplates.

**Files Impacted:**
- `Modules/XPBar.lua`
- `Modules/CastBar.lua`
- `Modules/LootToasts.lua`
- `Modules/FriendlyNameplates.lua`

**Tasks:**
1. Replace `ApplyBarFont` / `ApplyToastFont` wrappers with `NS.Frames.ApplyFont()`.
2. Replace hand-rolled debounce timers with `NS.UIHelpers.DebouncedTimer()`.
3. Replace hand-rolled event frame creation with `NS.Frames.CreateEventFrame()`.
4. Do NOT change any visual output, event registration list, or update logic.
5. Each module is a separate sub-commit.

**Acceptance Checks:**
- XP bar shows correct XP/rep/quest/rested values.
- Cast bar renders casts, channels, empowers correctly.
- Loot toasts appear for items, money, currency.
- Friendly nameplates styled correctly with class colors.

**Diff Budget:** ~80 lines net reduction across 4 files.

**Risk Level:** **Medium.** These modules have more state. Mitigate by testing each independently.

**Rollback:** Revert the commit.

---

### Step 6 — MinimapBar: Extract Ignore List to Data + Simplify Tickers

**Objective:** Clean up the second-largest module (1,108 lines) without splitting it.

**Files Impacted:**
- `Modules/MinimapBar.lua`

**Tasks:**
1. Extract the 63-item ignore list from inline code into a `local IGNORE_LIST = { ... }` table at the top of the file (it may already be partially this way — just ensure it's a clean data table, not built procedurally).
2. Replace hand-rolled ticker management with `NS.UIHelpers.DebouncedTimer()` where applicable.
3. Replace per-module font wrapper with `NS.Frames.ApplyFont()`.
4. Add a brief module-header comment block matching the pattern in XPBar/CastBar.
5. Do NOT change button discovery logic, popout behavior, or any visual output.

**Acceptance Checks:**
- Minimap bar appears with correct buttons.
- Popout hover works.
- Button ignore list still filters correctly.
- Orientation toggle works.

**Diff Budget:** ~40 lines net change in 1 file.

**Risk Level:** **Low-Medium.** Single file, but complex state. Test popout carefully.

**Rollback:** Revert the commit.

---

### Step 7 — CharacterSheet: Extract Guard Infrastructure

**Objective:** Move the recursion-guard and deferred-refresh infrastructure out of CharacterSheet.lua into a dedicated file, so it can be understood, tested, and maintained independently. This is the first of several CharacterSheet decomposition steps.

**Files Impacted:**
- NEW: `Modules/CharacterSheet/Guards.lua`
- `Modules/CharacterSheet.lua` (replace inline guard code with requires)
- `HaraUI.toc` (add new file before CharacterSheet.lua)

**Tasks:**
1. Create `Modules/CharacterSheet/` directory.
2. Extract into `Guards.lua`:
   - `IN_NATIVE_VIS_SWITCH` counter and `RunWithNativeVisGuard(fn)`
   - `QueueDeferredRefreshAfterNativeVisSwitch()` (will need `M` and `S` passed as upvalues or params)
   - `IsModeSwitchGuardActive()` and `RunWithModeSwitchGuard(fn)`
   - The `S.refreshInProgress` / `S.refreshQueuedAfterCurrent` / `S.lastRefreshFrame` / `S.openToken` gate logic
3. Expose via a returned table: `NS.CharSheetGuards = { ... }`.
4. In `CharacterSheet.lua`, replace the inline definitions with references to `NS.CharSheetGuards.*`.
5. Keep all call sites identical — just change where the functions are defined.

**Acceptance Checks:**
- Character sheet opens via keybind (Shift-C) 10x without freeze.
- Character tab click, Rep tab, Currency tab all work.
- No Lua errors on open/close/switch.
- Guard behavior is bit-identical (same deferred timing, same token checks).

**Diff Budget:** ~120 lines moved (not new) into Guards.lua. CharacterSheet.lua shrinks by ~100 lines. Net new: ~20 lines of wiring.

**Risk Level:** **Medium-High.** Guard code is the most fragile part of the addon. Mitigate by: (a) extracting verbatim, not rewriting; (b) testing Shift-C 10x immediately after.

**Rollback:** Revert the commit; Guards.lua deleted, inline code restored.

---

### Step 8 — CharacterSheet: Extract Right Panel (Vault/M+)

**Objective:** Move the right panel (Great Vault, M+ display) into its own file. This is a large, self-contained feature within CharacterSheet.

**Files Impacted:**
- NEW: `Modules/CharacterSheet/RightPanel.lua`
- `Modules/CharacterSheet.lua` (remove right panel code, call into RightPanel)
- `HaraUI.toc`

**Tasks:**
1. Identify all functions and state related to the right panel (likely prefixed `RP.` or containing "RightPanel", "Vault", "MPlus", "Affix").
2. Move them to `RightPanel.lua`, exposed via `NS.CharSheetRightPanel = { ... }`.
3. Move associated state variables from `S` into the new file's local state.
4. In CharacterSheet.lua, replace calls with `NS.CharSheetRightPanel.X()`.
5. Keep the right panel's show/hide tied to the same triggers.

**Acceptance Checks:**
- Right panel appears when Character Sheet opens (if enabled).
- Vault data displays correctly.
- M+ affix data displays correctly.
- Detached mode works.
- Right panel hides on CharacterFrame hide.

**Diff Budget:** ~800-1200 lines moved out of CharacterSheet.lua. ~30 lines of new wiring.

**Risk Level:** **High.** Large extraction from the most complex file. Mitigate by: (a) grepping for every reference before cutting; (b) testing all right panel states (attached/detached/hidden).

**Rollback:** Revert the commit.

---

### Step 9 — CharacterSheet: Extract Gear Display

**Objective:** Move gear slot layout, slot skinning, and item tooltip logic into its own file.

**Files Impacted:**
- NEW: `Modules/CharacterSheet/GearDisplay.lua`
- `Modules/CharacterSheet.lua`
- `HaraUI.toc`

**Tasks:**
1. Extract: `StylePaperDollSlots`, `ApplyChonkySlotLayout`, `UpdateCustomGearFrame`, slot skin state, item tooltip cache, enchant quality logic.
2. Expose via `NS.CharSheetGear = { ... }`.
3. Wire calls in CharacterSheet.lua.

**Acceptance Checks:**
- All gear slots render with correct icons, borders, enchant text.
- Item tooltips show on hover.
- Slot positions match golden master exactly.

**Diff Budget:** ~800-1000 lines moved. ~20 lines new wiring.

**Risk Level:** **High.** Gear display is tightly integrated with layout. Mitigate by extracting conservatively — if a function touches both gear and layout, leave it in the main file.

**Rollback:** Revert the commit.

---

### Step 10 — CharacterSheet: Extract Stats Panel

**Objective:** Move the custom stats frame (stat rows, stat sections, mode buttons) into its own file.

**Files Impacted:**
- NEW: `Modules/CharacterSheet/StatsPanel.lua`
- `Modules/CharacterSheet.lua`
- `HaraUI.toc`

**Tasks:**
1. Extract: `UpdateCustomStatsFrame`, stat row creation, stat section layout, stats mode button logic, sidebar buttons.
2. Expose via `NS.CharSheetStats = { ... }`.
3. Wire calls in CharacterSheet.lua.

**Acceptance Checks:**
- Stats panel renders all stat categories.
- Mode switching (if applicable) works.
- Stat values update on equipment change.

**Diff Budget:** ~600-800 lines moved. ~20 lines new wiring.

**Risk Level:** **High.** Same as Step 9. Mitigate identically.

**Rollback:** Revert the commit.

---

### Step 11 — CharacterSheet: Clean Up Remaining Main File

**Objective:** After Steps 7-10, CharacterSheet.lua should be ~3,000-4,000 lines. This step cleans up the remaining code: layout engine, model display, tab switching, the Apply/Disable/Refresh orchestration.

**Files Impacted:**
- `Modules/CharacterSheet.lua`

**Tasks:**
1. Review remaining code for dead locals, orphaned state variables, and commented-out blocks.
2. Add a module-header comment block documenting the subfile structure.
3. Ensure all cross-file calls are consistent (all go through `NS.CharSheet*` tables).
4. Add `-- TODO` markers for any remaining complexity hotspots.
5. Do NOT split further — diminishing returns.

**Acceptance Checks:**
- Full character sheet functionality works.
- Shift-C 10x test passes.
- All tabs work.
- No dead code warnings.

**Diff Budget:** ~50-100 lines removed/cleaned. No new files.

**Risk Level:** **Low-Medium.** Just cleanup, not restructuring.

**Rollback:** Revert the commit.

---

### Step 12 — Event Registration Audit & Cleanup

**Objective:** Audit all 83 event registrations across the addon. Ensure no module re-registers events on every `Apply()` call without first unregistering, and that disabled modules unregister their events.

**Files Impacted:**
- Potentially all module files (but likely only 3-4 need fixes).

**Tasks:**
1. Grep for `RegisterEvent` across all modules.
2. For each module, verify:
   - Events are registered once (in Apply or at file scope), not re-registered on every Apply.
   - `Disable()` unregisters events (or hides the event frame, which stops dispatch).
3. Fix any modules that re-register without guarding.
4. Document event registrations in each module's header comment.

**Acceptance Checks:**
- No duplicate event registrations (verify via `/dump` or debug logging).
- Disabling a module via options stops its event processing.
- Enabling it again restores event processing.

**Diff Budget:** ~30-50 lines across 3-4 files.

**Risk Level:** **Low.** Read-heavy audit with small fixes.

**Rollback:** Revert the commit.

---

### Step 13 — SavedVariables: Add Per-Module Migration Hooks

**Objective:** Allow individual modules to register their own migration rules, so future module changes don't require editing `Core.lua`.

**Files Impacted:**
- `Core.lua` (add migration hook registry)
- `SavedVariables.lua` (no changes — defaults stay as-is)

**Tasks:**
1. Add to Core.lua:
   ```lua
   NS._moduleMigrations = {}
   function NS:RegisterMigration(version, fn)
     NS._moduleMigrations[version] = NS._moduleMigrations[version] or {}
     table.insert(NS._moduleMigrations[version], fn)
   end
   ```
2. In `RunDBMigrations`, after the core rules, iterate `NS._moduleMigrations` for any version > currentVersion.
3. Do NOT convert existing rules — they stay in Core.lua. This is for future use.

**Acceptance Checks:**
- Existing migrations still run correctly.
- New migration hook is callable (test via debug).
- DB structure unchanged for existing users.

**Diff Budget:** ~25 lines in Core.lua.

**Risk Level:** **Low.** Additive only.

**Rollback:** Revert the commit.

---

### Step 14 — Final Sweep: TOC Ordering, Dead Code, Documentation

**Objective:** Final cleanup pass. Ensure TOC load order is correct for all new files, remove any dead code discovered during the refactor, and add minimal inline documentation.

**Files Impacted:**
- `HaraUI.toc`
- Various files (minor cleanups only)

**Tasks:**
1. Verify TOC load order: Shared/ → Core/ (including ModuleBase, CharacterSheet subfiles) → Options/ → Modules/.
2. Grep for any `NS.CharSheet*` references that don't resolve.
3. Remove any truly dead locals or functions discovered during prior steps (mark with `-- REMOVED in 2.0 refactor` comment if uncertain).
4. Add a brief `-- Architecture` comment block at the top of Core.lua describing the module system.
5. Do NOT add README or external documentation files.

**Acceptance Checks:**
- Full addon loads with no errors.
- All 12 modules work.
- Options panel fully functional.
- No stale references.

**Diff Budget:** ~50 lines across 5-6 files.

**Risk Level:** **Low.**

**Rollback:** Revert the commit.

---

## 4. Definition of Done

| # | Criterion | Verification |
|---|-----------|-------------|
| 1 | Addon loads without Lua errors | `/console scriptErrors 1`, reload UI, check for errors |
| 2 | All 12 modules Apply/Disable correctly | Toggle each via options, verify enable/disable |
| 3 | Options panel fully functional | Open every page, toggle every control, move every slider |
| 4 | Character Sheet stable | Shift-C 10x, tab cycling, right panel attach/detach |
| 5 | SavedVariables backward-compatible | Copy a pre-refactor `HaraUI_DB.lua` into SavedVariables/, load, verify no data loss |
| 6 | No visual regressions | Screenshot comparison of every module against golden master |
| 7 | Frame positions preserved | Existing anchor/x/y values load correctly |
| 8 | CharacterSheet.lua < 4,000 lines | `wc -l` check |
| 9 | No positional-arg threading in Options pages | Grep for the old signatures — should be zero matches |
| 10 | Every module has header comment documenting interface + events | Grep for `Interface:` block in each module |
| 11 | All commits individually loadable | `git stash && git checkout <commit> && /reload` for each step |
| 12 | No dead NS.* references | `grep -r 'NS\.' | sort -u` and verify all resolve |
