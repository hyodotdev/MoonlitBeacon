# Brief 229: project desk collisions onto walkable floor

## The ask
Finish the immersive gate-lodge introduction with stable movement and full root verification.

## Independently confirmed defect
The second root pnpm verify passed the corrected Vault test and reached the lodge suite, which reported2435 checks with1 failure: guard: the desk slides the hero out. Standalone rerun passed0 failures, so this has a timing/framing component; do not merely add sleeps or weaken the assertion.

The director invoked the real _push_out_of_desk method with real layout_for outputs in an isolated real lodge/player scene. At880x360, the desk center (167.2,74.39999) projected to (167.2,14.73333), outside the walk floor whose minimumy is117.4222. The method chooses the nearest desk edge without requiring the destination to remain in _walk_rect; floating-point center ties choose different edges at other ratios. The real player physics then clamps that invalid point back into the walk band, still within the desk, exposing frame-order-dependent overlap. Evidence: builds/verify/gate-desk-walk-root-proof.log. The actual full failure is gate-root-final-verify-rerun.log; standalone pass is gate-lodge-root-collision-failure.log. All are director evidence in the real tree.

## Do
- Correct desk projection narrowly so the resulting point is outside the desk AND inside the valid walk floor. Choose a valid nearby exit without depending on a floating-point equal-distance tie. Respect real layout/player bounds. Avoid an invalid point followed by a later player-clamp correction.
- Add deterministic registered collision assertions over all four existing framings plus representative desk edges/corners/center and subsequent real bounds/physics settling. Check both constraints after projection and after settling, not only a pre-physics snapshot. Preserve normal sliding, Lumi personal space, joystick/dash lessons, warm room framing and old behavioral assertions.
- Repeatedly run the actual lodge suite (at least3 clean runs) and show a negative control restoring the old projection makes the new guard fail deterministically at880x360. Leave deliberate contact-sheet negative-control diagnostics distinguishable from real suite failures.
- Run meaningful movement/lesson/adjacent regressions and report the measurements. The director verifies actual rendered movement and full root checks afterward.

## Do not
No unrelated refactor, timing-only workaround, removed/weakened tests, actor art/scale/spawn changes, reward/name/native/auth/privacy/versions change, hidden failures, marketing recapture or store actions. No protected paths or director notes may change.

## Acceptance
Desk projection always leaves the hero on walkable floor outside furniture for the real wide/tablet framings, and subsequent bounds clamping cannot re-enter it. Registered regression fails with the old method, passes repeatedly with the correction. Lesson flow and character presentation stay unchanged.

## Deliverables
Narrow production collision correction, meaningful registered tests and accurate report; optional author-only build-log entry.
