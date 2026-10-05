# Brief 184: Stop detached title music starts

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”
“스샷은 새로 안찍어도 돼”

Finish the replacement release without a title teardown error. This is a narrow lifecycle repair, not a redesign.

## Where things stand
The physical attacks and lazy actor allocation repair are already accepted in this tree. Root `pnpm verify` passed, including 6,368 physical-motion assertions and 157 node-budget assertions. Native Android 18 combat boot reproduced a current-process error on three starts: `ProductionEntry._fade_in_music`, `res://scripts/ui/production_entry.gd:903`, cannot call `create_timer` on a null value. The boot path launches production entry then transitions to the arena with the existing debug boot request. The function calls `get_tree().create_timer` before checking tree membership. The delayed and tweened music lifecycle must also be inspected for teardown or superseded start/stop intent; only confirmed defects should be fixed.

## Do
- Read the production title/music transition and the existing relevant tests.
- Make detached music start safe before creating any tree timer or tween; preserve normal audible delay/fade and release behavior.
- Add meaningful regression coverage reproducing the actual detached-before-start case and checking no delayed restart after a subsequent stop or teardown if the implementation permits it. Register the regression in the existing game runner.
- Run the relevant tests in the copy. Explain each necessary change and the regression result.

## Do not
- Touch actor art, attacks, save/auth/provider configuration, scene layout, version counters, locked engine settings, release tools, or capture/gallery files.
- Weaken existing tests, silence errors globally, swallow all audio failures, or make the title silent to pass.
- Touch git history, network, device, credentials or stores.

## Acceptance
- Relevant headless regressions pass with no script errors, including starting title music while its initialized node is detached.
- The new detached lifecycle assertion must fail on the original implementation when the director reverts only the repair in a disposable copy.
- Normal title start preserves its configured delay/fade and gameplay transition still releases title music.
- Existing game smoke, locale and hygiene checks pass. The director will rebuild native Android and verify the current PID no longer emits the reproduced error.

## Deliverables
A minimal change to `apps/game/scripts/ui/production_entry.gd`, a relevant registered regression (reuse an appropriate suite or add a narrow suite), and its runner entry if needed. No documentation is necessary for this invisible teardown correction.
