# Complete the moving-attack proof

Keep the accepted direction of the physical repair: the director's new
60 FPS no-VFX movie shows correctly sized and lit arms. The independent
unchanged attack suite passes 4552 cases. The repair remains in this copy,
not the real tree; preserve combat timing, damage, original sheets, all
earlier assertions and the real drawn-arm transform checks.

One observed harness defect prevents judging the moving gait: see
`builds/hero-attack-review/round4-motion-only.avi`,
`round4-board-3s.png` and `round4-board-10s.png`. At 10 seconds only three
movers remain visible. `_run_timed_loop()` increments `cycles` once per
hero, then selects left/right by that parity. Six heroes make the parity
repeat for each hero on the next pass, so each hero walks one way forever.
Their bounds include off-screen space. Fix the loop and visible lanes so
each hero repeatedly travels both ways while aiming against movement,
stays fully in view and stays separate from other bodies. Do not teleport
the body between observations. Frame-check the complete timed run, not only
the starting positions; all six moving bodies/weapons must be inspectable
for the whole movie. Keep 1616x720 and every normal/close facing.

Close the related test gaps while measuring actual state transitions.
`_test_attack_gait()` calls `dash()` only after `_finish_attack()` and does
not observe any drawn leg frame during that dash, yet its prose claims dash
gait coverage. Test a dash and walking start/stop DURING a primary attack,
with live SceneTree clocks as well as controlled steps. `_play_current()`
currently plays the hidden Sprite while `_step_attack_gait()` also assigns
its frame: verify that walking/facing transitions cannot run two clocks,
reset gait timing or make frames step backward. Fix only a reproduced
problem; keep one clear clock and preserve the current visible frame and
progress across attack restarts, movement changes and recovery. Repeated
attacks must keep a complete stride. Retain the pause check.

Document only what the tests and movies actually prove. Keep all old checks,
run the focused and related suites cleanly, and report the commands/counts.
No auth/UI/store/counter changes, network, git, devices, marketing capture
or provenance changes. The director will independently render both modes,
inspect full cycles and verify the drawn-arm negative control again.
