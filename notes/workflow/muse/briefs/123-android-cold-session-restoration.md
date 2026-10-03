# Brief 123: restore the real Android Firebase session on cold launch

## The ask
"Google, Apple not ready하지말고 로그인 구현해줘 firebase로" and "우리 겜은 무한 겜이라서 계속 마지막 플레이 한 구간 저장되서 계속 이어가게 해주면 좋겠는데".
An app relaunch must restore its signed-in account and public ID instead of silently downgrading an existing Firebase session to a local guest.

## Confirmed source defect
The Android JNI dispatch correction has been accepted and the director is now repeating actual native login. Inspect `apps/game/addons/moonlit-identity/android/src/main/kotlin/dev/moonlitbeacon/identity/MoonlitIdentityPlugin.kt`: `moonlitGetSession(requestId,argsJson)` ignores its config arguments, calls describeSession -> FirebaseAuth.getInstance before programmatic Firebase initialization, catches the missing-default-app exception and reports local guest. Export stages public config in the bridge's arguments; it does not ship a google-services resource initializing the default app through FirebaseInitProvider. The mutation path initializes only on Guest/provider/token calls. On a new process, Firebase's persisted user is unavailable until that app is configured; returning local guest before initialization loses session truth. The equivalent iOS startup bug caused a confirmed physical crash and has already been fixed separately. Android must also initialize a session reader safely rather than rely on catching an exception and silently downgrading it.

## Do
- Make the synchronous Android session read consume the already staged public Firebase config and initialize the default Firebase app before reading its persisted currentUser. Preserve any already configured default app and all real UID/provider/public-ID ownership.
- Keep unconfigured/invalid input/absent activity safe and honest. The session read must never begin a request or mutation, emit a later signal, log config/tokens/personal data, sign in anonymously, or switch a user. Missing setup can still answer the safe local session. Factor the existing initializer if useful, while preserving mutation failures and locks exactly.
- Add a focused registered native-build/contract regression for configuration-before-first-session-read, synchronous no-bookkeeping/no-signal and no automatic sign-in. Extend `scripts/lib/player-identity-build.test.mjs` around the existing native source contracts; preserve the newly accepted iOS tests and all previous assertions. A negative restoring the old ignored-args session path must fail. Do not broaden into unrelated game suites.

## Do not
Touch GDScript bridge/account/entry, forecourt/Account/UI, iOS native source, SDK pins, configs/secrets/backend/entitlements/version/presets/package/store. The director owns SDK builds, device I/O and any Firebase readback. Do not claim a fake proves cold-start restoration on hardware.

## Acceptance and deliverables
Narrow Kotlin source, registered native-build tests and author-only evidence note. Director independently runs the touched Node suite and its old-code negative, recompiles the Android AAR through the wrapper, builds/reinstalls preserving data and repeats real Guest -> Firebase user/profile -> force-stop/relaunch -> same SDK session/public ID and link availability. Existing mutating initializer failure and cancellation protections must remain green. No replacement guest UID may be minted just by reading a session.
