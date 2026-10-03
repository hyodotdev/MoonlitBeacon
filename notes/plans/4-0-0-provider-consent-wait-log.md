# 4.0.0 provider consent wait log (brief 128)

Native provider sheets (Google account chooser, Apple sheet) waited on a
human but were deadline-bound as 30s network calls: leaving the consent
screen open past 30s made the native side report "Sign-in request canceled
by Moonlit Beacon" and the game returned to Could not sign in. The bridge
now arms a bounded 300s human-interaction window for the sheet calls and
keeps every other call at 30s.

## Native review: which methods genuinely show consent

No dedicated reauthentication method exists on either native side. The
`moonlit*` surface is: SignInGuest, SignInProvider, LinkProvider,
GetSession, GetIdToken, SignOut, DeleteAccount, CancelRequest.

- `moonlitSignInProvider` / `moonlitLinkProvider` always present the
  native account/consent chooser (Credential Manager / browser OAuth /
  GoogleSignIn / Apple sheet). These two take the interactive window.
- Reauthentication rides on existing calls: a stale Google session
  answers `recent_login_required` so the UI re-runs the sign-in sheet
  (covered by the sign-in window); the Apple reauth runs inside
  `moonlitDeleteAccount` (Android `beginAppleReauthDelete`, iOS
  `deleteAccount` Apple leg + `reauthenticateWithCredential`).
- `moonlitDeleteAccount` shows a sheet only for Apple-linked users without
  `keep_provider_grant`; anonymous/Google deletes are pure network, and
  the wrapper cannot see the linkage at dispatch time. It stays at 30s at
  the bridge: its user-visible deadline is the host's
  `DELETE_NATIVE_TIMEOUT_SECONDS` (30s), and the host is owned by brief127
  and untouched here. Blanket-expanding a usually-network call would also
  break the "ordinary network operations stay 30s" rule.
- Guest, session, token, sign-out never show a sheet: 30s unchanged.

## Implementation

`apps/game/addons/moonlit-identity/moonlit_identity.gd` only (+ tests):

- `INTERACTIVE_TIMEOUT_SECONDS = 300.0` next to the 30s constant.
- `_timeout_for_method(method)`: the named policy. SignInProvider and
  LinkProvider select the interactive window; everything else selects the
  ordinary window.
- `_native_call` stores the chosen `timeout_seconds` in the tracked
  pending entry; `_arm_timeout` re-arms from that stored value, so
  draining extensions retain the request's own window even if an override
  changes mid-flight.
- `set_request_timeout_seconds` keeps its historical blanket meaning (it
  now sets both windows) so the four existing call sites behave exactly
  as before; new `set_interactive_timeout_seconds` narrows the sheet
  window (call it after the blanket setter to separate them). Both clamp
  at 0.5s as before.
- `pending_timeout_seconds(request_id)` test hook reads the stored
  window (-1 for unknown ids), mirroring `settled_request_count`.
- Cancel, draining ownership, settled-id suppression, and token scrubbing
  are untouched: expiry still asks native to stop, then force-settles a
  retryable `request_timeout` (never a success).

## Tests

`apps/game/tests/test_player_identity.gd` gains five cases (54
assertions, all through the real request path; short injected timing, no
5-minute sleeps). Already registered in `run_regression_tests.mjs`; no
fixture change was needed.

- policy selects per method: Android google/apple sign-in/link arm 300s,
  guest/session/token/sign-out/delete keep 30s, iOS google/apple sign-in
  arm 300s, unknown id reports -1. No timers armed (off-tree).
- interactive timeout settles and drops late: interactive 0.5s with the
  ordinary default untouched; a Google sign-in settles as retryable
  `request_timeout` and the late provider answer is dropped.
- ordinary and interactive differ on one bridge: blanket 0.5s then
  interactive 60s; the guest times out fast while the Apple link stays
  pending, then cancels at once; its late answer is dropped.
- cancel stays immediate at production defaults: Apple sign-in arms 300s
  yet cancels at once (native asked, one `user_cancelled` outcome, lock
  released); stale, late, and double answers stay dropped.
- draining retains the stored policy: interactive 0.5s changed to 60s
  mid-flight; the draining Google link still force-settles on its
  original 3 x 0.5s windows with `request_timeout`, late answer dropped.

## Evidence

- Baseline before the change: `pnpm godot:isolated --timeout 150
  --script res://tests/test_player_identity.gd` -> 403 cases pass.
- After: same command -> 457 cases pass, 0 SCRIPT ERROR, ~8s.
- Negative: `_timeout_for_method` forced to the ordinary window for all
  methods -> suite fails 16/448, every failure in the new consent
  coverage (300s selections, injected-window timers, split pending,
  draining retention); zero old-test regressions. Fixed bytes restored
  (sha256 `45640585...` verified identical before/after) -> 457 pass.
- `node --test scripts/lib/player-identity-build.test.mjs` -> 81/81
  pass (unchanged code, confirms no build/config drift).
- Related insurance: `res://tests/test_identity_registration.tscn` ->
  61 cases pass, 0 SCRIPT ERROR.
- `pnpm godot:isolated --timeout 600 res://tools/check_scripts.tscn` ->
  164 scripts compile. Isolated `--quit` smoke exits 0.
  `pnpm check:hygiene` ok. `pnpm check:store-screenshots` red as
  expected after touching `apps/game/` (proofs absent in this copy);
  not recaptured, brief does not authorize it.

## What bit

- The override-semantics choice (blanket setter vs ordinary-only) was the
  one real design fork. Blanket won: the brief demands the existing
  setter stay backward compatible, and unseen sibling suites using the
  old "override shortens every request" contract keep working; the new
  setter separates the windows with one documented ordering rule.
- Negative-run case total reads 448, not 457: two timer tests index
  `outcomes[0]` after a wait that (correctly, under the broken policy)
  yields nothing, aborting those two functions early. Same unguarded
  style as the existing timer tests; positive runs are unaffected.

## Device follow-up for the director

Keep the real Google consent screen open past 30s on the Galaxy build and
confirm completion still links the original public ID/UID and save. The
Apple delete sheet (Apple-linked delete re-runs consent inside
`moonlitDeleteAccount`) still answers to the host's 30s delete deadline;
if slow humans must be allowed there too, that is a host change for the
brief127 line, not this bridge.
