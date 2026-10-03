# Brief 067: make weapon verification fixtures clean and fully framed

## Evidence
The director independently ran round 063's `test_painted_weapons.gd`: 5013 cases passed. The real windowed `shot_painted_weapons.tscn -- tag=director-r2` passed 495 checks and wrote all three images. Four-texel source packing, Linear draw and grip compensation are visibly good.

Both commands emit `Camera2D overridden to physics process mode due to use of physics interpolation`: the test at `_test_spawn_coincidence` adds its Player before configuring the Cam, and the board `_build_board` disables each Player's Cam only AFTER adding it. In the actual `director-r2_normal.png`, the left block shows only the first three overlapping/misaligned rows of bodies while the six close weapon rows are present. Node counts alone did not prove all bodies were framed. The director requires the real 24-player, six-hero/four-direction board to judge body attachment after the painted body integration.

## Do
Fix only the new test and shot harness Camera2D setup before entering the tree: use the correct physics process callback under the existing project interpolation, disable board player cameras before they can take over the viewport, and keep the board viewport transform predictable. Ensure all 24 distinct hero bodies and their held weapons are actually on screen in the normal/fire/clear board, plus all 24 close rigs. Strengthen visibility/framing validation using rendered bounds, not node count alone. Update the latest log with measured results; old round records may remain explicitly historical.

## Do not
No production scene/player/engine/project setting, weapon geometry/packing/timing changes, art, shared runner/package/native/cloud/title or unrelated scope. Do not suppress warnings or disable project interpolation.

## Acceptance
Director repeats the 5013+ cases and windowed board: zero Godot errors/warnings, all six hero rows visible in four aims, all close rigs present. The related hero-weapon/combat suites stay green. Source-only patch remains under brief 056/063 ownership.
