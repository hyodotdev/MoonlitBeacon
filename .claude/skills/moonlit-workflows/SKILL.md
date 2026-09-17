---
name: moonlit-workflows
description: Use when a MoonlitBeacon repo request for commit/push/PR, a full check, Android device confirmation, all-direction E2E visual review of characters/monsters/items/graphics, course-clip capture, or starting a new lesson arrives in natural language without a slash command. Holds the rules, terminology (Lesson N), capture pipeline, and device-verification procedure for this monorepo of a Godot 4.7 game plus a Docusaurus course site.
---

# Moonlit Beacon workflows

Command definitions live in `.claude/commands/*.md`. On a natural-language
request, read the matching file and follow it.

| Request | Command |
| --- | --- |
| Commit / push / open a PR | `.claude/commands/commit.md` |
| Check / anything wrong / does it build | `.claude/commands/verify.md` |
| Put it on the phone / device check / APK | `.claude/commands/device.md` |
| Check characters, monsters, graphics / all-direction E2E | `references/visual-e2e.md` |
| Shoot a clip / record / video | `.claude/commands/record.md` |
| Start Lesson N / new lesson | `.claude/commands/chapter.md` |
| Ship / release / itch.io | `.claude/commands/release.md` |
| Store deploy / submit for review / App Store · Play | `.claude/skills/ship-release/SKILL.md` |
| Review / anything off | `.claude/commands/review.md` |

Whole-repo rules are in [`AGENTS.md`](../../../AGENTS.md). Below is the
summary.

---

## What this repo is

A 2D top-down dodge game **Moonlit Beacon** built in Godot 4.7.1, and a
**16-lesson course** of its making, managed in one repo.

```text
apps/game/      Godot project (res:// root)
apps/docs/      Docusaurus — docs/(reference) + course/(lessons) two instances
notes/          Author-only — plans, recording scripts, pipeline. Not on the site
_downloads/     Original asset ZIPs    (not in git)
_asset_sources/ Unpacked sources       (not in git)
builds/         Build and footage output (not in git)
```

---

## Do not break these

### Terminology

**Do not write "Phase".** Number lessons `Lesson 1`, `Lesson 2`. File names
are `chapter-01`, `chapter-02`. That applies to docs, commit messages, and
code comments.

### Docs

The docs site is **what students see**. Plans, recording scripts, capture
pipelines, and other production notes live in `notes/` and stay off the
site.

Do **not** put editorial policy or presenter directions in lesson prose.
Sentences like "this page is text-first and video is secondary", "you must
emphasize this", or "show this for at least 3 seconds" are for us. Send
them to `notes/`.

### Screen

**Whatever lesson you stop on, that screen must be usable as a store
screenshot.** No gray rectangles, debug text, default fonts, or placeholders
on screen. Do not prototype logic as gray boxes and skin it later.

On a request to confirm visual quality of characters, monsters, items, VFX,
or terrain, or "every direction", **read the whole**
[visual E2E evidence contract](references/visual-e2e.md) and follow it.
Pixel 10 device, full production-asset zoom, and automated contract checks
are different evidence. Do not report one scope passing as another scope
passing.

### git

**Do not push without user confirmation.** Commits are fine.

Never commit `.godot/`. It contains `export_credentials.cfg`, which holds
the Android signing keystore password.
`export_presets.cfg` has no secrets, so it is committed.
**Credentials stay out; presets go in.**

### Assets

Do not put originals in `res://`. The Ninja Adventure pack alone is 89MB.
**Copy only files actually used** into `apps/game/assets/third_party/` and
record them in the [asset manifest](../../../apps/docs/docs/assets/manifest.md).

Do not copy code or scenes from Ninja Adventure's Godot demo project.
Read it only as a reference for sprite-frame layout.

### Clips

What goes directly in the repo is **silent and under 1MB**. Narrated masters
live in `builds/footage/` and go to YouTube.
Do not check in a whole lesson. Attach a short clip only where you have to
see it to understand the section.

---

## Locked values (do not change)

| Item | Value |
| --- | --- |
| Engine | Godot 4.7.1 Standard, GDScript, Compatibility renderer |
| Target | Android first. Pixel 10 (2424×1080, arm64-v8a) |
| Screen | Landscape locked (`orientation=4`) |
| Internal resolution | 808×360 — 1/3 of Pixel 10 landscape, integer 3× |
| Stretch | `canvas_items` + `expand` |
| Texture filter | Nearest (`default_texture_filter=0`) |
| Controls | Floating move stick anywhere on screen + bottom-right dash button |
| Package name | `com.crossplatformkorea.moonlitbeacon` |
| Release | Android APK + itch.io |

---

## Things that often bite in this environment

### `godot` is not on PATH

The winget folder is on PATH, but the binary is named
`Godot_v4.7.1-stable_win64.exe`. Use the full path or `_console.exe`.

### Relative paths are relative to the `--path` folder

True for both `--export-debug` and `--write-movie`. From the repo root you
must write `../../builds/...`. `builds/...` points at `apps/game/builds/`,
and `--write-movie` **exits 0 and never creates the file.**
Godot will not create missing folders.

### Launch the app with `monkey`

`am start -n .../com.godot.game.GodotApp` is `SecurityException: not exported`.
The real launcher is `GodotAppLauncher`, but `monkey -p <pkg> -c
android.intent.category.LAUNCHER 1` is reliable.

### Do not put comments in `project.godot`

The editor strips them all on open-and-save. Write "why this value" in the
docs.

### Docs build needs a commit

`showLastUpdateTime` reads git log. Zero commits and `pnpm docs:build`
fails. The dev server is unaffected. The dev server returns 200 for missing
paths because of SPA fallback, so **dead links are caught only by the
build.**

### BOM direction is opposite

PowerShell `.ps1` **must have a BOM** or Hangul comments break.
`project.godot` **must not have a BOM** or Godot misreads key names.
`Set-Content -Encoding utf8` writes a BOM. Be careful.

### PowerShell `>` corrupts binaries

`adb exec-out screencap -p > x.png` is ruined.
Receive with `adb shell screencap` → `adb pull`.

### Capture on the right-hand monitor

A fullscreen game on the left monitor pins the cursor so clicks do not go
where you want.

Details are in the [recording pipeline](../../../notes/workflow/recording.md).
