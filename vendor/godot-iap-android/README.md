# godot-iap Android runtime

`apps/game/addons/godot-iap/android/GodotIap.{debug,release}.aar` are taken
byte-for-byte from the official
[`godot-iap-3.6.1`](https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.6.1)
release ZIP; 3.6.1 ships the same bytes as 3.5.1.

- upstream tag commit: `c1a3658e12a0bb7de6fdcfb40f0d82df9f68a653`
- official release ZIP SHA-256: `6aa51a9c4d195e9537b42ec4f4ecbbf637e254442aa2641d415246f3e8dc7cf9`

Verified SHA-256 — official 3.6.1 debug and release AARs are identical:

- official debug AAR: `3b19b3f8d9839b6e1596b3fbdf7a262ed54acda5983a43e17a85cb142aa4e34a`
- official release AAR: `3b19b3f8d9839b6e1596b3fbdf7a262ed54acda5983a43e17a85cb142aa4e34a`

`GodotIap.gdap` remote dependencies ship with 3.6.1 as
`io.github.hyochan.openiap:openiap-google:3.6.1`.

godot-iap 3.6 adds the `openiap/android_store` export option. Its default,
`auto`, links the store of the one connected device in a debug export, so the
`Android Play` preset pins `play`.

Play AAB export bumps the generated Godot Gradle template from AGP 8.6.1 to
8.9.1. `openiap-google:3.6.1` depends on `androidx.core:1.18.0`, which needs
that plugin version, and Godot 4.7.1 already ships Gradle 8.11.1.
Direct-distribution APKs do not pull the Maven artifact.

Purchase queries and restore go through the public
`get_available_purchases_result()` and `restore_purchases()`, so a failed query
is never read as an empty list. Purchase requests go through the official 3.x
`request_purchase()`. A normal async `null` is allowed; only a
synchronous `purchase_error` during the call counts as dispatch failure.

The license is MIT, kept at `apps/game/addons/godot-iap/LICENSE`.
