# Changelog

## Unreleased

### Added
- Unit Frames: player and target frames. Round class icon or character portrait with a level badge, health (number, percent or both), power numbers, class/reaction colours, mirrored target. Click to target, right-click for the menu, works in combat. Each has its own movable cast bar (countdown, channels drain, interrupted/failed in red).
- Unit Frames: hides Blizzard's player and target frames (option).
- Runs (new section): dungeon and raid run history per character: time, XP (across level-ups), gold gained or spent, bosses killed, deaths, and green-or-better loot you picked up. A /reload or quick disconnect inside keeps the same run. Movable run timer while inside; `/stzx runs` opens the history window (hover a run for its bosses and loot). Loot rolls you win aren't counted: the game keeps loot messages secret inside instances.
- Quests: party quest status. A small panel beside the quest giver window and the quest log's detail page lists your party and whether each is on that quest (On it / Not on it / Offline). The quest log panel has Share and Share all (one quest a second); `/stzx shareall` does the same.
- Move mode works alongside Blizzard's Edit Mode: opening Edit Mode opens move mode too (and closes it again), the toolbar moves to the top-left out of Edit Mode's way, StzxUI uses Edit Mode's grid size while its grid is showing, and StzxUI frames snap to the edges of Blizzard's frames (action bars, minimap, chat...). Setting: "Open with Edit Mode".
- Info: levelling pace readout, "Lv 18  45%  12.3k xp/h  1h 05m": XP per hour this session and the time to the next level at that pace. Movable, hidden at max level; `/stzx xp` restarts the count.
- Quests (new section): quests new to WoW: Forever get a glow on the parchment (quest giver window and quest log detail page); colour, strength and height adjustable. Quest item sparkles stay on after graphics presets. `/stzx quest` tells you whether the open quest is new.
- Party & Raid (new section): StzxUI party and raid frames. Health, name, debuffs (all, or only ones you can remove), range fading, target highlight, leader crown and raid markers; left-click targets, right-click opens the menu, in combat too. Size, spacing, growth and power bar are adjustable live, and each has a mover. Blizzard's party and raid frames are hidden while StzxUI's are on.
- Unit Frames: focus frame (with its own cast bar), and small target-of-target and pet frames. Each can be switched off; Blizzard's versions are hidden where StzxUI shows its own.
- Unit Frames: buffs and debuffs on both frames: duration swipe, stack count, debuff border by type, tooltip on hover. Options per frame: show buffs, show debuffs, only my debuffs (target), icon size, above or below. Works in combat (the game filters; StzxUI only displays).
- Move mode: snap to other frames' edges and centres, mouse wheel to resize a frame (saved per profile), a Show row to hide groups of boxes.
- Accent colour option: StzxUI blue or your class colour.
- StzxUI's addons are grouped together in the AddOn list.
- Unit Frames: optional JiberishUI Icons support. With that addon installed, its class and race styles are portrait choices; NPCs fall back to their face.

### Fixed
- Characters were saved as "Name - " on Forever (the game gives no realm name). Now just "Name"; existing choices carry over.
- Core: profiles. Each character picks one; new from current, reset, delete, export and import as a text string. Your existing settings move into a "Default" profile automatically.
- Core: move mode (`/stzx move`): grid from the screen centre, snap to grid (Shift to place freely), arrow-key nudge, right-click to reset one frame, Reset all, closes in combat.
- Core: Sections switches to turn whole modules on or off per profile.
- Core: StzxUI pop-up window for names, profile strings and "reload now?".
- Info: movable FPS/latency/clock readout and map coordinates.
- Core: StzxUI options page, saved settings, `/stzx` command, module system.
- Social: decline duel requests (and duels to the death), with an optional chat notice.
- Social: thank players who buff you, by emote or whisper, out of combat only, once per player per few minutes.
