# 4.0.0 native session settlement log — preserve the completion request id (brief 124)

Author-only. Round 1 of assignment 20261003-1332-preserve-native-session-completion-reque.

## Observed failure (director-supplied, no device in this copy)

A real Android Guest tap creates a Firebase anonymous user, but the player
stays at Signing in indefinitely. Read-back showed one anonymous Auth user
and zero profile/checkpoint/Hall documents, with no Godot script exception.
Confirmed source path: `NativeIdentityAdapter._apply_session` cached only
status/kind/uid/provider, then emitted `get_session()` without `request_id`.
`PlayerAccount._accept_outcome` correctly refuses any pending completion
with no matching id, so the account's pending request never settles — while
the bridge and adapter have already settled theirs and their timeout cannot
release it.

## What changed

`apps/game/scripts/net/native_identity_adapter.gd` only:

- `_on_bridge_completed` passes the already-accepted tracked id into the
  async success fold: `_apply_session(folded, request_id)`.
- `_apply_session(outcome, request_id = "")` keeps caching the clean
  four-key snapshot (status/kind/uid/provider: no id, no token) and now
  emits an ephemeral event copy that carries the id only when the caller
  supplied one. Sync folds (`_fold_sync_outcome`) pass nothing, so sync
  refresh keeps emitting the bare snapshot and keeps its existing explicit
  synchronous `PlayerAccount` fold path; it never becomes a pending
  mutation. The token path (`_emit_token_session`), conflict/error paths,
  stale/double/cancel/draining guards, and `PlayerAccount._accept_outcome`
  are byte-identical in behavior.

Untouched by this packet: player_account, wrapper, native Kotlin/
Objective-C, configs, secrets, backend, SDK pins, UI/forecourt, package/
version/presets, project.godot, runner infrastructure, protected paths.
No debug logs, no automatic sign-in, no network/adb/device/store/git work.

## Regression

`apps/game/tests/test_player_identity.gd`, three whole-chain tests over the
real bridge -> wrapper -> native adapter -> PlayerAccount path (fake native
bridge, no device). The suite was already registered; no runner change.

- `_test_native_chain_async_success_settles_account`: pending guest,
  provider link (same Firebase UID, new provider), and provider sign-in
  each clear the pending lock, keep the public ID, publish the real cloud
  uid/provider, and emit exactly one `account_changed`. The emitted event
  carries exactly the accepted id; cached `get_session()` keeps no
  `request_id` and no token, and the event carries no token.
- `_test_native_chain_late_completion_ignores_current_request`: after a
  cancel, a late terminal for the cancelled id and a mismatched id (both
  injected past the wrapper) emit nothing, move no binding, and leave the
  current request owning the lock; the live terminal then settles exactly
  once and its double is dropped.
- `_test_native_chain_sync_refresh_stays_id_free`: sync startup refresh
  hydrates the restored uid/provider with no pending lock, the snapshot
  emission carries no id, and no account change fires.

Negative proof: restoring the old `session_changed.emit(get_session())`
line fails 9 chain assertions (pending never clears, zero changes, no id
on the event) while every pre-existing assertion stays green; the fixed
bytes pass the full suite again.

## Evidence

- `pnpm godot:isolated --timeout 150 --script res://tests/test_player_identity.gd`
  -> `identity test passed — 403 case(s)` (exit 0).
- `pnpm godot:isolated --timeout 300 res://tests/test_production_host.tscn`
  -> `production host tests passed — 534 cases` (exit 0).
- `pnpm godot:isolated --timeout 300 res://tests/test_identity_registration.tscn`
  -> `identity registration tests passed — 61 cases` (exit 0).
- `pnpm godot:isolated --timeout 600 res://tools/check_scripts.tscn`
  -> `confirmed compile of 163 scripts` (exit 0).
- `pnpm godot:isolated --timeout 120 --quit` -> exit 0.
- `pnpm check:hygiene` -> `repo rules ok` (exit 0).
- `pnpm check:store-screenshots` -> fails as expected: device capture
  proofs are absent in this copy and `apps/game` bytes changed. No
  recapture run; non-visual defect fix, existing screenshots stand.
