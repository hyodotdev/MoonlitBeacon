# Correction brief 022: Remove the staged generator's forbidden token

Continue `20260930-2321-kinetic-hero-weapons-and-audio` after round 5.
One newly confirmed merge-check failure; no combat, audio or capture redesign.

The director's independently run `pnpm check:hygiene` now scans the staged
new audio generator, and fails its local oscillator variable at lines 107–108
in `apps/game/tools/build_combat_audio.py`. Earlier untracked-file checks did
not cover it. The brief-021 entry in `notes/plans/3-0-0-build-log.md` quotes the
same forbidden lesson-numbering token and also fails. Keep the checker/guide
unchanged; comply with the existing naming rule.

Rename only that local oscillator variable to a permitted clear name and
remove the forbidden token from the new build-log explanation. Preserve the
complete synthesis expression, sample parameters, RNG calls and call order.
Correct the report with the staged-file distinction and observed results.
Only these two deliverables plus the report; no other source edits.

Acceptance: full tracked/staged `pnpm check:hygiene` passes. The existing
`build_combat_audio.py --check` succeeds, and all seventeen custom combat
WAV files remain byte-identical by SHA-256. No rebake, test suite, git/network,
device/store/user-save work. The 667-file production witness must stay
unchanged. Existing approved music and the passing capture/runtime evidence
remain valid. This is a small naming correction, not a new game feature.

## Newly confirmed observation aliasing (same capture tool only)

The director's normal full windowed round-5 harness completed with one of
718 checks failing: `dancer strong left primary shows for the strip`.
All lane/primary-direction/body/hit/recoil/beacon checks passed; only 188
hero frames were saved because that one strip was correctly withheld.
Log: `builds/director-final-r5-weapons.log` in the copy.

An ignored operational observer of six repeated Dancer strong-left stages
reproduces the failure (1/119) while observing the actual primary every
process frame. The failed stage repeatedly polls false at cooldown
0.00919 / 0.04252 while the independent per-frame counter reaches 333:
the primary was visible on many frames between polls. Marks are 34px away,
within actual range 44.84, and tree_paused=false. Thus the weapon is firing
correctly and marks are reachable; this is observation aliasing from the
0.25s poll timer against the rapid weapon cadence / 30Hz ticks, not a game
or target-range defect. Log: `builds/director-dancer-frame-observer-r5.log`.
A prior six-stage range observer passed 113 checks; retain both observations.

Also correct the primary-anchor wait in `shot_weapons.gd`: inspect each
process frame with the same bounded six-second deadline instead of sampling
only every 0.25s. Keep controlled live-mark top-up, real attacks/hits/current
visible primary, body/rig/flight checks, recoil and post-draw 0.6s strips.
Do not return a cached past effect as a currently visible anchor or pose a
flash. Headless validation must not await frame_post_draw; preserve the
isolation gate and remove temporary prints. No production gameplay edits.

Run full six-hero early/strong/four-side validation and repeated Dancer
strong-left checks; compare with the observed timer-alias counterexample.
The director then repeats the original windowed full harness. Add a short
factual build-log/report entry distinguishing this new sampling defect from
the already-fixed lane-direction and pause problems. This expands the
permitted surface to this one capture tool plus the two naming deliverables
above. Approved WAVs and all production witness hashes stay unchanged.
