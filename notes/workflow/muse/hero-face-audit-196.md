# Hero face audit: cross-facing proportions (brief 196)

User report: side faces read much smaller than front/back faces when turning,
most visibly on the default hero (Warden). Previous work had stabilized each
facing through walk/stop/attack; the missing contract was consistency BETWEEN
facings at equal world scale.

## Method

Measured the committed `idle.png` row 0 (which carries the canonical head band
per facing, byte-identical to walk frames and the attack torso face) with
registered landmarks, not the fixed neck band:

- `face_h`: rows holding >= 6 skin pixels inside an audited face-core window
  (skin only: clear of hairlines, hood trim, ears, neck). Keeper has no face
  window: the beard mass runs continuous past the neck with no chin.
- `skull_w`: median opaque span (alpha >= 64) over calibrated eye/temple rows
  inside an x window that excludes tails, pigtails and flowing hair.
- Ratios are side/down. A profile never foreshortens vertically, so `face_h`
  must keep most of the frontal height; chibi skulls read near spherical, so
  `skull_w` must keep most of the frontal width. Hair/hood extent is reported
  separately and never counted as face.

## Before (committed pre-196 sheets)

| hero    | face_h d0/d2 | skull_w d0/d2 | hair note |
|---------|--------------|---------------|-----------|
| warden  | 20 / 16 (0.80) | 57 / 42 (0.74) | hood smaller too, not just the face |
| knight  | 15 / 9 (0.60)  | 44 / 39 (0.89) | hair mass close; face opening tiny |
| eclipse | 14 / 12 (0.86) | 49 / 43 (0.88) | hood + face both smaller |
| dancer  | 18 / 17 (0.94) | 45 / 46 (1.02) | narrowness is hair occlusion + profile, skull matches |
| keeper  | n/a (beard)    | 50 / 53 (1.06) | big bearded face in both; consistent |
| sage    | 10 / 8 (0.80)  | 35 / 36 (1.03) | side-swept hair covers profile forehead; skull matches |

(The director's neck-band widths — warden 59/47, knight 45/41, eclipse 58/55 —
already hinted at this, but those bands mix clothing/hair with face and end at
a fixed neck, so the landmarks above are the actual evidence.)

Confirmed mismatches: **warden, knight, eclipse**. Their side faces are
60-86% of frontal height with 74-89% skulls — a different, more adult/slender
head, not foreshortening. Dancer, keeper and sage are consistent (skulls at or
above frontal; dancer/sage side-face shortfall is hair occlusion, documented
in their lower face bounds) and keep their exact bytes.

Up (back-of-head) audit: down/up band heights are identical per hero
(46/46, 46/46, 44/44, 36/36, 42/42, 34/34) with widths within a few px
(dancer up reads wider only by pigtail spread). Backs come from the same
turnaround masters at the same row-0 scale and need no correction.

## Correction

Uniform head calibration of the three confirmed side heads, applied to the
donor contact frame before the canonical-head paste, so all 4 walk frames,
all idle frames and the derived attack torso share it byte-identical:

| hero    | factor | anchor (x, y) | head bottom | arm-capsule margin |
|---------|--------|---------------|-------------|--------------------|
| warden  | 1.18   | (72, 84)      | 119         | 1 px (head ends 125, capsules at 126) |
| knight  | 1.17   | (73, 100)     | 115         | 1 px (head ends 118, capsules at 119) |
| eclipse | 1.19   | (66, 84)      | 118         | 2 px (head ends 124, capsules at 126) |

The head part scales uniformly about its anchor (face shape preserved: no
per-axis stretch, no frontal stamp) and composites over the donor collar;
rows below the scaled head and every arm-capsule row keep their exact bytes,
which the bake asserts. Knight grows both ways (anchor mid-head) because its
shoulder capsule starts at row 119; warden/eclipse anchor at the crown so the
head top stays aligned with the frontal top.

Rejected alternatives, viewed before deciding:

- Turnaround-side head swap for warden: the turnaround side hood is bigger
  (63 px vs 47) but its face sits unreadable in hood shadow. Fails the
  readability requirement.
- Turnaround-side head swap for knight: barely wider (43 px vs 41) and no
  taller; fixes nothing.
- Whole-body enlarge / gait freeze / idle-only head: banned by the brief and
  unnecessary; the calibration touches head-band rows only.

## After (baked sheets)

| hero    | face_h side/front | skull_w side/front |
|---------|-------------------|--------------------|
| warden  | 23 / 20 (1.15)    | 52 / 57 (0.91)     |
| knight  | 15 / 15 (1.00)    | 46 / 44 (1.05)     |
| eclipse | 14 / 14 (1.00)    | 47 / 49 (0.96)     |

Turning reads as the same character on all three; front/back identity is
untouched (down/up columns byte-identical, portraits byte-identical).

## Regression bounds (locked before the bake)

`_check_face_proportions` in `pack_painted_world.py` (runs under `--check`)
plus `tests/test_hero_face_proportions.gd` (registered in the Godot suite)
and `tools/test_hero_face_checks.py` (registered in `check:assets`):

- `face_h` side/down >= warden 0.95, knight 0.80, eclipse 0.93, dancer 0.85,
  sage 0.72. Each corrected bound sits between the old defective ratio and
  the corrected one (margins >= 0.07 both sides); sage documents the
  hair-occluded profile forehead.
- `skull_w` side/down >= warden 0.85, knight 0.95, eclipse 0.92, dancer 0.90,
  keeper 0.90, sage 0.90.
- Negative controls: the exact old side heads (rebaked with the calibration
  table emptied — verified to reproduce the audited 16/9/12 face and 42/39/43
  skull pixels) fail every bound even pasted identically into all walk/idle
  frames; the GDScript probe inverts the calibration geometry and is rejected
  in every frame.

## Re-pins (all reviewed art changes, nothing else)

- `tests/test_hero_gait.gd` PRESERVED: warden/knight/eclipse idle bytes.
- `gate_hero_forecourt.gd` PAINT_LEFT / PAINT_IDLE_RIGHT / PAINT_WALK_LEFT /
  PAINT_WALK_RIGHT: warden/knight/eclipse side columns (mirrors verified
  exact: x' = 143 - (x + w - 1)).
- `tools/custom_asset_contracts.json`: the 6 side-torso color/alpha maxima
  (LANCZOS blends add real colors; counts re-pinned to the new exact pins).
- Dancer/keeper/sage walk/idle/portrait bytes unchanged; all arm patches
  unchanged; soles planted; atlas dims, hitbox, damage, timing unchanged.
