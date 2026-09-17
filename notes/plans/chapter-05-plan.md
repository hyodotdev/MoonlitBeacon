# Lesson 5 — Plan

## Official tutorial mapping

`Step by step / Creating the player scene` · `2D sprite animation`

## Goal

Make the player (ninja) as its own scene and stand it in the arena. **It does not move** —
that is Lesson 6. Instead, standing is done properly: shadow, breathing idle,
night tint, receiving beacon light.

**Build facing logic now.** When Lesson 6 attaches the stick, it only has to call `face_toward()`.

## Changes

### 1. Two assets + one derived

| File | Source | Size | Layout |
| --- | --- | --- | --- |
| `ninja_walk.png` | `Actor/Character/NinjaBlue/SeparateAnim/Walk.png` | 64×64 | **columns=direction, rows=frame** |
| `ninja_idle.png` | same folder `Idle.png` | 64×16 | columns=direction |
| `derived/player/shadow.png` | made here | 24×10 | soft ellipse |

Column order `down · up · left · right` was confirmed by eye at 6× zoom.
**Do not trust a layout written in a document** — packs differ.

Assets 67 → 70.

### 2. `player.tscn`

```text
Player   (CharacterBody2D)  modulate = night tint
  Shadow (Sprite2D)         light_mask = 0
  Sprite (AnimatedSprite2D) 8 SpriteFrames
  Body   (CollisionShape2D) radius 4
  Breathe(AnimationPlayer)  autoplay
```

Counting 20 `AtlasTexture`s by hand will be wrong. **Build them from the layout with a machine.**

Root is `CharacterBody2D`. Lesson 6 uses `move_and_slide()`.
Change the root type later and every child and script shakes.

### 3. Three light treatments

| Node | `modulate` | `light_mask` | Why |
| --- | --- | --- | --- |
| `Player` (root) | night tint | — | Sibling of the forest, so tint does not descend |
| `Sprite` | (inherited) | **1** (default) | Must receive beacon light |
| `Shadow` | darker | **0** | The shadow must not brighten |

The sprite receiving light is the difference from Lesson 2's pit.
**In a night forest, being bright beside the fire is this whole game**, so the player must receive that light.

### 4. Idle is only one frame

`Idle.png` is 1 frame per direction. An `AnimationPlayer` raises and lowers `Sprite:offset`
by 1px on a 1.8s cycle. Solved without drawing more frames.

**1px is the answer.** 1px on a 16px character is 1/16 of its height, about 10cm on a person.
2px bounces.

### 5. `player.gd`

- Keep `enum Facing` order **the same as the sprite-sheet column order** — used as-is when building names
- `face_toward(dir)` — split diagonals with `absf(x) > absf(y)`
- **Do not change facing when length is near 0.** Otherwise Lesson 6 looks down every time you release the stick. It does not show yet, but put it in now
- `set_walking(bool)` — Lesson 6 calls this every frame
- The setter runs before `@onready`, so re-hook in `_ready()` (same trap as Lesson 4)

## Completion criteria

- [ ] `player.tscn` is its own file, 8 animations
- [ ] A ninja stands in the arena with a shadow at its feet
- [ ] Beacon unlit → ninja dark / beacon lit → ninja brightens
- [ ] The shadow does not brighten
- [ ] Rise and fall like breathing
- [ ] `pnpm game:check` 0 · manifest 0 · media 0
- [ ] Device check, no logcat errors
- [ ] Silent clips · each under 1MB

## Deferred to Lesson 6

- Left floating joystick
- `move_and_slide()` and `walk_*` animation switching
- Keep the player from leaving the arena bounds (trees)

## Not this lesson

- Dash — Lesson 12
- Lighting beacons — Lesson 7
- Camera — everything still fits on one screen
