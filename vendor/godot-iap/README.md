# godot-iap 3.6.1 Moonlit integration patch

`apps/game/addons/godot-iap/` is the official
[`godot-iap-3.6.1`](https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.6.1)
release plus three small patches.

- upstream tag commit: `c1a3658e12a0bb7de6fdcfb40f0d82df9f68a653`
- official release ZIP SHA-256: `6aa51a9c4d195e9537b42ec4f4ecbbf637e254442aa2641d415246f3e8dc7cf9`
- Moonlit patch: [`0001-moonlit-integration.patch`](0001-moonlit-integration.patch)
- patch SHA-256: `f83b01ff8eba05de4873c3c50fb81b2ffeb53892f1111df834ce465f9e10cedd`

To check a zip before vendoring it, compare its SHA-256 with the release asset
digest and verify the build attestation:

```bash
gh release view godot-iap-3.6.1 --repo hyodotdev/openiap --json assets
gh attestation verify godot-iap-3.6.1.zip --repo hyodotdev/openiap
```

## File provenance

| File | Official 3.6.1 SHA-256 | Moonlit SHA-256 |
| --- | --- | --- |
| `godot_iap.gd` | `2bf54bbf119886a607ea1deb2897e9d28de27ca01c7b4f7ca6daebe3a1188bfe` | `e31fdf59e230b7f677c2513a8f6323240a794382ddedf92cde771a93cf3c899d` |
| `godot_iap_plugin.gd` | `31500d82ee2ed4b78e42fcbc1dd8c28ad5d97419df18b29a72b08bd83bea9ab8` | `052e86d6a4a688ecb93e6d9f385014a985ac892685fb9c4e1fbfa2da850c6110` |

Every other file is the official file, unmodified:

- `types.gd`: `d14c4b108c8af4f5b0b42203706fe83ada10d173e6c862c18e77bb2d69fc7970`
- `android_store.gd`: `1b9d4b80e70c2a93811c0fe973aab21b4f2149f0d391f2ca6971ecb603f43ffd`
- `scripts/fix_ios_embed.sh`: `1606332b07dcf2aa2b77ae266e476414a62423ce8769368122a52672002d938e`
- `android/GodotIap.gdap`: `b776033d531bb439ca85c69d079f4ca0f82ad2cacd35065318248349492ac806`

`pnpm test:godot-iap-vendor` checks these hashes and that the patch reverses
to the official bytes. `types.gd` declares an `IapStore` enum, and an autoload
with that name stops its `var store: IapStore` fields from parsing, so the
game's shop autoload is `Shop`.

## Patches kept

- **Restore timeout** (`godot_iap.gd`): an explicit iOS restore waits up to
  600 seconds instead of 120. `AppStore.sync()` can show Face ID, password, or
  account sheets, and two pauses there outlast 120 seconds, which left the app
  showing a failed restore while the system sheet was still open. Upstream
  3.6.1 still uses 120 seconds.
- **iOS descriptor export** (`godot_iap_plugin.gd`): the iOS-only descriptor is
  stored as `vendor/godot-iap-ios/bin/godot_iap.gdextension.ios`, and the
  export plugin writes it into the PCK under the live `.gdextension` name.
  Godot 4.3 to 4.7 cannot skip an iOS-only descriptor on desktop
  ([godotengine/godot#105615](https://github.com/godotengine/godot/issues/105615)),
  so a live copy under `res://` makes every editor and headless run log
  `No GDExtension library found for current OS and architecture`, and
  `pnpm game:check` must stay error-free.
- **Shared iOS extension list** (`godot_iap_plugin.gd`): the `extension_list.cfg`
  write goes through the MoonlitIdentity `ExtensionListComposer`, so the
  purchase extension stays registered alongside the identity extension no
  matter which export plugin writes last. Nothing else in that file changed.

## Patches dropped

- `fix_ios_embed.sh` preferring `/usr/bin/python3` and failing when framework
  references are missing: both are upstream since 3.5.2.
- The direct-distribution guard in `_ready()`: the itch.io APK ships without
  the Android plugin and `Shop.storefront_enabled()` keeps the store off there,
  so without the guard the wrapper only prints that no native plugin was found.

## Game-side changes for 3.6

- Release exports leave `res://iapkit.cfg` out of the bundle; godot-iap
  reserves that file for local settings. Store exports write the IAPKit
  publishable key to `res://iapkit_publishable.cfg` instead.
- The `Android Play` preset pins `openiap/android_store="play"`. The default,
  `auto`, links the store of the one connected device in a debug export.
