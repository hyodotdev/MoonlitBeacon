# Brief 171: Make all six hero attacks physical

## The ask
“그리고 지금보니 캐릭터가 칼을 들고 있는데 칼을 휘두르는 느낌이 전혀 었어.. 그냥 칼을 들고만 있고 이펙트만 나가네 저렇게 허술하게 하면 안될텐데 캐릭터 다 점검해주면 좋겠다 근데 이미 심사 제출했는데 빠르게 취소하고 이거는 중요한거니까 업데이트 해주면 좋겠어”

“스샷은 새로 안찍어도 돼”

Fix the actual body and held-weapon action for every hero before the director replaces the submitted build. Existing store screenshots stay byte-identical; do not capture or publish new ones.

## Why, and what good feels like
A sword must visibly travel through its cut, carried by a moving hand and a readable body action. A muzzle flash alone is not firing a gun. At normal gameplay scale the player should recognize a committed sword cut, quick alternating dagger attacks, a lantern pistol discharge, a heavy cannon kick, a crescent sweep and a precise rifle shot. Preserve the current smooth painted characters and equipment; do not return to primitive pixel figures or a whole-body wobble standing in for animation.

## Where things stand
- Baseline is the current feature branch at `25fe321`. The previous native Apple deletion fix is already present; do not modify auth.
- `apps/game/scripts/actors/weapon_rig.gd` explicitly says the held pose never moves. `_draw_held()` uses only `_aim`, static anchor and static pivot; `_process()` advances flash fade, not the physical weapon. This confirms the user's complaint.
- `Player.attack()` calls `_show_slash()` and `_rig.flash()`, while `_play_current()` only selects `idle_`/`walk_`. No attack body poses exist. `play_moonlight_cast()` is also flash-only; `recoil()` moves only the body for cannon, leaving the held rig behind.
- Baseline command `pnpm godot:isolated --timeout 150 --script res://tests/test_painted_weapons.gd` passes **5016 cases** despite the absent attack motion. These tests prove sheet quality/seating, not animation quality.
- Inspect `player.gd`, `weapon_rig.gd`, `scythe_orbit.gd`, `hero_weapons.gd`, Arena's melee/volley paths, and the six hero resources. Painted body atlas cells are 144×192 at 3× texels, runtime body scale .255; weapons have 4× texels and per-item Linear filtering. Current body sources/packing are in `tools/pack_painted_world.py`; older `build_warden_assets.py` delegates to that pipeline. Do not overwrite painted production art with the retired procedural generator.
- Existing meaningful regressions: `test_painted_weapons.gd`, `test_hero_weapons.gd`, `test_hero_combat_profiles.gd`, `test_hero_visuals.gd`, `test_hero_gait.gd`, and direction capture. Existing visual harness `tools/shot_painted_weapons.gd` freezes a flash, so it cannot prove a swing.
- The director has requested cancellation of the iOS 4.0.0 review. All store, credential, device and git operations remain the director's work.

## Do
1. Implement bounded, distinct attack motion for all six heroes: physical weapon rotation/translation and real hand/arm/body pose change. The free Warden needs a visible broad cut with a carried grip and follow-through; Dancer needs two distinct dagger/hand actions rather than rotating a rigid twin icon; Eclipse needs a carried crescent sweep tied to the orbit pulse; Keeper, Knight and Sage need different bracing, discharge and recovery, with the actual held gun participating in recoil. Choose a clean painted-part rig or deterministic attack atlas approach after inspecting the art. A stationary torso plus VFX, or rotating the entire static figure, fails.
2. Tie the attack cue, weapon contact/discharge and real combat event to one short timeline. Keep automatic combat immediate and responsive. Preserve damage, cooldowns, hit fans, range, projectile count/speed and relic balance. If a tiny lead-in requires scheduling contact, explicitly report it, keep it bounded, validate targets/scene lifetime and update meaningful timing tests; do not silently delay or duplicate hits. A presentation timeline that starts at the existing contact event is acceptable when the visible cut crosses the contact direction at that instant and then follows through.
3. Correctly carry the weapon in a hand across left/right/up/down and diagonal aims, including moving and firing in different directions. Keep the face readable on vertical attacks, appropriate depth for rear-facing hands/weapons, and no duplicate unmoving hand under a moved arm. Returning to idle/walk must preserve feet, frame continuity and the existing walk silhouette. Sidearm cues must not steal or restart a live primary action. Rapid relic-enhanced attacks, pause, dash, result, hero switch, clear and scene exit must not leave a stuck/offset weapon or pending hit.
4. Add focused regression coverage that would fail for the current static pose, including all 6 heroes × 8 aims: physical tip/grip paths, per-hero action distinction, contact/muzzle correspondence, sidearm priority, rapid retrigger, pause and recovery/cleanup. Register it in the regression runner. Stage a **motion video harness**, using real Players and production attack methods, normal composite plus a readable close view, all heroes/cardinal aims and separate no-VFX motion. It must support headless validation with machine-readable timing/geometry observations and a windowed timed run suitable for Godot `--write-movie`; no PNG screenshot writes or store capture pipeline.
5. Keep documentation brief and true: update the relevant player/combat explanation and build log; record any new runtime art in the asset manifest. Report exact commands, counts and limits, and the harness invocation/output. The director will judge actual rendered motion before acceptance.

## Do not
- Touch auth/login, saves, account deletion, ranking, shop layout, music, world content, store metadata or screenshots.
- Touch `export_presets.cfg`, versions/build numbers, project locked settings, guards, instruction files, or director workflow notes.
- Capture marketing or QA still screenshots, recapture existing art, replace the accepted walk/idle source atlas unnecessarily, or weaken established combat/asset tests to pass.
- Hide the static body behind brighter/larger slash VFX. Do not add permanent process overhead to every enemy, allocate a new Tween/node every frame, or leave desktop harness/debug UI in production.

## Acceptance
- New action tests pass and the report demonstrates a reverted negative probe where freezing the physical weapon/body path causes failure.
- All established painted-weapon, hero combat, gait, visual and cleanup regressions stay green. Same baseline combat numbers; document and test any intentional short contact scheduling.
- At production scale and close view, **6 heroes × 4 cardinal aims × a complete attack/recovery** are identifiable in the motion harness; no-VFX mode still unmistakably shows the physical action. At least 48 distinct primary action/aim samples are checked headless, including diagonals.
- Melee physical blade has a substantial visible arc (Warden at least 90 degrees, each Dancer action at least 60 degrees, Eclipse at least 120 degrees) and settles back; ranged guns visibly move with their hands and return exactly to their rested transform. Do not make arc duration longer than the attack interval at minimum cooldown. Calibrate the body pose to the motion, not arbitrary sprite displacement.
- At gun discharge the painted muzzle and projectile launch match within .5 world pixels for all 8 aims. A sidearm never relocates the main held weapon. No hand grip gap at contact exceeding 1 world pixel.
- `pnpm test:game`, `pnpm game:check`, relevant asset generator `--check`, hygiene and docs build pass. `pnpm check:store-screenshots` may report existing fingerprint staleness; report it and do **not** recapture.

## Deliverables
Small production actor/animation changes, any necessary deterministic painted-part asset pipeline/resources and manifest rows, registered attack-motion tests, a timed motion harness under `apps/game/tools/`, relevant docs and build-log updates, and `IMPLEMENTER_REPORT.md`.

## Settle these yourself
Use the existing painted masters where possible. A small hand/arm rig is preferable to large new full-body sheets if it convincingly carries the weapon without doubled limbs. Preserve the six established combat identities. Prefer a timeline at the current contact event over altering damage/cooldown behavior. An initially facing-away walking body must turn or brace coherently toward its own primary attack rather than pointing a gun through its back. The director will use Android first, then the connected physical devices; do not operate them.

## How the director will judge
Read every changed hunk and all new files, run the new tests and established combat regressions independently, break the physical motion in the copy and see the tests fail, render the motion harness at 60fps and view consecutive frames with/without VFX, then inspect normal Android gameplay. Rejection follows if the weapon still looks glued on or if animation is only a full-body wiggle.
