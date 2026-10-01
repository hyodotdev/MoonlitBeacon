# Brief 024: stabilize the late cannon node budget

## The ask
"너가봤을 때 어때 훨씬 쎄련되고 재밌어? 꼼꼼히 2~3번 점검해주고 괜찮으면 머지하고 스토어 스크린샷 등다 새로 올리고 직접 배포도 해줘"

The release review found a reproducible gate failure to investigate before capture and shipping. Preserve the heavy cannon feel and all gameplay rules while resolving the confirmed budget failure.

## Why, and what good feels like
The Knight should keep a satisfying shell and delayed blast, without late-game visual effects or retained nodes exceeding the existing budget. The director will judge the cause, the diff and repeated live measurements independently.

## Where things stand
The accepted 3.0.0 renewal has six distinct weapons and six music tracks. The working branch is at becf316. Earlier original full verification passed, with Knight Lv40 node peaks around 1187. A fresh original `pnpm verify` now fails in `apps/game/tests/test_late_game_performance.gd`: Knight Lv40 node_peak=1202, friendly_peak=8, spirit_peak=40; the unchanged cap is 1200. The sample logged shell_detonations=16, cache_builds=4, cache_hits=44, total candidate work=1472 over 91 physics steps. One of 71 cases failed. A Pixel emulator was booting concurrently; wall-clock CPU time is diagnostic only, and no claim about the cause has been established.

Read `apps/game/tests/test_late_game_performance.gd`, `apps/game/scripts/actors/moon_arrow.gd`, the arena/weapon integration and impact effects. Warmup and sampling currently use wall-clock durations. Do not assume that either production VFX or the fixture is at fault before measuring.

## Do
- Reproduce the unchanged live Knight sample, identify which node classes contribute to the excess and whether scheduling changes the staged state. Record measured evidence rather than guessing.
- Make the smallest supported correction. A fixture correction is valid only if you establish the fixture is wrong and preserve the original intended stress conditions; otherwise reduce retained/transient production node overhead while preserving damage, timing, blast geometry and visual feedback.
- Keep a meaningful regression for the confirmed cause and register any new test in the existing runner. Avoid a test that merely mirrors the implementation.
- Record the cause and before/after measurements in the existing 3.0.0 build log, with the limitations explicit.

## Do not
- Do not raise the 1200 node cap, reduce the 34/40 spirit counts, weaken the 256 candidate-per-physics-step budget, erase projectiles/VFX to pass, choose a lucky seed, suppress a failure or replace measured values with constants.
- Do not alter cannon damage, pierce, 48px blast, max-growth cadence, Starfall evolution, other hero identity, music/assets, prices, locked versions/package/render settings, protected files or git history.
- Do not attempt store capture or deployment. The director does that after the runtime is stable.

## Acceptance
- Original late-game performance test passes at least three consecutive isolated executions with the same 1200 cap and live 34/40-spirit stages, repeated detonations and unchanged candidate-work bound; provide the actual peaks.
- `test_hero_combat_profiles`, missile loop/growth and game smoke remain clean. Related tests for any affected effects or lifecycle pass.
- Independent source review shows preserved cannon strike and delayed detonation damage, geometry and player-visible feedback. The correction leaves useful budget headroom, or explains with evidence how the unchanged gate is now reliable.
- No unrelated changes, metadata/IAP changes or budget exceptions.

## Deliverables
The minimal affected GDScript/test files and a short measured entry in `notes/plans/3-0-0-build-log.md`. Name all changed paths and commands in the report.

## How the director will judge
Read the source diff and cause, rerun the live original test repeatedly, run related guards and original full verification, and inspect actual Knight rendering after acceptance. A report is a claim, not proof.
