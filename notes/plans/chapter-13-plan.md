# Lesson 13 — Plan

## Official tutorial mapping

Outside the official intro course. See `Resources` · `class_name` · `SpriteFrames`.

## Goal

Grow enemies to four kinds but **keep one scene.** When the last beacon lights, a Guardian
appears and the music changes.

## Changes

### 1. `SpiritKind` custom resource — the core of this lesson

Copy the scene three times and fixing one hit cooldown means fixing three places.
That is what we have been avoiding since Lesson 2.

One `.tres` is one enemy kind. **A new enemy needs neither code nor a scene.**

| | Speed | Turn rate | Color |
| --- | --- | --- | --- |
| Wandering spirit | 62 | 5.0 | blue |
| Night bat | 70 | 2.2 | deep blue |
| Ember spirit | 84 | 8.5 | red |
| Forest Guardian | 52 | 3.2 | purple |

### 2. Slice the sheet in code

Export `cell` · `rows` · `columns` all as settings.
**Only the Guardian's layout is different** — 50px cells, one row, no facing.
Hard-code even one of those and you cannot add the Guardian.

Clamp with `mini(index, kind.columns - 1)`. One column always uses `float_down`.
Forget `remove_animation(&"default")` and an empty animation remains.

### 3. Spawn

From the farthest spot, appear over 0.9s with `materialize()`.
**`monitoring = false` while appearing** — getting hit before you have a body is unfair
(same judgment as Lesson 9's moonlight gate).

Kind is chosen by **lit beacon count**. It is progress, not time, so it gets hard faster
for people who are good. `MAX_SPIRITS = 3`.

### 4. Guardian — the small fry fall back

:::danger At first you died the instant the last beacon lit
We just added the Guardian and **Guardian + three spirits** charged at once.
With 3 health it was not hard, it was **impossible**. Confirmed by rendering.

`retreat()` the small fry and `_spawn_timer = INF`.
Clear the stage so the last stretch is one-on-one. It also matches the story.
:::

One more: **the Guardian appeared right in the player's face.** If the last beacon is north,
it overlapped the Guardian spawn. Use `_farthest_spawn()` together.

### 5. Music

`17 - Fight`. Lesson 3 picked the arena track as "the smallest swing";
here we pick by the **opposite criterion**. Measure with the same ruler and take the other end.

### 6. Handling several

`_prune_spirits()` strips dead ones before use.
Putting `is_instance_valid()` in early in Lesson 9 pays off.

## Verification

| | |
| --- | --- |
| Spawn | up to 3, farthest spot (377px) |
| While appearing | alpha 0.29, `monitoring = false` |
| Guardian | `Forest Guardian`, speed 52 |
| Spirit count after Guardian | 4 → 1 |
| Music | `arena_theme.ogg` → `guardian_theme.ogg` |

Assets 78 → 82 (10.9MB).

## Completion criteria

- [ ] Four enemy kinds but **one scene**
- [ ] One more `.tres` is a new enemy
- [ ] The Guardian (sheet with no facing) also comes out correctly
- [ ] When the Guardian appears, small fry fall back and the music changes
- [ ] `pnpm game:check` 0 · manifest 0 · media 0

## Deferred to Lesson 14

- Score and saving records

## Not this lesson

- Enemy health · kills — this game is an avoidance game
