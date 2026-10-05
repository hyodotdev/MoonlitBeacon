# Player identity setup (4.0.0) — author-only release note

Standalone native player identity: ordinary Google sign-in (`google.com`)
on Android (Credential Manager + Google ID) and iOS (GoogleSignIn SDK),
Apple sign-in (`apple.com`) on iOS (native sheet) and Android (Firebase
browser OAuth flow), the optional Play Games v2 gaming profile
(`playgames.google.com`, Android only, never merged with `google.com`),
anonymous Firebase authentication for guests, and a stable public player ID
minted before local guest play. One Google account uses the same Firebase
provider on either platform; one Apple account likewise. No UI, no cloud
saves, no ranking, no title integration in this round — the later
integration brief reads the capability signals and receipts from these
modules. Presentation and owned-journey orchestration are separate tasks.

New code (all new files except the one noted IAP export-plugin change):

- `apps/game/addons/moonlit-identity/` — GDScript wrapper
  (`moonlit_identity.gd`, per-provider readiness gates), editor/export
  plugin (Play Games APP_ID manifest stamp, iOS URL-scheme plist stamp),
  iOS extension-list composer, iOS export manifest
  (`ios_export_manifest.gd`, frameworks/bundles/link flags plus the
  reversed-client-ID callback scheme), Android Kotlin plugin source
  (Google/Apple/Play), iOS Objective-C++ GDExtension source (Google/Apple
  plus the chaining URL forwarder), `.gdap`/`.gdextension`/Gradle/SCons/
  Podfile/Xcode templates, addon README.
- `apps/game/scripts/net/player_account.gd` — public-ID service with
  durable-readiness gating. No host change in this round: the production
  host task owns `PlayerAccount` wiring and calls the adapter's
  `refresh_native_session` from there.
- `apps/game/scripts/net/identity_adapter.gd` — adapter interface
  (`google` provider id, `refresh_native_session` contract).
- `apps/game/scripts/net/native_identity_adapter.gd` — wrapper adapter
  (`refresh_native_session` forwards the bridge's real `get_session`).
- `apps/game/tests/test_player_identity.gd` plus
  `apps/game/tests/support/fake_identity_adapter.gd` and
  `fake_identity_bridge.gd` — focused tests and doubles, run directly
  (the shared regression runner is out of scope for this task).
- `scripts/build-player-identity.mjs` plus
  `scripts/lib/player-identity-build.mjs` (+ `.test.mjs`) — preflight
  (per-provider readiness), public-config staging (partial configs stage
  with warnings), and native bridge builds.
- `apps/game/addons/godot-iap/godot_iap_plugin.gd` — the single permitted
  existing-file change: its iOS `extension_list.cfg` write now goes through
  the shared composer so the purchase extension survives alongside the
  identity extension. Nothing else in that file changed.

## Official documentation used

Exact links consulted while writing the native sources:

- Firebase, authenticate with Google on Android (Credential Manager plus
  GoogleAuthProvider; the dependency example pins credentials 1.3.0 and
  googleid 1.1.1):
  https://firebase.google.com/docs/auth/android/google-signin
- Firebase, authenticate with Google on iOS (GoogleSignIn headers,
  reversed-client-ID URL scheme, handleURL forwarding, FIRGoogleAuthProvider):
  https://firebase.google.com/docs/auth/ios/google-signin
- Google, Sign in with Google for iOS (official SDK integration):
  https://developers.google.com/identity/sign-in/ios/start-integrating
- Firebase, authenticate with Apple on Android (OAuthProvider,
  pendingAuthResult, SDK browser flow, reauth/link requirements,
  server-side Service ID/key configuration):
  https://firebase.google.com/docs/auth/android/apple
- Firebase, authenticate with Play Games Services on Android:
  https://firebase.google.com/docs/auth/android/play-games
- Firebase, authenticate with Apple on iOS:
  https://firebase.google.com/docs/auth/ios/apple
- Play Games Services v2 sign-in for Android (`GamesSignInClient.signIn`,
  `isAuthenticated`, `requestServerSideAccess` — no intents, no sign-out):
  https://developer.android.com/games/pgs/android/signin
- Play Games `GamesSignInClient` reference (v2 Task API):
  https://developers.google.com/android/reference/com/google/android/gms/games/GamesSignInClient
- Apple, Sign in with Apple overview:
  https://developer.apple.com/sign-in-with-apple/
- Apple, AuthenticationServices reference:
  https://developer.apple.com/documentation/authenticationservices
- Godot, creating Android plugins:
  https://docs.godotengine.org/en/stable/tutorials/platform/android/android_plugin.html
- godot-cpp (pinned for the iOS GDExtension build):
  https://github.com/godotengine/godot-cpp
- Firebase console (provider enablement, app configs):
  https://console.firebase.google.com/
- Apple developer account (App ID capability):
  https://developer.apple.com/account/
- Play Console (Play Games Services setup, OAuth client):
  https://play.google.com/console

## Pinned official dependencies

Single source: `IDENTITY_PINS` in `scripts/lib/player-identity-build.mjs`,
repeated in the templates (a Node test fails on drift):

- Android Gradle Plugin 8.5.0, Gradle 8.7, Kotlin 2.1.21, JDK 17,
  compileSdk 34, minSdk 23. The compiler matches the dependencies'
  metadata (Godot 4.7.1 and FirebaseAuth 24.0.0 ship 2.1.0) and the
  kotlin-stdlib 2.1.21 the official Godot POM resolves; older compilers
  fail metadata checks instead of compiling.
- `org.godotengine:godot:4.7.1.stable` (compileOnly, MavenCentral).
- `play-services-games-v2:20.1.2`, `firebase-auth:24.0.0` (also in the
  `.gdap`, which the export plugin reads for remote dependencies).
- `androidx.credentials:credentials:1.3.0`,
  `androidx.credentials:credentials-play-services-auth:1.3.0`,
  `com.google.android.libraries.identity.googleid:googleid:1.1.1` (also in
  the `.gdap` and `build.gradle.tmpl`; versions from the Firebase Android
  Google-sign-in documentation's own dependency example).
- `org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1` (also in the
  `.gdap` and `build.gradle.tmpl`): the pinned Credential Manager API is
  suspend-only — the Kotlin compiler's overload list proves no callback
  form exists at 1.3.0 — so the picker runs in a coroutine on the main
  dispatcher. Contemporary with Kotlin 2.1.0; Gradle resolution proves
  the version. Minimum API unchanged.
- godot-cpp tag `godot-4.5-stable` at revision
  `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77` (verified with
  `git ls-remote`: neither `godot-4.7.1-stable` nor `godot-4.7-stable`
  exists). The extension compiles against the tag's DEFAULT extension API
  and runs on the 4.7.1 engine unchanged; do NOT pass a `custom_api_file`
  dumped by 4.7.1 (that older generator collides on `UINT8_MAX`/`INT8_MIN`
  and other new constants). The iOS prereq check reads the `GODOT_CPP`
  checkout's git HEAD and refuses any other revision.
- Firebase iOS SDK `FirebaseAuth 11.0.0` plus `GoogleSignIn 7.1.0` (see
  `ios/Podfile.tmpl`; the Sign-In release contemporary with FirebaseAuth
  11.0.0 and the documented configuration/callback integration),
  CocoaPods 1.16.x (verified 1.16.2; the prereq check requires the 1.16
  line), SCons 4.9.1 (measured for the godot-cpp archives; recorded, not
  gated), `ios_min_version=13.0` shared by the godot-cpp archives and the
  bridge, CocoaPods platform 15.0 for the deps project. The game export
  targets iOS 17, so both link with no min-version warnings.
- The iOS privacy set is the six Firebase bundles plus the three
  measured GoogleSignIn-closure bundles (`AppAuthCore_Privacy.bundle`,
  `GTMAppAuth_Privacy.bundle`, `GoogleSignIn.bundle` — the last carries
  the sign-in button assets next to its manifest), identical in both
  real config roots. Any other set fails discovery loudly for
  deliberate blessing (same rule as before: no silent compliance
  drift). Resolved closure versions: GoogleSignIn 7.1.0, AppAuth 1.7.6,
  GTMAppAuth 4.1.1.
- FirebaseAuth 11 is Swift-implemented: the bridge imports
  `FirebaseAuth-Swift.h` (class interfaces, error codes) plus
  `FirebaseCore/FIRApp.h` and `FirebaseCore/FIROptions.h`, using the ObjC
  spellings `APIKey` / `GCMSenderID:` from the real headers. The
  generated header carries `@imports`, so the SCons compile enables
  `-fmodules -fcxx-modules` (Apple Clang 21 refuses `@import` in ObjC++
  with `-fmodules` alone — measured) with `-F` on the discovered
  frameworks and `-I` on the headers forest.
- Gradle builds invoke the system `gradle` binary and require exactly the
  pinned 8.7 (the preflight names any other version); the wrapper files ship
  for reproducible re-runs. Build children receive only an explicit env
  allowlist (tool paths and build dirs), never loaded secrets.

The plugin AAR carries its Godot 4 registration in its manifest
(`org.godotengine.plugin.v2.MoonlitIdentity`, same key scheme as the vendored
godot-iap AAR) plus consumer ProGuard rules keeping the bridge entry points.

## Provider setup checklist (director operations)

Historical baseline: when this standalone-bridge note was written,
Firebase Authentication had no enabled providers, and everything
below was a director operation in a configured copy.

Current completed setup (server/provisioning, not device login):
Anonymous, Google, and Apple Firebase providers are enabled; the
Apple provider carries the Service ID and code-flow team/key/
private-key configuration, and the signed 4.0.0 build-12 IPA
carries the Apple sign-in entitlement. Fresh `--check` preflight
reports iOS Google and Apple READY, and Android Google and Apple
READY as well. Android Google (debug build) and guest flows have
native evidence in the director record. Live provisioning evidence
lives in the [director 4.0.0 review status
note](../workflow/muse/director-four-zero-review-status.md) and
the final portions of the [4.0.0 hosting validation
note](../workflow/muse/four-zero-hosting-validation.md), not here.
Preflight READY and a signed entitlement prove configuration and
packaging only: they are not a successful native sign-in.

Live device evidence (separate scopes, 2026-10-05 KST): see the
[Apple authentication and cold-resume
validation](../workflow/muse/apple-auth-and-cold-resume-validation.md)
director record. Completed native authentication, durable save
preservation, and observed resumed gameplay are distinct claims;
a successful first-gate return is not every later cycle.

- iPad native Apple sign-in: completed on the connected iPad
  (installed game 4.0.0 build12). The original local guest public
  ID is retained after sign-in, the stored binding names Apple and
  matches the real non-anonymous Firebase user (`apple.com`), and
  the cloud checkpoint payload equals the parsed local checkpoint
  exactly with the same original ID on the public Hall entry. The
  return shows real Warden gameplay with a relic choice. This
  proves migration of the original local guest public ID. The
  baseline had no Firebase anonymous binding, so it does not prove
  linking an already-created anonymous Firebase UID without a UID
  change.
- iPad full process exit and cold launch: durable preservation
  verified. The game process was terminated, the subsequent
  process list contained no game executable, and a fresh launch
  rendered the real title. Local identity, Apple binding, and
  checkpoint bytes before and after the launch are identical
  (checkpoint1, cycle1, zone0, Warden level1, same journey and
  seed). The physical title/Continue tap and the automatic native
  SDK session hydration after that launch are still pending and
  are not claimed here.
- Android cold resume (Galaxy Z Flip5, 4.0.0 build17,
  Google-linked player): the existing first-gate checkpoint
  reaches real Night Forest combat twice via Resume (never New
  expedition). The repeat termination removed the game process, a
  fresh launcher start restored the same ID and Resume menu, and
  Resume returned to real combat. Identity, binding, and save
  bytes matched before and immediately after launch; after Resume
  the identity file's `created_utc` is harmlessly rewritten by
  `PlayerAccount._save_id`, so only the public ID itself is equal
  there. Checkpoint, revision, and binding bytes remain equal at
  all measured boundaries, and journey, route, seed, hero, cycle,
  zone, and growth match exactly. Repeat checks of the first gate
  only: not every later cycle/fork, another account, an offline
  session, or a destructively deleted account.
- Gate-start save contract: `Journey` and the arena save a
  segment-entry checkpoint on crossing a moon gate or entering the
  next cycle after a guardian reward. Continue restores the saved
  hero, level, relic stacks, missile growth, score bookkeeping,
  deterministic route, and seed at that gate. The exact last
  mid-combat position, live enemies, projectiles, cooldowns, combo,
  and floor loot are transient, and backgrounding does not replace
  the last valid gate checkpoint. This is the production contract,
  not exact-frame suspension. The automated journey/cloud
  regression cases are simulated evidence for later forks, separate
  from the physical first-gate observations.
- iOS delete-after-revoke-failure fix (brief168 source change):
  a missing fresh Apple authorization code or a token-revocation
  SDK error now stops with one retryable failure, preserves the
  native session and local binding, and never reaches Firebase
  user deletion; only successful revocation advances to Auth
  deletion. A compiled stub probe over the production methods
  passes its behavioral scenarios, and the previous revision fails
  the revoke-failure cases. No real account was deleted. Installed
  build12 and the previously submitted store package do not
  contain this fix; a new package and store replacement are still
  pending and will be recorded separately when they complete.

Still unverified: physical iPad Continue tap with resumed gameplay
and automatic SDK hydration after the cold launch; Android Apple
browser authentication; optional Play Games, which remains
unconfigured; round trips beyond the first gate, other accounts,
offline sessions, and destructive deletion. Android's aggregate
`--check` exit stays NOT READY solely because that optional Play
Games application ID is absent — ordinary Google and Apple
readiness pass independently and are not blocked by it.

Providers gate independently: stage what is ready and the app
offers exactly that — a missing Google client id never blocks
guest or Apple play, and a missing Apple setup never blocks
Google. `--install` stages partial configs with warnings (the
provider lines name what is ready); `--check` keeps the strict
full-readiness exit code.

Native requirements (the app will not sign in without these):

1. Google Cloud console → Credentials → the OAuth web (server) client id
   for the Firebase project → `MOONLIT_PLAY_SERVER_CLIENT_ID`. Android
   Google sign-in passes it to the Credential Manager Google ID option;
   the Play Games auth-code flow uses it too. Also note the iOS OAuth
   client id (Firebase console → project settings → the iOS app's
   config, `CLIENT_ID`) → `MOONLIT_GOOGLE_IOS_CLIENT_ID`. `--install`
   stages it into `moonlit_identity.cfg`, and the iOS export stamps its
   reversed form as the GoogleSignIn callback URL scheme at export time
   (no export-template hand edit).
2. Play Console → Play Games Services → setup for
   `com.crossplatformkorea.moonlitbeacon`; note the numeric Play Games
   application ID → `MOONLIT_PLAY_APP_ID`. `--install` stages the APP_ID
   into `moonlit_identity.cfg`, and the export plugin stamps it into the
   app manifest at export time (no export-template hand edit; the plugin
   AAR stays game-agnostic). The bridge refuses gaming-profile calls
   without it (`not_configured` naming `play_games_app_id`). The gaming
   profile is optional: nothing requires it for guest or Google play.
3. Firebase console → Authentication → enable Google, Apple, and Play
   Games; register the Android package + SHA-1 and the iOS bundle id; copy
   the public app configs (NOT the whole google-services bundle) into the
   export machine's ignored `.env`:
   `MOONLIT_FIREBASE_PROJECT_ID`, `MOONLIT_FIREBASE_SENDER_ID`,
   `MOONLIT_FIREBASE_ANDROID_API_KEY`, `MOONLIT_FIREBASE_ANDROID_APP_ID`,
   `MOONLIT_FIREBASE_IOS_API_KEY`, `MOONLIT_FIREBASE_IOS_APP_ID`.
   The natives initialize Firebase from these staged values; without them
   every Firebase call answers `not_configured` instead of throwing.
4. Firebase console → Authentication → Apple provider → complete the
   Android setup (Service ID, key, redirect configuration, all
   server-side). When that setup is done, acknowledge it with
   `MOONLIT_APPLE_ANDROID_ENABLED=true` so the app offers Apple on
   Android truthfully. The flag stages as `[apple] android_enabled`;
   nothing else about the Apple server setup enters the app.
5. Apple developer account → App ID → enable the Sign in with Apple
   capability for the game bundle, and Firebase console →
   Authentication → Apple provider → enable it for iOS. When both are
   done, acknowledge with `MOONLIT_APPLE_IOS_ENABLED=true` so the app
   offers the native sheet truthfully. The flag stages as
   `[apple] ios_enabled`. No services id is needed for the native sheet.
   A staged flag (or any fixture standing in for one) is an
   acknowledgement, not proof: genuine device Apple login stays a
   separate evidence item.
6. Final tooling handoff (director, real signed profile only): the game
   export must emit the Sign in with Apple entitlement. Godot 4.7.1's
   Apple exporter appends the `entitlements/additional` preset text into
   the emitted `.entitlements` file — that is the hook, not
   `capabilities/additional`, which only lists installation
   requirements. The required content is the key
   `com.apple.developer.applesignin` with array value `[Default]`, and
   the export must run under a provisioning profile whose App ID has
   the capability enabled, or the sheet fails on device. The iOS export
   wrapper (`scripts/ios.mjs`) stages that grant into the preset extras
   for exactly one export when Apple iOS readiness is acknowledged and
   supported, then restores the locked presets byte-exact and refuses a
   signing profile that lacks the grant.
7. The export plugin links the staged identity frameworks (plus
   `-ObjC -lz`) automatically once `--fetch-deps` and `--build-ios` ran.

Server/provider configuration (separate concern, documented here only):

- The Sign in with Apple service id (`MOONLIT_APPLE_SERVICE_ID`, optional in
  preflight, never staged into the app) matters only for web OAuth flows.
- OAuth consent screen, Play Games tester lists, Firebase authorized
  domains, and Play data-deletion obligations stay in provider settings.
- Firebase and the providers process account data as part of
  authentication. Google's SDKs authenticate under their own default
  account scopes (openid/email/profile): that is Google's documented SDK
  behavior, not a game choice, and not using profile data in game code
  does not mean Google requests none. App code adds no scopes of its own
  and never reads, saves, or logs a name, email, profile, token, or auth
  code — except the Firebase ID token returned only to the in-memory
  `get_id_token` caller for immediate use. The Apple sheet requests no
  personal scopes, and the Android Apple browser flow adds none.

Private material (OAuth client secrets, Apple `.p8`) stays in
provider/server settings and the export machine. It never enters the repo,
the build logs, or `moonlit_identity.cfg`.

## Build commands (director runs these)

```bash
# 1. Preflight: explains missing public config without printing values.
node scripts/build-player-identity.mjs --dry-run
node scripts/build-player-identity.mjs --check --platform android
node scripts/build-player-identity.mjs --check --platform ios

# 2. Acquire the iOS dependencies (director runs; network used here only).
git clone --branch godot-4.5-stable --depth 1 https://github.com/godotengine/godot-cpp
git -C godot-cpp rev-parse HEAD  # must print e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77
cd godot-cpp
scons platform=ios arch=arm64 target=template_debug ios_min_version=13.0 -j4
scons platform=ios arch=arm64 target=template_release ios_min_version=13.0 -j4
cd ..
# Point GODOT_CPP at the checkout and GODOT_CPP_LIB at its bin/ dir, then:
# (runs `pod install` for FirebaseAuth 11.0.0 + GoogleSignIn 7.1.0, builds
# the pods' static frameworks for iphoneos arm64 Debug+Release, and writes
# the MoonlitLink tree the bridge and the export staging read; needs
# CocoaPods 1.16.x and Xcode. Discovery searches the nested
# <Pod>/<Pod>.framework products, skips the Pods_MoonlitIdentityPods
# aggregate scaffolding, records exact bundle paths, and refuses ambiguous
# duplicates, and verifies the nine measured privacy bundles.)
node scripts/build-player-identity.mjs --fetch-deps --platform ios

# 3. Bridge builds. Dry-run reports missing deps; without it the script
# renders a standalone project under builds/moonlit-identity/, resolves the
# pinned official dependencies, compiles, copies the artifacts into place,
# and verifies registration symbols. Physical-device iOS only (arm64).
node scripts/build-player-identity.mjs --build-android --dry-run
node scripts/build-player-identity.mjs --build-android --release
node scripts/build-player-identity.mjs --build-android --debug
node scripts/build-player-identity.mjs --build-ios --dry-run
node scripts/build-player-identity.mjs --build-ios --release
node scripts/build-player-identity.mjs --build-ios --debug

# 4. Stage the public identifiers for one export, export, then clean up.
node scripts/build-player-identity.mjs --install
# ... run the Godot Android / iOS export ...
node scripts/build-player-identity.mjs --clean
```

`--install` writes `res://moonlit_identity.cfg` (mode 600) plus an ignored
copy under `builds/`. Never commit the installed file. If the project ever
wants it ignored by git, that `.gitignore` edit is a director call — the
implementer may not touch that file. The ordinary export wrappers
(`scripts/android-build.mjs`, `scripts/ios.mjs`) run the same
preflight/diagnostics, stage the config for exactly one export, and remove
it again on success, failure, or cancel; `--install`/`--clean` remain for
manual and fixture flows.

The iOS export plugin links the built static library plus every staged
identity framework (discovered from the Pods build: FirebaseAuth,
GoogleSignIn, and their transitive dependencies) into the Xcode project,
adds the required `-ObjC -lz` linker flags, declares the measured system
frameworks (AuthenticationServices, CoreTelephony, GameKit, SafariServices,
Security, SystemConfiguration, WebKit), registers the nine staged privacy
bundles for the app resources, stamps the GoogleSignIn callback URL scheme
(reversed iOS client id) into the app Info.plist, and writes the composed
extension list; godot-iap writes the same composed list, so the purchase
extension stays registered. Nothing about SDK linking is left to a hand
edit: `--fetch-deps` discovers the framework set, `--build-ios` stages it
per variant under `bin/ios/frameworks/<debug|release>/` plus the privacy
bundles under `bin/ios/resources/<debug|release>/`, writes a `.gdignore`
next to each staged set so the editor never imports the Apple-optimized
native products (bundle images ship byte-identical), verifies the full
export-input set (static lib entry symbol and both exclusions included),
and the export plugin links exactly what is staged (warning when the
staging is missing instead of linking a half-built export). The plist hook is probed on the running
engine (`add_apple_embedded_platform_plist_content`, legacy
`add_ios_plist_content` fallback); without either, the export warns and the
director registers the scheme by hand.

Archive verification proves the `.a` carries `moonlit_identity_ios_entry`;
it does not prove the game resolves it. The export hook additionally emits
whole-source C++ (via `add_apple_embedded_platform_cpp_code`, with the
legacy `add_ios_cpp_code` fallback) that the template places at namespace
scope in dummy.cpp: an `extern "C"` entry declaration so the static link
retains the archive member, a registrar whose constructor only queues an
engine init callback at startup, and the callback itself, which the engine
runs from the OS_AppleEmbedded constructor — after the dynamic-symbol map
exists and before extension lookup — to write the entry address with
`register_dynamic_symbol`. The entry is never called there, and nothing is
emitted when the static library is absent, so a library-less export stays
a clean graceful degradation.

### Full-app export/link inspection (director runs this)

1. Enable both `godot-iap` and `MoonlitIdentity` in a disposable export
   fixture (ignored scratch, never the locked project), with the built
   `.a`, frameworks, and bundles on disk. The export preset needs
   `plugins/MoonlitIdentity=true` alongside `plugins/GodotIap=true`;
   that preset edit is a director call (presets are locked).
2. Run the real iOS export (`node scripts/ios.mjs export` or the preset).
3. Inspect the generated `<App>/dummy.cpp`: it must contain the
   `extern "C"` entry declaration, the `MoonlitIdentityInitRegistrar`
   queueing `moonlit_identity_register_entry`, and that callback's
   `register_dynamic_symbol((char *)"moonlit_identity_ios_entry", ...)`
   write — all at namespace scope, with no naked call and no
   `godot_apple_embedded_plugins_initialize` redefinition.
4. Build the exported Xcode project for arm64/iphoneos.
5. `xcrun nm -gj <built-app>/MoonlitBeacon | grep moonlit_identity_ios_entry`
   must print the entry; on the pre-fix app it printed nothing.
6. Confirm both extension-list rows and all nine `*_Privacy.bundle`/`GoogleSignIn.bundle` dirs
   with untouched `PrivacyInfo.xcprivacy` files in the product.
7. Confirm the app Info.plist carries the reversed-client-ID
   `CFBundleURLSchemes` entry (Google OAuth callback). Confirm a foreign
   URL still reaches the delegate's previous handler: the bridge
   forwarder offers the URL to GoogleSignIn first and chains anything
   else, so existing app/IAP URL handling is preserved.

Link evidence (measured, not reasoned): `nm -u` over the real static
archives shows FirebaseAuth needing GameKit/SafariServices/WebKit/
Security, GoogleUtilities needing CoreTelephony/SystemConfiguration/
Security/zlib, GTMSessionFetcher needing Security; a real arm64 link of
all nine frameworks plus this explicit set plus `-ObjC -lz` produces a
clean Mach-O. The Swift runtime resolves through Xcode's default
toolchain library path plus object autolink (proven by the same probe:
no explicit `-lswift*` flags). The SCons bridge compile passes `-F` as
an explicit `CCFLAGS` item (SCons `FRAMEWORKPATH` was measured to never
reach the compile command) with `-fmodules -fcxx-modules`.

## Callback contract (both natives honor it)

- Each native method takes `(request_id: String, args_json: String)` and
  returns a receipt JSON string: `pending`, or a terminal `ok` / `error` /
  `cancelled` / `conflict` / `unsupported` / `not_configured`.
- A `pending` receipt is followed by exactly one terminal outcome on the
  `moonlit_identity_event` signal with the same `request_id`. Late answers
  after cancel or timeout and any second terminal for one id are dropped;
  settled-id memory is capped (64) and sync reads record nothing.
- `moonlitCancelRequest` answers `cancelled` while no SDK mutation began, or
  `draining` once one did. Draining keeps the operation lock; the terminal
  outcome still arrives and reports the truth. Timeouts extend through
  draining (two extra windows) before force-settling; session truth always
  comes from a fresh `get_session`.
- Each native holds a single mutation slot: a second sign-in/link/delete/
  sign-out while one drains answers `mutation_in_progress` (retryable)
  without touching SDK state. The slot releases only on SDK completion or
  pre-mutation cancel — never on a UI timeout. Session/token reads bypass it.
- Provider methods dispatch on the `provider` arg (`google`, `apple`,
  `play_games` on Android; `google`, `apple` on iOS) and answer
  `unknown_provider` for anything else. Session and conflict outcomes name
  the game-level provider mapped from the Firebase user's linked provider
  data — never a constant — so the gaming profile is never reported as
  the Google account.
- Missing Play Games `APP_ID` manifest metadata answers `not_configured`
  with `missing: ["play_games_app_id"]` before any sheet is attempted.
- A device with no Google account answers Android Google sign-in with
  `no_google_account` (not retryable in place; the account is added in
  system settings). Picker/sheet/browser dismissal answers `cancelled`
  (`user_cancelled`) with the previous account untouched.
- The Android Apple browser flow reattaches to `pendingAuthResult` when
  one is in flight (activity recreation) instead of starting a second
  flow; once the browser intent fires, cancel reports `draining`.
- Outcomes carry status, code, request id, and — on a cloud session — `kind`,
  `uid`, `provider` only. The `id_token` field exists solely on answers to
  `get_id_token`; auth codes, profiles, emails, and display names never
  cross into GDScript, logs, or saves. The Apple sheet requests no
  personal scopes and the Android Apple browser flow adds none; Google's
  SDKs authenticate under their own default account scopes, which game
  code neither adds to nor reads from.
- A link keeps the Firebase UID; a provider already linked to a different
  player returns `conflict` (`already_linked_elsewhere`) naming the
  attempted provider, and neither account is merged or overwritten. No
  social provider is ever auto-linked onto another: every link is an
  explicit call.
- iOS account deletion re-runs the Apple sheet natively for a fresh
  revocation code, then re-authenticates, revokes the grant, and deletes the
  Firebase user, unless `keep_provider_grant` is set. When the fresh code
  is missing or the revocation reports an error, the chain fails closed:
  it answers one recoverable `network_error` terminal carrying the re-read
  cloud session, never invokes Firebase user deletion, and leaves the
  native account signed in, so the UI retries the whole delete for a new
  code. Only a successful revocation advances to Firebase deletion, and
  only a successful deletion emits the local-session terminal. Android
  Apple-linked deletion re-runs the browser reauthentication natively,
  then deletes, unless `keep_provider_grant` is set. Google-linked
  deletion with a stale session answers `recent_login_required` so the UI
  re-runs the provider flow and retries. Play Games v2 has no
  programmatic sign-out; sign-out clears Firebase (plus the Google SDK
  state on iOS) while the Play profile stays linked at OS level by design.
- Deletion ordering stays fixed by the production host: owned cloud rows
  are removed before the native Auth deletion runs. A native deletion
  failure therefore preserves the local slot and binding and supports a
  retry, but the already-removed cloud rows are not restored — a failed
  native step is never reported as a successful deletion either way. A
  real destructive account deletion has not been authorized or performed
  in this audit; the revoke-failure path is covered by source-contract
  tests and a compiled behavior probe over the production Objective-C
  bodies, not by a device deletion.
- `NativeIdentityAdapter.refresh_native_session()` re-reads the bridge's
  real `get_session` through the normal outcome folding (sync answers
  apply at once, pending ones settle on the signal); `get_session()`
  stays a pure memory snapshot. An SDK-restored sign-in hydrates the
  adapter after a process restart through this method, without a new
  provider sign-in or UI. The production host task owns `PlayerAccount`
  wiring and calls it from there; this round makes no host change.
- An iOS sign-out that fails at the SDK answers `sign_out_failed`
  (retryable) carrying the re-read session, and preserves Google state;
  it never declares a guest success. The no-config no-op (local
  session) and the operation lock are unchanged.

## Readiness checklist for device checks (director runs these)

Source/mock tests ran in the implementer copy (see evidence in the round
report). The unchecked boxes below are the standing device-check
contract: every row stays a requirement and none is promoted to a
passed test here. An unchecked box is not a live claim that the
corresponding previously built artifact remains untested — signed
packaging and preflight evidence recorded in the director notes
above stands on its own. Native device completion still belongs to
the director after configuration; nothing below is claimed as
passed:

- [ ] `--build-android` / `--build-ios` compile from the pinned official
      dependencies; artifact verification passes (AAR manifest registration,
      static-lib entry symbol). `godot-cpp rev-parse HEAD` prints
      `e83fd09…`; `--fetch-deps` lists FirebaseAuth and GoogleSignIn among
      the built frameworks and the export links `-ObjC` with no missing
      symbols.
- [ ] The built `.app` contains all nine `*_Privacy.bundle`/`GoogleSignIn.bundle` dirs with
      untouched `PrivacyInfo.xcprivacy` files (export-plugin bundle
      registration is new; inspect the product, do not assume it), and the
      Info.plist carries the reversed-client-ID callback scheme.
- [ ] The game export links identity with IAP: no missing-symbol errors
      for Firebase, GoogleSignIn, system frameworks, or Swift runtime
      objects.
- [ ] `xcrun nm -gj` on the built app binary prints
      `moonlit_identity_ios_entry`, and the generated `dummy.cpp` holds
      the registration statement (archive checks alone do not prove this).
- [ ] Android device: Google picker opens from `sign_in_provider("google")`
      and signs the `google.com` Firebase user in; picker dismissal keeps
      the guest id with no UID switch; a device with no Google account
      answers `no_google_account`; link keeps the UID; link conflict
      shows the UI choice without merging; cancel mid-mutation drains to
      the true terminal.
- [ ] Android device: Apple browser flow opens from
      `sign_in_provider("apple")` after the server setup; closing the
      browser keeps the guest; link conflict shows the choice; delete of
      an Apple-linked account re-runs the browser reauthentication.
- [ ] Android device: Play Games sheet still opens from
      `sign_in_provider("play_games")` as the optional gaming profile; it
      is never required for guest or Google play, and its UID is never
      reported as the Google account.
- [ ] iOS device: Google sheet opens from `sign_in_provider("google")`,
      the OAuth callback returns through the URL scheme, and the same
      Google account yields the same Firebase UID as Android; dismissal
      keeps the guest; a foreign URL still reaches the previous delegate
      handler (callback chaining preserved).
- [ ] iOS device: Apple sheet opens from `sign_in_provider` with no personal
      scope prompts; cancel keeps the guest id; delete re-runs the Apple
      sheet, revokes the grant, and deletes the user.
- [ ] Providers gate independently on device: with Google unconfigured,
      guest and Apple work and Google refuses explicitly; with either
      Apple acknowledgement missing, Google works and that Apple
      provider refuses explicitly.
- [ ] iOS sign-out failure keeps the session: guarded by native and
      wrapper tests (a failed sign-out answers `sign_out_failed` with
      the re-read session instead of a guest success). No device
      trigger is required for this path.
- [ ] Guest play works with providers unconfigured (explicit `not_configured`,
      no crash, public id stable across restarts); unready identity (broken
      disk) refuses cloud calls until the retry save lands.
- [ ] A signed-in session survives a process restart: relaunch hydrates
      the adapter through `refresh_native_session` with no new sign-in
      and no UI.
- [ ] No token, auth code, profile, email, or display name appears in
      device logs or in `user://player_identity.cfg` after sign-in, link,
      token refresh, and delete flows.
- [ ] iOS export registration contains both the purchase and the identity
      extensions; store purchase flows still work after export.
