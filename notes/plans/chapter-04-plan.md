# Lesson 4 — Plan

## Official tutorial mapping

`Step by step / Creating your first script` · `Exporting variables` · `Setters and getters`

## Goal

Write the first script. Beacons **start unlit**, light one by one, and each lighting
brightens the forest moonlight one step.

And **pay the debt from Lesson 3** — turn off `Editable Children` and replace it with `@export`.
The Lesson 3 text already previewed "we revert this in Lesson 4."

## Changes

### 1. `scripts/objectives/beacon.gd`

| Exported value | What it does |
| --- | --- |
| `lit: bool` | On/off. The setter changes the screen immediately |
| `ignite()` | Swells light from 0 to 1.7× then settles to the baseline (0.45s) |
| `flicker_speed: float` | Flicker speed. Replaces Lesson 3's `Editable Children` |

| | Unlit | Lit |
| --- | --- | --- |
| `Pit` | `(0.17, 0.19, 0.33)` | `(0.258, 0.28, 0.45)` |
| `Light` · `Glow` | `visible = false` | `true` |
| Three particles | `emitting = false` | `true` |
| `Flicker` | `stop()` | `play("flicker")` |

Attach `@tool`. There are three beacons, so it is better to see which is lit in the editor.
Block signals with `Engine.is_editor_hint()` so the arena does not react while you edit.

**`set` runs before `@onready`.** If the inspector has `lit = false`,
the setter runs while `_pit` is still `null`. You need both of these.

1. `if _pit == null: return` inside the setter
2. In `_ready()`, **run every setter again** (`_set_lit` · `_set_flicker_speed`)

Skip the second and **there is no error, but a beacon you turned off starts lit.**
Skip `_set_flicker_speed` and **the inspector flicker speed never applies.**
Every extra `@export` also grows `_ready()`.

Delete the guard and **the game still does not die.** GDScript prints the error and continues.
The actual text is this (quote it as-is in the lesson):

```text
SCRIPT ERROR: Invalid assignment of property or key 'modulate' with value of type
'Color' on a base object of type 'Nil'.
```

### 2. `scripts/gameplay/arena.gd`

Listen to `lit_changed` and raise forest `modulate` by the lit count.

```gdscript
var target: Color = NIGHT_TINT * pow(LIT_BRIGHTEN, _lit_count)
```

`LIT_BRIGHTEN = 1.14`. Three beacons → 1.14³ ≈ 1.48×.
**Kill the previous tween before making a new one.** At the current spacing they do not overlap
— it finishes brightening in 1.1s and the next lights 2.6s later. This is prep for Lesson 7,
when the player can light them in a row. **Write that honestly in the lesson text.**

The overlap symptom is not "color jumps" but **the forest never reaches full brightness**.
Shrink the gap to 0.6 and drop `kill()`, and measured final brightness is 42.9 → 39.8.

Ignition order is the arena's job (`_run_ignition_sequence()`).
When the player lights them in Lesson 7, you only delete this function — brightness only
listens to the signal, so it does not care who lit it.

`is_inside_tree()` guard after `await`. You can leave the scene during three 2.6s waits.
Same reason as Lesson 1's title screen.

### 3. `arena.tscn`

Delete the three `[editable path=...]` lines. Instead give each instance `lit = false` and
`flicker_speed`.

## Measurement

Mean red channel of a 48×48 at each beacon (Movie Maker render, 4fps sample):

| Time | West | North | East | Forest (outside light) |
| --- | --- | --- | --- | --- |
| 0.0s | 29 | 35 | 29 | 14.9 |
| 2.0s | 224 | 35 | 29 | 16.5 |
| 4.0s | 225 | 35 | 235 | 17.8 |
| 7.0s | 225 | 222 | 235 | 22.6 |
| 10.0s | 225 | 225 | 235 | 25.0 |

On device (1212×540, 2fps) the order is the same: west at 4s → east at 8s → north at 10s.

## Recording

| Clip | Content | Length |
| --- | --- | --- |
| `chapter-04-device.mp4` | Device — tap → arena → sequential ignition | 12s |
| `chapter-04-ignite.mp4` | Ignition sequence (Movie Maker) | 11s |

## Completion criteria

- [ ] Three beacons start unlit
- [ ] An unlit beacon is a cold pile of stones (no flame · smoke · light)
- [ ] They light in sequence, and the forest brightens one step each time
- [ ] The three beacons **flicker on different beats** (Lesson 3 work was not lost)
- [ ] Fire does not snap on; it swells once then settles
- [ ] `arena.tscn` has no `[editable` — **Lesson 3's debt is paid**
- [ ] `@tool` shows `lit` immediately in the editor
- [ ] Title screen matches Lesson 3 as-is (PSNR compare)
- [ ] `pnpm game:check` 0 · arena leaks 0
- [ ] Device check, no logcat errors
- [ ] Silent clips · each under 1MB
- [ ] Lesson-text section numbers 1:1 with the recording script

## Pitfalls that must stay in the lesson text

| Pitfall | Why |
| --- | --- |
| `set` runs before `@onready` | Starts silently wrong, with no error |
| You must hook it again in `_ready()` | Pair of the above |
| `@tool` can kill the editor too | Block signals with `is_editor_hint()` |
| Overlapping tweens pull on each other | They do not overlap now. Write honestly that this is prep for Lesson 7 |
| `_ready()` must **re-hook every** setter | Skip one and only that value silently does nothing |
| After `await` the scene may already be gone | Shows up again after Lesson 1 |

## Deferred to Lesson 5

- Player (ninja) scene and 4-direction animation
- A path from arena back to title

## Not this lesson

- The player lighting beacons — Lesson 7 (signals)
- Beacon ignition SFX — together in Lesson 7
