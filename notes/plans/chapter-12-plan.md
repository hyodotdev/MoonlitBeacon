# Lesson 12 — Plan

## Official tutorial mapping

Outside the official intro course. See `Tween` · `AnimatedSprite2D.sprite_frames`.

## Goal

Flick the stick with the right thumb to dash. Leave afterimages and slip between spirits.

## What Lesson 6 prepared pays off

Lesson 6 text: "In Lesson 12 a dash stick appears on the right. **It watches only its own finger.**"

Thanks to that, today's work is **placing the same scene one more time** (just flip the anchors).

## Changes

### 1. It fires at the moment of release

`flicked(direction)` signal. Fire **while pushing** and there is no time to pick a direction —
the wobble at the instant the thumb lands fires it.

Capture `_value` **before** zeroing it. Reverse the order and it always fires 0.

The left stick emits the same signal, but nobody listens. Same principle as Lesson 7.

### 2. Ignore the stick during a dash

`_dash_left` guard. Same problem as Lesson 8 knockback — the hand still holding the left stick
erases the dash as-is.

### 3. 1.15s cooldown

Without it you only move by dashing, and walking loses meaning.
Set it just a little longer than the spirit hit cooldown (1.1s) to make it tight.

### 4. Afterimages

**Attach them to the parent (arena), not as children of the player.** As children they
follow along and become a shell, not a trail.

`light_mask = 0` — same judgment as Lesson 5's shadow and Lesson 2's flames.

:::warning At first they were invisible
Alpha `0.5` buried them in the night forest; counting pixels at 30fps showed only a few hundred.
Raised to `0.85`, 4 → 5 sheets, 0.3 → 0.42s.
**On a dark background, translucency is much dimmer than you think.**
:::

### 5. HUD dash indicator

Show it with the **opacity** of the `Dash` letters. Counting a 1.15s cooldown as a number is noisy.
Same approach as Lesson 10's hearts.

## Verification

| | |
| --- | --- |
| Dash travel | 92px |
| Readiness right after | 0.28 |
| Retry during cooldown | `false` |
| Afterimage nodes | 3 (simultaneous) |
| After cooldown | 1.0 |

Device: dash confirmed by flicking the right stick, no script errors.

## Completion criteria

- [ ] Dash at the moment of release, not while pushing
- [ ] Afterimages stay on the path already traveled
- [ ] Cooldown is visible on the HUD
- [ ] Walk and dash with both hands at once
- [ ] `pnpm game:check` 0

## Deferred to Lesson 13

- Three enemy kinds and a final Guardian

## Not this lesson

- Dash invincibility — add it and people play only with dash
- Dash SFX — gather sound work in Lesson 13
