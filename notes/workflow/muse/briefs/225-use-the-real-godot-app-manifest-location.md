# Brief 225: use the real Godot app manifest location

## The ask
Finish the native iOS attendance reminder export requested in brief223.

## Confirmed remaining defect
The round2 merger currently computes `join(projectDir, scheme, 'PrivacyInfo.xcprivacy')`. The director's actual Godot4.7.1 export places the engine manifest directly at `builds/ios/PrivacyInfo.xcprivacy`, alongside `MoonlitBeacon.xcodeproj`, not under `builds/ios/MoonlitBeacon/`. Its PBXFileReference has `path = PrivacyInfo.xcprivacy; sourceTree = "<group>"` and is a child of the root PBXGroup. The added tests create the invented nested path, so they can pass while the real export fails with missing app manifest.

## Do
- Correct the generated manifest path to the observed Godot export root, and make the test fixture reflect that actual root layout rather than calling the implementation's path helper to generate a self-confirming fixture.
- Check the generated project registration against the observed layout. Keep fail-closed behavior for ambiguity/missing paths and keep SDK bundles untouched.
- Preserve all scanner and privacy merge corrections from previous rounds. Run focused registered tests, report exact results. Do not spend a long run repeating full verification of the same copied-import environment; the director will run it on the integrated root after acceptance.

## Evidence
The director copied the actual engine-generated manifest and the previously failing project's project.pbxproj into ignored `builds/verify/director-ios-export-fixture/` in this copy. The old project intentionally contains two root output registrations (one engine and one loose addon) and should be rejected by the duplicate guard. These are generated diagnostic inputs, not deliverables.

## Do not
Do not move the engine manifest into an invented folder or write a second Xcode resource. Do not edit SDK privacy manifests, credentials, signing, assets, marketing screenshots or game behavior.

## Acceptance
The owned export pipeline opens the real root engine file, merges UserDefaults CA92.1, preserves engine reasons and tracking, and registers one root output. Focused tests use an independently specified root layout and fail if the obsolete nested path is restored. The director will repeat the real export and Xcode build.

## Deliverables
Narrow path correction and meaningful regression evidence, with an accurate report.
