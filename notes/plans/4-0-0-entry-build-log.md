# 4.0.0 entry build log — moon gate entry presentation

Round 1 of assignment 20261002-2349-moon-gate-entry-presentation. This round
owns reusable presentation modules only: a later round connects the finished
native/cloud/journey services and replaces the production title. Nothing
here talks to a store, a cloud, or a native SDK.

## What was built

A standalone entry surface plus its dialogs and loader, all new files:

- `apps/game/scenes/ui/gate_entry.tscn` + `scripts/ui/gate_entry.gd`
  (`class_name GateEntry`): the surface. Moon-gate art, procedural light /
  mist / dust / drift, title block, auth status card, menu bar, version tag.
- `scripts/ui/gate_entry_strings.gd`: runtime loader for the dedicated
  `gate.*` locale table. `scripts/ui/gate_entry_style.gd`: shared palette,
  smooth MapleStory+Noto faces, buttons, cards, fitted card math, code-drawn
  radial glows.
- `scenes/ui/gate_loading_overlay.tscn` + `scripts/ui/gate_loading_overlay.gd`
  (`class_name GateLoadingOverlay`): honest async loader veil.
- `scripts/ui/gate_panel_base.gd` (`class_name GatePanelBase`): shared modal
  shell (dim + centered fitted card + back-button rule).
- `scenes/ui/gate_account_panel.tscn` + `gate_account_panel.gd`,
  `gate_conflict_panel`, `gate_hall_panel`, `gate_exit_panel`: the four
  host dialogs, each usable standalone or embedded in the entry surface.
- `apps/game/localization/gate_entry.csv`: 59 keys × ko/en/ja/zh_CN/zh_TW,
  same column order as the shared table, no ASCII commas.
- `apps/game/assets/gate/moon_gate_title.png`: byte copy of the approved
  master `notes/workflow/muse/art/4-0-0/moon-gate-title.png` (1672×941 RGB,
  2633671 bytes). Manifest row + author note in
  `apps/docs/docs/assets/manifest.md`.
- `apps/game/tools/shot_gate_entry.tscn` + `shot_gate_entry.gd`: windowed
  render harness and headless invariant runner (`validate`).
- `apps/game/tests/test_gate_entry_layout.tscn/.gd`,
  `test_gate_entry_state.tscn/.gd`, `test_gate_loading.tscn/.gd`: the three
  committed tests. They run STANDALONE (see below); the shared regression
  runner is reserved for integration and is untouched.

No existing title/arena/result/player/resource scene or script, journey,
cloud, or native module was edited. `project.godot`, presets, package,
stores, guards, and workflows are untouched.

## Host integration contract

### Showing the surface

Instance `res://scenes/ui/gate_entry.tscn` full-rect. It defaults to a real
logged-out state: no providers, guest usable, shop hidden, loader hidden,
music intent `play` (announced deferred in `_ready`, re-announced on
demand with `sync_music()`, queried with `get_music_intent()`).

### Driving sign-in (presentation never invents success)

- `set_providers([{id, label, ready, draining}])`: only supplied providers
  render. `ready == false` disables with its honest note. Empty list shows
  the "sign-in off, guest works" line.
- Out: `provider_login_requested(id)`, `guest_requested`.
- `show_busy(id, label)` / `show_error(detail)` / `show_logged_out()`.
  Out: `login_cancelled(id)`, `login_retry_requested(id)`.
- `set_offline(bool)`: shows the offline badge; guest/retry stay usable.

### Driving identity and start

- `show_identity(identity, saved_gate)`:
  `identity = {stable_id, hero: Hero | null, hero_name, portrait}`.
  Portrait resolves `portrait`, else `hero.portrait`, else hidden with the
  honest empty line. `hero_name` falls back to `tr(hero.display_name)`.
  `saved_gate = {has_save, title, detail}`; Resume renders only with a save.
- Out: `start_requested`, `resume_requested`, `account_requested`,
  `id_copied(stable_id)`. Start/Resume flip the music intent to `stop`.
- Menu out: `hall_requested`, `chronicle_requested`, `heroes_requested`,
  `shop_requested` (button hidden until `set_shop_available(true)`),
  `settings_requested`.

### Dialogs (embedded or standalone)

- `open_account({stable_id, hero|portrait, hero_name, provider_label,
  saved_title, saved_detail, analytics_opt_in=false, show_links=true})`.
  Out: `account_closed`, `analytics_opt_in_changed(bool)`,
  `external_link_requested(https url)`, `id_copied(id)`. Opt-in defaults
  off; links render only when the project settings hold valid URLs; the
  panel never opens a browser itself.
- `open_conflict(local, cloud)` with `{title, detail, updated}` each.
  Out: `conflict_resolved(&"local" | &"cloud")`, `conflict_cancelled`.
  Nothing pre-picked; focus and back-button take the safe branch.
- `open_hall(rows, {cached, offline})`, rows of `{rank, score, id, hero |
  portrait, hero_name}`. Out: `hall_closed`. Empty list renders the honest
  empty line; rows are never invented.
- `open_exit()`. Out: `exit_confirmed`, `exit_cancelled`. Never quits; the
  host quits. Focus and back-button stay.
- `close_panels()` hides all four.

### Loading (`load_scene(path, stage) -> token`, `cancel_loading()`)

- Paint-first: the veil and stage text render for two frames before
  `load_threaded_request` goes out. The bar shows only real 0..1 samples;
  before the first sample the card reads "preparing".
- Generations: every `begin` takes a token; cancel and re-begin retire old
  tokens. A late completion for a retired token is ignored — `finished`
  can never fire for a cancelled path, and the overlay never enters any
  scene itself. The host places the `packed` scene from
  `loading_finished(path, packed, token)`.
- Out: `loading_finished`, `loading_failed(path, message, token)`,
  `loading_cancelled(path, token)`, `loading_retry_requested(path)`
  (the overlay also re-runs the load itself), `loading_return_requested`.
  Error and cancelled cards offer retry + return.
- A short gate-light flash answers readiness on the entry surface only; it
  ignores the mouse and never gates input. Reduced motion skips it.

### Motion, music, framing

- `set_reduced_motion(true)` freezes drift/glow/mist/dust and skips the
  flash; status, progress, and buttons keep working.
- Music is signal-only: `music_intent(play|stop)`. The host owns players.
- Layout reads the real viewport rect every resize: 808×360, wider phones,
  and tablets frame from the same code. Decorative layers are mouse-ignore;
  only real buttons stop input, and hidden panels/loader capture nothing.

### Locale table

`gate_entry.csv` uses a lowercase `gate.*` namespace deliberately: the
static locale check governs SCREAMING_SNAKE literals against the shared
table, which this round must not touch. `GateEntryStrings.ensure_loaded()`
registers real `Translation`s at runtime, so labels keep `text = key` and
translate at draw time in all five locales. Merging into the shared table
later is mechanical (same header, same columns).

## Budgets (from `shot_gate_entry -- validate`)

- Entry nodes: 123 total (surface + 4 embedded panels + loader).
- Texture bytes: `moon_gate_title.png` 2633671 bytes on disk; every other
  visual (glows, mist, dust sprite, shade, flash) is code-drawn
  `GradientTexture2D` (16–256 px, created once per surface).
- Motion: art drift ±8/±5 px over 16/13 s; 2 glow pulses (6 s, 7.3 s);
  2 mists (±36/∓30 px over 19/23 s); 20 dust motes, 7 s life, ≤14 px/s.
  One sine clock drives all of it; reduced motion freezes the clock.

## What bit me

- Autowrap `Label.get_combined_minimum_size()` reports a 1 px column and a
  matching giant height. Sizing any card from it explodes (measured 1871 px
  on the conflict card). All gate cards now use a fixed width with
  `GateEntryStyle.fitted_stack_height()`, which measures wrapped labels at
  the real content width; panels were compacted to fit 360 px heights.
- `RenderingServer.frame_post_draw` never fires headless, so the loader's
  paint gate waits on process frames instead (every frame still draws).
- GDScript lambdas capture ints by value: signal counters in tests must be
  arrays, or they silently never move.
- `Translation.add_string` does not exist; it is `add_message`.
- `Object.get()` takes no default; hero fields are read through typed
  `Hero` casts instead.
- Missing paths fail through the honest branch but the worker logs engine
  ERRORs the suite forbids, so the committed error test round-trips a real
  non-scene resource (`res://icon.svg`) and the missing-path variant was
  verified by hand (settles, `failed` emitted, error card shows).
- Quitting while a worker load runs tears the worker down with engine
  errors, so the harness drains background loads before freeing/quitting.
- Break-verification honest notes (round 1): freezing `cancel()`'s bump
  alone did not fail the black-box suite (`_loading` + `begin()`'s bump
  carry the safety). Round 2 added a white-box fault-injection subtest
  (`_test_cancel_drains_orphan`) that re-raises the stale token's flags
  behind the overlay's back: with the bump frozen it fails on a late
  `finished`. The rapid-rebegin test covers `begin()`'s bump (freezing it
  fails 4 cases including "superseded path never reached the worker").
  The raw-min-size card break only fails with the height cap also removed
  (67 layout + 70 harness failures); the cap masks it otherwise.

## Round 2: full-ID Hall layout and loader lifecycle cleanup

### Standalone tests (no runner edit)

The three suites and the harness run directly; nothing here is registered
in the shared regression runner (reserved for integration):

- `pnpm godot:isolated --timeout 300 res://tests/test_gate_entry_layout.tscn`
- `pnpm godot:isolated --timeout 300 res://tests/test_gate_entry_state.tscn`
- `pnpm godot:isolated --timeout 300 res://tests/test_gate_loading.tscn`
- `pnpm godot:isolated --timeout 300 res://tools/shot_gate_entry.tscn -- validate`
- Windowed: `... res://tools/shot_gate_entry.tscn -- state=<name>
  locale=<locale> width=<w> height=<h> [shot=<path>] [reduced_motion=1]`

### Loader cleanup behavior (exact)

- `cancel()` and superseding `begin()` move an issued load's path to the
  orphan list. Every `_process` polls each orphan once: `LOADED` is
  claimed with `load_threaded_get` and discarded; `FAILED` /
  `INVALID_RESOURCE` is dropped. No signals, no waiting.
- Re-beginning a path removes it from the orphan list first, and the paint
  gate adopts an in-flight or cached worker state instead of requesting
  twice — so retry and same-path re-begin never double-ask the worker.
- `has_pending_drain()` reports the orphan list. Hosts tearing down
  mid-load wait on it (tests and the harness do); `_exit_tree` takes one
  final non-blocking pass.
- Claiming is idempotent through the resource cache, so a load the test
  helper claims after the overlay drained it (or vice versa) is harmless.

### Leak evidence (read before doubting the warmup)

Probed with stock API calls and zero overlay code (throwaway probes,
deleted after):

- Sync `load(arena)`: 0 warnings. Raw worker request + claim of the arena:
  34 leaked temporaries. Worker loads of `title_menu` / `room` / `hud`
  cold: 3 / 4 / 2. Sync-warm, then 3 worker cycles: silent.
- Conclusion: cold worker loads leak a few engine-side temporaries per
  script compiled on the worker; sync loads and warm round-trips do not.
  The suites sync-warm every path they worker-load
  (`test_gate_loading`, layout's error card, harness validate), so their
  output carries no leak warnings. Windowed single-state loading runs stay
  cold on purpose — a real loading-veil screenshot needs a real cold load —
  and may print the cosmetic engine warning at exit.
- The rapid test's stale path stays cold deliberately: warming it would
  mask the "worker never hears it" assert.

### Full-ID Hall layout (exact)

- Rows are now three lines: `Headline` (`#rank · score`, bold),
  `HeroLine` (single-line hero name, hidden when empty), `IdLine`
  (autowrap ID, full text, never clipped). The director's probe
  (knight, `MB-aaa…a`, en, 808×360) went from card `(194,95,493,273)`
  bottom 368 to `(194,95,420,169)` bottom 264, stable across frames.
- Root cause, deeper than the ID: unbounded autowrap labels report a 1px
  minimum column with a matching giant height, and `Control.size`
  assignment clamps UP to the minimum — round-1 cards were secretly
  ~1700px tall with top-packed content that passed every check by luck.
  Every autowrap label in a fitted card is now bound at build/layout to
  its content width (`custom_minimum_size.x`), which makes minimums sane
  and stable from birth; panel titles went single-line (short keys); the
  Hall ID wraps at 300px (just under its real 318px middle width — the
  bound must sit at or below the assigned width, never above). Cards
  center from the read-back rect after sizing.
- Fixtures use actual-shape 35-char IDs (`MB-` + zero-padded body),
  the longest real hero name (Silver Moon Knight), all locales, and
  1/100 Hall rows in both the layout test and the harness
  (`hall_single`, `hall_many` states).
- Host-string contract this layout relies on: single-line nested labels
  (provider labels, hero names, saved titles, account status) stay short
  in practice; direct stack labels are wrapped and line-capped (2-3
  lines) so pathological strings cap instead of stretching. IDs are never
  capped or clipped anywhere: scrollable fields on entry/account, wrapped
  lines in Hall rows.

## Later rounds

- Register `gate_entry.csv` with the shared table / project translations
  and re-point labels if the key style is unified.
- Connect real provider/journey/cloud/Hall data behind the setters above,
  then replace the production title; prove cold boot and real services.
- Capture the windowed harness states on a real display
  (`state=` × `locale=` × `width=`/`height=`); this round validated them
  headless only. Screenshots: keep TEST markers out of marketing frames.

## Round 082 — crafted gate controls and living hero introduction

Assignment 20261003-0409-crafted-gate-controls-and-living-hero-in, round 1.
The user saw the production entry and rejected the flat app-style controls
and the character-free gate. This round owns the visual change only: new
faces, the six-hero forecourt, title composition, launcher visibility.
No mechanics, account, cloud, native, preset or `project.godot` edits.

### What was built

- `scripts/ui/gate_frame_style.gd` (`class_name GateFrameStyle`, extends
  `StyleBox`): the authored face. Cut-corner ink frames with a bright rim,
  dark foot and steel/gold/coral/mint edge, drawn as vector geometry
  through the canvas item (`_draw` + `RenderingServer.canvas_item_add_*`).
  Cards add gold rivets and a crescent moon on the top edge; buttons stay
  quiet for text. Focus is a gold chamfered ring. No image files.
- `scripts/ui/gate_entry_style.gd`: factories rewired to the new faces.
  Same palette, fonts, fitted-card math and function names, plus
  `apply_kind` (live accent re-skin) and `hall_row_style`. Unused flat-box
  constants removed. `FONT_TITLE` 40 → 32.
- `scripts/ui/gate_hero_forecourt.gd` (`class_name GateHeroForecourt`):
  six presentation actors (body from the hero's own idle sheet, weapon
  from `WeaponRig.painted_sheet`, contact shadow), melee front facing the
  viewer, ranged back facing the gate, staggered idle clocks and arrival.
  Never touches the Vault: locked heroes are marketing, not ownership.
- `scripts/ui/gate_beacon_mark.gd`: crescent-and-beacon title mark beside
  the kicker, drawn from code.
- `scripts/ui/gate_entry.gd`: forecourt behind the interaction layer,
  title block with the mark, exactly one gold primary (resume with a save,
  start without), reduced motion freezes the lineup too.
- `scripts/dev/test_launcher.gd` + `scenes/menus/production_entry.tscn`:
  `show_developer_controls` (default true, pinned false in the production
  scene). Hidden builds no buttons but keeps the probe/clean-UI/boot
  hooks; `dev_launcher` launch arg or `moonlit_dev_launcher` root meta
  re-enables. Old title untouched.
- Tests: state suite gains button-face, forecourt identity/transparency/
  motion and launcher assertions (78 → 198 cases); layout suite gains
  forecourt bounds and authored-face coverage (27751 → 47956 cases).
- `tools/shot_gate_entry.gd`: `lineup` render state (ready card + gold
  primary + full forecourt) in the validate matrix; harness asserts six
  on-screen heroes per render.

### What bit me

- Style minimum sizes clamp cards: a `+16/+8` floor in
  `_get_minimum_size` pushed the Hall card from 420px to 442px and
  off-center on every framing. Content margins only now; the layout suite
  guards the 420px width.
- Arrival tweens outlived the reduced-motion freeze (roots kept rising
  after the clocks stopped). The freeze now kills the tweens and snaps
  the roots to their slots.
- Headless frames run faster than wall time, so idle-frame advance is
  asserted over a 0.8s timer, not over N frames.
- Production-host ladder/rank failures (4/247) reproduce on the
  untouched baseline; they belong to the persistence round, not this one.
- The 25 `check:hygiene` failures are pre-existing in
  `shot_painted_weapons.gd` and the painted-weapons log; none in this
  round's files.

## Round 085 — visible heroes and authored gate controls (correction)

Assignment 20261003-0409-crafted-gate-controls-and-living-hero-in, round 2.
The director rendered round 1 at Korean 1616x720
(`builds/shots/intro-candidate-ko.png`, gitignored): heroes read as tiny
background NPCs and the control faces as flat navy cards with pale
chamfers. Same scope and boundaries as round 1.

### What changed

- Forecourt rebuilt around measured paint, not atlas cells. A stdlib PNG
  probe (`/tmp/paint_bounds.py`, kept out of the repo) found 110px of
  opaque paint in every down/left idle cell (y 82..191, feet at the cell
  bottom), 57-82px wide. Slots now target paint heights: 73-77 front,
  53-57 back, tablet boost capped at 1.10 so the bands hold everywhere.
  Bodies ground on the paint feet, shadows span the paint width, weapons
  draw at body scale (the game's own body-to-weapon proportion) seated on
  the rig pivots. A gate-mouth keep-clear rect is mapped from the
  painting through aspect-cover framing per viewport.
- `GateFrameStyle` gained material: dark keyline, beveled crown/foot,
  etched inner frame, thinner deeper edges, one small motif per accent
  (crescent/diamond/triangle/beacon), warm glow on the gold primary.
  New "portal" mint kind for provider and guest passage; steel stays
  navigation, coral stays destructive.
- Harness gains the `unready` render state (one ready, one down, one
  draining provider) in the validate matrix. Layout suite pins paint
  height bands, paint-rect viewport fit and clearance from UI plus the
  gate mouth, including one post-arrival settled check. State suite
  re-measures the paint constants from the source sheets and smokes
  degenerate draw rects.
- No host/state/service, preset, `project.godot` or store edits. The four
  production-host ladder/rank failures and the `test:game` reimport gate
  failure reproduce identically on the untouched baseline (sandbox
  noise); see the round report.

### What bit me

- `git stash -u` round-trips for baseline comparison drop the new
  `class_name` files; the next editor run rewrites the global class
  cache without them and later runs fail to parse until `--import`
  refreshes it. Re-ran `--import` after the last comparison; all suites
  green again.
- `paint_global_rect` must union the weapon's rotated extent: the blade
  tips, not the bodies, set the tightest viewport margins (eclipse, wide
  phone, 7px after drift).

## Round 090 — production launcher actually hidden (property order)

Assignment 20261003-0510-production-launcher-property-order, round 1.
The director booted the real production scene and found the debug
launcher visible with all buttons, even though the scene pins
`show_developer_controls = false` and the SceneState assertions passed.

### Cause

In `scenes/menus/production_entry.tscn` the pin sat before the
`script` line on the TestLauncher node. A custom property stored
before its script is assigned never lands on the node: the
instantiated launcher booted with the default `true`, visible, with
8 buttons. Confirmed on a real instance (throwaway probe, deleted
after): SceneState prop 1 `show_developer_controls=false`, prop 13
`script`, yet the live node reported
`show_developer_controls=true visible=true child_count=8`.

### What changed

- `scenes/menus/production_entry.tscn`: the pin moved to after the
  `script` assignment on TestLauncher. No other property, node, art,
  script, preset, or store change.
- `tests/test_gate_entry_state.gd`: `_test_production_launcher` keeps
  its SceneState pins, asserts the pin serializes after `script`, and
  boots the actual packed scene untouched behind a stub host
  (`StubProductionHost`: logged-out, no providers, no real services)
  to read the live launcher: pin landed, hidden, no buttons, no
  developer controls reported, still processing. The stub-host boot
  mirrors `test_production_host.gd`'s `_make_entry` override pattern.
  Hooks, `dev_launcher` / `moonlit_dev_launcher` opt-in, and the old
  title's launcher are untouched.

### Evidence

- `res://tests/test_gate_entry_state.tscn`: passed, 250 cases.
- Negative control: with the offending order restored the suite
  fails exactly the 5 new launcher cases (order pin + 4 live-boot
  reads); with the fix restored it passes 250 again.
- `res://tests/test_gate_entry_layout.tscn`: passed, 48185 cases.
- `--script res://tests/test_store_capture_clean_ui.gd`: passed,
  64 cases.
- `res://tools/check_scripts.tscn`: 156 scripts compile.
- `pnpm check:hygiene`: the same 25 pre-existing failures in
  `shot_painted_weapons.gd` and the painted-weapons log; none here.
- `pnpm check:store-screenshots`: fails before the fingerprint on a
  pre-existing `hero-bundle-512.png` determinism error, identical on
  the untouched baseline. Not recaptured. The scene edit
  definitionally invalidates the `apps/game` fingerprint.

## Round 119 — grounded walking party on the original title

Assignment 20261003-1248-grounded-living-intro-sprite-party, round 1.
The human saw the native title and rejected the six large fixed-slot
portraits bobbing above their shadows. This round reworks the
forecourt into six small presentation actors that walk short ground
loops on both sides of the beacon: walk sheet while moving, idle
sheet while stopped, facing the real travel direction, staggered
paces and stops. No auth, account, title, combat, preset, locale, or
store change; the gate-entry layout/state suites are untouched and
still green.

### What was built

- `scripts/ui/gate_hero_forecourt.gd`: patrol actors instead of
  fixed slots. Per-actor normalized waypoint loops (two-point
  back-and-forth or three-point loop), speeds 15-22.5 px/s, opening
  stops 1.6-3.35s then a 1.2-2.4s deterministic dwell cycle. Facing
  follows the Player dominant-axis rule; the walk/idle atlas column
  always matches the pose, with a per-actor frame cache. Feet plant
  on measured union opaque bounds per sheet and facing (idle
  down/left tables byte-identical to before; idle up/right and all
  four walk columns newly measured); paint targets shrink to
  back 33-35 / front 46-48 inside new bands 30-40 / 42-54. Weapons
  seat proportionally (0.20 width out, 0.45 height up) with the same
  rest angles and left-mirror rule, refit only on pose change.
  Shadows stay glued to the feet; roots sort by ground y. No bob, no
  arrival tween, no timers: reduced motion freezes mid-pose and
  resumes from it. Public API kept (`actor_count`, `actor_info` plus
  `sheet`/`moving`, `paint_global_rect`, `gate_mouth_rect`,
  `is_motion_active`), same `HeroActor{i}/Shadow/Body/Weapon` nodes.
- `tests/test_forecourt_party.tscn/.gd` (registered in
  `tools/run_regression_tests.mjs`): wall-time proof. Re-measures
  the new paint tables from the PNGs and pins stride frames
  (distinct bounds, feet on row 192); watches the real production
  title 10.5s for travel (>=25px per actor), pace (>=10px/s on real
  elapsed time), sheet/facing truth on the real sheets, stopped-feet
  and no-bob exactness, weapon hold, z-from-ground, scale under the
  old 65px floor, and clearance of prompt glyphs/doors/version at
  every sample; repeats card/badge/mouth clearance on the standalone
  gate at 808x360, 840x360 and 808x606; freezes and resumes reduced
  motion mid-walk; cycles title/chooser/terms three times checking
  for 24 forecourt descendants, no timers, no Vault change, no
  Player/physics nodes.
- `tools/shot_forecourt_party.tscn/.gd`: windowed render harness
  (title/selection, `t=`, `shot=`, per-second `trace=1` actor lines,
  `reduced_motion=1`) plus a headless `validate` sweep over both
  states and all three framings.

### What bit me

- The state suite pins spawn-time idle sheets and down/left-only
  facing, so every actor opens with a 1.6s+ idle dwell at its route
  head with a spawn facing of down/left. First departures stay
  staggered after it.
- Walk and idle union bounds differ by 1-2px, so a pose change
  refits the hold by <1px. The weapon-drift check compares within a
  pose (same sheet and facing), where the hold is exactly fixed;
  across poses it stays proportional by construction.
- `Texture2D.get_size()` returns Vector2: comparing it to Vector2i
  is a parse error in 4.7, not a warning.
- `pnpm test:game` cannot run in this sandbox: its reimport step
  fails on macOS CA-cert, adb-daemon and editor-settings ERRORs
  before any test starts. Every entry-adjacent suite passes
  individually through the isolated runner instead (see report).

### Evidence

- `res://tests/test_forecourt_party.tscn`: passed, ~8.6k cases
  (sample-count dependent).
- Negative control: with departures disabled (fixed-root idle-only)
  the suite fails exactly the 25 travel/turn/facing cases; restored,
  it passes again.
- `res://tests/test_gate_entry_state.tscn`: passed, 9408 cases.
- `res://tests/test_gate_entry_layout.tscn`: passed, 66732 cases.
- `res://tests/test_title_tap.tscn`: passed headless, 30 cases
  (routing steps need a window).
- `res://tests/test_gate_loading.tscn`: 346;
  `test_identity_registration.tscn`: 61; `test_production_host.tscn`:
  495; `--script test_gate_entry_exported_locales.gd`: 1899.
- `res://tools/shot_forecourt_party.tscn -- validate`: 2996 cases.
- `res://tools/shot_gate_entry.tscn -- validate`: 17200 cases.
- `res://tools/check_scripts.tscn`: 164 scripts compile.
- `pnpm check:hygiene`, locale script, `check:assets`: ok.
- `pnpm check:store-screenshots`: fails (missing capture proofs in
  this copy; the `apps/game` edit invalidates the fingerprint by
  definition). Not recaptured.

## Round 122 — title party on the real forest ground

Assignment 20261003-1248-grounded-living-intro-sprite-party, round 2.
Correction to 119: the director's 1616x720 render showed the corner
routes standing on tree canopies with shadows on trees. Viewport
corners are not ground. This round stages the party in forest-world
coordinates inside the tree-free clearing and conceals it while modal
content covers the clearing. No ProductionEntry, title, combat,
preset, locale, or store change; the gate-entry layout/state suites
are untouched and still green.

### What was built

- `scripts/ui/gate_hero_forecourt.gd`: two stagings, one patrol
  engine. World staging walks six forest-world lanes (verticals at
  x312/x338 and x470/x496, horizontals at y284) through the title's
  own `Screen.center_offset`, at 24-34 world-pixel bodies wearing the
  forest's depth-tier tint by feet row (the `tier_of` curve from
  `build_title_forest.py`, verified to reproduce committed prop
  tints). Lanes avoid the fire column (painted opaque x405..427
  plus flame/smoke), the campsite solids (log pile x273..295 and
  scattered stones), the foreground tree tops, and each other; feet
  stay deep inside the open ellipse and below the prompt glyphs.
  Formation staging keeps the standalone corridors. First walks step
  off at 0.8s, staggered. `set_presentation(world, concealed)`:
  staging switches restart at route heads, concealment only hides
  while the patrol simulates on. Frame clocks run continuous across
  pose changes. No bob, tweens, or timers, as before.
- `scripts/ui/gate_entry.gd`: narrow presentation context only.
  `_refresh_forecourt_presentation` stages world mode beside a real
  title with the backdrop hidden (standalone keeps formation even
  with its backdrop hidden) and conceals the party while the status
  card, loader, a gate dialog, or a title modal (via `Ui/Screen`
  visibility) covers the clearing. Hooked into `_refresh_auth`,
  every `open_*`, `close_panels`, `set_backdrop_visible`, and the
  loader/Screen `visibility_changed` signals. ProductionEntry
  untouched.
- `tests/test_forecourt_party.tscn/.gd`: world assertions added.
  Feet map into the open ellipse (r <= 0.80) through the center
  offset at 808x360, 840x360 and 808x606; feet and paint clear the
  fire box and live solid-prop rects (T925, D025, D018, T901);
  bodies match the tier curve; world scale 24-34; selection and a
  title modal conceal, Tap restores on-lane without teleport and
  without node growth. Formation card/badge/mouth checks retained.
- `tools/shot_forecourt_party.tscn/.gd`: validate asserts world
  staging, clearing placement, fire/prop clearance, world scale,
  travel, sheets, and selection concealment at all three framings.

### What bit me

- camp.png is one static 1104x432 canvas: connected-component
  analysis put the fire at world x405..427 y250..270, a log pile at
  x273..295 y266..291, and flame wisps up to y167. The first lane
  draft crossed the log pile; lanes moved to x300..370 / x440..530.
- The state suite pins the lineup visible with the card up
  (standalone, backdrop hidden) and idle-frame advance over exactly
  0.8s. So world staging requires a Title host (standalone keeps
  formation), and pose changes no longer restart the frame clock.
- A concealed party sits behind its modal by design: the tool's
  card-clearance check now applies only while visible.

### Evidence

- `res://tests/test_forecourt_party.tscn`: passed, ~13.2k cases.
- Negative control: forcing formation staging in production fails
  1269 cases (staging, clearing, tier, lanes); restored, green.
- `res://tests/test_gate_entry_state.tscn`: 9408;
  `test_gate_entry_layout.tscn`: 66732; `test_title_tap.tscn`: 30
  headless; loading 346; identity 61; production host 495;
  exported-locales 1899; `shot_gate_entry -- validate` 17200;
  `shot_forecourt_party -- validate` 4824; `check_scripts` 164.
- `pnpm check:hygiene`, locale script, `check:assets`: ok.
- `pnpm test:game`: still sandbox-blocked at `[Reimport resources]`
  (editor-settings/adb/CA-cert ERRORs, same as round 1).
- `pnpm check:store-screenshots`: fails as expected, not recaptured.
