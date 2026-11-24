# WoW: Forever addon development notes

Collected 2026-11-23 against Forever 1.60.1 build 71037 (Gethe/wow-ui-source `forever` branch, commit 734f065).
Things the game client does that matter for StzxUI. Recheck after each patch.

## The client

| Fact | Detail |
|---|---|
| Interface number | `16001` |
| Client family | Modern (Midnight 12.1.x) UI code, vanilla content. Blizzard: Forever "shares Mainline WoW's UI architecture, including the vast majority of APIs available in 12.1.5". |
| Game type | `Camelot`. `WOW_PROJECT_ID == WOW_PROJECT_CAMELOT` |
| TOC suffix | `MyAddon_Forever.toc` or `MyAddon_Camelot.toc` (plain `MyAddon.toc` with 16001 also works) |
| AddOns folder | `World of Warcraft\_forever_\Interface\AddOns` (the beta used `_classic_beta_`) |

## Addon restrictions (same as retail Midnight)

- **Secret values.** In combat, encounters, PvP matches and some other moments, combat-related APIs return secret values (health, auras, cooldowns, threat, casts, tooltip text). Addon code can store them, pass them to widgets (e.g. `StatusBar:SetValue`) and show them, but cannot compare, test, index, do maths or measure their length. Test with `issecretvalue(v)`; `C_Secrets.ShouldAurasBeSecret()` says whether aura data is currently locked.
- **No combat log.** `COMBAT_LOG_EVENT_UNFILTERED` and `CombatLogGetCurrentEventInfo()` are not available to addons. Use Blizzard's built-in Damage Meter and Cooldown Manager instead of rebuilding them.
- **Chat and addon messages** are restricted inside instances/encounters. Trial accounts can't send addon messages.
- **No WeakAuras on Forever.**
- Some legacy globals exist only as deprecation shims (`DoEmote`, `IsSpellKnown`, `GetSpellInfo`...). Prefer the `C_` namespaced versions (`C_ChatInfo.PerformEmote`, `C_SpellBook.*`, `C_Spell.*`).

## Showing combat values (checked against the 1.60.1.71037 API docs)

| Need | Use | Why it works with secrets |
|---|---|---|
| Health/power bar | `bar:SetMinMaxValues(0, UnitHealthMax(u))`, `bar:SetValue(UnitHealth(u))` | `SetMinMaxValues`/`SetValue` accept secret arguments from addons |
| Health number text | `AbbreviateLargeNumbers(UnitHealth(u))` into `SetText`/`SetFormattedText` | both accept secrets; returns a secret string |
| Health percent | `UnitHealthPercent(u, false, CurveConstants.ScaleTo100)` | percent 0-100 without addon maths |
| Cast bar with secret times | `bar:SetMinMaxValues(startMS, endMS)` then `bar:SetValue(GetTime() * 1000)` each frame | bar does the maths; countdown text can't be shown |
| Anything you branch on | `StzxUI.Plain(v)` first | testing a secret raises an error |

`UnitHealth` and `UnitHealthPercent` are marked `SecretReturns`; `UnitHealthMax`, `UnitPower`, `UnitCastingInfo` turn secret only in restricted situations. `StatusBar:SetTimerDuration` does **not** accept secret arguments from addons.

## Forever-specific quirks found in other addons' notes

- **Names have surnames.** `UnitName(unit)` returns `first, surname` on Forever (a realm elsewhere). Whisper targets are the full two-word name.
- **Macro unit conditionals** like `[@player]` / `[@unit]` don't resolve on Forever.
- **Aura source** (`aura.sourceUnit`) can be nil even when the caster is visible; code defensively.
- **Quest events** pass a single quest ID (modern style), not index + ID.
- **Professions** come from `C_SkillInfo`; the old global skill-line API is gone. Match professions by skill line ID, not name.
- **Ace3** (latest release r1390, Feb 2026) doesn't list Forever. Questie ships a small `SetDesaturation` shim for AceGUI on Forever. StzxUI uses Blizzard's own `Settings` API for options instead, so it doesn't need AceGUI.
- **World map libraries:** HereBeDragons v34 recognizes Forever. Krowi's world-map-buttons library needs a fix on Forever (Questie patches its `HasNoOverlay` flag).
- **Settings with "shown" predicates** got one addon tainted through Blizzard's options search. Keep option pages simple.
- **CVars persist** in `WTF/Config.wtf`. An addon that changes a CVar must restore it when turned off.

## Public APIs other addons offer (integration instead of rebuilding)

| Addon | API | Use for StzxUI |
|---|---|---|
| Questie | `Questie.API` (`RegisterOnReady`, `RegisterForQuestUpdates`, `GetQuestObjectiveIconForUnit`) | Quest markers on StzxUI nameplates/frames |
| OpenMap | `OpenMapAPI` (`RegisterMenuToggle`, `RegisterDungeonSection`, `ShowWorld`, `WorldFromMap`, callbacks) | Add StzxUI layers/toggles to the map instead of owning it |
| DaylightUI | `DaylightUI.API` (documented in its `API.md`) | Only if StzxUI ever plugs into DaylightUI; not planned |

## Reference sources

- Blizzard UI source: https://github.com/Gethe/wow-ui-source (branch `forever`)
- API dumps, CVars, GlobalStrings: https://github.com/Ketho/BlizzardInterfaceResources (branch `forever`)
- Forever API change notes: https://warcraft.wiki.gg/wiki/Patch_1.60.1/API_changes
- Secret values explained: https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes
- Game data tables per build: https://wago.tools (DB2 tables; Forever builds 1.60.1.x)
- Forever item/quest data: Wowhead's Forever database; ForeverDB.app
