# Cloud coordinator host contract — 4.0.0 owned journeys (author-only)

`apps/game/scripts/cloud/cloud_coordinator.gd` is the game-facing bridge
between the local Journey/Vault and the owned Firestore rows. Presentation
(title/HUD copy) and native wiring (auth provider UI, token minting) follow
separately; this note is the exact contract the future host implements
against. No provider is enabled and no rules are deployed yet: everything
below is verified against scripted fakes plus the real rules emulator, never
against production.

## What the host supplies

One call, synchronous and local-only (validates, partitions files, migrates
once, floors the active receipt, then reserves in the background):

```gdscript
coordinator.configure_host({
    "uid": "firebase-uid",            # required, [A-Za-z0-9_-], 1..128
    "guest_public_id": "MB-…",        # required, MB- + 32 lowercase hex
    "token_supplier": Callable,       # required, () -> String, "" = signed out
    "sender": Callable,               # required, (method, url, headers, body)
    "vault": Vault,                   # required, the Vault autoload
    "release": "4.0.0",               # default 4.0.0, 1..32 chars
    "project_id": "moonlitbeacon-778ee",
    "web_api_key": "",                # default empty
})
```

- `guest_public_id` is the durable pre-play ID the host holds before play.
  A new UID reserves exactly this ID; it is never silently replaced.
- `token_supplier` is called per request and held in memory only. The token
  is never persisted, never logged, and never appears in a result dict.
- `sender` follows the transport contract: returns `{transport, code,
  body}` where transport is one of `ok`, `offline`, `timeout`, `dns`,
  `cancelled`, `response-too-large`, `unreachable`. It may be async.
- Re-calling `configure_host` switches accounts. The old slot's bytes stay
  untouched; its in-flight work retires and reports `cancelled`.

## What the host receives

- The canonical public ID, via the `account_changed` signal and
  `account_snapshot()["public_id"]`, once `state == "ready"`. Persist it
  and supply it as `guest_public_id` next launch. When it differs from the
  supplied guest (a UID that already owned another ID), the canonical one
  wins and the guest slot's offline work moves under it byte for byte.
- Account states: `reserving`, `ready`, `offline`, `conflict`
  (`guest-id-taken`: another UID holds the guest ID — ask the player/host
  for a fresh durable ID, do not invent one), `error`, `closed`.
- Save states via `save_changed`: `idle`, `unregistered` (local-only),
  `queued`, `uploading`, `acked` (with `acked_revision`, set only on a real
  server commit), `conflict`, `offline`, `error`.
- Conflicts via `conflict_found` and `conflict_snapshot()`: safe
  local/remote summaries (revision, bytes, digest, gate/cycle markers) —
  never full payloads, never credentials. The coordinator never auto-picks.
  Conflict codes: `foreign-progress` (another device's work predates the
  local sync baseline), `remote-advanced` / `remote-rewritten` (the remote
  moved since the baseline), `remote-missing` (document gone with
  acknowledged history — the local choice recreates it, the remote choice
  is refused), `revision-conflict` (guard miss between load and commit),
  `restore-differs` (download versus a valid local journey). Every conflict
  also carries `baseline_revision` for context.
- Hall via `hall_changed` / `rank_changed`: actual rows and our actual
  owned-best standing, each labeled `live`, `cache`, `cache-throttled`,
  `stale`, `offline`, `unranked`, or `unregistered`. The rank always
  describes the owned `mb_hall_v1` best row (hero/score/cycles carried
  with it), never the live checkpoint score. A missing own row is
  genuinely unranked (rank 0, no invented #1). Rank refresh is throttled
  globally (one window per 5 s no matter how the score moves) over
  caches bounded to 8 entries each; one window-crossing refresh sends
  at most 2 requests (own-row GET + count query), inside the window
  none.

## Calls the host makes

| Call | Meaning |
| --- | --- |
| `flush()` | Upload the coalesced pending payload. Compares the loaded remote against the durable sync baseline before any commit (up to 3 attempts on retryable failures). No-op when nothing is queued; `flush-already-running` while another flush owns the upload. |
| `restore_from_cloud()` | Pull the cloud checkpoint. Installs only into an empty or install-identical slot; a differing local journey becomes a `conflict` for explicit choice. A fresh install remaps an imported integer journey id, floors its receipt with zero granted, and adopts the remote as the new baseline. Reports `flush-in-flight` while an upload runs. |
| `resolve_conflict("local" \| "remote")` | Explicit choice. Either side preserves the rejected version to its recovery file first (`recovery_payload("local" \| "remote")` reads it back); the local choice preserves the actually overwritten bytes when the remote advanced again mid-choice (see `remote_exact` / `remote_revision`). Remote installs only after complete `Journey` validation plus integer-id remapping. Reports `flush-in-flight` while an upload runs. |
| `map_remote_journey_id(uid, journey)` | Pure import-id mapping (see below). |
| `submit_current_best()` | Submit the active checkpoint's actual hero/score/cycles as our single best row (idempotent same-document retries). Refuses without sending when out of bounds. |
| `refresh_board(limit)` | Public top board, cached + throttled + labeled. |
| `refresh_rank()` | Actual standing of our owned best row (see below). No arguments; reads only, never submits. |
| `account_snapshot()` / `save_snapshot()` / `conflict_snapshot()` / `hall_snapshot()` / `rank_snapshot()` / `state_snapshot()` | Memory-only state, no tokens. |
| `set_auto_flush(bool)` | Queue-flush after every stable checkpoint (default on). |
| `close()` | Retire everything; late replies change nothing. Also runs on `_exit_tree`. |

Nothing here waits on network: `configure_host` returns before the
reservation answers, stable checkpoints queue synchronously and flush
deferred, and every async reply is generation-guarded so a late answer for
an old account applies nothing.

## Rank result and snapshot fields

`refresh_rank()` reads our owned `mb_hall_v1/<canonical-id>` row, then
counts Hall rows strictly above its best score (rank = count + 1, ties
share it). The two reads are sequential HTTP calls, not one atomic
snapshot; each half carries its own source label and measurement time.
The result and `rank_snapshot()` carry the row with the rank, so the HUD
shows one record, never a cached rank beside a different hero or score:

| Key | Meaning |
| --- | --- |
| `status` | `ok`, `unranked` (row missing), `offline`, `failure`, `cancelled`, or `unregistered` (account not ready). |
| `state` (snapshot) | `ready`, `unranked`, `offline`, `error`, or `unregistered`. `offline`/`error` keep the last known ranked fields. |
| `rank` / `greater` | 1-based standing and the strictly-greater count; 0 while unranked. |
| `score` / `hero` / `cycles` / `public_id` | The owned best row the rank was computed for. `hero` is the canonical `res://resources/heroes/*.tres` path (short ids resolve through the submit allow-list); all zeroed/empty while unranked. |
| `requested_score` | Always equals `score`: the owned best the rank was computed for. Kept so older readers keep working. |
| `source` | Freshness of the count half: `live`, `cache`, or `cache-throttled`. |
| `row_source` / `rank_source` | Freshness of each half read (`live`, `cache`, `cache-throttled`; `rank_source` is `""` while unranked). |
| `fetched_msec` | The newer half's measurement time (device milliseconds). |
| `row_fetched_msec` / `rank_fetched_msec` | Each half's measurement time; stale serves keep theirs, so the score stays bound to its timestamp. |
| `live_error` | `""` normally; the failed live attempt's code on labeled-cache fallback (`offline`, …). |
| `code` | `own-row-missing` on unranked, `bad-hall-row` / `bad-hall-body` on a malformed row, else the transport code. |

Request budget: at most 2 requests per window crossing (own-row GET,
then the count query only when a valid owned score exists), 0 inside
the 5 s window, over an 8-entry own-row cache (misses cached too) plus
the 8-entry per-score rank cache. Simultaneous callers for one account
share one in-flight ticket: the first owns it before the first await
and the rest await its exact result (same rank, row, sources, and
timestamps), so three at once still fire one owned-row read plus at
most one count query and never combine different row/rank pairs. A
switch or cache invalidation retires the ticket: waiters report
cancelled (`account-changed` / `stale-reply`) promptly, and the
retired owner itself reports cancelled too — it writes no cache,
touches no throttle stamp, starts no later count query, and never
releases a newer ticket, so a late reply can neither restore stale
standing nor disturb a newer measurement (including across A→B→A).
The coordinator drops a cancelled Hall result silently and keeps
its newer snapshot pair. No new collection, rule, or index:
the own row is a public document GET and the count query is the
unchanged `score GREATER_THAN best` aggregation.

## Files (all under the isolated `user://`)

Per account key (canonical ID when ready, requested guest ID while
unregistered): `journey.<key>.json`, `.bak`, `.rev.json`
(acked/known-remote revisions), `.rejected-local.json`,
`.rejected-remote.json` (latest rejected payloads, byte for byte). The
legacy `journey.json` moves once, byte-verified, into the first account's
slot; later accounts find nothing to claim. Files hold checkpoint data and
revision numbers only — no UID, token, email, provider, or purchase record.

## Money rules the coordinator keeps

- A restore floors the remote cumulative target durably with zero granted;
  only new play above the floor settles, exactly once. Unknown or retired
  receipt ids (including evicted fallback strings) never mint.
- Restart reconcile (`Vault.reconcile_local_receipt`, run on configure and
  on ready) preserves locally-owed value: locally-issued integers and
  session-issued fallbacks with no record are left strictly alone
  (`local-pending`) so a failed settlement's retry still pays exactly
  once; existing records are never raised from an echo; only unknown ids
  are floored with zero granted.
- Imported integer journey ids are remapped at every remote install:
  `map_remote_journey_id(uid, journey)` turns each foreign int into a
  deterministic per-account string (`c` + 31 hex of
  `sha256("uid:journey")`); strings pass through (random fallbacks and
  mapped ids are already globally unique). The install rewrites only the
  journey-id span of the original bytes, re-validates, and verifies every
  other field untouched; the original remote bytes are preserved to the
  remote recovery slot. Host contract: never settle a foreign integer
  directly, never alias an imported int onto a local sequence id, and
  never reinterpret a mapped `c…` id as a sequence number. Local integer
  issuance stays purely device-local; the import path never advances the
  local watermark. No checkpoint schema change: mapped ids are ordinary
  safe strings that old validators already accept, so no host data change
  is required.
- Purchase and currency ledgers are never uploaded, downloaded, or synced:
  checkpoint payloads carrying ledger keys are refused both ways.
- Score/cycle bounds sent to the Hall match the Journey cap (cycles
  0–99999); the structural score ceiling (0–2000000000) is unchanged.

## Sync baseline (durable)

Each slot's `.rev.json` (version 2; version 1 files load with their
acknowledged revision and adopt baseline bytes on first verified
agreement) carries `acked_revision`, `known_remote_revision`,
`baseline_revision`, and `baseline_digest`: the last revision + payload
both sides agreed on. A flush compares the loaded remote against this
baseline before committing, because compare-and-swap alone cannot see
progress made before the guard read. The baseline moves only on commit
success, remote acceptance, restore, and verified adoption — never
silently on retries. A second concurrent flush reports
`flush-already-running`; choices and restores report `flush-in-flight`
while an upload owns the wire, and chained follow-ups run only while
newer work is actually queued.

## What the coordinator never does

No UI, no native/addon calls, no autoload reads of its own, no per-frame
serialization, no mid-frame background writes, no silent conflict choice, no
silent save overwrite, no fake rank (a missing row is unranked, never #1)
or fake login success, no rank submission from the rank path, and no claim
that fake-sender tests prove a provider. Fakes prove the orchestration;
the emulator proves the rules; providers prove themselves on a device.

## Runnable checks

```bash
node apps/game/tools/run_coordinator_tests.mjs   # 1089 coordinator cases
node apps/game/tools/run_cloud_tests.mjs         # 44 + 54 + 63 + 249 + 37 cloud cases
firebase emulators:exec --only firestore \
  "node --test tests/cloud-rules/cloud-rules.test.mjs"   # 38 rule cases
```

The coordinator suite is scene-based (`tests/test_cloud_coordinator.tscn`)
because it bridges the Vault autoload and the Journey globals. It is not
registered in the shared runner by brief order.
