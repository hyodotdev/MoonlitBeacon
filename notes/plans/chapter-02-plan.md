# Lesson 2 — Plan

## Official tutorial mapping

`Step by step / Nodes and scenes` · early `Creating instances`

## Goal

The Lesson 1 result `title_menu.tscn` is a single 11,228-line file.
The screen is finished, but **there is not one reusable part.**

Lesson 2 splits that lump into three files.

| File | What |
| --- | --- |
| `scenes/objectives/beacon.tscn` | One beacon (8 nodes — including the flicker player) |
| `scenes/gameplay/night_forest.tscn` | Night forest (1,296 nodes) |
| `scenes/gameplay/arena.tscn` | Stage that holds both as instances (11 lines) |

Then rewrite `title_menu.tscn` to use the same two scenes so **the forest is not duplicated**.
Skip that and the teaching repository becomes a bad example of itself.

What you see is almost the same as Lesson 1. This lesson **changes structure, not appearance**.
A new screen `arena.tscn` does appear, and Lesson 3 continues from there.

## Work order is lesson order

In the Lesson 1 scene **the beacon is not one lump.**

```text
Forest (night tint via CanvasModulate)
  Beacon
    Pit / Light          ← fire pit and light only
Fire (CanvasLayer)
  Flames
    Smoke / Embers / Flame / Glow   ← flame, sparks, smoke live here
```

`CanvasModulate` tints the whole canvas, so putting the flames in the forest turns them blue.
Lesson 1 avoided that by parking the flames on a separate `CanvasLayer`.

So **`Save Branch as Scene` on `Beacon` saves only half of it.**
You get a pile of stones with no fire. The lesson text must follow this order as-is.

| Step | What to do | Why this order |
| --- | --- | --- |
| 1 | Delete `NightTint` → put the night tint on `Forest.modulate` | Skip this and the next step leaves the flames blue |
| 2 | Move the four nodes under `Fire/Flames` under `Forest/Beacon` | Gather the beacon into one place |
| 3 | Move `Beacon` out of `Forest` (make it a sibling) | Flames turn orange again — the moment you see that `modulate` only descends to children |
| 4 | `Pit.modulate` = `(0.258, 0.28, 0.45)` | Compensate for the pit looking as bright as noon |
| 5 | Delete the empty `Fire` `CanvasLayer` | |
| 6 | `Beacon` → `beacon.tscn` | Only now is it one lump you can save |
| 7 | Move flicker into `beacon.tscn` and raise `energy` 3.2× | See item 4 below |
| 7b | Set `light_mask = 0` on the four flame nodes | 3.2× light washes out its own flames. See item 5 below |
| 8 | `Forest` → `night_forest.tscn` | |
| 9 | Create `arena.tscn` · reassemble `title_menu.tscn` | |

Moving nodes in step 2 **makes coordinates jump.** Inside a `CanvasLayer` they were screen coordinates.
Godot does not correct this, so the lesson text gets a warning.

## Changes

### 1. Extract `beacon.tscn`

| Node | Type |
| --- | --- |
| `Beacon` | `Node2D` |
| `Pit` | `Sprite2D` |
| `Light` | `PointLight2D` |
| `Smoke` | `GPUParticles2D` |
| `Embers` | `GPUParticles2D` |
| `Flame` | `GPUParticles2D` |
| `Glow` | `Sprite2D` |

Keep the root as `Node2D`. If the pit `Sprite2D` is the root, touching the pit drags flame and light with it.

When extracting, **follow nested resources recursively.** One particle references a
`ParticleProcessMaterial`, which in turn references a `Curve` and a `GradientTexture1D`.
Picking by eye misses nested things like `Curve_flame` and `GradientTexture1D_smoke`.
The finished `beacon.tscn` is 227 lines (after the flicker animation is in).

### 2. Extract `night_forest.tscn`

The 1,280 trees and grass baked by `build_title_forest.py` in Lesson 1 come along as-is.
12 top-level children (`Ground` `Clearing` `Scorch` `Details` `Trees` `CanopyShade`
`Motes` `Beams` `MistFar` `MistNear` `Mist` `Vignette`), 1,296 nodes total, 10,819 lines.

**Do not bring `CanvasModulate`.** Instead put this on the root `Node2D`:

```ini
modulate = Color(0.315, 0.35, 0.57, 1)
```

Reason in item 3 below.

### 3. Why the night tint moved from `CanvasModulate` to `modulate`

`CanvasModulate` tints **the whole canvas layer**. Put the beacon on the same canvas and
the flames go blue too. Lesson 1 avoided that by parking the beacon on a separate `CanvasLayer`.

That workaround dies in Lesson 3. `CanvasLayer` children **do not inherit world transforms.**
Giving the beacon a `position` does not move it in arena space.
Lesson 3 places three beacons in different spots, so this must be fixed now.

`modulate` only descends to self and children. In `arena.tscn`, make `Beacon` a
**sibling** of `NightForest` and only the forest tints; the beacon stays itself.
The beacon remains an ordinary `Node2D`, so `position` works.

Side work: the pit used to pass through `CanvasModulate` and now sits outside it, so
write the multiplied result directly on `Pit`.

| | R | G | B |
| --- | --- | --- | --- |
| Original | 0.82 | 0.80 | 0.79 |
| × night tint | × 0.315 | × 0.35 | × 0.57 |
| Result | 0.258 | 0.28 | 0.45 |

### 4. Raise light energy 3.2× and move flicker into the beacon

Change structure alone and **the clearing's warm light dies.** Not because the color is wrong,
but because the two compositing orders differ.

| | Order |
| --- | --- |
| `CanvasModulate` | original color → light → multiply night tint on the result |
| `modulate` | **albedo already darkened by night tint** → light on top |

Measured (title screen frame at 1.4s, region-average RGB):

| Spot | Lesson 1 | Structure only | After 3.2× |
| --- | --- | --- | --- |
| Forest outside the light | (16.1, 21.6, 24.8) | (16.1, 21.6, 24.7) | (16.1, 21.6, 24.7) |
| Clearing left | (134.1, 79.2, 65.4) | (83.9, 60.1, 61.6) | (134.8, 84.4, 73.1) |
| Clearing right | (118.9, 74.0, 63.2) | (77.3, 57.5, 60.2) | (119.4, 77.5, 69.6) |

PSNR went 28.2 dB → 35.7 dB. We ran 1.5 · 1.9 · 2.3 · 2.7 to get the slope and settled on 3.2.
The B channel stays a little high; you cannot see it by eye.

**Tried and discarded:** leave `CanvasModulate` and cancel it on the beacon root with the
inverse night tint `(3.175, 2.857, 1.754)` as `modulate`.
The forest is preserved pixel-for-pixel, but **the flames burn white** — pixels already near white
clamp in the multiply, then the canvas tint is multiplied on top. Confirmed by rendering.

Where you put the raised energy is the next problem. `BeaconFx` overwrites `Light:energy` with
absolute keyframes, so `energy` on `beacon.tscn` is a dead setting on the title screen.
Fixing both the keyframes and the scene means two places to touch — exactly what this lesson
teaches you not to do.

So **move flicker into a `Flicker` AnimationPlayer inside `beacon.tscn`.**
Autoplay, paths shorten one step to `Light:energy` · `Glow:scale`.
The title keeps only the tap flourish `flare`, and `BeaconFx` autoplay is turned off.
`flare` energy is the same 3.2×.

Side effect: delete `_beacon_player.queue(&"flicker")` from `title_menu.gd`.
That animation no longer exists on `BeaconFx`; leave it and you get a runtime error.
For the overlapping 0.85s, `BeaconFx` (later in the tree) wins; when it ends the beacon takes over.

Bonus: **the arena beacon flickers too.** It used to be a static `energy = 1.02`.

### 5. Keep the flames out of the beacon's own light

After raising `energy` 3.2×, **flame color blew out.** Deep orange, red wick, and smoke vanished
into a pale yellow blob.

In Lesson 1 the flames sat on a separate `CanvasLayer`, so **2D lights never reached them.**
This came along when we merged onto one canvas.

Set `light_mask = 0` on `Smoke` · `Embers` · `Flame` · `Glow`.
No bits on means no light hits them.
Leave `Pit` as-is — the pit received light in Lesson 1 too.

**Do not invent a new idiom.** `night_forest.tscn` already uses `light_mask = 0` on eight nodes:
`MistFar` `MistNear` `Beams/*` `Motes` `CanopyShade` `Vignette`.
We first used `light_mask = 2` (a bit that does not overlap the light cull mask),
then matched `0` so the same meaning is not written two ways in the repo.
Render comparison: the two screens match (PSNR 39.4 vs 39.5 dB, flicker timing offset).

Measured (beacon cropped 120×120, title at 1.4s):

| | Mean RGB | White-saturated pixels |
| --- | --- | --- |
| Lesson 1 | (211.0, 120.8, 76.7) | 0 |
| Before mask | (216.1, 154.8, 103.5) | 21 |
| After mask | (213.2, 129.7, 91.1) | 0 |

Overall PSNR 28.2 → 35.7 (energy fix) → **39.4 dB** (mask too).

### 6. Create `arena.tscn`

```ini
[node name="Arena" type="Node2D"]

[node name="NightForest" parent="." instance=ExtResource("forest")]

[node name="Beacon" parent="." instance=ExtResource("beacon")]
position = Vector2(404, 250)
```

`(404, 250)` — horizontal center of 808 × 360, vertical at the clearing.

### 7. Rebuild `title_menu.tscn` on the new parts

11,228 lines → 201 lines. What remains is three UI nodes (`Title` `Prompt` `Version`),
the `AnimationPlayer`s, and two scene instances.

**Fix animation track paths in the same pass.** They differ by where things moved.

| Animation | Where | Path |
| --- | --- | --- |
| `flicker` | `Flicker` in `beacon.tscn` | `Light:energy` · `Glow:scale` |
| `flare` | title `BeaconFx` | `Beacon/Light:energy` · `Beacon/Glow:scale` |

A wrong path **does not error.** The game runs and only the flame stops swaying.
So the lesson text also gets a warning to check by eye.

`@onready` paths in `title_menu.gd` change with them.

```gdscript
@onready var _forest: Node2D = $NightForest
@onready var _vignette: Sprite2D = $NightForest/Vignette
@onready var _beacon: Node2D = $Beacon
```

## Recording

| Clip | Content | Length |
| --- | --- | --- |
| `chapter-02-arena.mp4` | `arena.tscn` running | 9s |
| `chapter-02-compose.mp4` | forest only → beacon only → combined | 13s |

Both are rendered with Godot Movie Maker (`--write-movie`). This is not a screen capture —
the engine writes frames itself, so there is no frame drop and no cursor.

The `compose` clip briefly creates two temp scenes (`_tmp_forest_only.tscn` `_tmp_beacon_only.tscn`)
under `res://` to render, then **must delete them.** The `_tmp_` prefix is there so a leftover
is obvious if you forget.

The beacon-only stretch shows Godot's default clear color (gray) as-is.
That looks like a forgotten background, so lay a night-color (`#0b0e1c`) `ColorRect` behind it.

Burn captions in with ffmpeg `drawtext`. Do not use TTS.
The clip only needs to show what is happening; the lesson text does the explaining.

## Completion criteria

- [ ] Running `beacon.tscn` alone shows a burning beacon
- [ ] Running `night_forest.tscn` alone shows a night forest with no beacon
- [ ] `arena.tscn` is 11 lines · 3 nodes
- [ ] Running `arena.tscn` shows a blue forest and an orange beacon
- [ ] `title_menu.tscn` is 201 lines
- [ ] Forest outside the light matches Lesson 1 pixel-for-pixel; clearing restored by measurement
- [ ] Flame close-up comparison has 0 white-saturated pixels
- [ ] The arena beacon flickers too
- [ ] Beacon sway animation on the title screen is correct
- [ ] `pnpm game:check` exits 0
- [ ] Rebuild APK; no script errors on device
- [ ] Two silent clips · each under 1MB
- [ ] Lesson-text section numbers 1:1 with the recording script

## Pitfalls that must stay in the lesson text

| Pitfall | Why |
| --- | --- |
| Saving `Beacon` immediately saves only half | You will hit this if you do not know it is split |
| Coordinates jump when moving `CanvasLayer` → `Node2D` | The engine does not correct them |
| A wrong animation track path **does not error** | Only the flame quietly stops swaying |
| Properties an animation touches ignore the scene value | Setting them in the inspector does nothing. Give the homework as `color`, leave `energy` as the trap |
| **Change structure and you must recapture the light** | Unlit areas match on their own, so looking only at the forest makes it easy to say "done" |
| Lighting something that already glows washes the color out | It does not get brighter; it blows out. Exclude it with `light_mask` |

## Deferred to Lesson 3

- Placing three beacons and each one's lit state
- Title → arena scene change
- Putting a camera in `arena.tscn`

## Not this lesson

- Scripts on the beacon — Lesson 4
- Player — Lesson 5
- Beacon ignition interaction — Lesson 7
