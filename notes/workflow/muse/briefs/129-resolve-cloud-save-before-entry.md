# Brief 129: resolve cloud save before entry

## The ask
“아이패드 로그인도 해줘야지 게스트 로그인은 잘돼? 이제 로그인 사용자 마지막 어디서 플ㄹ이했는지 알고 플레이 구간 있음 거기서 띄워주는거야?”
A returning cloud player must see the saved segment and Continue before being offered a fresh journey on a new device.

## Why, and what good feels like
On an empty device slot, signing in should check the owned cloud checkpoint before making a start decision. Waiting is explicit and bounded; network failure must not be presented as proof that no save exists. Existing offline guests and valid local resumes remain usable.

## Where things stand
Accepted uncommitted packets through 128; root full verify passes (production host 632, identity 457). Native Android Google UID/public-ID/checkpoint ownership and cold resume are verified. Do not touch SDK configuration or user data. The director independently reproduced a race using an isolated subclass of test_production_host: after _sign_in_cloud with an empty canonical slot, actual host coordinator account_ready is true, only the profile request has been sent, and plan_entry(true,false) returns ok and arms FRESH before restore_cloud.call_deferred executes. Probe initially had an invalid enum name; corrected probe exits 0 without ScriptErrors. Observation is available in the director status note, not production tests.

Relevant: production_host.gd _adopted_canonical, restore_cloud, plan_entry, account_state; production_entry.gd _refresh_identity; cloud_coordinator.gd restore_from_cloud; existing injected real-coordinator/fake-sender host tests. Automatic cloud restore currently runs only when local checkpoint is empty. Preserve that limited policy and explicit local/remote conflict choice.

## Do
- Own the initial empty-slot restore operation before any deferred work or ready emission. Guard plan_entry and UI readiness until a terminal restore result is resolved for that exact account/generation.
- Successful remote payload installs before Continue is shown; authoritative not-found unlocks fresh start. Non-not-found failures provide honest retry and an explicit offline/fresh decision instead of silently treating failed fetch as no save. Reuse the game's existing panels/visual language; no new generic popup/default controls.
- Bound waiting, prevent duplicate requests, clear/retire on sign-out, account switch, shutdown and cancellation; late results may not unlock or overwrite another account. Local saved guest resume and known local cloud resume must remain responsive.
- Add registered host/entry regression coverage using delayed real fake transport: immediate tap before deferred pull, pending remote request, remote install/Continue, not-found, network failure/retry, cancellation/switch/stale completion, same-account duplicate ready, and valid local resume. Assert actual entry card state and Journey mode, not only helper state.

## Do not
- Redesign Title, provider buttons, sprites, menus, or loading art. Do not change native identity plugins, secrets, Firebase/provider config, security rules, export/version values, package/engine/resolution, store media, Vault settlement, or cloud conflict policy.
- Auto-overwrite differing local saves, auto-start Arena, seed pretend cloud data, or make every returning player wait for network if their valid local checkpoint already exists.
- Weaken or delete existing assertions to hide the new guard; update fixtures only with a demonstrated contract change. Do not include any director probe in deliverables.

## Acceptance
- pnpm godot:isolated --timeout 300 res://tests/test_production_host.tscn passes all existing/added cases with no ScriptErrors; added tests fail against the old deferred-only restore behavior.
- New device cloud sign-in + delayed remote checkpoint cannot plan fresh or expose Ready before remote read; after valid remote restore, Continue resumes the remote cycle/zone/hero/checkpoint.
- Authoritative 404 may unlock Fresh; network failure cannot automatically unlock Fresh or claim no saved segment. Explicit offline decision is visible/reversible and retains account ownership; retries do not create parallel pulls.
- Timeout and stale completion cannot hang indefinitely or enter/mutate another account. Known local resume and local guest work offline. Same-account duplicate callbacks do not restart blocking indefinitely.
- Relevant locale, hygiene, game regression checks pass. Original provider/title/party pixels remain unchanged apart from the transient save-status UI required here.

## Deliverables
Narrow changes to apps/game/scripts/net/production_host.gd, apps/game/scripts/ui/production_entry.gd, their existing entry UI if unavoidable, registered apps/game/tests/test_production_host.gd, localization/gate_entry.csv only if new copy is needed, and notes/plans/4-0-0-build-log.md. Report exact behavior of failed fetch and explicit offline choice.

## Constraints specific to this task
The current source contains hundreds of accepted uncommitted changes: preserve them. Never put credentials or raw native user identity in reports. Preserve segment-entry save semantics and per-account partitioning.

## Settle these yourself
Prefer a brief save-checking state using existing Busy/Error/Ready surfaces with truthful localized copy. Distinguish pending initial restoration from authentication operation context so retries/cancellation cannot accidentally relink/sign-in. Use a bounded real elapsed deadline with a short injected test clock. A local-only guest needs no cloud check.

## How the director will judge
Read the full diff and tests, run host tests and related suites independently, remove one guarded line in the isolated copy to reproduce the race and restore exact bytes, inspect the player-visible checking/failure/ready screens, accept normally only after evidence, then root verify and sequential native builds if accepted.
