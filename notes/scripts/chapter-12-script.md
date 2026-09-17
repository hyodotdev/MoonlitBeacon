---
sidebar_position: 11
title: Lesson 12 recording script
---

# Lesson 12 — Recording script

[Lesson text](../../apps/docs/course/chapter-12.mdx) · [Plan](../plans/chapter-12-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 12 min |
| Segments | 9 |
| Shot | Editor · game window · phone device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:35)

**On screen** — `chapter-12-dash.mp4`

**Narration** — Through Lesson 11 it was a game that ran. From here we make a better game.
The only way to dodge a spirit was walking. Cornered in a tight spot, there is no answer.

## 2. What Lesson 6 prepared (0:35 ~ 2:00)

**On screen** — Put up the Lesson 6 text preview, and instance the stick scene one more time

**Narration** — In Lesson 6 we made it watch only its own finger.
Thanks to that, today's work is only placing the scene one more time. Just flip the anchors to the right.
Same as placing three beacons in Lesson 3.

## 3. Check the official docs (2:00 ~ 2:25)

**Narration** — This lesson is outside the official intro course. We look at Tween and SpriteFrames.

## 4. Not while pushing — at the moment of release (2:25 ~ 4:00)

**On screen** — Fire while pushing and **it fires in a nonsense direction the instant the thumb lands**

**Narration** — This is the most important judgment.
Fire while pushing and there is no time to pick a direction.
It fires in the direction of the tiny wobble at the instant the thumb lands.
Stand the stick, aim, let go, and it fires.

**Watch-outs** — Also mark that you must capture `_value` before zeroing it.
Reverse the order and it always fires 0. Actually swap it and show that it does not fire.

## 5. Implement (4:00 ~ 9:30)

### 5-1. Ignore the stick during a dash

**On screen** — Without the guard, dash while holding the left stick and it does not fire

**Narration** — Same problem as Lesson 8 knockback. The left hand erases the dash as-is.

### 5-2. Cooldown

**Narration** — Without it you only move by dashing. Walking loses meaning.
1.15 seconds is just a little longer than the spirit hit cooldown of 1.1 seconds.
After one hit and getting out, you have to wait tightly until the next dash.

### 5-3. Afterimages

**On screen** — Attach as a child of the player and **it follows** → attached to the parent

**Narration** — Afterimages must stay on the path already traveled.
As a child they move together and become a shell, not a trail.

**Watch-outs** — Show them **invisible** at alpha 0.5.
On a dark background, translucency is much dimmer than you think.
We only knew after pulling frames at 30fps and counting pixels while making this lesson.

### 5-4. Tell whether dash is ready

**Narration** — We do not use a number. Counting a 1.15-second cooldown in seconds is noisy.
Sharp or faded is enough. Same approach as Lesson 10's hearts.

## 6. Confirm (9:30 ~ 10:20)

**On screen** — On a phone, walk and dash **with both hands**

**Watch-outs** — Two-hand simultaneous control is only confirmed on a phone. Must be on device.

## 7. Get it wrong on purpose (10:20 ~ 11:40)

**Narration** — Five things. Drop the dash guard, reverse the `last` order,
afterimages as children, cooldown 0.1, alpha 0.3.

## 8~9. Completion criteria and homework (11:40 ~ 12:00)

**Narration** — Try homework 2. Change the afterimages to beacon orange and
they are confused with the spirit's blue. Think about what color does in the game.
