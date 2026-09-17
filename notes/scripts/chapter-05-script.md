---
sidebar_position: 4
title: Lesson 5 recording script
---

# Lesson 5 — Recording script

[Lesson text](../../apps/docs/course/chapter-05.mdx) · [Plan](../plans/chapter-05-plan.md) · [Recording pipeline](../workflow/recording.md)

| Item | Value |
| --- | --- |
| Target length | 14 min |
| Segments | 9 |
| Shot | Editor · game window · phone device |

**Section numbers are 1:1 with the lesson text.**

## 1. Finished screen (0:00 ~ 0:45)

**On screen** — `chapter-05-device.mp4`

**Narration** — Three beacons stand in the night forest. Now we make the person who will stand in that forest.
Today we do not move. We only stand.
Instead we make standing properly. Cast a shadow, rise and fall like breathing,
and beside a beacon, firelight lingers.

## 2. Why its own scene (0:45 ~ 2:00)

**On screen** — `player.tscn` tree

**Narration** — Same reason we pulled the beacon out in Lesson 2.
When we make enemies in Lesson 8 we use the same structure as-is.
We only have to make the player new.
The root is CharacterBody2D because Lesson 6 will use move_and_slide.
Change the root type later and every child and script shakes.

## 3. Check the official docs (2:00 ~ 2:30)

**On screen** — Godot official `Creating the player scene`

**Narration** — The official example puts in two animations.
We put in 4 directions times 2 states, eight. It is top-down, so we need facing.

## 4. Reading a sprite sheet (2:30 ~ 4:30)

**On screen** — Zoom `ninja_walk.png` 6× and walk columns and rows

**Narration** — Columns are direction and rows are frames. Get that backwards and facing changes while walking.
Column 0 shows the face so it is down, column 1 the back of the head so up, columns 2 and 3 left and right profiles.

**Watch-outs** — **Zoom the sheet itself, not a document.**
Packs differ, and even inside the same pack characters differ.

## 5. Implement (4:30 ~ 11:00)

### 5-1. Idle is only one frame

**On screen** — A ninja frozen on one idle frame → after the breathe animation

**Narration** — The Idle sheet is one frame per direction. Leave it as-is and it freezes completely.
Without drawing more frames, we raise and lower the sprite 1 pixel. 1 pixel in 1.8 seconds.

**Watch-outs** — Also show it stretched to 4px.
1px on a 16px character is 1/16 of its height, about 10cm on a person.

### 5-2. Shadow

**On screen** — Shadow `light_mask` at 1, fading when a beacon lights → to 0

**Narration** — If light hits the shadow, the shadow fades beside a beacon.
Closer to the fire, the shadow disappears — the opposite of reality.
Same judgment as what we gave the flames in Lesson 2.
Do not shine light on something that already glows, or something that blocks light.

### 5-3. Night tint

**On screen** — A noon ninja in a night forest → after applying modulate

**Narration** — The player is a sibling of the forest, so night tint does not descend.
Same treatment as Lesson 2's pit and Lesson 3's clearing.
There is one difference. Leave the sprite's light_mask at the default.
It has to receive beacon light. In a night forest, being bright beside the fire is this whole game, and
if the player does not receive that light there is no reason to light a beacon.

**Watch-outs** — Mark the **difference**: the pit does not receive light and the player does.

### 5-4. Decide facing now

**On screen** — Write `face_toward()`. Change Facing in the inspector and confirm 4 directions

**Narration** — We make this in advance so Lesson 6 only has to call this function when the stick attaches.
Diagonals follow whichever of x and y is larger. We only have 4-direction sprites, so we have to pick one.
Not changing facing when length is near 0 is also important.
The instant you release the stick the value drops to 0, and if you change facing then
the character looks down every time you let go.

**Watch-outs** — Say honestly that this treatment does not show yet.
Preview that in Lesson 6 we will drop that guard and actually show it looking down.

### 5-5. Place it in the arena

**On screen** — Attach as an instance at (330, 300)

**Narration** — Near the west beacon. The instant a beacon lights, firelight lingering is visible.

## 6. Confirm (11:00 ~ 11:40)

**On screen** — `pnpm game:check` · ninja before and after a beacon lights

## 7. Get it wrong on purpose (11:40 ~ 13:20)

**On screen** — Four things

**Narration** — First, revert Modulate to white and a noon ninja stands in a night forest.
Second, set the shadow light_mask to 1 and the shadow fades beside a beacon.
Third, stretch 1px to 4px and it bounces.
Fourth, deleting the facing guard does not show yet. We see it in Lesson 6.

## 8~9. Completion criteria and homework (13:20 ~ 14:00)

**Narration** — Try homework 1. Change walk_down to autoplay and it walks in place.
That is a preview of when this animation will appear in Lesson 6.
