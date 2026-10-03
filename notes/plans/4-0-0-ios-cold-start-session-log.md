# 4.0.0 iOS cold-start session log — safe Firebase restoration (brief 121)

Author-only. Round 1 of assignment 20261003-1300-ios-cold-start-firebase-session-safety.

## Observed failure (director-supplied, no network in this copy)

A fresh official devicectl foreground launch of the current 4.0.0 iPad debug
build returns to Home immediately after OpenGL context setup. Console shows
`FirebaseAuth/Auth.swift:152: Fatal error: The default FirebaseApp instance
must be configured before the default Auth instance can be initialized`
followed by signal 5. No credentials were entered and no iPad save was
cleared. Xcode build, sign, and install all succeeded; that is not runtime
proof.

Confirmed source path: `MoonlitIdentityIos::moonlitGetSession` discarded
`p_args_json`, then worker `describeSession` -> `sessionOutcome` read
`[FIRAuth auth].currentUser` with no `FIRApp` check and no init. Session
read is the startup operation and runs first; provider, guest, and token
paths init through `ensureApp`, but session never did. The Apple Firebase
SDK Swift fatal error cannot be caught by an Objective-C exception handler.
Official setup requires configuring Firebase before Auth access.

## What changed

`apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm` only:

- New `-ensureSessionApp:args:`: synchronous init for session reads. Uses
  the already configured app when one exists; otherwise builds one from
  the same staged public keys as the mutating path (`firebase_api_key`,
  `firebase_app_id`, `firebase_project_id`, `firebase_sender_id`, plus
  `ios_client_id` into `FIROptions.clientID` when present). Missing or
  rejected config answers NO. Never touches request bookkeeping, never
  emits a signal, never touches `FIRAuth`, never signs in, never logs a
  value (rejection logs the request id and exception name only).
- `sessionOutcome` (shared by the session answer and the sign-out failure
  terminal) now returns the local session when `[FIRApp defaultApp]` is
  nil, before any `[FIRAuth auth]` access. No try/catch around Auth.
- `moonlitGetSession` now parses `p_args_json`, calls `ensureSessionApp`
  first, then answers through `describeSession`. Cold-start with staged
  config and a saved Firebase user restores the live user; absent or
  rejected config falls through to the guarded synchronous local
  session. Still synchronous: no `begin*`, no `finishRequest`, no
  pending receipt, no signal.

Untouched by this packet: GDScript bridge, account, ProductionEntry,
forecourt, layout, Android JNI, SDK versions, config, entitlements,
presets, version lock, package, renderer, stores.

## Regression

`scripts/lib/player-identity-build.test.mjs`, two source-contract tests
next to the existing objc session checks; all existing tests preserved:

- `objc cold-start session initializes firebase before the first read`:
  entry consumes args (`parseArgs`), calls `ensureSessionApp` before
  `describeSession`, never the bookkeeping `ensureApp:`, and stays
  synchronous with no signal; the sync initializer preserves a
  configured app, uses the staged keys plus `FIROptions` /
  `configureWithOptions`, and never touches bookkeeping, `FIRAuth`,
  or personal fields.
- `objc shared session helper never touches auth without a configured
  app`: `sessionOutcome` guards `[FIRApp defaultApp] == nil` before
  `[FIRAuth auth]`, answers the local session when unconfigured,
  carries no try/catch, and stays a synchronous read;
  `describeSession` keeps its wire format with no bookkeeping, no
  signal, and no direct Auth access.

Evidence:

- New tree: `node --test scripts/lib/player-identity-build.test.mjs` ->
  79 pass, 0 fail.
- Negative (baseline `.mm` restored, new tests kept): 77 pass, 2 fail —
  both new tests fail on the old unguarded path, all pre-existing tests
  still pass. Fix then restored, 79/79 green again.

## What the director must still prove on hardware

A source-only test does not prove physical success. This copy ran no
device build, no export, no iPad launch. The director rebuilds the
native plugin through `scripts/build-player-identity.mjs`, exports and
signs with the wrapper, and relaunches the physical iPad: actual game
pixels must appear and no Firebase initialization fatal error may
recur. Subsequent guest, provider, and session checks must keep the
public ID and real SDK binding.
