# godot-iap Android runtime

`apps/game/addons/godot-iap/android/GodotIap.{debug,release}.aar` are taken
byte-for-byte from the official
[`godot-iap-3.5.1`](https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.5.1)
release ZIP.

- upstream tag commit: `acb7924d6512cdf87a6a51d22bf75cb285f76dc9`
- official release ZIP SHA-256: `30ec3a2e149644b3fa6c51f2d6f66c180e024388b317ff6ed35000bb88ab6c7c`

Verified SHA-256 — official 3.5.1 debug and release AARs are identical:

- official debug AAR: `3b19b3f8d9839b6e1596b3fbdf7a262ed54acda5983a43e17a85cb142aa4e34a`
- official release AAR: `3b19b3f8d9839b6e1596b3fbdf7a262ed54acda5983a43e17a85cb142aa4e34a`

`GodotIap.gdap` remote dependencies ship with 3.5.1 as
`io.github.hyochan.openiap:openiap-google:3.5.2`.

Play AAB export bumps the generated Godot Gradle template from AGP 8.6.1 to
8.9.1. `openiap-google:3.5.2` depends on `androidx.core:1.18.0`, which needs
that plugin version, and Godot 4.7.1 already ships Gradle 8.11.1.
Direct-distribution APKs do not pull the Maven artifact.

`apps/game/scripts/iap/godot_iap_3_compat.gd` still reads the result envelope
and the Android `restorePurchases()` result. Purchase requests go through the
official 3.x `request_purchase()`. A normal async `null` is allowed; only a
synchronous `purchase_error` during the call counts as dispatch failure.

The license is MIT, kept at `apps/game/addons/godot-iap/LICENSE`.
