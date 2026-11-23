# StzxUI

A personal UI suite for **World of Warcraft: Forever** (game version 1.60.1, interface 16001).
Built one module at a time; every module is its own addon folder, so any part can be switched off in the AddOns list.

## What's in it so far

| Folder | What it does |
|---|---|
| `StzxUI` | Core: settings page (Esc > Options > AddOns > StzxUI), saved settings, `/stzx` command |
| `StzxUI_Social` | Declines duel requests. Thanks players who buff you (emote or whisper, out of combat, with a cooldown per player) |

## Commands

- `/stzx` opens the settings
- `/stzx help` lists every command
- `/stzx thanks <message>` sets the thank-you whisper (`%s` = their first name)
- `/stzx version`

## Installing for testing

Copy the `StzxUI` and `StzxUI_Social` folders into:

```
World of Warcraft\_forever_\Interface\AddOns\
```

Then restart the game (a brand-new addon folder needs a full restart; after that, `/reload` picks up code changes).

**Easier while developing:** link the folders instead of copying, so every save in the repo is live after a `/reload`. In a Windows Command Prompt:

```
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI" "C:\...\StzxUIAddon\StzxUI"
mklink /J "C:\...\World of Warcraft\_forever_\Interface\AddOns\StzxUI_Social" "C:\...\StzxUIAddon\StzxUI_Social"
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
