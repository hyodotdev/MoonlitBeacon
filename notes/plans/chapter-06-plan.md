# Lesson 6 — Plan

## Official tutorial mapping

`Step by step / Listening to player input` · `Coding the player`

## Goal

Walk the ninja with a left floating virtual stick. On a phone it is actually driven by a thumb.

## Changes

### 1. Stick art (two derived)

`stick_base.png` 48×48 ring, `stick_knob.png` 22×22 circle.
**Draw in white only and give color with `modulate` in the scene.** Lesson 12's dash stick
should be able to reuse the same art with a different color.

### 2. `scenes/ui/virtual_stick.tscn` · `scripts/ui/virtual_stick.gd`

A `Control` covering the **left half** of the screen (`anchors_preset = 9`, `offset_right = 404`).
`expand` means width differs per device, so pin with anchors.

Three key points:

| Trap | Response |
| --- | --- |
| There are several fingers | `_touch_index` watches **only its own finger** |
| Leaving the pad cuts off events | Receive once more in `_input()`. Convert coords with `make_input_local()` |
| Resting a finger is not a zero value | `dead_zone = 0.16` |

The second is the nastiest. Use only `_gui_input` and when the thumb slides right
**the stick freezes on and the character keeps walking.**

### 3. `player.gd` movement

```gdscript
velocity = velocity.move_toward(_wish * speed, rate * delta)
move_and_slide()
```

`speed = 96` (about 8 seconds to cross the screen), `ACCELERATION 900` / `FRICTION 1200`.
**Stop faster than you start** — starting is soft, stopping is crisp.

`face_toward(_wish)` and `set_walking(velocity.length() > WALK_THRESHOLD)`.
**Look at `velocity`.** Look at `_wish` and after you release, the character slides
without moving its feet.

### 4. Bounds

Clamp coordinates with `BOUNDS = Rect2(96, 150, 616, 172)`.

A collider on every tree would be the "proper" way, but **the forest has 1,296 nodes.**
That becomes a different job unrelated to what this lesson teaches. Write that honestly in the text.
When the moonlight gate opens in Lesson 9 this rectangle is not enough — preview that too.

### 5. The arena reads the stick and forwards it

**The player does not read the stick itself.** Lesson 8's enemies have no stick,
and the point is not to touch the input side when dash is added in Lesson 12.

## Device verification

`adb shell input swipe` in four directions, tracking ninja position every frame.
**Total travel 1050px** (72 frames, 0 detection failures). The stick ring is visible on screen too.

## Completion criteria

- [ ] Press anywhere on the left half and the stick appears there
- [ ] Walks in the pushed direction and that direction's animation plays
- [ ] Release and it stops smoothly
- [ ] Resting a finger does not move it
- [ ] The stick keeps following even if the finger leaves the pad
- [ ] Does not leave the forest
- [ ] `pnpm game:check` 0 · manifest 0 · media 0
- [ ] Operated by thumb on device

## Deferred to Lesson 7

- Standing beside a beacon fills a light ring and lights it (signals)
- Ignition SFX

## Not this lesson

- Right dash stick — Lesson 12
- Tree colliders — not doing this. Lesson 9 recaptures bounds
