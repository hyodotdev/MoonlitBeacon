# godot-iap iOS runtime

iOS frameworks and the descriptor come from the official
`godot-iap-3.6.1` release. All three files match the official ZIP
byte-for-byte; 3.6.1 ships the same bytes as 3.5.1.

- release: <https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.6.1>
- ZIP SHA-256: `6aa51a9c4d195e9537b42ec4f4ecbbf637e254442aa2641d415246f3e8dc7cf9`
- license: MIT (`LICENSE`)

Verified stored-file SHA-256:

- official iOS-only descriptor `godot_iap.gdextension` renamed to
  `godot_iap.gdextension.ios`:
  `17ceb8eea0298265e8a7569c16ed1ae725d75c07ca6ca3411462ede1045d128c`
- official `GodotIap.framework/GodotIap`:
  `0e9914201189d1409ad294228986b6751e1f4cb9a2bdd2192b98da8852214dd9`
- official `SwiftGodotRuntime.framework/SwiftGodotRuntime`:
  `89a1f9306992f6b83be0432c9bdec83454d6cf1393e19b6f4c2b2422bd9253b3`

The descriptor declares only the iOS framework, so a live `.gdextension`
under `res://` makes desktop Godot 4.7 log errors on every run. The contents
stay official; only the `.ios` suffix is added.

Every `pnpm ios:*` export (`scripts/ios.mjs`) copies this `bin/` into
`apps/game/addons/godot-iap/bin/` for the length of the export. The export
plugin writes the descriptor into the PCK under the live `.gdextension` name,
`fix_ios_embed.sh` adds both frameworks to Xcode's Embed Frameworks and prints
its `Runtime embed check` line, and the temporary `bin/` is removed again.

The GDScript wrapper is official 3.6.1 plus the patch documented in
[`../godot-iap/README.md`](../godot-iap/README.md).
