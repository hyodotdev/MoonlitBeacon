# 4.0.0 cloud coordinator build log

Author-only. What the Brief 053 round actually built, why it is shaped the
way it is, and what bit us. Player-facing behavior is unchanged: the
coordinator has no presentation yet, so title/HUD/arena play exactly as
before until the wiring round lands.

## Round 6: retired rank owners write nothing (Brief 077)

The director's overlap probe caught the gap Round 5 left: the ticket
retired waiters, but a retired owner that landed after A→B→A still
wrote its stale Knight row, count entry, and last-pair snapshot over
the fresh Dancer-600 measurement (the binding allowed A again, so
only the ticket knew it was stale). Ticket validity is now checked
before and after every awaited step and before every mutation: the
ticket threads through the own read and the count (both keep an
optional ticket defaulting to the legacy ticketless call), a retired
owner reports cancelled (`account-changed` on a foreign binding,
else `stale-reply`) without writing any cache, touching any throttle
stamp, starting any later count query, or releasing a newer ticket.
The coordinator drops a cancelled Hall result silently and keeps its
newer snapshot pair instead of degrading to error.

Tests overlap for real this time: the fresh newer result completes
BEFORE the retired old result in every case — A→B→A retired during
the own read (the director's probe shape) and during the count, a
same-account best submission invalidating a pending pair, and a late
old completion while a newer ticket is still pending (its waiter
shares the newer best, proving the ticket was never released). The
Round 5 expectation that an invalidated owner may return ok is
replaced with the freshness contract: cancelled owner, no count
query, same-clock live re-read. The coordinator test drives a
submit refusal through a gated sender pair and pins the kept
Dancer-600 snapshot with zero post-invalidation emissions.

What bit us in round 6: the coordinator overlap pair silently served
from the live refresh's own window instead of reaching the gate, so
the overlap leg runs past TTL expiry where a live read is forced.

Measured checks: coordinator 1089/1089 (was 1072); hall 249 (was
207); checkpoint 63, transport 44, identity 54, account 37; journey
484; vault 206; `check_scripts` 149. Negative controls (each
reverted, green again): a neutered retirement predicate fails 19
hall cases with the exact stale signature (600→100, Knight over
Dancer, old ok); dropping only the own-read check still fails the
request-budget guards. `check:store-screenshots` goes red (all of
`apps/game` is hashed; no recapture). Emulator suite (38) and
device checks stay with the director.

## Round 5: simultaneous rank refreshes share one ticket (Brief 072)

The director's delayed-transport probe caught the gap Round 4 left:
with nothing cached, three simultaneous `fetch_self_rank` calls fell
through the throttle and fired three owned reads plus three count
queries. The complete refresh now owns a generation-safe in-flight
ticket per public ID before the first await: the first caller
measures, later callers await the same exact result (rank, row,
sources, timestamps), so three at once fire one owned-row read plus
at most one count query and never combine different row/rank pairs.
Every exit completes through `_finish_self_rank`, which emits only
while its ticket is still current; `set_account` and `clear_cache`
retire outstanding tickets with a cancelled outcome per waiter
(`account-changed` / `stale-reply`), snapshotting and clearing the
table before the first emission so a reentrant refresh mints a newer
ticket the retire cannot touch. A retired owner's late reply
completes silently to its own caller. No coordinator change was
needed: concurrent `refresh_rank()` calls coalesce in the Hall, and
the no-argument API is untouched.

Tests mirror the probe: a frame-delayed routing sender forces real
overlap for three simultaneous service calls (one test failed first
with 2 reads + 2 counts and a transport-cap refusal, then passed),
waiters share offline/malformed/unranked terminal outcomes, and
retirement covers switch (prompt cancel, late owner cancelled),
A to B to A (both legs live, no stranded lock), and mid-flight
invalidation (waiter cancelled, owner keeps its result, next refresh
re-reads live). The coordinator concurrent test now pins exactly one
read plus one count with a shared measurement, and a new waiter test
pins switch-cancel for the pair plus the A to B to A recovery.

What bit us in round 5: the new waiter test queued spare dummy
replies that a later profile restore consumed positionally, so
routed-call tests now queue only the bodies non-routed calls need.
Also, a retired-pair emission assertion initially swept the final
recovery refresh; it now scopes to pre-recovery emissions.

Measured checks: coordinator 1072/1072 (was 1058); hall 207 (was
159); checkpoint 63, transport 44, identity 54, account 37; journey
484; vault 206; `check_scripts` 149. Negative control (reverted,
green again): a disabled waiter join fails counts, sharing, and
prompt-retirement assertions. `check:store-screenshots` goes red
(all of `apps/game` is hashed; no recapture). Emulator suite (38)
and device checks stay with the director.

## Round 4: the rank describes the owned best record (Brief 070)

The accepted `refresh_rank()` ranked the live checkpoint score, so a
fresh Dancer journey at 10 counted our own Knight record at 100 above
itself and reported #2 on a one-player board — and any rank it showed
sat beside the wrong hero/score. The rank now reads our owned
`mb_hall_v1/<canonical-id>` row first, then counts rows strictly above
its best score, and carries that row's hero/score/cycles/public ID
with the rank result and snapshot. The director fixture (Knight 100
owned vs Dancer 10 live) reports rank 1 / score 100 / hero Knight; a
missing row is genuinely unranked (rank 0, `own-row-missing`, no
submission started).

`CloudHall.fetch_self_rank()` owns the pair: a validated cached own
read (own ID, allow-listed hero with short-id resolution, bounded
score/cycles; misses cached too) plus the existing aggregation count
at the owned best. The two reads are sequential, not atomic, so each
half labels its own source and measurement time (`row_source` /
`rank_source`, `row_fetched_msec` / `rank_fetched_msec`;
`fetched_msec` is the newer half) and `source` follows the count
half. The complete refresh shares the existing global 5 s window and
bounded caches (new 8-entry own-row cache beside the 8-entry rank
cache): inside the window it serves the last known pair labeled
`cache-throttled` and sends nothing, so the own row is never
re-probed per local score change. Budget: at most 2 requests per
window crossing, 0 inside; concurrent first-calls at most 2 each.
`submit_best` now clears caches on `not-best` as well as on success
(including the write-race denial), so a refusal converges to the
actual server record on the next refresh. `refresh_rank()` keeps its
no-argument shape and `rank_snapshot()` keeps every key
(`requested_score` now equals the ranked owned best); new keys are
documented exactly in the host contract. No new collection, rule, or
index: the own row is a public document GET, the count query is the
unchanged `score GREATER_THAN best` aggregation.

Seven coordinator scene tests pin the fixture, unranked, submit and
cross-device convergence, malformed rows, offline labeled cache,
switch/cancel during both awaits (gated own-read retire + tripped
aggregation), and concurrent-call bounds; the hall suite pins the
pair, ties, throttle, offline, not-best convergence, and the own
cache bound. The three older rank tests now queue the own row first
and assert the owned best travels with the rank.

What bit us in round 4: pre-setting the shared throttle stamp before
the own read made the inner count call serve stale instead of going
live on window crossings, so the gate stamp moves only when a count
actually sends (plus on a live unranked verdict, which sends no
count). And a bare concurrent-refresh test with queue-ordered replies
depends on coroutine resumption order, so the overlap test routes
fixed bodies by URL while still recording every call.

Measured checks: coordinator 1058/1058 (was 750); hall 159 (was 63);
checkpoint 63, transport 44, identity 54, account 37; journey 484;
vault 206; `check_scripts` 149 (was 135). Negative controls (each
reverted, green again): an invented #1 for a missing row fails 1 hall
case plus 1 coordinator case; ranking score 0 instead of the owned
best fails the count-filter case.
`check:store-screenshots` goes red (all of `apps/game` is hashed; no
recapture). Emulator suite (38) and device checks stay with the
director.

## Round 3: the upload lock is a ticket (Brief 066)

The director's gated probe caught one ownership defect: stale exits in
`_flush_async` assigned `_flush_running = false` unconditionally, so when
generation A answered late while generation B's own upload was parked, A
retired B's lock and a third flush/choice/restore could overlap B's
outstanding upload. Fix: the lock is now a ticket (`_flush_owner`, minted
from `_flush_seq`). Every early, success, failure, stale, and retry-exhaust
exit releases through `_release_flush(ticket)`, which clears only while the
completing flush still holds the lock; `configure_host` and `close` free
the retired ticket so the next owner acquires fresh. No polling loops were
added; the audit below found no other concrete ownership defect, so no
other module changed behavior:

- Transport: one `_in_flight` decrement after the retry loop serves every
  exit (retired break, success, exhausted) exactly once. The count is
  generation-agnostic by design and every resume re-checks retirement.
- Checkpoint: every post-await mutation (`_last_acked_revision`,
  `_failed_save`, byte drain) sits behind the stale check, and
  `switch_account` clears pending/failure state plus bumps the generation.
- Sender/hall: stale completions return cancelled before any cache or
  request-table write (the sender forgets only its own entry; the board
  cache is account-independent and the coordinator still guards the
  snapshot write).

Two permanent tests genuinely overlap two generations through separately
gated senders: A parks, B readies and parks its own upload, A answers
late and must retire (cancelled, lock held, zero emissions, zero file or
sender effects on B) while a third flush/restore/choice is refused, then
B answers, finishes, and releases its own ticket so the waiting choice
lands. A second test parks a flush, closes, then answers late: cancelled,
no post-close emissions, closed snapshots and files untouched.

What bit us in round 3: the unconditional-release negative control fails
the key assertion and then wedges the suite — the freed lock lets the
"third" flush take work and park at the closed gate while the test awaits
it directly, which is exactly the production overlap the ticket forbids.
The disabled-release control fails cleanly instead (30 failures, both new
release assertions among them).

Measured checks: coordinator 750/750 (was 704); checkpoint 63, transport
44, identity 54, hall 63, account 37; journey 484; vault 206;
`check_scripts` 135. Host contract unchanged: same codes, signals, and
snapshot keys; the ticket is internal (`_test_state.flush_running` still
reports the lock as a boolean).

## Round 2: three production interleavings (Brief 059)

The director's probes confirmed three defects against real isolated files;
all three are fixed, with focused durable tests, in the same copy.

1. Silent rebase onto foreign progress. `flush` loaded the remote and
   committed local work one past it even when the remote held another
   device's progress the local baseline had never seen. Fix: each slot's
   `.rev.json` (now version 2, version 1 loads compatibly) carries a
   durable sync baseline (revision + payload digest of the last agreed
   state); the flush compares the loaded remote against the captured
   baseline before any commit and conflicts (`foreign-progress`,
   `remote-advanced`, `remote-rewritten`) without sending. A missing
   remote with acknowledged history is a `remote-missing` conflict, not a
   silent re-create; identical bytes agree without a commit. The baseline
   moves only on commit success, remote acceptance, restore, and verified
   adoption — never silently on retries. The local choice re-reads the
   remote fresh, preserves it before committing, then preserves the
   actually overwritten bytes when the remote advanced again mid-choice
   (`remote_exact` / `remote_revision` in the result).
2. Reconcile stealing unpaid local earnings. Restart reconcile floored
   the checkpoint echo with zero granted even for locally-issued ids with
   a live retry, so the failed settlement retried to zero. Fix: new
   `Vault.reconcile_local_receipt()` leaves locally-issued integers and
   session-issued fallbacks with no record strictly alone
   (`local-pending`), never raises an existing record from an echo, and
   floors only unknown ids with zero granted. Imported integer journey
   ids are remapped at every install to deterministic per-account strings
   (`c` + 31 hex of `sha256("uid:journey")`, strings pass through) by
   rewriting only the journey-id span of the original bytes — verified
   field-by-field afterwards — so a foreign int can never alias or
   corrupt a local record and the local watermark never advances for
   imports. No checkpoint schema change; mapped ids are safe strings old
   validators accept, so the host needs no data change.
3. In-flight completion erasing a newer seal. Every queued payload shared
   revision 1, so a commit success drained a newer seal queued mid-flight
   and reported it acknowledged. Fix: `CloudCheckpoint` drains by exact
   committed bytes only (identical requeues still drain); the coordinator
   serializes uploads behind a single flush owner
   (`flush-already-running`, `flush-in-flight` on choices/restores while
   busy) with chained follow-ups only while newer work is queued. The
   checkpoint module binds to one account (`switch_account`) with
   generation guards inside every awaited helper, so a reconfiguration
   mid-await retires the old completion without touching the new
   account's pending or failure state, and cross-account queuing is
   refused (`wrong-account`).

What bit us in round 2: Godot's JSON round-trip is lossy — `stringify`
sorts keys and `parse` returns every number as a float — so the restart
catch-up now queues effective file bytes verbatim (main-or-backup, like
`Journey.read_checkpoint` but without re-serializing) and the remap is a
verified surgical span rewrite instead. Parsed floats count as integers
wherever the Journey validator counts them. Also, scene-test settle
helpers must poll for the ack itself, not merely a `queued` state the
hook also emits.

Measured checks: coordinator 704/704 (was 589); checkpoint 63 (was 48);
transport 44, identity 54, hall 63, account 37; journey 484; vault 206;
`check_scripts` 135. Negative controls (each reverted, green again):
disabled pre-commit compare fails the foreign-progress cases; bypassed
reconcile-local branch replays probe 2 (retry grants 0, 8 failures);
revision-compare drain fails 2 checkpoint + 5 coordinator cases.

## What changed

### Coordinator (`scripts/cloud/cloud_coordinator.gd`, new)

- Host-injected Node (no UI, native, autoload, or scene deps):
  `configure_host()` takes UID, durable guest `MB-` ID, token supplier,
  sender, Vault, release, project, and web key; the canonical ID comes back
  via `account_changed` / `account_snapshot()` for the host to persist.
  Re-configuring switches accounts.
- Guest reservation through the new
  `CloudIdentity.register_or_restore_with_guest_id()`: a new UID reserves
  the exact pre-play ID in one atomic commit; a taken ID returns explicit
  `guest-id-taken` with no silent replacement; an existing UID returns its
  canonical ID with `restored: true`.
- Journey slots partitioned by public ID (`use_account`, `account_*_path`
  helpers in `journey.gd`): main, backup, revision metadata, and the two
  latest rejected payloads. The legacy single save moves once, byte-verified,
  into the first account; a guest slot that learns a different canonical ID
  moves under it the same way, never into an occupied slot.
- Subscribes to the new stable-checkpoint hook, which fires only after a
  verified local write (failed writes never queue). Uploads coalesce, flush
  deferred off the gameplay path, ack only on real CAS success, bounded to
  3 attempts on retryable failures. Stale generations drop without
  re-queueing, so an old account's payload can never upload as the new one.
- Conflicts surface summaries only and wait for
  `resolve_conflict("local" | "remote")`. Either choice preserves the
  rejected version byte for byte first. Remote installs only after complete
  `_validate_remote_payload` (both size bounds, silent JSON parse,
  ledger-key refusal, strict `Journey.validate`) plus the installing
  `write_checkpoint_text` validating again; the hook is suppressed during
  installs. Restore installs only into empty/identical slots, else opens a
  conflict instead of overwriting.
- Hall: `submit_current_best` sends the active checkpoint's actual
  hero/score/cycles (score recomputed through `Score`, hand-count pinned at
  18620 in tests) into the one owned row; board/rank refreshes label every
  source and retain last-known on failure.
- Revision file beside each slot (acked/known-remote, best effort);
  recovery reads via `recovery_payload()`; `close()`/`_exit_tree()` retire
  everything. No `_process`, no per-frame serialization, no mid-frame
  background writes. No token/UID in Hall rows, logs, or files.

### Journey (`scripts/gameplay/journey.gd`)

- Stable-hook subscribe/unsubscribe/clear + notify-on-OK in both write
  paths. Empty by default, so existing suites behave byte for byte.
- Partition + migration + slot-move helpers, all byte-verified with
  verify-before-delete; existing slot files are never overwritten.
- `write_checkpoint_text()` installs validated download bytes exactly.

### Vault (`scripts/gameplay/vault.gd`)

- Fallback strings settle only from the session issuance set; evicted or
  never-issued strings retire and mint nothing (the confirmed hole).
- New `initialize_remote_receipt_floor()`: records remote history durably
  with zero granted, rising only, advancing the int watermark past remote
  ids; new deltas settle exactly once after. Paid/coin ledgers untouched.
- The coordinator floors the active journey from its checkpoint echo on
  configure/ready/install, which also reconciles pre-fix unsettled
  fallbacks across a restart without re-issuing them.

### Bounded services

- `cloud_schema.gd`: `MAX_CYCLES` 9999 → 99999 to match `Journey.MAX_CYCLE`.
  The score ceiling stays 2000000000 (legacy-aligned, structural only).
- `cloud_hall.gd`: rank cache bounded to 8 (oldest-first eviction), rank
  refresh throttled globally (changed scores reuse labeled last-known),
  offline fallback to labeled cache, per-account binding with stale
  cancellation. Exact-score fresh cache still answers `cache` first, so old
  expectations hold.
- `cloud_http_sender.gd`: `body_size_limit` bounds allocation before
  receipt (`RESULT_BODY_SIZE_LIMIT_EXCEEDED` → `response-too-large`
  envelope), active-request tracking with `close()`/`_exit_tree()`
  cancellation, generation guards on completion.
- `cloud_transport.gd`: maps `response-too-large` to non-retryable
  `response-too-large`; the post-receipt size check stays for unbounded
  senders.

### Tests and tools

- `tests/test_cloud_coordinator.gd` (+`.tscn`, scene-based: the bridge
  needs the Vault autoload and Journey globals, which a bare `--script`
  run does not register): 589 cases covering offline start, exact-ID
  reservation, canonical restore, collision, guest→canonical move,
  migration-once bytes, switch preservation + Hall/pending clearing, stale
  flush, disk failure, auto-flush ack, CAS conflict with both choices and
  byte-identical recovery, malformed/oversized rejection with layer codes,
  remote floor + delta-once, retired replay zero, 200-score throttle with
  bounded cache/requests, grown restore + actual Hall row/rank, leak
  checks, and sender pre-bound/close.
- `tools/run_coordinator_tests.mjs`: standalone isolated runner (mirrors
  the cloud runner; error gate included). Not registered in the shared
  runner by brief order.
- `test_cloud_hall.gd`: matched-bound expectations (10000/99999 valid,
  100000 refused) plus rank throttle/bound/account/fallback coverage.
- `test_cloud_identity.gd`: guest reservation, explicit collision,
  canonical restore, malformed-guest refusal.
- `test_cloud_transport.gd`: pre-receipt bound mapping.
- `test_journey.gd`: `_test_mixed_eviction_and_garbage_ids` rewritten with
  the reason in its doc comment — unissued strings now assert `RETIRED`
  with zero grants/no growth; issued fallbacks settle while retained and
  an evicted one replays `RETIRED`. Normal fresh runs, failed-issue,
  restart/retry, and junk expectations are unchanged.

### Rules

- `firestore.cloud.addition.rules`: Hall cycles `<= 9999` → `<= 99999`;
  legacy `firestore.rules` untouched (splice shows legacy 9999 beside
  cloud 99999).
- `tests/cloud-rules/cloud-rules.test.mjs`: new bound case (10000 and
  99999 allowed, 100000 and score 2000000001 denied, final state pinned).
  Suite grows 37 → 38. Emulator run stays with the director.

## What bit us

- A bare `--script` SceneTree run does not register autoload identifiers,
  so the coordinator suite is scene-based like the journey suite (first run
  failed compile on `Vault`; `Journey.validate` also reads `Vault.HEROES`
  at runtime, so faking the Vault was never an option).
- The `--script` probe and the stale `.godot` class cache (no `Journey`
  entry until `--import`) produced confusing `Identifier not found`
  errors; one `--import` fixed the cache and minted the new `.uid` files.
  The sandbox blocks saving editor settings, which `--import` reports and
  survives — documented, not worked around.
- The first flush design re-queued taken payloads on stale completions,
  which would have uploaded old-account bytes as the new account. Stale
  completions now drop; only same-generation failures re-queue, and only
  when nothing newer superseded them.
- Rank throttling initially returned a failure when throttled with nothing
  cached, which would block the first post-boot fetch. Throttled calls with
  nothing to serve now send once instead.
- Negative control 3 (skipped coordinator validation) first passed because
  the installing Journey layer refused the same payload with a different
  code — the test now pins the layer code, which also documents the
  two-layer defense.

## Measured checks

- Coordinator: 589/589; cloud: 44 + 54 + 48 + 63 + 37; journey 484;
  vault 206; `check_scripts`: 135 scripts compile.
- Negative controls (each reverted, green again): reopened string hole
  fails 5 coordinator cases; disabled rank throttle fails 5 hall cases;
  skipped coordinator validation fails 1 case with the install layer as
  backstop; fabricated replacement ID fails 3 identity cases.
- `check:store-screenshots` goes red (all of `apps/game` is hashed; no
  recapture). Emulator suite (38) and device checks stay with the director.
