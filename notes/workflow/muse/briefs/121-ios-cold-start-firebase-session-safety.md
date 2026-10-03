# Brief 121: safe iOS cold-start Firebase session restoration

## The ask
"Google, Apple not ready하지말고 로그인 구현해줘 firebase로" and "ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해".
The native iPad build must display the real game on a cold launch and restore its SDK session without an initialization crash.

## Where things stand and observed failure
The director compiled, signed and installed the current 4.0.0 iPad debug build with correct Moonlit identity plugin, staged public Firebase/Google config, native Apple capability and signing entitlement. Xcode/build/install all succeeded, but that is not runtime proof. The actual device immediately returns to Home. A fresh official devicectl foreground launch with console captured `FirebaseAuth/Auth.swift:152: Fatal error: The default FirebaseApp instance must be configured before the default Auth instance can be initialized` followed by signal 5, immediately after OpenGL context setup. No credentials were entered and no iPad save was cleared.

Confirmed source path: `apps/game/addons/moonlit-identity/ios/src/MoonlitIdentityIos.mm` `MoonlitIdentityIos::moonlitGetSession` discards p_args_json, then calls worker describeSession -> sessionOutcome -> `[FIRAuth auth].currentUser` without checking or initializing FIRApp. Provider/guest/token mutation methods initialize through ensureApp using staged public arguments, but session read is the startup operation and runs first. Apple Firebase SDK's Swift fatal error cannot be caught by an Objective-C exception handler after the fact. Primary official setup https://firebase.google.com/docs/ios/setup requires configuring Firebase before Auth access. The director supplies these facts since your copy has no network.

Other implementer copies are changing Account layout, forecourt sprites, and GDScript Android JNI identity dispatch. This packet owns only iOS native cold-session initialization/safety plus focused native-build regressions and an author-only note.

## Do
- Safely initialize the default Firebase app from the already staged public config before the first session read when no app exists. Preserve an already configured app. Cold-start after a real saved Firebase session must restore the current user, rather than reporting local guest just because initialization was delayed.
- An absent or rejected config must return an honest synchronous safe receipt/local session as appropriate to the existing bridge contract and never access FIRAuth without a configured FIRApp. Make the shared session helper safe wherever it is called, including sign-out failure reads. Do not treat Objective-C try/catch around Swift fatalError as a fix.
- Keep session reads synchronous with no request bookkeeping or later signal. Do not mutate user/UID/provider, sign in automatically, write or log any token or personal fields, or weaken request/cancellation/mutation locks. Reuse legitimate staged config and existing provider behavior.
- Add a focused meaningful native-build/contract regression for the first-call initialization/guard ordering, unconfigured no-Auth branch and synchronous no-signal session read. Existing scripts/lib/player-identity-build.test.mjs source contract checks are available; keep tests capable of failing under the original defective session path. Preserve all existing tests.

## Do not
Touch GDScript bridge/account/ProductionEntry, Account/forecourt/layout tests, SDK versions, config/env/secrets/profiles/entitlements/presets/version lock/package/renderer/stores. Do not solve by removing the native identity plugin or forcing offline success. The director performs dependency builds and physical device operations.

## Acceptance and deliverables
Narrow iOS source and registered native-build regression changes plus author-only evidence note. Director independently runs node --test scripts/lib/player-identity-build.test.mjs, reviews the complete source hunk and runs a negative with the old unguarded describeSession path. Director then rebuilds the existing native plugin through scripts/build-player-identity.mjs, exports/signs with the wrapper and relaunches the physical iPad: actual game pixels must appear and no Firebase initialization fatal error may recur. Subsequent Guest/provider/session tests must keep the public ID and real SDK binding. A source-only test does not prove physical success; report that limitation explicitly.
