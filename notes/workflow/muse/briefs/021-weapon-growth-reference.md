# Correction brief 021: Finish the combat reference and capture evidence

Continue `20260930-2321-kinetic-hero-weapons-and-audio` after round 4.
Change only `apps/docs/docs/game.md`, `apps/game/tools/shot_weapons.gd`,
the factual build log and report. Production combat/audio/art, other tools,
tests and balance remain byte-identical. No git/network/device/store/save work.

## The ask

“겜을 좀더 속도감있고 박진감있게 해주면 좋겠어 그리고 캐릭터별로 완전 느낌을 다르게 잘 수정 보완해주고”

## Confirmed reference correction

The rewritten combat overview says power 3 always turns volleys into homing;
its core table labels powers 3–8 simply `homing` and power-0 Shots=1.
Actual `_starfall_evolved()` requires evolved Starfall, or Awakening plus
power >=3. Normal fire otherwise stays straight even at power 8. Keep the
separate primed Resonance volley exception accurate. Existing five-locale
`MISSILE_HOMING` already says homing during Awakening: do not change gameplay.

`_missile_volley()` takes max(native lanes, core curve). Keeper starts with
five pellets and Dancer/Eclipse two at power 0. Label/qualify the table as the
baseline core curve and explain native floors. Keep numeric thresholds and
historical Lesson/rebuild figures unchanged. Concise prose, no new tutorial.

## Confirmed windowed harness correction

Round 4 fixed the capture XP-choice pause lifecycle correctly. Keep its real
`debug_freeze_capture_progress`, per-arena unpause, stationary live targets,
spawn suppression, target top-up, body/primary-rig aim, real damage and primary
effects, recoil, draw-synced 0.6s strips and ten settled armed beacons.

The director's normal windowed command, tag `director-final-r4`, still fails
`dancer early right volley center flies right` in
`builds/director-final-r4-weapons.log`. Averaging currently surviving arrows
does not reconstruct a volley: the center lane may already hit/perish while
an outer lane remains, and even-count volleys intentionally alternate the
unpaired side. Thus a legal candle backup can have an off-axis average even
while the actual twin-blade primary and its target point right. The candle
is 20px above the feet, the right pocket 34px, and the designed 16° extra
fan can cross the dominant-axis boundary.

Replace this false assertion with evidence that distinguishes real primary
aim and legal fan lanes. Retain strict primary-rig side and body assertions
for all six; independently observe true gun-primary flight alignment for
Keeper/Knight/Sage without treating all surviving lanes as a complete
symmetric volley. If secondary flight is checked, compare each with its own
actual fan/origin/target contract, not a compass-axis assumption. Do not
change production, shrink fan, move candle, disable attacks, pose effects or
delete primary direction/hit/body coverage. Prefer a small transparent check
over extra instrumentation. Keep isolation gating and no temporary prints.

## Acceptance

Run headless full six-hero early/strong four-side validation. Include a
negative control that reverses a real primary aim/flight and makes the
direction observation fail; restore exact bytes. The director then repeats
the normal windowed command without operational subclasses. Existing
production runtime witness must remain unchanged.

Build docs and run anchors/hygiene as permitted; add a short factual entry to
the build log and report. Distinguish the independent windowed failure from
the implementer's headless passes and retain historical measured evidence.
No new test suite or broader feature work.
