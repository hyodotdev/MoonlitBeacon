---
sidebar_position: 13
title: Lesson 14 recording script
---

# Lesson 14 — Recording script

[Lesson text](../../apps/docs/course/chapter-14.mdx) · [Plan](../plans/chapter-14-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 14 min |
| Segments | 9 |
| Shot | Editor · game window |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:40)

**On screen** — `chapter-14-score.mp4`

**Narration** — Until now there were only two outcomes, win or lose. There was nothing that
said how well you did. Today we score, stamp a rank, and leave the best record on the device.

## 2. What does score praise (0:40 ~ 3:00)

**On screen** — Put up the score table and walk the items one by one

**Narration** — A score formula decides what the game is telling you to do well.
Beacon 300, remaining time 12 per second, remaining heart 250, escape 500.

**On screen** — A run with `if not escaped: return "D"` deleted. Light beacons only and wait 90 seconds

**Narration** — Delete this one line and lighting beacons and waiting becomes the optimal strategy.
You get an S. There is no reason to escape.

**On screen** — Revert and the same play. 1,904 points but **D**

**Narration** — A 1,904-point D. Change the score and the game changes.

## 3. Check the official docs (3:00 ~ 3:30)

**On screen** — Godot official `Singletons (Autoload)` · `ConfigFile`

## 4. What survives across scenes (3:30 ~ 5:00)

**On screen** — Show the line in the Lesson 9 text that says "Lesson 14 will cover this"

**Narration** — What Lesson 9 deferred is this. `reload_current_scene()` wipes everything.
Only the best record has to remain.

**On screen** — Register `Records` in Project Settings ▸ Autoload

**Watch-outs** — Also move arena state onto the autoload, and show that after restart the beacons stay lit.
What Lesson 9 made collapses.

## 5. Implement (5:00 ~ 11:00)

### 5-1. Score as a data type

**On screen** — Write `score.gd`

**Narration** — The arena fills it and the result panel draws. Both only know this type.
Same principle as Lesson 10 HUD. The drawing side does not calculate.

### 5-2. Save with `ConfigFile`

**On screen** — Write `records.gd`. Open `records.cfg` with `Project ▸ Open User Data Folder`

**Watch-outs** — Treat `cfg.load() != OK` as an error, delete the save file, run, and show
**the first launch dying**. A missing file is not an error.

**Narration** — Change it to `res://` and it will not save. In an exported game that path is read-only.

### 5-3. The numbers climb

**On screen** — Chain `tween_method`. Run and they climb in sequence

**Narration** — Chain on one tween and they run in sequence. You do not need four timers.
A value passed with `bind()` attaches **after** the value the tween gives.

**Watch-outs** — Try making it by **adding** lines one by one, and show the label growing
and overlapping what is below.

### 5-4. Like a stamp landing

**On screen** — `_stamp_in()`. Slow playback of overshooting slightly then coming back with `TRANS_BACK`

**Watch-outs** — Run without `pivot_offset` and show it stretching down-right.

### 5-5. The flourish must be skippable

**On screen** — Tap during the flourish. It winds to the end but does not restart

**Narration** — It is a 2.2-second flourish. On the tenth run it is in the way.
Skip and play-again are different actions.

**Watch-outs** — `kill()` only, do not fill the values, and show it stopping at `Total 1,847`.

### 5-6. Place them so they do not overlap

**On screen** — Screenshot of the first layout, stamp covering the title and `New best!` covering the prompt

**Narration** — Empty labels will not tell you they overlap. We only knew after actually rendering
a screen with values filled in. UI you have to look at after the values are in.

### 5-7. The result screen found Lesson 9's gap

**On screen** — Two device screenshots. Result beacons 0 / HUD beacons 1/3

**Narration** — We put it on a phone, lost the first run, and the two numbers differed on the same screen.
We died beside a beacon, and Lesson 9's `_over` only stops the arena.
The beacon runs on its own clock. Behind the panel it lit itself.

**On screen** — Write `Beacon.freeze()`, call it from `_finish()`. Reproduce the same situation

**Narration** — It was there for five lessons until we printed the beacon count on screen.
It was not visible anywhere. Put a number out and the mismatch shows.

## 6. Confirm (11:00 ~ 12:00)

**On screen** — Finish a run → score → again → quit the app → relaunch. Best record remains

## 7. Get it wrong on purpose (12:00 ~ 13:30)

Seven things in turn. What section 5 already showed, mark briefly and move on.

## 8~9. Completion criteria and homework (13:30 ~ 14:00)

**Narration** — Homework 1, try setting `PER_SECOND` to 0.
The reason to hurry disappears. You feel immediately that score is the rule.
