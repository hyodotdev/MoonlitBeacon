# Brief 051: Fix the real native build failures, using measured dependencies

## The ask
Continue the native identity foundation. Android/iOS login must really compile; canned source tests are insufficient.

## Confirmed evidence
The director's round-3 Android build now resolves dependencies and passes Gradle syntax, but processDebugManifest fails. Real SAX exception: line 4 column 39, `The string "--" is not permitted within comments.` The XML comment contains the CLI flag `--build-android`. Correct all XML comment syntax and use an actual XML parser test, not only a string presence test.

The replacement godot-cpp tag `godot-4.7-stable` also does not exist (successful official git ls-remote returns no refs). Stop inventing a same-version tag. Official existing tag `godot-4.5-stable` is revision `e83fd0904c13356ed1d4c3d09f8bb9132bdc6b77`. The director fetched that exact source and compiled its DEFAULT extension API with SCons 4.9.1 on Xcode for `platform=ios arch=arm64 target=template_debug ios_min_version=13.0 -j4`; the archive links successfully. Template-release compilation is running. An extension compiled against the older supported API can run on the newer engine; document compatibility precisely, keep engine 4.7.1 unchanged, and do not require a nonexistent newer tag. The director also tried custom_api_file dumped by engine 4.7.1; that older generator collides on UINT8_MAX/INT8_MIN and other new constants, so do not prescribe that failed combination.

Real `node scripts/build-player-identity.mjs --fetch-deps --platform ios` with CocoaPods 1.16.2 fails during target inspection with `TypeError - no implicit conversion of nil into String`, target_inspection_result.rb:53. The current dummy pbxproj has empty build settings and incomplete PBXProject attributes. Provide a project CocoaPods can actually inspect and build, or use an official reproducible SDK dependency route that does not depend on an incomplete project. Xcode plist lint proves only syntax. Check exact Firebase 11 Objective-C-visible headers: if the Swift-based SDK needs a generated Swift header/module/framework build, perform that in tooling and supply a buildable layout rather than assuming Pods/Headers/Public/FirebaseAuth is sufficient.

## Do
Fix these concrete build defects, inspect all nearby source/templates against actual SDK API, and add meaningful syntax/preflight regressions. Supply complete build and export linking automation for Firebase and transitive dependencies; do not delegate missing project authoring to the director. Keep global native mutation locks and child environment sanitization from round 3. Report exact runnable commands and dependency versions.

## Do not
Do not download from the implementer or claim native builds passed there without running them. No gameplay/UI/cloud/locked project/presets/credentials/guard/store changes. No handwaved one-line director fixes. This is a newly measured XML and CocoaPods failure; the repeated nonexistent godot-cpp pin has now been independently checked and must use the proven revision.

## Acceptance and judgment
Director repeats real Android AAR compilation, SDK dependency installation and arm64 Objective-C++ bridge compile/link. No fabricated missing-dependency pins or SDK layouts. XML parser and CocoaPods/Xcode definition checks are meaningful. Produced artifacts and composed export registrations preserve IAP. Provider/device login remains a separate test from compilation. Focused Godot/Node identity tests remain clean.
