# Brief 159: Keep the distribution probe fix separate from the accepted marker test

## Confirmed overlapping change
While task 156's copy was running, the director independently judged and accepted brief 155 in the real tree, committed as d6e0a11. That task already fixes the stale title-marker source assertion in scripts/lib/capture-run-state.test.mjs and pins all scoped predicate guards (debug build, real-title resolver, occlusion, screen visible, exact version) plus four-frame writer order. Independent current tests: capture-state 40/40, Android 130/130, Play 232/232; marker-guard bypass negative fails and exact restore passes.
Your copy started before that acceptance. Its obsolete host assertion failure is now resolved in the real tree, and the new change to the same test both duplicates that task and would conflict on normal accept. Do not replace the already verified stronger real-tree assertion with the copy's alternate version.

## Do
Restore ONLY scripts/lib/capture-run-state.test.mjs to your copy's original baseline (git show HEAD:file or equivalent). Leave your confirmed production probe fix, new tests and registration intact. The resulting task diff must omit this file. Report that the copy's old marker source assertion remains stale but is independently fixed by brief 155 in the real tree; the director will run the full current host suites after normal acceptance. Run your final focused Godot suites and all remaining relevant host tests without weakening their definitions. Do not modify host code to hide failures.

## Do not
No rebase, network, git-history changes or copying the real private repository. No other changes outside brief 156. Do not change the actual strict predicate/proof fields, production marker, saves or assets. Do not patch the guard or bypass acceptance.

## Acceptance
Cumulative diff omits capture-run-state.test.mjs. Direct-distribution production/standalone/occlusion behavior remains verified and old-root negative still fails. Explain the isolated stale host-test result accurately, never call the obsolete-copy full suite green. Current-root full suite after acceptance is the final integration gate.
