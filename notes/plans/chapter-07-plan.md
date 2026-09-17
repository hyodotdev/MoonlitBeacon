# Lesson 7 — Plan

## Official tutorial mapping

`Step by step / Using signals`

## Goal

**The player lights the beacons.** Stand beside one and a ring at the feet fills; when full it lights.
Leave and it drains.

And harvest the seed planted in Lesson 4 — the actor that lights moved from arena to player,
but **the forest-brightening code is not changed by a single character.** That is this lesson's proof.

## Changes

### 1. `Area2D` on the beacon

`collision_mask = 2` (player layer). Lesson 8's enemies sit on another layer so
**enemies lighting beacons is blocked with no code.**

:::danger `scale` shrinks the detect range too
Lesson 3 set `scale` to 0.78 / 0.62 / 0.86 for depth.
`Area2D` takes that as-is, so **the north beacon's radius becomes 34 × 0.62 = 21**.
It was shrunk to look far away, not to be harder to approach.

`_normalize_reach()` divides by `scale`. **You must `duplicate()`** —
the three instances share the same `CircleShape2D` resource, so skip it and the last
calculation overwrites all three.
:::

### 2. Charge

`CHARGE_SECONDS = 1.3`, `DECAY_MULTIPLIER = 1.8` (drain is faster).
When nobody is there and it is empty, `set_process(false)`.

`_visitors` is a **count**. A boolean misses the wobble at the edge.

### 3. Ring — no shader

Stack two copies of the same ring and grow only the top sheet's `region_rect`.
**You must set `offset` with it** so it fills from the bottom. Skip that and it grows from the top.

Filling by angle with a shader looks nicer, but this lesson's subject is signals.
Do not split what you are teaching in two. Write that honestly in the text.

The ring attaches **at the player's feet**. Put one on each beacon and you see two between two beacons.
The arena relays `max(charge)`.

### 4. SFX

`Elemental/Fire2.wav` (1.25s) → `beacon_ignite.ogg` 20KB.
`Fire3` (0.65s) is shorter than the light-up (0.45s), so it ends before the fire settles.

It is an `AudioStreamPlayer2D`, so the west beacon's sound comes from the left.

:::warning Inheritance is split
`music_player.gd` inherits `AudioStreamPlayer`, so it cannot attach to 2D.

```text
Script inherits from native type 'AudioStreamPlayer',
so it can't be assigned to an object of type 'AudioStreamPlayer2D'.
```

Pull only the wait part into `AudioFlush` and both sides use it.
**If you never lit one, there is no leak** — that makes it easy to miss.
:::

### 5. Do not change Lesson 4's code

**Only delete** `_run_ignition_sequence()`.
`_on_beacon_lit_changed()` stays. That is this lesson's conclusion.

## Verification

Headless probe:

| | |
| --- | --- |
| Ignition time | 1.33s (design 1.3s) |
| All three beacons | `lit=true` |
| On leave | 0.18 → 0.00 |
| Forest `modulate` | (0.315, 0.35, 0.57) → (0.467, 0.519, 0.845) |
| Leaks on exit | 0 |

Device: walk over and light the west beacon in 3.2s. Capture the ring filling.

## Completion criteria

- [ ] Stand beside it, the ring fills, and when full it lights
- [ ] Leave and it drains
- [ ] All three beacons react at the same distance (even with different `scale`)
- [ ] Sound plays at the light-up instant and the direction is correct
- [ ] 0 leaks on exit
- [ ] **Did not change brightness code in `arena.gd`**
- [ ] `pnpm game:check` 0 · manifest 0 · media 0

## Deferred to Lesson 8

- Enemy (spirit) scene and chase
- Enemies on another layer — they cannot light beacons

## Not this lesson

- Shader — do not split what you are teaching in two
- Win/lose — Lesson 9
