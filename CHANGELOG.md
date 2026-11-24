# Changelog

## Unreleased

### Added
- Unit Frames: player and target frames. Round class icon or character portrait with a level badge, health (number, percent or both), power numbers, class/reaction colours, mirrored target. Click to target, right-click for the menu, works in combat. Each has its own movable cast bar (countdown, channels drain, interrupted/failed in red).
- Unit Frames: hides Blizzard's player and target frames (option).
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
