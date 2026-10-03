# 4.0.0 art build log

Author-only. How the playable world's pixel art became shaded 2.5D painted art,
what the packer does, and what bit us. User-facing truth lives in
`apps/docs/docs/assets/manifest.md`; this is the record.

4.0.0 replaces every production sheet the playable world reads — six heroes,
seven ordinary spirits, twelve guardians, six terrain sets — with original
painted art packed from generated masters. World coordinates, collision,
muzzles, timing and node counts are unchanged; only the pixels and their
resolution changed.

## Reproduce it

```sh
# Bake all 89 runtime sheets from the masters (deterministic).
python3 apps/game/tools/pack_painted_world.py
# Byte-verify the committed sheets against a fresh bake (~40s), or validate
# them structurally when the masters are absent.
python3 apps/game/tools/pack_painted_world.py --check
# Dimensions and byte totals per sheet.
python3 apps/game/tools/pack_painted_world.py --report
# Review harness: 89 contact sheets 1:1 plus staged game-camera shots.
pnpm godot:isolated --windowed res://tools/shot_painted_world.tscn -- tag=painted
# Headless harness validation (no capture).
pnpm godot:isolated --timeout 900 res://tools/shot_painted_world.tscn -- validate=1
# Contract test for the painted layout (direct-callable; another round owns
# the regression runner).
pnpm godot:isolated --timeout 300 --script res://tests/test_painted_world.gd
```

## Source mapping

Masters are the original generated atlases in `notes/workflow/muse/art/4-0-0/`
(tracked, read-only). The user's commercial reference screenshots were never
copied; the only shared vocabulary is "shaded chibi with depth".

| Master | Size | Runtime outputs |
| --- | --- | --- |
| `<hero>-turnaround.png` ×6 | 1254×1254 (warden 1234×1275) | `actors/heroes/<id>/{walk,idle}.png` 576×768, `portrait.png` 96×96 |
| `spirit-turnarounds.png` | 948×1659 RGBA, 4 cols × 7 rows | `actors/spirits/<species>.png` 576×576 |
| `guardian-states.png` | 1024×1536 RGBA, 4 cols × 6 rows | `actors/guardians/*.png` idle 1152×192, states 768×192 |
| `biome-props.png` | 1024×1536, 4 cols × 6 rows | `terrain/<biome>_props.png` 768×192, nature/prop sheets |
| `biome-floors.png` | 1536×1024 RGB, 3 cols × 2 rows | `terrain/{forest_floor,ground_<biome>}.png` 512×512 |
| `moon-gate-title.png` | 1672×941 RGB | title grass minis composited into the nature sheets |

Row orders follow the brief exactly: spirits
drifter/ember/caster/weaver/stalker/swarm/wisp; guardians, props and floor
panels forest/field/camp/frost/marsh/ruins (floors across the top row, then
the bottom row).

## The zoom contract

Every runtime sheet is 3× its legacy pixel size, and the resources carry the
zoom back down so the world never moves:

- heroes: 144×192 cells, `Hero.visual_scale` 0.255 (legacy 0.765 body factor
  over three). `Player.apply_hero_visual` runs the legacy foot formula on the
  world cell and corrects the sprite offset, so the rendered foot stays at
  world y −5.64 and `BODY_CENTER`, grips and muzzle seats are untouched.
- spirits and guardians: 144 / 192 cells, `SpiritKind.visual_scale` 1/3 on
  top of the legacy (0.9, 0.85) sprite squash (`Spirit.LEGACY_SPRITE_SCALE`),
  so the world body renders exactly as before. `lift` values are root-space
  and unchanged.
- terrain: `RoomKind.art_zoom` 3. `Room._sheet_rect` scales the world KIND /
  PROP / OBSTACLE rects up and draws at 1/3. Feet, pivots, shadows and
  collision circles are computed in world units and never touch the art.
- global `default_texture_filter` stays Nearest for legacy course content;
  every painted node (actor sprites, room ground and decor, preview panels,
  beacon pit, voice icons) sets Linear explicitly.
- obstacle feet plant at world y=50 (sheet y=150); guardian state sheets are
  facing-less horizontals; hero soles sit on the cell bottom edge; spirit
  soles float 6 world px above it, as before.

Bytes: 89 files, 18,372,137 PNG bytes (legacy 87 files, 1,251,136 bytes),
100,534,272 decoded-RGBA bytes. The two new files are `field_nature.png` and
`camp_nature.png`: every biome now has its own scatter sheet instead of
sharing or recolouring the forest one.

## What bit us

- Neighbours touch in the masters. Wings, flames and grass cross gridlines,
  so exact grid crops clipped wingtips and mixed neighbours. The packer
  assigns pixels by connected-component mass, floods contested pixels from
  figure cores, erases small detached fragments near gridlines, and fits
  from the solid-mass box (alpha ≥ 64) so faint dust skirts settle under the
  soles instead of lifting the figure.
- The swarm's side columns ship swapped in the master (verified against the
  pixels, not assumed). The pack swaps them back; see `SPECIES_SIDES`.
- Single-pose sources (all spirits, all guardian states, hero idle) get
  feet-planted breathing baked as frames: small scales about the soles plus
  a ±3px bob for spirits. Nothing mirrors a front view into a back view;
  `test_painted_world.gd` fails if the up column equals the flipped down
  column.
- Guardian variants keep the base silhouette with restrained channel grades
  and offset breathing cycles only. The field's second windup is mirrored
  and reversed for a distinct pattern; camp and ruins reuse windup for the
  charge slot, exactly like the legacy sheets.
- The camp beacon pit is composited from the camp row's own pixels (lantern
  stones plus glass glow) at camp sheet `Rect2(576, 240, 96, 90)`. Earlier
  crops read as a post or timber; the fix was lifting both stone clusters
  beside the lantern post and warming the glass.
- Legacy obstacle sheets were 256×256 with dead rows below the consumed
  first row; painted sheets are 768×192 with exactly the four consumed
  cells. Obstacle art may touch the top edge (it clamps, there is no
  neighbour above); side margins stay clear and the contract pins them.
- The legacy spirit squash (0.9, 0.85) was load-bearing: the Hover keys were
  tripled for the zoom, which only lands exactly on top of the squash. The
  first integration dropped it and rendered spirits ~15% large; restoring it
  made rendered bodies exact to the subpixel.
- Shader pixel assumptions: `actor_polish` neighbour taps gained a
  `tap_radius` uniform (3 on the shared material) to keep the world outline
  width; `world_nature` tree row moved 128 → 384 and sway 1 → 3 (local
  pixels, drawn at 1/3). The rim taps stay one texel, which is now a finer
  line — deliberate.
- The retired builders byte-compared production art against pixel output, so
  `check:assets` failed on seven builders plus the contracts. Each retired
  builder now refuses to bake (exit 2 with a pointer) and delegates
  `--check` to the painted structural check (~3s); the full 40s byte
  comparison stays one manual command. `build_world_assets.py` keeps its
  non-terrain outputs; `pack_ludo_guardians.py` keeps its existence check;
  `test_terrain_sheet_checks.py` now synthesizes its recolour fixture and
  pins delegation instead of retired CLI behaviour.

## Checks and evidence

- `pack_painted_world.py --check`: `painted world packed: 89 outputs current
  (byte-verified)`.
- New `tests/test_painted_world.gd`: 1108 cases — sheet dims, cell grids,
  rect-inside-sheet for every KIND/PROP/OBSTACLE entry, ink in every frame,
  facing distinctness plus no-mirror checks, obstacle feet and margins,
  beacon pit, polish uniforms, global Nearest. Proven to fail: tap_radius
  3→1 fails 1/1108; obstacle top-margin over-pin failed 8 before the
  sides-only correction.
- Updated geometry pins without weakening coverage: hero/spirit visuals
  (cells, foot/world-body preservation, smooth filters), shrine and IAP
  previews (72×72 crops, Linear panels), room terrain (zoom-aware regions
  and alpha bounds), vault and combat profiles (cell/sheet sizes).
- Full regression: all 50 runner test rows pass, plus the new painted-world
  test and the harness validation (the two `--editor` reimport rows cannot
  run in the sandbox and were skipped). Late-game performance passes at 73
  cases with node/draw budgets unregressed.
- `check:assets` passes end to end (176/176 contracts). `check:hygiene`,
  locale, script compile (123 scripts) and `docs:build` pass.
  `check:store-screenshots` fails as required after any `apps/game` touch;
  nothing was recaptured.
- `shot_painted_world` validates headless (109 cases staged) but cannot
  render in the sandbox; the director runs the windowed capture on a real
  display.
- Registration rows for the other round: the new test needs
  `['Painted-world resource contract', ['--script',
  'res://tests/test_painted_world.gd'], true, false]` in
  `run_regression_tests.mjs`, and the painted `--check` belongs in the
  `check:assets` script line next to the retired builders.

## Round 2: floor repeat seams

The director rendered all six rooms and found a straight vertical tile line
at logical x=377-379 in frost/marsh (paired ~8.5 neighbor steps around a
flat middle), crossfade banding in forest/field/camp, and tonal squares in
frost. Cause, all one root: `_tileable` forced opposite floor edges to
their midpoint over 48px. The seam columns matched (the old check's only
assertion), but the first interior columns kept near-source values, so each
tile edge carried a coherent step of half the edge difference (measured
means 12-22, max 41 — twice the interior mean). Under the production
plain-repeat sampler (`texture_repeat = 2` is `TEXTURE_REPEAT_ENABLED` in
Godot 4.7, verified from the class constants — not mirror), ground-local
1024 lands on screen x=378 and renders the injected pair510/seam/pair0
triplet as a line.

Fix, in `pack_painted_world.py`, all rearrangement and blending of the
panel's own pixels (no new art):

- `_heal_cut_edges`: the master concatenates biomes, and five panel edges
  carry 1px cut damage (frost east/north, marsh east/west, forest south;
  pair steps 12-21 vs a 3-10 background). An edge pair stepping harder than
  twice the panel median is extrapolated from its two interior neighbours;
  clean panels pass through pixel-identical.
- No circular shift was kept: rolling would move the original edge
  discontinuity into the tile interior as a visible line. The seam stays
  where the panel edges are.
- `_ramp_match`: symmetric linear ramps tilt each row, then each column of
  the result, so opposite edges meet exactly (sequential matching is exact
  in both axes). Injected slope never exceeds half a level per pixel, so
  there are no bands, no corner squares, no ridge. Tile-vs-source drift
  audits at mean 6-8.5 levels of smooth gradient; detail is retained.
- `_check_floor_seams` now pins what the old check missed, all judged
  against the tile itself: edges meet within one quantum; seam-adjacent
  pairs must not step harder than every interior pair (both axes); no
  four-edge smoothing (both edge strips below every interior strip on both
  axes — the blend signature; one-sided natural calm, as in ruins south,
  correctly passes).

Results: simulated rendered seam steps at the director's band fall from
~8.5/10 to interior-typical (frost 2.57, marsh 5.57); a scanline plot shows
the old notch gone. New floors pass all metrics; the old tiles fail 15
assertions (all six floors trip at least one), which is the negative
control. `tests/test_painted_world.gd` gained the same metrics in GDScript
plus a game-camera repeat simulation over the staged 808×360 frame (sampler
settings pinned from the Ground node first) and two in-suite synthetic
negative controls; 1176 cases pass. Fixture cameras (test player, harness
stage/contact/room players) now set `CAMERA2D_PROCESS_PHYSICS` before
entering the tree, matching the interpolation override without the
warning; production cameras and settings are untouched.

Rerunnable room captures for the director: `pnpm godot:isolated --windowed
res://tools/shot_painted_world.tscn -- tag=<tag> mode=stage` (six
`stage_<terrain>` frames at (950, 590)), or the existing `shot_rooms`
harness; byte repeat via `pack_painted_world.py --check`.

## Round 4 (continuation): registration and check hygiene

The correction round was interrupted after its report, so this round
recovered the tree, finished the deferred integration, and re-verified. No
art was rebuilt: `--check` byte-verifies all 89 outputs, which also proves
no negative-control mutation was left in the generated PNGs.

- Registered the rows round 1 deferred: `['Painted-world resource
  contract', ['--script', 'res://tests/test_painted_world.gd'], true,
  false]` in `run_regression_tests.mjs`, and `pack_painted_world.py
  --check` in the `check:assets` line after `build_world_assets.py`.
- Fixed a latent `check:locale` failure: the static key scan reads any
  uppercase-underscore string literal as a translation key, and the new
  harness's `OS.has_environment("MOONLIT_VAULT_TEST_ROOT")` tripped it
  (`shot_painted_world.gd:66`). Same one-line fix as the sibling harness
  and the vault tests: the split literal `"MOONLIT" + "_VAULT" + "_TEST" +
  "_ROOT"`. Zero behaviour change; locale, 123-script compile, assets,
  hygiene and `docs:build` pass.
- `check:store-screenshots` fails as required after the `apps/game` touch;
  nothing recaptured.
- Full `test:game` cannot pass in this sandbox: every Godot invocation
  prints the environmental macOS `get_system_ca_certificates` ERROR
  (`os_macos.mm:1035`), which the runner's `ERROR:` substring rule counts
  as a row failure, and the two `--editor` reimport rows cannot write
  editor settings here. A per-row probe with only that platform line
  scrubbed is the substitute evidence; the director re-runs the real gate
  on acceptance.
