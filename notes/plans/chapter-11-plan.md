# Lesson 11 — Plan

## Official tutorial mapping

`Step by step / Finishing up` · `Pausing games` · `Exporting for Android`

## Goal

Make it possible to **play a full run to the end** on a phone. Pause is that last piece.
Bump the version to `0.1.0`.

## Changes

### 1. `pause_panel.tscn` · `pause_panel.gd`

Top-right `II` button → overlay (Paused · Resume · Restart).

`process_mode = ALWAYS`. `get_tree().paused` **stops every node**, so if this panel
stops too you can never unpause. **Write it on both the `.tscn` and in code** —
if you only change it in `_ready()`, the default still applies through that frame, which
is too late if the scene pauses the instant it is created.

### 2. Button anchors — caught on device

At first we used `anchors_preset = 14` and **the button stretched across the full screen width.**
14 is `HCENTER_WIDE` (full width, vertical center only), so `anchor_left = 0`,
`anchor_right = 1`.

Switch to `preset 8` (`CENTER`) and set all four anchors to `0.5`.

This is the cost of choosing `expand` in Lesson 1. Screen width differs per device, so
"center" must be said with anchors.

### 3. Auto-pause when the app goes to the background

`NOTIFICATION_APPLICATION_PAUSED`. If a call comes in and you return with a spirit right
in front of you, it feels unfair.

:::danger Do not use `FOCUS_OUT`
We first used `NOTIFICATION_APPLICATION_FOCUS_OUT` and
**every `adb exec-out screencap` paused the game**, so we spent a long time thinking
"the button does not press." Even a notification banner dropping down fires it.
:::

### 4. Hide the button when the run is over

`set_available(false)`. Stacking it on the result panel looks ugly, and there is no reason to pause.

### 5. Version 0.1.0

Change `project.godot` in one place and the title display follows (Lesson 1 already reads it
from `ProjectSettings`).

## Verification

| | |
| --- | --- |
| Time change while paused | 0.0 |
| After Resume | −0.84 (it flows again) |
| Device | Overlay shown, resume confirmed |
| APK | 31.5 MB |

## Completion criteria

- [ ] You can play a full run to the end on a phone
- [ ] Pause and resume at any time
- [ ] Time does not count down while paused
- [ ] Coming back from background, the game is paused
- [ ] Title shows `v0.1.0`
- [ ] `pnpm game:check` 0

## Deferred to Lesson 12

- Right dash stick (Lesson 6 already prepared `_touch_index`)

## Not this lesson

- Signed APK — Lesson 16
- Settings — Lesson 15
