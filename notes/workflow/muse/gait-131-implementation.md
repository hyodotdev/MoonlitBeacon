# Gait 131: alternating side walk and intro cadence

Dedicated implementation note for brief 131 (not the shared 4.0 build log).
Donor originals stay under `notes/workflow/muse/art/4-0-0/gait/`; runtime
sheets are baked by `apps/game/tools/pack_painted_world.py`, never hand-edited.

## Donor verdicts (all six accepted, none redesigned)

Each `gait/<hero>-sidewalk-v2.png` strip holds four left-facing cells in
contact / recover / opposite-contact / recover order. Verified in pixels
(sole-band extent and near/far boot brightness), not just by eye:

- contact rows plant two feet wide with the lighter near boot trading
  sides between rows 0 and 2; recover rows narrow onto one support with
  the swing boot off the ground (see runtime numbers below).
- head tops hold within 1px and solid heights within 4px across each
  strip (sage row 2 runs 7-9px taller, a slightly lower stance; ~1.4px
  at runtime scale — kept as drawn).
- warden valley 1032 and eclipse valleys 565/1057 pass between figures
  whose limbs cross the cut; component assignment keeps every crossing
  whole with its owner (99%+ mass). Zero contested components on all six
  strips, so the contact-split path never triggers.
- eclipse row 3 recovers low: the swing boot hovers 12 source px above
  the floor (~1.8px runtime). Still off-ground with a narrowed stance
  (27 vs 58-60 contact spread); accepted as drawn, the width change
  carries the read at live size.
- isolated specks of 5-12px sit in a few gutters (dust/sparkle or
  generation noise); kept as donor pixels, sub-pixel at runtime.

## Split and registration (actual bake inputs)

Valleys are the lowest-ink columns near each strip quarter (ties to the
lower x). One scale per hero from the taller contact solid (rows 0/2) to
108px; every cell centers its torso anchor (solid-ink centroid-x of the
top 40%: head, chest, hips; striding legs excluded) on cell middle and
plants its 32-level soles on y=192. No per-cell enlargement, no
independent centering on stride-shifted bounds.

| hero | strip | valleys | ref_h | scale |
| --- | --- | --- | --- | --- |
| warden | 2073x758 | 532, 1032, 1540 | 694 | 0.15562 |
| dancer | 2120x742 | 546, 1076, 1606 | 712 | 0.15169 |
| keeper | 2167x726 | 494, 993, 1545 | 646 | 0.16718 |
| knight | 2172x724 | 551, 1077, 1620 | 656 | 0.16463 |
| eclipse | 2078x757 | 565, 1057, 1594 | 708 | 0.15254 |
| sage | 2079x756 | 500, 1009, 1532 | 704 | 0.15341 |

Solid heights rows 0-3: warden 694/692/687/689, dancer 708/712/712/710,
keeper 642/643/646/640, knight 653/657/656/657, eclipse 708/708/705/705,
sage 695/697/704/697. No global shrink triggered: every placed cell
clears the 4px side/top gutters with room (placed ink x in 29-128,
tops at 84-85, soles on 191). Right columns are exact mirrors of the
placed left cells.

Runtime sole metrics, left column (spread px, near/far brightness):

| hero | row 0 | row 1 | row 2 | row 3 |
| --- | --- | --- | --- | --- |
| warden | 66, L+54 | 36 | 69, R+51 | 42 |
| dancer | 62, L+61 | 28 | 60, R+57 | 27 |
| keeper | 77, L+17 | 52 | 74, R+22 | 53 |
| knight | 62, L+34 | 24 | 57, R+43 | 24 |
| eclipse | 60, L+13 | 34 | 58, R+21 | 27 |
| sage | 60, L+30 | 37 | 57, R+31 | 32 |

L+n/R+n is how much lighter the leading side reads. Contact-vs-recover
margins run 20-33px; brightness deltas 13-61. Test thresholds sit at
12px and 8.0 with the signs pinned per row and side.

## Intro stride

`GateHeroForecourt.WALK_CYCLE_HEIGHTS = 0.5`: one four-frame cycle per
half body height of measured screen travel. Walk cycle advances by
honest per-tick distance (partial step on arrival); idle keeps its own
time clock. Departures resume their stride row across dwells and turns;
reduced motion and staging switches behave as before. Combat and the
Player keep `Hero.walk_fps` untouched.

Measured cadence (cadence suite printout, direct drive):

| staging | range cycles/s |
| --- | --- |
| world 808x360 | 1.15 - 1.50 |
| formation 808x360 | 0.83 - 1.03 |
| formation 808x606 (tablet boost) | 0.75 - 0.93 |

The tablet minimum (0.75, slowest-plus-biggest actor) is the honest edge
of the brief's about-0.8 band; the suite floor is 0.75.

## Paint tables refreshed (measured, alpha >= 32 union)

Only `PAINT_WALK_LEFT` / `PAINT_WALK_RIGHT`; every other table is
untouched. All new boxes sit at y=84 h=108 like their predecessors.

Left: warden (41,84,81,108), dancer (34,84,79,108),
keeper (29,84,81,108), knight (38,84,86,108), eclipse (38,84,90,108),
sage (36,84,73,108).
Right: warden (22,84,81,108), dancer (31,84,79,108),
keeper (34,84,81,108), knight (20,84,86,108), eclipse (16,84,90,108),
sage (35,84,73,108).

Asset contracts needed no refresh: new walk color counts (32846-44759)
and alpha levels (249) sit under the contracted maxima.

## Preserved bytes

`bake_heroes` routes only walk directions 2/3 through the donor path;
down/up walk columns, idle sheets and portraits come out of the fresh
bake byte-identical to the committed files (verified region by region
before writing; `git status` after the bake shows only the six walk.png
plus the packer). The gait suite pins per-hero SHA-256 over idle bytes,
portrait bytes and decoded down/up columns against future drift.

## Regression cover

- `tests/test_hero_gait.gd` (new, registered): stride spreads and
  near-boot alternation both sides, head/torso registration, gutters,
  pairwise-distinct rows, exact right-mirrors-left on sources,
  preserved-bytes digests. 354 cases.
- `tests/test_forecourt_cadence.tscn` (new, registered): direct-driven
  cycle-vs-distance, frame order without skips, cadence band, frozen
  dwells, resume-without-jump across a turn, in world, formation and
  tablet formation. 11803 cases plus the printed proof table.
- `tests/test_painted_world.gd`: hero walk sides now assert the mirror
  (visible art, alpha >= 32) instead of true turnarounds; idle and
  spirit sides keep the strict rule. Rationale: the importer's
  alpha-border fix fills transparent/faint RGB with a directional
  tie-break (17 + 1-2 pixels per sheet, all below alpha 20), so exact
  RGBA equality is only meaningful on sources, where the gait suite
  pins it.
- `tests/test_gate_entry_state.gd`: the idle-advance probe now samples
  actor 5 (dwelling 2.3s) instead of actor 0, whose opening stop ends at
  exactly the 0.8s sample; the old sample passed only because one clock
  served both sheets.
- `tools/shot_sidewalk.tscn` (new): twelve-panel cycle board over the
  production PNGs with `row=` pinning, `cycle=`, `trace=`, `shot=` and
  a headless `validate` (81 cases). Windowed stills are for the
  director's display; the sandbox cannot render them.

## What bit

- Godot `%` keeps the sign: `(0 - 3) % 4` is `-3`, which briefly failed
  the stride wrap check; `posmod` is the fix.
- Cadence cycle-vs-distance needs a 0.001 tolerance, not 1e-6: feet
  live in float32 Vector2s at ~300px magnitude.
- A resume tick's own first step can cross into the next stride row, so
  resume asserts cycle-exact plus frame-within-one rather than
  frame-equal.
