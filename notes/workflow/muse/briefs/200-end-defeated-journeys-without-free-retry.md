# Brief 200: End defeated journeys without a free gate retry

## The ask
“현재 게임에서 죽으면 코인으로 계속하거나 이어서 처음으로 가야하는데 그 스테이지에서 시작하는게 있네? 이거 수정해주고”

Remove the free restart of a defeated segment. A coin revives in place; leaving defeat or choosing a new expedition starts from the beginning. Quitting while alive still permits checkpoint continuation.

## Why, and what good feels like
The loss screen must give honest choices: one continue coin to revive, a fresh expedition, or return to the title. The title, cold launch, backup recovery and owned-cloud restore must not offer a free continuation of a run that already ended in defeat. Wallets, unlocks and earned permanent records survive.

## Where things stand
- Main was clean and fast-forward checked at `1ed5fb1`; work starts on `codex/gate-chamber-and-defeat-rules`.
- `arena.gd` currently implements `_retry_from_gate()` and `_finish_result_action()` deliberately routes defeat Retry there. `_finish()` preserves a playable checkpoint; `result_panel.gd` changes Retry to `RESULT_GATE_RETRY`.
- `journey.gd` persists main and backup checkpoint files; `has_valid_checkpoint()` powers title Continue. `cloud_coordinator.gd` and `cloud_checkpoint.gd` synchronize valid checkpoint payloads and conflicts.
- Baseline: `pnpm godot:isolated --timeout 180 res://tests/test_journey.tscn` passes 499 cases, including expectations for repeated free death retries. These expectations now describe the wrong product behavior and must be replaced with stronger death-terminal checks, keeping unrelated coverage.
- The title and production host entry are `scripts/ui/production_entry.gd`, `scripts/net/production_host.gd`, and `scripts/ui/title_menu.gd`.

## Do
- Make defeat a durable terminal journey state, with a compatible representation that the owned-cloud coordinator carries. A valid ended marker must outrank an older alive backup and survive cold launch/account switching/cloud conflict resolution. Do not merely delete a local file and allow remote restore to resurrect it.
- Remove the loss-screen free gate retry and its actual action route. Clearly label fresh restart and coin continue in all five locales. The final failure must settle rewards/records once; repeated exits, terminal restores or retries must not farm rewards.
- Keep paid continuation transactional: consume exactly one coin only on success, revive the current run in place with health/grace as before, and durably make it playable again. Failed persistence or insufficient balance must not erase or double-spend coins or make a terminal run resumable. Keep active living-run continuation after app quit unchanged.
- Update and register meaningful regressions for real arena death/result routes, fresh cycle/zone reset, alive quit, terminal main versus alive backup, cloud round trip and offline retry, coin success/failure, and wallet/record preservation. Update the game reference's affected journey paragraphs and an author-only implementation record.

## Do not
- No nickname/onboarding-room work in this brief; that is the next task.
- Do not alter hero art, identity/auth providers, purchases, version/build counters, locked engine settings or unrelated gameplay tempo.
- Do not capture or rebuild any store screenshots. Existing marketing images must remain byte-identical.
- No deployment, network, git history changes, secrets or protected files.

## Acceptance
- The previous defeat/free-gate-retry test behavior is no longer reachable from either result or title/cold launch. Fresh restart begins cycle 1/zone 0 with a new journey, while keeping permanent rewards/unlocks.
- A paid continuation preserves current hero, cycle/zone, score and growth, debits one coin once, and restores a resumable live journey. Zero coins and injected save failures keep balances and terminal status safe.
- Alive checkpoints still resume after process relaunch. Defeat tombstones remain terminal even when an older valid backup or stale remote payload is present; cloud conflict choices do not silently bypass the death.
- Related registered Godot tests, cloud tests, locale checks, game smoke check and documentation build pass. Do not weaken unrelated assertions or declare errors successful merely because Godot exits zero.
- Supply a production-scene desktop result harness for a real defeat with/without coins, so the director can see and exercise the actual buttons, with isolated user files.

## Deliverables
Affected journey/arena/result/cloud code, five-locale copy, registered regressions, targeted game-reference changes, one author note, and a small desktop review harness. Report exact files/commands, counts and remaining limitations.

## Settle these yourself
Keep the stable public ID and score ownership contracts. Use an additive terminal marker rather than weakening cloud validation. Preserve the existing once-only settlement ledger. The new-name chamber will use these corrected entry rules later.

## How the director will judge
Read all changed state transitions and persistence/cloud code; independently run the relevant tests and the full verification after acceptance; render and click the real result screen; inject a guarded defeat-state regression to prove a test fails. Judge terminal backup/cloud behavior, not just button text.
