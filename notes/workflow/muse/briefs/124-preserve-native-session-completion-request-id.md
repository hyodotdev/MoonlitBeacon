# Brief 124: preserve the native session completion request id

## The ask
"Google, Apple not ready하지말고 로그인 구현해줘 firebase로"
"ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해"
Make successful native login settle the real PlayerAccount and production entry.

## Why, and what good feels like
The real Android guest SDK call creates a Firebase anonymous user, but the player stays at Signing in indefinitely. The director read back one anonymous Auth user and zero profile/checkpoint/Hall documents after a real Guest tap. No Godot script exception was printed. Source evidence identifies the lost completion id: NativeIdentityAdapter._apply_session caches only status/kind/uid/provider, then emits get_session() without request_id. PlayerAccount._accept_outcome correctly refuses any pending completion with no matching request_id. The bridge and adapter have already settled, so their timeout cannot release the still-pending PlayerAccount.

## Where things stand
- apps/game/scripts/net/native_identity_adapter.gd: _on_bridge_completed accepts exactly the tracked pending id and calls _apply_session for success; _apply_session drops it from the emitted event.
- apps/game/scripts/net/player_account.gd: _on_session_changed requires _accept_outcome, which rejects missing or stale ids; preserve this ownership guard.
- apps/game/tests/test_player_identity.gd mostly exercises the account and native adapter separately. Add a real bridge -> NativeIdentityAdapter -> PlayerAccount integration regression instead of another direct fake-account assertion.
- Accepted Android JNI dispatch and iOS/Android cold session initialization fixes must remain intact. Forecourt sprite positioning is being edited in another copy; do not touch UI files.

## Do
- Preserve the accepted request_id on the transient successful session completion event that reaches PlayerAccount, while keeping cached get_session snapshots clean and token-free.
- Cover pending guest, provider sign-in and provider link through the real adapter/account chain, including pending clearance, unchanged public ID, actual cloud uid/provider and exactly one account_changed outcome.
- Retain stale/double/cancel/draining protections. Prove a late or mismatched completion does not settle the current account request. Keep synchronous startup refresh behavior correct.
- Add registered meaningful regression in the existing identity suite; restore the old id-dropping line and demonstrate the new integration assertion fails. Run related host tests, not broad unrelated combat loops.

## Do not
- Do not weaken PlayerAccount._accept_outcome or accept request-id-free async events. Do not store the pending id in cached session, disk or bindings.
- Do not change native Kotlin/Objective-C, configs, secrets, backend, SDK pins, UI/forecourt, package/version/presets, project.godot, runner infrastructure or protected paths. Do not add debug logs or automatic sign-in.
- No network, adb, emulator, device, store or git history operations. The director will rebuild and verify native pixels plus backend.

## Acceptance
- pnpm godot:isolated --timeout 150 --script res://tests/test_player_identity.gd passes with genuine whole-chain guest/provider/link coverage.
- Related production host suite passes; existing assertions stay intact.
- Restoring old adapter session emission fails the new integration assertions; restored fixed bytes pass again.
- Cached get_session after completion has no request_id or token, emitted success carries exactly the accepted id; stale/double callbacks remain rejected.

## Deliverables
apps/game/scripts/net/native_identity_adapter.gd, focused additions to apps/game/tests/test_player_identity.gd, and a short author-only notes/plans/4-0-0-native-session-settlement-log.md.

## Constraints specific to this task
One confirmed request-ownership defect only. No other refactors. Existing local identity, progress and IAP bytes must be preserved. Check the store fingerprint and report expected stale without capture.

## Settle these yourself
Use an ephemeral event copy with the id only for the matching async success. If synchronous refresh emits a snapshot without an id, keep its existing explicit synchronous PlayerAccount fold path; do not turn it into a pending mutation.

## How the director will judge
Read all changed hunks and tests, run positive/old-source negative checks independently, rebuild the existing Android and iOS debug apps preserving user data, tap Guest, verify busy settles and the same public ID reaches a real Firebase profile, then cold-relaunch and check ownership stability.
