# Brief 166: execute the tested prewarm orchestration in production

## Correction to brief 165
The live diff currently adds `runXcodeFrameSequence`,
`quiesceExactProductionProcess` and `assertXcodeFrameBroadContinuity` to the
library, but the real capture producer does not import or call them.
Their comments explicitly say they mirror the producer. A fake-device test
of unused duplicate logic does not demonstrate that the production race is
fixed. The director cannot accept new test-only implementation mirrors.

Connect narrowly scoped injected orchestration/guard helpers to the actual
ordinary and guardian producer paths, with the same sequence and existing
SIGSTOP/SIGCONT cleanup. Alternatively remove unused helpers and test the
real producer functions in an isolated harness with fake device operations.
Do not retain a second unused implementation just for tests.

Keep the exact final-quiescence evidence and both broad pre/post frame
checks. No quiescence after screenshot acquisition is allowed. Keep original
PID, device, signing, byte, state and canonical-publishing guards unchanged;
no game/asset/metadata edits.

The fake-device prewarm case must exercise the helper/function the real
producer uses. Removing the final quiescence in that production execution
path must fail it. Source integration assertions may supplement behavioral
tests, but not substitute a test-only mirrored algorithm for the real one.
The director will independently inspect call sites, run focused tests,
mutate the actual used path, restore it exactly and run full verification.
