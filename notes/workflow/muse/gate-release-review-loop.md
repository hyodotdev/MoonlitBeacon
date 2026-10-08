# Gate lodge 4.0.1 release review loop

User authorization includes review, PR, push, main merge, both-store
deployment and review submission. Existing marketing screenshots are
retained. Branch: codex/gate-chamber-and-defeat-rules.

## Round 1: actual store and entry boundaries

The read-only store probe found iOS 4.0.0 build 14 ready for distribution
and Play 4.0.0 code 19 published on internal and production. This requires
a new patch display version, selected as 4.0.1 / iOS 15 / Android 20.
The older approved version is not canceled or changed.

Confirmed findings sent to brief 231:

- Generated Apple review instructions omit the new Lumi/name room.
- The Play retained-gallery binary-only planner refuses a newer display
  version even with a strictly newer artifact code.
- The privacy inventory predates nickname and attendance records.

Director remote privacy readback then confirmed Name was optional in Play
while the new normal online lodge requires naming. Official guidance and
the production form/host show the local-only failure escape is not an
all-user opt-out. Name was saved as required for the coming review;
email remains optional, User IDs already required. No review submission
has happened. Brief 232 supplies this correction to the implementer.
Apple's existing linked App Functionality identifier/name/gameplay labels
already cover these data types; no Apple form mutation was made.

Operational proof files are under builds/verify/gate-4-0-1-* and
gate-release-live-initial.json. The prior comprehensive core review is
recorded in gate-chamber-review.md. New release preparation remains under
independent review; no acceptance, PR, main merge or binary upload yet.

## Device evidence boundaries

Android Wi-Fi endpoint connects and reports SM-F731N. The device is dozing;
the first current screenshot is black. A human unlock/unfold request is
pending. The installed code 19 has no Play installer, so it is not proof
of Play purchase E2E. iPad mini A17 Pro remains available and paired.
Prior final isolated iPad title rendering and emulator name/reward/native
reminder proofs remain historical, not fresh physical purchase evidence.

## Storage operation

Closed accepted-copy regenerable caches were removed after dry run and
open-handle checks. Byte-identical closed-copy marketing PNGs were then
converted to APFS copy-on-write clones: 4610 files, 9485792626 logical
bytes, no canonical image modified and no file removed. Hash, mode and
native timestamps were checked; the first failed attempt's one timestamp
was restored within 0.001 ms. Exact receipts are under builds/cleanup/.
Source, Git history, signing material, SDKs, original art, final artifacts
and device backups were preserved. Available space became about 10 GiB.

## Release preparation corrections and independent review

Briefs 231–233 were judged and accepted from the implementer's copy.
The exact six protected export-preset edits were read twice: both Android
names/codes become 4.0.1/20 and iOS short/build versions become 4.0.1/15.
Package, team, engine, renderer, controls, signing and all other preset
bytes remain unchanged. The public reference and ten release-note blocks
now condition lodge skipping on a completed guide; interrupted practice
returns to Lumi. CLI help describes the retained-gallery path neutrally.

| Round | New angle and measured evidence | Finding |
| --- | --- | --- |
| 2 | Actual Play Name/User-ID form, source name form and lesson bit, semantic parser inputs, 500-character destination | Name incorrectly optional in inventory; incomplete guide incorrectly skipped; leading-zero versions accepted; Play paragraph too long. Corrected by brief 232. |
| 3 | Remaining ten release blocks, current public reference, operator CLI help | Returning-guide prose and current counters still stale. Corrected by brief 233. |
| 4 | Cumulative 15-file diff; 179 App Store/Play tests independently passed; five director fault injections and byte-exact restoration | No further correction. Broken malformed-version, downgrade, note-digest, lodge-guidance and identity guards each exited 1; restored checks each exited 0. |

Actual product names produce Apple review notes of 3930 characters / 3934
UTF-8 bytes, ten sale IAPs. The Play paragraph is 417/500 characters and
was saved in the actual console; it remains ready for review, not submitted.
Existing premium-access settings and product definitions were not changed.
Fresh Apple GET plus public lookup confirms 4.0.0 is READY_FOR_SALE and
publicly available; the new patch does not cancel or release the older one.

The retained published Play-19 package was operationally derived only after
its APPLIED receipt, signed AAB and both live track identities matched.
All 122 nonbinary payload files remain byte-identical; no fresh capture or
remote mutation is claimed by that operation. Canonical `stores/` has no
diff from main. The separate capture check still reports the historical
permanent-file inventory mismatch; existing images stay untouched under
the user's explicit reuse instruction.

The existing user instruction, “이번에는 미완료 결제 검증을 생략하고
심사 제출까지 진행”, remains the purchase-validation exception for this
ongoing submission. Actual purchases are not claimed. Artifact, product,
receipt and game-logic validation still applies. Physical iPad native IME,
notification permission and twelve-hour delivery remain unobserved.

Android is connected at the user-supplied endpoint and a normal wake action
now shows its main home screen, so the earlier black capture was dozing,
not evidence of a game defect. Before updating, its files/shared preferences
were backed up locally at mode 600: 61 tar entries, 1998336 bytes, SHA-256
3f19b467a6107b154849a2c31b858bb62ec65f986145b2a186101e04e42a08eb.
No app data was deleted; no arbitrary name was assigned to its real account.

| Round | New angle and measured evidence | Finding |
| --- | --- | --- |
| 5 | Accepted real tree `pnpm verify` exited 0; all Node/Godot suites, 419 manifest assets, 271 custom contracts, native export/privacy tests, five locales, deterministic graphics, skill parity, repo hygiene, 26 docs and all internal anchors | No further correction. Lodge 2850/0 failed, reminders 1441/0 failed, production host 1353 cases passed. The source review loop has two consecutive clean rounds; subsequent device/artifact/CI checks remain required before merge and submission. |

Final root verification log: `builds/verify/gate-4-0-1-root-verify.log`.
The lodge log's three contact-review FAIL lines are deliberate oversized
and missing-silhouette fixtures at `test_gate_lodge.gd:632-647`; the
registered suite explicitly requires those audit rejections. They are
also present in the previous passing full verification. No runtime smoke
failure is inferred from those negative controls.
