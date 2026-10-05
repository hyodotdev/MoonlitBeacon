# Brief 187: Open an unboosted native hero inspection

## The ask
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해 이것때문에 계속 배포를 못하고 취소하고 하자나”
The visual E2E contract requires all six heroes in four identifiable directions in the installed APK, in a quiet real Lv1 arena, without changing the user's account or saved journey.

## Confirmed starting point
The existing `hero_direction` runtime probe already proves clean real Player/physics/camera state, requested hero/direction, fresh nonce and observations. But `StoreCaptureBoot` only opens boosted Lv10 or Lv20/C3 presets. The registered clean-UI test explicitly excludes `hero_direction` from that boosted boot list. These presets cannot satisfy the Lv1/zero-kill/first-zone quiet contract. The original tap-to-start menu now goes through real account/save choices; using Start over to prepare each character would delete the user's saved gate. The director also inspected the installed engine's Android activity implementation: exported launch intents remove command-line extras. Do not bypass this or change activity permissions. Reuse the established owned debug request mechanism instead.

## One task
Add a narrowly scoped **unboosted** debug boot for the existing `hero_direction` inspection. It must open the real Arena with no TestLauncher boost, no journey arm/clear, no fake level/kills/HP and no production entry plan. `test_hero.request` continues selecting the next hero through its existing one-shot Arena consumer; `store_capture_runtime.request.json` continues supplying the separate nonce-bound hero/direction readiness proof. Opening an arena is not proof that it is ready; preserve the existing runtime checks untouched.

## Do
- Keep boot request validation fail-closed: debug build only, valid nonce, explicit allowed kind, invalid/release requests no-op.
- Distinguish this fresh inspection from boosted marketing presets. Do not call `_launch(0, 1)` or `_launch(1, 1)`: `_apply_test_boost` still grants max missile and survived time even at Lv1. Open the real scene without the boost meta or a title-origin journey plan.
- Refuse a boot if it would discard an already armed/pending real journey. Never clear or rewrite saved game/account files to make an inspection ready.
- Preserve normal title/account flow and existing boosted request behavior. Existing title-music lifecycle repair stays untouched.
- Extend the existing registered clean-UI suite (and a real-scene regression if needed) to distinguish unboosted inspection from old boosted boot, cover release/invalid rejection, and prove actual Lv1/cycle1/zone0/zero kills/full HP plus unchanged journey data through a real title→Arena inspection. Coverage must fail on the original code with just this repair reverted.
- Keep all scene readiness/hero direction constraints, native save guards, and overlay cleanup meaningful. Do not loosen any thresholds or forge proof fields.

## Overlap boundaries
Brief 186 is independently changing hero packers/art, Player, forecourt, hero regressions and public art documentation in another copy. Do not edit those paths, `production_entry.gd`, `run_regression_tests.mjs`, version counters, the build log, or any notes deliverables. This task should be limited to existing debug boot/launcher code and its registered clean-UI regression; if a new test harness is necessary, call it from that existing suite rather than changing the runner.

## Do not
Change Android activity permissions, engine/renderer/project locks, auth/save/cloud implementations, IAP, release behavior, balance, art/music, marketing screenshots or capture provenance. No network, device, git or store work. No account/SDK/Keychain resets. No additional user-visible UI.

## Acceptance / deliverables
The director will read the minimal diff, run the registered suite and an original-code negative control, then use ordinary `monkey` launch plus owned debug requests on the installed APK. A fresh `hero_direction` state must prove Lv1 and all original clean conditions with a consumed selected hero and matching nonce; post-image observation must advance while health and readiness remain unchanged. Tests must prove no Journey arm/clear/checkpoint write and no boosted state. Product code is debug-gated and leaves the retained store gallery untouched. Return the code/tests and an accurate report; no docs are needed for this internal-only operation.
