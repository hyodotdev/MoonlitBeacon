# Brief 079: fix the real iOS sign-out failure session shape

## Measured
The director rebuilt your Round 2 against the actual pinned SDKs. Android Debug and Release both compile and stage successfully. The iOS dependency fetch now succeeds with all 12 frameworks and the nine real privacy/resource bundles. Preserve those corrections.

The actual arm64 Objective-C++ Debug bridge build still fails: `MoonlitIdentityIos.mm:1046:16: error: cannot initialize a variable of type NSDictionary *__strong with an rvalue of type NSString *`. `signOutFailedOutcome:` treats `describeSession:` as a dictionary even though its declared/implemented/bridge contract returns JSON NSString. This is a source type error in the new truthful sign-out failure branch, not a dependency or sandbox issue. Sanitized actual build evidence is under `builds/director-inputs/ios-session-shape/`.

## Correct and verify
Make the failure branch compile against the actual method contract and preserve the actual Firebase session identity/provider after sign-out failure. Keep the SDK-backed session source, the existing wire format, Google state preservation on failure, and error semantics. Do not fabricate a local guest or silence the failed SDK sign-out. Use a focused test that would detect mixing serialized JSON with a dictionary here; don't claim regex mocks prove real SDK compilation. Do not touch host, PlayerAccount, art, shared runners, presets, Vault or cloud services.

The director will build the actual Debug AND Release arm64 bridge and complete Godot app composition after this round. Run your related Node and native adapter suites, restore a meaningful negative control, and report the exact changed paths. No package/model/SDK upgrades or unrelated rewrite. Keep all resource manifests byte-identical and signing/config claims factual.
