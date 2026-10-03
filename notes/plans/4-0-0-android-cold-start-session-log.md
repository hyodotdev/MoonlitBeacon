# 4.0.0 Android cold-start session log — restore the real Firebase session (brief 123)

Author-only. Round 1 of assignment 20261003-1320-android-cold-session-restoration.

## Observed failure (director-supplied, no device in this copy)

An app relaunch silently downgrades an existing Firebase session to a local
guest. Confirmed source path: `moonlitGetSession(requestId, argsJson)`
ignored its config arguments and called `describeSession` ->
`FirebaseAuth.getInstance` before programmatic Firebase initialization,
caught the missing-default-app exception, and reported local guest. Export
stages public config in the bridge's arguments; it does not ship a
google-services resource initializing the default app through
FirebaseInitProvider. The mutation path initializes only on
Guest/provider/token calls, so on a new process the persisted Firebase user
is unavailable until the app is configured, and the pre-init local-guest
answer loses session truth. The equivalent iOS startup bug caused a
confirmed physical crash and was fixed separately (brief 121).

## What changed

`apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt`
only:

- New `ensureSessionApp(requestId, args)`: synchronous init for session
  reads. Uses the already configured app when one exists; otherwise builds
  one from the same staged public keys as the mutating path
  (`firebase_api_key`, `firebase_app_id`, `firebase_project_id`,
  `firebase_sender_id`). Absent activity, missing keys, or a rejected
  config answers false. Never touches request bookkeeping, never emits a
  signal, never touches `FirebaseAuth`, never signs in, never logs a value
  (rejection logs the request id and exception name only).
- `describeSession` (the shared session reader) now returns the local
  session when there is no configured app (`activity == null` or
  `FirebaseApp.getApps(host).isEmpty()`), before any `auth.currentUser`
  access. The unconfigured path no longer depends on catching the
  missing-app exception; the remaining catch in the entry is a backstop
  for genuinely unexpected errors only.
- `moonlitGetSession` now parses `argsJson` (invalid JSON falls back to
  empty args, which yields the guarded local session), calls
  `ensureSessionApp` first, then answers through `describeSession`.
  Cold-start with staged config and a saved Firebase user restores the
  live user with real UID/provider ownership; absent or rejected config
  falls through to the guarded synchronous local session. Still fully
  synchronous: no `begin*`, no `finish`, no receipt, no signal, no
  anonymous sign-in, no user switch.
- The mutating initializer `ensureFirebase` is byte-identical: mutation
  failure receipts, the single-mutation lock, and cancellation behavior
  are untouched. The session initializer duplicates its key handling
  instead of factoring it, mirroring the iOS `ensureApp` /
  `ensureSessionApp` pair, so the mutation path cannot drift.

Untouched by this packet: GDScript bridge, account, entry, forecourt,
UI, iOS native source, SDK pins, configs, secrets, backend,
entitlements, version lock, presets, package, renderer, stores.

## Regression

`scripts/lib/player-identity-build.test.mjs`, two source-contract tests
next to the existing kotlin checks; all existing tests preserved:

- `kotlin cold-start session initializes firebase before the first
  read`: entry parses args (`JSONObject(argsJson)`), calls
  `ensureSessionApp` before `describeSession`, never the bookkeeping
  `ensureFirebase(`, and stays synchronous with no signal and no
  sign-in; the sync initializer preserves a configured app, uses the
  staged keys plus `FirebaseOptions` / `FirebaseApp.initializeApp`,
  and never touches bookkeeping, `FirebaseAuth`, `currentUser`, or
  personal fields.
- `kotlin shared session helper never touches auth without a configured
  app`: `describeSession` guards with `FirebaseApp.getApps` before
  `auth.currentUser`, answers the local session when unconfigured,
  keeps real provider ownership through `providerOfUser`, and stays a
  synchronous read with no init, no bookkeeping, and no signal.

Evidence:

- New tree: `node --test scripts/lib/player-identity-build.test.mjs` ->
  81 pass, 0 fail.
- Negative (baseline `.kt` restored, new tests kept): 79 pass, 2 fail —
  both new tests fail on the old ignored-args path, all pre-existing
  tests still pass. Fix then restored, 81/81 green again.

## What the director must still prove on hardware

A source-only test does not prove cold-start restoration on a phone.
This copy ran no AAR compile, no export, no install, no relaunch. The
director recompiles the Android AAR through the wrapper, builds and
reinstalls preserving data, and repeats real Guest -> Firebase
user/profile -> force-stop/relaunch -> same SDK session/public ID and
link availability. Existing mutating initializer failure and
cancellation protections must remain green, and no replacement guest UID
may be minted just by reading a session.
