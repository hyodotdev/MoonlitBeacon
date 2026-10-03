# Brief 041: A journey that resumes through its last gate

## The ask
The user said: “아니다 이번에 그냥 구글 게임 로그인 애플로그인 게스트 로그인 넣고 마지막 플레이한 곳에서 플레이하고 명예의 전당 붙여서 계속 랭크 보여주면 어때? 우리 겜은 무한 겜이라서 계속 마지막 플레이 한 구간 저장되서 계속 이어가게 해주면 좋겠는데 이후 시나리오도 계속 업뎃해서 붙이기 좋은 구성으로 해줘”, then “이렇게하고 4.0.0으로 해보자”. They also said guest players must receive a unique ID before play, and compared the experience to an isekai gate. The immediately preceding defect report was that first-play guidance feels like stuttering.

This brief is the local journey and story foundation of that larger release. Account services and identity-aware ranking follow separately.

## Why, and what good feels like
Opening the game should offer one clear Continue action into the last reached gate. Closing the app should not throw away the journey. Dying retries the saved segment with the growth earned before that segment, without farming rewards by repeated restore. Reading the opening instruction must not make moving combat appear broken. Existing character combat, music and the Nari/Lantern Hollow canon remain intact.

## Where things stand
- Baseline main is commit 815d5b5, clean except an unrelated untracked browser-output directory. This branch has no implementation changes.
- `arena.gd` `_begin_tutorial()` calls `_open_run_story()` on every real title entry. `_flush_cycle_story()` opens an ActCard then Dialogue, both pausing the tree. Movement tips are centered HUD announcements, not pauses themselves. There is no persisted run/checkpoint.
- Safe travel happens in `_on_gate_entered()` and `_change_cycle_world()`; cycle loot and the cashout/continue choice overlap these transitions. `_finish()` settles cumulative shards through `_run_shards_awarded`, currently memory-only.
- Vault contains paid entitlements and upgrades; do not rewrite or synchronize its purchase ledger. Chronicle has a separate local save. RunEntry separates humans from tests/captures.
- Acts and Chronicle enumerate the current story; `_story_lines` derives translation keys from cycle numbers. The story includes beats through cycle 12 and gameplay already continues endlessly.
- `test_story_structure`, `test_terrain_integration`, `test_result_route`, `test_ladder` and capture regressions pin neighboring contracts. Use their `.tscn` entry points; direct `--script` on scene-attached test Nodes does not provide their autoload context.

## Do
- Add a bounded, versioned local journey save with atomic replace, valid backup recovery and strict validation of every resource path and numeric field. Save a safe segment-entry checkpoint after travel/cycle rewards are resolved. Preserve cycle, zone, deterministic route/seed, selected hero, held relic stacks, combat growth, score counters and reward-settlement bookkeeping that are necessary to reconstruct the journey. Restore derived combat state through production methods, not copied live nodes.
- Make Continue the title's primary action when a valid journey exists; show the saved character and reached gate/cycle. A fresh journey remains available with an in-game confirmation before replacing a save. Save failure is visible and never advertised as successful. Test/debug/capture entry must not write real human journey state.
- Death offers retry from the last gate and preserves the checkpoint. Completed-region growth is retained; defeated-region kills, shards, score and rewards must not be multiplied by retries, restarts or repeated process launches. Cashout and existing paid continue semantics must remain coherent and cannot duplicate grants. Do not consume a paid continue merely to resume a saved journey.
- Persist onboarding completion separately from purchases. Start a fresh human journey with a short nonmodal story/guidance strip and responsive movement, rather than the ActCard→Dialogue pause chain. Record the full opening in Chronicle for rereading. Keep later intentional story/reward choices readable and safe; do not unpause combat behind modal choices. Resume must not replay the opening or completed guidance.
- Introduce a data-driven story episode catalog with stable episode IDs, cycle ranges/beat IDs, localization keys and fallback beyond authored content. Acts, Chronicle and arena story lookup use this catalog so a future episode is added as data/localization without editing arena progression. Migrate existing story unlocks; retain the current complete story and endless gameplay. Include a documented, runnable content-extension example/test without pretending unimplemented chapters are available.
- Add focused behavioral regressions and a foreground visual/play harness for fresh start, resume, death retry and a later gate. Register tests in the existing runner. Update player-facing docs to describe actual behavior and add an author-only 4.0.0 build log with measured checks and remaining account work.

## Do not
- Add placeholder login buttons or claim cloud/global support in this foundation round. Do not change network/backend rules yet.
- Touch credentials, guards, skills, stores, existing marketing screenshots or purchases. No network, git history or device operations.
- Bump versions in this round; lock 4.0.0 and platform build numbers after the complete feature is ready.
- Turn the existing 3.0.0 runtime into a broad refactor or redesign hero art/music. No downloaded asset packs or gray/debug UI.

## Acceptance
- Fresh title entry into a human journey remains unpaused while the first instruction is displayed; player position changes while it is visible. Once learned, tips do not repeat on resume/relaunch.
- A journey saved after a fork and a guardian reward restores the same hero, selected terrain/route, held stack counts, power, score counters and safe gate on a new process. Also test a late cycle above all authored episodes.
- Corrupt, truncated, oversized, future-schema and invalid-path saves cannot load arbitrary resources or erase paid state. A valid backup recovers safely. Failed writes retain the previous playable save.
- At least three repeated death/restore/process-launch retries cannot increase banked shards or duplicate record/reward settlement. Switching from Continue to a fresh journey requires the in-game confirmation.
- Existing terrain, relic, result, IAP and capture regressions pass; opening-story tests are updated to assert the new continuous-input contract while later story tests retain their protection.
- The foreground harness produces clean localized fresh/resume/retry screens and a short playable first-guidance sequence for the director to inspect. No store recapture.
- `pnpm test:game`, `pnpm check:scripts`, `pnpm check:locale`, `pnpm check:hygiene` and docs build pass in the copy. Report the actual checks; source-fingerprint screenshot failure is expected and is not a reason to recapture.

## Deliverables
Journey persistence and integration in `apps/game/scripts/gameplay/`, title/result/guidance UI integration as needed, story episode data/resources, registered tests, a small `apps/game/tools/` review harness, `apps/docs/docs/game.md`, and `notes/plans/4-0-0-build-log.md`. Name all changed files and explain persisted fields and settlement rules in the report.

## Constraints specific to this task
Keep all AGENTS locked engine, renderer, resolution, controls and package values. Preserve six heroes and existing entitlements. Backward-compatible saves must keep 3.0.0 Vault/Records/Ladder/Chronicle data readable. Progress restoration must stay within existing gameplay/node budgets.

## Settle these yourself
Use segment-entry checkpoints rather than serializing projectiles, enemies or physics mid-frame. Save only after all deferred world/reward transitions are stable, and on app background only preserve a known valid checkpoint. Treat the title Continue journey as distinct from existing paid resurrection. Default future content to endless trials after the catalog's latest authored beat.

## How the director will judge
Read all persistence/restore/settlement code; independently run the focused tests and full suite; perform a negative-control test in the isolated copy; look at the foreground harness and play the first guidance plus checkpoint retry. Acceptance is based on reproduced behavior, not the implementation report.
