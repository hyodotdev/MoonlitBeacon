# Gate chamber director review

Branch: `codex/gate-chamber-and-defeat-rules`.
Baseline: fast-forward-checked main `1ed5fb1` on 2026-10-07.

## Baseline measurements

- Journey: 499 cases with `pnpm godot:isolated --timeout 180 res://tests/test_journey.tscn`.
- Cloud identity: 54 cases with `pnpm godot:isolated --timeout 120 --script res://tests/test_cloud_identity.gd`.
- Real combined Firestore rules emulator: 38 tests, nine suites, zero failures. Proof: `builds/verify/gate-chamber-cloud-baseline.log`.
- Existing hero raster baseline: 100 PNG hashes in `builds/verify/gate-chamber-existing-hero-hashes.json`.

## Initial defeat implementation findings

Two independent isolated operational probes failed against the initial
implementation, before acceptance:

1. Real defeat writer followed by corruption of the primary save recovered
   the prior alive backup. `free_resume: true`, `recovered_ended: false`,
   checkpoint 2. Proof: `builds/verify/gate-defeat-probe/result.log`.
2. The stable-checkpoint hook observed a resumable alive payload while the
   coin balance was still 2. Blocking the wallet temp write and the ensuing
   checkpoint rollback made `continue_run()` return false while preserving
   a resumable checkpoint and the unchanged balance. Proof:
   `builds/verify/gate-defeat-probe/paid-result.log`.

Correction brief: `briefs/203-protect-defeat-and-paid-continue-crash-boundaries.md`.
The initial implementation is not accepted. Final results will be recorded
after the correction and lodge integration are independently checked.

The director independently ran the initial registered suites: defeat 95,
Journey 519, coordinator 1167 and production host 804 cases, all exit 0.
These passing suites miss the two reproduced persistence boundaries above.

During brief 203, an independent journal/account probe reproduced another
boundary: acknowledge account A's paid seal, reload the wallet, switch to an
empty B slot, then `recover_paid_continue()`. It imported A's alive run into
B and erased A's pending journal. Proof: `builds/verify/gate-defeat-probe/account-result.log`,
exit 1, `wrong_account_import: true`, `journal_retained: false`, balance 1.
Correction brief 206 binds recoverable payment to its owning account/slot
and covers independent pending attempts under two accounts.

Another production-button probe confirms that a journaled last-coin debit
with failed alive-seal install routes the result's continue tap to purchase
instead of retry. The isolated signal probe now exits cleanly with no Godot
ERROR: balance 0, pending journal true, purchase true, continue false.
Proof: `builds/verify/gate-defeat-probe/last-coin-result.log`. Brief 206 also
requires this already-paid attempt to remain retryable at zero balance.

The initial two director probes now pass against the in-progress 203 code:
`terminal-round2.log` reports `free_resume: false`, `recovered_ended: true`;
`paid-round2.log` observes balance 1 at the alive stable hook and returns
a paid resumable checkpoint with balance 1. Both exit 0. These are targeted
boundary passes, not cumulative acceptance or a native-device check.

## Art inputs

Lumi's four-facing source and the warm lodge room were generated with
imagegen. Prompts and original PNG copies are in `art/gate-chamber/`.
Runtime packing and scene integration belong to the implementer. Marketing
screenshots and previously submitted store binaries remain untouched.

## Additional user scope

During the correction run, the user requested two attendance continue coins
each half day, half-day reminders explaining that coins are ready, and a
Settings opt-out. The director stated the rolling twelve-hour interpretation:
two on an eligible foreground visit, no repeated grant from relaunch or a
notification tap. Brief 204 supplies server eligibility and durable grants;
brief 205 supplies actual Android/iOS local reminders and persistent opt-out.
The native permission request belongs to an explicit in-app enable action,
without interrupting account naming or the guide lesson.

Connected-device inventory on this task: Android SM-F731N available; iPad
mini A17 Pro available/paired. No new physical gameplay or notification
verification has been performed yet.

Pixel_10 was booted with host GPU, port 5554 and snapshot saving disabled.
Its existing owner user and installed game remain untouched; an isolated
test-user flow will be used later. Native bridge prerequisites were found
in the preserved `builds/verify/native042-deps/` toolchain and both Android
and iOS debug build dry-runs pass with those explicit paths. No dependencies
were installed. The generic strict provider preflight is red solely for
the optional Play Games application ID, as previously documented; Android
Google/Apple and iOS Google/Apple report READY. No new native binary has
been built yet.
## Canonical journal adoption fault found during round 3

Round 4 independently found a remaining target-priority hole: `target-pending-round4.log` exercises the actual coordinator with a canonical target's paid journal/no surviving files and a different living source with no source journal. The new preflight returns early on no source receipt, imports the source, then discards the target's acknowledged one-coin receipt as stale. Exit 1; paid target `d1` replaced by `d1-other`, receipt removed, source file moved, balance still 1. Brief 201 now includes this confirmed account-preservation prerequisite and registered production-route cases before nickname integration. The cumulative diff remains unaccepted.

Actual REST baseline independently passed: `builds/verify/gate-chamber-rest-baseline.log`. A guarded synthetic JWT/HTTP sender runs the unmodified GDScript CloudTransport + CloudIdentity through localhost Firestore only: profile GET 404, atomic canonical-ID commit 200, owner reload GET 200. The helper and probe live only in ignored `builds/verify/gate-chamber-cloud-emulator/`, refuse all non-emulator destinations, clean emulated rows afterward, and never read real tokens. Reuse this boundary for actual Unicode nickname and attendance REST checks.

Android emulator operational isolation: the existing `Pixel_10` emulator on `emulator-5554` retains Owner/user 0 untouched. `pm create-user MoonlitQA` created user 10 for later native/login/name/reward QA; no switch, app data clear, replacement install or launch has occurred yet. Remove this QA user and restore user 0 after testing. Physical Android and iPad data remain untouched.

An independent operational probe at `builds/verify/gate-defeat-probe/rekey-round3.log` confirmed that a real Vault temp-file failure lets `CloudCoordinator._move_slot_to_canonical()` move both account files and adopt the canonical ID while ignoring a failed journal rekey. After reload, the one-coin receipt remains owned by the old guest slot (now empty), and recovery under the adopted ID defers permanently. Exit 1; no human account/storage was touched. Brief 207 requests recovery across this joint file/journal boundary before the name service begins.

The corrected canonical rekey probe now passes: `rekey-final-round4.log`,
exit 0, deferred adoption reports `slot-move-failed`, then retry after the
real wallet temp-path fault clears restores the paid seal under canonical
C with balance 1. This does not waive the separately confirmed target
priority defect assigned to brief 201.

Director negative controls completed while the implementer was idle.
Bypassing the terminal mirror guard makes `terminal-negative-control.log`
exit 1 (corrupt primary recovers a living backup); exact-byte restoration
makes `terminal-restored-control.log` exit 0. The operational probe omits
an intervening read, since a production read also heals the terminal
backup and would mask this specific writer control. Skipping the actual
`begin_continue_txn` debit makes `debit-negative-control.log` exit 1;
exact-byte restoration makes `debit-restored-control.log` exit 0. Both
product files were restored in a `finally` block and compared byte-for-byte.
No permanent product edits were authored by the director. Brief 201 is
running as cumulative round 5; no change has been accepted or deployed.

## Independent name boundaries during round 5

The actual client/emulator probe in `gate-chamber-names-preliminary.log`
fails after canonical registration: new adventurer GETs return 403 because
the rule reads a missing row's `resource.data.uid`. Independent SDK probe
`gate-name-rule-boundaries-preliminary.log` also fails and demonstrates
that deleting only the name/adventurer pair succeeds while the canonical
profile remains. The token-wait recorder probe executes the production
claim wrapper unchanged and calls account B with account A's `Alpha`
request after the coordinator changes (`name-token-switch-preliminary.log`,
exit 1). These three confirmed boundaries are assigned to correction 208.
The current production Hall mapper also drops `display`, so real name
presentation is included in that correction instead of claiming payload
fields alone as a finished Hall.

The separate low-level writer probe (`gate-name-writer-preliminary.log`)
passes: Korean raw document IDs commit/reload, URI-encoded index GET works,
intro completion succeeds, and full six-row deletion succeeds. Competing
real writers receive 409 ALREADY_EXISTS. This isolates the first-read and
partial-release defects without dismissing the working atomic writer.
No real Firebase rows, tokens or user saves were touched.

The actual coordinator REST restore probe
(`gate-name-restore-preliminary.log`, exit 1) confirms a fourth name defect:
completion caches true, but restoring the same existing immutable name
returns no `intro_complete` field and overwrites the durable cache to false.
Reload retains false although the server remains complete. Correction 208
also requires returning the real bit and monotonically preserving it under
older same-name replies. Registered pure name-service tests independently
pass 129 cases (`gate-name-client-preliminary.log`); those cases alone
miss these integration/enforcement boundaries.

The faithful 4:3 tablet room plate and prompt add two source inputs, bringing
the protected raw art set to six files; `gate-chamber-art-source-hashes.json`
confirms all root/copy bytes match. The wide and tablet backgrounds keep
both registry and gate in frame without stretching the environment.

Second cache cleanup removed 149 regenerable directories from closed
implementer copies, preserving source/Git/reports/media and the active tag.
Receipt `builds/cleanup/20261007/closed-cache-second-applied.json` records
the exact paths; available space became about 7.1 GiB. Existing package
outputs and native toolchains were preserved.

Round 5 preservation checks independently pass. `target-pending-round5.log`
restores canonical `d1` from its acknowledged paid journal, keeps the
unrelated guest source file and leaves one coin. `rekey-round5.log` holds
the failed wallet rekey, then recovers the paid canonical seal after retry.
Both director scenes exit 0 in about three seconds under isolated saves.

Further disk pressure required removing 85 extracted-video frame caches
(source movies, contact sheets and 634 hashed proof files retained) and five
obsolete development build products. Exact receipts are
`builds/cleanup/20261007/extracted-frames-applied.json` and
`old-debug-products-applied.json`. Current release packages, native toolchain,
source/Git, credentials and the active implementer copy are unchanged.

An independent reverse partial-deletion SDK probe passes in the local
emulator: removing only the canonical profile/reservation with the name
pair present is denied; the public name remains. See
`gate-name-orphan-preliminary.log`, exit 0. Correction 208 must preserve
this already-working guard while denying the confirmed opposite
name-only pair release under the living account.

Round 5 returned after 67.8 minutes, exit 0. The director independently
ran the registered production-host scene: 1,013 cases pass, exit 0 after
36.9 seconds (`gate-name-host-independent-round5.log`). This does not
override the four confirmed real REST/token/cache failures or the dropped
Hall display/HUD call. Sent correction 208 as round 6; no product accepted.

A closed diagnostic copy's Git objects were repacked without pruning
unreachable history; HEAD remained `f444bad3a91f56e18f8614c82f73c627a06e802d`
and `fsck --no-reflogs` exited 0. It saved only about 10 MiB, so no broader
repack sweep is justified. Source, branches and dangling commit remain.

The actual round-5 registered rules emulator ran 62 tests: 60 passed, two
failed. Both failures are the already-confirmed missing-owner adventurer
GET (`mismatched pair halves acquire nothing` and the losing concurrent
claimer's read), not a new independent defect. Full log:
`gate-name-rules-registered-round5.log`. All preceding legacy suites pass.

Persistent disk pressure was resolved by sharing 40,207 byte-identical
immutable loose Git objects among 15 closed October 5 implementer copies.
Each target's raw SHA-256 matched the source; the inflated canonical Git
SHA-1 matched its object path. Every path/object was retained, all HEADs
stayed identical and all 15 `git fsck --no-reflogs` commands exited 0.
Receipt `builds/cleanup/20261007/git-object-sharing-applied.json` records
the operation and about 5.94 GiB less duplicate storage. The current run
and real checkout were excluded; no source or Git history was removed.

During round 6, the independent real begin-deletion token barrier finds
one remaining shared-operation boundary. With UID/coordinator A unchanged,
`delete_current_account()` sets its real pending ticket; releasing the
parked claim then calls A with `Alpha` and returns ok. The probe holds only
the deletion body's remote latency, performs no native/cloud deletion, and
exits 1 in 2.5 seconds (`name-token-deletion-round6.log`). Brief 204 includes
this small prerequisite: both name and attendance calls must capture the
deletion lifetime and cancel during/after that retired operation. A test
that merely calls `_retire_coordinator` misses the actual pending request.

Round-6 independent production REST probes now all pass: fresh Unicode
claims and concurrent collision (`gate-name-rest-round6.log`), authoritative
missing-owner read and denied name-only release (`gate-name-boundaries-round6.log`),
true completion retained through actual coordinator/Vault reload
(`gate-name-restore-round6.log`), and original atomic writer/full six-row
delete (`gate-name-writer-round6.log`). Summary `gate-name-probes-round6-summary.log`
exits 0. The unchanged production token-switch recorder also exits 0,
returns `cancelled/account-retired` and dispatches nothing to B. Pending
begin-deletion is still the separately confirmed prerequisite for 204.

Round 6 completed in 38.0 minutes, exit 0. Independent final registered
checks: rules 69/69, production host 1,085, cloud name 137 and Vault 282
functional cases pass. Vault's registered entry is `--script test_vault.gd`,
not a scene; it prints two resource-cleanup warnings after passing (the
cumulative full runner will settle whether those are gate failures).

The director rendered 10 valid maximum-length Korean/Japanese-name states
through the actual production mapper, Hall panel and title Rank-button
route, at five locales and 808×360 / 808×606. The first operational harness
called the Hall handler directly, bypassing the title's normal parking;
that artificial logo overlap is not a product defect. Calling the real
title `_open_ladder()` hides the title correctly. Corrected PNGs use
`gate-hall-name-{locale}-{height}.png`; long handles fit and IDs remain
separate, with ordinary list scrolling for lower rows.

Independent negative control: temporarily forcing `_name_ticket_live` true
reproduces real B dispatch (`name-ticket-negative-control.log`, exit 1,
`account_b_calls:["Alpha"]`). Exact-byte restoration is SHA-256 verified;
the original probe then cancels with no B call, exit 0
(`name-ticket-restored-control.log`). No product file remains mutated.

Proceed to attendance brief 204 in the same cumulative copy, including
the confirmed actual pending-deletion prerequisite. No product accepted,
no live backend/site/store deployed, no push or PR.

## Shared deletion boundary checked during attendance round

The exact operational production-name/pending-delete probe now passes
against round 7: builds/verify/gate-defeat-probe/name-token-deletion-round7.log,
exit 0 after 1.6 seconds, no claim dispatched while the actual deletion
wrapper holds a nonempty ticket. The independently executed registered
production-host suite passes 1111 cases, exit 0 after 32.8 seconds
(builds/verify/gate-name-host-independent-round7.log). This closes the
confirmed prerequisite; attendance implementation is still running.
All 100 baseline hero PNG hashes still match the cumulative copy.

Android native baseline compilation succeeds from existing cached tools:
builds/verify/gate-native-android-baseline.log. The first real iOS build
exposed a missing explicit FIREBASE_PODS_DIR setting despite a successful
default-path dry-run; retry uses the preserved Pods without SDK reinstall.
Reminder code is not yet implemented or tested. Pixel_10 restarted with
host GPU and owner data retained. MoonlitQA/user 10 was created without
switch, install, data clear or launch. Physical device data is untouched.

## Attendance independent measurements and correction required

The 84 registered real Firestore rules tests in 14 suites pass with zero
failures (gate-attendance-rules-registered-round7.log); the 62 attendance
service cases pass independently (gate-attendance-service-independent-round7.log).
Actual GDScript client REST probe passes first owner batchGet absence,
first conditional server-timestamp claim, same-install reload, other-install
hold, stranger denial, no standalone reset deletion and one concurrent
claim winner (gate-attendance-rest-correct-route-round7.log). The initial
operational DELETE probe omitted documents/ and was corrected; its 404 was
a harness path error, not a production-rule defect.

Two isolated actual-Vault/coordinator probes still fail: ten owner claims
inside ten minutes evict the first receipt and owner mark, so replay after
reload increases 27 to 29 (attendance-pruned-owner-round7.log, exit 1);
an acknowledged failed wallet grant followed by restart thirteen hours later
is overwritten by the next claim and yields balance 4 instead of 6
(attendance-expired-recovery-round7.log, exit 1). Correction brief 209 is
prepared; round 7 is still active and no cumulative change is accepted.
The expiry probe initially had an invalid computed GDScript const; the
operational script was corrected before the clean reproduced failure.

Actual attendance-wrapper pending-deletion barrier passes independently
(attendance-token-deletion-round7.log, exit 0 after 1.9 seconds). Director
editor import succeeds in the normal environment, exit 0 after 4.8 seconds.
The implementer used grep/head pipelines for some reported suite runs;
the director will use true exits and full logs for acceptance.

Both baseline native identity targets now compile, with explicit cached
Pods environment for iOS (gate-native-ios-baseline-complete-env.log).
All 18 SDK privacy resources remain byte-identical. No reminder code or
physical notification verification exists yet. Original emulator Owner APK
is backed up and hash-pinned in gate-emulator-owner-original-proof.json for
restoration after QA-user testing. No emulator app install/launch yet.
Fresh fetch still finds HEAD and origin/main at 1ed5fb1a9b2798a0b76095e942d4fa5552efd2d0.

## Attendance correction round 8 — director observations

- Actual isolated Vault ten-owner pruning replay now exits 0; balance 27→27, purchased receipt retained.
- Actual Coordinator server-ACK/local-wallet failure, restart after 13h, recovery then new claim now exits 0; balance 2→6.
- Round 7 actual CloudAccount REST deletion was independently denied because client omitted attendance; correction 209 covers named/unnamed payloads, expanded emulator probe awaits completed patch.
- New actual Coordinator probe attendance-pruned-return exits 1: a previously paid evicted owner returns after 13h and terminal ambiguity prevents any new claim (22→22, expected24). Added this small confirmed integration correction to brief 202; old forgotten receipts must remain unpaid while a new conditional period can progress. No product code hand-edited.

- Round 8 real GDScript REST + combined Firestore emulator: all 14 checks pass; named deletion includes 7 rows, unnamed includes5; race exactlyonewinner; anotherinstall cannot receive current grant; standalone reset denied. Full log gate-attendance-rest-delete-round8.log.
- Round 8 dedicated seeded 13h-old server row: actual service conditional advance preserves opaque millisecond stamp; old receiving install recovers only its 2 earned coins from carried previous row; second retry is idempotent, foreign current period remains uncredited (2→4→4). Full log gate-attendance-rest-advance-round8.log exits0. Fixtures are emulator-only, never actual Auth/store/user wallet.

- Round 8 final refreshed combined rules + SDK suite: 88 tests/14 suites all pass (6.57s, true emulator exit0). Actual Coordinator scene1218cases/2.9s and ProductionHost scene1288cases/32.4s independently pass with clean raw logs. CloudAccount56cases clean; attendance86assertions pass but malformed-prev stamp emits engineERROR; assigned precise parser correction to202. An early --script invocation of Node-based Coordinator was wrong and explicitly renamed diagnostic; the actual scene run is the evidence.
- Round8 completed28min exit0; no accept because evicted-return future eligibility and parser diagnostic remain, plus playable lodge/native reminders. Round9 brief202 started11:12UTC with all previous APIs/proofs.

- Round9 returned successful empty terminal text, no tools/diff/report; stderr contains no approval/classifier refusal. Normal unchanged continuation retried once as round10; meaningful edits now running. No fresh-session/sandbox/config bypass.
- Round10 actual Coordinator attendance-pruned-return probe independently exits0:22→24, old ambiguous receipt skipped (unpaid), genuinely new eligible commit proceeds. Full raw log attendance-pruned-return-round10.log. The prior crossowner replay and purchase preservation contract remains intact.

- Round10 actual attendance service now91cases, clean full raw log, exit0/1.5s; malformed timestamp boundary no longer emits engine ERROR.
- Lodge review pending while actor builds: verify actual first native guest/provider login enters the lodge naturally after restore, and that users need not accidentally request a new expedition just to reach setup. Current partial Entry diff detours plan_entry(needs_lodge); judge completed UI route rather than partial code. Verify direct host plans reject unsettled named/intro state, cache-complete offline behavior, save bytes through room, and Mini1.52 keyboard layout.

- Round10 packed lodge art director check exits0:7outputs byte-current, Lumi four facing heights853/850/851/852, spread0.0035, common crop/scale/foot line. Runtime presentation still pending. All100existingheroPNG SHA hashes independently unchanged after packing new art.

- Pending Lumi runtime judgment: partial lumi_guide.gd currently bobs the WHOLE Sprite vertically±2px while foot_local() reports node origin. That report alone is not foot evidence; rendered alpha/shadow contact must be measured through idle at both ratios. Brief requires grounded planted feet and fixedcommonfoot; send a confirmed visual correction if the completed scene still moves boots off the floor. Also check banned-term variable in final hygiene. Do not judge incomplete art/layout as final.

  Clarification before any correction: Lumi bob is 2SPRITE-local source pixels, not necessarily2worldpixels. If room sets WORLD_HEIGHT/FRAME_HEIGHT scale≈0.11, actual bob is±0.22worldpx and may be visually stable. Measure completed rendered boots/shadow; do not infer a visible floating defect from unscaled source arithmetic or foot_local() alone.

- Partial layout arithmetic to verify after self-checks: GateLodge.layout_for returns actor_scale1 at808360/808606; _lumi.scale is assigned directly. Lumi sprite source height869 and WORLD_HEIGHT96 constant has not yet been used in the partial script. Actual rendered scene must prove final source-to-world scaling (NPC should not render869px) before attributing source-local bob amplitude. At widerviewport906360 actor_scale≈1.12; keep NPC/hero relative/worldscale consistent as brief requires. These are pending incomplete-code observations, not accepted findings.

- Early independent actual lodge windowed probe encountered current in-progress dash() arity parser error; Godot then rendered scene nodes without the controller. That869px measurement/image is NOT valid production controller evidence. Ignore partialPNG; operational probe now aborts if controller fails to load. Wait actor self-checks then rerun exact scale/foot proof with clean full diagnostics. No product edits.

- After partial dash arity repair, real controller now loads with no SCRIPT ERROR. Independent windowed scale probe cleanexit1:808360NPC frameheight871.15, sprite_scale1 and node_scale1.002475. Screenshot also shows a huge empty-looking speech panel covering characters; need actual panel/body globalbounds diagnostic (probe prepared) and completed actor QA. This is actual current rendered evidence; ask for correction only if actor self-checks do not close it.

## Lodge round10–12 director decisions

- Round10 finished63.3min exit0. Actual registered lodge542cases independently pass clean5.1s, but this alone missed rendering. Real windowed post-seat-fix probe cleanexit1: frame871.151worldpx, node1.002475/sprite1; screenshotgiantboot. Speech seating fixedwithinviewport(P124,231/S560,117), actualKoreanspeakertranslatescorrectly. Raw speaker.text remainskey by GodotControl auto-translation; not a literal-visible-key defect.
- Actual cold-completed scene probe exits1 in round10: cloud response intro_complete=true/cached=true changes host needs_lodge false, yet scene staysGREET1 with named-practice speech insteadDEPART7. Returning living save offeredonlyafterrepeatedpractice. Brief210 covers this boundary and actualNPCscale/contact/harness semantic gaps.
- Round11 finished13.5min exit0; report lodge624/validate347. Actual cold-completed probe rerun independently exits0/1.9s: stateDEPART7, hostlessonfalse, living summary preserved. Guideworldheight now42.104 at808360, source-to-worldcommonNodeScale0.048451. Final actual windowed image shows correctly sized guide and original hero, original100PNG remainunchanged.
- New actual idle foot proof, not root-origin math: invoke real guide idle quarter/three-quarter phases under productiontransform. Bodybottom (therefore every unchanged opaque boot pixel) moves4.0worldpx peak-to-peak while shadow/root stayplanted. Report's planted node anchor is insufficient. Exact raw gate-lodge-scale-and-foot-mid-round11.log exits1 with sizepassed=true/footpassed=false. Brief211 startsround12 on this boundedmotion correction; native205 remainsnotstarted. ActiveMusePTY3837 (prior83100/92743 finished). No productaccept/commit/push/stores.
- Desktop actual nameform KO808360 captured gate-lodge-room-round10/room-808x360-ko-name.png. Fieldroughlyy136–184, confirmation229–275. No nativekeyboard on Mac: not IME-pass. Native205 nowrequests realkeyboardheight/field/action diagnostics and boundedkeyboard-aware adjustment ifneeded; don'tclaimphysicalfailurewithoutmeasurement.
- Native205 alsoclarifiescoldnotificationlaunchTitle vswarmprocesssafelyresuminglivinggame; neither action auto-fresh nor directlyclaims/spendscoins.
- Diskpressurecleanupverified549files of9closediPad capture frozen-app expansionsbyteidenticalagainstpreservedZIPs. Removedonlyexpandedfrozenfolders, all9exactZIPsandallgallery/proofs/logs preserved. Dry/applyreceiptsbuilds/cleanup/20261007/frozen-app-zip-*.json; free3.1→4.8GiB. CurrentiPadstillavailablepaired/Androidphysical+emulator5554connected. Nootherrepo/cachesdeleted.
- Round12 finished2.8min; director actualwindowed scale+idleprobe cleanexit0/2.6s:42.104worldpx, bodyfootspan0.0. Actual registeredlodge652checks cleanexit0/5.5s; noengine/scriptERROR innormalenv (onlyknowncamera warning). Feetfixclosed. Muse13/native205 started; activePTY67584.
- Director operational actualscene matrix uses productionpackedlodge + inheritedQAhelper/injectedsyntheticHost, livingSave fordeparture, actualWindow resolution, checksactualstate+panel/guidebounds, fullrawdiagnostics. 90combinations cleanpass across808360/880360/808606/808532 and5locales×5states (lastMiniChinese9remaining). Case91 haltedstrictly onin-progressNative13 ProductionHost parseerrors despiteGodotexit0; screenshotitself stillscene1/0auditfails, not an actual finalNative defect. Matrixselectedroomsourcehashesunchanged; newHostpartiallyedited duringcapture. Resume last10afterActor13 imports/stability, notfalse100pass. Logs/PNG/metricsbuilds/verify/gate-lodge-room-round12; batchscript render-matrix.mjs/probe room-audit.gd/.tscn areignoredmeasurementoperations. ENname,JAdeparture,ZH_TWgreet visuallyreviewedfit. NativeSamsungconfirmedphysical1080×2640 =>880×360logic.
- Six closed director-probe Git stores now share14,397 byte-identical immutable loose objects with a closed canonical snapshot. EverycompressedSHA256 and inflatedGitOID verified before sharing; allpaths/refs/HEAD retained, sixfullfsck exit0. No root/currentcopy/source/media/SDK removed. Logical2.273GB duplicate data; actualfree3.2→5.2GiB. Receiptsbuilds/cleanup/20261007/closed-probe-git-sharing-{dry-run,applied}.json.
- Native13 partial reminder controller had MIN_FIRST_DELAY_SECONDS60; verify completed behavior at a genuine deadline30–59seconds away, so near-boundary settings enable does not permanentlycancel ALLfuture reminders. This is a pending in-progress inspection point, not yet a confirmed completed defect; native tests/source may change.
- Actual clean round12 wider880×360 greeting screenshot shows initialhero's lowerbody overlappedbybottomspeechcard. Consider a bounded final scene layout correction if stillpresent afterNative13 keyboardlayout: initialrealplayer should remain fullyvisibleonfloor abovegreetingcard, without changingheroart/worldscale. Tabletname/departure, ENname, JAdeparture andZHTWgreeting visuallyfit. Do notcalloldAvatarart inconsistentbasedonocclusion.

## Native reminder boundary, director round13
- Actual Android Gradle compile exits1: owned drawable not copied into generated project; chained builder error. Actual iOS SCons compile exits1: Objective-C reminder methods outside implementation and no interface selectors (18 errors). Controller thirty-second future deadline probe clean exit1 with zero schedule calls. Brief212 correction started as Muse round14.
- Actual Korean Settings808x360, Analytics unconfigured: screenshot and all visible bounds pass; actual denial label is legible. No native permission/notification claim yet.
- Director hero-occlusion probe first used wrong Sprite node name and timed out; corrected to actual Player/Sprite. Clean actual controller render shows opaque player y209.1428..236.9378 versus speech starting231: 5.938px covered. Brief214 prepared.
- iOS source actually schedules first at eligibility and repeat from current time, producing duplicate first/repeat around fresh reward and shortened initial gap on halfway enable. Brief213 prepared to use bounded, eligibility-anchored owned one-shots with truthful horizon.

## Round14 director evidence
- Actual30seconds controller now clean exit0, exactly1schedule; old0schedule failure closed.
- Actual Android rebuild: resource defect closed, now Kotlin fails Unit-vs-Boolean permission callback and five activity-or-Godot Context fallbacks. Pinned actual AAR javap confirms void callback and Godot is not Context. Brief215 prepared, static previous Boolean contract invalid.
- Actual isolated GateLodge keyboard method with scene/autoload context: raw432devicepx at3x treated as viewportpx gives354shift/field-216/confirm-124, versus66normalized. Official DisplayServer docs and pinned Android get_vk_height delegate confirm device units. Brief214 adds conversion and bounded form layout. Bare --script initial probe lacked Vault, discarded as diagnostic.
- Settings15windowed views (5langs times808360/808532/808606) all rawlogs clean exit0, visible bounds fit, Analytics false, readable off/denial row. Native permission still untested.
- Actual iOS round14 SCons: priorcontext18errors closed;4newtypedAPIerrors now visible (NSUserDefaults longLongForKey/setLongLong nonexistent, baseUNNotificationTrigger nextTriggerDate nonexistent) and2iOS14Ephemeralavailability warnings atmin13. Added tobrief215. No native success claimed.

## Round15/16 independent UI/runtime evidence
- Actual real lesson clip passed: moved266.9/dashed/stopped/depart,126simframes/26savedPNGs. Viewed movement anddeparture; nativekeyboard stillpending.
- Stockcontactharness callsCamera.make_currentbeforeadd -> engineERROR and last actor interpolation renders huge despitefixedsource42. Director settled/reset contactproberealscript clean0: fourtransformedheights42.0000015, screenshotallfourconsistent. Brief214 includes clean harness settle, not image regeneration.
- Actualsame-deadlinecontroller revocation cleanexit1: nativepermissiondenied butSettingsstate stillgranted, becauseunchangedguardbeforestatus. Brief216 addsboundedOSreturnconvergence/unknownUItruthfulness.
- Nativehorizon15slotsfixed0..47 cannotrefillpast47*43200; independentJSplanmirrorsimplementation and lacks25daycase. Brief216 requiresfutureNthanchor48slots+observableboundedforegroundrefill (no shifting/no burst).
- Cumulativegame suite actualfails lateKnightnode_peak1202 cap1200 (1/73), newController1+Settingsrow2 overhead;HUDalreadylazy. Brief216 includeslazySettingsrow lifetime, no cap weakening. Baseline isolatedmaincompare underway.

## Director continuation: native round16 and cloud deployment
- Android actual debug Gradle build round16 exits0. iOS SCons source/static archive completes with no error/warning; packaging exits1 because WORK has no ios-deps/MoonlitLink/firebase-flags.json. This is a dependency-tree path, not a source compilation failure. Resolve from kept director dependency cache, then rebuild packaging.
- Combined owned Firestore rules independently pass88checks/14tests and are deployed to moonlitbeacon-778ee only. Live readback ruleset01b75c82-aeac-4259-8244-ee3479706b99,36220bytes,SHA242f593c06e35706ae65bcb7425f53c8ee08a8448f5cd0242988b66e0521630c matches candidate; prior legacy-owned rules preserved. Rollback backups under builds/verify/gate-live-rules/before.json; no root legacy-only deploy.
- Hosting build and check round16 independently PASS (49 care+142 docs,26pages,2068local links). Hosting deployment remains pending reminder horizon/permission corrections.
- Round17 brief214 running. Brief216 pending. No product accepted, no git commit/push/PR/merge/store upload.
- iOS full debug source+SDK packaging round16-staged now trueexit0:12frameworks/9SDKprivacybundles, artifact verified; no source diagnostics. WORK ios-deps is an ignored symlink to kept root dependency cache.
- QuickTime connected iPad mirror opened (not recording). Actual screen currently shows another app's sandbox IAP/TouchID sheet. Do not dismiss or interrupt that other workflow; build isolated Moonlit QA first and request a concrete available touch only after it is ready, if needed.
- Android brief216 now also asks honest alarm diagnostics: PendingIntent existence is not proof of an AlarmManager-held alarm; cancellation retains tokens. Effective status must include app-global/channel-off, not only POST_NOTIFICATIONS permission.

## Round17 independent final inspection
- Actual stock contact clean assertionexit0: front16x42/rear15x42/left12x42/right11x42. No ERROR; harmless Camera2D physics override warning remains. Rawgate-lodge-contact-round17.log.
- Actual name controls Japanese808x360 panel124,58,560,228; field140,138,528,44; confirm140,230,528,44. Restoredfinal540device@3x ->180occlusion, cappedlift58 ->confirmbottom216, keyboardtop180,36pxcovered, exit1. Brief217 requiresactual compact/reflow+restoration, notonly clamp math. Camera callback explicit before treeentry too.
- Initial keyboard probe lacked emptyfake.display: discardedfixturefailure. A later probe raced actornegativecontrol and returnedraw540occlusion: discarded. Finalpost-completion probe is accepted evidence.
- Nativepermission/horizon brief216 next, then217. Never run dependent director probes during actor negative-control edits again.
- Root main re-fetched at14:16UTC; origin/main still1ed5fb1a9b2798a0b76095e942d4fa5552efd2d0, featurebranch clean product root unchanged.
-100baselinehero images unchanged. WORK staged9debugSDKprivacy manifests byte-identical;9release manifests not staged in WORK yet, not modified. Root all18unchanged. App-owned CA92.1UserDefaults manifest is separate source ios/PrivacyInfo.xcprivacy and exportregisteredbundle-root input; actual finalapp inspection pending.
- Closed Oct2 ios-deps compilation caches4removed afterdryrun/lsof noopenfiles;732848376bytes,240keptDebug/Releaseproducts SHAidentical. Receipts builds/cleanup/gate-closed-native-module-cache-{dry-run,applied}.json. Currentnative042/Oct3SDK/privateinputs/assets/products/clips protected. Disk~2.4GiB, watchbeforedeviceexports.
- OriginalemulatorOwnerAPK publicsignerSHA2569091f1102d14a25c05a5089b457ed5c663847574869f79e34380f20c56867d72. Compare finalQA beforeuser10install; ifdifferent neveruninstallOwner. Preservebackuppackage132281386bytes sha83709692e4c0bd13b1884ba259e7455cc538f0fdaa00ddf7298c64f2413a969d.
- Async user question pending: iPad otherapp IAPsheet inprogress; availability/Allowtouch needed afterisolatedQA build ready. No device install/launch/user-switch has been performed.

## Round18 director findings / queued correction218
- ActualAndroid18GradleFAIL: hidden OPSTR_POST_NOTIFICATION unresolved atMoonlitReminderAlarm.kt106. iOS18actualSCons+12framework/9privacySDKstage PASS trueexit0. PrimaryAndroidXAPI23reflectivefallback source verified viaandroid.googlesource.com/platform/frameworks/support/+/f82200123a365205ce2af67df269fb1dc56b55bb/core/core/src/main/java/androidx/core/app/NotificationManagerCompat.java; brief218needsAPIcompatiblequery.
- ActualAttendanceReminders+registeredfakes+isolatedautoload, enabled/granted, knownownedcacheanchor25daysago/remaining0/expiredhorizon: nativecalls0, assertionexit1 clean. `_schedule_for_view`remaining0 stillstarvesfutureNativeIOSrefill; sourceprotectedcachemustallowfuture-onlyplanswithoutcoin/newgrant. Rawgate-reminder-expired-horizon-round18.log.
- IndependentunmodifiednumericCPPfragments extractedfromproduction .mm compiledexecuted, SHAstable undergate-ios-planner-source-probe/: fresh equalanchor firstFuture0 yields47future duefire<=now skip; day25base51 yields48 future. At19.75days nativeadequacyguard true(recordedbase0/end47), GDS8intervalmarginfalse (nativehas8futurepoints/end-now7.5intervals). Native duplicateok omitsactualend/base/count; afterexpiredguardfixthis can repeatedlyreplaceknownGamehorizonwith0. Brief218coversagreement/metadata/expiredskip/API23; requiresproductionruntimeplannerhelpertests, notonlystructuralRegex.
- Muse round19 brief217running PTY4376; keyboardcompact+callbacks. Next218after19thenfinalnativecompile/visual/probes/fullverify. No acceptance/commit/push/storeactions.
- PhysicalAndroidAPK backedup code-only togate-android-device-original.apk;132281386bytes. Certificate/hashproofchecking40317. No physicaluserdataread, no installs/no launches. iPad availability questionstillpending. Currentactive meaningfuljobs: Muse4376; certificateproof40317 (maycompleted).

## Round19 independent live-window review
- Muse report19 completed compact name form; director actualwindow10views (808x360/808x606 times5langs), synthetic OS height convertedthroughlivewindow/screen transform, 120feedback/occlusioncases,1080actualcontrolchecks PASS cleanexit0. Field/status/confirm clear180occlusion with8pxmargin; typedvalue/chrome restored. NotnativeIMEdelivery. Rawgate-keyboard-round19/*.log/results.json. ActualKOshortformPNG reviewed. No fourth correctionrequired.
- Stockcontactfinalrender now rawclean0/noCamera2Dwarning, front16x42,rear15x42,left12x42,right11x42. No hero artmodified.
- AndroidphysicaloriginalAPKSHA/cert identicaltoemulatorbackup; originalcode preserved. No userdata/install/switch/touchesyet.
- Brief218 started as round20 PTY34613 at15:03UTC; pending nativeAPI23/expired-horizon/future-slots agreement. Finalroommatrix100 runningPTY81049; guide/hero/contactsourcehashproof. No productacceptance/commit/store actions.

- Director finalroommatrix100/100PASS withunchanged5sourcehashes. Newassertactualheroopaque bounds do not intersectspeech atanyratio/locale/state; finalKO880greetviewed. FinalSettings15/15PASS realpanel.open lazynodes created, syntheticdeniedwithAnalyticsfalse, KO360imageviewed. Current UIshownfaithfully, no marketingcapture/upload.
- Root main refreshed15:16UTC still1ed5fb1a9b2798a0b76095e942d4fa5552efd2d0. ClosedrootAndroidintermediates1,086,186,856bytes removedafterlsof noopenfiles, outputs7keptSHAidentical; receiptbuilds/cleanup/gate-closed-android-intermediates-applied.json. Regenerablecompilecacheonly; dependencies/outputSDK/releases retained.

- Additional actualwindowkeyboard108checks at2424x1080(3xnormalized raw540=>180) and1448x1086tablet PASS clean0, confirmsdevice/viewportunits withlivescreentransform; nativeIME stillpending.

## Round20 independent native/build and callback findings
- Actualproductionheadernumericcompiled4testsPASS. Actualexpiredknowncacheprobe nowtrueexit0/1schedule. AndroidfinaldebugGradlecompiles+artifactverifyPASS trueexit0; iOSfinaldebugSCons+SDKstage+artifactverifyPASS trueexit0/12frameworks9privacybundles.
- After20stable/restored, actualpendingstatus->userdisable->lategrant still1schedulewhilewantedfalse; secondpendingstatus->sourcenonewithretaineddeadline also1schedule. Bothcleanassertionexit1. Newbrief219round21PTY29539 narrowscommonGDSscheduletailguards only, nativefilesmustunchanged. Rawnative-sourcebefore21proof27files. Do notacceptwithoutthiscorrection.
- AnadditionalinventedCLI --check-android flagreturnedusageexit2, no mutation; discardedasaninvalidinvocation, notaconfig/buildfailure. ActualGradleandexportpreflightarethesupportedchecks.

## Accepted core / final integration failures
- OriginalMuse21 changes accepted152files afterexact6rawsourceSHA comparison/safekeep. Rootstage now173files. DebugAndroidAAR/iOSstaticlib copiedfromindependentlyverifiedworkoutputs withSHA receipt. Native27sources unchanged21,100heroPNGs unchanged,18RootSDKprivacy manifests unchanged.
- Director lateperformancefinal actual73PASS/nodepeak1199; all4controllerprobe scenes PASS clean0 includingofflate/sourceNone,expiredcache,30snear,permissionrevocation.
- Root pnpm verify actualfailsinexport-preflight2inventorytests: attendance_reminders.disabled missing preservedlists, notgamefailure. NativeAndroidRELEASE additionallyactualAAPTfails vector?attr/colorControlNormal unresolved; iOSRELEASEactualcompile+stageverifiedPASS. Freshbrief220 correctsboth producercontracts/resources, no captures/releaseuploads.
- Nativepreflight4FirebaseprovidersREADY; all-platform --check exits1 solelyoptionalPlayGamesappIDnotset, sameasmain andoutsidecurrentfeature. No PlayGamesclaim.

## Root integration and actual Android entry (October 8)
- Briefs220/221 accepted11files after independent118 Node checks. Actual root Android release and debug native AAR builds pass; wrapped debug APK passes. Original icon tint and33-file persistence contract fixed without changing pixels outside the new feature. Root hygiene passes.
- Integrated verify next fails the gate-locale scanner on a legitimate `begins_with("gate.lodge.")` prefix. Brief222 fixes complete-key recognition. That run stopped emitting events for over20minutes and was terminated normally via CLI SIGTERM(exit143), with no approval rejection or changed flags. Brief223 continues the same unaccepted copy for the independently observed iOS root manifest collision.
- Actual root iOS isolated export succeeds, but Xcode reports two PrivacyInfo.xcprivacy app-root outputs: Godot engine manifest and new identity manifest. Brief223 requires merging app declarations while preserving engine reasons and all SDK manifests. No iPad install/launch and no simulator retry.
- Pixel_10 emulator used a separate synthetic user10. Actual guest entry claimed QA1008Luna against live Firebase, completed real movement/dash lodge practice and departed. First eligible attendance changed2coins to4; cold restart plus living Resume retained4 without duplicate payment and did not re-run the lodge.
- Actual Settings opt-in displayed Android POST_NOTIFICATIONS dialog. After Allow, AlarmManager held one inexact RTC_WAKEUP repeating alarm anchored12hours after the successful claim. Turning off canceled every held reminder. Cold force-stop/relaunch showed Reminders off and no held alarms. Historical canceled-alarm entries are not active schedules. Native notification delivery at the12-hour deadline has not been observed yet.
- Actual English settings screenshot exposed a10px label/button overlap missed by the prior viewport-only matrix. Previous actual rects: ReminderLabel(214,229,164,34), button x368. Brief224 requires real minimum-width and sibling-gap coverage without extra dormant nodes.
- Synthetic account deleted through the actual production account UI. Firebase admin readback confirms exact synthetic name/adventurer/attendance/reservation/Hall documents all404. No other account rows were modified by cleanup.
- Emulator restored Owner0, QA user removed, temporary launch probe jar removed. First original-APK reinstall failed insufficient emulator storage; removing the completed QA user freed space and the next reinstall succeeded. Installed code readback SHA83709692e4c0bd13b1884ba259e7455cc538f0fdaa00ddf7298c64f2413a969d exactly matches original. Physical Android data/app untouched; iPad other-workflow availability remains unanswered.
- Root hosting build/check pass49care+142docs,26pages. Firebase Hosting deployment succeeds191files; ko/en privacy, ko support and game reference routes return200 and byte-exact new HTML hashes. Custom domain updated; no git push or Pages mirror action.
- Separate root store screenshot check fails expected33-vs32 inventory/fingerprint evidence. Existing screenshots and all store files remain unchanged; no marketing recapture/upload. New feature is not store-submitted.

## Privacy integration accepted; settings correction pending
- Independent source tests56PASS for scanner/privacy. Real Godot-generated engine XML merges to four categories with required UserDefaults CA92.1; `plutil -lint` passes. Actual old duplicated PBX project is rejected. Director nested-path mutation makes registered tests fail; restoring bytes passes. Complete-key typo insertion makes scanner fail with the exact missing key; removed before acceptance.
- Privacy round2 initially invented a nested engine-manifest path; brief225 used the actual export root and independently specified fixtures. Round3 CLI was interrupted by ENOSPC, not approval refusal. The runner recovered the lost PID with unchanged settings. Round4 completed corrected root-path and ambiguity checks. Accepted7files; SDK declarations and game behavior unchanged by this integration.
- Cleanup: removed7 closed docs/node_modules/.cache folders,908556925logicalbytes, after lsof found no active handles. Sources/git/assets/stores/privateinputs/nativeSDKproducts preserved. APFS available space also changed independently; do not attribute all disk recovery to this deletion.
- New focused settings brief224 runs in tag20261008-0207-fit-the-attendance-label-beside-its-butt. Real root isolated iOS export/Xcode build now runs against accepted privacy correction. No device install or store actions yet.

## Final settings pixels and native iOS build

The director independently broke the settings label fitting call in the closed implementer copy. The real registered regression failed 73 of 1441 checks, including the original 164px English label and -10px sibling gap. Original source bytes were restored; the prior positive 1441-check run passed. The 3-file correction was accepted.

A real Compatibility windowed render then exercised 75 combinations: 5 locales × 3 framings (808×360, 808×532, 808×606) × 5 notification statuses. All produced nonempty PNGs, no diagnostics and zero layout failures. English uses 11px (119px text within 128px column); every case keeps the 8px rectangle gap. The director inspected the English off PNG. Evidence: builds/verify/gate-settings-tight-final/matrix-results.json and gate-label-negative-control.log.

The normal asset-catalog iOS isolated-device build succeeded after the app-root privacy merge correction. The built app has the four required API categories, including UserDefaults CA92.1, and nine SDK privacy manifests are byte-identical to their staged sources. Evidence: gate-ios-built-privacy-proof.json and gate-ios-built-sdk-privacy-proof.json. This confirms build resources, not human iPad permission taps or delayed notification delivery.

Final locale validation also identified the accepted attendance payload's REQUEST_TIME wire enum being mistaken for a UI key. Brief 226 requests a narrowly contextual checker fix with preserved UI-key negative controls. Root full verification and local commit remain pending.

The final settings correction is now included in both real device artifacts: root wrapped Android debug APK and normal asset-catalog iOS isolated app both built successfully. The iPad isolated app was installed and launched using CoreDevice; QuickTime mirroring visibly shows the landscape title with sprites, no black/blank render. No production iPad app was overwritten or opened, no other app purchase screen was interacted with, and no recording was started. The user was asked for the OS permission and off/relaunch touch check; no reply yet. The final Android APK was measured in gate-final-android-artifact.json; the physical Android user's data remains untouched.

## Scanner round1 rejected after independent negative control

The completed round1 scanner passed all its own nine fixtures, but the director planted a temporary valid GDScript dictionary containing both a protocol value and REQUEST_TIME as a second stored label value on the same line. The actual checker incorrectly exited0: the broad before.includes(field) condition skipped the UI occurrence. The probe was deleted. Brief227 requests occurrence-specific exemption and stronger same-token controls; this round was not accepted. This is a confirmed validator defect, not a production attendance change. Evidence: gate-wire-same-line-ui-negative.log.

The final separate store screenshot check exits1 because the old capture proof inventory predates the new persistent notification-disable file. Existing store marketing files and uploads were left untouched as instructed; no recapture was started. QA screen PNGs are separate ignored evidence.

## Scanner correction accepted after independent controls

Round2 now recognizes only the direct server-value occurrence or the narrow getter-expectation tail used by the actual attendance regression. The director reran all12 actual-checker fixtures (pass), repeated the previously escaped same-token dictionary UI probe (now exit1 naming REQUEST_TIME), removed the protocol predicate deliberately (3 of12 tests failed), restored original bytes, and reran the6 existing gate-locale tests (pass). The 3-file patch was accepted with exact allowance for .github/scripts/check-locale.mjs; no workflow or game bytes changed. Evidence: gate-wire-checker-independent-tests.log, gate-wire-same-line-ui-final.log, gate-wire-checker-negative-control.log, gate-wire-existing-gate-tests.log.

Remote main was checked again and remains 1ed5fb1a9b2798a0b76095e942d4fa5552efd2d0. The feature branch starts from that current main. Root pnpm verify is now running; no push, PR, merge or store upload has been performed for this new feature.

## Root full verification: fixture teardown failure corrected

The first final root pnpm verify progressed through Node suites, character visuals, weapons, audio, missiles and late-game performance, then correctly failed the strict Vault regression. All381 behavior assertions passed, but13 unfreed temporary Nodes held2 script resources, producing16 leaked ObjectDB instances. Director verbose output confirmed the normal/failing Vault resource names. This is new fixture lifetime ownership, not a reward/save behavior failure.

Brief228 corrected only test_vault.gd (+21 lines) and an author-only build-log entry. It frees the10 temporary Nodes in the continue-transaction group and3 in receipt-move, including loop instances, and adds2 real orphan-node baseline assertions. The director independently ran the actual isolated verbose test:383 pass, zero ERROR/WARNING diagnostics. Removing the loop cleanup caused exit1 and the exact expected=1/actual=4 orphan failure; source bytes were restored. The 2-file patch was accepted and root pnpm verify is rerunning. Evidence: gate-vault-leak-verbose.log, gate-vault-independent-clean.log, gate-vault-independent-negative.log, gate-root-final-verify.log and gate-root-final-verify-rerun.log. Production runtime bytes and device artifacts are unaffected by this test-only change.

Closed final Android Gradle intermediates were dry-run checked, verified untracked with no open handles, then removed (924101052 logical bytes). Final debug APK SHA d21eaa33a1865618c711fc4ab2f889c990124eea095a75c9be79c5efddfa9b13 stayed byte-identical. Source/config/keystores/SDK inputs/original binaries were retained; a later Android build regenerates these intermediates. Cleanup proofs live under builds/cleanup/gate-final-android-intermediates-*.json.

Connected physical Android reports one maximum switchable user. No synthetic account was created in its human profile and no physical Android application data was touched. Actual new-guest, unique name, movement, reward and native permission/scheduling/cancel/cold-off verification used the Android emulator's separate temporary user, which was deleted afterward and original owner code was restored. iPad final isolated app launch was visually confirmed; OS permission touch remains awaiting the user.

### Desk collision review and closed-copy cleanup

The second root full verification stopped at one real lodge failure: 2435
checks, one failed desk push-out assertion. A standalone repeat passed, so
it was treated as a timing defect rather than deleting the assertion. The
real lodge method at 880x360 projected the desk center to y=14.73333,
outside walk min-y=117.4222; the real player's bounds clamp could bring it
back inside the desk. Brief 229 changes the projection to select a valid
walk-floor exit with deterministic near-tie priority.

Director independently ran the registered suite: 2850 checks, zero failed,
exit 0. Restoring only the old production method produced 84 failures,
including the exact 880x360 off-floor and re-entry signature; the accepted
bytes were restored afterward. Both the direct method probe and real
windowed live physics/render loop held outside-desk and inside-walk at
808x360, 880x360, 808x532 and 808x606. Four rendered proofs were saved;
880x360 was viewed. Only the lodge script, its regression, and build log
were accepted. Android and isolated iPad binaries must be rebuilt after
this acceptance; the earlier binaries predate this correction.

Closed accepted copies had their regenerable dependency installations
removed after open-handle and accepted/finished checks. Approximately
1.94 GB of logical dependency files was removed; immediate APFS free-space
change was much smaller and is not attributed wholesale to this cleanup.
Sources, lockfiles, reports, imports and Git histories remain; reusing these
old copies requires reinstalling their dependencies. A normal repack and
prune-packed in one closed copy removed only redundant loose objects.
Every Git object inventory, HEAD, index and worktree status matched before
and after. No history or Git directory was removed. The current root and
active verification dependencies were retained. Dry-run/applied inventories
and the object-compaction proof remain under builds/cleanup/.

### Final accepted source verification and device artifacts

Third root `pnpm verify` completed with exit 0 after the confirmed vault
fixture leak and desk projection defects were corrected. It covered the
complete Node and Godot regression suites, clean game smoke, script,
locale, metadata, skill parity, hygiene, assets, store graphics, docs
build and internal anchors. Lodge: 2850 checks, zero failed. Reminders:
1441 checks, zero failed. No product source changed afterward.

The final Android wrapper and isolated iOS Debug build both exited 0.
Android APK is 137005081 bytes, SHA-256
`ef15bf9eb2d3997bce38785ac5cb2892dcf61e8147e828ccb605a03fa186ca91`;
its DEX contains the real reminder receiver and its resource table contains
the reminder icon. iOS completed normal asset catalog, arm64, signing,
Apple entitlement, public-key-only and resource-boundary checks. The built
app keeps all four engine/native required-reason categories with tracking
false, and all nine staged SDK privacy manifests are byte-identical.
The final isolated app installed and launched on the connected physical
iPad; QuickTime showed its actual landscape title and sprites. Production
iPad app data remains untouched. Actual iPad permission choice/native IME
and twelve-hour notification delivery remain unobserved; only the earlier
isolated Android permission, scheduled-alarm, cancellation and cold-off
checks are claimed. The finite iOS reminder horizon is documented, not
represented as indefinite background delivery.

The separate store capture proof check remains red: the existing Pixel
phone proof lists the old permanent-file contract and lacks the new
notification-disable setting slot. Existing marketing image bytes were
preserved; no recapture or store upload was performed. Root main and remote
main still resolve to `1ed5fb1a9b2798a0b76095e942d4fa5552efd2d0`.
This feature is prepared as local game, public-docs and author-note commits;
no push, pull request, merge or new store submission is inferred.

### Public-site readback and automatic-release steering

Game commit: `9fb14f9`; public documentation commit: `0a8aa22`.
Post-commit hosting build/check passed, hosting-only publication completed
191 files, and direct HTTPS readback of Korean privacy/support, English
privacy and the game reference returned HTTP 200 and exactly matched the
reviewed generated bytes. Source game and native artifacts stayed unchanged.

The user then explicitly requested immediate automatic release for future
iOS submissions. The ship-release source skill now records AFTER_APPROVAL
as the standing preference; its Codex mirror was regenerated with
`pnpm skills:sync`, and `pnpm check:skills` passed four tests and exact byte
parity. Brief 230 sends the small release planner/readback change to the
implementer. No existing in-review or approved version is released or
modified by that brief; future-default completion remains to be judged.

### Future iOS automatic-release default accepted

Brief 230 adds AFTER_APPROVAL to generated release metadata, manifest
validation and editable version create/update plans. GET field selection
and audit output carry the actual releaseType; the submission path refuses
missing/manual/scheduled/unknown readback before any review POST/PATCH.
In-review/published mutation protections remain in the existing real apply
path. The director read all five changed files and independently passed all
83 App Store tests. Removing only the new readback guard failed the focused
registered regression; the exact production bytes were restored. No game,
version, canonical gallery, binary or secret changed. The five-file patch
was accepted, and the source/mirror release skill retains the same default.

After final Android export, another closed 3449-file/924102291-byte
intermediate directory was removed only after untracked/open-handle checks.
The final APK SHA-256 stayed exactly unchanged. Source, native AARs, SDKs,
signing files, backups, current dependencies and proofs remain intact.

### Final local verification and commit closure

Fourth root `pnpm verify` completed with exit 0 after accepting the future
iOS automatic-release default. Its log is
`builds/verify/gate-root-final-verify-fourth.log`. All registered Node and
Godot regressions, game smoke, locale, metadata, synchronized skills,
repo hygiene, assets, store graphics, docs build and anchors passed. The
hygiene check included all 2855 staged/tracked files, including the new
briefs, source artwork and author notes. No game or public-docs source
changed during this verification.

Local release/workflow commit: `2fd9879` (`fix(release): default ios to auto
release`), following game `9fb14f9` and public-docs `0a8aa22`. This records
the user's future AFTER_APPROVAL preference and the remote readback guard.
The author-note commit closes the remaining local documentation. These
changes remain on `codex/gate-chamber-and-defeat-rules`; no new push, pull
request, merge, version bump, store screenshot upload or review submission
was performed. The existing capture-proof mismatch and unobserved actual
iPad permission/IME and twelve-hour reminder delivery remain the same
explicit limitations documented above.
