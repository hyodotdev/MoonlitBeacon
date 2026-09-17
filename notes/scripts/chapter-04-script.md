---
sidebar_position: 3
title: Lesson 4 recording script
---

# Lesson 4 — Recording script

[Lesson text](../../apps/docs/course/chapter-04.mdx) · [Plan](../plans/chapter-04-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 18 min |
| Segments | 9 |
| Shot | Editor · game window · **phone device** |
| Render sources | `builds/footage/chapter-04-*.avi` · `chapter-04-device.mp4` |

**Section numbers are 1:1 with the [lesson text](../../apps/docs/course/chapter-04.mdx).**

## Already shot

| Section | Repo clip (silent · captions) | Render source |
| --- | --- | --- |
| 1. Finished screen | `chapter-04-device.mp4` | `builds/footage/chapter-04-device.mp4` |
| 5. Implement | `chapter-04-ignite.mp4` | `builds/footage/chapter-04-ignite.avi` |

## 1. Finished screen (0:00 ~ 0:50)

**On screen** — `chapter-04-device.mp4`

**Narration** — Through Lesson 3 we did write scripts. Centering the screen, flushing audio,
swapping scenes — backstage work. Today is different. Code holds the game's state.
Is the beacon on or off: that one slot appears, and the screen follows it. Beacons start unlit
and light one by one, and each lighting brightens the forest moonlight one step.

**Watch-outs** — First show clearly that an unlit beacon looks like a "cold pile of stones."
Only then does the contrast at the moment fire catches land.

## 2. A script is something you attach to a node (0:50 ~ 2:20)

**On screen** — Attach Script on the `beacon.tscn` root. In the arena, all three beacons have that script

**Narration** — A Godot script is where you write a node's behavior.
If a scene is "what is there," a script is "what it does."
Attach it to the beacon-scene root and the three beacons placed as instances of that scene all have that script.
Each runs on its own, and each has its own values.

## 3. Check the official docs (2:20 ~ 2:50)

**On screen** — Browser. Godot official `Creating your first script`

**Narration** — The official docs spin one icon around.
In the same slot we put a beacon's on and off state.
Today we look at Exporting variables and Setters and getters together with that.

## 4. The debt from Lesson 3 (2:50 ~ 4:00)

**On screen** — Bring up the Lesson 3 text's danger box again → the three `[editable` lines in `arena.tscn`

**Narration** — Last session, to give each beacon a different flicker speed,
we turned on Editable Children. We wrote this then.
"The instant you turn it on, that instance depends on inner structure." Time to pay.

**Narration (continued)** — The way to pay is the beacon script exporting the speed.
Then the arena does not even need to know a node called Flicker exists.
But you have to make the script first for that slot to appear. The actual pay-off is 5-4.

**Watch-outs** — Do not make them operate here. State the concept only and hand it to 5-4.
Flip the order and you are telling them to put a value in a slot that does not exist yet.

## 5. Implement (5:00 ~ 12:00)

**On screen** — `chapter-04-ignite.mp4`

### 5-1. Attach a script to the beacon

**On screen** — Put up the unlit/lit table and move it into code as-is

**Narration** — First we decide how an unlit beacon differs from a lit one.
Pit color, light, glow, three particles, flicker. Write that as-is into the setter.

**On screen** — Leave `lit = false` and run → `null instance` error

**Narration** — Do it this way and it dies.
If the inspector has lit set to false, when the scene is built
that value arrives before the @onready variables are filled.

**Watch-outs** — **Actually produce the error.** Put the message on screen and read it.
Then show putting the guard in, and calling once more from `_ready()`.
Also actually try skipping the second: there is no error, but a beacon you turned off starts lit.
**The quiet-wrong side is more dangerous.**

### 5-2. Make the moment fire "catches"

**On screen** — Snapping on with `lit = true` → swelling then settling with `ignite()`

**Narration** — Turn it on immediately and the beacon pops in. It does not feel like fire catching.
Swell the light once from 0 then settle and it is much better.
Hold flicker during that, then hand it over when it ends.
Measure and it jumps from 29 past 210, 229, then comes down to 225.

**Watch-outs** — Show both side by side. It is 0.45 seconds, so seeing it once is hard.

### 5-3. Visible in the editor too

**On screen** — Attach `@tool` and toggle `lit` in the inspector

**Narration** — Put @tool at the top and the script also runs in the editor.
You see it immediately without running the game. There are three beacons, so it is much better.

**Watch-outs** — Also say @tool is dangerous.
The editor really runs this code. An infinite loop and the editor stops.
Signals must not fire during edit either, so block them with is_editor_hint.

### 5-4. Pay Lesson 3's debt

**On screen** — Export `flicker_speed` with `@export` → in the arena, turn off
Editable Children on the three beacons → in the inspector, `Lit` off and `Flicker Speed` 0.87 / 1.24 / 1.03

**Narration** — Now we can make the slot.
In the arena, turn off Editable Children on the three beacons.
Then the overrides we put in Lesson 3 disappear, so we put the same values in the new slot again.
0.87, 1.24, 1.03. The same values we used in Lesson 3. They have to differ so each rides its own beat.
Turn Lit off here too. Leave it and the default is on, so
all three beacons are already burning from the start and the ignition flourish never happens.

**Watch-outs** — Open the `.tscn` as text and **show the `[editable` lines gone yourself.**
Three vanished lines beat the words "we paid."
Then confirm one by one in the inspector that the three values differ.

### 5-5. Announce that the beacon lit

**On screen** — One line: `signal lit_changed`

**Narration** — Brightening the forest is not the beacon's job.
The beacon only announces the fact that it lit. It does not need to know who is listening.
Right now the arena listens, but later a scoreboard can listen too and the beacon stays the same.
Handling signals properly is Lesson 7. Here we write only one line.

### 5-6. The arena brightens the forest

**On screen** — Write `_on_beacon_lit_changed` and run

**Narration** — We only count how many are lit. Which number lit does not matter.
Multiply 1.14 three times and it is about 1.48 times; when all three are lit the forest is about half again as bright.

**Narration (continued)** — The two lines that kill the tween have nothing to do at the current spacing.
It finishes brightening inside 1.1 seconds and the next lights 2.6 seconds later, so they do not overlap.
In Lesson 7, when the player starts lighting, they can light two in a row. That is what this is for.

**Watch-outs** — Say "they do not overlap now" honestly.
The overlap case is reproduced in section 7 item 3 by shrinking the gap.

### 5-7. Light them in sequence

**On screen** — Write `_run_ignition_sequence()`. Guard after `await`

**Narration** — Right now the arena lights them on its own.
In Lesson 7 that changes so the player lights them by standing beside them, and then you only delete this function.
Brightness only listens to the signal, so it does not care who lit it.
During three 2.6-second waits you can press back.
After await, always check is_inside_tree.
When we faded music and swapped scenes in Lesson 3 we put the same guard for the same reason.

## 6. Confirm (12:00 ~ 13:00)

**On screen** — Terminal `pnpm game:check` · measurement table

**Narration** — At the moment a beacon lights, that spot jumps from 29 to 224.
The forest climbs like stairs from 14.9 to 25.0.
Not "it seems brighter" — we measure and confirm.

## 7. Get it wrong on purpose (13:00 ~ 14:40)

**On screen** — Four things in turn

**Narration** — First, delete one line in `_ready()` and a beacon you turned off starts lit.
No error. Second, delete the null guard and a Nil error appears in the console,
but the game does not stop and the result is still correct. `_ready()` corrects it afterward.
Exactly the kind you skip with "it runs, so it's fine."
Third, shrink the gap to 0.6 and delete the two tween-kill lines and
the forest only brightens to 39.8, not 42.9.
Fourth, delete @tool and it is invisible in the editor; you have to run to see it.

## 8~9. Completion criteria and homework (14:40 ~ 16:00)

**On screen** — Lesson-text checklist

**Narration** — The checklist has an item confirming there is no `[editable`.
That is checking whether we paid last session's debt.
Please do homework 3. Change the `_beacons` order and the lighting order changes.
Which beacon lights as which number is the arena's decision, and the beacon itself does not know —
that is the core of this structure.
