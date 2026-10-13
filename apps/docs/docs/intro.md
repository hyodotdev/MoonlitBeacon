---
sidebar_position: 0
slug: /intro
---

# Getting started

Start here if you want to run this game yourself.
To follow the course in order, go to the [course guide](/course).

:::info Two different goals, two different folders
**Running the complete game** means cloning this repository and opening the
finished Godot project inside it. **Following the course** means building a
separate blank project of your own, lesson by lesson. The blank project lives
outside any clone — never create it inside one, and never run `git init`
inside a folder you cloned. The course guide's
[two-folder section](/course#two-folders-your-blank-project-and-this-repository)
shows the exact layout.
:::

## What you need

| | |
| --- | --- |
| Engine | Godot — minimum 4.7.1 Standard, recommended 4.7.2 (see [Godot version](#godot-version)) |
| Language | GDScript (no extra install) |
| Clone tools | Git, plus Node.js 20+ and `pnpm` for the repository's shortcut commands |
| Assets | [Download the assets](./assets/download-guide.md) — all free |
| Phone | An Android device. Install and check at the end of every lesson, starting with Lesson 1 |

## Running the game

These steps run the **complete game from a clone**:

1. Install Godot for your OS ([Godot version](#godot-version): minimum
   4.7.1 Standard, recommended 4.7.2).
2. Install Node.js 20+ and `pnpm`, then clone the repository into its own
   folder (not inside your course project, if you have one):

   ```bash
   git clone https://github.com/hyodotdev/MoonlitBeacon.git
   cd MoonlitBeacon
   pnpm install
   ```

3. Download nothing: the clone already includes every selected playable
   asset, so the complete game runs as cloned. Original-pack downloads are
   only for the blank-project asset-selection exercise — see
   [Download the assets](./assets/download-guide.md) when you follow the
   course.
4. In the Godot Project Manager, open `apps/game/project.godot`. Open the
   project in the editor once before any command-line launch: a first clean
   import prints missing-generated-translation messages until the editor has
   imported.

## Godot version

| | |
| --- | --- |
| Minimum (course baseline) | Godot 4.7.1 Standard — the version the lessons were written against ([exact 4.7.1 archive](https://godotengine.org/download/archive/4.7.1-stable/)) |
| Recommended (latest stable as of 2026-10-13) | Godot 4.7.2 Standard ([exact 4.7.2 archive](https://godotengine.org/download/archive/4.7.2-stable/)) |
| Export templates | Must match the editor exactly — a 4.7.2 editor needs 4.7.2 templates, from the same archive page |

What was actually checked: both editors (`4.7.1.stable.official.a13da4feb`
and `4.7.2.stable.official.ed1daf0bf`) compiled the 174 shipping scripts and
booted the shipping title for 30 frames with clean post-import logs — and the
full practice run passes all 16 reference checkpoints on each editor
(desktop/headless, 2026-10-13). Those checks do not cover phone runs,
exports, sign-in, or newer engine versions: anything untested stays outside
the tested range until it is checked the same way. The production engine lock
stays 4.7.1 regardless.

To run from the command line (inside the clone):

```bash
pnpm game
```

:::tip It is fine if `godot` is not on PATH
Installing Godot often does not give you a command named `godot`.
The executable in the install folder is named with a version, like
`Godot_v4.7.1-stable_win64.exe`.

`pnpm game` above finds the executable for you. If it cannot, it tells
you where it looked, and you can set `GODOT_BIN` to the full path.

```bash
# Windows
set GODOT_BIN=C:\...\Godot_v4.7.1-stable_win64_console.exe
# macOS / Linux
export GODOT_BIN=/path/to/godot
```
:::

## Running on a phone

These commands also run **inside the clone**. In the Godot editor, set up
the Android build template and a debug keystore first.

```bash
pnpm android:build
pnpm android:run
```

`android:build` cleans the build template and Gradle output, and isolates
the Play Billing plugin from the direct-distribution APK. Do not call
Godot yourself for Android export.

:::danger Do not bypass the wrapper for Android export
`pnpm android:build` prepares relative paths and the output folder. The
wrapper also isolates the Play Billing plugin from the direct-distribution
APK, so do not call `godot --export-debug` yourself. (This rule is for the
complete game inside a clone. Your separate blank course project has no
wrapper, so it uses plain `godot` export commands instead — Lesson 1,
section 8 shows both.)
:::

:::warning `am start` will not launch it
`adb shell am start -n com.crossplatformkorea.moonlitbeacon/com.godot.game.GodotApp`
fails with `SecurityException: not exported`. `GodotApp` is an internal
activity. The real launcher activity is `com.godot.game.GodotAppLauncher`.
Throwing a launcher intent with `monkey`, as above, is the safest way.
:::

## This game's display settings

| Item | Value |
| --- | --- |
| Internal resolution | **808 × 360** |
| Orientation | **landscape locked** (`Sensor Landscape`) |
| Stretch | `canvas_items` / `expand` |
| Texture filter | `Nearest` |
| Renderer | Compatibility |

**Why 808 × 360.** Pixel 10 landscape is 2424 × 1080.
808 × 360 is **exactly 1/3** of that, so it scales by an integer 3×.
16px pixel art does not land on a half pixel. At 16px tiles that is 50
tiles across and 22.5 down, so one arena fits on one screen.

**Why `expand` instead of `keep`.** Android devices have many aspect
ratios. `keep` makes black-bar thickness differ by device. `expand` fills
the screen with no bars and extra width becomes extra view. So UI anchors
to the screen edges, and the background image is shifted by the leftover
width to stay centered.

**Physics at 30Hz, render interpolated.** `physics_ticks_per_second=30`
fits a mobile CPU and battery budget. The display draws at 60Hz or more,
so without interpolation a moving body sits on each physics tick for
several frames and you get **judder that looks like two overlapping
characters**. `physics_interpolation=true` interpolates between the last
two physics ticks on every render frame and removes that. `physics_jitter_fix=0.0`
turns off a correction that overlaps with interpolation — Godot 4 ignores
jitter fix when interpolation is on, so the value itself does not change
behavior. On teleports (zone changes, post-spawn placement) call
`reset_physics_interpolation()` so a trail does not streak across the screen.

## Repository layout

```text
MoonlitBeacon/
  apps/
    game/            # Godot project (res://)
    docs/            # this site
  _downloads/        # original ZIP files     (gitignored)
  _asset_sources/    # unzipped originals     (gitignored)
  builds/            # build output           (gitignored)
```

Do **not** put original asset packs inside `res://`. The full Ninja
Adventure pack is about 89MB, and Godot would import unused images and
music too. The project gets heavy and the files you need get hard to find.
Copy **only the files you actually use** into
`apps/game/assets/third_party/`.
The current game holds 75 selected third-party files plus original and
derived work, 259 files in all (about 26.5MB). About 15MB of that is the
Noto Sans CJK font that draws Korean, Chinese, and Japanese player names
clearly. The `.import` files Godot makes automatically are not in that count.
