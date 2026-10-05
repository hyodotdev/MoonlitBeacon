# Brief 064: register the static identity extension in the actual iOS app

## The ask
The user wants genuine Google, Apple and guest identity in the 4.0.0 game. Continue the native foundation only; the director found a defect that archive-only tests missed.

## Evidence
Round 062 has clean source-only harvesting. Its 64 Node tests pass independently. The director enabled both identity and IAP plugins in an ignored disposable full-game export fixture, imported it, ran the real `scripts/ios.mjs export`, then built the exported full Godot app for arm64/iphoneos with Xcode Debug and signing disabled. Export and app build both succeed, with the nine Firebase static frameworks and six privacy resource bundles.

But `xcrun nm -gj <built-app>/MoonlitBeacon` has **no `moonlit_identity_ios_entry` symbol**, while the input archive has it. The generated `MoonlitBeacon/dummy.cpp` contains only the empty Godot plugin initialization functions and no identity entry reference/registration. The source descriptor is `.gdextension.ios`; adding its bytes to the PCK via `add_file` does not make the normal GDExtension exporter discover the static entry. Linking an archive and checking that archive's symbols is insufficient: the actual game cannot resolve the native extension.

The locked real engine archive exports `register_dynamic_symbol(char *, void *)` (`__Z23register_dynamic_symbolPcPv`). Official upstream sources at `drivers/apple_embedded/os_apple_embedded.mm` show `.a` loading via `RTLD_SELF`, then a `dynamic_symbol_lookup_table` lookup; `add_apple_embedded_platform_init_callback` also exists. Export plugin C++ injection is `add_apple_embedded_platform_cpp_code` (legacy iOS hook fallback available). These are primary-source clues, not a mandate to use an unsafe static initialization order.

## Do
- Make the iOS export hook emit the exact C++ registration/reference needed by this engine, or use the normal static-extension export path safely. Preserve desktop non-loading and composed IAP + identity extension lists. Keep the entry retained in the final app and registered before engine extension lookup, without calling its GDExtension initialization before the engine supplies the real interface.
- Avoid reliance on C++ global initialization order of the engine's String/hash map. Use the engine's supported initialization stage. Keep the exported cpp snippet self-contained; exported projects have no engine source headers.
- Add meaningful tests around emitted registration, entry retention, supported hook fallback and extension-list coexistence; report a reproducible full-app export/link inspection procedure. Archive verification remains useful but must not pretend it proves app registration.
- Keep build products ignored and on disk; this is a narrow source correction, no SDK rebuild necessary unless C++ bridge source truly changes.

## Do not
No native provider expansion (brief 058 will own that), PlayerAccount changes, UI/gameplay/cloud/art/shared runner/package/project settings, vendor rebuilds, signing/store/device/network/history, SDK privacy byte modifications, or unrelated scope. Preserve the reviewed minimal IAP composition hunk.

## Acceptance
Native Node and Godot identity suites remain green. The director repeats a genuine full-game export and arm64 Xcode build; generated C++ registers the correct entry at the supported engine stage, the final executable retains that entry, both extension-list rows and all six original SDK privacy manifests survive. Removing the entry reference or registration must fail a targeted test. Source-only `muse diff --names` stays clean.

## Deliverables
Native addon export/manifest helpers, their tests and native setup/README instructions only, under the already-owned foundation paths. No built archives, AARs, frameworks or copied SDK headers in the patch.
