# Brief 127: retry the original account link operation

## The ask
"동의해. 기존 게스트 기록에 Google 계정 연결 진행"
"ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해"
An account-link retry must keep linking the existing guest; it must never silently become a sign-in to a different Firebase user.

## Why, and what good feels like
The director has now reproduced a real Android Google link failure, followed by Retry. The second Google authentication succeeds, and the UI displays the old public ID and saved Warden/Wave 1, but administrative Auth readback shows a newly created Google UID while the original anonymous UID still owns the profile/checkpoint/Hall. This is a real ownership error, not merely copy. Source evidence is exact: ProductionHost.retry_login always calls sign_in_provider, even when the failed call was link_provider. Both platforms share this host. The original records remain untouched and must stay recoverable.

## Where things stand
- apps/game/scripts/net/production_host.gd: begin_provider, link_provider, switch_to_provider, retry_login, cancel_login and account outcome handlers.
- apps/game/scripts/ui/production_entry.gd: account link requests enter host.link_provider; the shared Error Retry enters host.retry_login.
- apps/game/scripts/net/player_account.gd: existing guarded sign-in versus link operation; do not weaken pending/request-ID ownership.
- apps/game/tests/test_production_host.gd is Node-based and must run via res://tests/test_production_host.tscn (not --script). Current director run is 539 assertions, clean.
- The integrated Root pnpm verify passed before this confirmed retry defect. Accepted pending settlement, cold Firebase init, grounded intro and guest-last chooser are already in this copy.

## Do
- Retain the actual last user-requested authentication operation and its provider before the call, including synchronous error callbacks. Retry must repeat link after a link failure, sign-in after a sign-in failure, and an explicit switch only after that explicit operation. Guest retry keeps its current semantics.
- Bind the retry context to the matching provider; refuse or safely handle a different stale provider so an old UI event cannot link/switch another account. Clear stale context on ordinary cancellation, successful terminal completion and sign-out/deletion as appropriate; retain it on a retryable failure. Preserve draining/deletion refusal and request ownership.
- Add a meaningful real Host -> PlayerAccount -> adapter regression with an anonymous SDK session, failed Google link, then Retry. Assert the adapter receives link again (zero sign-in calls), successful link retains the original UID and durable public ID, and profile/checkpoint/Hall configuration never adopts a second UID. Also cover ordinary sign-in retry, explicit switch/conflict, mismatched retry, synchronous failure and cancel/draining boundaries where applicable.
- Run the focused host and identity suites, and demonstrate old retry dispatch fails the new regression. Report exact results and a short distinct author note.

## Do not
- Do not migrate, overwrite, delete or repair real accounts/data; the director handles the already-reproduced device state separately. No native SDK, backend, security rules, configs, tokens, model settings, credentials, network, device or git operations.
- Do not merge conflicting accounts automatically, weaken identity/binding checks, invent success, add debug logs, or change production UI/art/order/version/export presets. No broad refactor or unrelated coverage.

## Acceptance
- pnpm godot:isolated --timeout 150 res://tests/test_production_host.tscn exits 0 with no ScriptErrors and genuine link-failure/retry coverage.
- pnpm godot:isolated --timeout 150 --script res://tests/test_player_identity.gd exits 0.
- Restoring the old sign_in_provider retry dispatch fails the new linked-UID preservation test; byte-exact fixed restoration passes.
- Same guest UID/public ID across successful retried link; no unsolicited account switch; deletion/draining/cancellation guards intact.

## Deliverables
apps/game/scripts/net/production_host.gd, focused test additions to apps/game/tests/test_production_host.gd (identity tests only if genuinely needed), and notes/plans/4-0-0-link-retry-ownership-log.md. Avoid other deliverables.

## Constraints specific to this task
One confirmed account-ownership defect. Preserve all existing uncommitted game improvements and every existing local slot. No store capture/upload. The director will rebuild and install preserving device data after acceptance.

## Settle these yourself
Use a small typed retry-operation record or fields at the host's operation boundary. Record before invoking the account because synchronous errors can arrive during the call. Do not infer link intent solely from provider names or presence of a cloud session, since explicit switches are legitimate.

## How the director will judge
Read every changed hunk; independently run focused tests, restore old dispatch as a negative control and restore exact fixed bytes, then normal accept--check/accept. Rebuild Android and iPad sequentially and verify actual account identity/server ownership, not merely the displayed label.
