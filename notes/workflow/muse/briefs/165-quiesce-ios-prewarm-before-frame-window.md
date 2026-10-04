# Brief 165: close the iOS prewarm race before the frame window

## The ask
“자러가야되는데 배포까지 잘해놔 리뷰 심사 받아”
Finish the already authorized 4.0.0 release. This task fixes only a confirmed
race in the iPad capture producer; it does not change the game.

## Why and where things stand
The fourth full Xcode capture run accepted title, shrine and hero, then
failed before requesting barrage. `reactivateCaptureProcess` established
exactly one isolated capture process. The two subsequent runtime-state
observations took roughly 147 seconds. The final broad pre-frame check then
found the same isolated PID plus the original production executable.
The physical device's unified log identifies the new process as
`DAS Prewarm launch` originated by `com.apple.dasd`, followed by
`running-suspended-NotVisible`. This is OS prewarming, not a user tap or an
OAuth callback. The normal producer had no production-bundle launch call.

`scripts/capture-ios-device-evidence.mjs` already has exact installed-path
`quiesceProductionApp`, same-PID foreground reactivation, broad single-game
continuity probes both before and after the Xcode handoff, SIGSTOP/SIGCONT
finally cleanup, isolated bundle removal and original identity/data
preservation. Those guards must remain intact. The early quiesce happens
before the long state-observation window and cannot prevent later prewarm.
No successful final iPad marketing set exists; do not fabricate one.

## Do
- Make the existing exact-path production quiescence occur once more at the
  last safe point before opening the native frame window, after the slow
  runtime observations. Preserve the original broad single-process checks
  before and after the screenshot. Record the final quiescence observations
  in evidence so the director can trace which process was stopped.
- Apply the same order to ordinary and guardian Xcode capture paths. Reuse
  the existing exact-path termination operation and PID ownership checks.
- Add meaningful orchestration regressions using fake operations, including
  a production prewarm introduced during state waiting, an unrelated game
  competitor, mismatched capture PID and failures in quiescence. Old ordering
  must fail the prewarm case. If an existing helper can model this sequence,
  extend it; keep the refactor narrow.

## Do not
- Never quiesce or sanitize a competing process after the screenshot has
  been taken: a post-frame competitor must still fail continuity.
- Do not ignore original production processes in broad queries or relax
  exact single-PID checks. Do not retry a failed frame as successful.
- Do not modify game files, native artifacts, version numbers, capture
  fingerprints, stored receipts, timeout constants, expected screenshot
  hashes or canonical publishing rules.
- Do not change device settings, uninstall production, touch its container,
  add network access or perform a device capture. Director handles devices.

## Acceptance
- Focused iOS evidence tests and related Xcode handoff tests pass.
- A negative mutation removing the final quiescence fails an orchestration
  regression; exact restoration passes.
- Broad post-frame continuity still rejects a production or unknown
  competitor and PID changes. Failure cleanup still resumes/terminates only
  the owned capture process and restores the original production identity.
- `pnpm verify` passes; no change under `apps/game/` and no asset/metadata
  edits. Full physical recapture is the director's later check.

## Deliverables
`scripts/capture-ios-device-evidence.mjs`, a narrowly scoped helper under
`scripts/lib/` only if needed, and registered meaningful regression tests.

## How the director will judge
Read the entire diff and relevant source ordering, run focused tests,
negative mutation and full verification independently, then perform a fresh
normal Xcode capture with unchanged image, PID, source and signing guards.
