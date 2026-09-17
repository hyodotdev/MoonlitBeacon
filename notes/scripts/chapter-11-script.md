---
sidebar_position: 10
title: Lesson 11 recording script
---

# Lesson 11 — Recording script

[Lesson text](../../apps/docs/course/chapter-11.mdx) · [Plan](../plans/chapter-11-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 12 min |
| Segments | 9 |
| Shot | Editor · **phone device (center)** |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:40)

**On screen** — `chapter-11-pause.mp4`

**Narration** — Until now we confirmed on a phone every lesson,
but it was not a state where you could play a run to the end. There was no way to pause.

## 2. A phone game can be interrupted at any time (0:40 ~ 1:40)

**Narration** — A desktop game only stops when the user decides to quit. A phone is different.
A call comes in, a notification appears, you have to get off the subway.
Without a way to pause, you lose a run every time.

## 3. Check the official docs (1:40 ~ 2:10)

**On screen** — Godot official `Pausing games`

## 4. What stops when you pause, and what does not (2:10 ~ 4:00)

**On screen** — Pause without giving `process_mode` and **you can never unpause**

**Narration** — paused stops every node. The pause panel stops too.
Then you cannot press Resume.

**Watch-outs** — **Actually make the state where you have to kill the app, and show it.**

**Narration (continued)** — Write it on the .tscn too.
If you only change it in _ready, the default still applies through that frame, so
if the scene pauses the instant it is created, you are too late.

## 5. Implement (4:00 ~ 9:00)

### 5-1. Button anchors

**On screen** — Leave preset 14 and on a phone **the button stretches across the full screen width**

**Narration** — 14 is HCENTER_WIDE. Full width, vertical center only.
anchor_left is 0, so offset -66 becomes "66 left of the left edge."
To put it in the center: preset 8, all four anchors 0.5.

**Watch-outs** — Mark that this is the cost of choosing expand in Lesson 1.
Screen width differs per device, so "center" must be said with anchors.

### 5-2. Pause on its own when the app goes to the background

**Narration** — When a call comes in, Android sends the app to the background.
Coming back with a spirit right in front of you feels unfair.

**Watch-outs** — Tell as a true story why you must not use FOCUS_OUT.
While making this lesson we used FOCUS_OUT and
every screenshot paused the game, so we wandered a long time thinking "the button does not press."

### 5-3. Hide the button after the run is over

### 5-4. Version 0.1.0

**On screen** — Change one line in `project.godot` and the title display follows

**Narration** — The pay-off of reading from ProjectSettings in Lesson 1 lands here.
You only have to change one place.

### 5-5. Put it on a phone

**On screen** — `pnpm android:build && pnpm android:run`

**Watch-outs** — Mark again after Lesson 1 that you must not drop `../../`.

## 6. Confirm (9:00 ~ 10:00)

**On screen** — On a phone, **play a run from start to finish**

**Watch-outs** — This is the core of this lesson. Do not cut in edit; show a whole run.

## 7. Get it wrong on purpose (10:00 ~ 11:30)

**Narration** — Four things. Drop process_mode, preset 14, drop set_available,
switch to FOCUS_OUT.

## 8~9. Completion criteria and homework (11:30 ~ 12:00)

**Narration** — Think about homework 2.
If you give ALWAYS only to Overlay, why can you not press the button before pausing.
