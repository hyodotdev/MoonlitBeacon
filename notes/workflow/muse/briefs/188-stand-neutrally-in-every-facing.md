# Brief 188: Stand neutrally in every facing

## Why this correction arrives before the first report
The director independently inspected the newly baked idle/walk cells at 4×. The current answer to brief 186 does not meet its main standing criterion. Continuing rig calibration and full tests on these poses would validate the wrong art, so the director stopped that work round deliberately. This is a correction in the same copy; keep useful work and read its current diff first.

## Confirmed defects
- `warden/idle.png`, row 0, down column: it remains exactly the forward stepping pose from `walk.png` row 0, with the raised knee and only one clearly supported boot. The head match is useful, but this is not a neutral standing pose.
- `dancer/idle.png`, row 0, up column: it likewise remains the moving pose, one leg bent/lifted and one supporting boot. The same front/back turnaround row-0 reuse remains in `bake_heroes` for every hero; only Keeper's few sole rows have been extended. These twelve down/up cells were not actually changed into standing poses.
- The narrowed side prototype still reads as a shortened step: the rear shin angles backward and the foot remains far behind the front leg. Rotating about each contact foot's x coordinate then targeting a positive gap between whole boot extents is not the same as placing the legs vertically beneath the hips. Profile feet normally overlap in x, with a small offset between near/far boots; they need not be separated side-by-side like a front view. A smaller spread number does not prove a natural pose.

## The user's priority
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해 이것때문에 계속 배포를 못하고 취소하고 하자나”
Both `“다리를 벌리고 있지말고 서있게”` and the unchanged face/head are required. All six heroes, all four facings, actual intro and Player transitions. Do not redefine row-0 contact art as standing to satisfy the test.

## Correct the standing art
- Produce genuine supported neutral idle lower bodies for **all 24 hero/facing combinations**. Both relaxed legs should descend from the hips with believable knees/ankles and supported feet. Do not reuse a passing/contact stride, extend a lifted boot into a vertical color smear, erase a leg, or simply narrow/scale the whole body.
- Front and back must show two believable standing legs/feet; keep their perspective and near/far depth honest. Left/right should have near/far legs together under the torso, with a slight depth offset instead of a running split. Inspect boots, ankle joins and thigh/crotch joins at 4×.
- Keep one canonical head/face and stable upper-body proportions per facing through idle, all four walk frames and attacks. Preserve accepted alternating side gait; do not freeze the walk loop. If harmless subpixel translation is necessary for gait, register it honestly rather than changing head scale or anatomy. Do not keep a wrong old byte-preservation rule merely because the walking bytes were previously accepted; the user explicitly allowed this repair.
- Existing painted donor parts and deterministic surgery may be used when they actually produce a natural standing pose. If the existing sources cannot support one, report the exact missing facing/source parts instead of calling a compromised pose finished; the director can provide additional authored raster collateral. No network/image download yourself.
- Keep stable forecourt size/grounding and physical attack hands/weapon grips, first-turn fractional stride, independent Dancer hands and Eclipse orbit suppression. Recalibrate and rebake rig assets after the canonical art is correct.

## Coverage must see the defect
Use meaningful painted geometry/region and actual-render transitions. An equality check between idle and walk row 0 is insufficient: it would bless the original down/up stride pose. Guard the front/back supported neutral pose as well as the side pose, head dimensions in **every** walk/idle frame and the attack torso, and measured drawn scale at forecourt stops. Negative controls must fail when the old down/up stepping lower bodies are reinserted, when side contact stance is restored, and when the mismatched idle head is restored. No generous threshold invented just to fit this output.

## Overlap / preservation
Brief 187 is independently adding an unboosted debug `hero_direction` native inspection path in `store_capture_boot.gd`, `test_launcher.gd` and the registered clean-UI regression. Do not touch those paths, the regression runner or title-music code. Continue the brief-186 hero/forecourt/rig/tests/docs/build-log scope. No login/save/IAP/music/version/gallery/world-art changes. Keep all combat damage/cadence/counts and the unchanged 1,200-node late-arena limit. No store capture or provenance regeneration.

## Acceptance remains the original one
All 24 production idle facing cells genuinely stand, the same character/head appears in repeated move→stop→attack→recovery→move, and the director reviews dense real Godot movies plus final installed native footage. Relevant registered regressions, deterministic hero/rig checks and original late-arena budgets pass without weakening. Return the minimal corrected diff, meaningful negative-control evidence and exact preview/movie harness instructions. A test report is not a visual approval.
