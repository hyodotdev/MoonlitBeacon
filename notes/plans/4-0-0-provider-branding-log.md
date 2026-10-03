# 4.0.0 provider branding log

Author-only. What the calm official-provider pass built, why each piece
is shaped the way it is, and what bit us. The gate kept its accepted
shape (original title first, Tap chooser, Guest/Google/Apple order,
legal footer, in-app Terms, six heroes); this pass calms the title
light leak, dresses Google/Apple in vendor-brand doors, and finishes
the note-glyph fit the 109 candidate left open.

## What changed

### Candidate 109 applied first, then finished

`candidate109-note-glyphs.patch` applied clean with `git apply`: the
note reserve plus size-readback centering in `gate_entry.gd`, and the
note-glyph assertions in `test_gate_entry_state.gd`. Its glyph
behavior and assertions are preserved untouched; the confirmed
360px-tall overflow it left (card taller than the viewport on
three-provider shapes) is fixed below, and its card check is
strengthened to cover the whole rim, per the brief.

### The fitted height lied by a line

Measured on ko/808x360 with the unready three-provider shape: fitted
want 336.0, real card 378. The 42px gap was exactly two missing label
lines. `GateEntryStyle.wrapped_text_height` measured with
`Font.get_string_size`, which only ever returns ONE line (probe:
single=(196,15) vs multi=(104,30) vs label min 39 for the two-line
provider note). It now measures from live shaped lines
(`get_line_count`, valid synchronously once the card bounds the label
width, probe-verified pre-draw) times font height plus theme spacing,
capped at the label's own max-lines budget spacing-aware — the same
formula the 109 reserve uses. This is the only sizing correction; glyph
reservations and budgets are unchanged.

### Compact logged-out layout, only where necessary

With honest wants, the 360px-tall viewport needs real shedding for
note-heavy shapes (unready3 honest want 378/357, empty 350/329 against
a 336 budget). `_apply_logged_out_compact` resets to full every layout
and sheds in order — hint, stack separation 6→2, provider separation
8→4, guest 44→40, consent last — recomputing after each stage and
stopping early. Providers keep 44px, notes keep their 3-line budgets,
footer links are never what gets clipped. In every acceptance shape
the shedding stops at or before the provider separation: guest stays
44 and consent stays visible, both pinned by the combo test. The
empty-list hint sits within a few px of the budget either way
(ko hides it, zh keeps it); that knife-edge line is deliberately left
unpinned while consent/guest/fit stay pinned.

### Official Google / Apple doors

New `scripts/ui/gate_provider_buttons.gd` (plain Buttons, so entry
collectors and signals treat them like every other door):

- Google: white fill, inside 1px #747775 stroke, #1f1f1f titles in
  Google Sans Medium (FontVariation wght 500, bundled Noto Sans CJK
  fallback), 16px, gradient Super G from the official tile.
- Apple: black fill, white titles in the plain bundled reading face at
  19px (43% of 44px), the whole padded 31x44 artwork scaled to button
  height, never the glyph alone.
- One coherent set: full card width, 44px each, 8px radius, centered
  logo-plus-title groups with real button text in all five locales
  (`gate.auth.signin.google/apple`). Guest and every extra provider
  keep the game's portal look and host labels.
- Platform spacing without duplicated providers: the iOS tile on iOS,
  the Android tile elsewhere, with the spec edge/separation numbers;
  the tiles' baked padding was measured (G 79x80, pads 40/48) and the
  content margins land the spec gaps. Only the tiles' outer 4px stroke
  ring is cropped at draw (it would double-draw inside our own stroked
  face); shipped bytes are untouched.
- No state tints the marks: all five icon colors pinned white,
  disabled dims only titles, focus is a ring drawn outside the rect.
  Mipmapped linear filtering throughout (the project default Nearest
  would shimmer the 4x-minified marks).

### Modal UI ignores scene light

`_isolate_modal_light` puts every canvas item under Content, the five
dialog panels, Terms and the loader on light mask 0; the art layer and
forecourt keep mask 1 with their world ambience. No draw order, input
or coordinate moves — masks only decide what lights touch. The beacon
itself is untouched (cull mask still 1, flare still 9.92): isolation
is UI-side and robust to any light config, unlike a z-range trick (the
beacon covers z -1024..1024, so z would have to leave the sane range).

## What bit us

- `get_string_size` vs `get_multiline_string_size` vs label truth are
  three different numbers (15 / 30 / 39 for the two-line note). Only
  the label's own shaped count plus its theme spacing reproduces the
  39. Any future fitted-height work must use the shaped count.
- Label minimum heights shape at the label's current width, not its
  minimum width — with zero frames between add and setup the card
  explodes (probe: 1281px). The game and tests never take that path
  (ready-time sorts leave sane widths), so it is left as is; compact
  and fitting depend only on shaped counts, never on sizes.
- `Button.icon` theme colors default per state; every one must be
  pinned white or disabled/focus states retint the marks.
- The Google tiles are complete stroked button tiles, not bare logos.
  Drawing one whole inside our own stroked button double-draws the
  edge; the 4px-ring crop is forced by geometry, not taste.
- SVG import scale and mipmaps live in `.import` build config, not in
  the shipped bytes: Apple rasterizes at 4x (124x176 keeps the 31x44
  ratio) with mipmaps for the 3x device scale.

## Round 2: three confirmed defects (brief 111)

Not fully compliant in round 1; the director's renders and boundary log
confirmed three defects, fixed here with no new scope.

### Tile-corner dirt: glyph-only crop

The ring-only crop kept the tiles' rounded-corner stroke pixels (eight
gray points around the G in the real Korean chooser). The factory now
draws the measured 79x80 glyph alone per tile (android x40-118 y40-119,
iOS x48-126 y48-127): identical glyphs at different offsets, every
colorful pixel kept, zero transparent/neutral-dark/sub-threshold pixels
in or around the box (verified by census). Explicit 20px logical draw
height, exact spec edge/gap padding (12/10/12 Android, 16/12/16 iOS),
donor bytes intact, Apple unchanged.

Two size traps bit during this: `icon_max_width` does not scale icon
height (minimum stays at the natural 80px: measured min 88, rejected),
and 12px vertical margins plus the 16px text line pushed Google's
natural height to 48, breaking 44px prominence and inflating every card
want by 4. The fix is the spec 14px type with 11px margins (natural 43
under the 44 floor, glyph 20-22px by engine accounting). The layout
suite caught the 48px door; the state suite only pinned custom minimums.

### Mandatory consent: viewport budget, consent never hides

Compact no longer hides consent under any shape. The vertical budget is
the viewport itself (12px side margins stay): the empty shape fits whole
at 350 with hint and unconfigured visible, mixed sheds the hint
(ko/en/ja) or fits whole (zh), all-draining/all-unready shed hint,
separations (6/8 to 5/5), and guest/extras to 40px, landing at 357 or
below with consent painted. Google/Apple
stay 44 in every layout; notes keep glyph budgets; the suggested
unconfigured-drop proved unnecessary (nothing that shows it exceeds the
viewport) so more information stays visible, not less.

### Apple clearspace: 5px integer floor

Provider and stack separations never drop below 5px in compact (44/10
= 4.4, integer gap 5), on all four Apple sides in full and compact
shapes alike.

### What bit us (round 2)

- Button minimum height is text line plus content margins, border
  excluded (measured: 24 + 8 = 31-32 with expand icons). Any T/B margin
  plan must budget the text line first or the 44px door breaks.
- `get_offset` excludes the border; whether layout adds it back is
  unmeasurable headless. Margins are chosen so both accountings land in
  a compliant band (20-22px glyph), and the director's pixels confirm.
- Wants sit within single px of shape boundaries (zh mixed is 357 vs
  the 360 viewport); compact pins are per-locale literals, and any
  string/font change fails loudly by design.
- Headless pixel scans need integer channel math: float32 boundaries
  misclassify exact-threshold pixels.

## Evidence

- `test_gate_entry_state.tscn`: PASS — 10231 cases (incl. glyph-truth
  re-measurement, consent glyphs, Apple clearspace, draining/all-down
  permutations across 5 locales x 3 framings).
- `test_gate_entry_layout.tscn`: PASS — 64110 cases (incl. draining
  shape, per-framing clearspace, bounds, rims).
- `test_gate_entry_exported_locales.gd`: PASS — 1859 cases.
- `test_gate_loading.tscn`: PASS — 346 cases; loader untouched.
- `test_production_host.tscn`: PASS — 495 cases.
- `res://tools/check_scripts.tscn`: 163 scripts compile.
- `res://tools/check_locale.gd` + `check-locale.mjs`: translation load
  confirmed; static table ok.
- `check-manifest.mjs`: 324 assets, all covered. `check:hygiene`: ok.
- Negative control: provider compact separation 5→4 fails the Apple
  clearspace assertions on compacted draining/all-down shapes;
  restored to 5 and the state suite is green again. (A consent-hide
  control was attempted first and never fires: every shape now fits by
  the extra-shed stage, which itself proves consent hiding is dead.)
- `pnpm check:store-screenshots`: red, as expected after touching
  `apps/game/`; never recaptured.

## Round 3: readable and aligned provider buttons (brief 113)

The user rejected the chooser on the real Korean screen: washed-out
disabled titles, mismatched type sizes, unaligned logos. Fixed in the
provider factory and its brand assertions only; entry scenes, input,
donor bytes, and the manifest's byte records untouched.

### Opaque disabled ink, honest readiness

`GOOGLE_INK_DISABLED`/`APPLE_INK_DISABLED` (alpha 0.38) are deleted:
`font_disabled_color` is now `GOOGLE_INK` (#1f1f1f) and `APPLE_INK`
(white). Doors stay logically disabled from the host's ready flags
and the separate provider note still names every down door; only the
dimming is gone. All five icon colors stay pinned white in every
state, so logo pixels never change.

### One 14px type voice, one baseline family

`APPLE_FONT_SIZE` 19 → 14 with the plain bundled reading face kept:
Apple custom typography is permitted by the sign-in guide, and 14
matches Google's explicit brand type, so neither door outsizes the
other — equal prominence, Google at least as prominent as Apple.
Headless probe: both 14px faces measure height 22, ascent 17,
descent 5, an identical line box and baseline. Korean falls back
differently by face (Google Sans has no Hangul, so Noto Sans CJK;
Maplestory Light has Hangul, so itself) but shapes in the same 22px
line box at 14px. Guest keeps its authored 15px face.

### Centered logo-plus-title groups

`make_provider_button` now sets `icon_alignment = CENTER` beside the
existing `alignment = CENTER`: text CENTER alone centers only the
title while the icon defaults LEFT and the pair splits. Both doors'
groups center on the shared button axis at equal 44px height with
untouched platform gaps, the intact 79x80 G, and the whole padded
Apple file. The actions have different word lengths, so logo ink
legitimately sits at different x; the tests compare group centroids
and type baselines instead. Apple raster census (124x176): white-ink
bounds x31-92, horizontal pads exactly 31/31 — the glyph is centered
in the file, so no layout compensation was needed and none was
added. (Vertical: the glyph center sits ~2px above the file center;
the file draws whole per the guide, so that ships as-is.)

### Tests

- `test_gate_entry_state.gd`: opaque disabled-ink literals per door,
  Apple 14, icon-alignment pins, `_check_official_pair` (one 14px
  size, one baseline family, one button axis, one group centroid) in
  unready and capable shapes across all five locales, plus
  `_test_apple_artwork_centering` (symmetric white-ink pads measured
  from the imported raster the button draws).
- `test_gate_entry_layout.gd`: Apple 14, opaque disabled ink and
  CENTER-plus-CENTER pins per door, `_check_official_pair` in all
  four selection shapes across five locales x three framings.
- Consent, full-card, glyph-truth, light-isolation, and readiness
  guards untouched.

### What bit us

- The copy shipped without imported `gate_entry.*.translation`
  (gitignored build outputs): both suites failed the same 150
  translation-dependent cases on the baseline and the tree alike.
  `pnpm godot:isolated --import` wrote the five files (the editor-
  settings save still errors in the sandbox) and both suites went
  green; the failure sets were byte-identical before/after, then zero.
- `Button.icon_alignment` defaults LEFT (probed headless:
  `alignment=1`, `icon_alignment=0`); the old "centers as one group"
  comment only ever described the title. Pinned now, not trusted.
- Headless pixel census needs integer channel math (the round-2
  lesson, reused for the Apple symmetry check).

### Evidence

- `test_gate_entry_state.tscn`: PASS — 10298 cases.
- `test_gate_entry_layout.tscn`: PASS — 65310 cases.
- `test_gate_loading.tscn`: PASS — 346 cases (untouched).
- `test_gate_entry_exported_locales.gd`: PASS — 1859 cases.
- `res://tools/check_scripts.tscn`: 163 scripts compile.
- `res://tools/check_locale.gd` (isolated) + `check-locale.mjs`:
  ok. `check:assets`: ok. `check:hygiene`: ok.
- `shot_gate_entry.tscn -- validate`: PASS — 18292 cases.
- Negative controls (factory bytes restored, sha256 `a7ce3bfb…b0bbd74`
  matched before and after each): Google disabled ink back to 0.38 →
  11 opaque-ink FAILs and suite exit 1; `icon_alignment` back to LEFT
  → 22 mark-attach FAILs and suite exit 1; suite green again after
  each restore.
- `pnpm check:store-screenshots`: red (capture proofs are gitignored
  and absent in this copy), never recaptured.
- Windowed shots are blocked in the sandbox (killed, exit 137, no
  window); the director renders on a real display. Staged:
  `shot_gate_entry.tscn -- prod=1 state=selection locale=ko shot=…`
  and `locale=en` for the actual unconfigured chooser, the same two
  with `capable=1` for the ready TEST fixture (FIXTURE banner),
  `state=unready locale=ko` / `locale=en` for the mixed shape, and
  the same commands without `shot=` to hold the window open for
  disabled/hover/pressed/focus per door.

## Round 4: composed provider groups (brief 115)

The director's real windowed render proved round 3's centering wrong:
native `icon_alignment=CENTER` centers the icon and the title
independently on the same axis, so the G covers the middle of
“Google로 로그인” and the Apple mark covers “Apple로 로그인”.
Opaque ink and equal 14px titles were accepted as correct and are
kept. The fix composes the group by hand instead of flagging it.

### Composed Group/Logo/Title, no native icon or text

`make_provider_button` now returns a plain Button with `text=""` and
no icon: it holds only the vendor styleboxes and the native
press/hover/focus/disabled semantics. A full-rect centered HBox named
`Group` composes the official mark (`Logo`, a TextureRect) beside the
real action title (`Title`, a Label), all mouse-transparent, so input
stays exactly the native Button's. The group centers mark-plus-title
as one unit with the platform logo gap; the old
title-CENTER-plus-icon-CENTER path is deleted, not flagged.

- Google logo: the same AtlasTexture glyph crop, minimum
  19.75x20 from `GOOGLE_GLYPH_HEIGHT` times the measured region
  ratio; title in Google Sans Medium 14 with the CJK fallback.
- Apple logo: the whole padded file, minimum 31x44 from
  `BUTTON_HEIGHT` times the file ratio — full-file height, no added
  vertical padding; title in the reading face at 14.
- One opaque label ink per door (`font_color` only; labels have no
  per-state colors): #1f1f1f Google, white Apple, every state.
- `clip_contents=true` on the button is the overflow guard. The title
  stays deliberately unclipped: `Label.clip_text` collapses a label's
  minimum width to 1px (probed: title crushed to a 1px sliver), which
  is exactly the failure the old native `clip_text` never had.
- New readback interface for tests: `content_group()`, `logo_node()`,
  `title_node()`.

### Tests read live rects, not flags or formulas

- `_check_official_door` (state) and `_check_official_faces` (layout)
  now pin the composed structure (group/mark/title present, centered
  HBox, platform gap, mouse-transparent children), the title's real
  action key, vendor face/size/opaque ink, single shaped line, the
  logo's aspect fit, clean minification, white modulate, and the
  official artwork (G region, Apple file ratio, fitted minima).
- New `_check_official_group_rects` in both suites reads the laid-out
  rects: group spans the door (so the engine did the centering),
  readable mark/title widths, mark beside title, no intersection,
  actual gap >= platform gap, union centroid within 1px of the door
  axis, children inside the door rect, union clear of the platform
  edges. The summed-width fit helpers are deleted.
- `_check_official_pair` in both suites compares the titles' live
  baselines measured down from each own door top (the doors stack, so
  absolute Y is meaningless), plus shared 14px size, shared metrics,
  shared axis; the state pair also compares actual union centroids.
- The generic "Button styled font" invariant in the layout suite and
  the shot harness exempts the official doors: they carry vendor type
  on Title labels, and every label is still face-checked. No other
  harness behavior changed.
- Consent, full-card, glyph-truth, Apple-centering, light-isolation,
  and readiness guards untouched.

### What bit us

- `set_offsets_preset(PRESET_FULL_RECT)` keeps the current size: on a
  fresh container that means a 0x0 group and crushed children. The
  factory uses `set_anchors_and_offsets_preset`, and the tests pin
  the group span so the preset bug cannot return silently.
- HBox cross-axis: the TextureRect stretches to full container height
  while the Label keeps its 22px line box, vertically centered. Both
  are deterministic; the tests read the actual rects rather than
  assuming either rule.
- `--script` probes that `await` frames can observe the startup
  locale instead of the requested one; suites set the locale and
  build synchronously and genuinely cover all five (proven by the
  locale-dependent compact expectations staying green).

### Evidence

- `test_gate_entry_state.tscn`: PASS — 10390 cases.
- `test_gate_entry_layout.tscn`: PASS — 72270 cases.
- `test_gate_loading.tscn`: PASS — 346 cases (untouched).
- `test_gate_entry_exported_locales.gd`: PASS — 1859 cases.
- `test_production_host.tscn`: PASS — 495 cases (names/disabled/
  signals only; unaffected).
- `res://tools/check_scripts.tscn`: 163 scripts compile.
- `res://tools/check_locale.gd` (isolated) + `check-locale.mjs`:
  ok. `check:assets`: ok. `check:hygiene`: ok.
- `shot_gate_entry.tscn -- validate`: PASS — 18448 cases.
- Negative controls (factory bytes restored, sha256
  `8574840d…52ba152` matched before and after each): group
  separation -30 (mark over title) → 65 FAILs across the beside/
  overlap/gap/centroid assertions and suite exit 1; title ink back
  to 0.38 alpha → 11 opaque-ink FAILs and suite exit 1; suites green
  again after each restore.
- `pnpm check:store-screenshots`: red, never recaptured.
- Windowed re-render stays a director operation; the round-3 staged
  commands still apply (prod selection ko/en, capable fixture,
  unready shapes, held-open states).

## Round 5: accessible provider action (brief 116)

The director's windowed readback accepted the round-4 composition as
visually readable but proved one regression: each native Button had
empty text, empty accessibility_name, and empty
accessibility_labeled_by_nodes — the visible action had moved to
Group/Title without binding it to the actionable control.

### Live labeled-by binding, native text still empty

`make_provider_button` now sets `accessibility_labeled_by_nodes` to
the live `Group/Title` node path on each door. Assistive tech reads
the visible translated title through the binding, so no translated
snapshot can go stale; native `text` stays empty and nothing
double-draws. No other factory behavior changed: same styleboxes,
fonts, inks, gaps, artwork, 44px doors, masks, and native
press/hover/focus/disabled semantics.

### Tests

- `_check_official_door` (state) and `_check_official_faces` (layout)
  pin the binding per door: exactly one labeled-by path, resolving
  through `get_node_or_null` to the door's own Title, whose key
  resolves to translated text (never raw) in the running locale.
- New `_test_official_accessible_action_follows_locale` (state):
  one door across a live ko/en/ja/zh_CN/zh_TW switch keeps its
  binding on the same Title while the resolved text follows each
  locale, with ko/en/ja proven pairwise different so the switch is
  real.

### Evidence

- `test_gate_entry_state.tscn`: PASS — 10472 cases.
- `test_gate_entry_layout.tscn`: PASS — 73800 cases.
- `test_gate_loading.tscn`: PASS — 346 cases (untouched).
- `test_gate_entry_exported_locales.gd`: PASS — 1859 cases.
- `test_production_host.tscn`: PASS — 495 cases.
- `res://tools/check_scripts.tscn`: 163 scripts compile.
- `res://tools/check_locale.gd` (isolated) + `check-locale.mjs`:
  ok. `check:assets`: ok. `check:hygiene`: ok.
- `shot_gate_entry.tscn -- validate`: PASS — 18448 cases.
- Negative control (factory bytes restored, sha256
  `e130b6e3…a2f81d` matched): binding emptied → 54 FAILs across the
  per-door bind/resolve assertions plus the locale-switch binding
  assertions, suite exit 1; green again after restore.
- `pnpm check:store-screenshots`: red, never recaptured.
