---
sidebar_position: 15
title: Lesson 16 recording script
---

# Lesson 16 — Recording script

[Lesson text](../../apps/docs/course/chapter-16.mdx) · [Plan](../plans/chapter-16-plan.md) · [Store copy](../release/store-page.md) · [Checklist](../release/checklist.md)

| Item | Value |
| --- | --- |
| Target length | 17 min |
| Segments | 9 + wrap |
| Shot | Editor · terminal · device · browser (itch.io) |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:50)

**On screen** — `chapter-16-complete.mp4`

**Narration** — The game is all made. Nobody can play it yet.
Today we make it shippable.

## 2. "It's all made" and "it can ship" are different (0:50 ~ 2:20)

**On screen** — Install the Lesson 15-state APK on device, press back while playing → the app closes

**Narration** — You survived 80 seconds and it vanished with one finger.
This is the default behavior. Nobody tells you.

## 3. Check the official docs (2:20 ~ 3:00)

**On screen** — Godot official `Exporting for Android`

## 4. Back button (3:00 ~ 6:30)

**On screen** — The "Lesson 16 will cover this" line in the Lesson 11 text

**On screen** — `quit_on_go_back=false`, write `_notification`. Reproduce the `chapter-16-back.mp4` flow

**Narration** — What Android expects is walking screens back one at a time.

**Watch-outs** — Make the result screen accept back too, and show leaving without seeing the score.

**Watch-outs** — Put the quit-confirm default focus on `Quit` and press Enter.
Asking becomes meaningless.

## 5. Implement (6:30 ~ 13:00)

### 5-1. Version lives in two places

**On screen** — `project.godot` and `export_presets.cfg` side by side. `v1.0.0` on the title

**Watch-outs** — Try redistributing without bumping `version/code`.

### 5-2. Keystore

**On screen** — Create a keystore with `keytool`. **Cut the password-entry screen.**

**Narration** — Lose this file and password and you cannot ship updates.
Sign the same package name with a different key and it will not even install.
The user has to wipe and reinstall, and records disappear.

**On screen** — The `.godot/` line in `.gitignore` and `export_credentials.cfg`

**Narration** — This is the most important reason we do not commit `.godot/`.

### 5-3. Release build

**On screen** — `pnpm android:release`, `apksigner verify --print-certs`

**Watch-outs** — Show that calling `godot --export-release` directly bypasses IAP plugin isolation and Gradle
clean. The itch.io APK must be made with the script.

**Watch-outs** — Run `apksigner` on a debug build and show `CN=Android Debug`.

### 5-4. Confirm permissions

**On screen** — `aapt dump permissions`

### 5-5. On a wiped device

**On screen** — Install after `adb uninstall`. First launch taking the path where there is no save file

**Narration** — It is `uninstall`, not `pm clear`. The "does not die if the file is missing" code
we made in Lesson 14 is confirmed here.

### 5-6. Store page

**On screen** — Paste the copy into a new itch.io project screen

**Narration** — The copy is not for the maker to write; it is for a player to read.
Not "an enemy system built with custom resources" but
"spirits come out of the dark and chase you."

### 5-7. Private first

**On screen** — Leave it `Restricted`, open the link on another device, download and install

## 6. Confirm (13:00 ~ 15:00)

**On screen** — Walk the checklist and press the six things on device yourself

## 7. Get it wrong on purpose (15:00 ~ 16:00)

Six things. What section 5 already showed, mark briefly.

## 8~9. Completion criteria and last homework (16:00 ~ 16:40)

**Narration** — Homework 1, back up the keystore now.
This is the most irreversible mistake in this course.

## Wrap (16:40 ~ 17:00)

**On screen** — Lesson 1's empty-project screen and Lesson 16's device screen side by side

**Narration** — In the middle we came back several times.
Lesson 6's bounds widened in Lesson 9, and Lesson 8's hit detection was rewritten in Lesson 9.
That is normal. Try to get it right from the start and you cannot start anything.

**Narration** — If you take only one thing, it is that you do not know until you put it on screen.
Lesson 14's beacon bug was there for five lessons.
What looks fine when you read it and what looks fine when you run it are different.
