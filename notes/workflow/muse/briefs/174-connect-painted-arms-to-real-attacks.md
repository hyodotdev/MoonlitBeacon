# Correct the physical attack candidate after rendered review

## User request and judgment

The user says characters hold a sword without visibly swinging it and asks
for all six heroes to be checked before replacing the canceled submission.
They explicitly say not to recapture store screenshots.

Round 1 is not accepted. The director rendered the real timed harness with
VFX off, at 60 FPS. The movie and extracted QA-only frames are in this copy
under `builds/hero-attack-review/round1-motion-only.avi`, `round1-board.png`,
`round1-dancer-motion.png`, and `round1-dancer-second.png`. These are not
marketing captures. The close characters have conspicuous orange round hands
near their knees/crotch while their original painted arms remain in the old
idle pose. A floating weapon plus a primitive glove does not satisfy the
original brief. Translating, rotating, and squashing the entire idle sprite
does not make a planted character actually swing its arm.

## One correction task

Make the physical pose read as the same painted character attacking. Keep
the useful weapon timelines, distinct weapon grammar, existing combat logic,
and tests. Correct the following confirmed problems together:

1. Replace the flat line/circle sleeve and glove with painted arm/hand motion
   that actually belongs to the character. The shoulder must be attached to
   the torso, elbow must bend, hand must grip the weapon, and the original
   baked idle arm must not remain as a duplicate third arm. Use a practical
   texture-based arm/upper-body rig, a locally deformed painted mesh, or
   properly authored attack frames; choose what yields clean results with
   the existing painted art. Do not simply hide the orange circle and keep
   an unattached moving weapon. Feet remain planted while the upper body and
   arm commit to a slash, alternate dagger cut, recoil, or two-handed sweep.
   Avoid stretching a whole body as a substitute for articulation.

2. Recalibrate seats against the actual painted wrists/shoulders for all six
   heroes and all four facings/eight aims. Currently `_draw_arm` places its
   shoulder by interpolating the glove toward the origin, so even its
   shoulder moves with the glove. In `refresh_attack_pose` the rig translation
   includes `attack_shift_now`, and `draw_anchor_now` includes it again:
   remove accidental double application and test world-space travel, not
   only rig-local values. Keep projectile origin at the drawn muzzle at the
   production contact instant, within the existing tolerance. Dancer must
   retain both daggers while one cuts; the other stays in its real hand.

3. Primary attacks must face their target while locomotion continues. Ranged
   `play_moonlight_cast` currently does not face its target; the following
   `_physics_process` always faces `_wish`, overriding melee target facing.
   Cover firing/slashing right while walking left (and the inverse), plus
   diagonal/vertical aims, without a pre-call to `face_toward` in the test.
   Sidearm cues must not override the primary pose or aim. Dash, pause,
   result, hero change, and rapid restart must restore cleanly.

4. Fix the timed motion harness as a real visual acceptance tool. The
   director's movie is 1616x720 despite BOARD_SIZE 1280x720; its Warden row
   is off the top, and the nearest-neighbor close view of Dancer never shows
   a full convincing attack. Correct window/min-size/stretch handling
   inside the harness only (no project setting changes), frame all six full
   bodies and their full weapon/hand bounds at contact/peak/recovery, and
   check every row including the close block. Include a true no-VFX mode:
   Eclipse's decorative orbit circles are still visible in the current
   no-VFX movie. Suppress VFX without suppressing the physical weapon or arm.
   Use production attack methods in both modes (disable VFX at the draw
   layer), rather than a motion-only convenience that can mask production
   differences. Timed mode must show actual live complete cycles and produce
   observations confirming multiple rendered poses, not just method calls.

5. Strengthen the motion regression test to catch fixed baked arms and whole
   sprite wobble: measure actual painted shoulder/elbow/wrist articulation,
   hand-to-grip connection in world space, duplicate-arm masking, body facing
   during opposite movement, and the full cleanup paths. Freeze only the arm
   rig as a negative control: the test must fail even when the weapon and
   VFX still move. Restore the probe before reporting. Keep existing checks
   and the original damage/cooldown/contact semantics unchanged.

## Scope and acceptance

Same scope as brief 171: actor rendering, the required small art/rig support,
meaningful tests/harness, and accurate technical docs/build log. No auth,
store/UI changes, version changes, network, screenshots/provenance edits,
git history, machine operations, or protected paths. If an asset-generation
step needs director assistance, report the exact required input rather than
inventing a placeholder. The director will render the complete normal and
no-VFX movies again and reject obvious extra arms, knee-height hands,
unattached grips, missing dagger, and a static body with only weapon/VFX
motion even if numeric geometry tests pass.

This is a 4.0.0 replacement: move the new attack entry currently appended to
`notes/plans/3-0-0-build-log.md` into `notes/plans/4-0-0-build-log.md`, retaining
all historical content. Do not put this release's work under the old version.

Run the new regression, harness validation, existing painted-weapon,
hero-visual, combat-profile and hero-weapon checks, plus smoke/hygiene.
Report measured articulation and world-space travel, the negative control,
and complete movie invocation. Do not claim rendered review from headless
checks. Do not change a test expectation to conceal one of these defects.
