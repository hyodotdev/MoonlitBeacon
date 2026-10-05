# Cloud schema and setup — 4.0.0 owned journeys and Hall (author-only)

Data-layer round only. No title/HUD integration yet; the game plays exactly
as 3.0.0 until the integration round lands. Do not promise players cloud
support from this round: mock and emulator evidence below is not production.

## Collection field contracts

Project `moonlitbeacon-778ee`, database `(default)`. All timestamps are
Firestore timestamps; the client stamps device time and the rules accept
15 minutes past to 10 minutes future skew.

### `mb_profiles_v1/{uid}` — private, immutable UID-to-public-ID row

| Field | Type | Rule |
| --- | --- | --- |
| `uid` | string | == document ID == `request.auth.uid` |
| `public_id` | string | `MB-` + 32 lowercase hex |
| `schema` | int | == 1 |
| `created_at` | timestamp | near now |
| `updated_at` | timestamp | near now |

Owner get/create/delete only, no list, updates denied (the mapping can never
be reassigned). Creation requires the paired reservation to belong to the
caller after the commit (`getAfter`), so no profile can point at another
player's reserved ID — neither alone, nor mismatched in a batch, nor via a
same-batch reservation delete. Registration is one atomic commit of both
halves or nothing; sequential half-registration is denied on both sides.
Deleting a living profile requires the Hall row and the reservation half
both gone after the commit; a missing row deletes as a no-op.

### `mb_reservations_v1/{public_id}` — ID claim keyed by the ID

| Field | Type | Rule |
| --- | --- | --- |
| `public_id` | string | == document ID, valid shape |
| `uid` | string | == `request.auth.uid` |
| `schema` | int | == 1 |
| `created_at` | timestamp | near now |

Owner get/create/delete only, no list, updates denied. `create` fires only
on absence, so a taken ID can neither be claimed nor changed by another UID,
and requires the paired profile after the commit: lone reservations are
denied, so no canonical profile can coexist with a missing or foreign
reservation after any commit. Deleting a living reservation requires the
Hall row and the profile half both gone after the commit, so a freed ID can
never be re-registered underneath a living Hall row or a stranded profile;
a missing row deletes as a no-op.

### `mb_checkpoints_v1/{uid}` — private versioned Journey save

| Field | Type | Rule |
| --- | --- | --- |
| `uid` | string | == document ID == `request.auth.uid` |
| `revision` | int | create == 1, update == old + 1 |
| `payload` | string | 1–32768 chars, brace-shaped (`{...}`); shape only, NOT parsed JSON |
| `schema` | int | == 1 |
| `updated_at` | timestamp | near now |

Owner get/create/update/delete only, no list. Client pairs the revision rule
with a compare-and-swap update-time guard. The server brace regex is a size
and shape bound only: brace-shaped garbage such as `{bad}` clears the rules,
so the client parses and rejects non-JSON before queueing or uploading, and
downloads still need the Journey validator before gameplay applies them.
Paid entitlements and Vault ledgers are rejected client-side and never
uploaded. Firestore offers no server JSON parser; none is invented here.

### `mb_hall_v1/{public_id}` — public best-score row per public ID

| Field | Type | Rule |
| --- | --- | --- |
| `public_id` | string | == document ID, valid shape |
| `hero` | string | one of the six `res://resources/heroes/*.tres` paths |
| `score` | int | 0–2000000000, never decreases |
| `cycles` | int | 0–99999 (matches `Journey.MAX_CYCLE`) |
| `release` | string | 1–32 chars, e.g. `4.0.0` |
| `schema` | int | == 1 |
| `updated_at` | timestamp | near now |

Public get/list. Create/update require BOTH the caller's UID profile
mapping to the document's public ID AND the reservation belonging to the
caller, before AND after the commit, so a write bundled with pair deletes
cannot orphan a row no living account owns; deletes need the pre-state pair.
Rows carry no UID, email, save, or credential. A profile alone — even a
planted one — grants nothing. Equal-score retries succeed (idempotent);
lower scores are denied. Bounds are structural only, not anti-cheat.
Deleting a missing row is a signed-in no-op.

## Client modules (`apps/game/scripts/cloud/`)

- `cloud_schema.gd` — collection names, bounds, hero allow-list, Firestore
  value encode/decode, silent JSON parse, payload summaries.
- `cloud_transport.gd` — authenticated REST with injected sender + token
  supplier. Statuses: ok, offline, unconfigured, cancelled, conflict,
  failure. Bounds: 10 s timeout, 256 KiB response cap, 3 attempts, 2 in
  flight. Stale replies after account switch or cancel-all report cancelled.
- `cloud_http_sender.gd` — real `HTTPRequest` sender (future integration).
- `cloud_identity.gd` — atomic profile+reservation registration with
  collision retry (5 attempts), canonical restore, guest-link identity.
- `cloud_checkpoint.gd` — coalesced queue, guarded saves, explicit
  revision conflicts with local/remote summaries, retained failed saves.
- `cloud_hall.gd` — monotonic submit, top-board query, aggregation rank
  (ties share), owned deletion, cache/throttle with labeled sources.
- `cloud_account.gd` — one atomic deletion commit: Hall, checkpoint,
  reservation, profile together; ok only on acknowledgement.
- `cloud_local_store.gd` — per-UID `user://cloud_journey.<uid>.json` files.
- `cloud_coordinator.gd` — game-facing Node over the modules above: host
  account injection, guest-ID reservation, partitioned Journey slots,
  conflict surfacing with recovery, receipt floors, and bounded Hall
  reads. Host contract:
  `notes/setup/cloud-coordinator-contract.md`; behavior tests:
  `node apps/game/tools/run_coordinator_tests.mjs` (standalone, not in the
  shared runner).

Behavior tests: `apps/game/tests/test_cloud_*.gd` plus
`tests/support/fake_cloud_sender.gd`, run by the new isolated runner:

```bash
node apps/game/tools/run_cloud_tests.mjs
```

The existing regression runner is untouched by brief order, so run this file
separately until integration.

## REST shapes the client sends

- Get: `GET .../documents/{collection}/{id}`
- Register: `POST .../documents:commit` with two `update` writes, each
  `currentDocument: {exists: false}` (profile + reservation).
- Checkpoint save: `POST .../documents:commit` with one `update` write
  carrying all five fields, `currentDocument: {updateTime: "<read guard>"}`
  (or `{exists: false}` for revision 1).
- Hall submit: `POST .../documents:commit` with one `update` write keyed by
  public ID (idempotent retries, same document).
- Top board: `POST .../documents:runQuery`, `orderBy score DESCENDING`.
- Self rank: `POST .../documents:runAggregationQuery`, count where
  `score GREATER_THAN mine`; rank = count + 1.
- Account deletion: one `POST .../documents:commit` with four `delete`
  writes (Hall, checkpoint, reservation, profile), no preconditions —
  missing rows are server no-ops, so a crash or repeat is safe.
- Single Hall-row reset: `DELETE .../documents/mb_hall_v1/{public_id}`
  (owned pair required; the pair itself stays).
- Auth: `Authorization: Bearer <Firebase ID token>` (in-memory only, never
  saved or logged) plus `?key=<web API key>` when configured.

## Deployment and readiness (director operations, in order)

1. Enable providers in Firebase Console (Google, Apple, anonymous/guest).
   No provider is enabled yet; nothing here works against production until
   then.
2. Merge `firestore.cloud.addition.rules` into `firestore.rules` before the
   final catch-all (the builder below shows the exact splice), and merge
   `firestore.indexes.cloud.addition.json` into `firestore.indexes.json`.
   Keep every legacy line byte-identical.
3. Review the combined ruleset:
   `node tests/cloud-rules/build-combined-rules.mjs --out /tmp/combined.rules`
4. Run the emulator suite (needs Java, firebase-tools, `firebase` and
   `@firebase/rules-unit-testing` packages):
   `firebase emulators:exec --only firestore "node --test tests/cloud-rules/cloud-rules.test.mjs"`
5. Repeat the negative controls: flip the `-1` score case to a valid score
   and watch it fail, then revert; rerun the director's takeover probe
   (impostor profile + Hall overwrite of score 10 with 11) and confirm both
   steps are now denied with the score untouched.
6. Deploy rules, then indexes:
   `firebase deploy --only firestore:rules --project moonlitbeacon-778ee`
   `firebase deploy --only firestore:indexes --project moonlitbeacon-778ee`
7. Confirm the composite `mb_hall_v1(schema ASC, score DESC)` index is
   `READY` in Console before the filtered board ships. The global top board
   needs no composite (automatic score index).
8. Ship `firebase.cfg` with the web API key to test devices only; the
   key stays out of git. Keep the Spark plan: no Cloud Functions.

## Account-data deletion runbook (before Auth deletion)

Run `cloud_account.delete_account_data(uid, public_id)` — one authenticated
`documents:commit` carrying four deletes (Hall, checkpoint, reservation,
profile), no preconditions — then delete the Firebase Auth user natively.
Never delete Auth until the cloud commit is acknowledged.

A crash or kill can only leave all four rows or none of them: the commit is
atomic, and the rules couple the living pair halves to each other and to
the Hall row, so no canonical profile can end up claiming an ID whose
reservation is gone (and thus re-registerable by another UID). Missing rows
are no-ops, so repeat the same single commit after any interruption; a
failed commit applies nothing and reports its code with all four steps
remaining. Never delete the pair halves by themselves: the rules refuse a
living half without its counterpart.

## Evidence map

- Source: new modules and behavior tests above (mock transport, no cloud).
  206 Godot cases across the five `test_cloud_*` suites.
- Emulator: `tests/cloud-rules/cloud-rules.test.mjs`, 37 cases in 9 suites
  (director runs; the implementer sandbox has no emulator packages or
  network). Covers the director's takeover probe verbatim, planted and
  orphaned-row resistance, atomic-only registration, both mismatch
  directions, final-state bypass, the harmless no-op, restore, coupled and
  atomic deletion with idempotent repeats, and two negative controls: a
  rules-disabled scenario proof plus a per-leg guard control.
- Deployed providers: none yet. No production cloud claim is made.
