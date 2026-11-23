# StzxUI: notes for Claude Code

Scott's personal UI suite for WoW: Forever. Scott is learning addon development as we go: explain changes in plain words, keep code readable and commented, and prefer small working steps he can test in game.

## The game client

- WoW: Forever 1.60.1, `## Interface: 16001`. Built on the **modern (Midnight) client**, not the Classic Era client. Use modern APIs (`C_UnitAuras`, `C_ChatInfo`, `C_AddOns`, `C_Container`, `Settings`), not Classic-era globals.
- Game type is `Camelot`; `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT`. TOC suffixes `_Forever` and `_Camelot` both work.
- Live AddOns folder: `World of Warcraft\_forever_\Interface\AddOns`.
- Blizzard's own UI code for this client: `github.com/Gethe/wow-ui-source`, branch `forever`. Read how Blizzard does something before writing it. API docs live in `Interface/AddOns/Blizzard_APIDocumentationGenerated`.

## Hard rules

1. **No copying other addons.** Read them for ideas and to see which API calls work on Forever; write StzxUI's own code. This applies even to MIT/GPL addons (Scott's choice). Libraries meant for embedding (LibStub, CallbackHandler, LibSharedMedia, HereBeDragons) are fine, with their licenses kept.
2. **Secret values.** In combat, encounters and PvP, many values (health, auras, names in tooltips, chat in instances) come back secret. Code may display them but may not compare, test, index or do maths on them. Pass anything you branch on through `StzxUI.Plain()` (secret -> nil). Check `C_Secrets.ShouldAurasBeSecret()` before reading aura payloads.
3. **No combat log.** `COMBAT_LOG_EVENT_UNFILTERED` is not available to addons. Don't design features that need it; Blizzard's built-in Damage Meter and Cooldown Manager cover that ground.
4. **Two-part names.** `UnitName()` returns first name and **surname** on Forever (not realm). Whispers need the full "First Surname".
5. **Macros:** `[@unit]` conditionals don't resolve on Forever.
6. **Combat lockdown:** no changes to secure frames, bindings or protected attributes in combat.
7. **Every feature gets a setting** in the StzxUI options page; slash commands are shortcuts.
8. Lua 5.1, tab indents. Run `luacheck .` and `lua5.1 tests/harness.lua` before handing work back; add a harness check for new logic.
9. Say honestly what has only been tested offline. The harness fakes the client; only the game proves it works.

## Layout

- `StzxUI/` core: `Core.lua` (modules, saved settings, `/stzx`), `Settings.lua` (options page helpers).
- `StzxUI_<Module>/` one folder per module, `## Dependencies: StzxUI`, registers with `StzxUI:NewModule(name, addonName, defaults)` and implements `OnInitialize` (build settings page) and `OnEnable` (register events).
- `tests/harness.lua` offline fake client.
- `docs/` notes, not packaged.

## Releasing

Only when Scott asks. Update `CHANGELOG.md`, tag `vX.Y.Z`, push the tag; `.github/workflows/release.yml` builds the zip with BigWigsMods/packager.
