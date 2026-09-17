---
sidebar_position: 12
title: Lesson 13 recording script
---

# Lesson 13 — Recording script

[Lesson text](../../apps/docs/course/chapter-13.mdx) · [Plan](../plans/chapter-13-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 15 min |
| Segments | 9 |
| Shot | Editor · game window |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:40)

**On screen** — `chapter-13-kinds.mp4`

**Narration** — There was only one spirit. For the whole 90 seconds the same thing chases at the same speed.
Today we grow to three kinds, and when the last beacon lights, the Forest Guardian appears.
The scene is still one.

## 2. Make three scenes and you lose (0:40 ~ 2:30)

**On screen** — Make a state with `spirit.tscn` copied three times, show it, then delete

**Narration** — The easiest method is copy. And that is what this course has been avoiding the whole time.
Fix one hit cooldown and you have to fix three places; thirteen kinds and it is thirteen places.
One scene, several settings. We use a custom resource.

## 3. Check the official docs (2:30 ~ 3:00)

**On screen** — Godot official `Resources`

## 4. Slice the sheet in code (3:00 ~ 6:00)

**On screen** — Write `_apply_kind()`. Swap `.tres` in the inspector and the enemy changes

**Narration** — Through Lesson 3 we wrote AtlasTexture into the tscn.
Four kinds and that becomes four too.

**Watch-outs** — Skip `remove_animation("default")` and show an empty animation remaining.

**On screen** — Zoom the Guardian sheet (250×50, one row)

**Narration** — Only the Guardian's layout is different. 50-pixel cells, one row, so there is no facing.
That is why we exported cell, rows, columns all as settings.
Hard-code even one of those and you cannot add the Guardian.

**Watch-outs** — Drop `mini()` and spawn a Guardian, and show **it dying on a missing animation**.

## 5. Implement (6:00 ~ 12:00)

### 5-1. It comes out of the dark

**On screen** — Leave a fixed spawn, stand top-left, and it comes out in your face

### 5-2. It appears gradually

**Narration** — While appearing you cannot hit it. Getting hit before you have a body is unfair.
Same judgment as turning monitoring on late for Lesson 9's moonlight gate.

### 5-3. It gets fiercer as the run progresses

**Narration** — We pick by lit beacon count, not time.
It gets hard faster for people who are good, and slower for people who wander.

### 5-4. Guardian — the small fry fall back

**On screen** — Without retreat, **you die the instant the last beacon lights**

**Narration** — We just added the Guardian and one Guardian plus three spirits charged at once.
With 3 health it was not hard, it was impossible. We learned by actually making it.

**Watch-outs** — **You must show this failure.** Difficulty you only know by measuring.

### 5-5. The music changes

**Narration** — In Lesson 3 we picked the arena track as the one with the smallest swing.
Here we pick by the opposite criterion. Measure with the same ruler and take the other end.

### 5-6. Handling several

**Narration** — Strip dead ones before use.
Putting is_instance_valid in early in Lesson 9 pays off here.

## 6. Confirm (12:00 ~ 12:50)

## 7. Get it wrong on purpose (12:50 ~ 14:30)

**Narration** — Five things. Drop retreat, drop materialize, fixed spawn,
drop mini, MAX_SPIRITS 12.

## 8~9. Completion criteria and homework (14:30 ~ 15:00)

**Narration** — Please do homework 1.
Make one more `.tres` and a fifth enemy appears. You do not write a single line of code.
