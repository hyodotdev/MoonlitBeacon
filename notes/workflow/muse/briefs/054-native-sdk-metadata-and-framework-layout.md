# Brief 054: Match real Kotlin metadata and CocoaPods output

## Confirmed director evidence
Round 4 passes 50 Node and 166 Godot assertions, but the real native commands still fail. Android now reaches Kotlin compilation: Godot 4.7.1 and FirebaseAuth 24.0.0 metadata is 2.1.0; the pinned compiler 1.9.24 expects 1.9.0. The downloaded official Godot Maven POM explicitly depends on `kotlin-stdlib` 2.1.21. Match a compatible compiler/toolchain; do not suppress metadata checks or downgrade the locked engine.

Real CocoaPods installation and both device framework builds now succeed. Discovery fails because it only searches the output root: it sees `Pods_MoonlitIdentityPods.framework` but FirebaseAuth is actually at `Build/Debug-iphoneos/FirebaseAuth/FirebaseAuth.framework`, likewise Release. The real products contain FirebaseAuth.h and FirebaseAuth-Swift.h. Nine dependency frameworks are similarly nested under their target names (FirebaseCore, FirebaseAuthInterop, FirebaseAppCheckInterop, FirebaseCoreInternal, FirebaseCoreExtension, GoogleUtilities, RecaptchaInterop, GTMSessionFetcher). Preserve their exact discovered paths rather than rebuilding an assumed root path. Include these real nested products in tests; flat fake directories alone missed this defect.

## Do
Fix the compatible Kotlin pin and bounded nested framework discovery/link-tree/staging. Preserve real paths, reject ambiguous duplicates, and supply the real framework/header search flags needed by Objective-C++ compilation. Audit the full bridge against built Firebase 11 APIs, not only Apple's selectors. Make the scripted builds/export linking complete. Add regression tests that fail on the old compiler compatibility contract and actual nested layout. Keep all existing guards and unrelated source intact. Director will rerun both real Android variants and iOS arm64 bridge builds using the already built official dependency products.

## Do not
No gameplay/UI/cloud, protected/project/presets, credentials/network/store/device/git-history operations, or metadata-check bypasses. Do not claim native builds succeeded in your copy without running them. Do not author an approximation of provider success. Native provider configuration/device authentication remains a separate check.

## Judgment
Exact commands `node scripts/build-player-identity.mjs --build-android --debug` / `--release`, `--fetch-deps --platform ios`, and `--build-ios --debug` / `--release` must compile and verify their actual artifacts. Neighboring 50/166 tests remain clean and stronger tests exercise these defects. The director will check produced metadata/entry symbol and export composition. Report changed pins and commands precisely.
