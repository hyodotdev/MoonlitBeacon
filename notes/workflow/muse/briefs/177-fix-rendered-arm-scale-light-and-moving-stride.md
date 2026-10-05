# Correct the actual painted attack rendering

The user asks for real weapon swings for all heroes before resubmitting and
explicitly says to retain the existing store screenshots. Round 2 still has
confirmed rendering defects. This is the third judgment round for this task.
The director stopped round 2 after those independent failures; its report
is an unfinished draft, not an accepted result. No candidate test process
remains running. Read the accumulated diff first and continue in this copy.

Director evidence is in this copy under `builds/hero-attack-review/`:
`round2-framed-motion-only.avi`, `round2-framed-board.png`, and
`round2-knight-cycle/cycle.png`. The cycle strip shows bright idle paint
switching to a dark attack body with oversized detached arm patches. These
are internal QA artifacts, not marketing captures.

Correct these together, preserving combat timing, damage, the original
idle/walk sheets, all six distinct weapon actions and existing checks:

1. `ArmRig._layout()` scales joint positions with `cell_scale` but never
   scales either painted Sprite2D. Its raw texture pixels render at 1.0
   against a 0.255-scale hero. Apply the correct scale and pivot transforms
   to the actual drawn segments. Prove transformed texture-local elbow and
   wrist endpoints coincide with adjacent joints and weapon grip at rest,
   contact and recovery for every facing. An IK getter alone is not proof.

2. The original Sprite has `HERO_READABILITY_TINT`; AttackTorso, AttackLegs,
   AttackNub and both painted arm segments do not. Preserve the same paint
   brightness and applicable render properties when switching renderers.
   The body must not blink dark on every attack. Inspect actual movies and
   check the visible sprite properties, including arm descendants.

3. `_begin_attack_pose()` pauses the animation and takes a frozen leg strip;
   `_play_current()` returns while the split is shown. Moving attacks must
   keep the original live walking cadence and update the drawn leg strip,
   including repeated attacks while moving opposite the target. Plant feet
   only when stationary. Check actual drawn leg frames over a continuous
   moving volley, pause, dash and recovery; preserve state transitions.
   Confirm the thigh/knee and boot crossing remains coherent in the actual
   moving clip; adjust the split boundary if updating only the bottom strip
   leaves a static duplicated upper leg. Keep the original walk sheet bytes.

4. The AVI remains 1616x720 while the board forces 1280x720, even with the
   CLI resolution set. Warden is cropped out. MovieWriter chooses the locked
   project's window override before scene startup. Make the harness board
   match the actual 1616x720 output and re-layout normal and close cells,
   or use a supported capture approach whose physical output matches its
   declared geometry. Do not change project.godot. Show all six full bodies
   and full weapons at peak, and cycle all four close-view facings. Include
   moving repeated attacks and normal/no-VFX complete live cycles.

Strengthen tests against the actual Sprite2D transforms/color/leg atlas,
not only joint math. A negative probe freezing only `_layout()` must fail
while IK getters, weapon timeline and VFX continue; restore exact bytes.
The director already ran this probe in a separate throwaway copy: the
unchanged suite passed 4174 checks, and removing only the entire `_layout()`
body still passed 4175 checks. The current regression demonstrably cannot
detect frozen drawn arms. Full logs will be in this copy's QA folder.
Keep all earlier assertions. Run registered related suites, assets/hygiene
checks and headless harness validation. Update technical docs and the
4.0.0 log accurately. No auth/UI/store changes, new counters, network, git,
marketing capture or provenance edits. No empty transparent arm patches or
primitive placeholder hands. The director will render and inspect both
modes independently before accepting.

The related arena suites must complete cleanly, with no pending or skipped
assertions in the report. `test_hero_weapons.gd` lacked `_expect_false` until
the last round's late fix. Director correction: `Player.facing_vector()`
does exist (baseline line 692; candidate line 1277); the earlier statement
that it was nonexistent was wrong. Do not add an API to fix that statement.
Keep independent anchor calculations correct. Remove the leftover side-hand comment describing
the retired 10px seat rule. Run each test without piping away its exit code
or hiding Script Errors until a long timeout. Preserve strict assertions.
