# Night-forest painted-atlas addressing (brief 099)

The intro diorama `apps/game/scenes/gameplay/night_forest.tscn` still read
`nature.png` with logical 1x regions (for example `Rect2(256, 128, 32, 32)`)
while the accepted painted sheet is exactly 3x dense at 1152x1008. Every
tree therefore sampled a third of its frame, which is the chopped
rectangles in the `ko title` capture. The room runtime never had this bug:
`room.gd` multiplies its KIND rects by `art_zoom` and draws at the
reciprocal with node-local smoothing.

## Rule applied, per nature sprite (1280 total, 34 logical families)

- `region_rect`: each component times 3. All 34 families land inside
  1152x1008 (largest: `Rect2(960, 96, 192, 144)`).
- `scale = Vector2(0.33333334, 0.33333334)`: exactly `Vector2.ONE / 3.0`
  in float32, the same value the room runtime assigns. No nature sprite
  had a scale before; the only scaled nodes in the file are the
  `CanopyShade` and `Vignette` gradient overlays, which are untouched.
- `texture_filter = 2` (Linear, node-local), matching `room.tscn` Ground.
  The project-wide Nearest default is unchanged.
- Untouched: `position`, `modulate`, `flip_h`, `centered = false`,
  Ground (`forest_floor.png` repeat mapping), mist, beams, motes,
  canopy, vignette, animation, and every TitleMenu/auth/forecourt file.

World-space geometry is preserved: all 1280 positions identical, all
regions exactly x3, worst draw-size delta 0.00000128 px (float rounding).

## Proof

- New guard `apps/game/tests/test_night_forest_atlas.gd` (registered in
  `run_regression_tests.mjs`): walks actual sprites, checks 3x grid,
  sheet bounds, reciprocal scale, smoothing, anchoring, compensated
  draw size, the 34 families with counts, two placement anchors, and
  the ground repeat mapping; an in-memory old-1x negative trips it and
  restoring returns to green. Also verified by breaking D000 in the
  file (5 failures naming it) and restoring byte-identical (green).
- Related suites still green unmodified: `test_painted_world` 1176,
  `test_title_version` 1305, `test_title_transition` 30.
- Sandbox cannot render windowed harnesses, so the director owns the
  visual: `pnpm godot:isolated --windowed --timeout 45
  res://tools/shot_ui.tscn -- ko title`, then compare
  `builds/shots/ui/ko/title.png` against the pre-fix capture.

## Generator (fixed in the follow-up round)

`apps/game/tools/build_title_forest.py` now emits the same corrected
bytes: KIND stays logical 1x, `region_rect` is scaled by `ART_ZOOM = 3`
at emit time, each sprite draws at `0.33333334` with `texture_filter = 2`
in the same line order as the corrected scene. Seed, counts, positions,
flips, and modulation are untouched. Proven: the updated generator run
against the pre-fix scene reproduces the corrected `night_forest.tscn`
byte-identically (sha256 `64892286...f739a`), and two in-tree regens are
a no-op. A nonmutating `--check` fails when the scene drifts from
generation (it trips on old 1x output, exit 1) and is registered at the
tail of `check:assets`, which passes end to end.

## Follow-ups for another round

- The terrain neighbour-fragment fix stays independent; no packer or PNG
  changed here.
