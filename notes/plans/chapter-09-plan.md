# Lesson 9 — Plan

## Official tutorial mapping

Official intro course `Step by step / The main game scene` · `Game over`.

The official example makes a separate `Main` scene. **For us the arena is that place.**
There is not enough to manage to justify another scene.

## Goal

Give something that had no end **a run**. Light all three beacons and a moonlight gate opens;
enter it and you win. Get hit three times and you lose. Either way, tap to start again.

## Changes

### 1. `_over` — the core of this lesson

Win or lose, gather it in one `_finish(won)`. Put shutdown in two places and you skip one.

Without `_over` **the game keeps running behind the panel.** The spirit keeps chasing,
health goes negative, and the panel stacks several times.

### 2. Moonlight gate

Leave `visible = false` until all are lit, then appear over 1.2s.
**Do not show a closed gate in gray** — players wander toward it from the start.

`monitoring = false` while it opens. If the last beacon is near the gate you
**graze it mid-appear and win.** You did win, but it feels empty.

### 3. Lesson 6's bounds trip us — as previewed

The Lesson 6 text already said "in Lesson 9 this rectangle will not be enough."
It happened. The gate is at `y = 336`, the player at `y ≤ 322`. **You cannot reach it.**

`const DEFAULT_BOUNDS` → `var bounds` + `set_bounds()`, open only the path in front of the
gate with `Rect2.merge()`. **Two lines to change.**

If we had built "perfect" bounds with a collider on every tree, we would have to retouch
everything today. Keeping it simple, knowing it would change, pays off.

### 4. The gap in `body_entered`

:::danger Stood still 24 seconds on device and got hit only once
`body_entered` fires **only at the moment of entry**. If the spirit keeps overlapping while
pushing, the second signal never comes. Health is 3 and you never die.

Check every frame in `_physics_process` with `has_overlapping_bodies()`.
After the fix: hit three times at 3.8s · 4.8s · 6.0s and it ended.
:::

**A signal is a "change", not a "state".** Same as Lesson 7's beacon counting `_visitors`.

### 5. Result panel

Win or lose, **the same panel.** Only the text and color change.

If a finger is already down when it appears, it restarts immediately. At the moment of loss
the hand is still on the stick. **Wait 0.6s before accepting input.**

### 6. Restart is one line: `reload_current_scene()`

Do not write code that reverts state one field at a time. Every new value is another place
to miss. **Anything that must survive across scenes is handled separately in Lesson 14.**

### 7. Put `is_instance_valid()` in early

Right now there is one spirit and it is not freed. **Lesson 13 creates and destroys them.**
An `@onready` reference remains after the node is freed, and calling it dies with
`in base 'previously freed'`.

## Verification

| | |
| --- | --- |
| Gate | `visible = false` before 3 beacons |
| While opening | `monitoring = false` |
| Bounds | After `merge()` you can reach the gate |
| Device hits | 1 in 24s → 3 at 3.8 · 4.8 · 6.0s |
| Behind the panel | Spirit stopped, no health loss |

## Completion criteria

- [ ] The gate appears only after all three beacons are lit
- [ ] Enter to win, three hits to lose
- [ ] **Standing still actually loses**
- [ ] The game does not run behind the panel
- [ ] `pnpm game:check` 0

## Deferred to Lesson 10

- Show health · time · beacon count on screen (they only live in code now)

## Not this lesson

- Score — Lesson 14
- A separate `Main` scene — the arena is that place
