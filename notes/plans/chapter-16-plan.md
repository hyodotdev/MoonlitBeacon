# Lesson 16 — Plan

## Official tutorial mapping

Outside the official intro course. See `Exporting for Android` · `NOTIFICATION_WM_GO_BACK_REQUEST`.

## Goal

Make it shippable. Back button, version 1.0.0, signed APK, store page.

**A person uploads to itch.io.** Prepare copy and images, then hand them over.

## Changes

### 1. Back button — the core of this lesson

What Lesson 11 deferred as "Lesson 16 will cover this."
The default is **quit from any screen**. Survive 80 seconds, tap it by accident, and it closes.

Turn it off with `config/quit_on_go_back=false` and we decide.

| Current screen | Back |
| --- | --- |
| Credits → Settings → original screen | Close windows first |
| Playing → Pause → Title | One step at a time |
| Result screen | **Does nothing** |
| Title | Ask whether to quit (default focus is `Cancel`) |

Why the result screen does not accept it: you spent 90 seconds, the score is up, and backing out
means **you leave without seeing the record.**

Expose one `request_pause()` on `pause_panel.gd`.
Calling `_pause()` from outside is awkward, and a finished run must not pause.

### 2. Version

| | |
| --- | --- |
| `project.godot` `config/version` | `1.0.0` — bottom-right of the title |
| `export_presets.cfg` `version/name` | `1.0.0` — inside the APK |
| `version/code` | `1` — integer. You cannot redistribute with the same value |

The title reads from `ProjectSettings` (Lesson 1 set that up).
Hand-write it on the screen and the next version will definitely drift.

### 3. Signing — what this repository cannot do

:::danger Lose the keystore and you cannot ship updates
Sign the same package name with a different key and **it will not even install.**
You have to wipe and reinstall, and saved records disappear.
:::

This repository has no release keystore (confirmed `.godot/export_credentials.cfg` is absent).
**A person creates it and a person signs.** The docs only record the commands and how to verify.

Commit `export_presets.cfg`; do not commit `.godot/export_credentials.cfg`.
Share settings, do not share secrets.

### 4. Store page

`notes/release/store-page.md` has Korean and English descriptions, controls, credits,
release notes, and install instructions written so you can paste them as-is.

The copy is not for the maker to write; **it is for a player to read.**
Not "an enemy system built with custom resources" but "spirits come out of the dark and chase you."

### 5. Screenshots

6 shots in `builds/release/screenshots/` (1616 × 720), cover 630 × 500.
All pulled from Movie Maker renders.

We also tried `adb shell screenrecord` and **color washes out.** Contrast muddies and
a green cast appears. Stills are better with `screencap`; clips are better as renders.

## Verification

| | |
| --- | --- |
| Device title back | Quit confirm window |
| Device quit confirm → Cancel | Return to title |
| Device back while playing | Pause (app stays) |
| Device pause back | Title |
| Version | `v1.0.0` on the title |
| Translation | 35 keys, two languages |

## Completion criteria

- [ ] Back walks screens one at a time
- [ ] Title asks whether to quit
- [ ] Version is 1.0.0 in both places
- [ ] Store copy and screenshots are ready
- [ ] `pnpm verify` 0

## Human work (handed off)

- [ ] Create and back up a release keystore
- [ ] Signed APK with `--export-release`
- [ ] Confirm with `apksigner verify --print-certs`
- [ ] itch.io upload · confirm `Restricted` then `Public`
- [ ] Turn on GitHub Pages at `Settings ▸ Pages ▸ Source = GitHub Actions`
      (it is not on, so `deploy-docs.yml` keeps failing)

## Not this lesson

- Play Store — developer fee and review are outside the course
- Windows / Web builds — scoped out from the start
- Auto upload (butler) — the first ship is by hand and by eye
