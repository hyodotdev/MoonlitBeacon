# 4.0.0 cloud data layer build log

Author-only. What the Brief 045 round actually built, why it is shaped the
way it is, and what bit us. Player-facing behavior is unchanged: this round
is the cloud data layer only, and title/HUD integration follows later.

## What changed

- New `apps/game/scripts/cloud/` modules (schema, transport, HTTP sender,
  identity, checkpoint, Hall, account deletion, local store). All are
  `RefCounted` except the real HTTP sender `Node`, take injected sender and
  token-supplier Callables, and never save or log tokens, emails, provider
  names, or auth codes. No autoloads, no `project.godot` touch.
- New behavior tests `apps/game/tests/test_cloud_*.gd` with scripted fake
  sender (`tests/support/fake_cloud_sender.gd`) and a new isolated runner
  `apps/game/tools/run_cloud_tests.mjs`. The existing regression runner is
  untouched by brief order.
- New `firestore.cloud.addition.rules` + `firestore.indexes.cloud.addition.json`
  (additive files; the locked `firestore.rules`/`firestore.indexes.json` are
  not edited) plus `tests/cloud-rules/` with a splice builder, real emulator
  tests, and a runbook README.
- New author note `notes/setup/cloud-4-0-0-schema.md` with field contracts,
  REST shapes, deployment order, and the deletion runbook.

## What bit us

- `JSON.parse_string` prints an engine ERROR on malformed input, which fails
  the runner's error gate. All cloud parsing of untrusted text (payloads,
  server bodies, local files) now goes through `JSON.new().parse()` via
  `CloudSchema.parse_json_value`, which only returns its error code.
- `await obj.call("async_method")` and `await callable.call(...)` both work
  in Godot 4.7.1 (probed before building on the pattern), so duck-typed
  transport calls stay compatible with preloaded scripts and no `class_name`
  or editor import is needed.
- The macOS sandbox prints one engine-level
  `get_system_ca_certificates ... ret != noErr` ERROR on every Godot run,
  including pre-existing tests. It is environmental, not from this change.
- Naive brace counting on the combined ruleset tripped on a `{` inside a
  comment and a regex. The splice check strips strings and `//` comments
  before counting code braces.

## Decisions

- Profiles and reservations deny updates entirely: the UID-to-public-ID
  mapping is write-once and can never be reassigned, only deleted.
- Hall ownership is proven by a rules `get()` on the caller's UID profile,
  so public rows carry no UID, email, save, or credential.
- Checkpoint conflicts return both summaries and stop; the integration
  chooses local or remote explicitly. No clock-timestamp auto-choice.
- Hall rank counts strictly greater scores, so ties share a rank.
- Deletion order is Hall, checkpoint, reservation, profile, then Auth:
  deleting the profile first would orphan the Hall row its proof needs.

## Round 2: ownership repair (Brief 048)

The director's emulator probe took over an ID under the round-1 rules: a
second UID created its own profile pointing at the owner's reserved public
ID, then overwrote the owner's Hall score. Both writes were accepted because
`ownsPublicId()` read only the requester's profile and profile creation did
not require the paired reservation.

- Profile creation now requires the paired reservation to belong to the
  caller after the commit (`getAfter`), so atomic registration passes while
  lone, mismatched, or delete-smuggled profiles are denied.
- `ownsPublicId()` now checks profile AND reservation ownership, so even a
  planted pre-fix impostor profile grants no Hall access.
- Reservation and profile deletes of living rows wait for the Hall row
  (`hallGoneAfter`), so a freed ID can never be re-registered underneath a
  living Hall row; missing rows delete as no-ops so interrupted deletions
  resume instead of wedging.
- The checkpoint brace regex now says what it does: it bounds size and
  shape only and cannot parse JSON (`{bad}` clears it). Upload/queue paths reject
  non-JSON client-side with new tests; downloads still need the Journey
  validator. No server JSON parser exists to call.
- Client commit construction needed no change: registration already commits
  profile plus reservation atomically with `exists: false` on both, which
  is exactly what the `getAfter` rule expects.
- The splice builder's brace check tripped on the apostrophe in "caller's"
  (round 1 passed the same text by luck of pairing). It now strips comments
  and strings in one pass per line.

Emulator suite grew 20 to 32 cases: the director's probe verbatim, planted
resistance, atomic/mismatched/incomplete registration, final-state bypass,
restore, guarded/complete/idempotent deletion, and a rules-disabled control
showing the attack flips the score without enforcement.

## Round 3: atomic pair through registration and deletion (Brief 052)

The emulator ran 31/32: the `set profile + delete profile` same-batch
no-op succeeds (missing-row deletion contract) instead of failing as the
test expected. That expectation was wrong, not the rules: the batch nets to
nothing and creates nothing. It is now its own passing case asserting
success plus absence, and the real smuggle batch (set pair, delete
reservation) keeps its denial.

The round-2 rules still allowed lone reservations and single-half deletes,
so a kill between the client's sequential deletes could strand a profile
claiming a freed, re-registerable ID. Both halves are now coupled in both
directions: creation requires the counterpart after the commit (atomic
registration or nothing), and a living half deletes only with its
counterpart and the Hall row both gone after the commit. Hall writes check
ownership before AND after, so a write bundled with pair deletes cannot
orphan a row. The client deleter is one precondition-free four-delete
commit: all rows or none, idempotent to repeat, Auth only after
acknowledgement.

The suite is 37 cases with a genuine per-leg control: identical Hall writes
fail on lone halves and succeed once only the missing half is planted,
proving each ownership leg fires. A rules-disabled smoke test alone could
not prove that.
