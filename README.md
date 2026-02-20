# HaraUI

:sparkles: A curated World of Warcraft UI focused on clean gameplay UX, practical QoL modules, and battle-tested nameplate behavior.

![WoW Interface](https://img.shields.io/badge/WoW-12.0.1-1f6feb?style=for-the-badge)
![HaraUI](https://img.shields.io/badge/HaraUI-2.2.1--alpha-f97316?style=for-the-badge)

## :school_satchel: Overview

- **Target Patch:** WoW `12.0.1` (Interface `120001`)

### :package: Included Addons

| Addon | Version | Interface | Author | Purpose |
|-------|---------|-----------|--------|---------|
| HaraUI | 2.2.1-alpha | 120001 | Harath | Modular UI/QoL suite |

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
- `/hui layoutdebug` -> toggle Character Sheet layout debug mode
- `/hui layoutsnap` -> print Character Sheet layout snapshot
- `/hui version` -> show version details

## :rocket: Installation

[![CurseForge](https://img.shields.io/badge/Download-CurseForge-F16436?style=for-the-badge&logo=curseforge&logoColor=white)](https://www.curseforge.com/wow/addons/haraui)

1. Download the latest build from CurseForge.
2. Extract the `HaraUI` folder into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

3. Run `/reload` in-game.

## :spiral_notepad: Changelog (Recent)

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

