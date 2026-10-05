# Preserve fractional gait at renderer handoff

The director's new 60 FPS movie confirms all six movers remain visible;
the direction/bounds repair is good. The painted scale, brightness,
weapon action, drawn-arm tests and one-clock repair stay. Do not revisit
the art, board, combat timing/damage or settled state-transition work.

Two remaining timing defects were independently reproduced in an isolated
copy using your latest Player. Read `builds/hero-attack-review/`:
`gait_fraction_probe.gd` and `gait_fraction_probe.log`.

The probe sets the real AnimatedSprite2D with
`set_frame_and_progress(2, 0.75)` before a walking attack. The automatic
sprite clock has progressed 2.75 frames, but the first split swap seeds
`_gait_time` from `sprite.frame` alone: it becomes 2.0 frames, losing 0.75
of a frame. Recovery also loses progress: the explicit clock's fractional
progress is 0.8 but the resumed Sprite's `frame_progress` is 0.0. Repeated
renderer swaps therefore delay steps even though the frame index survives.
This contradicts the requested preservation of both frame and progress
through attack entry and recovery.

Preserve the complete progress at both handoffs, including walking/idle
and facing transitions, using the actual AnimatedSprite2D frame/progress
API. Keep the hidden Sprite paused while the explicit clock owns it, and
retain the already-fixed mid-attack restart clock. Do not reset the frame
or replay an animation into frame zero at recovery. Keep the gait rate
unchanged. Add precise fractional checks at nonzero progress for all six
heroes; tests disabling either handoff must fail. Keep every old assertion.

The second finding confirms the reported facing-hold flake, rather than
accepting a retry as evidence. Read `facing_boundary_probe.gd` and its log
in the same QA directory. Keeper aims right with an active rig; expire the
physics countdown and apply a left movement tick. Actual facing changes
RIGHT (3) to LEFT (2) while `rig.attack_live()` remains true and its aim is
still (1, 0). Separate physics and rig clocks make this boundary reachable.
Hold the body's target-facing until the actual rig is finished, regardless
of countdown exhaustion; movement and gait must continue. Restore movement
facing promptly after cleanup. Add an exact boundary regression for every
hero, plus live full-suite runs without retrying a failed facing assertion
away. Preserve old assertions and do not change attack span or damage.

Re-run the supplied fractional probe: walking attack entry must read 2.75 before and
after, and recovery Sprite progress must agree with the explicit clock to
float tolerance. Run the focused and related suites, update only affected
technical prose/counts, and report the commands. Original sheets remain
byte-identical. No new assets, auth/UI/store/counter changes, network, git,
devices, marketing captures or provenance edits. The director will run
final movies and verification independently before acceptance.
