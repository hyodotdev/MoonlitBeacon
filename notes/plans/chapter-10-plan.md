# Lesson 10 — Plan

## Official tutorial mapping

`Step by step / Heads-up display`

## Goal

Put three health hearts · beacons n/3 · remaining time on screen as wood UI.
And add a **90-second time limit**.

## Changes

### 1. Two assets

`Ui/Receptacle/Heart.png` (80×16, 5 stages) · `Ui/Theme/Theme Wood/nine_path_panel.png` (16×16).

The heart has 5 stages, but **we use only the full one.** Empty slots are alpha 0.24.
Switching two pictures makes the slot wobble slightly — in pixel art even 1px shows.

### 2. `hud.gd` — decides nothing

It only draws values it is given. "Health 0 means over" is the arena's judgment.
If HUD holds rules, every time you open that file in Lessons 14 and 15 you have to be careful with game rules.

### 3. Nine-patch

`StyleBoxTexture` + `texture_margin = 5`. The stretching center of a 16px source is only 6px,
so use it **only at 12×12 or larger**. Margin 8 breaks the panel.

### 4. `mouse_filter` all Ignore

Same trap as Lesson 8's `HitFlash`. **If even the root `Control` is `Stop`, the stick dies.**
Give it to the panel, containers, and labels, all of them.

### 5. Time limit

`TIME_LIMIT = 90`. The arena counts it.

Use `ceilf` — `floorf` shows `1:29` the instant you start.
Without `maxf(seconds, 0)` it prints negatives after time runs out.

Below 15 seconds **the color turns red.** Shrinking numbers alone do not tell you it is urgent.

### 6. Draw once at start

If you only draw when a value changes, the first frame is empty.
Same reason Lesson 4's beacon re-hooks setters in `_ready()`.

## Verification

| | |
| --- | --- |
| Start | hearts [1,1,1], `Beacons 0/3`, `1:30` |
| One beacon | `Beacons 1/3` |
| One hit | hearts [1, 1, 0.24] |
| After 1s | `1:29` |

Device: hearts 3→0, beacons 0/3→1/3, time 1:28→1:23 confirmed.

## Completion criteria

- [ ] Three hearts sit on a wood panel
- [ ] Hits fade them, lighting a beacon changes the number
- [ ] Time counts down and turns red below 15 seconds
- [ ] Time running out is a loss
- [ ] **The stick still works with HUD present**
- [ ] `pnpm game:check` 0 · manifest 0 · media 0

## Deferred to Lesson 11

- Unsigned release APK, finish a run on device
- Pause and restart

## Not this lesson

- Score — Lesson 14
- Settings — Lesson 15
