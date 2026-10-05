# 4.0.0 loading glyph log (brief 108)

Real loading stage text invisible from first paint: `GateLoadingOverlay/
LoadingCard/Stack/Stage` held the resolved preparing line, visible=true,
but its actual rect was `(328,1)` — one pixel high — on every loading
frame. Bar/status/cancel painted; stage did not. Cold Arena worker load,
actual guest choice, actual Start. `FIRST_PAINT_FRAMES=2` ordering held
(first two frames issued=false, later true); Arena entered correctly.
A real glyph clipping defect, not fake loading.

## Root cause

Both wrapped labels in the overlay (`Stage`, `Detail`) set
`autowrap_mode=WORD_SMART`, `max_lines_visible=2`, `clip_text=true`, and
only `custom_minimum_size.x`. A wrapped Label with `clip_text` reports a
combined minimum height of 1px:

- `wrap+clip`: min `(328,1)`, rect `(328,1)`, `get_line_count` correct
  (1 or 3 or 5), `get_visible_line_count=0`.
- `wrap, no clip`: min correct (`23` single, `49` two-line capped,
  `75` three-line), visible lines correct.

Measured: font height `23` (body 15) / `18` (small 12), Label
`line_spacing=3`, so two lines need `49`, not `46`. The card's fitted
height (`GateEntryStyle.fitted_stack_height` via `font.get_string_size`,
height `17`, no spacing, no multi-line) gave `23` even for five-line
stages, so the card never forced the label's minimum either.

## Fix (`apps/game/scripts/ui/gate_loading_overlay.gd` only)

- `_reserve_wrapped_heights(content)`: bind both labels to the live
  content width, read each combined minimum with the clip briefly off
  (true wrapped need: font lines plus spacing, capped to
  `max_lines_visible`), keep it as `custom_minimum_size.y` (at least one
  font line). Immediate, no frames needed; `get_line_count` is correct
  even at 1px.
- `_fitted_height_reserved()`: fit the card from the reserved minima for
  the two wrapped labels and combined minima otherwise (shared helper
  misses spacing on multi-line).
- `_recenter_card()`: reserve first (fallback width when the view is
  still zero), then fit from reserved. Covers begin, error, cancel,
  retry (via begin), visibility and every resize.
- `set_stage_text()`: refit after the text change (was text-only).

No changes to intro/menu, providers, Host/Journey/cloud, SDKs, config,
other scenes, assets, version, package, protected files, texture
settings, or unrelated gate components. No fake progress, holds,
preloads, waits, or budget changes.

## Tests (existing files only)

- `apps/game/tests/test_gate_loading.gd`: first-paint layout (before
  issued), cancel-before/after and error/retry cards, plus new
  `_test_wrapped_glyph_heights` — first paint in all five locales at
  base framing, long stage via public `set_stage_text` on a stable
  cancelled card (wraps past max, capped to two, short-again), long
  detail via the honest fail card before the paint gate (no worker).
  Helpers compute wrapped need from the label's own line count, font
  height and spacing — independent of the reserve path — and assert
  rect height vs line/wrapped need, not-1px, reserved minimum,
  visible lines, card inside, stack disjoint, buttons inside card.
- `apps/game/tests/test_gate_entry_layout.gd`: `_check_loader_glyphs`
  on flying (plus issued=false first-paint assert), error and cancelled
  in all five locales x 808x360/840x360/808x606, plus locale-resolved
  and long wrapping stages on the stable cancelled card with cap
  asserts. Existing `_check_tree` calls kept; loader buttons now also
  asserted inside the loader card (generic owner lookup skips
  `LoadingCard`).

Counts (isolated, after `--import` for translations):

- `test_gate_loading`: 46 -> 346, pass, no SCRIPT ERROR.
- `test_gate_entry_layout`: 50162 -> 55907, pass, no SCRIPT ERROR.
- `test_gate_entry_state`: 387 -> 387, pass (unmodified, regression).
- `godot:isolated --quit`: exit 0 (compile check).
- `check:hygiene`: ok.
- `check:store-screenshots`: fails (missing capture proof in this copy;
  expected after any `apps/game` touch; no recapture per brief).

Negative control: reserve forced to `1.0` -> loading suite fails
87/346, all new glyph asserts (`1.0 >= 23.0`, `not 1px`, `reserved`,
`glyphs visible 0 >= 1`); all 46 original generation/cancel/drain
asserts still pass. Restored -> 346 pass.

Director renders pixels and runs final full verification.
