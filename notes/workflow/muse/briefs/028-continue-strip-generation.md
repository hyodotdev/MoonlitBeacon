# Investigate delayed story-strip ownership across continue

## User words
"/loop-review 돌아서 확실하게 해줘 pr 만들어 이번에는 내가 승인"

## Where we stand
The 3.0.0 renewal is committed on feat/3-0-0-ui-story at 6b9a658.
The director is doing a fresh review of the whole branch. Four earlier
corrected-root full verify runs passed; a new root verify is running now.
Final Android captures and local Play image/package checks passed. No PR
or store upload has occurred. Do not touch those artifacts or their proofs.

Source inspection suggests a possible continuation race; it is NOT yet a
confirmed defect. In arena.gd, _finish increments _run_generation but does
not reset _strip_flush_running or its pending presentation fields.
_flush_strip waits on real timers, breaks on a generation mismatch, then
unconditionally clears _say_deferred_line/_places_pending and resets the
running flag. continue_run revives the same arena. A stale worker might
therefore clear new presentation queued after a fast, valid continue.
The discovery guard is only three seconds; establish whether the race is
actually reachable rather than assuming that it is.

## Do
1. Reproduce or disprove this specific race in the isolated copy. Use the
   real arena death/result/continue path, a valid isolated Vault coin
   fixture and actual beacon/discovery/voice scheduling. Use the production
   timer intervals. Do not fake a generation change, manually inject the
   queue, extend a production timer or bypass the coin debit to claim a
   reachable player defect. The existing testable arena and capture-safe
   debug beacon actions can arrange the gameplay state.
2. If confirmed, implement the smallest ownership/reset correction so an
   old worker cannot clear or unlock a newer worker's pending presentation.
   Death must still suppress its old speech, valid continue must still
   spend exactly one coin, new discoveries must still be recorded/readable,
   and the existing per-run seen records must survive continuation.
3. Add a meaningful regression to the registered place-memory test suite.
   Demonstrate that the actual original behavior fails that new regression
   and the correction passes. Check normal death, fast continue and another
   subsequent deferred voice, not only a happy first callback.
4. If the race cannot be reproduced under the real constraints, return a
   report with the commands, timing observations and reason. Make no
   speculative production change.

## Do not
- No feature, art, music, combat balance or IAP contract changes.
- Do not change price/ownership metadata, engine/renderer, budgets,
  capture contracts, fingerprints, reports, signing or locked versions.
- Do not modify director workflow files, git history, guards or stores.
- Do not turn unrelated teardown warnings into a guessed fix.

## Acceptance
- Evidence establishes a reachable original defect, or convincingly
  disproves this one suspicion. A source-only hypothesis is insufficient.
- If fixed, the original-code negative control fails the new live-path
  assertion; byte-exact restoration and the fixed regression pass.
- Existing place-memory, result/continue, story and combat-audio suites
  remain green. Run with pnpm godot:isolated; scene entry points preserve
  autoloads. No real user save is accessed.
- The change does not add runtime nodes or loosen the 1200-node budget.
- A production change goes through director review/acceptance before it
  reaches the real tree; the director will rerun related checks there.

## Deliverables
If a defect is confirmed: apps/game/scripts/gameplay/arena.gd and the
existing apps/game/tests/test_place_memories.gd, with only necessary related
test support changes. Record the measured result in
notes/plans/3-0-0-build-log.md if a fix is made. Otherwise the implementer
report is enough; leave source untouched.

## How the director will judge
Read the complete changed functions and test diff, rerun the isolated
live-path test and related suites in the copy, independently disable the
ownership correction and restore it exactly, then accept and run the root
verification. Report screenshot freshness honestly if runtime changes.
