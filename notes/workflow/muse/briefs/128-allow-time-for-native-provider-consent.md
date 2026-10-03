# Brief 128: allow time for native provider consent

## The ask
"Google, Apple not ready하지말고 로그인 구현해줘 firebase로"
"ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해"
Let the player finish real provider account selection/consent instead of cancelling it as a short network request.

## Confirmed evidence and current scope
The director's real Galaxy Google SDK sheet displays a valid Moonlit Beacon account/consent. Waiting for the human's approval causes the native sheet to report "Sign-in request canceled by Moonlit Beacon" and the game returns to Could not sign in. Source apps/game/addons/moonlit-identity/moonlit_identity.gd uses REQUEST_TIMEOUT_SECONDS=30 for every pending method, including provider sheets. No native credential error is logged on these cancellations. Consent completed quickly in another attempt authenticated successfully. A separate brief127 is fixing host retry operation ownership in another copy; do not touch that host/UI/test suite.

## Do
- Give interactive provider sign-in/link and interactive reauthentication a distinct bounded human-interaction window, default 300 seconds. Keep ordinary guest registration, session/token/network operations at their existing 30 seconds.
- Preserve immediate user cancellation, finite timeout/draining settlement, request-ID ownership, stale/late/double suppression and token secrecy. Do not disable deadlines or expand all network calls. Review whether interactive account deletion/re-authentication uses its own native method and include only methods that genuinely show consent.
- Keep existing set_request_timeout_seconds test overrides deterministic and backward compatible. Use a named policy/helper and store the chosen per-request timeout when tracked; repeated draining windows retain that request's policy.
- Add meaningful registered identity bridge tests: method-specific policy for Google/Apple sign-in/link, ordinary calls unchanged, real pending timer uses chosen policy, user cancel settles immediately, timeout boundary still settles, late provider callback remains dropped. Use short injected test timing rather than sleeping five minutes.
- Prove restoring the universal30-second policy fails the new behavioral assertions. Run identity403 baseline and related native build Node tests; do not broaden to unrelated game loops.

## Do not
No ProductionHost/ProductionEntry edits, provider setup/SDK pin/config/version/presets changes, native Java/Objective-C changes, security-rule changes, network or device operations, assets/UI redesign, debug logs, or git operations. Do not weaken the native mutation lock or turn a timed-out completion into accepted success.

## Acceptance
Provider sign-in/link interactive requests select300s in production; ordinary guest/get-session/get-token remain30s; test overrides can keep tests fast. Real bridge pending bookkeeping/timers follow that policy, explicit cancel stays immediate, timeout stays bounded and late outcomes stay ignored. pnpm godot:isolated --timeout 150 --script res://tests/test_player_identity.gd and node --test scripts/lib/player-identity-build.test.mjs pass without ScriptErrors. Old universal timeout negative must fail the new coverage, fixed bytes restored pass.

## Deliverables
apps/game/addons/moonlit-identity/moonlit_identity.gd, focused apps/game/tests/test_player_identity.gd additions (support fixture only if necessary), and notes/plans/4-0-0-provider-consent-wait-log.md. No shared author-note append.

## How the director will judge
Read every changed hunk, independently run positive/old-policy negative checks and restore exact bytes, normal accept--check/accept, then rebuild both native debug apps sequentially. The director will keep the real Google consent screen open longer than30 seconds and verify it can still complete with the original linked public ID/UID and save.
