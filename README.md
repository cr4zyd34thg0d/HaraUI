# HaraUI

:sparkles: A curated World of Warcraft UI bundle focused on clean gameplay UX, practical QoL modules, and battle-tested nameplate behavior.

![WoW Interface](https://img.shields.io/badge/WoW-12.0.1-1f6feb?style=for-the-badge)
![HarathUI](https://img.shields.io/badge/HarathUI-1.5.8-f97316?style=for-the-badge)
![Platynator](https://img.shields.io/badge/Platynator-319-22c55e?style=for-the-badge)
![OPie](https://img.shields.io/badge/OPie-7.11.3-a855f7?style=for-the-badge)

## :school_satchel: Bundle Overview

- **Target Patch:** WoW `12.0.1` (Interface `120001`)
- **Bundle Release:** `v1.2.2` (rolling main)
- **Focus:** fast setup, modern defaults, and modular control

### :package: Included Addons

| Addon | Version | Interface | Author | Purpose |
|-------|---------|-----------|--------|---------|
| HarathUI | 1.5.8 | 120001 | Harath | Modular UI/QoL suite |
| Platynator | 319 | 120001 | plusmouse | Highly customizable nameplates |
| OPie | 7.11.3 | 120001 | foxlit | Radial action rings |

## :jigsaw: HarathUI Feature Highlights

### :gear: Core UI Modules
- :orange_circle: **XP/Rep Bar** with session text, rate text, and max-level behavior options
- :large_blue_circle: **Custom Cast Bar** with icon, shield, latency spark, texture/color controls
- :gift: **Loot Toasts** for items, currencies, and money
- :compass: **Minimap Button Bar** with orientation, sizing, and popout controls
- :chart_with_downwards_trend: **Smaller Game Menu** with resolution-aware scaling

### :shield: Combat & Utility
- :label: **Friendly Player Nameplates** with class color support, font sizing, and dungeon/raid-friendly font handling
- :dart: **Rotation Helper Frame** (compact keybind indicator panel)
- :white_check_mark: **Auto Accept Summons**
- :receipt: **Tracked Bars Skinning** for Blizzard Cooldown Viewer bars
- :id: **Spell ID Tooltip Toggle**
- :busts_in_silhouette: **Copy BattleTag** from Friends dropdown

### :bricks: Character Sheet (HaraChonk)
- :bust_in_silhouette: Expanded custom character frame layout
- :bar_chart: Styled stats and gear presentation
- :world_map: Mythic+ / vault-focused right panel with richer activity rendering
- :art: Font/theme integration across custom frame elements

## :keyboard: Slash Commands

### HarathUI
- `/hui` -> open options
- `/hui lock` -> toggle Move Mode
- `/hui xp | cast | loot | summon` -> toggle module quickly
- `/hui debug` -> toggle debug mode
- `/hui version` -> show version details

### OPie
- `/opie` -> open configuration
- `/opie rings` -> ring customization

Docs: https://www.townlong-yak.com/addons/opie

## :rocket: Installation

Copy addon folders into:

```text
World of Warcraft/_retail_/Interface/AddOns/
```

Then run `/reload` in-game.

## :wrench: Local Development Workflows

### Reapply local compatibility patches

```powershell
.\scripts\reapply-local-patches.ps1 -Patch platynator-no-friendly
```

Patch docs: `patches/README.md`

### Full Platynator refresh flow

```powershell
.\scripts\update-platynator.ps1 -SourcePath "C:\path\to\Platynator"
```

### Stamp HarathUI release metadata

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release-harathui.ps1 -Version 1.5.8 -GitVersion 1.5.8 -CommitRef HEAD
```

This also updates `HarathUI/Generated/HostedVersion.lua` by default, using GitHub release/tag data for hosted version checks.

Optional flags:
- `-SkipGitHubHostedSync`
- `-RequireGitHubHostedSync`
- `-GitHubOwner`, `-GitHubRepo`
- `-GitHubToken` (or `GITHUB_TOKEN` env var)

Low-level stamp example:

```powershell
powershell -ExecutionPolicy Bypass -File .\HarathUI\tools\stamp-version-metadata.ps1 -Version 1.5.8 -GitVersion 1.5.8 -BuildCommit 56a5bb9 -LatestCommit 56a5bb9
```

## :spiral_notepad: Changelog

### v1.2.2 (2026-02-15)
- Updated Platynator to `v319`
- Improved dungeon/raid friendly name font behavior for HaraUI-friendly plates
- Expanded CharacterSheet vault and layout logic for better live data handling
- Switched game menu scaling to a resolution-aware model

### v1.2.1 (2026-02-14)
- Updated HarathUI to `v1.5.8`
- Resolved Currency tab account-transfer taint path by routing bottom Character/Rep/Currency buttons through native CharacterFrame tabs
- Fixed bottom tab routing mismatch where Rep/Currency could open Blizzard Titles/Equipment panes

### v1.2.0 (2026-02-11)
- Updated HarathUI to `v1.4.1` for significant module additions
- Added HaraChonk character/player frame replacement (Character Sheet module)
- Added Tracked Bars skinning module
- Added Auto Accept Summons module
- Added Spell ID toggle to General settings
