# godot-iap iOS runtime

iOS frameworks and the descriptor come from the official
`godot-iap-3.5.1` release. All three files match the official ZIP
byte-for-byte.

- release: <https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.5.1>
- ZIP SHA-256: `30ec3a2e149644b3fa6c51f2d6f66c180e024388b317ff6ed35000bb88ab6c7c`
- license: MIT (`LICENSE`)

Verified stored-file SHA-256:

- official iOS-only descriptor `godot_iap.gdextension` renamed to
  `godot_iap.gdextension.ios`:
  `17ceb8eea0298265e8a7569c16ed1ae725d75c07ca6ca3411462ede1045d128c`
- official `GodotIap.framework/GodotIap`:
  `0e9914201189d1409ad294228986b6751e1f4cb9a2bdd2192b98da8852214dd9`
- official `SwiftGodotRuntime.framework/SwiftGodotRuntime`:
  `89a1f9306992f6b83be0432c9bdec83454d6cf1393e19b6f4c2b2422bd9253b3`

Leaving the iOS-only `.gdextension` live under `res://` makes the desktop
editor look for a host-platform library and error. The official 3.5.1
descriptor already uses `include_tags = ["ios"]` and only declares the iOS
framework, so the contents stay unmodified and only the `.ios` suffix is
added. `scripts/ios.mjs` copies this `bin/` into
`apps/game/addons/godot-iap/bin/` for the iOS export window, and the export
plugin restores the live `.gdextension` name plus the extension list inside
the PCK. After the frameworks are added to Xcode Embed Frameworks, the
temporary `bin/` is removed again.

The GDScript wrapper is official 3.5.1 plus the Moonlit patch documented
in [`../godot-iap/README.md`](../godot-iap/README.md). Generic async calls keep
the 30-second limit; Moonlit Beacon patches only the 10-minute restore limit
and the direct-distribution guard. iOS query success envelopes are still read
by `apps/game/scripts/iap/godot_iap_3_compat.gd` so an authoritative empty
list is not confused with a native failure.
