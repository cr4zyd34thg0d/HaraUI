# HaraUI

:sparkles: A curated World of Warcraft UI focused on clean gameplay UX, practical QoL modules, and battle-tested nameplate behavior.

![WoW Interface](https://img.shields.io/badge/WoW-12.0.1-1f6feb?style=for-the-badge)
![HaraUI](https://img.shields.io/badge/HaraUI-2.3.0-f97316?style=for-the-badge)

## :school_satchel: Overview

- **Target Patch:** WoW `12.0.1` (Interface `120001`)

### :package: Included Addons

| Addon | Version | Interface | Author | Purpose |
|-------|---------|-----------|--------|---------|
| HaraUI | 2.3.0 | 120001 | Harath | Modular UI/QoL suite |

## :jigsaw: Current Feature Set

### :gear: Core UI Modules
- :orange_circle: **XP / Reputation Bar**: swaps between XP and watched reputation, with session tracking, rate text, and ETA support.
- :large_blue_circle: **Custom Cast Bar**: player cast bar with icon, interrupt shield, latency spark, and visual tuning controls.
- :gift: **Loot Toasts**: compact notifications for items, currencies, and money with clean stacking behavior.
- :compass: **Minimap Button Bar**: gathers minimap buttons into a movable bar with orientation and popout behavior controls.
- :chart_with_downwards_trend: **Smaller Game Menu**: applies compact Escape menu scaling with resolution-aware behavior.
- :world_map: **Move Options Window**: allows dragging Blizzard Settings/Options for cleaner screen placement.

### :bricks: Character Sheet (HaraChonk)
- :bust_in_silhouette: **Expanded Character Layout**: larger character frame footprint with dedicated right-side panel space.
- :bar_chart: **Stats and Gear Presentation**: custom stat and equipment presentation for faster reading.
- :world_map: **Mythic+ and Vault Panel**: integrated dungeon run details and Great Vault progress snapshot.
- :money_with_wings: **Currency and Reputation Integration**: unified tab behavior and layout polish across Character, Reputation, and Currency views.
- :art: **Visual Skinning Pass**: consistent borders, textures, and typography across Character Sheet elements.

### :busts_in_silhouette: Alt Tracker
- :bar_chart: **Alt Overview Panel**: cross-character dashboard showing item level, Mythic+ rating, keystone, Great Vault progress, raid lockouts, and seasonal currencies for every alt.
- :mag: **Equipment Inspector**: left-click any character row to pop up a gear summary with slot-by-slot item levels.
- :arrows_counterclockwise: **Auto Weekly Reset**: detects Tuesday reset and clears stale vault/lockout data automatically.

### :crossed_swords: Combat and Utility
- :label: **Friendly Player Nameplates**: class-color and font handling for friendly units, tuned for dungeon and raid readability.
- :dart: **Rotation Helper**: compact keybind helper panel for quick combat decision support.
- :white_check_mark: **Auto Accept Summons**: accepts party/raid summons when enabled.
- :receipt: **Tracked Bars Skinning**: skins Blizzard Cooldown Viewer tracked bars to match HaraUI visuals.
- :id: **Spell ID Tooltips**: appends spell IDs to tooltips for debugging and setup precision.
- :busts_in_silhouette: **Copy BattleTag**: adds a quick copy action in the Friends dropdown.

### :art: Personalization and Control
- :lock: **Unlock Frames (Move Mode)**: drag and save positions for movable module frames.
- :paintbrush: **Theme Accent Color**: one accent color applied across options and module visuals.
- :satellite: **Minimap Launcher Button**: optional LibDBIcon launcher for quick access.
- :control_knobs: **Unified Options Window**: organized module pages with toggles, previews, sliders, and advanced controls.

## :keyboard: Slash Commands

### HaraUI
- `/hui` or `/haraui` -> open options
- `/hui lock` -> toggle Move Mode
- `/hui xp | cast | loot | summon` -> toggle module quickly
- `/hui debug` -> toggle debug mode
- `/hui version` -> show version details
- `/haralt` -> toggle Alt Tracker panel

## :rocket: Installation

[![CurseForge](https://img.shields.io/badge/Download-CurseForge-F16436?style=for-the-badge&logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/haraui)

1. Download the latest build from CurseForge.
2. Extract the `HaraUI` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

3. Run `/reload` in-game.

## :spiral_notepad: Changelog (Recent)

### v2.5.0 - 2026-03-14
- **New:** Merchant module — automatically repairs all gear and sells grey items when you open a merchant. Toggles for each action in General settings.
- **New:** Quest Reward module — automatically selects the best quest reward 1.5s after the completion screen appears. Prioritises same armor type + primary stat + ilvl upgrade, falling back to highest vendor value.
- **New:** Auto Equip module — scans bags on `BAG_UPDATE_DELAYED` and equips any soulbound item level upgrade that matches your class armor type and spec primary stat. Accessories (neck, cloak, ring, trinket) only require an ilvl upgrade.
- **New:** Bag Upgrade Arrows — shows a small green arrow indicator on bag slots that contain an item level upgrade for your currently equipped gear.
- **New:** Codex panel — Merchant, Quest Reward, and Auto Equip added as rune entries with custom on/off icons. Left-click toggles; enable/disable all button updated.
- **Fixed:** XP bar max-level visibility logic hardened — bar now correctly hides at max level when `hideAtMaxIfNoRep` is set and no tracked reputation is active.
- **Improved:** Loot toasts refactored — text block detached from accent rail, intro alpha preserved through the full animation, fade-out timing restored, and stack layout aligned with upgraded loot data.
- **Improved:** Merchant auto-repair and auto-sell toggles promoted to General settings row for quick access without navigating to a separate page.
- **Removed:** Auto Summons module removed.
- **Optimised:** `CLASS_ARMOR_TYPE`, `PRIMARY_STAT_KEY`, and `ACCESSORY_EQUIP_LOCS` constants consolidated into `Constants.lua` — shared by AutoEquip and QuestReward, eliminating duplicate definitions.
- **Optimised:** Dead option page files (Merchant, QuestReward, AutoEquip pages were defined but never wired into the options system) removed from load order.

### v2.4.0 - 2026-03-02
- **Fixed:** Character panel, reputation panel, and currency panel now respond to keybinds and button presses in WoW 12.0 — root cause was `SetAttribute` on CharacterFrame tainting the UIPanelLayout system.
- **Fixed:** CharacterFrame correctly positions on screen in WoW 12.0 when ShowUIPanel skips native positioning due to taint; fallback anchor applied automatically.
- **Fixed:** `CharacterFrame:SetScale()` guarded behind `InCombatLockdown()` — prevents ADDON_ACTION_BLOCKED in WoW 12.0.
- **Fixed:** MythicPanel and StatsPanel no longer bleed through the combat view when CharacterFrame opens during combat.
- **Fixed:** Removed registration of events removed in WoW 12.0 (`LEARNED_SPELL_IN_TAB`, `PLAYER_TITLE_CHANGED`) — wrapped in pcall with safe fallback.
- **Fixed:** Combat panel bleed — reputation and currency content no longer overlaps with the gear overlay when switching tabs during combat. Overlay correctly suppresses/restores per active tab using custom HaraUI tab hooks (no taint near currency transfer).
- **Fixed:** XP bar max level detection now uses `UnitXPMax() == 0` instead of a hardcoded level cap — future-proof for any level squish or cap change.
- **Fixed:** Loot toast stack spacing now scales with the scale slider — toasts no longer overlap at scale > 1.0.
- **Improved:** Scale slider range expanded to 0.5–2.5 on Cast Bar, Loot Toasts, Rotation Helper, and XP Bar options pages.
- **Improved:** Combat panel overlay refactored — all suppression/restore calls grouped into single helper functions; active tab detected from native frame visibility at show time.

### v2.3.0 - 2026-02-20
- **Added:** Alt Tracker module — cross-character dashboard with item level, M+ rating, keystones, Great Vault progress, raid lockouts, seasonal currencies, and equipment inspection popup. Toggle with `/haralt`.
- **Improved:** Cache `IsAccountTransferBuild()` as session-constant; deduplicate shared utilities across CharacterSheet modules.
- **Improved:** Consolidate `VAULT_THRESHOLDS` and `WEEKLY_REWARD_TYPE` constants into Data.lua (single source of truth).
- **Improved:** Reduce FrameFactory Apply retry delays from 4 to 3 passes; slot enforcer timing tightened from 1.5s to 0.75s.
- **Removed:** Dead slash commands (`layoutdebug`, `charsheetdebug`, `layoutsnap`, `charsheetsnap`), orphaned `Minimap.tga`, unused SavedVariables keys, and other dead code paths.

### v2.2.1-alpha - 2026-02-20
- **Added:** "None" Codex glyph theme — clean pages and spine with no watermark textures.
- **Changed:** Codex module entries: left-click navigates to the module settings page; right-click toggles enable/disable. Tooltip updated to reflect both actions.
- **Added:** Subtle green (on) / red (off) gradient per Codex entry row and power bar color to indicate enabled state at a glance.
- **Changed:** Options nav replaced with compact rune icon cluster — same icons as the Codex panel, 40px each, with frame ring, glow, and tooltip. General/home uses the charsheet rune.
- **Removed:** Unused nav screenshot PNG media files (General, XP_Rep_Bar, Cast_Bar, Friendly_Nameplates, Rotation_Helper, Minimap_Bar, Loot_Toasts).

### v2.2.0 - 2026-02-19
- **Refactored:** Complete CharacterSheet 8-phase rewrite — Coordinator state machine, FrameFactory extraction, CurrencyLayout extraction, PaneManager, sub-module lifecycle (OnShow/OnHide), dead code removal.
- **Removed:** Layout.lua deleted; layout logic consolidated into FrameFactory and PaneManager.
- **Added:** Dungeon Portal Panel with expansion-grouped spell list, right-click grid assignment, and quick-access 4x2 portal grid.
- **Added:** Great Vault card restyle with Blizzard atlas lock icon, animated glow/swirl/sparkle effects, and reward tooltip on hover.
- **Fixed:** Equipped item level display now updates reliably via Core event routing (PLAYER_EQUIPMENT_CHANGED, PLAYER_AVG_ITEM_LEVEL_UPDATE) and multi-retry recheck.
- **Fixed:** Portal list and quick-access grid secure casting now uses dedicated castBtn overlay matching M+ panel pattern.
- **Changed:** Stat panel row heights tuned to 18px with tighter section gaps for consistent alignment.

### v2.1.1-alpha - 2026-02-18
- **Fixed:** Resolve "Primary" stat label bug when SPEC_STAT_STRINGS is unavailable.
- **Fixed:** Guard StatusTrackingBarManager, CharacterFrame, and Minimap SetParent against combat lockdown taint.
- **Fixed:** Sanitize CHAT_MSG event args with tostring() to strip secret string taint.
- **Added:** Dynamic gem socket tooltips based on expansion, slot, and PvP context.
- **Added:** Bind M+ right panel to character frame, remove independent drag.
- **Changed:** Shorten loot toast preview duration from 20s to 10s.

### v2.1.0-alpha - 2026-02-18
- Sync local feature snapshot to main for 2.1.0-alpha
- Group release notes into feature summaries
- Refresh README features, install, and changelog
- Remove legacy refactor plan doc
- Stop tracking legacy addon/vendor folders

### v1.2.2 - 2026-02-15
- **Changed:** Improved dungeon and raid friendly-name font behavior for HaraUI plates.
- **Changed:** Expanded Character Sheet vault and layout logic for better live data handling.
- **Changed:** Switched game menu scaling to a resolution-aware model.

### v1.2.1 - 2026-02-14
- **Changed:** Updated HaraUI to `v2.0`.
- **Fixed:** Resolved Currency tab account-transfer taint path by routing bottom Character/Rep/Currency buttons through native CharacterFrame tabs.
- **Fixed:** Corrected bottom tab routing where Reputation/Currency could open Blizzard Titles/Equipment panes.

### v1.2.0 - 2026-02-11
- **Changed:** Updated HaraUI to `v1.4.1` for major module expansion.
- **Added:** HaraChonk character/player frame replacement (Character Sheet module).
- **Added:** Tracked Bars skinning module.
- **Added:** Auto Accept Summons module.
- **Added:** Spell ID toggle in General settings.

