# 4.0.0 world screens log (briefs 083/084/086)

World-authored presentation for every production screen except the Gate flow
(082) and build/export (076): shrine, hero preview, chronicle, act card,
dialogue, shop, result, ladder, run choices, relic picks, HUD, pause, dash,
settings, credits, quit, analytics consent, and old-title control
compatibility. Mechanics, IDs,copy, timings, purchases and callbacks unchanged.

## Art direction

One moon-gate language: cut-corner bronze silhouettes, narrow polished rims
(lit crown, shadowed foot), a dark groove, deep-ink inset faces, etched moon
diamonds at the bevels, moon-blue keylines, ember-gold reserved for what
matters. 34 hand-authored SVG originals under
`assets/custom/ui/world/` (22 nine-patch faces, 12 ornaments), each at 4
source texels per logical unit, sampled Linear. No generator draws art;
`tools/build_world_ui_kit.py --check` only validates sizes and determinism.

Per-screen roles: shrine/hero = guardian exhibition (full-body centre,
accent-tinted frame, beacon tab/crest); chronicle/act/dialogue = journey book
(book tab/crest, moon beads, bead divider under chapter titles); shop = relic
display (coin tab/crest, lit owned chips, ember buy buttons); result/ladder =
journey record (gold/ash seals, warm/cold wash, ember primary routes);
choices/relic/HUD = combat instruments (ember kindle vs steel ring-trial
faces, card picks, chipped pills, neutral boss bar, dash dial); settings/
credits/quit/consent = journal/colophon/confirmation (steel controls, coral
only on Quit, equal-weight opt-in).

## The draw-scale defect (086) and the fix

Round-2 styles set `texture_margin_left = 48` on 144px art, assuming 4 texels
per unit. Godot 4.7 `StyleBoxTexture::draw` passes margins through as
destination fixed edges: corners drew 48 logical pixels wide and short
controls squashed. The photographed frame confirmed it.

Fix: four tiny classes (`WorldPanel`, `WorldFrame`, `WorldButton`,
`WorldLabel`) paint in `_draw` through `WorldChrome.slices/draw_nine`, which
map source texels to logical units explicitly: 48 → 12, 32 → 8, 56 → 14,
16 → 4, clamping (never inverting) on undersized controls. Native text,
icons, focus, signals and hitboxes stay native; invisible margin styles hold
the old content margins, so layout never moves. `WorldButton` repaints on a
cached state signature only. `test_run_choice_panel::_test_world_draw_scale`
proves the mapping; a deliberate break (src for dst) fails 6 cases.

Also fixed: `WorldChrome.tab` passed a StringName to `get_node_or_null`
(086 intermediate failure) — decor names are Strings now; corner flourishes
were removed with the silhouette re-author (cut corners carry their own
etching); `bar_fill` is neutral-white because the boss bar tints it at
runtime; the `Title`/`No`/`Yes`/consent/buttons mapping keeps No/NotNow safe
and Yes painful.

## What bit

- Scene migrator applied jobs top-down with stale line offsets and half moved
  style lines. Restored all 17 scenes from baseline and re-ran bottom-up;
  verified zero dangling Ext/SubResources and consistent load_steps.
- `WorldFrame` margins read 0,0,0,0 in a probe: `_ready` is deferred past
  SceneTree `_init`, so the probe checked too early. Awaited one frame;
  margins correct. Not a product bug.
- IAP preview assertion used a guessed `ProductsScroll/Products` path. Real
  rows are `CardsScroll/Cards` and `CoinsScroll/Coins`. Fixed, suite green.
- `bar_back`/`bar_fill` drawn as horizontal capsules left transparent bands
  that read oddly in ASCII review; re-authored as full cut-end slots.
- Seal lose gap: verified by arc sampling (gap alpha ≈ halo-only at −40°,
  ring solid at −35°/east); the ember covers −55°..−41° by design.

## Evidence pointers

- `pnpm godot:isolated --timeout 600 res://tools/shot_ui.tscn -- en,ko "" 808x360 validate`
  → 44 ok (22 screens × 2 locales), zero script errors; same at 840x360 and
  808x606 in en,ja.
- `pnpm godot:isolated --timeout 600 res://tools/check_scripts.tscn`
  → confirmed compile of 158 scripts.
- Focused suites: choice 358, quit 27, credits 30, result-layout 205,
  ladder 103, story 709, external-links 29, consent 260, shrine 653,
  IAP previews 609, title-version 1305, title-transition 30, beacon 199,
  skills 126, result-depth 55, result-route 76, guardian-staging 18,
  place-memories 951 — all green.
- Windowed `shot_ui` capture cannot run in the implementer sandbox; the
  director renders shrine/chronicle/shop/result representatives first, then
  the full catalogue, from the staged harness.

## Open for the director

- Visual inspection of the cut-bronze family at real scale (bevel weight,
  etch restraint, ember/steel/coral balance) — headless ASCII thumbs read
  correctly but are not the game.
- `WorldButton` text vs face contrast in amber-on-ember cases (shrine buy
  buttons keep hero-accent text) — unchanged from the old kit, but confirm.
- Full `pnpm verify` + Android gameplay review remain with the director.

## Round 5 (brief 097): title preserved, inner screens finished, perf resolved

- Reverted `title_menu.tscn` to baseline; final diff has no title changes.
  The Gate/title integration stays with the director.
- Perf: knight Lv40 node_peak 1202 → 1193/1195 (73/73 green, threshold
  untouched). Root cause was leaked WorldFace nodes: children run `_ready`
  before their panel hides, so summon-only faces on closed-panel buttons
  (Relic C0–C2/Title, Result actions, Dialogue Skip) lived forever. A live
  census at the peak named all 9 faces; 8 were on hidden panels. Faces now
  dismiss on hide and re-summon on show (`_sync_face` in world_button.gd
  and world_label.gd). A custom StyleBox subclass was ruled out first:
  ClassDB shows StyleBox exposes no draw commands to scripts in 4.7.1.
- Shrine/hero: the rail keeps its pinned 48px head-crop portraits (the
  shared-picture contract in hero.gd), and the preview is now the
  exhibition: 96×96 full body on a dais, hero accent on frame and stage,
  the real painted signature weapon (`items/weapons/<id>.png`) as a corner
  medallion, plus the existing motion trail. All additive; pinned paths,
  sizes and capture gates untouched.
- Chronicle: open book. The index keeps every section and entry (nothing
  hidden; count/heading/progress asserts re-pointed, not deleted) and rows
  are selectable by tap, touch and keyboard (PASS bodies keep touch scroll;
  focus is selection). The opposite page shows section, memory title, all
  recorded lines at reading size and a locale-free page number; locked
  pages show the dim `?` line, never the text. No new strings.
- Shop: showcase scale without moving the 332px frame budget. Supporter
  46×44 → 56×56, lantern 92×44 → 112×56 with 24×48 flames, cards widened
  246 → 264 so blurbs still show whole in three lines; coin cards get the
  coin-crest mint mark in the footer beside the price (footer 25 → 28
  stays under the 68 card minimum). Pixel-10 safe-area assert green.
- Result: journey record carries the run hero. New `HeroBody`/`HeroName`
  plate (96×96 full body on a dais, name in hero accent) fed by one new
  optional `show_result(..., hero_path)` argument carrying the arena's
  run-start `_run_hero_path` snapshot — never a fresh vault read, so a
  later shrine selection cannot rewrite the run. Empty hides the plate;
  all previous callers and layout asserts unchanged.
- Harness: shot_ui result shots pass the keeper and show the road/window;
  new `_check_role` asserts per-screen compositions (six-hero rail,
  exhibition dais+weapon, index+page, product+coin rows with mint, hero
  plate). Faces are asserted only while drawn now.
- Blind-alley notes: `OVERRUN_TRIM_ELLIPSIS` on the chronicle heading
  labels collapsed their minimum width to 1px (story suite caught it);
  reverted. WorldButton minimums exceed their `custom_minimum_size`
  (theme margins + font), which explained the first shop overflow.

## Round 6 (brief 104): lazy Result seal, teardown leak closed

- `result_panel.gd` built its WorldSeal in the member declaration, so every
  unopened Result carried an unparented TextureRect + texture that leaked at
  teardown (director probe; CanvasItem RIDs + seal_win.svg). The seal is now
  `null` until the first `show_result` allocates and parents it. Only eager
  node allocation in the UI scripts (grep-verified).
- `test_result_layout.gd` gains `_check_seal_lifecycle` (6 asserts, 210
  retained): no seal pre-open, orphan count flat across unopened
  instantiate/teardown, gold-on-win / ash-on-defeat texture swap, exactly
  one seal across reopen. Eager-allocation negative control fails the 2
  leak asserts; restored green (216).
