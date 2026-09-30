# Brief 011: Keep the spatial performance check deterministic

The user asks to finish the renewal and make its PR merge-ready after repeated review. The director
confirmed another flaky regression on the real tree: two sequential
`pnpm godot:isolated --timeout 120 res://tests/test_late_game_performance.tscn` runs passed then failed
only `spatial-cell candidates are under 25% of a full scan`. Logs are
`builds/verify/director-late-repeat-a.log` and `director-late-repeat-b.log` (not present in your copy).
Passing Lv40: 3798/18720 candidate/naive visits, 91 physics steps, 1129 nodes.
Failing Lv40: 4672/18200 visits, 90 steps, 1130 nodes. All other 17 cases pass. Another isolated copy
independently recorded pass/fail/pass, with a failure at 6700/22000. This is confirmed sampling dependence,
not a demonstrated production spatial-index defect. The test's own comment already acknowledges clumping.

Change only `apps/game/tests/test_late_game_performance.gd` and necessary test collateral. Keep the live
immortal-wall staging, 34/40 spirits, fire-rate/lane/trail density, damage checks, 1200 node limit and
256 candidate visits per physics tick. Keep logging the live ratio and timings honestly. Do not delete
enemies, reduce bullets, change production balance or simply loosen 25% until the current samples pass.

Move the factor-four spatial-selectivity guarantee onto a deterministic spread/adjacent-cell fixture
using the actual missile sweep/index and work counters. It must catch switching the index to a full scan,
preserve direct-hit and neighboring-cell splash behavior, and not depend on frame scheduling or random
live clustering. A test-local fixture is allowed; no production code, docs, registry removals, versions,
stories, stores, network, devices or git operations. Other implementer copies own the title test and story.

Run repeated sequential and contended diagnostics, plus a meaningful full-scan/selectivity mutation and
restore. Report exact counts, live budgets, remaining environmental warnings and command results. The
director reads the full diff, repeats the negative and restored checks, then runs final root verification.
