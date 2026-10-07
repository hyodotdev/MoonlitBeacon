# Cloud rules emulator tests

Real enforcement tests for `firestore.rules` (legacy, untouched) plus
`firestore.cloud.addition.rules` (4.0.0 owned cloud). They run only against
the official Firebase rules emulator. Nothing here executes without it, and
the splice check below is source-only: it is not enforcement evidence.

## Dependencies (director supplies)

The implementer sandbox has no network, so these are not installed here:

- Java 21+ (current `firebase-tools` refuses to start the Firestore
  emulator below 21; a Java 17 default fails before the emulator
  starts): `java -version`
- `firebase-tools` (emulator)
- npm packages `firebase` and `@firebase/rules-unit-testing`

Measured versions: `firebase` 12.19.0,
`@firebase/rules-unit-testing` 5.0.2, `firebase-tools` 15.32.1.
The byte-current suite holds 88 tests in 14 suites, including the
attendance previous-claim chain transitions; the director runs the
emulator pass.

## Reproduce (temporary workspace; the repo lock stays untouched)

Do not `pnpm add` these into the repo: that rewrites the tracked
dependency lock. Instead copy the sources into an explicitly
temporary workspace, install there (the director runs this; network
is used here only), run the local emulator from that copy, and
delete it afterwards:

```bash
TMP="$(mktemp -d)"
mkdir -p "$TMP/work/tests/cloud-rules"
cp firebase.json firestore.indexes.json firestore.rules \
  firestore.cloud.addition.rules "$TMP/work/"
cp tests/cloud-rules/cloud-rules.test.mjs \
  tests/cloud-rules/build-combined-rules.mjs \
  "$TMP/work/tests/cloud-rules/"
cd "$TMP/work"
npm init -y
npm install firebase@12.19.0 @firebase/rules-unit-testing@5.0.2 firebase-tools@15.32.1
export JAVA_HOME="<a Java 21+ home for this process>"
export PATH="$JAVA_HOME/bin:$PATH"
java -version
./node_modules/.bin/firebase emulators:exec --only firestore \
  "node --test tests/cloud-rules/cloud-rules.test.mjs"
```

`JAVA_HOME` alone does not select the executable: the CLI spawns
`java` from `PATH`, so the selected home's `bin` directory must come
first or an older installed Java fails the run again. `java
-version` above must report the selected 21+ before the emulator
starts.

Expected: 88 tests, 14 suites, zero failures (legacy intact,
profiles, reservations, checkpoints, hall, attendance). The test builds the
combined ruleset in memory from the two copied rule files, so the
repo's `firestore.rules` itself is never edited. The run is local
only (`emulators:exec --only firestore`); nothing is deployed and
no production data is touched. Delete the temporary workspace when
done.

## Source-only splice check (not enforcement)

```bash
node tests/cloud-rules/build-combined-rules.mjs --check
node tests/cloud-rules/build-combined-rules.mjs --out /tmp/combined.rules
```

`--check` proves the addition splices mechanically before the catch-all with
balanced braces and all four new match blocks. It says nothing about what
the rules enforce. Only the emulator run above does.

## Negative controls

Three controls prove the suite can fail:

- `negative control: invalid writes always fail` attempts a Hall write with
  score -1 and requires denial. If the harness ever ran with the wrong
  ruleset (for example legacy-only, where the write would fail closed on
  the catch-all too, or a permissive draft), the control plus the positive
  owner-operation tests would disagree and the run would go red. To repeat
  by hand, change `-1` to a valid score and watch that case fail.
- `negative control: takeover works only without enforcement` reruns the
  takeover with rules disabled and requires the score to flip to 11. That
  proves the attack steps are executable, so the takeover suite's denials
  come from the rules, not from broken setup.
- `control: each ownership leg decides identical Hall writes` plants lone
  halves (profile-only, reservation-only), requires the identical Hall
  write to fail for each, then completes each pair and requires the same
  write to succeed. Only the guarded fact changes, so this proves each
  ownership leg actually fires — a rules-disabled smoke test alone could
  not show that.

## What the suite covers (84 cases)

- Legacy `/scores` public read plus valid create, invalid hero denied.
- Legacy `/analytics_events_v1` valid create, reads denied.
- Unknown collections denied for authenticated users.
- Profiles: unauthenticated denied, owner create/get/delete, cross-owner
  denied, list denied, ID reassignment denied (updates denied entirely).
  Creation requires the paired reservation after the commit; a living row
  goes only with its pair half.
- Reservations: atomic-pair creation only (lone reservations denied),
  stranger read/takeover denied, updates denied, living rows never go
  alone.
- Takeover: the director's probe verbatim (impostor profile + Hall
  overwrite/delete of score 10 denied, score untouched), a planted
  pre-fix impostor profile granting no Hall access, and an orphaned
  profile with no reservation granting none either.
- Registration pairs: atomic batch registration + Hall submit, mismatched
  batches in both directions acquiring nothing, lone halves denied on
  both sides, same-batch reservation delete smuggling nothing, the
  harmless set/delete no-op succeeding with no new document,
  canonical-ID restore.
- Deletion: pair halves blocked while the Hall row lives, living halves
  going only together, complete account deletion as one atomic commit
  freeing the ID for clean re-registration, repeated deletion
  idempotent, Hall rewrite bundled with pair deletes denied.
- Checkpoints: unauthenticated and cross-owner denied, revision must start
  at 1 and advance by exactly 1, oversized/non-brace/extra-field payloads
  denied, brace-shaped-but-invalid JSON honestly passing the rules (the
  client parses instead), owner delete allowed.
- Hall: public get/list, anonymous writes denied, writes need the matching
  profile AND reservation before and after the commit, invalid hero and
  extra fields denied, scores monotonic with equal-score retry allowed,
  cycles bounded 0..99999 (the Journey cap), cross-owner write/delete
  denied, owner delete allowed, public row keys contain no UID, email,
  save, or credential.
- Names: atomic two-half claim, one concurrent winner, mixed-case Latin
  collision, Korean/Japanese round-trip, shared invalid matrix, private
  row unreadable/unwritable by others, index exposing handle and public
  ID only, unauthenticated denied. The proven owner reads an
  authoritative missing row; other owners, the unregistered, and lists
  stay denied.
- Adventurer metadata: immutable except the intro bit false to true,
  arbitrary fields denied.
- Hall display: claimed handle only, forged/unclaimed/malformed/another
  player's denied, backfill at the same score, downgrades denied, legacy
  unnamed rows untouched.
- Name deletion: lone halves denied, halves blocked under a living Hall
  row, name-only release denied under a living canonical pair, Hall-plus
  halves without the pair denied, canonical halves blocked while the
  name pair stays, missing-row no-ops allowed, full named deletion (with
  or without a Hall row) completing and freeing the name exactly once,
  legacy unnamed deletion unchanged.
- Attendance: owner first claim with a server stamp, authoritative
  missing-row owner read, strangers/unregistered/lists/anonymous denied,
  forged past/future/missing stamps denied, unregistered and stranger
  claims denied, seeded 13h-old row claims for a new install, 11h-old
  row holds, exactly 12h eligible, canonical halves immutable, one
  winner per concurrent update race and first-claim race, living row
  never deletes alone, pair halves blocked while attendance stays,
  full deletion removing attended accounts, never-attended deletion
  unchanged.
