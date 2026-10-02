# Brief 001: Bullet weaving, so the fights are two-sided

## The ask

The user, after watching the game being played:

> 지금 플레이하는거 보고 있는데 너무 일방적이다 적도 수호자도 좀 미사일 같은걸 막 쏴서 막 비행기 게임 피하기 처럼
> 요리조리 잘 피하면서 공격하게 그렇게 해야할듯한데 겜이 좀 재미없어서 일방적이면

In English: the game is one-sided. The player auto-attacks and the spirits and guardians barely fight back. The
user wants them to fire lots of missiles, like a shoot-'em-up (a "plane game" dodger), so the player weaves through
them while attacking. It is not fun when it is one-sided.

## Why, and what "good" feels like

Moonlit Beacon is a cute little mini-game. The player only steers; attacking is automatic. So the fun has to be in
the steering: something is always drifting toward you, you slip between the gaps, and now and then a guardian's big
telegraphed volley asks for a bigger answer. Pressure is constant and readable, never a wall and never a surprise.
A good first loop has the player weaving through slow pastel bullets most of the time and getting hit now and then,
not once in a while. The bullets are slower than the player, small, and leave wide gaps; a person can always find
the way through. It must stay cute (pastel orbs, soft colours), never a red gritty bullet-hell.

## Where things stand

All of this is in the working tree, uncommitted, and `pnpm test:game` was green on it this morning.

Built:
- `apps/game/scripts/actors/bullet_field.gd`: one node holds up to 150 enemy bullets in packed arrays, moves them,
  tests them against the player's chest (`HIT_RADIUS` 6, drawn orb 15 px), stops them on structures, fades them at the
  end of their range, and draws them with `hostile_moon_bolt.png` tinted pastel (`Tint`: PINK, MINT, GOLD, LILAC,
  SKY). It also holds the shooters' turn-taking (`claim_volley`) and the quiet time after arriving in a place
  (`quiet_for`). `Source` tags every bullet (caster, weaver, wisp, aura, stream) so a hit can say what threw it.
- `bullet_emitter.gd`: `BulletEmitter.spiral / aimed / ring / wave`, with `tick()`.
- `guardian_streams.gd`: per guardian style an **aura** that never stops (thorn spiral, petal ring, lantern-smoke wave,
  feather spiral, bubble ring, rune spiral) and a heavier **stream** while it is not winding up a volley. `intensity(cycle)`
  is 0.6 at cycle 1, 1.0 by cycle 4 and 2.0 from cycle 17; `speed_scale(cycle)` up to a third faster.
- `SpiritKind.Barrage` (`spirit_kind.gd`) and the settings on `caster.tres`, `weaver.tres`, `wisp.tres`
  (`barrage_share`, `barrage_speed`, `barrage_count`, ...). The caster throws a fan after its windup (drawn honestly by
  `Spirit.volley_shape`-style data: see `aim_angles`), weavers a slow aimed shot, wisps a slow ring.
- `arena.gd` creates the `Bullets` node, wires `struck` to the hit handler, clears it on a room change, dissolves it
  when a guardian falls, and gives `BULLET_QUIET_ON_ARRIVAL` 14 s of calm on arrival.
- `apps/game/tools/play_bot.gd` reads the field (`bullets:` peak, average in the air, share of time with one within
  80 px, hits by `Source`).
- `apps/game/tests/test_bullet_field.gd`: 46 cases, passing, **not registered** in `run_regression_tests.mjs`.

Measured with the play bot (`react=0.25`, six runs on the tree after the last tuning, tag `bi2`): 27 hits in 23.0
minutes, 1.17 a minute; by cause caster 14, stalker 6, weaver 5; the shots at zones 27, at guardian fights 0 (only one
guardian fight happened); bullets peak 52, average in the air 6.4, share of the time weaving 29%. The old tree
(HEAD) under the same bot measured 0.64 hits a minute. The bot dodges worse than a person, so its hit rate is a floor.
The director measures its own baseline separately; take yours in your copy before you change anything.

Late-game budgets that must hold: the node budget of 1200 (`test_late_game_performance`), hostile `MoonBolt`
nodes capped at 24, spirit cap 40, ground marks 8. The bullet field is one node and adds none. Natural runs already
touch about 1175 nodes, so add no node per bullet, per shooter or per effect.

Not done:
1. `test_bullet_field.gd` is not registered, and `guardian_streams.gd`'s header points at a `tests/test_barrages.gd`
   that does not exist yet. Nothing tests the rules that keep the bullets fair.
2. The guardian fights with aura and stream have hardly been played (one fight in `bi2`). They have not been tuned.
3. Density and unlock curve for the ordinary spirits and the first loop have been calibrated once, on six runs.
4. Nobody has looked at the bullets in a picture since they were tinted: contrast against the arena floors and
   against the player's own projectiles, size, readability with 60 on screen.
5. No docs or notes describe any of it.

## Do

1. Read `AGENTS.md`, this brief, then `bullet_field.gd`, `bullet_emitter.gd`, `guardian_streams.gd`, the barrage parts
   of `spirit.gd` (`_build_barrages`, `_tick_barrages`, `_fire_caster_shot`, `aim_angles`), the arena wiring and
   `tools/play_bot.gd`. Restate the acceptance criteria at the top of your report.
2. Register `test_bullet_field.gd`. Write `tests/test_barrages.gd` (register it) holding the rules that keep the
   bullets fair, for every guardian style and every cycle from 1 to 100 and for every ordinary kind that shoots:
   - every bullet speed is below the slowest hero's walking speed (read it from the hero resources, do not
     hardcode it);
   - within one shot (a ring, a fan, a spiral arm set) neighbouring bullets leave a gap wider than the player's hit
     width plus a bullet's, so a way through always exists;
   - a ring or a set of arms that fires again has turned, so its gaps are somewhere new;
   - the number of bullets one guardian can have in the air stays under a stated cap, and all shooters together stay
     within the field's `LIMIT`;
   - `GuardianStreams.intensity` is 0.6 at cycle 1, monotonic, and 2.0 at cycle 17 and after;
   - the stream is silent while the guardian winds up a volley or a charge (so telegraphs stay readable), and the
     aura never stops.
   Each test must be able to fail: after it passes, break the guarded value and watch it fail, then restore it.
3. Play the guardian fights. Run the gauntlet for all six places at cycles 2, 6 and 12 (commands below) and tune the
   auras and streams (`guardian_streams.gd` numbers, the guardian tuning that already exists) until a fight is a dance:
   something always drifting, a bigger telegraphed volley now and then, hits in the band below. Keep every
   telegraph honest and still readable on its own: `test_volley_fairness` and `test_telegraph_floors` stay green.
4. Tune the first loop and the zones (`barrage_share`, counts, speeds, intervals, unlock cycle, quiet time) to the
   band below with the natural-loop batch. Ordinary spirits should shoot enough that the player is weaving most of
   the time, without the first minute being a wall (`BULLET_QUIET_ON_ARRIVAL` exists for that).
5. Look at it. Render the guardian fights and a busy zone with the desktop harnesses (`apps/game/tools/shot_*.tscn`;
   `--windowed`, in the foreground) into `builds/shots/`, and adjust tint, size and contrast so the bullets read
   clearly on the forest, field, camp, frost, marsh and ruins floors and never look gritty or red. Name the pictures
   in the report; the director will look at them.
6. Document it: a short "Bullets" section in `apps/docs/docs/game.md` in player terms (what a player sees and how to
   answer it), and a section in `notes/plans/3-0-0-build-log.md` (what was built, the numbers, what bit you, and an
   entry under "Not done" for anything left).
7. Run every check the change calls for (list below), then write the report.

## Do not

- Do not add a node per bullet or per shooter, raise `HOSTILE_BOLT_LIMIT` or the spirit cap, or exceed the 1200-node
  late-game budget.
- Do not make bullets faster than the slowest hero, or use thin lines, hard outlines or red for them. No
  gray boxes, debug text or placeholders on screen.
- Do not change the telegraph pictures' meaning, guardian HP or damage budgets pinned by `test_guardian_balance`, the
  cycle 1 to 8 numbers pinned by tests, or the hero combat profiles.
- Do not recapture store screenshots, run any `store:*` script, or touch `stores/`.
- Do not tune to the bot alone. It is a proxy that dodges worse than a person. If a number in the band seems right for
  the bot and wrong for a person, say so in the report and choose for the person.
- Do not edit comments in `apps/game/` for their own sake: any byte there invalidates the store-screenshot check.

## Acceptance

All commands run from the repo root through `pnpm godot:isolated` (throwaway HOME, hard timeout).

1. `pnpm test:game` passes, and `test_bullet_field.gd` and `test_barrages.gd` are in
   `apps/game/tools/run_regression_tests.mjs`. The new tests are mutation-checked (report which value you broke for
   each).
2. Natural first loops, twelve runs across the heroes:
   `pnpm godot:isolated --timeout 3300 res://tools/play_bot.tscn -- tag=nat runs=12 seed=5 speed=3 loops=1`
   then `python3 apps/game/tools/play_report.py builds/play/nat.json`. Required: hits between 0.9 and 1.4 a
   minute (HEAD measures 0.64, the last tuning 1.17); bullets in the air peak at most 110 and average at least 6;
   share of time weaving at least 35%; kills a minute within 15% of the same command's kills a minute on the tree
   before your change (run it first and keep the number); no soft locks; no new "stuck" causes; frame max no worse
   than before.
3. Guardian gauntlet, eighteen fights:
   `pnpm godot:isolated --timeout 3300 res://tools/play_bot.tscn -- tag=gaunt gauntlet=1 guardians=0,1,2,3,4,5 starts=2,6,12 runs=18 seed=11 speed=3`
   Required: at least 80% of the fights won; between 0.8 and 3.0 hits a fight on average; bullets in the air during a
   fight peak at most 110; no frame spikes over 100 ms during a fight. (The old tree measured 89% won, 1.4 hits a
   fight, without auras and streams.)
4. `test_late_game_performance` passes (node budget) and `pnpm check:scripts`, `pnpm game:check`,
   `pnpm check:hygiene`, `pnpm check:locale` pass; `pnpm check:store-screenshots` is run and its result reported (it
   is expected to be red; that is not a reason to recapture).
5. Pictures exist for a guardian mid-stream on at least three places, a busy zone and a caster fan, and the
   bullets read clearly and stay cute (the director judges).
6. `apps/docs/docs/game.md` and `notes/plans/3-0-0-build-log.md` describe the bullets, and `pnpm docs:build` passes.

## Deliverables

Code under `apps/game/scripts/` and `apps/game/resources/`; `apps/game/tests/test_barrages.gd`; the two registrations in
`apps/game/tools/run_regression_tests.mjs`; any bot changes in `apps/game/tools/play_bot.gd` and `play_report.py`
that the measurements need; `apps/docs/docs/game.md`; `notes/plans/3-0-0-build-log.md`; `IMPLEMENTER_REPORT.md`.

## Settle these yourself

- Whether ordinary weavers and wisps shoot at all in the first zone (default: casters from the start, weavers and
  wisps from cycle 2, wisps rarely).
- The exact densities and the unlock schedule, inside the bands above. Default to the smallest change from the current
  numbers that reaches the bands.
- Tints per source. Default: keep the current ones unless a picture shows a floor where they vanish.
- Whether the arena's hit handler needs a short extra grace after a bullet hit (it already has invulnerable time).
  Default: no change.

## How the director will judge

The director repeats commands 1 to 4 in your copy and compares the numbers, breaks one guarded value in each new test
to see it fail, reads the diff line by line (constants, types, doc comments, no per-bullet nodes), and looks at the
pictures. Anything in the report that the diff does not contain, or a check reported as passing that fails, sends the
round back.
