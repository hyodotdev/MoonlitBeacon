---
sidebar_position: 9
title: Lesson 10 recording script
---

# Lesson 10 — Recording script

[Lesson text](../../apps/docs/course/chapter-10.mdx) · [Plan](../plans/chapter-10-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 13 min |
| Segments | 9 |
| Shot | Editor · game window · phone device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:35)

**On screen** — `chapter-10-hud.mp4`

**Narration** — Lesson 9 made a run, but nothing was visible.
How much health is left, how many beacons you lit, how much time has passed.
Today we put that on screen.

## 2. HUD decides nothing (0:35 ~ 2:00)

**On screen** — Show code with rules in the HUD, then delete it

**Narration** — This is the most important principle. HUD only draws values it is given.
The judgment that health 0 means over is the arena's.
If that rule goes into HUD, game rules get written in the file that draws the screen.

## 3. Check the official docs (2:00 ~ 2:30)

**On screen** — Godot official `Heads-up display`

## 4. Nine-patch (2:30 ~ 4:00)

**On screen** — 16px source → a 120-wide panel. Margin 8, it breaks

**Narration** — We make a 120-wide panel from a 16 by 16 source.
Split into nine pieces, leave the four corners as-is, and stretch only the edges and center.
Margin 5 and the stretching center is only 6 pixels. Margin 8 and it becomes 0 and breaks.

## 5. Implement (4:00 ~ 9:30)

### 5-1. Do not make the heart two pictures

**On screen** — Switching to an empty-heart picture, the slot wobbles → only lowering alpha

**Narration** — The sheet has an empty heart, but we do not use it.
Switch two pictures and the slot wobbles slightly. In pixel art even 1 pixel shows.

### 5-2. mouse_filter all Ignore

**On screen** — Leave only the root Control as Stop and **the stick dies wholesale**

**Narration** — Same problem as Lesson 8's flash rectangle.
The hearts are top-left, but the root Control covers the whole screen, so
even that one Stop kills the stick.

**Watch-outs** — **You must reproduce this and show it.** If you do not know the cause you wander a long time.

### 5-3. Time limit

**On screen** — With `floorf`, it shows 1:29 the instant you start

**Narration** — We use ceilf. floor and even 0.01 seconds past 90.0 becomes 89.
Without maxf, after time runs out it prints negatives.

### 5-4. Turn red when little time remains

**Narration** — Shrinking numbers alone do not tell you it is urgent. Change the color and the eye knows first.

### 5-5. Draw once at start

**On screen** — Skip the initial draw and the first screen is empty

**Narration** — Draw only when a value changes and the first screen shows nothing.
Same reason Lesson 4's beacon re-hooks setters in _ready.

## 6. Confirm (9:30 ~ 10:20)

**On screen** — On a phone, getting hit, hearts shrinking, time turning red

## 7. Get it wrong on purpose (10:20 ~ 12:20)

**Narration** — Five things. mouse_filter Stop, floorf, drop maxf,
skip the initial draw, nine-patch margin 8.

## 8~9. Completion criteria and homework (12:20 ~ 13:00)

**Narration** — Homework 2 is fun. Raise the warning time to 60 seconds and
it is red the instant you start, so the urgent feeling disappears. A warning has to be rare to be a warning.
