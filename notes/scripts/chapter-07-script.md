---
sidebar_position: 6
title: Lesson 7 recording script
---

# Lesson 7 — Recording script

[Lesson text](../../apps/docs/course/chapter-07.mdx) · [Plan](../plans/chapter-07-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 16 min |
| Segments | 9 |
| Shot | Editor · game window · phone device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:40)

**On screen** — `chapter-07-ignite.mp4`

**Narration** — In Lesson 4 the arena lit the beacons in sequence. Nobody asked; it did it on its own.
Today the player lights them. Stand beside one and a ring at the feet fills; when full it lights.

## 2. What a signal is (0:40 ~ 2:30)

**On screen** — Bring up the one `signal lit_changed` line from Lesson 4 again

**Narration** — A signal is announcing that this happened.
The announcer does not need to know who is listening.
We already wrote one line in Lesson 4. The beacon only announces that it lit, and
listening and brightening the forest is the arena.
In this lesson that design pays off.

**Watch-outs** — You must mark "couldn't we just call the function."
You can. But then the beacon has to know the arena, and
the instant you put the beacon in another scene it breaks.

## 3. Check the official docs (2:30 ~ 3:00)

**On screen** — Godot official `Using signals`

## 4. Know you are beside it with Area2D (3:00 ~ 5:30)

**On screen** — Add `Reach` Area2D, `collision_mask = 2`

**Narration** — It only looks at what is on layer 2. We put the player there in Lesson 5.
When enemies appear in Lesson 8 we put them on another layer.
Then enemies lighting beacons is blocked automatically.
You do not have to ask in code "is this the player."

**On screen** — Only the north beacon's detect range is too small to light → after `_normalize_reach()`

**Narration** — In Lesson 3 we gave different scale for depth.
Area2D takes that as-is. The north beacon becomes 34 times 0.62, 21.
It was shrunk to look far away, not to be harder to approach.

**Watch-outs** — Run without `duplicate()` and show **all three beacon ranges becoming the same**.
You have to see by eye that instances share a resource.

## 5. Implement (5:30 ~ 12:30)

### 5-1. Fill and drain

**On screen** — Stand beside, leave, the ring rising and falling

**Narration** — We set drain 1.8 times faster.
A brief leave is not a big loss, and a real leave resets quickly.
1.3 seconds is a value we felt and decided. 0.5 seconds lights as you pass; 3 seconds is boring.

### 5-2. Why we count visitors

**On screen** — Change to a `bool` and it desyncs when wobbling at the edge

**Narration** — visitors is a count, not a boolean.
Area2D can repeat enter and exit when the same body wobbles at the edge.

### 5-3. Fill the ring without a shader

**On screen** — Stack two ring sheets and grow region. Without offset it grows from the top

**Narration** — A circular gauge usually uses a shader. We do not here.
Stack two copies of the same picture and grow only the top sheet's region.
Skip offset with it and the ring grows from the top, not the bottom.

**Watch-outs** — **Say honestly that a shader looks nicer.**
But this lesson's subject is signals, and pulling out a shader splits what you are teaching in two.

### 5-4. The ring is at the player's feet

**On screen** — A ring on each beacon, two visible between two beacons

**Narration** — Put one on the player and show the most-filled value.
The player does not know about beacons. The arena relays.
In Lesson 8 enemies use the same body, and enemies do not light beacons.

### 5-5. Sound

**On screen** — Light a beacon, quit the game, and `resources still in use at exit` appears

**Narration** — The flush logic we attached to music in Lesson 3 is needed here too.
But AudioStreamPlayer and 2D have split inheritance, so one script cannot serve both.
Pull only the wait part into AudioFlush and both sides use it.

**Watch-outs** — Emphasize **if you never lit one, there is no leak**.
That makes it easy to miss.

### 5-6. We did not change Lesson 4's code

**On screen** — `git diff` showing `_on_beacon_lit_changed` in `arena.gd` unchanged

**Narration** — We only deleted `_run_ignition_sequence()`.
We did not touch the forest-brightening function by a single character.
Even though the actor that lights moved from arena to player.
The pay-off of going through a signal in Lesson 4 lands here.

**Watch-outs** — **Put the diff on screen.** It is this whole lesson's conclusion.

## 6. Confirm (12:30 ~ 13:20)

**On screen** — Light the three beacons in sequence on a phone

## 7. Get it wrong on purpose (13:20 ~ 15:20)

**Narration** — Five things. Remove duplicate, change to bool, drop offset,
mask to 0, drop AudioFlush.

## 8~9. Completion criteria and homework (15:20 ~ 16:00)

**Narration** — Try homework 3. Attach the ring to the beacon and
between two beacons you see two. You will know why we put it on the player.
