# HarathUI

*Your cozy corner of Azeroth, now with 100% less UI clutter.*

**Version:** 1.2.4
**WoW Patch:** 12.0.7 (Midnight)
**Author:** Harath

---

## What Is This Thing?

HarathUI is a modular quality-of-life addon that quietly replaces the bits of Blizzard's UI that made you go "ugh" with bits that make you go "ooh." It's not trying to be ElvUI. It's not trying to replace your action bars. It just wants to make your XP bar smarter, your cast bar prettier, and your loot toasts less... aggressive.

Think of it as a UI spa day.

---

## The Modules

### XP & Reputation Bar
The smart bar that knows when to shut up.

- Shows XP while leveling (obviously)
- At max level? Only shows rep **if you're actually tracking one**
- Otherwise it politely hides itself like a good UI element
- Tracks rested XP, quest XP bonuses, and session progress
- Fully moveable and resizable

### Cast Bar
Blizzard's cast bar, but make it fashion.

- Clean, modern design with square icon crop
- Preview mode when unlocked (no more "am I casting?" confusion)
- Text always renders on top (revolutionary, we know)
- Replaces the default player cast bar entirely

### Loot Toasts
Because you deserve to know what dropped.

- Shows items, money, AND currency (toggleable)
- Less intrusive than the default Blizzard toasts
- Actually tells you useful information

### Smaller Game Menu
For when ESC gives you too much menu.

- Scales down the main game menu
- More screen real estate for... looking at your transmog

### Friendly Nameplates
Quick toggle for friendly nameplate visibility.

- Great for raids where you need to see who's standing in fire
- Also great for when you don't want to see who's standing in fire

### Minimap Button Bar
Corrals all those addon minimap buttons.

- Keeps your minimap clean
- All buttons still accessible
- Marie Kondo would approve

### Rotation Helper
*(Work in progress)*

- Visual hints for your rotation
- Because sometimes we all need a little help

---

## Commands

| Command | What It Does |
|---------|--------------|
| `/hui` | Opens the options panel |
| `/hui lock` | Toggles Move Mode (drag stuff around!) |
| `/hui xp` | Toggle XP bar module |
| `/hui cast` | Toggle Cast bar module |
| `/hui menu` | Toggle Smaller Menu module |
| `/hui loot` | Toggle Loot Toasts module |

---

## Installation

1. Download and extract to:
   ```
   World of Warcraft/_retail_/Interface/AddOns/HarathUI/
   ```
2. Restart WoW or type `/reload`
3. Type `/hui` to configure
4. Enjoy your slightly-less-cluttered life

---

## Changelog

### v1.2.4
- Updated for WoW 12.0.7 (Midnight)

### v1.1.0
- Sliders now show live values (fancy!)
- Summoning Ring keybind added (Keybinds > HarathUI > Toggle Ring)
- Basic ring action editor

### v1.0.0
- Removed Frame/Health coloring module
- Added Summoning Ring for mounts and movement utilities

### v0.3.0
- Cast bar preview mode when Move Mode is ON
- Square/flat icon crop + stronger frame styling
- Text always drawn on top

---

## Dependencies

**Optional but recommended:**
- LibSharedMedia-3.0 (for extra fonts)
- LibDataBroker-1.1 (for minimap integration)
- LibDBIcon-1.0 (for minimap button)

*All libs are bundled, so you're good to go out of the box.*

---

## Found a Bug?

Whisper into the void. Or open an issue. Whichever feels more cathartic.

---

*Made with caffeine and questionable life choices.*
