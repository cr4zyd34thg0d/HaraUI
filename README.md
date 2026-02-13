# HaraUI

A collection of World of Warcraft addons for patch 12.0.1 (Midnight).

**Bundle Version:** 1.2.0
**Target WoW Patch:** 12.0.1 (Interface: 120001)

## Included Addons

| Addon | Version | Interface | Author |
|-------|---------|-----------|--------|
| HarathUI | 1.5.0 | 120001 | Harath |
| OPie | 7.11.3 | 120001 | foxlit |
| Platynator | 314 | 120001 | plusmouse |

### HarathUI (v1.5.0)
Modular quality-of-life UI suite.

**Features:**
- XP/Reputation bar (shows rep only when tracked at max level)
- Custom cast bar (replaces Blizzard's player cast bar)
- Loot toasts (items, money, currency)
- Smaller game menu scaling
- Friendly nameplates toggle
- Minimap button bar
- HaraChonk character/player frame replacement with styled character sheet
- Tracked Bars skinning for Blizzard Cooldown Viewer bars
- Auto-accept summons module
- Spell ID tooltip toggle

**Commands:**
- `/hui` - Open options
- `/hui lock` - Toggle Move Mode
- `/hui xp | cast | loot | summon` - Toggle individual modules

### OPie (v7.11.3)
Radial action-binding addon.

Groups abilities, items, mounts, macros, and more into customizable rings that appear when you hold down a keybind. Release to activate the selected action.

**Commands:**
- `/opie` - Open configuration
- `/opie rings` - Ring customization

**Website:** [townlong-yak.com/addons/opie](https://www.townlong-yak.com/addons/opie)

### Platynator (v314)
Nameplate customization addon.

Highly configurable nameplate replacement with support for:
- Health/Cast/Power bars
- Aura tracking
- Target/Focus/Mouseover highlights
- Quest markers
- Elite/Rare markers
- PvP indicators
- Custom widget positioning

## Installation

Copy the addon folders to your WoW AddOns directory:
```
World of Warcraft/_retail_/Interface/AddOns/
```

## Changelog

### v1.2.0 (2026-02-11)
- Updated HarathUI to v1.4.1 for significant module additions
- Added HaraChonk character/player frame replacement (Character Sheet module)
- Added Tracked Bars skinning module
- Added Auto Accept Summons module
- Added Spell ID toggle to General settings

### v1.1.0 (2026-02-11)
- Updated bundle target to WoW 12.0.1 (Interface 120001)
- Updated OPie TOC interface to 120001-only
- Updated HarathUI to v1.2.6 and added visible version text in the settings UI

### v1.0.0 (2026-01-29)
- Initial release for WoW 12.0.7
- Updated all addon TOC files to Interface 120007
- Bundled HarathUI v1.2.4, OPie v7.11.3, Platynator v287
## Local patch workflow

For upstream addon updates that overwrite local compatibility changes, reapply local patches:

```powershell
.\scripts\reapply-local-patches.ps1 -Patch platynator-no-friendly
```

Patch docs are in `patches/README.md`.

For a full Platynator update flow (mirror upstream folder, reapply patch, verify):

```powershell
.\scripts\update-platynator.ps1 -SourcePath "C:\path\to\Platynator"
```

## HarathUI version metadata workflow

When releasing HarathUI, stamp TOC metadata from a specific git ref so build diagnostics match what you package:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\release-harathui.ps1 -Version 1.5.0 -GitVersion 1.5.0 -CommitRef HEAD
```

By default this also refreshes `HarathUI/Generated/HostedVersion.lua` from GitHub (`cr4zyd34thg0d/HaraUI`) so the in-game version light can compare against hosted release/tag data.

Optional flags:
- `-SkipGitHubHostedSync` to skip GitHub feed refresh.
- `-RequireGitHubHostedSync` to fail the command if GitHub sync fails.
- `-GitHubOwner/-GitHubRepo` to target a different repository.
- `-GitHubToken` (or `GITHUB_TOKEN` env var) to avoid GitHub API rate limits.

Direct low-level stamp example (advanced):

```powershell
powershell -ExecutionPolicy Bypass -File .\HarathUI\tools\stamp-version-metadata.ps1 -Version 1.5.0 -GitVersion 1.5.0 -BuildCommit 56a5bb9 -LatestCommit 56a5bb9
```

Notes:
- `X-Build-Commit` reflects the packaged build commit.
- Runtime "update available" status is sourced from addon comms (and optional hosted feeds), not only local TOC metadata.
