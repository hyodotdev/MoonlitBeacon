---
sidebar_position: 5
title: Lesson 6 recording script
---

# Lesson 6 — Recording script

[Lesson text](../../apps/docs/course/chapter-06.mdx) · [Plan](../plans/chapter-06-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 16 min |
| Segments | 9 |
| Shot | Editor · game window · **phone device (required)** |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:40)

**On screen** — `chapter-06-stick.mp4`

**Narration** — The ninja was only standing. Today we make it walk.
It is a phone game, so there is no keyboard. Press the lower-left of the screen with a thumb and
a joystick stands there, and the ninja walks in the pushed direction.

## 2. Why a floating stick (0:40 ~ 2:20)

**On screen** — Draw a fixed stick and overlay large-hand and small-hand positions

**Narration** — A stick fixed in one place is easy to make.
But hold a phone landscape and the spot a thumb reaches differs per hand.
A large hand is too far inward; a small hand cannot reach. Change phone size and both are wrong.
A floating stick appears where you press. Wherever you rest the thumb, that is the center.

## 3. Check the official docs (2:20 ~ 2:50)

**On screen** — Godot official `Listening to player input`

**Narration** — The official example uses keyboard arrow keys.
We are touch, so we handle InputEventScreenTouch and Drag ourselves.

## 4. There are several fingers (2:50 ~ 4:20)

**On screen** — Touch the screen with two fingers and show `index` printing differently in output

**Narration** — This is the place people get wrong most often. A mouse is one; fingers are several.
When a dash stick appears on the right in Lesson 12, events come in on two lines.
Each event has an index attached. You have to watch only your own finger.

**Watch-outs** — Also say that on a computer it is a mouse, so there is only one finger.
Two-finger motion is only confirmed on a phone.

## 5. Implement (4:20 ~ 12:30)

### 5-1. A pad that receives the left half

**On screen** — Pin with `anchors_preset = 9` and it stays the left half even if you change window width

**Narration** — We picked expand in Lesson 1, so width differs per device.
Pin with anchors and it still holds the left half on a wide phone.

### 5-2. Stand it where you press

**On screen** — Press here and there on the left and the stick stands in a different spot each time

**Narration** — origin is the center. How far you pushed from here is the input.
accept_event is a mark that this event ends here.
Skip the call and things behind receive the same touch again.

### 5-3. If the finger leaves the pad

**On screen** — Without `_input()`, slide the thumb right and **the character keeps walking**

**Narration** — This is the second trap.
_gui_input only receives what happened inside that control.
Slide the thumb outside the left half and from that instant events stop coming.
The stick stays on and the character keeps walking. Even if you let go it does not stop.

**Watch-outs** — **You must make this state first and show it.**
Say it only in words and why we use two functions will not land.

**Narration (continued)** — Receive once more with _input. This side sees the whole screen.
Converting coordinates to this control with make_input_local must not be skipped either.
Skip the convert and the stick is drawn far from the finger.

### 5-4. Dead zone

**On screen** — Dead zone 0, rest a thumb, and it creeps

**Narration** — Resting a thumb is not a zero value. The hand trembles slightly.
Inside 16% of the radius we treat it as 0.
Go past 0.3 and it feels like you pushed and it did not go. Hold a phone and feel it to decide.

### 5-5. Move

**On screen** — `move_toward` and `move_and_slide()`

**Narration** — The player does not read the stick itself. The arena reads and forwards.
In Lesson 8 enemies use the same body, and enemies have no stick.
When we add dash in Lesson 12 we also will not touch the input side.
The player only needs to know "go this way."
Whether that direction comes from a finger or from AI, it does not need to know.

### 5-6. Cannot leave the forest

**On screen** — Walking into the trees with no bounds → after clamp

**Narration** — A collider on every tree is the proper way.
But the forest has 1,296 nodes. That becomes a different job unrelated to what this lesson teaches.
We clamp coordinates. When the moonlight gate opens in Lesson 9 this rectangle will not be enough.
For now we just know this will change later, and move on.

### 5-7. Walk animation

**On screen** — Judging with `_wish`, feet stop while sliding → with `velocity`

**Narration** — You have to look at velocity. Even after you release the stick, while it is sliding it is still walking.
Look at _wish and it moves without moving its feet.

## 6. Confirm (12:30 ~ 13:20)

**On screen** — Phone in hand, operated with a thumb

**Watch-outs** — This lesson **must be confirmed on device.**
A mouse is only one finger, so you only confirm half.

## 7. Get it wrong on purpose (13:20 ~ 15:20)

**On screen** — Five things

**Narration** — First, delete _input and when you slide the thumb right the character keeps walking.
Second, dead zone 0 and resting a finger still moves it.
Third, deleting the touch_index check does not show yet. We see it in Lesson 12.
Fourth, judge walking with _wish and the feet stop while sliding.
Fifth, delete the facing guard we put in Lesson 5 and **it looks down every time you let go.**
That is the treatment Lesson 5 said "does not show yet."

**Watch-outs** — The fifth is the join with Lesson 5, so you must include it.

## 8~9. Completion criteria and homework (15:20 ~ 16:00)

**Narration** — Please do homework 1. Change speed to 40 and 200 and
the reason we picked 96 is felt in the body. You do not measure a number; you feel it and decide.
