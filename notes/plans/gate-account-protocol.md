# Gate account protocol (Brief 201 service contract for the lodge)

Author-only implementation record. Brief 202 (the lodge room UI) reads this
note to call the name service; the lodge builds no new cloud contract.

## What exists

Each signed-in account owns at most one adventurer name, stored as an
immutable pair bound to the canonical UID/public-ID pair:

- Private `mb_adventurers_v1/{public_id}`: `{uid, public_id, display, key,
  intro_complete}`. Owner-read, owner-write-once, owner-delete.
- Public collision index `mb_names_v1/{name_key}`: `{public_id, display}`.
  Public-readable, owner-write-once, owner-delete. No UID, no credentials,
  no private metadata: the handle and the already-public ID are enough to
  establish a collision.
- Hall best rows `mb_hall_v1/{public_id}` gained an optional `display`
  field. Old rows without it still render; rules require any `display`
  written to equal the writer's claimed name.

Rules live in `firestore.cloud.addition.rules`; enforcement tests in
`tests/cloud-rules/cloud-rules.test.mjs` (the director runs the emulator).

## Names

`CloudSchema.normalize_adventurer_name(raw)` returns
`{ok, display, key}` or `{ok: false, error: "invalid-name"}`:

- Trim boundary whitespace, then 2-12 visible characters.
- Allow-list: Latin letters, digits, underscore, precomposed Hangul
  syllables (U+AC00-U+D7A3), hiragana, katakana plus the prolonged-sound
  mark U+30FC (as in `ルミー`), CJK ideographs (U+4E00-U+9FFF), and single
  interior ASCII spaces.
- Rejected: path separators, controls, invisible/combining characters,
  Jamo, astral emoji, doubled or boundary spaces, anything else.
- The key is `display.to_lower()`: mixed-case Latin variants collide,
  CJK passes through byte identical. Rules mirror the list exactly.

Renaming is out of scope: claims are immutable. The handle is a public
game name, not a real name.

## Lodge call contract (Brief 202 reads this)

All calls go through the production host
(`apps/game/scripts/net/production_host.gd`). Generation-bound: stale
callbacks after account switch, token refresh, or cancellation report
instead of applying to the wrong account.

- `verified_display_name() -> String`
  Synchronous cache read of the live account's verified handle, or `""`
  when it claimed nothing. The lodge shows the naming step when this is
  empty after a load attempt; otherwise it skips naming. No request.
- `claim_adventurer_name(raw_display: String) -> Dictionary`
  Online-only. A local-only guest gets
  `{status: failure, code: local-guest}`: the lodge must not offer naming
  without a cloud session. On success the result carries
  `{status: ok, display, key, intro_complete: false, cached, backfilled,
  backfill_code}`; `cached`/`backfilled` name the legs that did not land so
  the lodge can retry exactly that leg (`load_adventurer_name` for the
  cache, `backfill_hall_name` for the row). A Firebase-registered anonymous
  guest claims like any signed-in account and keeps the name after linking
  to Google or Apple. Error legs: `invalid-name`, `name-taken`
  (`status: conflict`), transport offline/auth failures.
- `load_adventurer_name() -> Dictionary`
  Reload the live account's claimed name and refresh its offline cache.
  Restart-after-claim recovery calls this before deciding the account is
  unnamed. `{status: ok, display, key, intro_complete, cached}`.
- `mark_intro_complete() -> Dictionary`
  Flip the tutorial bit false to true when the lodge tutorial finishes.
  Idempotent: double taps and uncertain acknowledgements converge.
  `{status: ok, display, key, intro_complete: true, cached}`.
- `backfill_hall_name() -> Dictionary`
  Attach the verified handle to the account's existing best row at the
  row's own saved score, hero, and cycles (never the currently selected
  hero, never a zero-score row, never a downgrade). Writes nothing when no
  best row exists yet.

Result statuses elsewhere: `unregistered`/`account-not-ready`,
`cancelled` (stale generation, `account-retired` when the initiating
account moved on, `host-closed` on shutdown), `failure` with a code, and
`retryable` flags. The host pins every name call to the initiating
account before the token wait: a switch, deletion, or shutdown parked
across the wait cancels instead of dispatching onto the next account,
and a failed token fails the call without sending any mutation. Only
the initial claim needs online confirmation; verified returning accounts
use the cached handle offline.

Every successful claim carries the real `intro_complete` bit, including
restores of a name claimed earlier and recoveries after an uncertain
acknowledgement. The durable cache bit is monotone per name: a late
incomplete same-name response never clears a stored completion, while a
different account or key still starts incomplete.

Reads: the owner proven by the canonical pair gets an authoritative
missing-row read (claim naming starts there); other owners, unregistered
callers, and lists stay denied. A `permission-denied` is never a taken
name: taken arrives only as a commit conflict followed by a missing
own-row recheck, so missing backend rules surface as configuration
failures instead. Deletion binds both name halves to the full account
deletion: no partial release lives under a living profile/reservation,
and missing rows still delete as no-ops.

## Local durability

`Vault` keeps a bounded (max 8, least-recently-touched eviction)
account-partitioned cache: display, key, intro bit per public ID. No
tokens, emails, or raw native identity profiles. Separate accounts never
share cache entries; cache validation rejects malformed rows on load.
Account deletion removes the verified cache row, then deletes the Hall
row, name, adventurer record, cloud save, reservation, and profile in one
verified commit before the sign-in itself is deleted, so a name is never
stranded or freed under a living score.

## Score routing

`Arena._on_result_record()` routes a verified named production player to
`LadderPanel.ask_named()` with the cached handle: read-only, no editable
name field, no legacy `GlobalLadder` upload. Unnamed and legacy fixture
players keep the old editable route unchanged.

The owned Hall panel renders the verified handle on each named row's
headline (`#rank · score · handle`), with the stable MB ID on its own
line; unnamed rows keep the honest rank-and-score headline. Best
completion pushes the refreshed standing to the Arena rank chip again.

## Preservation prerequisite (Brief 203/207 shape)

`Vault.prepare_receipt_move()` treats a canonical target with a pending
paid journal or an existing journey as occupied even when the source has
no receipt: it returns `kept`, keeps the source bytes, and the target
recovers its exact acknowledged seal with no second debit. The lodge must
not bypass this guard when adopting canonical slots at first login.

## Attendance (Brief 204: two coins per twelve hours)

One private account-owned row, `mb_attendance_v1/{public_id}`, holding
`{public_id, uid, install_id, last_claim_at, schema}` plus, after the
first advance, the carried `{prev_claim_at, prev_install_id}`. Only
`last_claim_at` is server-set (`request.time`); the client never writes a
timestamp or a count. First claim creates with `exists: false`; later
claims compare-and-swap on `updateTime` while carrying the overwritten
row's stamp and install byte for byte (the rules require exactly that
pair, and forbid it on create), so another install's advance never
erases this install's still-unapplied reward. A first read that finds
nothing returns authoritative not-found for the proved owner; 403 stays
an error and strangers stay denied. Concurrent claims for one account
converge on one receipt through the loser re-reading the winner's row.

Eligibility is a rolling 43200-second server cooldown from the last
acknowledged claim: the first eligible visit grants two, and days away
still grant two, never a stockpile. Remaining time derives from a server
`batchGet` read time or commit time only; device clock and time zone
cannot move it. Forward/backward clock changes are covered in the client
tests. A notification never grants coins by itself.

An eligible advance never commits before its owned rewards land: the
coordinator backfills the read row's current stamp when this install
received it, plus any carried previous stamp from this install, then
commits. A failed backfill stops before the commit (the row keeps the
receipt); a failed wallet write reports `local-grant-failed` with
`server_claimed` for retry, while an eviction-floor ambiguity reports
terminal `attendance-replay-ambiguous`. Backfilled calls set `backfilled`
plus `backfilled_receipt`; the entry receipt counts fresh plus
backfilled coins. The carried pair preserves exactly one generation: a
third install's advance drops the oldest carry. Purchased balances stay
local and outside this protocol.

Wallet application goes through `Vault.grant_attendance_coins(public_id,
claim_seconds, install_id, fresh_commit)` exactly once per claim,
idempotent under the stable receipt key
`attendance:{public_id}:{seconds}:{install_id}`. The key binds the
reward to its receiving install: another device cannot replay the same
grant into a second wallet, but may claim the next eligible period. No
token, email, or raw native profile is persisted. Replay state stays
bounded (newest 8 attendance keys, 8 owner watermarks, one global
eviction floor); purchased-coin keys are never evicted, and an untracked
owner at or below the floor fails closed as ambiguous unless the call
carries fresh-commit proof (a just-landed conditional commit, whose
twelve-hour rule makes same-second cross-owner ties genuine).
`Vault.attendance_receipt_applied(public_id, seconds, install)` reports
whether one receipt already landed.

Callable surface for the lodge and the reminder brief:

- `ProductionHost.request_attendance()` — one bounded nonblocking check
  for genuine account entry and explicit calls. Skips (never errors) for
  local guests, unready accounts, in-flight deletion or restore, and
  overlap. Shows the receipt only for coins newly granted by the call.
- `ProductionHost.claim_attendance()` — the direct generation-bound claim;
  same deletion/account guards as the name routes, including the pinned
  deletion generation across awaits.
- `ProductionHost.notify_foreground_return()` — one bounded re-check on
  window-focus return; wired to `focus_entered` on real displays only.
- `ProductionHost.attendance_view()` / `CloudCoordinator.attendance_snapshot()`
  — `{state, source, public_id, receipt, last_claim_utc,
  next_eligible_utc, remaining_seconds}`. `source` is `live` (server),
  `cache` (display/reminder only, never grants), or `none`. Reminder
  scheduling reads `next_eligible_utc` plus bounded `remaining_seconds`.
- Signal `ProductionHost.production_attendance(snapshot)` — emitted on
  every live publish and every offline/cache serve.
- `CloudAttendance.commit_advance(transport, uid, public_id, install,
  update_time, prev_claim_rfc, prev_install)` — the conditional advance
  commit after backfill; service `claim_attendance` returns `eligible`
  with the read row instead of committing it.
- Result statuses: `granted` (coins: 2, receipt, deadline),
  `already-claimed` (mine: top-up once or duplicate; foreign: none),
  `cooldown` (deadline, no coins), `offline`/`failure` (honest error,
  never coins, play continues). Any advance/hold result may add
  `backfilled` plus `backfilled_receipt` for recovered earned coins.

Entry wiring: the arena scene change flushes a gate-time receipt and
fires a deferred nonblocking claim; living runs are untouched and new
players finish naming first (no overlay while an IME field holds focus
or an NPC dialogue is open). The receipt string is `ATTENDANCE_RECEIPT`
in all five locales, shown only after the durable local grant.

Deletion removes the attendance row with the Hall row, name, adventurer
record, save, reservation, and profile in the one verified commit (seven
steps named, five unnamed, attendance after checkpoint), and clears the
local watermark and cached deadline; granted coins stay in the device
wallet ledger. Legacy unnamed and never-attended accounts delete
unchanged: missing rows are server no-ops. Firebase Auth deletion still
runs only after the data commit is acknowledged.

## Reminders (Brief 205: local attendance notices)

One controller, `scripts/gameplay/attendance_reminders.gd`
(`class_name AttendanceReminders`), owned by the production host so it
outlives scene changes. It reads the attendance view above as its
single authority (`next_eligible_utc` + bounded `remaining_seconds`;
`live` or `cache` may schedule, `none` never does) and drives the
reminder API on the MoonlitIdentity bridge. There is no second reward
timer, and a notification never grants coins.

- Intent lives in Settings: `reminders_enabled` (default off) with its
  own `user://attendance_reminders.disabled` fail-closed mark (same
  shape as analytics, separate file, never cross-read),
  `reminder_receipt_offered` (the first receipt offers once, never
  nags), display-cache `reminder_os_state`
  (`unknown/granted/denied/unsupported`), and the scheduled record
  (`reminder_sched_account/_eligible_utc/_locale` plus
  `reminder_sched_horizon_end`: last held fire, -1 for an unbounded
  repeating native, 0 for a legacy schedule).
- Every refresh re-checks the live native permission before skipping
  unchanged inputs, so an OS revocation on the same deadline surfaces
  as denied (intent and record kept, nothing scheduled) instead of
  hiding. Identical inputs then skip only while the recorded window
  holds (unbounded, or the refill margin ahead of now still inside
  the held end), so a title refresh never shifts the deadline or
  stacks requests. Only the already-eligible visit (`remaining == 0`)
  arms nothing, since the foreground claim owns the next deadline;
  any positive window, however short, schedules with its own first
  delay under twelve-hour repeats (brief 212: the old under-60 s
  shortcut stranded newly enabled installs).
- `refresh()` reconciles on every attendance snapshot, settings
  change, and account transition, with a reentrancy guard (the
  reconcile writes the OS cache, which emits back into refresh).
  Disable, sign-out, account switch, and deletion cancel the native
  delivery and clear the triple. One active account per install.
- `user_enable()` persists intent, then requests OS permission (async,
  generation-guarded); denial keeps the intent but schedules nothing
  and shows OS-denied. `user_toggle()` from off-plus-denied opens the
  OS notification settings instead of re-asking.
- Native API (both platforms, same receipt contract, no Firebase
  gating): `moonlitReminderStatus`, `moonlitReminderRequestPermission`,
  `moonlitReminderSchedule` (`eligible_utc_millis`, localized
  `title`/`body`, `locale`, `account`), `moonlitReminderCancel`,
  `moonlitReminderOpenSettings`, `moonlitReminderPending`,
  `moonlitReminderDebugSchedule` (QA, one 5–600 s one-shot).
- Android: one inexact `RTC_WAKEUP` twelve-hour alarm re-armed after
  boot; delivery re-checks opt-out, permission, channel, and
  foreground (fresh resume record or foreground rank; stale records
  expire in ten minutes). Effective status weighs the app-global
  switch, the 33+ runtime grant, and the channel together on every
  version (no blanket grant below 33); the runtime sheet shows only
  when the runtime permission is the missing piece. Diagnostics
  separate persisted schedule intent from token existence and never
  claim an OS-held alarm from a token; retiring cancels the tokens.
  iOS: a bounded horizon of 48 non-repeating slots at eligibility
  plus N * 43200 (24 days, under the 64-request OS budget), refilled
  from the first future slot on the same anchor with stable ordinal
  ids 0..47 whenever fewer than 8 future slots remain; elapsed slots
  skip, adequate identical refreshes skip, the held base/end persist,
  the receipt and pending diagnostics report `base_slot` and
  `horizon_end_unix`, and cancel removes the horizon plus legacy
  first/repeat/debug ids. iOS status reads the OS asynchronously and
  settles as a bounded outcome; a granted outcome runs the schedule
  tail once (which never re-queries status, so it cannot loop).
  Foreground presentation suppressed through a delegate installed
  only when the center has none. iOS scheduling metadata lives in
  app-only `NSUserDefaults` (`dev.moonlitbeacon.reminder.*`),
  declared by the app-owned
  `PrivacyInfo.xcprivacy` (CA92.1) staged into the app resources.
- Cold notification launch opens the ordinary title route (Android
  reports `launched_from_reminder` once); tapping never claims or
  spends. Desktop answers `unsupported` everywhere and stays playable.
- Director QA: `res://tools/reminder_review.tscn` (`mode=validate`
  headless, `mode=ui delay=60` on an isolated native account;
  background the app before the fire time). Lodge entry QA prints
  `GateLodge.name_form_keyboard_report()` (visibility, height, real
  field/action rects, never the typed name); the form lifts above a
  covering keyboard via `keyboard_shift_for()` and restores after.
- Late async verdicts (Brief 219): the user-intent and ownership
  gates live in the shared schedule tail, not only in the reconcile
  head — a pending native status that completes granted after off (or
  after the scope drops to none with stale fields retained) still
  updates the truthful OS cache but schedules and records nothing. A
  later genuine enabled known view schedules once.
- Refill boundaries (Brief 218): the iOS 48-slot planner is integer
  milliseconds in `MoonlitReminderPlanner.h`, shared by the native
  schedule path and executed by `scripts/lib/reminder-planner.test.mjs`
  (48 unique future grid slots at initial/equal/day-25; first-future
  exact at every grid multiple). Due-now counts as future (a slot
  firing exactly now schedules once; strictly elapsed never bursts),
  so the equal-time boundary holds 48 and day 25 plans from slot 50.
  The duplicate gate holds while 8 of the recorded window are still
  future; every success receipt — duplicates included — carries
  `base_slot`, `horizon_end_unix`, and `scheduled_slots`, and the
  game side keeps known metadata rather than recording a zero from a
  bare duplicate. The game-side hold rule mirrors the native gate
  exactly (same base/anchor/integer-ms inputs, same shared vectors);
  legacy end-only rows derive their base once or replan once. An
  expired known anchor schedules future-only slots on genuine refresh
  (no coins move); unknown/none sources never schedule; Android first
  triggers land on the anchor grid's next future slot (boot included),
  and the pre-24 app-global check resolves its op id by reflection.
- Tall keyboards (Brief 217): a plain lift cannot fit the 228px card,
  so `_apply_keyboard_shift()` compacts when the lift runs out — the
  optional bust/header/hint hide, the card shrinks to its live minimum
  (full 228 vs short 138 at 808x360 ko), and field, error feedback,
  and confirm lift above the keyboard with the 8px margin. The mode
  decision always measures the full card, so the compact rect cannot
  feed back and oscillate; resize never re-seats a shifted form, and
  hiding restores chrome, geometry, and typed value, then re-seats for
  the current view. An all-screen keyboard that still covers the short
  card is dismissed once per height (`virtual_keyboard_hide`, edge on
  the occlusion value); the focused field keeps its value and the
  keyboard's own submit still files the claim. Tests and the QA
  harness drive this same hook with staged device pixels and window
  (`_apply_keyboard_shift(height, window)`; headless owns no window,
  so the window stages with the viewport); `lodge_review mode=room
  state=name kb=432` captures the adapted form (synthetic staging,
  never native delivery).

## The gate lodge (Brief 202 route)

Scene `scenes/gameplay/gate_lodge.tscn`, controller
`scripts/gameplay/gate_lodge.gd`, guide
`scripts/actors/lumi_guide.gd`. First visit for cloud-linked accounts
whose durable cache holds no verified handle or no acknowledged lesson
bit. Completed accounts plan the Arena directly; local-only guests
never enter (no claim to settle).

### Routing (production_host)

- `needs_lodge_lesson() -> bool`: sync, vault cache only. True when
  cloud-linked AND (no verified display OR intro bit unset). The only
  new refusal in `plan_entry`: `{refused, needs_lodge}`.
- `plan_lodge_entry() -> {ok, lodge, account_id, needs_name}`: same
  guards as `plan_entry` (identity/deletion/in-flight/login/restore)
  plus `lodge_complete` when settled. Holds the entry lock; arms NO
  journey, stamps NO title, touches NO save. Cancel via
  `cancel_entry_plan`.
- `plan_lodge_exit(fresh, confirmed)`: needs the live lodge plan on the
  same account plus a settled cache (`no_lodge_plan`,
  `login_in_flight`, `account_moved`, and the `needs_lodge` double-tap
  guard). Releases the hold, then plans exactly like the title (Resume
  vs confirmed fresh; defeated journeys refuse resume here too). On
  refusal the lodge hold restores.
- `production_entry` detours `needs_lodge` into the lodge loader with
  the same confirm/cancel/retry semantics (`_load_is_lodge`); a retry
  re-plans the lodge, never the arena.

### Lesson flow (controller states)

BOOT → GREET (3 lines + server name recovery) → NAME (form; empty
start; offline/taken/invalid/retry states; no spinner trap) → MOVE →
DASH → GATE (walk to the moon gate) → SEALING (`mark_intro_complete`)
→ DEPART (Resume vs confirmed Fresh vs walk back) → EXITING; LOST on
account move/deletion (releases the plan, walks to title). Skip
advances words only; gates complete only from performance: move needs
60 base units of real walking, dash a real `Player.dash()` in flight,
the gate the hero's feet inside the painted arch trigger plus the
server ack. Sticky per-account gates in the vault (`lodge_progress`,
cap 8, unknown gates refuse, malformed entries drop) resume practice
after restart; `Onboarding.mark_done(key, durable=true)` quiets the
matching arena tip from the actual performance (the lodge arms no
journey, so only the durable path writes). The intro bit flips only on
the ack; a miss re-arms the gate for another explicit touch. The scene
holds `moonlit_dialogue` for the whole visit, so attendance receipts
wait out the keyboard and speeches; the first eligible claim settles
after the lesson.

### Recovery

- Restart before claim / before seal: same canonical ID; `load_…` (or
  the warm cache) recovers the handle; sticky gates skip taught steps.
- Uncertain claim ack: retry the same name (restore path) or tap again;
  never a second name, never a remint.
- Uncertain seal ack: DEPART only on `ok`; anything else re-arms the
  gate; re-entry re-seals idempotently.
- Account switch / deletion / token death mid-visit: every await
  re-checks the bound account; stale work retires to LOST → title; the
  lesson waits for the next entry.
- Cold cache on a fresh install: the lodge loads before asking; a
  verified completed account passes straight to departure. The
  recovery branch trusts only the host's cached readiness
  (`needs_lodge_lesson`), never the reply's intro bit alone: a failed
  cache write keeps the lesson open and re-seals idempotently.

### Layout

`GateLodge.layout_for(viewport_size)` is pure: aspect ≥ 1.7 → the wide
plate (808×360 and wider), else the 4:3 tablet plate (808×606). The
room covers (never bands); actors scale with the room from their
plate's base (both bases run 1.0, so Lumi keeps one world height on
both plates: 42 world px, 1.5x the tallest hero opaque body at 28.05,
measured across all five heroes — never an assumed 64px hero);
walk/desk/gate/Lumi/hero derive from measured plate
fractions (gate pale mass 0.826/0.196 wide and 0.857/0.163 tablet,
desk warm mass 0.261/0.300 wide and 0.239/0.263 tablet, open floor
below ~0.34 wide / ~0.30 tablet). Walls clamp through the player
bounds, the desk and Lumi push out, the gate triggers on feet. Lumi
packs four 869px-tall facings under one scale and one bottom-center
foot anchor, with a still-body idle (visible heights 853/850/851/852
source px, 0.35% spread). The guide node converts source to world
itself (`BASE_SCALE`, `set_actor_scale` for the room zoom); only the
floor shadow breathes (alpha 0.85 +/- 0.04, period 2.6 s), so the
planted anchor and the painted foot line never shift, and the shadow
recomputes from world units.

### Fake-host contract (tests + harness)

`account_state`, `needs_lodge_lesson`, `verified_display_name`,
`load_adventurer_name`, `claim_adventurer_name`,
`mark_intro_complete`, `saved_gate_summary`, `plan_lodge_exit`,
`confirm_entry_account`, `cancel_entry_plan`, plus the
`production_changed` signal. The lodge also honors `host_override`,
`embedded` (emits `request_title` / `request_arena` instead of
swapping), and `move_override*` (scripted stick for the clip).

### QA harness

`apps/game/tools/lodge_review.tscn`
(`-- mode=validate|room|contact|clip framing=… locale=… state=…
out=…`). Validate runs headless (layout math plus safe-area and
clipping and 360-tall height-budget audits, 297 checks, plus the guide
source-to-world audit);
room/contact/clip need `--windowed` with
`--resolution` on a real display. The clip simulates up to 600 frames
with at most 120 saved, prints observed move/dash/stop/depart phases,
and exits nonzero unless all complete; room `state=greet` captures the
true unnamed greeting. Isolated user files throughout.

## Later extensions

Reminder tasks extend this same note.
