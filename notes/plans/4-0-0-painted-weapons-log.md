# 4.0.0 painted-weapons log

Author-only. What was actually built for brief 056 (held weapons match the
painted heroes), why it is shaped the way it is, and what bit us. The other
4.0.0 round is changing actor/hero-resource/terrain art in parallel; this
round touches none of those files, and actor compatibility is judged after
that integration.

## What changed

- `apps/game/tools/pack_painted_weapons.py` (new): deterministic pack from the
  master `notes/workflow/muse/art/4-0-0/painted-weapons.png` (1536×1024 RGBA,
  2×3, right-facing) to six bounded runtime sheets. Separates by alpha
  components, not grid lines; `--check` rebuilds in memory and fails on any
  pixel difference. A separate tool; the other round's packer is untouched.
- `apps/game/assets/custom/items/weapons/*.png` (new, six files, 1.8KB
  total): warden 17×5, dancer 15×9, keeper 15×9, knight 15×7, eclipse 17×8,
  sage 22×7. Each has a 1px transparent margin by construction.
- `apps/game/scripts/actors/weapon_rig.gd` (the one owned file): `_draw_held`
  draws the painted sheet at 1:1 with the same aim, depth (z 2), profile
  signals, and muzzle seats (16/9/9/9). Flash geometry, spans (0.16/0.22s),
  and the sidearm rule are byte-for-byte behavior; only stroke edges are now
  anti-aliased. Sheets wear the hero readability tint; flames keep the legacy
  boost explicitly per stroke.
- `apps/game/tests/test_painted_weapons.gd` (new, 574 cases, direct
  `--script` callable, registered in `run_regression_tests.mjs`).
- `apps/game/tools/shot_painted_weapons.{gd,tscn}` (new): windowed production
  board — 24 live Players plus 24 4x rigs, normal/fire/clear stages, 447
  checks in validate mode.
- `apps/docs/docs/assets/manifest.md`: one entry with author note and
  atlas-cell → runtime-file mapping. `custom_asset_contracts.json`: six
  `weapon.*` entries (sizes, graded alpha, 1px edge padding).
- `notes/plans/4-0-0-painted-weapons-log.md`: this file.

## Calibration (measured, not guessed)

Pack output (cores at alpha>=32, metadata in output pixels):

| weapon | core box | sheet | tip | grip/axis |
| --- | --- | --- | --- | --- |
| warden | (30,79,805,228) | 17×5 | (15,2) | grip (1,2) |
| dancer | (902,38,1392,302) union | 15×9 | (13,4) straddled | grip (1,4), handles rows 2/6, tips rows 2/5 |
| keeper | (130,363,687,669) | 15×9 | (13,2) | axis row 2, stock row 5 |
| knight | (831,379,1432,592) | 15×7 | (13,3) | axis row 3 |
| eclipse | (32,670,693,952) | 17×8 | (15,4) | grip (1,4) |
| sage | (757,724,1507,927) | 22×7 | (20,3) | axis row 3 |

- Gun pivots sit one seat behind the tip on the axis row — (4,2), (4,3),
  (4,3) — derived from `muzzle_length()`, so coincidence is structural: the
  drawn tip is the seat even if a seat constant moves. Melee pivots are the
  grips, hung 2px toward the body as before.
- Left aims mirror the sheet about its axis row; the tip (on-axis) is
  mirror-invariant, so seats hold in all four directions and on diagonals.
- Opaque counts: 23/52/40/50/41/47. File bytes: 219–341 each, 1796 total.
- Brightness vs the hero family: weapon mean RGB 104–148/channel against
  warden-walk (118,89,148) — same tonal family, so the hero tint fits.
- Effective sheet light: tint (3.175,2.857,1.754) × night (0.315,0.35,0.57)
  = (1.0001,1.0000,0.9998). The legacy 2.4 boost would have given blue 1.425
  (clipped); the new math lands on 1.0 in all three channels.

## Decisions

- Crop the core box exactly, then expand the margin — no source-side padding.
  At a ~40x downscale 12px of pad compresses to 0.3px and rounding can push
  the tip into the margin column; expand-after-resize guarantees the border.
- Floor alpha<8 (measured: 72k dust pixels, 4.6% of the master), scrub matte
  RGB (transparent pixels averaged a warm gray 60,53,52 — a real matte-box
  risk), keep the 8–31 fringe. One 1px alpha blip inside the knight gradient
  is logged as dust and vanishes in the downscale.
- Keep the UnsharpMask pass with the hero pack's exact parameters: a 40x
  LANCZOS downscale without it turns edges to mush. Same pipeline, same look.
- `self_modulate = WHITE` on the rig with per-draw tints, instead of keeping
  2.4 on the node and counter-tinting the sheet: the sheet shares the hero's
  tint by name, the flames keep 2.4 by name, and neither can wash out.
- No idle motion at all. The repo has no reduced-motion setting (searched;
  only unrelated "reduced" hits), so compatibility means adding no motion:
  the pose is static, flashes stay ≤0.22s and freeze under pause/result, and
  nothing animates without a real `flash()` call.
- Twin daggers stay one sheet: the pair straddles a single hand point, with
  both handle rows and both tip rows recorded. Splitting would have made
  seven textures against the brief's six.
- Test registration and contract entries are treated as sidecars of the new
  test and new textures (standing orders require the first, `check:assets`
  requires the second); both are reported as the only existing-file edits
  beyond `weapon_rig.gd` and the manifest.

## What bit us

- The atlas grid is approximate. The reaper curl starts at row 670, twelve
  rows above the 682 line; the sword tip ends at x=804 and the rifle starts
  at x=757, both across the middle column. Grid slicing would have beheaded
  two weapons and grafted the curl onto the lantern pistol. Component
  labeling plus explicit cut lines (670, 853/854, 725/726) fixed it, and the
  tool asserts every core stays on its side.
- Transparent pixels carried matte RGB (~60,53,52). With Nearest filtering
  this hides, but any filtered upscale (and the importer's own border fix)
  would have smeared it. Scrubbed at pack; the game test reads file truth
  (`load_png_from_buffer`) because the importer's correct border bleed would
  otherwise read as matte.
- The twin-blade centroid trap, twice: the rightmost-column centroid lands
  between the two tips, and the emptiest-middle-row lands inside a blade.
  Both calibrations now find the two masses first and center between them,
  and both verifies assert the straddle rather than paint-on-point.
- The first placement guard missed: tip-minus-pivot equals the seat even when
  the tip slides, because the pivot follows the tip. A 1px sage-tip mutation
  passed 568/568. The game test now also asserts paint ends exactly on the
  tip column, and the mutation fails 1/574 naming the guard. Flash (3),
  tint (5), and seat (14) mutations all fail too.

## Evidence

- `pack_painted_weapons.py` then `--check`: pass; rerun is byte-identical
  (sha256 per file in the report).
- `test_painted_weapons.gd`: 574/574 pass; four mutations fail and restore
  byte-identical.
- `shot_painted_weapons.tscn validate=1`: 447/447 pass headless.
- Existing weapon/combat tests post-change: `test_hero_combat_profiles`
  1128/1128; `test_hero_weapons`, `test_hero_visuals` in the full run.
- `pnpm test:game` (full suite incl. the new test): see the report.
- `check:store-screenshots`: fails as expected after touching `apps/game/`
  (reported, never recaptured).

## Round 2 (brief 063): premium detail at device resolution

The director rendered the round-1 board on a real display: 15–22px sheets
drawn 1:1 under global Nearest read as pixel blocks, and the master detail
was gone. Round 2 repacks from the master at four texels per logical pixel —
never upscales the tiny sheets — and draws at quarter scale through per-item
Linear filtering, keeping every logical number frozen.

### What changed from round 1

- Pack: texture content is exactly 4x logical (60/52/52/52/60/80 wide),
  margin 4px, final sheets 68×20, 60×36, 60×36, 60×28, 68×32, 88×28
  (14KB total). Warden/dancer/keeper fit a uniform scale from the
  width/height rounding overlap; knight pads one transparent row top and
  bottom (zero art change); eclipse (0.9376) and sage (0.9236) scale axes
  independently with the ratio asserted within 9% — trimming would have cut
  crescent curls and the sight bead. The tool re-derives the frozen logical
  metadata from the source every run and fails on any drift.
- Rig: two-space API (`LOGICAL_*` consts with round-1 numbers,
  `texture_pivot()` = 4x logical, `drawn_logical_point()` as the single
  shared world transform), `DRAW_SCALE` 0.25, `texture_filter` Linear in
  `_ready`. Global Nearest untouched. Flashes, seats, spans, sidearm rule
  identical.
- Test (rewritten, 5013 cases): exact-4x sizes, detail floors that a nearest
  upscale cannot meet (≥150 RGB colors vs tiny max 53, ≥60 alpha levels vs 36,
  ≥60 gradient texels), band-based tip/grip/straddle/silhouette checks, and a
  live-Player spawn coincidence check (painted tip vs `muzzle_origin` in world
  for four aims). Still direct `--script` callable.
- Harness: same board and stages (logical span unchanged, so the layout is
  identical); bounds updated, Linear-filter asserts on all 48 rigs.
- Records: contract entries updated to actual dims/stats with 4px edge
  padding; manifest sizes and pipeline note updated; the round-1
  `run_regression_tests.mjs` line removed (file reserved for integration).

### Measurements

- Detail: RGB colors 281–627, alpha levels 87–127, opaque texels
  246/576/549/627/365/422. File bytes 1536–2930 each.
- Pack `--check` passes; rerun byte-identical (new sha256 in the report).
- New test 5013/5013; tip/filter/scale mutations fail 2/2/1 and restore clean.
- Harness validate 495/495. Existing weapon/combat tests re-run green.

## Round 3 (brief 067): clean fixtures, fully framed board

Case counts from rounds 1–2 above are historical; current counts are below.
No production, art, packing, geometry, or timing changes in this round — only
`tests/test_painted_weapons.gd` and `tools/shot_painted_weapons.gd`.

### What was wrong

- Both fixtures added each Player to the tree before configuring its Cam, so
  every entry tripped `Camera2D overridden to physics process mode` under the
  project's physics interpolation. Fixed by setting `process_callback` to
  physics before `add_child` (test helper `_add_player`, board setup).
- The board disabled each player Cam only after adding it, so cameras went
  current one by one and the viewport kept the last stale canvas transform.
  Fixed by disabling before entering the tree, resetting the transform to
  identity once, and asserting null camera + identity transform every stage.
- The real row collapse was production bounds, not the camera: the arena
  clamp (x 96..712, y 150..322) stacked board rows 3–5 at y=322 and shoved
  row 0 to y=150 — exactly the director's screenshot and exactly 28 failing
  same-side pairs. Fixed fixture-side with `set_bounds()` to the board rect
  grown by 200; physics still simulates, no production file touched.

### Framing validation (rendered bounds, all three stages)

- Viewport owns no camera; transform is identity; visible rect is exactly
  (0,0,1200,700) (printed, measured).
- All 24 bodies: feet on screen, sprite frame rect rendered and intersecting
  the visible rect, facing matches the side.
- All 24 held + 24 close sheets: full texture quads (same pivot/mirror/aim
  math as the draw) with all four corners on screen.
- Pairwise separation (>50px) over all 24 body slots and 24 close slots.

### Measurements

- New test 5016/5016 (5013 + 3 camera asserts), zero script errors/warnings.
- Harness validate 2133/2133, zero script errors/warnings.
- Mutations: close block moved off-screen fails 360/2133; bounds fix removed
  fails 28/2133; both restore byte-identical and green.
- Related suites re-run green: hero_weapons 404, hero_visuals 1214,
  hero_combat_profiles 1128.
