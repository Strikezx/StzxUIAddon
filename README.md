# StzxUI

A personal UI suite for **World of Warcraft: Forever** (game version 1.60.1, interface 16001).
Built one module at a time; every module is its own addon folder, so any part can be switched off in the AddOns list.

## What's in it so far

| Folder | What it does |
|---|---|
| `StzxUI` | Core: StzxUI options window (`/stzx`; Esc > Options > AddOns > StzxUI has a welcome page with a button into it), profiles, move mode, section on/off switches, `/stzx` |
| `StzxUI_Social` | Declines duel requests. Thanks players who buff you (emote or whisper, out of combat, with a cooldown per player); recent mail names and your own characters beside Send Mail |
| `StzxUI_Info` | Small movable readouts: FPS, latency and clock; map coordinates; levelling pace (XP per hour, time to level) |
| `StzxUI_UnitFrames` | Player, target, focus, target-of-target and pet frames (class icon or portrait, health and power text, buffs and debuffs) with their own cast bars, plus party and raid frames (a separate Party & Raid section); hides Blizzard's |
| `StzxUI_Quests` | Tints quests that are new to WoW: Forever (glow on the quest parchment, colour and strength adjustable) and keeps the loot sparkle on quest items; `/stzx quest` says whether the open quest is new; a party panel shows who's on the open quest, with Share and Share all |
| `StzxUI_Runs` | Dungeon and raid run history: time, XP, gold, bosses, deaths and the loot you picked up, per character; a movable run timer while inside; `/stzx runs` opens the history |
| `StzxUI_Fishing` | Lure timer while you hold a fishing pole (red in the last 30 s, chime when it runs out) and a catch log per zone for all your characters; hover the timer or `/stzx fishing` to see this zone's catches |
| `StzxUI_ActionBars` | Restyles Blizzard's action bars (square icons with a 1-pixel border, StzxUI hover/pressed colours, tidy text, short keybinds, optional red icons out of range). Edit Mode still places and sizes them |
| `StzxUI_Nameplates` | StzxUI nameplates: health, name and level, raid marker, target outline with other plates faded, red edge when a mob attacks you, cast bars coloured by whether you can interrupt, your debuffs. Blizzard's plate stays (invisible) so clicking works; `/stzx test` shows pretend plates |
| `StzxUI_Blizzard` | Blizzard frames Edit Mode can't place, in StzxUI move mode (Blizzard group): alerts, error messages, zone text, capture bars and scores, boss banner, level-up toasts. Each can be switched off |
| `StzxUI_Inventory` | Remembers the bags, gear and bank of all your characters (and the account bank): item tooltips list who else has it, `/stzx items` searches them all. Read-only |
| `StzxUI_Minimap` | Square minimap with a 1-pixel border (black or accent), round frame art and zoom buttons hidden; tells minimap-button addons it's square; gathers addons' minimap buttons into a fly-out panel opened from the corner. Edit Mode still places it |

## Optional: JiberishUI Icons

If the separate [Jiberish Fabled Icons](https://www.curseforge.com/wow/addons/jiberish-fabled-icons) addon is installed, its class and race icon styles appear in StzxUI > Unit Frames > Portrait. StzxUI doesn't include or copy those icons; it asks the installed addon for them. JiberishUI Icons is © JiberishUI, LLC, and each style belongs to its artist (see that addon's LICENSE.md).

## Move mode

`/stzx move` (or the Unlock button in StzxUI's options) dims the screen, draws a grid and puts a labelled box over every StzxUI frame.

- Drag a box to move its frame. It lines up with nearby frames' edges, otherwise snaps to the grid; hold **Shift** to place freely.
- **Mouse wheel** over a box makes that frame bigger or smaller.
- Hover a box and use the **arrow keys** to nudge 1 unit (Shift + arrow: one grid step).
- **Right-click** a box to put that frame back where it started; **Reset all** does every frame.
- The toolbar switches grid and frame snapping, the grid size (8, 16, 32, 64), and has a **Show** row to hide groups of boxes (Info, Unit frames...). **Done**, **Escape** or entering combat closes it.

Positions are saved in the current profile.

## Profiles and sections

- **StzxUI > Profiles**: each character picks a profile. Make a new one from the current one, reset it, delete it, or **export** it as a text string and **import** a string from someone else.
- **StzxUI > Sections**: switch whole modules on or off for the profile (applies after a reload).
- A profile holds module options, frame positions and which sections are on. The grid and chat-notice options are the same on every character.
- When sharing a full setup, share two strings: the StzxUI profile, and your Blizzard **Edit Mode** layout (Edit Mode > Share) for the Blizzard frames StzxUI doesn't replace yet.

## Commands

- `/stzx` opens the settings
- `/stzx help` lists every command
- `/stzx move` unlocks frames for moving (again to lock)
- `/stzx profile` shows which profile this character uses
- `/stzx thanks <message>` sets the thank-you whisper (`%s` = their first name)
- `/stzx version`

## Installing for testing

Copy the `StzxUI`, `StzxUI_Social`, `StzxUI_Info`, `StzxUI_UnitFrames`, `StzxUI_Quests`, `StzxUI_Runs`, `StzxUI_Fishing`, `StzxUI_ActionBars`, `StzxUI_Nameplates`, `StzxUI_Blizzard`, `StzxUI_Inventory` and `StzxUI_Minimap` folders into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

Then restart the game (a brand-new addon folder needs a full restart; after that, `/reload` picks up code changes).

**Easier while developing:** link the folders instead of copying, so every save in the repo is live after a `/reload`. In a Windows Command Prompt:

```
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI" "C:\...\StzxUIAddon\StzxUI"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Social" "C:\...\StzxUIAddon\StzxUI_Social"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Info" "C:\...\StzxUIAddon\StzxUI_Info"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_UnitFrames" "C:\...\StzxUIAddon\StzxUI_UnitFrames"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Quests" "C:\...\StzxUIAddon\StzxUI_Quests"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Runs" "C:\...\StzxUIAddon\StzxUI_Runs"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Fishing" "C:\...\StzxUIAddon\StzxUI_Fishing"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_ActionBars" "C:\...\StzxUIAddon\StzxUI_ActionBars"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Nameplates" "C:\...\StzxUIAddon\StzxUI_Nameplates"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Blizzard" "C:\...\StzxUIAddon\StzxUI_Blizzard"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Inventory" "C:\...\StzxUIAddon\StzxUI_Inventory"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Minimap" "C:\...\StzxUIAddon\StzxUI_Minimap"
```

Install **BugSack** + **BugGrabber** to catch Lua errors, and send the error text back when something breaks.

## Checks before you load it in game

```
luacheck .
lua5.1 tests/harness.lua
```

GitHub runs both on every push (`.github/workflows/lint.yml`).

## Releases

Push a tag such as `v0.1.0`. GitHub Actions builds the zip and attaches it to a GitHub Release, which gives you a shareable download link. CurseForge upload can be switched on later (see `.github/workflows/release.yml`).

## Rules this project follows

- Other addons are studied for ideas and for which game functions work on Forever. Their code and art are never copied.
- Forever uses the modern client's addon rules: no combat log, and "secret" combat values. See `docs/forever-dev-notes.md`.
