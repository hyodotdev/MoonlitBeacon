# Correction 001c: A guardian gauntlet measures one fight

Keep the frozen bullet balance, resources, tests and art exactly as they are. Do not tune to this batch.

The director repeated the natural batch successfully: 12 runs, 46.89 simulated minutes, 1.173 hits/min,
23.12 scattered/min, mean weaving 33.08%, bullet peak 52 and no stuck or soft lock.

The gauntlet command in the judging battery leaves `loops` unspecified. In `play_bot.gd`, `_loops_max = 2`
and `_loops_target = _rng.randi_range(1, _loops_max)` still apply when `gauntlet=1`, although the documented
contract says one guardian fight per run. `_fix_route()` boosts only the initial fight. The director's run 10
(Knight, frost guardian, cycle 2, seed 1021) won that fight, then kept exploring the following cycle until the
2400-second bot cap. That is a synthetic harness run-cap observation, not evidence that the game is soft-locked.
The director stopped the partial batch and is repeating with explicit `loops=1`.

1. Make gauntlet mode select exactly one loop/fight regardless of the default/random natural-run loop target.
   Natural mode still honors its current `loops` behavior. Keep steering, targeting and all instruments unchanged.
2. Remove the source comment claiming bot deaths are a floor for people: no human comparison established it.
   Describe automated proxy limits plainly, without changing measurements or using a human-play claim.
3. Check the mode boundary with a small meaningful headless test or validation of the target-selection rule,
   and mutation-check it. Register any new regression test. Do not rerun hours of tuning; a short gauntlet
   `loops=2` diagnostic must settle after one fight, and a natural run must retain the chosen target.
4. Update only the necessary game-reference or build-log sentence about the command and report the director's
   partial batch honestly. Preserve the older measurements as dated, separate observations. The director will
   reconcile full records in brief 007.
5. Preserve all existing tests, version/build locks, store files and screenshot bytes. No network, devices,
   git-history operations or protected-path edits. All temporary helpers stay inside your workspace.

Finish the report with the changes, exact checks and limits. The director reads the diff, repeats the boundary
check and judges the already-running one-fight measurement. Do not change protected `scripts/lib/muse-judge.mjs`;
the corrected mode makes that existing command truthful too.
