# 3.0.0 renewed loop review

The user requested another `/loop-review` and explicitly approved the push
and PR proposed in the preceding reply. Review scope is the whole
`origin/main...feat/3-0-0-ui-story` renewal, not only its last commit.
The game checkpoint reviewed is `6b9a658`; base is `17761af`.
Subsequent changes in this review are director workflow records only.

## Round evidence

| Round | Re-read / measured | Outcome |
| --- | --- | --- |
| 1 | Whole changed-file inventory; expedition, acts, Chronicle, arena finish/continue/discovery/guardian/cycle paths, hero voice, results, six weapon specifications and player rig/recoil, preview/shrine diffs. Fresh `pnpm verify`, log `builds/verify/director-loop-review-20261001-final.log`, exit 0. | Fifth corrected-root full pass: 470 Node checks in sixteen groups, all 52 game steps, 122 script compilations, locales/store metadata, assets, skills, hygiene, docs and anchors. Knight Lv40 peak 1,186; 73 performance checks. One strip-worker ownership hypothesis required investigation; no production defect was yet confirmed. |
| 2 | Muse assignment `20261001-2325-continue-strip-generation`, briefs 028/028b; complete proposed arena/test diffs and both reports. Compared Dialogue pause, ResultPanel's 0.6s input gate, beacon charge and travel with the claimed reproduction. | Rejected both proposed proofs: round 1 forces death while the tree is paused and continues immediately; round 2 skips player travel and the new beacon's 1.3s charge. Their artificial failures do not establish a player-reachable defect. No proposed production/test/build-log changes were accepted. |
| 3 | Brief 028c asks for production timing and also checks awakening. The copy's last experimental tool task stopped making progress; the director ended that run normally with SIGTERM (exit 143, no final report). Independently ran its implementer-written natural continuation characterization against byte-exact original `arena.gd` using `pnpm godot:isolated --timeout 600 res://tests/test_place_memories.tscn`. | **None confirmed — first clean round.** Original code passes 977/977 in 54.5s, including the real result input gate, one-coin debit, preserved discovery record, subsequent fork and guardian lines. Original arena SHA-256 `f47e348a99a3c23cc1e64bf2bc625e8b0a4e3f7b9080d19c39a4b1109ab93876`; the proposal was restored byte-exactly afterward inside the rejected copy. This verifies the measured normal path, not every possible fast awakening setup. The unconfirmed ownership proposal and its synthetic regression stay out of the real tree. |
| 4 | Changed angle to publication/release evidence: runtime witness, all ninety Play candidate hashes, all one hundred IAP metadata rows versus main, three inspected Android artifact hashes, current main merge calculation, CI workflow/guard isolation and disclosure in the PR body. Re-read `muse-run`, `muse-workspace`, `godot-run`, capture persistence, CI game/error/compile/locale steps and PR guard. Repeat final binding checks after round 3; hygiene and skill synchronization. | **None confirmed — second clean round.** 667 runtime files unchanged; 90 candidate PNGs unchanged; 100 IAP rows equal; signed AAB/direct APK/capture APK match their inspection hashes. Main merge calculation has no conflict. Existing native-device, iOS signing and App Store provenance boundaries remain explicitly incomplete; they are not new code findings. |

## Checked evidence and limits

- Root full check is the fifth pass after the release-review corrections.
  Its Node totals are 34/9/4/211/10/58/51/4/8/21/2/8/39/4/4/3.
  The place-memory suite in that root run passes 951 checks; the 977-check
  natural continuation diagnostic is separately run in the copy and is
  not committed or claimed to be part of the root suite.
- Original-code diagnostic output and exact restoration proof:
  `builds/verify/director-loop-review-original-natural-continue.log` and
  `builds/verify/director-loop-review-original-natural-continue.json`.
- The source hypothesis is left unchanged because the available failed
  fixtures require unreachable timing shortcuts. Normal-path success does
  not prove a universal absence of races. No speculative fix is claimed.
- The three earlier confirmed release-review corrections and phone
  framing correction are already committed and covered by the five full
  root passes. Their independent negative controls are in the release
  director record.
- `pnpm check:store-screenshots` passes the Play portion and exits 1 at
  missing App Store provenance. Log:
  `builds/verify/director-loop-review-store-check.log`. No recapture or
  store upload occurs in this review. Play's separate local apply check is
  ready, blockers empty, uses no network and retains manifest digest
  `49a36ba1dfe649f221615d716d66de56a0d3ec1af6bd640da46e7e6ec24eb073`.
- Re-viewed the Korean six-screen Play board. Dialogue and dash are fully
  visible in the corrected framing; shrine and hero preview are present.
  Other locale/device boards retain their inspected bytes.
- Native physical-device direction/play tests and native ten-product IAP
  evidence remain pending. iOS still needs valid signing-key access and
  physical iPad capture. The title suite's existing RefCounted teardown
  warning remains disclosed, with no guessed audio fix.
- `.playwright-mcp/` is unrelated and is excluded from staging. No secrets,
  `.godot`, original asset packs, remote store writes, certificate changes
  or user-app replacement are part of this review.

## Publication

Approved target: `hyodotdev/MoonlitBeacon`, head
`feat/3-0-0-ui-story`, base `main`, title
`feat(game): renew moonlit beacon for 3.0.0`.
Body: `notes/workflow/muse/pr-3-0-0-ready-body.md`.

User push/PR authorization is received. The repository additionally
requires the human-owned `.claude/allow-pr` signal, which the director must
never create. Publication outcome and any resulting CI status are recorded
below when observed; native/store completion is not inferred from code
checks.

## PR follow-up on 2026-10-02

The human guard signal was consumed by the original guard and PR 10 was
created: https://github.com/hyodotdev/MoonlitBeacon/pull/10. The original
head passed docs, repo rules and Android builds but failed the Linux
`orbit sweep is a full circle` assertion. Five Mac full checks had not
exposed that platform boundary; it is not waived.

Confirmed corrections go through briefs 029, 030/030b and 032. The circle
fix covers full moon, Eclipse orbit and genuine Wide Arc takes reaching
360 degrees while retaining partial arcs, radial limits, damage and
cadence. The two App Store tool corrections handle distinct released
history and current-payload authorization instead of an obsolete literal
2.1.0 (9) gate. Their accepted diffs do not change products or prices.

| Round | Independent evidence | Outcome |
| --- | --- | --- |
| 5 | Final accepted-diff review; exact restoration; original circle negative control 2/388 failures; special-flags-only negative control 2/404 failures; final weapon scene 404/404, exit 0. App Store suite 58/58 without skips; original history predicate and original target pin fail their intended new regressions. | First clean round after the confirmed corrections. No further production defect in these boundaries. |
| 6 | Different angle: full corrected-root `pnpm verify`, exit 0; 477 Node checks in 16 groups, 52 game steps, 122 scripts, locale/100 IAP rows, deterministic assets/graphics, hygiene, docs and anchors. Re-hash all 667 runtime witness files: only the reviewed arena differs. Fetch current main: zero commits behind. | Second clean code-review round. Corrected-head GitHub Linux CI still must pass before merge; native and capture release gates remain incomplete. |

Evidence is in `builds/verify/director-pr10-corrected-root-verify.log`,
`director-pr10-corrected-runtime-witness.json`, and the director logs in
the three accepted Muse run folders. These records do not claim native
purchase E2E or a completed store release.

Signing is now resolved and TestFlight 3.0.0 (10) is VALID and assigned
to the existing internal group. Play internal 3.0.0 (15), five-language
copy and ninety new images are applied and independently read back.
Six native landscape English iPad images are accepted, but five locales
are not complete. The producer was canceled cleanly with no restoration
errors. Both public reviews and merge remain unperformed.

The old Android capture source fingerprint fails after the circle fix;
uploaded image bytes are preserved and no automatic recapture occurs.
User answers are pending for protected next-build configuration, native
ten-product checks, and final-build capture evidence. Current status is
in `store-submit-3-0-0.md`; remote CI evidence belongs to the PR's latest
published head, not an earlier green job.
