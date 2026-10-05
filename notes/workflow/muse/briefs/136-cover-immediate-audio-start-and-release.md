# Brief 136: cover immediate audio start and release

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
Resolve the newly reproduced audio lifecycle failure before the clean rounds.

## Where things stand
The documentation/Hall copy from 132–135 is accepted. Normal integrated `pnpm verify` reached the gate-state suite, whose 10315 assertions passed but whose process logged `ERROR: 2 resources still in use at exit`; the unmodified runner correctly failed it. A separate verbose run reproduces the error and identifies title-theme OggPacketSequence, AudioStreamOggVorbis and their playback references.

The director then measured both real audio-wrapper classes without mocks: instantiate with the real title-theme stream, add to tree, call `play()`, immediately call `release()` before the next `_process`. For both `music_player.gd` and `sfx_player_2d.gd`: `played=true`, `observed_by_process=false`, `playing_after_release=true`. Both release/exit guards rely solely on `_needs_flush`, so sound started after that frame's watcher is missed. This is a real lifecycle guard defect, not grounds to weaken error reporting.

## Do
- Correct the confirmed immediate-play lifecycle in both existing wrapper classes: a currently playing stream must be stopped by release/teardown even when `_process` has not yet observed it. Preserve the documented pre-swap release contract and the existing AudioFlush fallback; do not add a wait to every ordinary scene transition. Check repeated use too: the wrapper must not lose observation permanently after a prior release.
- Add focused deterministic regressions in the already registered `test_combat_audio.gd` path for same-frame play/release, same-frame play/free fallback and release/replay for both classes. Use real wrapper instances and real audio; distinguish state assertions from the engine's shutdown-error evidence. Keep every existing assertion.
- Independently run the gate-state suite and combat-audio suite, with a verbose gate-state log when feasible. No resources-still-in-use ERROR may remain in those outputs. Keep the normal integrated runner unchanged.

## Do not
Change music selection, gains, sound assets, gameplay, visual layout, account/cloud services, versions, dependencies, runners, error filters or AudioFlush wait constants. Do not silence ERROR lines or skip assertions. Do not report an engine exit 0 alone as a clean test.

## Acceptance
Change only `apps/game/scripts/audio/music_player.gd`, `apps/game/scripts/audio/sfx_player_2d.gd`, and `apps/game/tests/test_combat_audio.gd`. Current real same-frame probes report playing false after release. New regressions fail against original guards, then pass after exact restoration. Original gate-state and combat-audio suites pass without ScriptError or resources-still-in-use ERROR. The director runs stock integrated verification again after accepting.
