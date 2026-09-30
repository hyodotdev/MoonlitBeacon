# Brief 009: A worker-load regression must wait in real time

## The ask and evidence

The user asks to finish the 3.0.0 renewal, repeatedly review it and make its PR mergeable without merging.
The director's root `pnpm test:game` failed only at title-transition worker completion under simultaneous
desktop play: expected THREAD_LOAD_LOADED (3), actual THREAD_LOAD_IN_PROGRESS (1). Source files and imports
were present; the immediate process exit then printed preload failures. A sequential isolated repeat passed
11 cases in 2.2 seconds. The test currently spins for 600 headless frames, which is not a worker wall-time
deadline. It also checks status without consuming the loaded request. This is a confirmed flaky check, not
evidence that the player's actual title transition hangs.

The same test emits 17 leaked RefCounted instances (reference counts zero); consuming the request in a
temporary director probe passed 12 cases but still emitted 15. The game suite's older baseline also had
this warning. Do not assume this is an audio leak or invent an unverified production fix.

## Do

1. Make `apps/game/tests/test_title_transition.gd` bound worker waiting by a sensible real-time deadline
   and give its worker time between observations. Preserve real worker request, freed-title guard and all
   eleven assertions. Consume the completed request and verify it contains the arena PackedScene.
2. Cover slow progress, successful completion and failure/timeout meaningfully. A small test-local wait
   seam is allowed if it checks the same rule; never weaken the expected completion or swallow engine errors.
   Mutation-check the deadline/completion boundary. Clean up test-owned resources before quitting.
3. Run the affected regression repeatedly, including a slower diagnostic, and the full registered suite
   through the isolated runner if the sandbox cannot run its import stage. Record any remaining warnings
   honestly. Do not expand this into a production resource-loader refactor based on a guessed leak cause.

## Scope and acceptance

Only the title-transition test and necessary test collateral may change. No production code, scene, game
balance, story, UI, package, registry removals, versions, protected files, docs, stores, network, devices or git
operations. A separate story integration is running in another copy; keep this deliverable disjoint.

The director will read the full change, repeat the regression and negative check, and run final root verify.
Finish `IMPLEMENTER_REPORT.md` with exact commands, results and unresolved warning scope. No new output filtering.
