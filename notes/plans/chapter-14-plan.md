# Lesson 14 — Plan

## Official tutorial mapping

Outside the official intro course. See `Singletons (Autoload)` · `ConfigFile` · `user://`.

## Goal

Put **how well you did** on a result screen that only had win and lose.
Score · rank · best record. The record survives turning the app off and on.

## Changes

### 1. The score formula is the rule — the core of this lesson

| | Score | What it praises |
| --- | --- | --- |
| One beacon | 300 | The basic goal |
| 1s remaining | 12 | Fast |
| One remaining heart | 250 | Not getting hit |
| Escape | 500 | You have to finish |

Rank thresholds S 2400 · A 1900 · B 1400 · C 900.
**Fail to escape and it is always D.**

This one line defines the game. Drop it and "light beacons and wait 90s" becomes the optimal strategy.
Show a real 1,904-point D.

### 2. `Score` is a `RefCounted` data type

The arena fills it and the result panel draws `lines()`. Both only know this type.
Same as the Lesson 10 HUD principle — **the drawing side does not calculate.**

### 3. `Records` autoload

What Lesson 9 deferred as "anything that must survive across scenes is Lesson 14" is this.
`reload_current_scene()` wipes everything. Only the best record should survive.

**Put only the best record on the autoload.** Move arena state too and
Lesson 9's "restart means from the beginning" collapses.

`user://records.cfg` · `ConfigFile`.
**A missing file is not an error** — a first-run device does not have one.
Treat `cfg.load() != OK` as an error and the first launch dies.

### 4. Numbers climb and a stamp lands

`tween_method` from 0 to the real value, one line at a time. After all four lines, the total, then the stamp.
2.2s in all.

**Do not add lines one by one.** All four lines hold their seats from the start; only the numbers climb.
Add them and label height grows and overlaps what is below (item 5).

Stamp is `scale 2.4 → 1.0`, `TRANS_BACK` + `EASE_OUT`.
Forget `pivot_offset = size * 0.5` and it stretches down-right then comes back.

**Tap during the flourish and it winds to the end.** From the second run you have already seen it.
That tap does not restart — skip and play-again are different actions.

### 5. Overlap — we learned it by rendering

:::danger Empty labels will not tell you they overlap
In the first layout the `S` stamp sat on the title and `New best!` sat on the prompt.
It only showed when we actually rendered a screen with values filled in.
:::

| | Vertical (from center) |
| --- | --- |
| Title | −104 ~ −50 |
| Breakdown | −36 ~ 46, right-aligned |
| Stamp | −32 ~ 38, right of the breakdown |
| Prompt | 62 ~ 84 |

`New best!` is not a separate node; it went into the prompt line.

### 6. The result screen found Lesson 9's gap

:::danger Result screen beacons 0, HUD beacons 1/3
First run on device. Pushed by a spirit and died beside a beacon, then after the panel appeared
it kept filling at the feet and lit itself.

Lesson 9's `_over` only stops the arena. **The beacon runs on its own clock.**
Make `Beacon.freeze()` and stop all three in `_finish()`.
:::

For five lessons this was invisible anywhere until we printed the beacon count on screen.
**Put a number out and the mismatch shows.**

## Verification

| | |
| --- | --- |
| Clear | 2,404 pts S |
| Did not leave | 1,904 pts **D** |
| Perfect | 2,990 pts S |
| Render of a real run | 3,110 pts S, no overlap |
| Flourish | 0.4s all 0 → 1.1s first line done → 2.2s total · stamp |
| Save | stays in `user://records.cfg` and is read on relaunch |
| Device run 1 | start after wiping data → 984 pts D · `New best!` · HUD beacons 0/3 (1/3 before the fix) |
| Device run 2 | relaunch after `am force-stop` → `Best 984 (D)` |

## Completion criteria

- [ ] Score breakdown and total are visible
- [ ] A rank stamp lands
- [ ] Fail to leave and it is D
- [ ] Best record survives turning the app off and on
- [ ] Dying beside a beacon does not light it behind the panel
- [ ] `pnpm game:check` 0 · manifest 0 · media 0

## Deferred to Lesson 15

- Settings window, Korean/English, credits

## Not this lesson

- Online leaderboard — needs a server. Outside this course
- A ten-entry leaderboard — keep only the best. On a 90-second run,
  a longer result screen makes play-again farther away
