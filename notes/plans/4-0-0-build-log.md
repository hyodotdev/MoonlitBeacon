# 4.0.0 build log (foundation round)

## Round 3: mixed receipts, exact integers, clean exit (brief 049)

Author-only follow-up. The director reproduced that the 381-case journey
scene printed a `SCRIPT ERROR` (`int == String` in the ledger eviction)
plus one leaked ObjectDB instance, that `MAX_SAFE_INT` allowed 2^53 with
ints compared through float (9007199254740993 rounded into the bound),
and that journey ids had no upper bound. All fixed below; no
player-visible change, so `game.md` is untouched, and the blocked-checkpoint
receipt stays 0 → 15 → 15.

### Vault (`scripts/gameplay/vault.gd`)

- Receipt ids compare through `_same_receipt_id` (equal only within one
  type) in find, upsert and both eviction passes: GDScript errors on
  `7 == "r1"`, so the mixed int/string ledger can no longer error.
- `_normalize_journey_id` bounds integral floats below 2^53 and maps
  anything unusable (containers, unsafe strings, `""`, non-integral or
  out-of-range floats, bools) to null, which settles `RETIRED`: never
  issued, never mints. Loaded ids are likewise capped at 2^53 − 1.
- `JOURNEY_TARGET_CAP` is 2^53 − 1, the largest integer JSON carries
  exactly. The arena already treats `RETIRED` as pay-0 (`maxi` echo, no
  pending), so no arena change was needed.

### Journey (`scripts/gameplay/journey.gd`)

- `MAX_SAFE_INT` is the int 2^53 − 1; new `JSON_INT_LIMIT` is the float
  2^53, the exclusive envelope for parsed numbers.
- `_is_int_in`/`_is_number_in` take int bounds and compare in the value's
  own type: ints exactly as ints (never through float), floats strictly
  inside ±2^53 and in range. A parsed float at 2^53 is refused — it may be
  a rounded stranger, and parsing cannot recover precision already lost.
- `_is_journey_id` caps int sequences at 2^53 − 1. Two call sites move to
  int bounds (`survived`, gate axes); fractional in-range values still
  validate.

### Tests (`tests/test_journey.gd`, 428 cases)

- `_test_safe_integer_boundaries`: in-memory ints (2^53 − 1 ok; 2^53 and
  2^53 + 1 refused), in-memory floats, wide journey ids, ±run-seed bounds,
  fractional `survived`, and the same edges through real files on disk.
- `_test_mixed_eviction_and_garbage_ids`: sixteen string receipts plus one
  int (exercises the second eviction pass across types), then seven junk
  ids that must all retire without minting or growing the ledger.
- `_test_fresh_confirm_required` now unhooks the title's scene swap, lets
  each pressed title's flare land, and drains each threaded arena load
  before the next title issues its own: a completed-but-unclaimed load
  left for the next tap to overwrite leaked its result at exit (found by
  bisecting the suite; stubbing the request removed the leak, a bare
  request plus claim is clean, and skipping one drain brings it back).
- Hardening note: no in-engine hook can fail a suite on engine errors, but
  the sanctioned runner already does — `run_regression_tests.mjs` fails
  any suite whose output contains `ERROR:` (including `SCRIPT ERROR:`)
  even on exit 0. Every verification run this round also greps for
  `SCRIPT ERROR`/`ERROR`/`leaked`.

### Round-3 tests and checks

- `test_journey.tscn`: 428/428 pass with no `SCRIPT ERROR`, `ERROR`, or
  leak warning (the pre-existing Camera2D physics-interpolation notice
  remains: every arena-instantiating suite prints it).
- Negative controls: plain `==` in eviction returns the script error;
  the prior float-bound integer logic fails 8 boundary cases; skipping
  the first load drain returns the leak. All reverted; green again.
- Full isolated suite (51/51), `check_scripts`, both `check:locale`
  halves, `check:hygiene`, `check:assets`, harness validate: see the
  implementer report for the actual runs. Pre-existing neighbor note:
  `test_title_transition` passes 30/30 but prints 33 leaked-instance
  warnings from titles freed mid-start — the same engine behavior, out of
  this round's scope (warnings, not errors, so the runner still passes
  it).

## Round 2: crash-safe settlement and strict persistence (brief 046)

Author-only follow-up. The director reproduced that a committed Vault payout
plus a failed checkpoint write granted the same progress twice (bank 0 → 15
→ 30), that `schema_version=1.5` validated, that reads were unbounded, that
replace could delete the sole good save, and that cycle 1000 could not
validate. All fixed below; the round-1 record underneath is otherwise
unchanged (no player-visible change, so `game.md` is untouched).

### Vault receipt ledger (`scripts/gameplay/vault.gd`)

- Earned journey shards now settle as idempotent receipts in the Vault
  itself: `begin_journey()` issues a durable sequence id per fresh journey
  (random `"r..."` fallback when its save fails, never a reused sequence),
  and `settle_journey_receipt(journey, checkpoint, target)` grants
  `target − settled base` exactly once per `(journey, checkpoint)`.
- Redelivery of the same receipt pays 0 — unless the live score advanced
  past the sealed one, in which case only the new delta pays, immediately,
  so value is never stranded behind a crash. An older checkpoint always
  pays 0 even revalued upward: superseded value must not re-mint.
- The ledger keeps `[id, checkpoint, target]` triples, bounded at 16
  journeys (lowest sequence evicted first). Evicted or never-issued
  sequences read `RETIRED` and pay 0, so bounding cannot turn a forgotten
  receipt into fresh money. `DUPLICATE`/`RETIRED` save nothing (pure
  reads); `SAVE_FAILED` rolls balance and ledger back for a full retry.
- New Vault fields are optional in every schema (no version bump): old
  saves load with an empty ledger, and 3.0.0 code ignores the new keys.
  Legacy `settle_run_score` and the paid ledgers are untouched; only armed
  journey runs take the receipt path.

### Atomic journey writes (`scripts/gameplay/journey.gd`)

- Installs stage verified bytes in a temp file and rename them in; the
  main save is never deleted. Backup refresh (same atomic install) runs
  first and aborts the write on failure, like the Vault. Direct-replace
  failure falls back to rotating the main aside, installing, and
  reinstalling the aside copy on failure — backup stays behind the
  restored main.
- Reads are length-gated before a byte is kept (`_read_bounded`, one
  bounded read); oversized files refuse before allocation/parse, and an
  oversized main still falls back to a valid backup.
- Schema is strictly an integer with exactly the supported value: 1.5,
  `"1"` and `true` read unreadable; only integral newer versions ask for a
  newer game. Journey ids accept Vault sequences (int or integral float)
  and legacy/fallback strings.
- `MAX_CYCLE` is 99999 (centuries of gates at any human pace; scores stay
  in 64-bit/JSON-safe range). Authored content still ends at 12 with the
  endless episode after; no score/telemetry cap stops progression.
- Test-only `InstallFault` seam (`SKIP_DIRECT`, `FAIL_TEMP_INSTALL`,
  `FAIL_ALL`, always `NONE` in play) plus real directory-occupation
  faults cover every install boundary.

### Arena receipt flow (`scripts/gameplay/arena.gd`)

- Seals commit the receipt before writing the checkpoint; a failed receipt
  seals the checkpoint unsettled (old echo) and stashes it pending, and
  the next seal's cumulative target carries the value. Terminal settlement
  submits the sealed checkpoint's receipt. `_retry_pending_result_persistence`
  also retries receipt pending. Unarmed runs keep legacy settlement byte
  for byte.

### Round-2 tests and checks

- `test_journey.tscn` grows to 381 cases: blocked-checkpoint exact-once
  (the director's receipt, now 0 → 15 → 15), committed-payout crash with
  Vault reload, Vault-save-failure retry across restart, all four install
  faults, schema strictness, oversized refusal (incl. 10 MB), cycle-1500
  restore, and ledger retirement/eviction/duplicate/duplicate-after-reload
  plus issue fallback.
- Negative controls: full-target grants fail the delta assertions;
  `int()`-coerced schema fails the strictness assertions. Both reverted.
- Full isolated suite (51/51), `check_scripts`, both `check:locale`
  halves, `check:hygiene`, `check:assets`, harness validate: see the
  implementer report for the actual runs.

---

Author-only. The local journey and story foundation of the 4.0.0 release:
a journey that resumes through its last gate, death retry without farming,
a nonmodal opening, and a data-driven episode catalog. Account services
(Google/Apple/guest login) and identity-aware ranking follow separately and
are not in this round.

## What changed

### Journey persistence (`scripts/gameplay/journey.gd`, new)

- Versioned (`schema_version 1`) JSON checkpoint at `user://journey.json`,
  written temp → verify → atomic replace, with the previous valid save kept
  at `user://journey.json.bak`. A corrupt main falls back to the backup; a
  corrupt backup is ignored. A failed write keeps the previous playable save.
- Checkpoints are segment entries only: cycle, zone, route, run seed, hero,
  relic stacks, level curve, missile power, kills, score counters,
  settlement bookkeeping, gate direction. No projectiles, enemies or physics
  state. Written after gate travel, after the cycle continue/cashout choice,
  and once (without settling) at a fresh start. Backgrounding writes nothing:
  the file already holds the last known-valid checkpoint.
- Strict validation refuses the whole save on: future schema, oversize
  (>64 KiB), truncation, out-of-range numbers, hero paths outside
  `Vault.HEROES`, and relic paths outside `res://resources/relics/*.tres`
  (no `..`, must exist, must load as a `Relic`). Rooms and guardians are
  never stored — terrain ids re-derive them — so a hostile save has nothing
  to aim an arbitrary `load()` at. Refusal never touches the Vault ledger.
- Only a human run writes. The title arms writes (`begin_fresh` /
  `begin_resume`); tests, debug boards and capture harnesses never arm, and
  the arena neither writes nor restores while disarmed. Leaving for the
  title disarms; the file stays for Continue.

### Settlement rules (no farming)

- Gate and cycle checkpoints settle the score delta to the Vault before
  writing. Death settles the **checkpoint** score, never the defeated
  segment's live score, then rewrites the checkpoint's bookkeeping so a
  relaunch cannot grant it again. The run-start checkpoint settles nothing,
  so starting alone never pays.
- Records submit the checkpoint score on death: a repeat death reads
  `NOT_BEST`; only further progress saves anew. Cashout writes the next
  gate's checkpoint, settles once, and the result settles nothing twice.
- Gate retry is free and never spends a continue coin; paid continue
  (`continue_run`, revive in place) is untouched. Result Retry after a loss
  with a checkpoint means the saved gate (the button says
  `RESULT_GATE_RETRY`); after a cashout it means a fresh run, as before.
  Pause-menu and result-fresh restarts call `begin_fresh()`: an explicit
  restart is an explicit new journey.

### Restore (`arena.gd`, `beacon.gd`)

- Restore is segment rebuild through production methods: `_recompute()`
  resets growth to base+hero, saved stacks feed through `_on_relic_picked()`
  + `take_named()`, the deterministic world rebuilds from the saved seed
  (`_change_world`), completed beacons relight through the new
  `Beacon.restore_lit()` (no flare, no sfx, no `lit_changed`, so no rewards
  or guardians wake), and transient state (moonfire, combos, cooldowns,
  floor loot, skill instances) starts empty. Health restores full — the gate
  restores you — so a gate saved at one heart is not a death loop.
- A saved hero locked since (refund) falls back to the default hero rather
  than refusing the journey. `_ready` consumes the title action first so the
  room, art, boons and analytics all build from restored values; gate retry
  reuses the same rebuild in place.

### Title and result UI

- The title builds a Continue panel in code (scene file untouched): saved
  gate (`HUD_WAVE` + terrain + hero name), Continue primary, and New Journey
  behind an inline Erase/Keep confirmation that leaves the save untouched
  until Erase. Tapping anywhere else also continues. No valid checkpoint, no
  panel — the plain tap-to-start title. A prior save failure shows the
  `JOURNEY_SAVE_FAILED` line.
- Save failure is announced in the arena (`JOURNEY_SAVE_FAILED`) and never
  advertised as success; resume fallback announces `JOURNEY_RESUME_FAILED`.

### Opening and onboarding (`scripts/gameplay/onboarding.gd`, new)

- A fresh human journey opens nonmodal: the Act I card + Dialogue pause
  chain for cycle 1 is replaced by a voice-strip telling of the opening
  lines over live combat, plus the move/dash/beacon banners. The tree never
  pauses; the player moves while the first instruction shows. The full
  opening is recorded in the chronicle (`story_open`, `story_1`) for rereading.
- Learned tips persist in `user://onboarding.json`, separate from purchases
  and from the journey (a fresh start must not wipe what was learned):
  `opening/move/dash/beacon/auto/heart/core`. Resume and relaunch skip
  learned tips; tests and capture keep the old always-teach behavior and
  never write the record. Cycle 2+ story beats keep their intentional modal
  pauses; combat is never unpaused behind a modal choice.

### Story episode catalog (`scripts/gameplay/story_episodes.gd`, new)

- One data table: stable episode ids, act boundaries, cycle ranges, beat
  cycles. `Acts` lookups, `Chronicle.sections()` story entries and the
  arena's `_story_lines()` all resolve through it. Beats, ids, keys and the
  40-entry chronicle total are unchanged; cycle 11 stays a deliberate
  silence; cycle 13+ falls back to the endless episode (no dialogue, short
  strip asides, endless play continues).
- Content-extension example: `test_journey.gd` resolves a hypothetical
  `example_tide` episode (beats 13–14) through the same functions and proves
  the endless fallback survives it. It is data in that test only — no
  chapter ships. To add a real episode: append one `EPISODES` row, add the
  `STORY_CYCLE_<n>_A/B` rows in all five locales, extend the catalog test.

### Tests and harness

- `tests/test_journey.gd` (+`.tscn`, registered in `run_regression_tests.mjs`,
  263 cases): fork+reward round trip, cycle-25 restore, hostile-save refusal
  (corrupt/truncated/oversized/future-schema/invalid-path/out-of-range) with
  paid state untouched, backup recovery, failed-write survival, 3×
  death/retry + relaunched-death with zero shard/record duplication, result
  retry copy, title confirm flow (save untouched until Erase; Continue arms
  resume), unpaused-opening + movement + chronicle record + no-repeat on
  relaunch + no replay on cycle-1 resume, later-beat modality + cycle-11
  quiet, catalog consistency + extension example, unarmed silence, five-
  locale fit of the Continue panel and gate-retry button, relabel on locale switch, and all ten new
  keys in five locales.
- `tests/test_story_structure.gd` gains the Acts↔catalog pin only; its
  card-then-dialogue protection for cycles 3–4 is unchanged.
- `tools/shot_journey.tscn` (+`.gd`): foreground menu (fresh/resume/
  guidance/retry/late) for the director, plus headless `validate` (5/5).
  Windowed rendering was not possible in the implementer sandbox; validate
  ran headless instead.

## What bit us

- Assigning an untyped array to the typed `_route: Array[int]` fails at
  runtime and leaves the old value (the same trap `_prune_spirits` warns
  about). Both the restore and the test assign route elements in place now.
- `Beacon.reset()` emits `lit_changed(false)`, which uncounted the restored
  beacons through the arena handler. The restore resets with signals
  blocked, relights quietly, then re-asserts `_lit_count` from the snapshot.
- A missing `await` on one test call let the next case's `_fresh_paths()`
  disarm and wipe mid-case — the exact shape of bug the journey guards
  against in production. All coroutine test calls are awaited.
- `Time.get_unix_time_from_system()` returns a float; `%` needs the `int()`
  cast, which `check_scripts` caught.

## Measured checks

- `test_journey.tscn`: 263/263 pass (isolated runner).
- Neighbors, same tree: story_structure 709, result_route 76, ladder 103,
  terrain_integration 250, result_layout 135, title_transition 30,
  beacon_choice 199, run_choice_panel 331, place_memories 951,
  guardian_staging 18, vault 206, iap_store 852, missile_progression 1590,
  expedition 72294 — all pass.
- `check_scripts` (isolated): 126 scripts compile. `check_locale`: node
  half ok (567 translations, 490 keys in use), isolated Godot half exit 0;
  the plain Godot half crashes in the implementer sandbox (documented
  limitation). `shot_journey validate`: 5/5.
- Negative controls: forcing `Journey.validate` to refuse fails the
  round trip; forcing live-score death settlement mints shards across the
  three retries (84 → 89 → 92 banked) and fails the no-farming case. Both
  reverted; the suite is green again.
- Full `pnpm test:game`, `pnpm check:hygiene`, `pnpm check:assets`,
  `pnpm docs:build`, `pnpm check:store-screenshots` (expected red: all of
  `apps/game` is hashed and the game changed; no recapture): see the
  implementer report for the actual runs.

## Remaining account work (not this round)

- Google/Apple/guest login UI and flows: no login buttons were added and no
  network/backend rules changed, per the brief. Guest unique IDs (before
  play) belong with that round.
- Identity-aware ranking / hall of fame over the journey: records still
  submit the local checkpoint score; no cloud or global claims were added.
- Version lock: still 3.0.0 everywhere. Lock 4.0.0 and platform build
  numbers only after the complete feature (accounts + ranking) is ready.
- The foreground harness states still want eyes on a real display
  (implementer sandbox cannot render windowed harnesses).

## Round 5: one Google/Apple account on either mobile OS (brief 058)

Author-only follow-up. Native identity previously signed Play Games v2
only on Android and Apple only on iOS. Now `google` is the shared
Firebase `google.com` identity on both OSes (Android: Credential Manager
+ Google ID; iOS: GoogleSignIn SDK + callback URL scheme), `apple` is
the shared `apple.com` identity on both (iOS native sheet kept; Android
gains the Firebase browser OAuth flow), and `play_games` stays the
optional Android-only gaming profile (`playgames.google.com`), never
merged with `google.com`. Providers gate independently at preflight,
capability, and call time; a link keeps the Firebase UID; conflicts
name the attempted provider and touch neither account.

### GDScript (`moonlit_identity.gd`, adapters, `player_account.gd`)

- Capabilities list exactly the ready providers: Firebase for the
  platform keeps the bridge usable (`ok`), and each missing provider key
  removes only its provider. Full readiness is an empty `missing` list.
  Per-call gates check only the called provider's keys.
- New staged keys: `[google] ios_client_id`, `[apple] android_enabled`
  (server-setup acknowledgement; the flag normalizes to `true`/`""` at
  staging). Android Google injects the web client id, iOS Google the iOS
  client id; platforms never cross-send.
- `NativeIdentityAdapter.refresh_native_session()` forwards the bridge's
  real `get_session` through the normal outcome folding (sync applies at
  once, pending settles on the signal); `get_session()` stays a pure
  memory snapshot. Base and fake adapters answer the snapshot;
  `PlayerAccount.refresh_session` prefers the method when present (the
  one permitted host touch). The wrapper's `get_session` now passes a
  `pending` receipt through instead of answering a local guest, so
  asynchronous session reads hydrate instead of being dropped.
- The iOS export manifest derives the callback scheme (reversed client
  id), emits the `CFBundleURLTypes` plist fragment, and routes it
  through the probed plist hook (modern first, legacy fallback, warning
  when neither exists). The privacy set is eight bundles.

### Natives (Kotlin plugin, iOS GDExtension)

- Android Google: `GetGoogleIdOption` (no authorized-accounts filter, no
  auto-select) → `GoogleIdTokenCredential` → `GoogleAuthProvider`, with
  `CancellationSignal` pre-mutation cancel and `no_google_account` for
  bare devices. Sign-in and link share one credential exchange.
- Android Apple: `OAuthProvider("apple.com")` browser flow with
  `pendingAuthResult` reattach, draining cancel once the intent fires,
  link and reauthenticate-for-delete variants. No custom scopes.
- iOS Google: `GIDConfiguration` + `signInWithPresentingViewController`
  → `FIRGoogleAuthProvider`, dismissal mapped to `cancelled`, sign-out
  also clears the Google SDK state. The openURL forwarder offers each URL
  to `handleURL:` first and chains anything else to the previous
  delegate implementation (no concrete delegate class assumed; pending
  install retries on first use).
- Both natives map session/conflict providers from linked provider
  data, never constants; unknown provider names answer
  `unknown_provider`.

### Build (`player-identity-build.mjs`, templates, preflight)

- Pins: credentials 1.3.0, credentials-play-services-auth 1.3.0,
  googleid 1.1.1 (Firebase docs example), GoogleSignIn 7.1.0
  (contemporary with FirebaseAuth 11.0.0). All other pins unchanged.
- New env: `MOONLIT_GOOGLE_IOS_CLIENT_ID`,
  `MOONLIT_APPLE_ANDROID_ENABLED`. Preflight prints per-provider
  READY/NOT READY lines; `--install` stages partial configs with
  warnings while `--check` keeps the strict gate. Discovery, link tree,
  staging, verification, and prereqs all require GoogleSignIn next to
  FirebaseAuth.

### Tests and checks

- `tests/test_player_identity.gd` (295 cases, registered in
  `run_regression_tests.mjs` this round): per-provider capability
  matrix, client-id routing per platform, link UID stability, google
  conflict, sync/async/signed-out refresh hydration with a no-sign-in
  call proof, host refresh preference, google drain, scheme/plist/hook
  composition, eight-bundle manifest.
- `scripts/lib/player-identity-build.test.mjs` (72 cases): pin drift,
  flag semantics, provider independence, config normalization,
  GoogleSignIn discovery/staging/verify, Kotlin + ObjC source audits
  (documented SDK calls present, personal-scope/profile reads absent,
  forwarder chain intact).
- Fail-checks run and reverted: adapter refresh without forwarding
  (8 hydration cases fail), GoogleSignIn pin drift (3 cases fail),
  unreversed scheme (2 cases fail).
- Full `pnpm test:game`, `pnpm game:check`, `pnpm check:hygiene`,
  `pnpm check:locale`, `pnpm check:store-screenshots` (expected red:
  all of `apps/game` is hashed and the game changed; no recapture):
  see the implementer report for the actual runs.

### What bit us

- The wrapper's `get_session` answered a local guest for any non-ok
  receipt, which swallowed asynchronous session reads: the adapter saw
  a sync answer and dropped the later terminal as unknown. Pending now
  passes through like any other call.
- `dispatch_once` would have consumed the URL-forwarder install even
  when the delegate did not exist yet; a synchronized flag keeps the
  install pending until a later call retries it.
- `Activity.mainExecutor` needs API 28 while the plugin supports API
  23; the Credential Manager callback runs on
  `ContextCompat.getMainExecutor` instead.
- The two extra privacy bundles are expected, not measured: the first
  `--fetch-deps` with the GoogleSignIn pin confirms or corrects them
  loudly. No provider/device authentication is claimed from fixtures;
  device login stays a separate evidence item after the server setup.

## Round 6: finish shared login against the real native SDKs (brief 071)

Correction round against the director's real builds. The Android
compiler's overload list proved Credential Manager 1.3.0 is
suspend-only (no callback form exists), `OutcomeReceiver` unresolvable,
and reauthenticate returning `Task<AuthResult>`; the real Pods products
proved the bundle guesses wrong (measured: six Firebase plus
`AppAuthCore_Privacy`, `GTMAppAuth_Privacy`, `GoogleSignIn` with its
button assets); real arm64 Clang flagged the forwarder's `void *` cast.

### Native fixes

- Android Google runs the suspend `getCredential(context, request)` in
  a main-dispatcher coroutine (`kotlinx-coroutines-android:1.10.1`,
  pinned in `.gdap`/template/pins); one child job per request carries
  pre-mutation cancel, dismissal and bare-device errors map as before,
  and the mutation/draining contract is unchanged. Minimum API
  unchanged. Reauth attaches one `Task<AuthResult>` helper for both
  the resumed and fresh tasks.
- iOS blesses the nine measured bundles (identical in both real config
  roots; whole bundles still stage byte for byte) and keeps the typed
  `MoonlitOpenURLIMP` cast the syntax error demanded, still chaining
  to the previous delegate implementation.
- iOS sign-out failure now answers `sign_out_failed` (retryable)
  carrying the re-read session and preserves Google state, instead of
  declaring a guest success. No-config no-op and operation lock kept.

### Scope and honesty corrections

- `PlayerAccount` and `run_regression_tests.mjs` restored byte for
  byte to this copy's baseline; hydration is proven at the adapter
  contract level only. The host-wiring test case is removed.
- iOS Apple gates on `MOONLIT_APPLE_IOS_ENABLED` /
  `[apple] ios_enabled`, analogous to Android Apple; Google/guest run
  without it. Docs record the exact final-tooling handoff
  (`entitlements/additional`, `com.apple.developer.applesignin`
  `[Default]`, real signed profile) without touching locked presets.
- The engine runs the queued init callback from the
  `OS_AppleEmbedded` constructor (not `::initialize`): corrected in
  the manifest doc, the emitted snippet comment, and the setup notes.
- Scope wording corrected everywhere touched: the Apple sheet
  requests no personal scopes; Google's SDKs authenticate under their
  own default account scopes whether or not game code reads profiles.

### Tests and checks

- `tests/test_player_identity.gd` (305 cases, run directly): iOS flag
  gates, sign-out failure preservation, nine-bundle manifest.
- `scripts/lib/player-identity-build.test.mjs` (74 cases): coroutines
  pin, iOS flag semantics/independence, nine-bundle fixtures, suspend
  API + reauth type + cast + sign-out source audits.
- Fail-checks run and reverted; full `pnpm test:game` equivalent loop,
  `check_scripts`, `check:locale`, `check:hygiene` (pre-existing red),
  `check:store-screenshots` (expected red): see the implementer
  report for the actual runs.

## Voice strip portrait bounds (brief 094)

The painted 72x72 hero head crop kept its native minimum in the 24px
portrait cell (`TextureRect` defaults to `EXPAND_KEEP_SIZE`), so Box
grew to 78px tall and the strip hung out of the viewport. Two lines in
`scripts/ui/voice_panel.gd`: `EXPAND_IGNORE_SIZE` so the cell sets the
size, and vertical `SIZE_SHRINK_CENTER` so the 24x24 portrait centers
in its row instead of stretching with the 13px line height. No styling,
font, hold/fade, input, or pause change; Box material untouched for the
parallel styling run.

What bit us: with only the expand fix the portrait allocated 24x28 —
the row is 28px tall (Galmuri 13px line metrics) and `HBoxContainer`
stretches children to it. The shrink-center flag holds exactly 24x24.

`tests/test_place_memories.gd` gains 575 cases: real `VoicePanel.say`
with all six Hero resources at 808x360, 840x360 and 808x606, long ko/ja
lines (`VOICE_CYCLE_6`, `VOICE_MEET_STALKER_1`), and a live-arena
Warden spot check — box/portrait/text inside the viewport, strip
height, font, show/swap/clear, input-ignore, and unpaused. Before the
fix 146 fail with the reported numbers (Box 78, portrait 72,
outside); after, the suite passes 1526. Negative control reverted and
re-failed 146, then restored green.

## Native identity registration in the ordinary game/export (brief 101)

Two lines in `project.godot`: the `MoonlitIdentity` bridge autoload
immediately before `ProductionHost`, and the moonlit-identity editor
plugin enabled after godot-iap. The editor plugin's autoload lifecycle
is idempotent now — `_enter_tree` adds only when the setting is absent
and `_exit_tree` removes only what that enable added, so disabling the
addon or closing the editor can never strip the explicit runtime
registration. Export hooks untouched, including the 092 config
`add_file`; no preset, SDK, provider, or UI change.

What bit us: `EditorExportPlugin` cannot instantiate outside the
editor, so the new `tests/test_identity_registration.tscn` proves the
export class from its script (base type plus hook method list) instead
of an instance — 61 cases on the real boot: bridge before host, real
main booting the real host, adapter holding the exact live bridge with
a live stale-signal drop, removal/restore negative control, durable
local guest on desktop, and a live unpaused Arena. A control run with
the old unconditional remove showed headless `--import` never persists
`project.godot` either way; the fix guards the interactive disable
path. Brief 105 then added the single authorized preset line
(`plugins/MoonlitIdentity=true` in the iOS options, directly below the
purchase plugin line): the entitlement gate's flag requirement is met,
genuinely incomplete Apple config still refuses per the extended Node
suite, and no missing preset remains. Full note in
`notes/release/player-identity-registration-101.md`.

## Android JNI identity dispatch and honest settlement (brief 120)

Three narrow fixes. `addons/moonlit-identity/moonlit_identity.gd` gained
`_native_has_method`: when the actual native object exposes
`has_java_method` (Android `JNISingleton`, whose Java registry
`has_method` never sees), that verdict is authoritative; iOS
GDExtension and ordinary fakes keep `has_method`. Both `_native_call`
and `_native_reports_draining` use it, so dispatch and
cancellation/draining agree and absent methods are never blindly
invoked. Nearby guards (`native_identity_adapter` bridge checks,
`player_account` adapter check, host adapter/sender/clock checks) all
target GDScript objects, not JNI, and stay on `has_method`.
`scripts/net/player_account.gd` `_fold_sync_receipt` folds synchronous
terminal `unsupported` / `not_configured` into the existing
`account_error` path, so a busy entry unblocks without inventing a
login; IDs, bindings, and locks untouched. `scripts/ui/production_entry.gd`
`_linkable_providers` keeps links for an anonymous Firebase guest
(same UID and public ID on link) while authenticated sessions still
hide every link; the panel renders what it is given, so no panel
change was needed.

What bit us: the new refusal test adopts a UID binding, and every fake
guest shares one anonymous UID, so the second refusal iteration met the
first iteration's leftover binding as a conflict. The suite's wipe
helper only removed the identity file; the test now wipes the default
bindings file alongside it.

`tests/test_player_identity.gd` gains a `JavaOracleBridge` stand-in
(GDScript methods exposed, Java verdict scripted) plus dispatch,
cancel, and sync-refusal cases; `tests/test_production_host.gd` gains
refusal-through-entry and anonymous-vs-authenticated link cases. No
runner change: both suites were already registered. Negative controls:
old `has_method` guard fails 10 identity cases, ignored refusal fails
identity (1 case then aborts on the empty error index, exit 1) and
host (error never shows, busy sticks, no production error), old link
gate fails the anonymous-links case (0 vs 2). Green after restore:
identity 359, host 537, cloud_account 37, registration 61, title_tap
30, gate_entry_state 9408; `check_scripts` 163 scripts compile,
`check:hygiene` ok, `check:store-screenshots` fails as expected
(touched `apps/game/`, no recapture). Full `test:game` cannot run in
this sandbox (reimport needs the real HOME/editor settings); the
affected suites ran through the isolated runner instead.

## Resolve cloud save before entry (brief 129)

A returning cloud player on an empty device slot now sees the saved
segment and Continue before any fresh journey is offered. The race was
`_adopted_canonical` firing `restore_cloud.call_deferred()`: between
coordinator-ready and the deferred pull, `plan_entry(true, false)`
returned ok and armed FRESH over a cloud save nobody had read yet.

`scripts/net/production_host.gd` now owns the initial empty-slot check
synchronously inside `_adopted_canonical`, before any deferred work or
ready emission. A ticket names the exact account and generation;
`plan_entry` refuses with `cloud_restore_pending` while the fetch runs
and `cloud_restore_unresolved` after a failure nobody has answered.
Installed bytes and authoritative not-found both resolve cleanly (the
former shows Continue, the latter unlocks fresh with no error); a
conflict resolves to the unchanged explicit conflict choice. Every
other failure keeps blocking and emits `save_check_failed` carrying
the real reason, with `retry_cloud_restore()` (same account only,
refused while a fetch is outstanding, never touches authentication)
and `accept_offline_entry()` (explicit fresh start under the same UID
and slot, reversible by a later retry) as the two honest exits. One
fetch claim per ticket means retries stack no parallel pulls; a
15-second elapsed watchdog (short injected `restore_timeout_seconds`
in tests) fails hung pulls as `restore_timeout` while the orphan stays
claimed, and a late same-account install still surfaces truth while a
late result for a moved account changes nothing. Sign-out, switch,
deletion rotation, and shutdown retire the ticket; duplicate ready
callbacks for a live or resolved check start nothing. Local guests
never check, and a valid local checkpoint skips the check entirely, so
known resumes stay responsive offline.

`scripts/ui/gate_entry.gd` gained two save faces on the existing
cards, no new controls: `show_save_check` (busy with the checking
line) and `show_save_error` (error title plus the guest escape
relabeled as the offline start). `scripts/ui/production_entry.gd`
routes them: checking/failed own the card until the terminal result,
retry re-reads the cloud, the relabeled door records the offline
decision (the Ready card then says the save is unchecked instead of
claiming none exists), cancel parks to the title without issuing any
login cancel, and `save_check_failed` needs no error hold because the
host flag drives every repaint. Five `gate.save.*` keys in
`localization/gate_entry.csv` carry the copy in all five locales.

What bit us: the host retires the injected coordinator on first
configure (`_configure_cloud_async` always retires, then configures
the fresh one), so the parts-dict coordinator is already freed by the
time any duplicate ready could arrive. The first duplicate test held
it and segfaulted the engine on a post-free snapshot call — no
GDScript error, just signal 11 with a misleading backtrace. Duplicates
now re-emit through the live `host.get("_coordinator")`, matching
`_await_ready`, and a helper documents the trap. The same trap had
silently neutered a `set_auto_flush(false)` on the injected copy; the
local-resume case now proves the check never ran (no flags, no
`save_check_failed`) while the upload's own guard read accounts for
the single pull.

`tests/test_production_host.gd` gains eleven cases over delayed
URL-routed and hung senders (completion order can never steal a
scripted reply): immediate tap blocked, checking face plus
cancel-parks, remote Continue fidelity (cycle, zone, hero,
checkpoint), not-found unlock, offline failure with card retry and a
refused parallel retry, the explicit reversible offline decision,
sign-out and switch retiring a late valid remote, duplicate ready in
all three states, local resume plus offline guest, and the bounded
timeout with orphan upgrade. Four older fixtures queue an
authoritative 404 after their profile so their empty-slot sign-ins
resolve the way the new contract requires; no assertions weakened.
Negative controls: removing the `plan_entry` guard fails 10 cases
(fresh arms mid-check), and the full old deferred-only shape fails 44
cases across eight of the eleven (the other three pin preserved
behavior: not-found unlock, stale partitioning, local resume). Green
after restore: host 729, gate_entry_state 10315,
gate_entry_exported_locales 1999, gate_entry_layout 85722,
identity_registration 61, title_tap 30, forecourt_party 13165;
`check_scripts` 164 scripts compile, `check:hygiene` ok, both locale
halves ok, isolated quit-smoke ok, `check:store-screenshots` fails as
expected (touched `apps/game/`, no recapture). Full `test:game`
cannot run in this sandbox (reimport trips on the blocked editor
settings); the affected suites ran through the isolated runner
instead.

## Own restore completion and timeout exit (brief 130)

Two measured defects in the round-1 guard, both fixed. First, fetch
identity was reused: `_retire_restore` reset the claim counter, so a
newer account's claim could collide with a retired completion that
then freed it, sticking the new check on Busy forever. The host now
mirrors the coordinator's flush ticket — a monotonic
`_restore_fetch_seq` that is never reset plus an open slot that is —
and late adoption verifies the owning ticket and generation before
ignoring the reply unconditionally. Same UID and public ID still
carries a newer generation, so a relogin re-reads for itself. Second,
a timed-out attempt kept its claim, so the failure screen's retry and
offline doors were refused until the orphan landed. Timeout now
retires the attempt first through a narrow coordinator epoch:
`cancel_pending_restore` spends `_restore_epoch` without reading,
every `restore_from_cloud` claims the next value at start, and a
stale read reports cancelled without installing, flooring, or opening
conflicts. Only then does the host claim release and the honest
`restore_timeout` failure land, so retry and offline act while the
orphan is still held and the late valid reply changes nothing — no
install into a started journey, no unlock or re-fail of a newer
check. Flushes, profile work, rank, settlement, and the explicit
conflict choice are untouched; the conflict remote-choice path takes
no epoch gate. The failure card body no longer repeats the headline:
the headline names the failure (offline names itself) and one new
`gate.save.offline_body` line in all five locales explains the
offline door — this device's saved journey, or a fresh start when it
has none. Entry retry while already checking stays on the checking
face instead of falling through toward auth.

What bit us: the sequence-reuse defect cannot be reached end to end
through switch or sign-out — coordinator retirement already shields
the host there, which is why the first held-switch negative passed
vacuously. The true regression is a white-box same-coordinator test
(retire, reclaim, land the retired valid reply) in the director's
probe shape; resetting the counter fails it exactly. Also, the R1
timeout expectations encoded the defective behavior (orphan-held
refusal, orphan upgrade) and were replaced, not weakened: same
no-late-overwrite intent, retired/retryable shape.

`tests/test_production_host.gd` gains claim-identity, held-switch,
relogin, timeout-offline, and timeout-retry cases over a per-call
hung sender (each held pull is released by its own call number, so
old-first/new-second orderings are airtight), plus repeated-tap
coverage at the host and on the card.
`tests/test_cloud_coordinator.gd` gains cancel and supersede cases
over the gated sender. Negative controls: counter reset fails the
claim case (2); cancel no-op fails the coordinator cancel case (6)
and timeout-offline install (1); unclaimed reads fail supersede (3)
and the claim case (2). The entry pending-ignore has no observable
negative — the host's already-linked guard neutralizes the
fallthrough first — so it stands as defense in depth with end-state
pins (checking held, one pull, no auth calls). Green after restore:
host 798, coordinator 1104, gate_entry_state 10315,
gate_entry_exported_locales 2019, gate_entry_layout 85722,
identity_registration 61, title_tap 30, forecourt_party 13172;
`check_scripts` 164 compile, `check:hygiene` ok, both locale halves
ok, quit-smoke ok, `check:store-screenshots` fails as expected (no
recapture). Full `test:game` still sandbox-blocked at reimport.
