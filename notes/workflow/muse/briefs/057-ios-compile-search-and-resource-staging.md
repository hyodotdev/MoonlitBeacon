# Brief 057: Finish the measured iOS compile and SDK resource packaging

## Confirmed evidence
Round 5: the director independently reproduced all 56 Node and 166 Godot assertions. Actual Android Debug and Release AAR builds both succeed. Real `--fetch-deps --platform ios` now succeeds and finds the correct nine frameworks.

Actual `--build-ios --debug` still fails: `FirebaseAuth-Swift.h:349:9: fatal error: module 'FirebaseAuthInterop' not found`. SConstruct appends FRAMEWORKPATH, but the actual compile does not receive a working framework search path. The director then compiled the ENTIRE current MoonlitIdentityIos.mm with real godot-cpp headers, real built Firebase headers, `-fmodules -fcxx-modules` and an explicit `-F` for the discovered Frameworks directory: exit 0 with zero diagnostics. Thus the remaining compiler failure is a scripted search-path problem, not a reason to rewrite the native source. Add the proper compile-stage flags, prove their generated command, preserve path safety, and avoid unnecessary rebuilding or mutating the proven prebuilt godot-cpp environment.

The real device products also contain six `*_Privacy.bundle/PrivacyInfo.xcprivacy` resources under GoogleUtilities, FirebaseCoreInternal, GTMSessionFetcher, FirebaseAuth, FirebaseCoreExtension and FirebaseCore. Current staging copies only frameworks, and the export plugin has no bundle resource hook. Finish resource discovery/staging/export for those actual SDK products; do not fabricate or rewrite their privacy declarations. Validate a missing/ambiguous required resource loudly. Preserve original bytes and duplicate-free resource paths. Include Swift/static framework transitive link requirements in export verification so the resulting Xcode project can link, not just the standalone archive.

## Do
Fix the compile framework search flag, preserve the successful full source, and package the discovered SDK resources. Add focused tests of exact compiler arguments and real nested privacy-bundle layouts/byte preservation/export hook composition. Keep unchanged Android success and identity/global mutation guards. Director reruns arm64 Debug/Release script builds and then a real game export linking identity with IAP. No claim of successful provider/device authentication from compilation.

## Do not
No gameplay/UI/cloud, locked project/presets, secrets, stores/network/device/git-history operations. No warning suppression, edited vendor privacy manifests, or delegated missing authoring. Do not update the existing IAP vendor hash yet; integration will register its intentional composer change after inspection.

## Judgment
The scripted iOS builds must return success, stage matching-variant frameworks/resources, verify `moonlit_identity_ios_entry`, and produce complete export registrations. Director's manual full-source `clang++ -fsyntax-only` pass is supporting evidence, not a substitute for your script. Neighboring tests remain clean, and deliberately dropping the compile `-F` or resource registration must fail a meaningful check.
