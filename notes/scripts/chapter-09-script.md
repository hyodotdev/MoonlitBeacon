---
sidebar_position: 8
title: Lesson 9 recording script
---

# Lesson 9 — Recording script

[Lesson text](../../apps/docs/course/chapter-09.mdx) · [Plan](../plans/chapter-09-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 15 min |
| Segments | 9 |
| Shot | Editor · game window · phone device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:50)

**On screen** — `chapter-09-win.mp4` and `chapter-09-lose.mp4`

**Narration** — Until now there was no end. Light all the beacons and nothing happens, and
you can keep walking after a hundred hits from a spirit.
Today we make a run.

## 2. A run has state (0:50 ~ 2:30)

**On screen** — Without `_over`, health going negative behind the panel

**Narration** — "Is it over" is the most important thing.
Without it the game keeps running behind the panel.
The spirit keeps chasing, health goes negative, and the panel stacks several times.

**Watch-outs** — **Actually print negative health and show it.**

## 3. Check the official docs (2:30 ~ 3:00)

**On screen** — Godot official `The main game scene`

**Narration** — The official example makes a separate Main scene.
For us the arena is that place. There is not enough to manage to justify another scene.

## 4. Moonlight gate (3:00 ~ 5:00)

**On screen** — Showing a gray gate in advance, wandering toward it → making it invisible

**Narration** — Draw a closed gate in gray and people wander toward it from the start.
To teach that the beacons come first, it is better for the gate to be absent then appear.

**On screen** — Grazing it while it opens and the run ending → after the `monitoring` treatment

**Watch-outs** — **You must reproduce this empty win.**

## 5. Implement (5:00 ~ 11:30)

### 5-1. Lesson 6's bounds trip us

**On screen** — Put up the preview sentence from the Lesson 6 text, and even with the gate open you cannot go

**Narration** — In Lesson 6 we wrote this.
"In Lesson 9 a moonlight gate opens at the edge of the forest. Then this rectangle will not be enough."
It happened as written.

**Watch-outs** — Mark that if Lesson 6 had put a collider on every tree, we would have to retouch everything today.
**Knowing it would change later and keeping it simple means two lines to fix.**

### 5-2. While overlapping you must keep getting hit

**On screen** — Standing still 24 seconds on device and **getting hit only once**

**Narration** — The cooldown we put in Lesson 8 had a gap.
body_entered fires only at the moment of entry.
If the spirit keeps overlapping while pushing, the second signal never comes.
We stood still 24 seconds on device and got hit exactly once and it ended. Health is 3 and you do not die.

**Watch-outs** — **Use the device footage as-is.** Headless could not catch this.

**Narration (continued)** — A signal is a "change", not a "state."
To ask whether you are inside now, you have to look at state directly with has_overlapping_bodies.
Lesson 7's beacon counting visitors is the same reason.

### 5-3. Result panel

**On screen** — Without the 0.6s wait, at the moment of loss the panel is not seen and it restarts immediately

**Narration** — At the moment of loss the hand is still on the stick.
Accept as-is and it restarts before you even see the panel.

### 5-4. Restart

**Narration** — One line: reload_current_scene.
Code that reverts state one field at a time grows one more place to miss every time a value grows.

### 5-5. Do not touch something already freed

**Narration** — Right now there is one spirit and it is not freed.
But in Lesson 13 they are created and destroyed.
A reference grabbed with @onready remains even after the node is freed.

## 6. Confirm (11:30 ~ 12:20)

**On screen** — On a phone, standing still and losing, then winning the next run

## 7. Get it wrong on purpose (12:20 ~ 14:20)

**Narration** — Five things. Drop `_over`, drop `_try_hit`, drop `set_bounds`,
drop the 0.6s wait, drop `monitoring`.

## 8~9. Completion criteria and homework (14:20 ~ 15:00)

**Narration** — Please do homework 3.
Revert by hand instead of reload_current_scene and count how many you miss.
Three beacons, health, spirit position, gate, bounds, panel… count them and you will know.
