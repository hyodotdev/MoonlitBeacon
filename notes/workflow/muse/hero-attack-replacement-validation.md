# Hero attack replacement validation

## User scope

The user reported that a sword-carrying hero never visibly swings the held
blade, requested inspection and repair of all heroes, and explicitly
authorized immediate cancellation of the submitted review and a replacement
update. The next message says existing screenshots do not need recapture.
All existing marketing and IAP review images are retained. Moving QA evidence
is separate from marketing capture; no store capture pipeline is run.

## Store cancellation

The director first fetched the exact pending iOS submission, its version and
eleven items. The submission was `WAITING_FOR_REVIEW`, the version named
4.0.0, and the expected app version was present. One authenticated PATCH
requested `canceled: true` for that submission. The initial response was
`CANCELING`; a later independent GET confirmed submission `COMPLETE` and app
version `DEVELOPER_REJECTED`. This is successful cancellation, not app review
approval. No marketing or product image endpoint was mutated.

The canceled submission is `e53a0810-d622-4708-8958-47cc1ecb3949`; the editable
app version is `743c9128-6202-4f6f-8721-e0974a399e5e`. Ignored evidence is in
`builds/verify/hero-attack-review-cancellation.json` and
`builds/verify/hero-attack-cancellation-readback.json`.

A separate live Google Play GET confirmed internal and production 4.0.0
(17) both `RELEASE_LIFECYCLE_STATE_PUBLISHED`. There is no pending Play
submission to cancel. Evidence: `hero-attack-play-before-update.json`.
SHA-256 and byte counts of all 160 existing local store PNGs were recorded
in `hero-attack-retained-image-hashes.json` before product changes.

## Baseline and implementation briefs

Baseline commit is `25fe321c53c365ee7bf8183e3b107ebd571f9bc2` on
`feat/4-0-0-gate-journey`, clean before the director wrote new briefs.
`WeaponRig._draw_held()` uses a static aim/pivot; `_process()` only fades the
flash. `Player._play_current()` selects idle/walk only; cannon recoil shifts
the body without carrying its rig. These are confirmed source defects.

The baseline painted-weapon test passes 5016 cases despite missing physical
attack motion. Its coverage is sheet integrity/seating/flash, not readable
body and weapon action. Log: `hero-attack-baseline-painted-weapons.log`.

Brief 171 delegates physical attacks for all six heroes, direction and
rapid-fire cleanup tests, and a timed no-PNG motion harness. Brief 172 owns
the explicit retained-gallery App Store release mode and replacement build
counters, with no actor-file overlap. Both run in isolated copies; neither
has credentials, remote access or device permission. Implementation is not
accepted merely because either report says done.

## First rendered judgment and retained-gallery preparation

The director rendered the first candidate's actual timed motion-only movie
at 60 FPS. It completed 302 frames (about five seconds); normal and close
characters appeared, but the close Dancer retains its original idle arms
while a conspicuous circular glove near the knee carries the moving blade.
The Warden row is cropped off the top, and decorative Eclipse orbit rings
remain visible in the no-VFX movie. The source also applies weapon travel
both to the rig position and its drawn anchor, and locomotion can override
attack-facing. These observations prompted correction brief 174. The actor
candidate remains unaccepted; a passing geometry test does not resolve
these rendered defects. QA video/frame extraction did not run any store
capture pipeline or modify retained store files.

The independent App Store retained-gallery suite passes 80 tests. A director
negative control removed only the image-mutation refusal in the isolated
copy: the race test failed as required; the source was restored. The six-file
release change was accepted, including exactly two Android counter edits
17→18 and one iOS edit 12→13. Workflow mirrors were synchronized and checked.

The real local-only retained-gallery preparation writes the build-13 manifest
over unchanged PNG bytes. Its live App Store GET audit reports 76 GETs,
zero mutations, 104 unchanged targets, and only two expected blockers: the
not-yet-uploaded build 13 and its beta-group association. All remote image
targets match the retained files. The SHA-256 check still reports 160 of 160
local store images unchanged. Evidence is in
`hero-attack-director-reuse-gallery-round2.log`,
`hero-attack-reuse-gallery-director-negative.log`,
`hero-attack-reuse-preparation.log`, and
`hero-attack-reuse-gallery-prebuild-audit.log`.

Brief 175 closes the supported Play binary-only promotion/review path so the
new verified internal build can ship without relabeling old capture evidence
or selecting build 17 from the retained package.

The five-file Play change was independently inspected and accepted after
brief 176 corrected the operator instructions: production review is attempted
only when promotion has not already returned `IN_REVIEW` or `PUBLISHED`.
The director ran the package and publisher suites: 136 tests passed. A
negative control changed only the selected promotion identity from the new
applied build to the retained package's previous version; the exact-new-build
test failed as required, and the source was restored before acceptance.
Evidence: `hero-attack-play-postapply-director-tests.log` and
`hero-attack-play-postapply-director-negative.log`.

The new post-apply promotion/review modes require a verified, mode-600
`APPLIED` binary-only receipt binding the new AAB and retained gallery. They
delegate to the existing production-track lifecycle and readback checks;
they do not upload a second AAB, mutate listings, products or images, or
reuse the previous package's versionCode. No Play mutation has occurred for
build 18 yet.

## Remaining verification

After the release-tool patches were accepted together, director runs on the
real tree passed App Store release tests (80/80), Play release package tests
(248/248), skill mirror checks and compilation of all 165 current scripts.
The retained-image hash comparison still reports 160 images, zero changed.
These results cover the integrated release tools, not the unaccepted actor
candidate or a new deployed binary.

Read-only private backups while both observed games were paused returned
two identical reads on each device: 12 present protected Android files and
27 iPad Documents files. They are stored only under the ignored private
verification directory with restricted permissions. Native SDK preferences
and Keychain were not copied or reset; no remote file was written. Final
fixture work still requires a fresh quiesced snapshot immediately before
installation or test-control writes.

The director rendered the round-2 candidate at 60 FPS with production
attacks and VFX suppressed. Both the normal invocation and one with an
explicit 1280x720 CLI resolution wrote 1616x720 AVIs. The normal and close
Warden row is cropped. Internal QA frames and a full Knight cycle strip
confirm that attack bodies blink dark and arm patches are oversized.
Source review confirms raw arm Sprite2D textures lack the hero's 0.255
scale, replacement body/arm parts lack the original readability tint, and
the split pauses and freezes the drawn legs throughout moving attacks.
These defects prevent acceptance despite numeric IK/weapon checks. Brief
177 groups the confirmed defects for the third judgment round; no actor
changes have reached the real working tree yet.

An independent throwaway copy confirmed the render-only negative control:
the attack suite passed 4174 checks unchanged, and passed 4175 after only
`ArmRig._layout()` was replaced with an immediate return. Joint getters and
weapon/VFX timelines remained active. The original bytes were restored.
The small count variation is from live tick samples, not an assertion
change. This proves a frozen actual painted arm evades the current suite;
brief 177 requires checks of the drawn segment transforms and endpoints.
The running implementer also found missing test-helper/API calls in its
related arena suites. No green result is credited for those suites until
their full clean completion is independently verified.

The director stopped round 2 after its independent rendered failures and
negative-control evidence; the draft report was preserved by the runner.
This is a rejected unfinished candidate, not an approval/classifier refusal.
All candidate build/test processes were confirmed stopped before continuing.
The draft still had pending arena suites. Brief 177 includes clean complete
arena checks alongside the rendering fix. Director correction: the initial
claim that `Player.facing_vector()` was nonexistent was wrong; it exists in
both the baseline (line 692) and candidate (line 1277). A failed search from
the implementer's progress log was insufficient evidence. The root brief
and a separate QA correction note were corrected; no production API should
be added for that mistaken premise.

The revised physical animation has not yet been accepted. The next
artifacts are planned as Android 4.0.0 (18) and iOS 4.0.0 (13), subject to
fresh store checks before upload. Both builds, actual motion review, real
device installation, two clean independent review rounds and final store
submission readbacks remain required. The earlier actual-purchase waiver
remains in effect; it is not a claim of purchase verification.

The Pixel_10 AVD is available for the first Android loop. The connected
physical Android is Galaxy Z Flip5, not a physical Pixel 10. The connected
iPad is an iPad mini. Device evidence will identify its actual scope and
leave unobserved hero/direction cells incomplete rather than substitute a
representative fight for exhaustive evidence.

Before replacement installation, CUA observed the existing Galaxy build's
Google-signed-in account panel, selected the existing Resume action and
observed its production loading overlay followed by actual Wave-1 combat.
The arena advanced from level 1 to level 2 with kills on screen. This is
evidence that the old installed build re-enters play, not verification of
the still-unbuilt replacement. The run was left at its paused level-up
choice; no new-expedition erase or account-delete action was taken.
QuickTime's existing iPad mirror also displays actual Korean Wave-1 combat
at level 5 and a paused relic choice. No store PNG was written for either
observation. Repeat continuation after replacement installation remains
required.

The reviewed retained-gallery release tooling is locally committed as
`6472d56`. Its independent focused results remain App Store 80/80 and Play
248/248; this commit is not a store submission or an actor acceptance. The
source release skill now records the conditional promotion readback rule,
and its Codex mirror is byte-identical after sync.

At 26 minutes into actor round 3, the implementer had repaired the pending
arena checks and repeated the old joint-based negative control. The actual
arm Sprite scale, replacement tint, frozen legs and 1280-wide harness were
still unchanged. No positive visual judgment follows from that progress.
The user was informed of the third-round state; the existing instruction
to carry the repair through deployment remains the scope. No marketing or
IAP image has been regenerated.

The director stopped actor round 3 with SIGTERM after 31.1 minutes because
the four observed rendering defects remained unchanged. The runner records
exit 143 and no report, not success; its accumulated diff is preserved. This
was a deliberate rejection, not a tool approval or classifier refusal. No
candidate Godot or implementer process remained. Brief 178 restates the four
exact defects for a fresh conversation in that same copy using unchanged
approval and sandbox settings. The user was informed before continuation;
their earlier instruction to finish the repair and deployment persists.

Round 4, started with a fresh conversation and unchanged safety settings,
addressed the actual scale/tint/drawn transforms and added a gait clock.
The director independently rendered a 1616x720, 60 FPS no-VFX AVI: 938
frames, 15.633 seconds; the harness completes with 113 checks. The 139
recorded render inputs remained byte-identical between capture snapshots.
Full-board frames and six contiguous right-facing cycle sheets show the
scale and brightness repair and physically moving held weapons. They are
internal QA material, not new store screenshots or final acceptance.

The new isolated attack suite independently passes 4552 cases. Removing
only the actual `ArmRig._layout()` body now fails 192/4552 cases while the
joint getters and weapon/VFX clocks remain active. The probe source was
restored byte-exactly. This closes the previously false-green drawn-arm
test, without claiming any new device coverage.

The moving lane still fails observation: only three moving bodies remain
visible at 10 seconds. Its direction parity increments once per hero; six
heroes keep each hero moving in the same direction on every pass, into
off-screen bounds. Brief 179 targets visible two-way movement and complete
live state-transition proof. The current gait dash assertion activates a
dash only after the attack ends, without sampling legs during it; that
does not prove the advertised dash-while-attacking behavior. All normal
and close directions fit, but the full moving proof is not accepted.


Round 5 independently renders 938 frames at 1616x720 / 60 FPS, 15.633
seconds, with 7803 harness checks. The 139 recorded render inputs remain
unchanged across the movie. The 10-second board view shows all six movers
in distinct visible lanes. This closes that observed lane defect, not the
remaining gait timing or final native-device scope.

A new COW probe with round-5 Player sets actual AnimatedSprite2D progress
2.75 before attack entry. The split clock receives 2.0, losing 0.75 frames;
recovery has explicit fraction 0.8 but Sprite fraction 0.0. A second COW
probe expires the physics facing countdown while Keeper's rig is still
live: one movement tick changes facing RIGHT (3) to LEFT (2) despite rig
live=true and aim=(1,0). This confirms the implementer's reported facing
flake is a boundary defect, not a green retry. The first invocation of
that diagnostic accidentally used the root project and timed out; a
subsequent relative script path was missing. Only the correctly invoked
absolute diagnostic in the COW project supplies this evidence. Root
product sources and device data were untouched.

Brief 180 bundles these two verified timing defects. Round 6 starts a
fresh implementer conversation in the same copy without changing approval
or sandbox settings. No acceptance or final review pass follows from its
start. The director also reviewed all 82 new production rig PNGs at 4x
nearest (24 torsos and 58 arm/nub patches), compared their contract paths,
dimensions and color/alpha budgets without failures, and independently
ran pack_attack_rig.py --check successfully for 88 outputs. Existing
idle/walk sheets remain unchanged. Rendered composites still decide
whether the intentionally vacated torso patches are covered correctly.

Additional seen-list: complete Player cumulative diff through the round-5
gait, recovery, dash, cleanup and suppression paths; ArmRig drawing and
endpoint transforms; new motion tests through articulation, split,
facing, sidearm, pause, cleanup, no-VFX, orbit and freeze controls;
manifest/game prose and changed visual/painted-seat assertions. The
manifest's historical claim that muzzle seats are untouched now conflicts
with calibrated painted wrists and must be corrected by the implementer
before acceptance.

The director's independently pinned round-6 COW suite passes 5,408 checks.
Replacing only the painted ArmRig layout with an early return fails 192
of those checks; the original layout bytes were restored afterward.
Independent same-facing entry/recovery keeps 2.75 frames and the recovery
fraction, and the live-rig end-boundary probe keeps the held facing through
its last tick. Logs are `hero-attack-round6-director-motion-suite.log`,
`hero-attack-round6-drawn-arm-negative.log`,
`hero-attack-gait-fraction-round6-probe.log` and
`hero-attack-facing-boundary-round6-probe.log` under `builds/verify/`.

Round 6 is still not accepted: the director changed the viewing angle to a
first primary attack turning against the walking direction. The actual
baked Sprite progress drops from 2.75 to 0.0 before the split seeds its
clock (`hero-attack-gait-turn-entry-probe.log`). Brief 181 requests that
narrow production-path repair and tests for all six heroes, both axes,
walking and idle. It also corrects two independently measured prose claims:
painted muzzle spawn seats were recalibrated, and two of the 82 PNGs are
sampled-color profile mitt templates rather than literal atlas cuts.

The remaining harness sampling/cut/sweep/shot functions and WeaponRig's
sheet calibration, pivots, seats, spans and variant definitions were read.
The review harness steps its sample clocks explicitly; its timed assertions
are not an automated inspection of every encoded 60 FPS frame. Final movie
and device evidence must be judged separately. QuickTime is again showing
the connected iPad's old build paused at level 5; the Galaxy mirror shows
its old build's paused level-2 selection. Neither observation proves the
replacement build yet. The private backup operation prepared for the
replacement reads only game container files, quiesces the exact game,
compares two reads and leaves native SDK preferences and Keychain alone.

### Final first-turn repair and clean director round 1

- Round 7 source was independently pinned: Player and the new motion suite.
  In a COW project the director ran 6,368 assertions successfully. Reverting
  only the two primary-turn helper calls produced 240 failures; exact source
  restoration was checked. The initial invocation used the root cwd and
  printed a missing-script ERROR despite exit 0; that invalid run is not
  credited. The corrected copy-cwd log is the credited run.
- Independent first-opposite-turn and same-facing probes retain 2.75 frames
  at entry and 0.55 fractional progress at recovery. The rig-live boundary
  probe retains the attack facing when the countdown has already reached 0.
- Both actual windowed Godot movies are 1,616 × 720, 60fps, 938 encoded
  frames. Production motion runs with and without VFX. Each timed harness
  run checks 7,803 conditions over 108 row attacks; this does not mean every
  encoded frame was automatically checked. The director viewed all six
  four-facing contact sheets in each mode (28 selected frames per face,
  3.0–4.35s at 20fps), plus complete board samples including all six movers.
- 1,838 game-file input hashes match before/after both movie runs and after
  the implementer completed. Root acceptance changes only export presets
  relative to that render input set (authorized Android 18 / iOS 13).
- Code, fixtures, painted production PNGs, actual render, negative controls,
  and final build-log merge were judged without a further correction. This
  is clean round 1. Root full verification and native/artifact review form
  the second viewing angle and are still pending.
- The implementer finished all seven rounds and `muse accept --check` plus
  acceptance passed for 199 files. The root-only retained-gallery build-log
  paragraph remains once, after the actor insertion.
- Fresh stopped-process, two-read game-container backups are stable on the
  Android emulator (8 present files), Galaxy (12), and iPad (14). Native SDK
  preferences and Keychain were not captured or changed. An operational
  helper initially used `adb exec-out`, which hid a missing-file error in
  stdout behind exit 0; using `adb shell` preserves the real remote status
  and both subsequent Android snapshots passed. No fixtures/installations
  ran before the valid backups.
- Review evidence: `hero-attack-round7-director-motion-suite-corrected.log`,
  `hero-attack-round7-director-turn-negative.log`, three round-7 probes,
  `hero-attack-final-render-proof.json`,
  `hero-attack-final-after-muse-proof.json`, and twelve final internal contact
  sheets under `builds/verify/hero-attack-final-contacts/`. These are internal
  QA outputs, not marketing screenshots. All existing store PNGs are retained.

### Root full-check finding: Knight node budget

The first root `pnpm verify` stopped at the unchanged late-game performance
suite: Knight Lv40 cycle 5 peaked at 1,205 nodes, failing the 1,200 limit
(1 of 73 assertions). Forty spirits, shell detonation and spatial work pass.
The newly always-present split nodes are the relevant regression surface.
This resets the clean-round sequence. Brief 182 requests a narrow node
allocation/lifetime repair with unchanged combat, image bytes, and budget;
no native installation, upload, or merge has happened yet. The separate
store-screenshot check fails because game bytes changed after the old capture;
this expected freshness result does not authorize recapture. All 160 PNG
hashes still match the retained baseline.

### Current account ownership before replacement

A fresh Firebase Auth/Firestore GET audit matches each local public-ID
journey partition through its profile to the real Firebase UID: Galaxy is
Google-linked, iPad is Apple-linked. Profile, reservation and checkpoint
ownership match, and cloud/local checkpoint IDs and hero match. Evidence is
`hero-attack-current-account-cloud-proof.json`; only UID hashes are printed.
The first diagnostic incorrectly treated the journey filename's public ID
as a Firebase UID. Reading `Journey.use_account` / ProductionHost corrected
that diagnostic; it was not a product defect. This pre-upgrade readback is
not a claim that the replacement binaries have been installed or that every
native provider interaction/purchase has been exercised.

### Independent allocation review and confirmed state transitions

- Pinned four candidate files into the director's COW project. Node-budget
  suite passes 126, physical motion passes 6,368, unchanged late-game suite
  passes 73; Knight Lv40 peaks at 1,198 with forty spirits. Restoring the
  prior eager Player and scene fails 82/126 node assertions with no engine
  errors; the current files were restored byte-exactly.
- A separate actual production-API probe confirms two new lazy-orbit
  regressions: draw suppression before equipping Eclipse is not inherited
  by the new orbit; direction suppression before equipping Eclipse followed
  by restore leaves no active orbit. Both checks fail the candidate and
  both pass the previous eager Player/scene. Brief 183 requests a narrow
  state-propagation repair with no eager-allocation fallback. This is still
  not a clean round or native replacement validation.
- `hero-attack-node-budget-director-{suite,motion,late-game}.log`,
  `hero-attack-eager-node-negative.log`, `hero-attack-lazy-vfx-probe.log`,
  `hero-attack-eager-vfx-positive.log`, and the four source pins record these
  measurements. An initial attempt to write the probe in the copy used a
  nonexistent relative output directory; that missing-script invocation
  is not evidence. The credited script is the subsequent absolute-path run.

### Lazy-allocation final repair: director round 1

- Final COW source pins: `hero-attack-node-budget-final-director-probe-sources.json`.
  Independently ran 157 node-budget cases and both real VFX transition probes:
  both passed. The draw-inheritance repair reverted alone fails 1/157;
  reverting the direction-restore allocation alone fails 1/145. All five
  pinned COW files were restored, with no parse/script errors in either
  negative (`hero-attack-final-negative-proof.json`). An initial diagnostic
  assertion expected uppercase `FAIL`; the actual suite prints `failed`.
  It was corrected and both negatives were repeated; product code was not
  changed by this diagnostic.
- Final implementer copy rendered two new actual Godot movies, each with
  7,803 harness checks, 108 row attacks, 938 encoded frames at 60 fps and
  1616x720. Inspected all twelve final-code contact sheets, 28 selected
  frames in each of four facings for every hero, with and without effects.
  Physical grips, separate Dancer blades, broad Eclipse sweep, recoil,
  recovery and up-facing occlusion remain coherent. These are internal
  desktop QA movies, not replacement store images or native direction proof.
- Accepted the eight-file allocation patch. All 1,833 compared game-source
  files in the render copy match the accepted tree after rendering
  (`hero-attack-post-budget-source-proof.json`); excluded generated platform
  folders and skipped files not present in the root are not claimed by
  that comparison. No art bytes changed in the allocation repair.
- This round found no further defect. Full root verification is running;
  replacement APK/AAB/app/IPA and actual device review form the next angle.

### Accepted-tree full verification

`pnpm verify` completed with exit 0 on the accepted tree
(`hero-attack-root-final-verify.log` and the compact proof beside it).
This includes 684 passing Node TAP cases, all registered game regressions,
6,368 physical-motion cases, 157 node-budget cases, late-game 73/73 at
Knight Lv40 node peak 1,198, script compilation, locale and skill mirror
checks, hygiene, 412 manifest assets, 70 media references, deterministic
asset bakes, store graphics and the docs build. The docs output checks 26
HTML files with no NUL bytes and valid internal anchors. The login-glyph
source-image test prints its existing raw-image/export warning; this is
not a claim that every test output is warning-free. Separately ran the
accepted-root rig bake: all 88 outputs byte-verified.

A final archive-payload operation probe was self-checked against the
current source. A first old-iOS-pack diagnostic kept the source resource
root in reach and could fall back to those texture files; it is not
credited as a strict byte audit. Repeating from an empty resource root
rejects the old build-12 pack on the first missing rig texture. Desktop
inspection of an iOS pack may emit expected macOS/native-extension
mismatch messages; it is a resource-byte inspection, not a claim of native
iOS execution or native authentication.

The replacement Android 18 APK was installed over both the Pixel_10 emulator
and the connected Galaxy without uninstalling. Local and installed APK hashes
matched and stopped-process game-file backups were byte-identical across each
upgrade. Normal emulator cold restart kept the same guest identity and offered
the saved Wave 1 checkpoint; selecting Resume entered actual combat again.
Selecting Start over showed the deletion warning, and Keep preserved the save.
The Galaxy's normal account panel displayed the existing Google-linked account;
a cold restart retained its Warden/Wave 1 card and Resume entered actual Lv2
combat. These are gate-checkpoint resumes, not exact mid-frame restoration, and
cached provider continuation is not a fresh interactive OAuth proof.

Native QA automation initially failed because of its private-file shell quoting,
then rejected an identity-cache timestamp rewrite. The quoting was repaired;
independent comparison found only `created_utc` changed while public ID and
binding bytes matched. The owned fixture and control files were restored and
re-read byte-exact, without SDK preference resets. A subsequent smaller emulator
recording completed movement and recording but the current PID emitted a real
ProductionEntry null-tree music-timer error during fast combat boot. This is a
confirmed product finding, not a clean review round; brief 184 requests its
narrow lifecycle repair. Earlier combat clips are diagnostic material until the
new binary repeats the run without that error.

The iPad received build 13 over the existing installation; stopped game-container
bytes matched before and after, and its live QuickTime mirror showed the normal
4.0.0 title. A human touch request is pending for its current-build Apple account
and resume path. The normal Debug and Release archives include the asset catalog.
Automatic App Store export picked an old profile without Apple sign-in and failed.
The installed Apple-capable App Store profile was independently matched to the
current distribution certificate and manual export passed all signing, entitlement,
version and resource checks. The pending audio repair will be rebuilt before any
upload. No replacement store submission has been made.

Combined hosting build/check passed: 49 care files, 142 docs files including
26 pages, and 2,068 local links. All 160 retained PNG hashes still match their
baseline; no marketing or IAP image was regenerated or uploaded.

## Standing identity is now a release gate

The user's next visual review found a real defect not covered by the earlier
always-moving attack lanes: idle is a turnaround contact pose while lateral
walk uses separate donors. The Warden's face and hood are visibly larger at a
stop; the idle feet remain spread in a stride pose. Whole-figure idle breathing
and forecourt paint-bound refitting can add another scale change. Brief 186
explicitly supersedes the prior restriction against changing idle/walk sheets.
It requires one painted upper-body identity per facing, supported neutral feet,
intro and Player transition movies, rendered-region regressions with negative
controls, and rig recalibration while preserving the existing combat behavior.

The director added this gate to the authoritative visual E2E reference and ran
`pnpm skills:sync` and `pnpm check:skills`; both exited 0. No replacement upload
has been made. Existing native build-18/build-13 and movie proofs precede this
repair and must be superseded after acceptance. The packed-art operation now
includes all 12 idle/walk atlases as well as 82 rig textures and six joint JSONs;
this prevents a final archive with old resting art from passing a rig-only audit.

Brief 184's title-music repair was independently checked in a separate copy:
11 assertions passed; restoring only the original production entry caused the
expected detached timer and delayed-restart failures; restoring the repair
passed all 11 again. The final implementer source matched the tested SHA-256.
Five files applied cleanly, and the accepted root suite passed 11 assertions
without script errors. Commit `3eae52e` contains that repair. Native teardown
must still be repeated using the rebuilt binary after brief 186. Brief 185's
painted-fang documentation correction was independently docs-built, accepted,
and committed in `c3edb27`; it accurately describes the two independent grips.

The post-music root `pnpm test:game` completed all 79 registered runner rows
(including its two import rows), exit 0, with no script or engine error lines.
The original 6,368 physical-motion assertions still passed. An interim Android
18 APK containing the music repair was exported and installed over the emulator
with matching installed/local SHA-256 and byte-identical stopped game data.
The same owned fast-combat Warden boot that previously emitted the null-tree
error then completed a 12-second recording, four requested joystick directions
and dash, with zero current-PID/current-epoch native errors. Cleanup re-read the
original game and control files byte-exact; no SDK preference or Keychain reset.
These are narrow music-repair proofs before the standing-identity repair, not
final character-consistency or replacement-submission proof.

## Standing preview rejection and the unboosted native route

The director generated fixed-coordinate, 4× idle/walk contact sheets for all
six heroes and all four facings from the first brief-186 copy. Warden down and
Dancer up still reused the walking lower body, leaving a lifted/passing leg;
the side prototype narrowed the stride but left a backward shin and separated
profile feet. No part of this answer was accepted. The owned implementer child
was deliberately stopped after checking its process identity, and its runner
recorded exit 143. This was an intentional visual rejection, not a startup
permission refusal. Brief 188 continues the same copy as round two, requiring
neutral supported legs in all 24 cells and one canonical head through every
walking frame, idle, attack and recovery.

The native direction inspection also needed a distinct unboosted boot: the
existing marketing boot presets grant survived time and missile power even
when asked for Lv1. Brief 187 requests a debug-only real-Arena route, keeping
the existing nonce-bound runtime readiness checks and refusing armed/pending
journeys. A director-authored operation helper first tested the current APK:
it correctly rejected the missing unboosted boot, recorded no visual cells or
movies, and re-read the original game/control files byte-exact after cleanup.
This expected failure is not native visual approval.

The final packed-resource audit now covers 94 PNG source/import pairs and six
rig JSONs, comparing all 100 payloads in APK, AAB and iOS pack. It also checks
the packed title-music lifecycle property. The old pre-audio iOS pack was
inspected from an empty resource root and correctly failed that new music
check; no source fallback or native execution was claimed. All final artifacts
must be rebuilt and pass after the standing and inspection changes are accepted.

Brief 187 initially supplied a real-scene inspection test without registering
it: the clean-UI suite checked file presence only. Brief 189 added its one
runner row, leaving every other row unchanged. In a separate director copy,
fresh import followed by the request suite passed 93 assertions and the real
scene passed 48, with no engine/script errors. The complete game runner then
passed all 80 rows, including the new executable inspection scene, exit 0.
Reverting only the two production boot/launcher files failed the intended
Arena-entry assertion (1/14); using the old boosted launch failed missile and
survived-time assertions (2/48). Both negative runs had no engine errors.
Removing the journey guard also failed its intended preservation assertions,
but its negative-only cleanup then called `queue_free` on an already-freed
title; that run is explicitly not a clean negative control. Restoring the
actual repair passed all 48 again, with no errors. All seven final source
hashes matched the implementer's copy. The patch applied cleanly and the root
scene passed 48; commit `4c702dd` contains the accepted inspection route.

Native inspection now checks the original nonempty checkpoint and Vault bytes
after boot, after every direction image and after motion, before any fixture
cleanup. A later byte-exact restoration cannot conceal a temporary save loss.
These internal QA operations keep the existing SDK preferences and Keychain;
the standing-art repair is still unaccepted and no store upload has occurred.

The interim inspection APK was rebuilt at Android code 18 with SHA-256
`c578400fe089df525a13a46061ee42c6fb5b198f6135d3915761d815d811c0bd`.
Its emulator install matched that hash and preserved the stopped game files
through fresh two-read snapshots. The first live runtime-request rewrite
briefly exposed a truncated JSON file to the polling game. The director's
ignored QA operation helper now writes its owned request to a verified
temporary file and renames it atomically. Repeating the route on the same APK
produced four nonce-bound Warden cells and one movie with zero current-process
native errors and unchanged checkpoint/Vault bytes during the operation and
after cleanup. This was an operation repair, not a production-game change.

The shorter-input clearance probe also produced four distinct, unobscured
direction crops, but its movie is rejected: gradual short swipes show too
little walking to establish a full cycle, and the rightward dash ends in
brush. Its dense 60fps contacts and full-length 2fps overview remain comparison
evidence only. An explicit held-touch loop and a clear downward dash corridor
are being tested before repeating the matrix on the final art. Neither this
old-art probe nor source preview images count as final character approval.

The second standing round produced visibly improved supported feet, including
the corrected Keeper back pose, but still failed identity. An independent
fixed-coordinate RGBA measurement found all 24 idle head columns matched
their own walk frame 0, while none of the 24 walk columns held that head
through all four frames. Knight up translated five source pixels; Keeper
down grew from 68 to 73 source pixels wide and moved its top four pixels.
Shared fit scale alone therefore did not meet the user's consistency request.
The draft also changed Knight recoil and its expected test from 7 to 5,
contrary to the unchanged-motion acceptance criterion. No part was accepted.
The director checked the owned child/parent identities and deliberately ended
round two with SIGTERM; its runner recorded exit 143 after 77 minutes.
Brief 190 continues the same copy as round three, retaining the useful stance
work but requiring canonical heads in every walking frame, original recoil
thresholds, registered negative controls and dense real-render transitions.

The explicit held-touch native probe established multiple walking frames, but
random forest decoration hid the initial body and dash endpoint. It is rejected
as visual proof despite zero native errors and exact game restoration. Native
inspection now has an optional director-driven navigation preview: move through
normal input to a genuinely open area before nonce-bound direction captures.
The first interactive probe failed its initial down-facing readiness and
restored all game/control files; it produced no approved cells. Facing inputs
now use an explicit held touch too, and failure observations are retained to
diagnose the actual animation rather than guess. These are ignored QA helper
operations; production art is still pending and no release upload was made.

The held-facing interactive protocol probe then produced four genuinely open
Warden direction cells and a 16-second native walk/dash movie on the interim
code-18 APK. Current-process log inspection found zero errors. The nonempty
checkpoint and Vault were unchanged during boot, every direction and movement,
and all game/control files were byte-exact after cleanup. Explicit held input
showed complete moving frame cycles and an unobscured rightward dash. All nine
consecutive-original-frame contact pages were inspected, together with the
full-length overview and native QuickTime playback. A clean re-extraction uses
original PTS and passthrough frame timing; its nine pages hash-match the prior
derived pages and its log contains no DTS warnings. This validates the QA
operation only: the movie visibly retains the old head/idle mismatch and does
not approve the pending standing artwork or either final device matrix.

A separate secret-free director snapshot of the third standing round passed
6,368 physical attack assertions, 157 player-node assertions and 73 late-game
assertions. Knight Lv40 still peaked at 1,198 nodes against the unchanged
1,200 limit; recoil remained 4/7/2.5. Rig packing verified 88 deterministic
outputs and the painted-world check verified 89. The snapshot's first two
runs lacked ignored gate-entry translations and are not clean-engine passes;
a normal editor import rebuilt them, then every repeated run had zero engine
or script errors. A no-VFX real-Player movie recorded 1,138 original 60fps
frames and passed 9,499 live board checks. These are preliminary independent
checks, pinned separately from the ongoing implementation. They neither accept
the third round nor replace its new 24-facing walk/stop/attack/recovery chain
or the final installed-device matrices.

The third round's separate director snapshot was taken at 04:08 UTC. After
normal import rebuilt the ignored translations, independent runs passed
1,896 identity/stance checks, 13,218 forecourt checks, 354 gait checks and
1,176 painted-world checks, each with zero engine or script errors. The
manual motion harness passed 1,416 assertions across 103 samples with
`validate=1`. An earlier bare `validate` argument was ignored by the parser;
that diagnostic ran the timed headless loop and is not manual-validation
evidence.

All 16 four-times-nearest source contact pages were inspected: six heroes,
four facings, four idle frames and four walking frames (192 source frames).
All 24 attack contact pages were also inspected, covering both VFX modes,
every hero/facing and 60 consecutive original frames per cell. Both actual
1616-by-720 movies contain 2,338 original 60fps frames and passed 19,549
live checks with zero failures. Their stationary normal and close blocks
show attacks in all 24 facings; the separate six-player moving lane repeats
walk, stop, planted attack, recovery and departure and tallies all four stop
facings. The close block itself does not walk. The movie metadata records
seven stops per moving hero, at least five poses per cell and unchanged
motion floors. These desktop checks are not installed-device evidence.

Six deliberately broken controls in a separate secret-free negative copy
failed their intended assertions: a growing walking head, the previous idle
head, a front passing leg, a split side stance, a frozen walk and
state-dependent forecourt bounds. Restoring the exact three original files
made identity and forecourt checks pass again (1,896 and 13,218 assertions,
zero engine/script errors). The negative proof pins the logs and restored
bytes. No negative mutation reached either the implementer's copy or the
real tree.

The director's attack review record pins the 24 inspected pages and 188
production-art/import/generator/runtime files. At 04:31 UTC those files were
byte-identical to the still-running third-round draft. Final source matching,
acceptance, root verification, packed-artifact comparison and final native
matrices remain pending. No replacement binary was uploaded.

The implementer's third standing round finished successfully. A frozen final
director copy contains 2,728 files at baseline
`7af14d72e1c806f9e60ce86bcf3f7d60beb37407`; all 188 pinned visual production
files matched the previously inspected source/movie bytes at 04:43 UTC.
Its independent canonical-head run passed 1,896 checks and the actual
forecourt scene passed 13,255 checks with zero engine/script errors. The
forecourt count varies with live observation sampling. A diagnostic invoked
its Node script incorrectly through `--script`; it produced autoload compile
errors and is explicitly excluded, despite Godot returning zero. The proper
registered `.tscn` entry is the passing evidence.

The 70-file standing patch was accepted locally at 04:46 UTC. The frozen
copy's full verification and the real-tree import/build checks are still
running. A separate documentation-only brief 191 corrects the motion
harness's inaccurate close-block comment and records the work in the 4.0.0
build log. It does not reopen or modify the standing art. Final native
matrices, PR/merge and replacement store uploads remain pending.

### Accepted standing repair: current-root and replacement artifacts

The frozen final-copy verification exited zero; it predates the later quiet
inspection regressions. The current root then passed the complete `pnpm verify`
after brief 192 corrected a quoted internal reflection constant that the
locale-copy scanner had misclassified. The scanner and all translations are
unchanged. That narrow repair was independently checked in the implementer
copy and accepted; a deliberately missing inspection symbol failed the real
boot regression without engine errors. The current-root log is pinned in
`hero-character-standing-root-verify-proof.json` (SHA-256
`6b59279f8b8610f7c225a9ca71015368c9076df8b6cf42b7742b2033d1170a0c`).

The new code-18 APK and signed AAB contain all 100 current hero payloads
byte-exact: 12 idle/walk imports, 82 rig textures and six joint JSON files.
All 94 PNG source/import MD5 pairs were current. The APK SHA-256 is
`a0dbcf45b76f54bc7c9c5e9d1df6b6c8f3a94bea3345b9e564861cbc0a1bf13a`;
the AAB is `6e69311e2755c3e43d60da5a409112bdb473ce814e18cce357008bc9a1d7a284`.
Preserving installs on the emulator and the actual Galaxy Z Flip5, rather
than a physical Pixel 10, matched the installed APK bytes and all stopped
game-container files. No uninstall or SDK-preference reset was used.

The final emulator direction review covers all 24 clean, identifiable idle
cells and six full walk/dash movies. The director inspected 41 dense pages
containing 2,298 consecutive original native frames, plus every full-length
overview and QuickTime playback to its end. Native frame rates are variable;
this is not a claim of native 60fps. Dancer and Eclipse routes that touched
trees were excluded and replaced with separately pinned open-area routes.
The accepted record is `hero-character-standing-director-emulator-review.json`.
The physical Galaxy matrix is still running. A 150ms low-strength facing
gesture failed to move the Galaxy upward; the failed proof restored all game
files and is excluded. A stronger held gesture proves actual new facings
without weakening any readiness, identity or observation condition.

Normal iOS Debug build 13 and the App Store Release archive both contain
Assets.car and the Apple-login entitlement. The preserving iPad installation
kept all stopped game files byte-exact. The 100-payload PCK audit passed; the
host macOS tool reports expected iOS-only extension mismatch errors, so it
is resource evidence, not a clean native-engine run. The entire Debug and
Release PCKs match at SHA-256
`36a124467c1da65dacfe3dd11dac75151ba83fd500fc0e85f7f34a218609025a`.
The distribution IPA SHA-256 is
`8b45030f1637c6c87f053e978b927d4865c9df09093026d3ecdcfc9ad7a58d95`.
Local validate/upload dry-runs and Apple server Validate passed with no
archive errors; no TestFlight upload or review submission has occurred.

A real iPad QuickTime mirror showed the new title. The complete 74.793617s
native intro movie and all 150 two-fps overview tiles were inspected; this
is a representative title-party check, not an iPad input/direction matrix.
The human Apple/continue/cold-restart check was requested for this installed
build and remains pending. Firebase read-only GETs confirm current Google
and Apple account ownership, public-ID reservation and matching local/remote
checkpoint IDs. That ownership evidence does not replace the human check.

Hosting build and check pass: 49 care files, 142 docs files, 26 docs pages
and 2,068 local links. Existing 160 store PNGs are unchanged. The separately
run screenshot-freshness check is stale because game bytes changed; per the
user instruction, no marketing image, IAP image or capture provenance was
recaptured or regenerated. Native completion, final review/commit/PR/CI/merge
and both-store submission remain open.

### Final standing-source and documentation review

Briefs 193 and 194 corrected two measured documentation defects without
changing game bytes: idle breathing scales only the torso about the hips,
and the opaque painted body is about 28 world pixels, not the legacy 36.
The director independently re-read the bake, forecourt fit and registered
head/stance/transition tests, then measured all 192 production cells again.
The body height is 107–109 source pixels at alpha >= 32, or
27.285–27.795 world pixels at the unchanged 0.255 scale. The canonical-head
validator returned no identity errors. The measurement is pinned in
`hero-character-standing-director-height-recheck.json`.

The current-root full verification after those documentation repairs exited
zero. Its log is `hero-character-standing-final-root-verify.log`, SHA-256
`a9f67674c7a55d1df3c0d2b52ec1786dfc66e70eca1eab0cc2dbc145de493fff`.
It includes all 80 registered game/IAP checks, locale, repo hygiene, skills,
deterministic assets and the docs build. Brief 194 was accepted before the
docs build ran. Hosting build/check also passed after that repair. At
07:55 UTC all 188 production files pinned by the director's actual attack
movie review still matched the current root byte-exact; the independent
recheck is `hero-character-standing-current-source-recheck.json`. No later
product edit or PNG generation was made.

At 07:44 UTC all 160 retained marketing/IAP PNG hashes still matched their
baseline. `hero-character-standing-retained-image-recheck.json` pins that
comparison. Internal native QA recordings are not marketing recaptures.
The changed-runtime provenance check remains stale and has not been
regenerated. No replacement store binary has been uploaded or submitted.

The six-hero dense combat review on the physical Galaxy passed separately:
all six native overviews and the complete 72-second QuickTime movie were
inspected, with no native errors and byte-exact stopped game-file restore.
The pinned record is `hero-character-standing-director-galaxy-combat-review.json`.
This is representative combat evidence, not the quiet facing/motion matrix.

### Final physical Galaxy standing and motion review

The physical Galaxy Z Flip5 quiet matrix is complete. The accepted record is
`hero-character-standing-director-galaxy-review.json`: 24 distinct, clean idle
facings and six walk/dash movies, with all four actual walking frames observed
in every facing. Sixteen idle cells use the original held-route evidence;
the Sage and Dancer cells use the separately observed facing-B replacements.
Five motion movies use observed-motion A; Dancer uses observed-motion C.

The director inspected all 70 accepted dense pages, containing 3,242
consecutive original native frames, every full-duration overview and the
movies in QuickTime through their ends. No synthetic or interpolated frame
is included. Native timing is variable, not a native-60fps claim. During
these sequences the head/face identity, body scale and supported foot anchor
stay consistent across walk, stop, dash and recovery. All bodies remain
visible with a terrain gap during the approved quiet evidence. The separate
six-hero combat review covers the physical weapon motions in representative
combat; it is not substituted for this quiet matrix.

Excluded observations stay excluded: the old short, weak gestures did not
prove walking; obscured old Sage/Dancer idle cells were replaced; Dancer
motion A overlapped a tree; motion B also reached a tree at the dash endpoint.
The replacement C operational route shortens the walking input from 700ms
to 450ms and the pre-dash facing input from 250ms to 100ms. It still requires
four distinct walking frames per direction and every original clean-scene
condition. No production code, readiness threshold, collision, terrain or
character state was weakened or teleported for those routes.

Every accepted route reports zero native errors and byte-exact restoration
of the stopped game-container files. No uninstall, SDK-preference reset or
Keychain reset was used. The installed APK hash is the final code-18 hash
recorded above. The Galaxy is a Samsung SM-F731N, not the course's Pixel 10.

### Two final local product-review rounds

| Round | Independent angle and evidence | Confirmed product defects |
| --- | --- | --- |
| 1, after brief 194 | Re-read the production bake, head registration, forecourt union fit, live-transition tests and the corrected manifest; independently measured 192 cell heights and re-ran the canonical-head validator; compared all 188 rendered-review source files with the current root. Final root verification includes all 80 registered game/IAP checks and the docs build. | None. `hero-character-standing-director-height-recheck.json` and `hero-character-standing-current-source-recheck.json` pin the measurements and byte comparison. |
| 2 | Checked the final packed-artifact boundary, all 24 physical Galaxy stills, all six clean native motions and representative combat; rechecked final APK/AAB/IPA hashes and the full-verification log hash. All 160 retained marketing/IAP image hashes remain unchanged. | None. `hero-character-standing-release-boundary-recheck.json`, `hero-character-standing-director-galaxy-review.json` and the retained-image record pin the boundary. Failed capture routes above are excluded evidence, not new product defects. |

The local product review stops after these two clean rounds. This does not
declare all release gates complete. The current installed iPad build still
needs the human Apple/continue/cold-restart interaction check requested at
05:56 UTC; the inspected iPad title is representative evidence, not an
exhaustive iPad direction/input matrix. PR/CI/main merge, Hosting deployment
and replacement uploads/submissions are also pending. Android 18 and iOS 13
remain built and validated locally, with no replacement upload. Existing
marketing/IAP uploads and local PNGs remain unchanged.

### Replacement build staging after the renewed submission request

The renewed request authorizes continuing both-store release work. While PR
creation remains blocked on the absent human marker, the director completed
the already authorized preparation of concrete store candidates. No formal
review submission or production promotion was performed ahead of PR/CI/main
merge. The earlier no-upload statements above describe their observation
times; the current state is recorded here.

iOS 4.0.0 (13) passed the upload dry-run and uploaded successfully through
the normal signed IPA workflow. Delivery UUID is
`7d067dba-43e8-4358-b54c-6f81550bf736`; Apple reported 86,853,457 transferred
bytes with no upload errors. Independent GET at 08:59 UTC confirmed that
build as `VALID`. The retained-gallery readiness plan had exactly two
updates and 104 unchanged targets, with no unresolved target. Applying that
plan changed only the build association and internal beta-group assignment;
the tool revalidated by GET and reported `review submitted: no`.
Independent GET at 09:09 UTC confirms the linked build is 13/VALID and the
4.0.0 version is `PREPARE_FOR_SUBMISSION`.

The first post-upload readiness GET encountered an Apple HTTP 500 on
`inAppPurchasesV2`. A new read-only audit succeeded without changing code or
weakening any gate. The proof files are
`hero-character-standing-asc-latest-builds-readback.json` and
`hero-character-standing-asc-build13-association-readback.json`.

The Android binary-only local check initially refused the AAB because
`export_presets.cfg` had a later saved timestamp after the iOS workflow.
Both it and `project.godot` still matched committed bytes. The director ran
the normal signed `pnpm android:bundle`, rather than modifying timestamps
or the freshness check. The rebuilt entire AAB is byte-identical at
`6e69311e2755c3e43d60da5a409112bdb473ce814e18cce357008bc9a1d7a284`.
All 100 hero payloads match both current source and the reviewed installed
APK, whose hash is still
`a0dbcf45b76f54bc7c9c5e9d1df6b6c8f3a94bea3345b9e564861cbc0a1bf13a`.
The source, images, behavior and versions were not changed. The first
diagnostic looked in the base ZIP module instead of the actual install-time
asset pack; that path error is excluded, and the corrected namespace audit
passed all payloads in
`hero-character-standing-repacked-android-artifact-proof.json`.

Google Play internal 17 -> 18 binary-only apply succeeded, reusing the
committed ordered gallery. The dedicated owner-only receipt is
`builds/release/google-play-binary-only-4-0-0-18-receipt.json`, state `APPLIED`,
edit commit `17114852848825663133`. The existing 3.0.0/code-16 receipt was
left untouched; no old or uncertain receipt was deleted or repurposed.
Post-apply local check prints valid separate production-promotion and
review tokens. Neither operation has run. Metadata, listings, images,
prices and products remain unchanged.

The internal QA comparison board combines only the 24 accepted Galaxy
facings, with the replacement Sage/Dancer evidence, without resizing or
altering source pixels. It is not a marketing image. All 188 pinned visual
production files still match the reviewed source after packaging. These
operations introduce no new product change and do not reopen the two clean
product-review rounds. Current iPad human interaction, the human PR marker,
PR/CI/main merge, Hosting deployment, production promotion and formal
reviews remain open.

Independent Google Play GET at 09:12 UTC confirms internal build 18 is
`RELEASE_LIFECYCLE_STATE_PUBLISHED` on the internal track, while production
still carries published build 17. This is not a production-18 release or
review submission. The exact readback is pinned in
`hero-character-standing-play18-track-readback.json`.
