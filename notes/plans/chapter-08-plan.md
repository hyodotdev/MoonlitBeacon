# Lesson 8 — Plan

## Official tutorial mapping

`Step by step / Creating the enemy` · `Physics layers`

## Goal

Add a spirit. It chases the ninja, and on contact the screen flashes red.
**Make "spirits cannot light beacons" with layers, no code.**

## Changes

### 1. Assets

`Actor/Monster/Spirit/SpriteSheet.png` → `spirit.png` (64×64, columns=direction rows=frame).

`Spirit2` is an orange flame, so **it is confused with the beacon.** In a night forest, orange is the beacon's color.
`Spirit` is a pale blue, so it matches the night tint and stays distinct.

### 2. `spirit.tscn` — same structure as the player

| | Player | Spirit |
| --- | --- | --- |
| Speed | 96 | **62** |
| Facing | stick | toward the player |
| Idle | 1px breathe | 3px hover |
| Layer | 2 | **4** |

If the spirit is faster there is no way to run, so there is no game. When Lesson 13 adds faster
enemies, this balance is the baseline.

The only thing the player does not have is `Hitbox` (Area2D, `mask = 2`).

### 3. Layers become the rule — the core of this lesson

Lesson 7 made beacon `Reach` look only at layer 2. Put the spirit on 4 and **with zero lines of code**
the spirit cannot light a beacon.

Filter by name (`if body.name != "Player"`) and the condition grows every time enemies grow.
Even when Lesson 13 has three kinds, the layer setting stays.

### 4. Chase

`velocity.lerp(wish * speed, TURN_RATE * delta)`.
Snap it in and **you can dodge on a zero-radius turn.** `lerp` makes a wide turn so you can
cut and shake it. `TURN_RATE` is the difficulty knob.

**Who to chase is the arena's decision** (`set_target`). The spirit does not search the scene.
Same judgment as Lesson 7 keeping the player unaware of beacons.

### 5. Hit

`HIT_COOLDOWN = 1.1`. `body_entered` is a moment, but wobble at the edge repeats enter/exit.
When Lesson 9 adds health, one overlap would wipe it all.

Red `ColorRect` alpha 1 → 0. **Kill the tween first** (same trap as Lesson 4).
`mouse_filter = 2` is required — skip it and the whole screen eats touches, so the stick dies.

## Verification (headless probe)

| | |
| --- | --- |
| Spirit–player distance | 328 → 0 |
| Flash max alpha | 1.00 |
| Beacons the spirit lit | 0 (all three `false`) |
| Leaks on exit | 0 |

Device: red aura idle −5.2 → max 48.1, two flashes confirmed.

## Completion criteria

- [ ] The spirit chases and is slower than the ninja
- [ ] Contact flashes red
- [ ] Even overlapping, only once per 1.1s
- [ ] **The spirit cannot light beacons (layers, not code)**
- [ ] Stick and ignition still work with a spirit present
- [ ] `pnpm game:check` 0 · manifest 0 · media 0

## Deferred to Lesson 9

- Health and game over
- Moonlight gate when all three beacons are lit
- Spirit spawn (currently one fixed)

## Not this lesson

- Health UI — Lesson 10
- Multiple enemy kinds — Lesson 13
