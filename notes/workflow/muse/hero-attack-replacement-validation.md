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
