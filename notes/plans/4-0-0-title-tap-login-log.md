# 4.0.0 title tap-to-login log — original title first, in-app Terms

Round 3 of assignment 20261003-0534-centered-simple-intro-login
(Briefs 096 + 100). A distinct log: the shared entry-build log carries
accepted launcher/export notes that must not conflict on accept.

## Direction

Brief 096 (user correction, authoritative): keep the ORIGINAL title
introduction exactly — NightForest/Beacon diorama, centered title,
blinking TapPrompt, small original menu buttons — and open a simple
centered guest / ordinary Google / Apple selector only after the tap.
Brief 095's immediate three-choice first paint is cancelled. The other
run owns NightForest density and the Gate loader/registration; this
round touches neither scene.

Brief 100 (measured correction): the director checked the live support
site — `ko/privacy` is HTTP 200, `ko/terms` is HTTP 404. There is no
Terms page and no terms setting. The `/terms` sibling derivation drafted
in round 2 is removed; Terms ship as a compact in-app sheet instead.

## Terms draft state (read before any store submission)

The eight in-app paragraphs (`gate.terms.p1`–`p8`) are a GAME TERMS
DRAFT written by the implementer from observed behavior, not legal
counsel. They are faithful to the build on purpose and stay silent on
purpose where the brief forbids invention: no governing law, no age
thresholds, no fees, no warranties, no refund windows beyond each
store's own procedures, no enforcement system, no claim of legal
sufficiency, no new restriction on the repo's MIT-licensed source
(`LICENSE`, Hyo Dev). Google Play Terms and the Apple standard EULA
were checked by the director as store sources only; nothing is copied
from them and the sheet never presents them as ours. The draft needs a
proper review before it backs a store release; the footer consent line
is the user's requested wording, not a consent wall (analytics stays
optional in account settings, purchases stay store-handled).

## What changed

- `scripts/ui/title_menu.gd` (+`scenes/menus/title_menu.tscn` one
  line): opt-in external start. `set_external_start(true)` parks BGM,
  the journey panel and the dev launcher; a tap plays the sfx/flare
  and emits `external_start_requested` with no journey arming, no
  music fade, no arena preload and no legacy `start_requested`.
  `cancel_external_start` re-arms the tap, `external_go_back` unwinds
  the title's own panels for the host, and four `open_*` doors let
  host-routed signals reach the original panels. The scene's Ui layer
  moves 2 → 0 so the embedded gate (default canvas, later sibling)
  draws above it; standalone rendering order is unchanged.
- `scripts/ui/production_entry.gd` (+`scenes/menus/production_entry.tscn`):
  the scene embeds the original title as first paint and drops its
  second set of menu panels (settings/credits/shrine/chronicle/shop);
  the title's originals serve, including arena-return handoffs, which
  the title consumes natively. First paint parks the gate card and
  hides its painted backdrop (forecourt stays). Tap repaints from
  host truth: selection for new guests, ready/resume for restored
  players. Provider data loads at boot; a parked guard keeps async
  host settle from popping the card (user intents unpark). Back
  unwinds confirm → loader → gate panels → selection → title
  panels → exit. The launcher pin stays after `script`, untouched.
- `scripts/ui/gate_entry.gd`: one centered card (guest first, then
  the vertical provider stack, notes, consent line, Privacy/Terms/
  Back footer), modal scrim that only ever closes the selection,
  account door inside the ready card, offline badge top-left, no
  title block/menu bar/version of its own. New `show_title_rest`,
  `is_selection_open`, `is_title_rest`, `set_backdrop_visible`,
  `selection_closed`, and the code-built Terms sheet
  (`GateTermsPanel`: dim + centered card + fixed scroll body +
  Privacy/Close row, same shell as the scene panels).
- `scripts/ui/gate_hero_forecourt.gd`: the six flank the centered
  card along the lower ground, clear of the card, prompt glyphs,
  title doors, version tag and (standalone) gate mouth.
- `localization/gate_entry.csv`: +13 keys (consent, privacy, terms,
  back, `gate.terms.*`), all five locales, no ASCII commas.
- `scripts/ui/external_links.gd`: the fabricated `terms_of_use_url`
  is removed; privacy/support behavior and tests are untouched.
- Tests/harness/tool: state suite gains title-rest, backdrop, terms,
  doors and full production-first-paint coverage (layering, glyph
  clearance, tap/back, parked-settle guard); layout suite sweeps the
  selection (capable + unready) and the Terms sheet every locale and
  framing with 40px auth touch asserts; host suite taps through the
  title and re-points menus to the title originals; the shot harness
  gains `terms` state and windowed `prod=1` (real host) /
  `capable=1` (FIXTURE stub) production shots; the exercise tool taps
  before asserting the choice.

## What bit

- A stale `as HBoxContainer` cast aborted `_test_providers` silently
  (Godot prints SCRIPT ERROR and the awaited function never resumes,
  yet the suite still reports "passed" with a lower count). The
  geometric negative control passed vacuously and exposed it. Every
  touched suite is now also grepped for SCRIPT ERROR: all zero.
- The Terms card read 428 on a 420 request: the vertical scrollbar
  reserves exactly 8px once the body overflows (probed, transient
  script, deleted after). The body width now subtracts the live bar
  width instead of assuming it.
- Async host settle (`refresh_session`/cloud) lands after boot and
  briefly popped the card pre-tap; hence the parked guard plus the
  boot-time provider load that keeps signal-driven tests
  deterministic.

## Evidence

- `res://tests/test_gate_entry_state.tscn`: passed, 376 cases.
- `res://tests/test_gate_entry_layout.tscn`: passed, 47882 cases.
- `res://tests/test_gate_loading.tscn`: passed, 46 cases.
- `res://tests/test_production_host.tscn`: passed, 472 cases.
- `res://tests/test_external_links.tscn`: passed, 29 cases.
- `res://tests/test_title_transition.tscn`: passed, 30 cases.
- `res://tests/test_title_version.tscn`: passed, 1305 cases.
- `res://tests/test_result_route.tscn`: passed, 76 cases.
- `res://tools/shot_gate_entry.tscn -- validate`: passed, 18294 cases.
- `res://tools/prod_host_exercise.tscn`: passed, 23 checks.
- `res://tools/check_scripts.tscn`: 156 scripts compile.
- Negative controls: forecourt slot dragged into the card fails the
  layout suite; broken selection-back fails the state suite; both
  restored to green (the second caught the silent-abort cast above).

## Round 4 (Brief 106): original Rank button opens the real Hall

Integration defect: production's title Rank door still opened the legacy
local ladder while the gate (correctly) shows no Hall button, so the 4.0
Hall was unreachable in production. Minimal glue, visible originals
untouched (same LadderButton label, texture, path, position, hitbox):

- `title_menu.gd`: `_open_ladder` in external mode parks input, hides
  the doors and emits `external_hall_requested` instead of the local
  view; standalone path byte-identical in behavior. New
  `close_external_hall` restores doors + tap.
- `production_entry.gd`: routes the signal to the existing `_on_hall`
  (real `host.request_hall` → gate Hall panel, honest offline/empty
  states, no fake rank, no auto sign-in); Hall Close and the back
  unwind both restore the title. Host-null fallback restores too so
  the title can never strand parked.
- Blocking while open: the title parks its own input/doors at press
  time and the Hall panel's dim covers the rest; the gate card is
  never forced (still title-rest underneath).
- Tests: host suite presses the REAL LadderButton on the production
  main/Host fixture (one board fetch, two rows with hero/score/full
  ID, no loading/arena/login-card, Close + back restore); transition
  suite pins the standalone ladder unchanged. Prior manual-emit
  routing asserts kept.

Evidence (round 4): host 491 passed (+19), transition 34 (+4), state
376, title-version 1305, all zero SCRIPT ERROR; 156 scripts compile;
hygiene ok; store-screenshots fails as expected (touched `apps/game`).
Negative control: intercept emit stubbed → rank asserts fail (fetch 0,
no Hall, 0 rows); restored → green.

## Round 5 (Brief 107): real-pixel defects from the windowed render

Two confirmed defects from the director's actual `prod=1
state=selection` screenshot; no redesign, no fixture hiding.

1. Title chrome over the modal. The Ui layer 2→0 change was not
   sufficient: a CanvasLayer still draws the title screen above
   ordinary gate children. Fix: while any managed overlay is up, the
   title parks its Screen chrome (logo, subtitle, prompt, doors) and
   restores it exactly after. Diorama, forecourt and music untouched.
   - `title_menu.gd`: `park_screen_for_overlay()`; `cancel_external_start`
     now also restores the Screen. Standalone paths unchanged.
   - `production_entry.gd`: parks on tap (card and error alike) and
     before the exit question; restores on selection close, Hall
     close, back-unwind and exit-cancel. Restores are guarded by
     `is_title_rest()` so back-from-ready exit never unparks chrome
     under a live card. This also makes gate/title visibility
     mutually exclusive, so the layer trap cannot recur: with the
     card hidden, title panels still draw above the forecourt as
     before.
   - Caught while testing: with no save, the fresh journey-confirm
     box reads `visible=true` (property) under its hidden panel, so
     the mirrored back chain swallowed bare-rest back and exit never
     opened. `external_go_back` now checks `is_visible_in_tree()`;
     the legacy handler keeps its own check.

2. Unconfigured selection showed Guest only. The gate now always
   renders the ordinary Google/Apple doors in order: host entries
   where listed, honestly disabled bare-brand placeholders (same
   builder, same `not_ready` note line) where omitted, supported
   extras after. No readiness synthesized, dispatch still host-gated.
   `gate_entry.csv`: Korean consent and Terms p1 now end with `.`
   (was a full stop); ja/zh keeps 。.

Tests: state production test pins the empty shape (pair shown,
order, disabled, bare names, guest enabled) plus chrome
parked-on-tap / restored-on-back and the exit round-trip; layout
sweeps an empty-provider selection every locale/framing; host
first-entry expects the pair plus the supported extra with
per-door enabled states.

Evidence (round 5): state 387 passed, layout 50162, host 495,
transition 34, title-version 1305 — all zero SCRIPT ERROR; 156
scripts compile; hygiene ok; store-screenshots fails as expected.
Negative control: placeholders skipped → empty-shape assert fails;
restored → green. CSV revalidated (91 rows, 6 columns, no ASCII
commas, consent ends `간주합니다.`).

## Round 6 (Brief 112): restore real title taps

Defect: on the ordinary desktop window a native mouse click on the
original title did nothing, while Return opened the chooser. Root
cause: the ProductionEntry host root is a full-screen Control with
implicit `mouse_filter=STOP`, so it eats every pointer press before
the title's `_unhandled_input` start handler ever sees it. Key events
are not stopped by GUI hit-testing, which is why Return kept working.
Everything decorative under the root already passes through (Title
root, Screen, all labels, Gate root, Gate Content, hero forecourt are
IGNORE; scrim and card hide at rest), so the root was the only
blocker. Moving start to `_input` was rejected: it would preempt real
menus and modal controls.

Fix (one scene line, no visual or behavior change otherwise):
`scenes/menus/production_entry.tscn` pins the host root to explicit
`mouse_filter = 2` (IGNORE). Children keep their own hit-testing, so
menu doors, the selection card, the scrim and all modals still take
their clicks; the title's `_unhandled_input` ownership is untouched.

Regression: new registered `tests/test_title_tap.tscn` (+`.gd`)
boots the real production entry (original Title, six-hero Gate)
behind a logged-out stub host. Structural pins run everywhere
(host/title/screen/gate/forecourt IGNORE, scrim and card hidden at
rest, menu doors still STOP, no STOP control over the tap point);
real pointer routing runs windowed only — mouse click, touch tap,
menu click without login, disabled-provider tap (begins nothing,
loads nothing), footer Back, second tap after returning — all
through `Input.parse_input_event`/Viewport dispatch, never
`request_start`, `_unhandled_input` or `pressed.emit` as proof.

Why headless cannot guard the routing half: there is no OS window
and no native pointer path — hover tracking is dead
(`gui_get_hovered_control` stays null) and injected-event dispatch
disagrees across environments about whether it even reproduces this
failure (the director's probe passed headless where the same click
failed windowed). A headless green proves nothing about real taps,
so the routing steps gate on a real window.

What bit: the touch tap's emulated mouse counterpart lands on the
footer Terms door after the card opens (the prompt sits over the
footer's row) and opens the Terms sheet — the same would happen for
a real device tap. The test shuts that sheet by pointer when
present and continues; the mouse tap opens no sheet. This side
effect is worth a follow-up look (footer placement vs the prompt),
left unchanged here as out of scope.

Evidence: headless pins 17 passed, routing skipped; forced-routing
validation run (temporary, reverted) 50 passed; STOP negative 11
failed incl. all tap routing while menu clicks still passed, then
byte-restored (sha256 `88467285…b894d63c`); transition 34 and
gate-entry-state 10231 still pass; hygiene ok; store-screenshots
fails as expected (touched `apps/game`, no recapture).
`gate_provider_buttons.gd` and brand asserts untouched. Windowed
proof (`pnpm godot:isolated --windowed
res://tests/test_title_tap.tscn`) needs a display; the sandbox has
none, so the director runs it, including the STOP negative.

## Round 7 (Brief 114): opening tap stops at the chooser

Correction of round 6, whose test worked around the real defect: a
touch on the prompt opened the chooser AND the Terms sheet (the
touch's emulated mouse counterpart landed on the footer Terms door
after the card appeared synchronously), and the sheet then
intercepted the Guest tap. The director's windowed probe confirmed
it (`PRE_GUEST terms=true`, journey exit 1); the cleanup branch is
removed and replaced by fail-on-Terms asserts.

Fix in `scripts/ui/title_menu.gd` (production entry root IGNORE
retained): in external mode a pointer press plays feedback at once
but the login card opens on that pointer's release. Keys, gamepad
and programmatic starts carry no pointer tail and emit immediately,
as before; standalone behavior is untouched. The release watch is
an observe-only `_input` (never consumes; idle unless armed),
matched to the same mouse button or touch index, with a 1.0s
timeout for a lost release and a Screen-visible guard so any
takeover since the press (title panel, production exit question)
cancels the opening. No emulation or project-setting changes, no
menu gating, no indefinite keyboard hold.

Regression (`tests/test_title_tap.gd`, rewritten routing): fresh
headless unit pins (press opens nothing, wrong release ignored,
own release opens exactly once, key immediate) plus the realistic
mixed windowed sequence — mouse tap, explicit Terms round-trip,
disabled-provider tap, Back, Settings and Shop round-trips, touch
tap on the natural prompt, Guest answers. Each opening gesture
must open ONLY the chooser (Terms/Privacy/Ready/Busy/loader shut,
provider calls zero, exactly one emit); Guest beginning proves no
modal intercepted its click.

Evidence: headless 30 passed (pins + unit), routing skipped;
forced-routing validation (temporary, reverted) 84 passed;
click-through negative (deferral disabled) 10 failed incl.
`route/touch: no Terms sheet` and `Guest answers`, then
byte-restored (title sha256 `a24a16c9…9653b9f`); STOP negative 2
pin fails, byte-restored (`88467285…b894d63c`); state 10231,
transition 34, production-host 495 still pass; hygiene ok;
store-screenshots fails as expected, no recapture.
`gate_provider_buttons.gd` untouched. Windowed proof and pixels
stay with the director.

## Render commands (windowed, director's display)

- Actual unconfigured production title:
  `godot --path apps/game res://tools/shot_gate_entry.tscn -- prod=1 locale=ko shot=/tmp/prod_title.png`
- Actual unconfigured selection after tap:
  `... -- prod=1 state=selection locale=ko shot=/tmp/prod_selection.png`
- In-app Terms sheet: `... -- prod=1 state=terms locale=ko shot=/tmp/prod_terms.png`
- Capable provider fixture (prints FIXTURE, stub host, never truth):
  `... -- prod=1 capable=1 state=selection locale=en shot=/tmp/prod_capable_fixture.png`
