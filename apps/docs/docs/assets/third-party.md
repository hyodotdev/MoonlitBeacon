# Third-party assets and licenses

This records every external asset this game uses and its license.
When you add an asset, update this document and the
[asset manifest](./manifest.md) together.

## Engine

| Item | Detail |
| --- | --- |
| Name | Godot Engine 4.7.1 |
| Author | Juan Linietsky, Ariel Manzur, Godot Engine contributors |
| License | MIT License |
| Link | https://godotengine.org |

Games made with Godot must include the engine's MIT license notice.
The credits screen (Lesson 15) and the itch.io page description provide
the full license text or a link.

## Store integration

| Item | Detail |
| --- | --- |
| Name | godot-iap 3.5.1 |
| Author | OpenIAP contributors |
| License | MIT License |
| Source | https://github.com/hyodotdev/openiap/releases/tag/godot-iap-3.5.1 |
| Scope | Product query, purchase, and restore for Android Play Billing and iOS StoreKit 2 |
| Status | ✅ in use (7 non-consumable items in the Moonlit Store) |

The plugin's original license is kept with `apps/game/addons/godot-iap/LICENSE`
and the iOS distribution `vendor/godot-iap-ios/LICENSE`. It is not an
external **art asset**, so it is not in the asset manifest.

The Android AAR is taken byte-for-byte from the official 3.5.1 release.
Provenance, hashes, and the small GDScript integration patch are recorded in
`vendor/godot-iap-android/README.md` and `vendor/godot-iap/README.md`.

## Graphics · music · SFX

| Item | Detail |
| --- | --- |
| Name | Ninja Adventure - Asset Pack |
| Author | Pixel-Boy, AAA |
| License | CC0 1.0 Universal (Public Domain Dedication) |
| Credit required | no (recommended) |
| Source | https://pixel-boy.itch.io/ninja-adventure-asset-pack |
| Scope | BGM and SFX only at runtime. Tilesets, UI, and VFX are kept for course compatibility and have no active visual references |
| Status | ✅ selected audio in use / visual files archived (71 files / about 11.3MB, excluding `.import`) |

## Input icons

| Item | Detail |
| --- | --- |
| Name | Input Prompts Pixel |
| Author | Kenney |
| License | CC0 1.0 Universal |
| Credit required | no (recommended) |
| Source | https://kenney.nl/assets/input-prompts-pixel |
| Scope | Touch stick, tap, and Back icons (control-guide screen). WASD and arrows are for development test hints |
| Status | ⬜ not in use (empty folder only. Credits do not list the icons either) |

## UI SFX

| Item | Detail |
| --- | --- |
| Name | UI Audio |
| Author | Kenney |
| License | CC0 1.0 Universal |
| Source | https://kenney.nl/assets/ui-audio |
| Scope | One title confirm sound (`ui_confirm.ogg`) |
| Status | ✅ in use (Lesson 1 title-screen confirm sound) |

## Collision · hit SFX

| Item | Detail |
| --- | --- |
| Name | Impact Sounds |
| Author | Kenney |
| License | CC0 1.0 Universal |
| Source | https://kenney.nl/assets/impact-sounds |
| Scope | Player hit, collision, guardian appear, beacon impact |
| Status | ⬜ not in use (unused through Lesson 16. Beacons and hits use Ninja Adventure sounds) |

## Fonts

| Item | Detail |
| --- | --- |
| Name | Nexon MapleStory Font (Light/Bold) + Noto Sans CJK SC |
| Author | Nexon Korea / Google, Adobe and Noto CJK contributors |
| License | MapleStory: free use (commercial and embedding allowed; sale and modification forbidden) · Noto: SIL Open Font License 1.1 |
| Credit required | yes (Nexon attribution + OFL notice) |
| Source | https://maplestory.nexon.com/Media/Font / https://github.com/notofonts/noto-cjk |
| Scope | All UI text. Noto is the CJK glyph and player-name fallback MapleStory lacks |
| Status | ✅ in use (MapleStory in shipping UI; `.tres` files keep the old Galmuri filenames) |

## Credits-screen copy

```text
Engine
  Godot Engine 4.7.1
  MIT License

Art and UI
  Moonlit Beacon
  Original assets

Music and sound
  Ninja Adventure Asset Pack
  Pixel-Boy and AAA
  CC0
  Kenney UI Audio
  Kenney
  CC0

Font
  Maplestory · ⓒ NEXON Korea
  Noto Sans CJK SC · Google
  SIL Open Font License 1.1

Store integration
  godot-iap 3.5.1
  OpenIAP contributors · MIT License

Made by
  Hyo Dev
```

In-game credits (`ROWS` in `credits_panel.gd`) and the itch.io page
(`notes/release/store-page.md`) must match this copy. **Edit all three
together.**

## License texts

Copies of the license texts live in `apps/game/docs/licenses/` and each
plugin distribution folder.
We keep the three texts used in Lesson 1 (`OFL-1.1.txt`, `CC0-1.0.txt`,
`GODOT-MIT.txt`) plus `NOTO-OFL-1.1.txt` added for shipping
internationalization.
Do not postpone license records, whichever lesson an asset enters in.
