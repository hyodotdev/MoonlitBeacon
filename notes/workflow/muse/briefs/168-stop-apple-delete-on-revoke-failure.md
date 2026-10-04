# Brief 168: Stop Apple account deletion when grant revocation fails

## The ask
“완벽하게 해달라니까”
The player identity release must report real Apple authentication and deletion
outcomes, including failures, without claiming success prematurely.

## Why, and what good feels like
When Apple grant revocation fails, the player must receive a recoverable error
and retain the native signed-in account and local recovery data. A failed or
missing revocation must never be reported as a successful Firebase deletion.

## Where things stand
- The tree is clean. The iPad has completed real Apple authentication, returned
  to gameplay, retained the original local guest public ID, and written matching
  profile/reservation/checkpoint/Hall records. Cold restart and Android Apple
  completion are still being independently measured; do not claim they passed.
- `MoonlitIdentityIos.mm`, `revokeAppleGrant:user:authCode:`, currently invokes
  `deleteFirebaseUserAfterReauth:user:` both when the fresh authorization code is
  missing and when Firebase revocation reports an error.
- Firebase's official iOS Apple guide, Token revocation, says to obtain a fresh
  authorization code, revoke it successfully, then delete; missing code returns
  and a revocation error is displayed. Reference:
  https://firebase.google.com/docs/auth/ios/apple
- The director's existing filtered native contract tests pass 5 cases, but do
  not cover these failure branches. Player identity Godot tests pass 457 cases.
- `ProductionHost._run_deletion()` deletes owned cloud rows before native Auth
  deletion; failure already preserves local slot/binding and supports a retry.
  Do not claim that cloud rows are unchanged on a native failure.

## Do
- Make the iOS revoke/delete chain fail closed on missing fresh authorization
  code and revocation errors, with one truthful terminal error, existing session
  fields preserved, and no invocation of Firebase user deletion.
- Only a successful revocation may advance to Firebase deletion. Keep the
  existing request liveness/mutation/draining semantics and explicit
  `keep_provider_grant` behavior.
- Add meaningful regression coverage exercising the actual production Objective-C
  method bodies with stubbed SDK outcomes (not a rewritten JS version of the
  algorithm). On macOS the director must be able to compile/run the behavior
  probe with Foundation, and restoring the old fail-open call must fail it.
  Register portable contract coverage in an existing Node test group; explain
  any platform-specific behavior probe skip rather than claiming SDK execution.
- Update the callback contract in `notes/release/player-identity-setup.md` with
  the failure behavior and cloud/local distinction. Preserve the standing device
  checklist and historical readiness evidence. A real destructive account
  deletion has not been authorized or performed in this audit.

## Do not
- Do not change Android, login appearance, saves, public IDs, deletion ordering,
  provider scopes, dependency pins, version/build numbers, store metadata, guard,
  or screenshots. Do not touch credentials or network.
- Do not expand this into a login/account architecture refactor. Do not claim
  new code is already in the store build or has passed real-device deletion.

## Acceptance
- Missing code, SDK revocation error and a late retired callback never call
  Firebase user deletion; missing/error emit one error retaining the cloud session.
- Successful revocation calls Firebase deletion once; Firebase delete errors
  remain errors; successful deletion alone can emit the local-session terminal.
- The old failure branches fail the behavioral regression probe as a negative
  control. Existing native contract, identity export, and Godot identity tests
  remain green; hygiene remains green.
- The diff is limited to the iOS bridge, focused tests/probe and setup guide.

## Deliverables
- `apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm`
- Focused coverage under `scripts/lib/`, added to the existing identity test group
  without an unrelated package-script rewrite.
- `notes/release/player-identity-setup.md`

## Constraints specific to this task
Tokens/auth codes stay inside native SDK calls and never reach logs, GDScript or
saves. The error can use the existing generic recoverable network outcome if
that best preserves the wire contract. The native account remains signed in.

## How the director will judge
Read both changed branches and their call sites, compile and run the behavioral
probe, perform the negative control in the isolated copy, run related identity
tests and hygiene, then accept only confirmed fixes. Native device/auth results
and release packaging remain separate director operations.
