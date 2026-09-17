# godot-iap 3.5.1 Moonlit integration patch

GDScript integration under `apps/game/addons/godot-iap/` starts from the official
[`godot-iap-3.5.1`](https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.5.1)
release and applies only Moonlit Beacon's verified safety boundaries.

- upstream tag commit: `acb7924d6512cdf87a6a51d22bf75cb285f76dc9`
- official release ZIP SHA-256: `30ec3a2e149644b3fa6c51f2d6f66c180e024388b317ff6ed35000bb88ab6c7c`
- Moonlit patch: [`0001-moonlit-integration.patch`](0001-moonlit-integration.patch)
- patch SHA-256: `afeb152265e5431233930237e5d4edc9c2042d9dfec00b4e0f7c09d251a649da`

## File provenance

| File | Official 3.5.1 SHA-256 | Moonlit SHA-256 |
| --- | --- | --- |
| `godot_iap.gd` | `d872fd1d34c9075b761ca6ba2ca90c8d513b8e7d8e94f1e9a96f3b9cf9e7c2cb` | `1bf74d123066a932b1cb7baf8fb3eb5c95c6d1166ff8bc6dfa923b0058bb2238` |
| `godot_iap_plugin.gd` | `e0eb26b046700c2de24c7800927e0444ecec46e9eeb474c0d3476d865cb0fba0` | `a3eaf879fb9f7b017133e2bffa52dc3e39fae5b44fb7332dbf047986a1c4a50b` |
| `scripts/fix_ios_embed.sh` | `2b6494b705ce1beb7e23e0e5cfc8d60eff852ea3b6ffb1c72579def15f041807` | `06e1f319396196146fcfa7db967e5a82cca4d2011ba5b2ccb6fd51daf2fca249` |

`types.gd` is **not** in that reverse-patch set. Official 3.5.1 annotates
three purchase fields as `var store: IapStore`. Moonlit's autoload is also
named `IapStore` (`res://scripts/iap/iap_store.gd`), so those annotations
do not parse. The vendored file uses `var store := IapStore.UNKNOWN` so
GDScript infers the local enum. That is a compile workaround only; do not
treat it as an upstream behavior change.

The patch keeps project-specific boundaries:

- Direct-distribution builds do not probe for a missing native store singleton
  (`OS.has_feature("direct_distribution")` guard).
- Explicit iOS restore uses the verified 10-minute timeout instead of the
  upstream 120-second default. `AppStore.sync()` can present Face ID, password,
  or account sheets; two pauses there blow past 120 seconds and leave the app
  UI failed while native auth continues.
- The iOS descriptor is stored as `.gdextension.ios` and only written into the
  PCK under the live `.gdextension` name during export.
- `fix_ios_embed.sh` prefers `/usr/bin/python3` on macOS and fails closed when
  GodotIap frameworks are missing from the Xcode project.
