# HaraUI

## [v2.1.1-alpha](https://github.com/cr4zyd34thg0d/HaraUI/tree/v2.1.1-alpha) (2026-02-18)
[Full Changelog](https://github.com/cr4zyd34thg0d/HaraUI/commits/v2.1.1-alpha)

- fix(stats): resolve "Primary" label bug when SPEC_STAT_STRINGS is unavailable
    Fallback to class-based stat detection now triggers when the label is
    still "Primary", not just when the value is zero.
- fix(taint): guard StatusTrackingBarManager:EnableMouse() against combat lockdown
    Wrap protected calls on Blizzard XP bar frames with InCombatLockdown
    check and pcall to prevent ADDON_ACTION_BLOCKED errors.
- fix(taint): guard CharacterFrame SetAttribute and UpdateUIPanelPositions in combat
    Skip UIPanelLayout attribute writes and panel manager relayout during
    combat lockdown to prevent frame squishing and taint propagation.
- fix(taint): sanitize CHAT_MSG event args with tostring() to strip secret string taint
- feat(gems): dynamic socket item tooltips based on expansion, slot, and PvP context
    Missing-socket indicators now resolve the correct socket-adding item
    (Magnificent Jeweler's Setting, Technomancer's Gift, Forged Jeweler's
    Setting) by checking the equipped item's expansion ID and PvP status.
    Item names are fetched via GetItemInfo for locale accuracy.
- feat(panel): bind M+ right panel to character frame, remove independent drag
- perf(loot): shorten loot toast preview duration from 20s to 10s

## [v2.0.1-alpha](https://github.com/cr4zyd34thg0d/HaraUI/tree/v2.0.1-alpha) (2026-02-15)
[Full Changelog](https://github.com/cr4zyd34thg0d/HaraUI/commits/v2.0.1-alpha) 

- ci: use tagged commit message as changelog for CurseForge  
    Instead of dumping the full commit history between tags, extract just  
    the body of the tagged commit's message. This gives a clean,  
    human-written changelog on both GitHub Releases and CurseForge.  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- cleanup: remove 14 unused fonts, keep only Tahoma Bold  
    Strip all bundled font files except TahomaBold.ttf which is the only  
    font actively used by HaraUI and the Platynator Tahoma override.  
    Retain WoW built-in font LSM overrides (Arial Narrow, Friz Quadrata,  
    Morpheus, Skurri) as they reference game files, not bundled assets.  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- rename: HarathUI → HaraUI across entire project  
    Full project rename for the 2.0 release:  
    - Rename HarathUI/ addon folder and .toc file to HaraUI/  
    - Rename SavedVariables from HarathUI\_DB to HaraUI\_DB  
    - Update slash commands from /harathui to /haraui  
    - Update all Interface\AddOns\ path references  
    - Update frame names, UI labels, and display strings  
    - Update .pkgmeta, .gitignore, release.yml packaging config  
    - Update agents.md, README.md, REFACTOR\_PLAN.md documentation  
    - Rename scripts/release-harathui.ps1 to release-haraui.ps1  
    - Remove 21 unused media files (legacy Caps/White texture variants,  
      unused Chonky textures)  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- ci: generate changelog from commits for GitHub Release and CurseForge  
    Instead of linking to GitHub, build a markdown changelog from git log  
    between the previous tag and current tag. Used for both the GitHub  
    Release body and CurseForge changelog field.  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- haraui 2.0: options panel redesign, version bump, media assets  
    - Restyle glass cards: purple-to-black gradient, remove orange accent  
      stripe, soften inner highlight/shadow lines  
    - Shrink options window width from 900 to 720  
    - Expose closeButton ref on options window frame  
    - Bump version badges and references from 1.5.8 to 2.0  
    - Add module screenshot media (Cast Bar, Friendly Nameplates, General,  
      Loot Toasts, Minimap Bar, Rotation Helper, XP/Rep Bar)  
    - Add REFACTOR\_PLAN.md with full 14-step HaraUI 2.0 roadmap  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- ci: set CurseForge project ID for release pipeline  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- platynator: add Tahoma font override and Name Only (No Guild) style  
    - Add "Overwrite to Tahoma" checkbox under "Show friendly in instances"  
      dropdown; when enabled, friendly name-only plates use Tahoma Bold  
      instead of the profile's default font  
    - Add "\_name-only-no-guild" built-in style (Tahoma Bold, no guild text)  
    - Replace platynator-no-friendly gutting patch with minimal  
      platynator-tahoma-override patch (additive only, no upstream removal)  
    - Update patch README and reapply script for the new profile  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- docs: add agents.md with CurseForge publishing workflow  
    Documents the full release pipeline: tagging, GitHub Actions workflow,  
    CurseForge upload, required secrets, version stamping, and rollback  
    procedures.  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- ci: add GitHub Actions release workflow  
    Tag-triggered pipeline (v*) that:  
    1. Packages addon via BigWigsMods/packager (replaces v2.0.2-alpha.1)  
    2. Creates a GitHub Release with the zip attached  
    3. Uploads the same zip to CurseForge  
    Release type mapping: v2.0.3 => release, -beta.N => beta, -alpha.N => alpha  
    Requires GitHub secret: CURSEFORGE\_API\_TOKEN  
    Requires env update: CURSEFORGE\_PROJECT\_ID in release.yml  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- ci: add .pkgmeta and TOC version token for packager  
    - Rewrite .pkgmeta: use move-folders to flatten HarathUI/ nesting,  
      remove plain-copy so v2.0.2-alpha.1 token gets replaced,  
      ignore all non-addon directories  
    - Replace hardcoded "2.0" in HarathUI.toc with v2.0.2-alpha.1  
      (BigWigsMods packager substitutes the git tag at build time)  
    - Update .gitignore to allow .pkgmeta and .github/ tracking  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- charsheet: defer OnShow/OnSizeChanged to break keybind refresh loops  
    Opening the character sheet via keybind (Shift-C) triggered synchronous  
    Refresh→layout→OnSizeChanged→Refresh cascades that froze the client.  
    - OnShow: move all M:Refresh / SyncCustomModeToNativePanel / layout work  
      into a C\_Timer.After(0) deferred closure wrapped in RunWithNativeVisGuard  
    - OnSizeChanged: similarly defer the heavy Apply/Update calls  
    - Add S.openToken counter; each OnShow increments it and deferred closures  
      capture & check the token so stale callbacks are discarded  
    - Keybind and click open paths now share the same safe deferred codepath  
    Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>  
- CharacterSheet: guard PaperDoll mode refresh recursion  
- CharacterSheet: guard native vis switches to break recursive refresh loops  
- core: break Debug/GetDB recursion  
- charsheet: add mode-switch reentrancy guard for currency tab  
- Revert "charsheet: guard size-change handler during refresh"  
- charsheet: guard size-change handler during refresh  
- options/pages: dedupe preview button handlers  
- options/pages: dedupe module-enable toggle attachment  
- options/pages: dedupe integer coercion helper  
- Options pages: extract Loot page (move-only)  
- Options pages: extract Minimap page (move-only)  
- Options pages: extract Rotation page (move-only)  
- Options pages: extract Friendly page (move-only)  
- Options pages: extract Cast page (move-only)  
- Options pages: extract XP page (move-only)  
- Options pages: extract General page (move-only)  
- options-ui: refactor cast bar page to glass cards with tabs  
- options-ui: add reusable glass/toggle/value helpers  
- refactor(options): extract theme widgets and window framework (move-only)  
- refactor(minimapbar): split interaction handlers from layout/discovery paths  
- refactor(friendlynameplates): split event concerns without behavior change  
- Step 9: centralize TrackedBars runtime state and scan boundaries  
- Step 9: centralize LootToasts runtime state and section boundaries  
- CastBar: include hold segment as final empower stage when needed  
- CastBar: add empower stage visuals and stage text for Evoker  
- XPBar: fix ETA seconds conversion from xp/hr  
- XPBar: restore pre-regression ETA logic verbatim  
- XPBar: safeguard xp/hr abbreviation function in ETA path  
- XPBar: fix ETA/session elapsed initialization regression  
- Step 8: optimize XPBar hot-path lookups and state  
- Step 8: optimize CastBar hot-path lookups and state  
- RotationHelper: invalidate keybind cache on PLAYER\_ENTERING\_WORLD  
- Step 7b: cache RotationHelper keybind lookups with event invalidation  
- Step 7a: remove NS keybinds global and bind via module table  
- Step 7a: extract RotationHelper keybind map helpers  
- Step 6: consolidate duplicate Clamp helper  
- core: store migration state under profile namespace  
- core: add additive savedvariables migration pipeline  
- core: extract slash handling to Core/Slash.lua  
- core: extract tooltip hook service to Core/TooltipHooks.lua  
- core: extract minimap button service to Core/MinimapButton.lua  
- core: extract version tracker to Core/VersionTracker.lua  
- core: extract compat helpers to Core/Compat.lua  
- step3: add load-order contract and global slash shim  
- Refresh README with current features and versions  
    High-level summary  
    - Rewrote README content to reflect the current bundle state and latest addon versions.  
    - Added a more visual, icon-rich layout while keeping docs practical for users and maintainers.  
    File-by-file behavior changes  
    - README.md: Updated addon/version table (including Platynator v319), refreshed HarathUI feature highlights, reorganized commands/install/dev workflows, and added a current changelog entry for v1.2.2.  
    Risk/compatibility notes  
    - Documentation-only change; no runtime addon behavior changed.  
    - HarathUI/AGENTS.md remains local-only due gitignore and is intentionally not part of this commit.  
    Optional follow-up notes  
    - If you want AGENTS guidance shared to collaborators, we can move it to a tracked path (or adjust ignore rules).  
- Refine dungeon nameplate fonts and update UI behavior  
    High-level summary  
    - Added robust friendly player name font handling in dungeons/raids for HaraUI, including system font swap/restore behavior inspired by Platynator.  
    - Improved CharacterSheet layout resilience and weekly vault data rendering/styling logic.  
    - Updated Platynator friendly nameplate behavior, instance visibility controls, and related UI/config flows, plus minor aura/widget/core fixes and version bump.  
    File-by-file behavior changes  
    - HarathUI/Modules/FriendlyNameplates.lua: Added dungeon/raid-only system nameplate font override with backup/restore; wired refresh/apply/event hooks so friendly player names use configured font reliably in instances.  
    - HarathUI/Modules/CharacterSheet.lua: Expanded vault data normalization/retrieval, item level extraction, difficulty labels, card sorting/styling, and event coverage; improved frame width/layout handling and resize enforcement.  
    - HarathUI/Modules/SmallerGameMenu.lua: Replaced fixed menu scale with resolution-aware scaling and live display/UI-scale update hooks.  
    - HarathUI/SavedVariables.lua: Updated default game menu scale baseline from 0.85 to 0.70.  
    - Platynator/Display/Initialize.lua: Added full friendly display pool flow, friendly stacking/hit-test/size handling, instance show-state management, and friendly font update logic tied to relevant lifecycle events.  
    - Platynator/CustomiseDialog/Main.lua: Added friendly behavior toggles, friendly-in-instances mode selector, friendly style assignment UI, and style-deletion assignment fallback.  
    - Platynator/CustomiseDialog/ImportExport.lua: Removed broad import sanitization path; simplified import style fallback behavior.  
    - Platynator/Display/Auras.lua: Important aura refresh now triggers when important-buff filtering is enabled.  
    - Platynator/Display/Widgets.lua: Simplified texture fetch/fallback logic for health/cast/absorb/cutaway widgets.  
    - Platynator/Core/Initialize.lua: Simplified rect calculation assumptions for assets/text sizing.  
    - Platynator/CHANGELOG.md: Updated changelog entry to version 319 notes.  
    - Platynator/Platynator.toc: Bumped addon version from 318 to 319.  
    Risk/compatibility notes  
    - Friendly nameplate behavior now depends more heavily on instance CVars and system font object overrides; interaction with other nameplate addons may still require precedence/ordering checks.  
    - CharacterSheet vault logic now tolerates more API variants/fallbacks, but output depends on live weekly reward API payload timing.  
    - Resolution-based menu scaling may feel smaller/larger at uncommon display setups; clamped bounds are in place.  
    Optional follow-up notes  
    - Verify friendly name-only behavior in party and raid instances with and without third-party nameplate addons enabled.  
    - Validate weekly vault card fields across reset states and locked/unlocked reward transitions.  
    - If needed, split HarathUI and Platynator changes into separate release commits in future cycles.  
- chore: sync Platynator update and reapply local no-friendly patch  
- fix(charsheet): resolve currency transfer taint via native mode tabs  
    Route bottom Character/Rep/Currency buttons through native CharacterFrame tabs instead of PaperDoll sidebars, preserving secure click flow and fixing Rep/Currency misrouting to Titles/Equipment.  
    Also bumps HarathUI to 1.5.8 and updates README bundle/version metadata to 1.2.1.  
- chore(release): bump HarathUI version to 1.5.7  
- feat(character-sheet): add contextual title formatting  
    - add BuildContextualTitleText to format titles contextually based on Blizzard title string patterns\n- handle %s/%1 placeholders, existing embedded names, prefix titles with trailing whitespace, and suffix fallback\n- use contextual title text in the known titles data list\n- add BuildContextualTitleDisplayText to preserve contextual ordering while keeping class-colored name and neutral title color\n- refresh header title display on PLAYER\_TITLE\_CHANGED so title swaps update immediately  
- chore(release): bump HarathUI version to 1.5.6  
    Update TOC addon metadata version after the CharacterSheet state refactor and peer-only version-check pipeline cleanup so packaged builds report the new release.  
- refactor(version-check): simplify to peer-only addon comms  
    Remove hosted metadata and build-stamp dependence from version status resolution; local metadata is now a non-authoritative fallback until peer data arrives.  
    Trim addon message payloads to protocol + version (V|<protocol>|<version>) and simplify tooltip/slash output to focus on installed/latest version, source, and peer.  
    Delete the hosted-version generated file and stamp script, and update the TOC entries to match the new runtime-only peer comparison flow.  
- refactor(charsheet): centralize UI runtime state and tune refresh scheduling  
    Move CharacterSheet module globals into a shared state table (S) and collect layout constants in CFG so mutable state is tracked in one place.  
    Tighten mode sync/mirroring paths by threading suppress flags through state, normalizing mode input handling, and making deferred native mirror transitions explicit.  
    Replace always-on ticker behavior with UpdateTickerState so OnUpdate runs only while the character UI/right panel is visible, which lowers idle work and keeps secure refresh retries predictable.  
- release: 1.5.5  
    - fix CharacterSheet keybind/native subframe switching to mirror bottom tab behavior  
    - harden layout reassertion during native panel toggles  
    - improve version comm prefix registration retry behavior  
- release: 1.5.4  
- release: bump HarathUI to 1.5.1 and fix mega-dungeon portal links  
- release: milestone v1.5.0  
    - bump HarathUI to v1.5.0  
    - overhaul version tracking (addon comms + hosted feed support)  
    - add GitHub-backed hosted version sync and release helpers  
    - improve options version indicator source/status reporting  
- release: bump HarathUI to 1.4.7  
- vendor(platynator): update to v314 and forward-port compatibility patch  
- chore(scripts): add verified Platynator update workflow  
- fix(platynator): sanitize imported profiles and refresh local patch profile  
- chore(gitignore): track patch and script directories  
- release(harathui): bump to v1.4.6 and ship import/version fixes  
- chore(xpbar): shorten rested label text  
    Replace 'Rested Experience' with 'Rested' in XP detail/preview strings.  
- feat(version): add build commit/date diagnostics  
    - add X-Build-Commit and X-Build-Date metadata in HarathUI.toc  
    - expose commit/date through NS.GetVersionInfo and /hui version  
    - show commit/date in options version-dot tooltip and refresh indicator from shared runtime info  
- release(harathui): bump to v1.4.5  
    - update addon metadata (Version/X-GitVersion) to 1.4.5  
    - refresh README HarathUI version references to v1.4.5  
    - include current CharacterSheet/XPBar and CopyBattleTag working changes  
- Release v1.4.1  
- Release v1.4.0 and finalize character sheet updates  
- feat(harathui): overhaul character sheet gear/stats presentation  
    Expand and rebalance CharacterSheet layout with wider pane sizing, improved slot spacing, updated stat panel gradients, and refined row padding/section sizing. Add draggable non-clickthrough custom panel behavior and integrate gear-row metadata display updates (upgrade tracks, ilvl formatting, enchant text handling, tier/class color paths, and directional gradient rendering).  
- fix(platynator): guard widget absorb/foreground texture fallbacks  
    Prevent nil indexing in Display/Widgets when upstream data omits absorb or foreground assets/colors. Use shared bar-background fallback resolution and white texture/color defaults so hostile-only mode and third-party updates do not trigger startup Lua errors.  
- ﻿Add HarathUI HaraChonk modules and refresh release docs  
    Summary:  
    - Introduce major HarathUI feature set centered on HaraChonk character frame replacement and related QoL modules.  
    - Bump HarathUI addon version to 1.3.0 and align README release metadata/features.  
    Included changes:  
    - Character Sheet module: add HaraChonk-style player/character frame replacement with custom layout, theming, stat/gear presentation, and right-side data panel support.  
    - Tracked Bars module: add skinning pass for Blizzard Cooldown Viewer status bars using HarathUI castbar texture/font settings.  
    - Summons module: add optional auto-confirm summon flow with combat-safe retry behavior.  
    - Core/settings wiring: register and apply new modules, persist defaults, and integrate related toggles.  
    - Friendly Nameplates, Cast Bar, Loot Toasts updates: apply compatibility and behavior refinements required by the expanded module set.  
    - Assets: add Chonky texture files required by the character sheet presentation.  
    - Version/docs: set HarathUI TOC version to 1.3.0 and update root README features/changelog to document new significant functionality, including HaraChonk player frame replacement.  
- Patch 12.0.1 addon updates and harden nameplate behavior  
    Summary:  
    - Move bundle metadata to 12.0.1/120001 and update addon version/docs.  
    - Remove Platynator friendly-nameplate control paths and stop its global nameplate toggle interaction.  
    - Add defensive nil-safe rect sizing in Platynator initialization to prevent startup errors.  
    - Display HarathUI addon version in the options left panel (bottom-right).  
    - Tighten repo ignore rules to focus tracked content on addon-relevant files.  
    Details by area:  
    - OPie: set Interface to 120001-only.  
    - HarathUI: bump TOC version to 1.2.6 and render dynamic version label from addon metadata in options UI.  
    - Platynator: enemy-only nameplate management, remove friendly UI/config hooks, and remove nameplateShowAll writes.  
    - README: keep existing structure while updating patch/version table and changelog for this release.  
    - .gitignore: whitelist addon folders and explicitly ignore local editor/agent/tooling metadata under HarathUI.  
- fix: Cast bar preview only shows when frames unlocked  
    Preview now properly checks framesLocked state, not just previewWhenUnlocked setting  
    Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>  
- fix: Update Interface versions to match WoW 12.0.x  
    Changed to 120000, 120001 to match working addons like Plater  
    Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>  
- fix: Add multi-version Interface support to HarathUI TOC  
    Supports: 12.0.7, 11.0.2, 5.0.5, 4.0.4, 1.15.0  
    Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>  
- docs: Add emojis and extra personality to HarathUI README ✨  
    Because documentation should spark joy 💜  
    Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>  
- docs: Add detailed HarathUI README with module descriptions  
    - Fun, informative documentation for all modules  
    - XP bar, cast bar, loot toasts, and more  
    - Commands reference and installation guide  
    Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>  
- v1.0.0: HaraUI addon bundle for WoW 12.0.7  
    Updated all addon TOC files to Interface 120007:  
    - HarathUI v1.2.4: QoL UI suite (XP bar, cast bar, loot toasts)  
    - OPie v7.11.3: Radial action-binding rings  
    - Platynator v287: Nameplate customization  
    Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>  
