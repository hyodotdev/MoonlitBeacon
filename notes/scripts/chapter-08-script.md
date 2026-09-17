---
sidebar_position: 7
title: Lesson 8 recording script
---

# Lesson 8 — Recording script

[Lesson text](../../apps/docs/course/chapter-08.mdx) · [Plan](../plans/chapter-08-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 14 min |
| Segments | 9 |
| Shot | Editor · game window · phone device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:35)

**On screen** — `chapter-08-chase.mp4`

**Narration** — Until now lighting a beacon had no interference. You just walked over and stood.
Today we add a spirit. It appears from the dark, chases the ninja, and on contact the screen flashes red.

## 2. An enemy has the same structure as the player (0:35 ~ 2:00)

**On screen** — `player.tscn` and `spirit.tscn` trees side by side

**Narration** — Almost the same. Only Hitbox differs.
The pay-off of pulling the player into its own scene in Lesson 5 lands here.
We already know how to make it, so slice the sheet and attach and we are done.

**Watch-outs** — Mark the speed difference. 96 versus 62.
If the spirit is faster there is no way to run, so there is no game.

## 3. Check the official docs (2:00 ~ 2:30)

**On screen** — Godot official `Creating the enemy`

## 4. Layers become the rule (2:30 ~ 5:00)

**On screen** — Change the spirit layer to 2 and **the spirit lights a beacon** → revert to 4

**Narration** — This is the most important part.
In Lesson 7 we made the beacon detect area look only at layer 2. Put the spirit on 4 and
the spirit cannot light a beacon. We did not ask in code "is this the player."

**Watch-outs** — **You must show the spirit lighting a beacon after changing the layer to 2.**
"It does not light" is slower to understand than "do this and it lights."

**Narration (continued)** — Filter by name and the condition grows every time enemies grow.
Even when Lesson 13 has three kinds, the layer setting stays.

## 5. Implement (5:00 ~ 10:30)

### 5-1. Chase, but do not stick

**On screen** — Sticking tight with `velocity = wish * speed` → after `lerp`

**Narration** — Snap it in and the spirit sticks tight and follows.
When it turns it turns on a zero-radius, so there is no way to dodge.
lerp turns slowly, so it makes a wide turn, and you can cut and shake it.
TURN_RATE is the difficulty knob.

### 5-2. Who to chase is the arena's decision

**Narration** — The spirit does not search the scene. The arena puts it in.
Same judgment as Lesson 7 keeping the player unaware of beacons.

### 5-3. On contact

**On screen** — Cooldown 0, overlapping, flashing continuously

**Narration** — body_entered fires once, at the moment of entry.
But if the spirit pushes and wobbles at the edge, enter and exit repeat.
When Lesson 10 adds health, that one burst wipes all three hearts.

### 5-4. Red flash

**On screen** — `mouse_filter` set to Stop and **the stick dies**

**Narration** — Same as what we learned in Lesson 4. Kill the previous tween before making a new one.
And you must give mouse_filter Ignore.
Skip it and the rectangle covering the whole screen eats touches, so the stick does not work.

**Watch-outs** — **Actually show the stick dying.** If you do not know the cause you wander a long time.

### 5-5. Knockback

**On screen** — Getting hit while holding the stick still knocks back / without the guard, it does not get pushed

**Narration** — Flash alone is weak. The body has to be pushed for it to reach the hand.
But if you do not ignore the stick during the push,
next frame velocity returns to the stick direction.
The hand holding the stick erases the knockback as-is.
We skip reading for only 0.18 seconds. Measured push is 48 pixels.

## 6. Confirm (10:30 ~ 11:20)

**On screen** — On a phone, being chased while lighting a beacon

## 7. Get it wrong on purpose (11:20 ~ 13:20)

**Narration** — Six things. Layer to 2, drop lerp, cooldown 0,
mouse_filter Stop, drop the knockback guard, speed 120.

## 8~9. Completion criteria and homework (13:20 ~ 14:00)

**Narration** — Try homework 2. How many seconds to place one more spirit.
Same as placing three beacons in Lesson 3.
