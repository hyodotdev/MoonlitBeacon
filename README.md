# Moonlit Beacon

> A 2D top-down survivor. Light the beacons in forest, field, and camp, then
> grow three weapon paths from spirit embers and relics and take on the
> guardians — and the next, harder cycle.

![Moonlit Beacon title screen](docs/screenshots/04-title.png)

| Moonlight barrage | Storm Fieldwing |
| --- | --- |
| ![Late-game missile volley](docs/screenshots/01-moonlight-barrage.png) | ![Guardian boss fight](docs/screenshots/02-field-guardian.png) |

This repository is **open source (MIT)** and has one purpose: a real game
you can play, and the course that builds it, in the same place. It is a
**shipping Godot 4.7 game** on Google Play and the App Store, a 16-lesson
course that follows the official Godot intro sequence without cloning
`Dodge the Creeps!`, and a public example of
[godot-iap](https://github.com/hyodotdev/openiap/tree/main/libraries/godot-iap)
with [IAPKit](https://kit.openiap.dev) purchase verification.

Clone it, run it, read the course alongside the code it produced, and send
improvements back: contributions are welcome
([CONTRIBUTING.md](CONTRIBUTING.md)).

Docs site: **https://hyodotdev.github.io/MoonlitBeacon/**
(auto-deploys when `apps/docs/` changes land on `main`)

| | |
| --- | --- |
| Engine | Godot **4.7.1 Standard**, GDScript, Compatibility renderer |
| Internal resolution | **808 × 360** landscape (`orientation=4`) |
| Stretch | `canvas_items` + `expand`, nearest-neighbor filter |
| Reference device | Pixel 10 — 2424 × 1080 landscape, arm64-v8a |
| Controls | Full-screen floating move stick, auto-attack, dash button |
| IAP | **godot-iap 3.6.1** + IAPKit (publishable key at export time) |
| Application id | `com.crossplatformkorea.moonlitbeacon` |
| Version | **3.0.0** (Android code 15, iOS build 10; last recorded store release 2.1.0) |
| License | MIT code; third-party assets keep their own ([notices](THIRD_PARTY_NOTICES.md)) |

808 × 360 is exactly one third of the Pixel 10 landscape panel, so 16 px pixel
art scales by an integer 3×. Aspect is `expand`, not `keep`, so extra width
becomes extra view instead of letterbox.

Windows / Web are out of the current ship scope. Desktop runs are for
development. `pointing/emulate_touch_from_mouse=true` lets the virtual stick
work with a mouse.

## Using this as a reference

Moonlit Beacon is a shipping example of
[godot-iap](https://openiap.dev/docs/setup/godot) **3.6.1** with
[IAPKit](https://kit.openiap.dev) purchase verification. It sells one-time
products and consumables on the App Store and Google Play. There are no
subscriptions.

What the code shows:

- Fetch products, purchase, verify the receipt with IAPKit, then finish the
  transaction (permanent unlocks) or consume it (continue coins) only after
  the entitlement is saved.
- Restore purchases, re-sync when the app resumes, and take back only a
  purchase the store and IAPKit report as refunded or revoked.
- Read purchases with `get_available_purchases_result()`, so a failed store
  query is never mistaken for "no purchases".

Start with `apps/game/scripts/iap/iap_store.gd` (the `Shop` autoload: catalog,
ledger, restore, refunds) and `godot_iap_backend.gd`, the only file that calls
godot-iap.

To run purchases in your own copy, change:

1. **Application id.** `com.crossplatformkorea.moonlitbeacon` is this game's
   store identity. Replace it everywhere (`git grep` finds each place);
   product IDs are built from `APP_ID` in `iap_store.gd`.
2. **Signing and team.** Store builds need your own Android upload keystore
   (`GODOT_ANDROID_KEYSTORE_RELEASE_*` in [`.env.example`](.env.example)).
   iOS builds sign with `MOONLIT_APPLE_TEAM_ID`, which defaults to this
   project's team.
3. **Store products.** Create the SKUs listed in
   [Monetize](apps/docs/docs/monetize.md) in App Store Connect and Play
   Console, or change the catalog in `iap_store.gd`.
4. **IAPKit key.** Set `IAPKIT_API_KEY` to your project's `openiap-kit_pk_…`
   publishable key; never ship an `openiap-kit_sk_…` key. Store exports write
   it to `apps/game/iapkit_publishable.cfg` and delete the file afterwards.
   Do not use `res://iapkit.cfg`: godot-iap 3.6 leaves it out of release
   exports.

How the pieces fit:

- `apps/game/addons/godot-iap/` is the official 3.6.1 addon plus two small
  patches, documented in [`vendor/godot-iap/README.md`](vendor/godot-iap/README.md).
  `pnpm test:godot-iap-vendor` checks them against the release.
- The iOS frameworks live in `vendor/godot-iap-ios/bin/`, outside `res://`,
  because desktop Godot 4.7 logs errors for an iOS-only extension. Every
  `pnpm ios:*` export copies them into the addon, puts the descriptor in the
  PCK, runs `fix_ios_embed.sh` to embed the frameworks in Xcode, and removes
  the copy again.
- The direct-distribution APK (itch.io) has no store SDK: `pnpm android:build`
  moves the Android plugin aside, and the `direct_distribution` feature keeps
  the shop off.

See also [Monetize](apps/docs/docs/monetize.md) and
[IAP store setup](notes/release/iap-store-setup.md).

## Layout

```text
MoonlitBeacon/
  docs/              # maintainer art/audit notes (not the published site)
  apps/
    game/            # Godot project (res://)
    docs/            # Docusaurus (GitHub Pages)
      docs/          # reference
      course/        # Lesson 1 … Lesson 16
  notes/             # maintainer plans, scripts, capture pipeline
  vendor/godot-iap*  # official zip provenance + Moonlit patch
  stores/            # store listing images
  _downloads/        # original asset ZIPs (gitignored)
  _asset_sources/    # unpacked originals (gitignored)
  builds/            # export and capture output (gitignored)
```

Original asset packs stay outside `res://`. Only the files the game uses are
copied into `apps/game/assets/third_party/` and listed in the
[asset manifest](apps/docs/docs/assets/manifest.md).

## Run the game

1. Install [Godot 4.7.1 Standard](https://godotengine.org/download).
2. Clone this repository.
3. Follow the [asset download guide](apps/docs/docs/assets/download-guide.md)
   if you are rebuilding art from upstream packs. The in-tree `assets/` copy is
   already the used subset.
4. Open `apps/game/project.godot`.

```bash
pnpm game          # run
pnpm game:editor   # editor
pnpm game:check    # headless open/quit
pnpm verify        # CI-equivalent checks
```

`scripts/godot.mjs` finds Godot on PATH or in common install locations.
Set `GODOT_BIN` if it cannot.

## Android

```bash
pnpm android:build
pnpm android:run
```

Do not call `godot --export-debug "Android"` yourself. `android:build`
installs the export template, isolates Play Billing from the direct-distribution
APK, and cleans Gradle leftovers.

`am start -n …/com.godot.game.GodotApp` fails (`exported=false`).
`android:run` launches with `monkey` against
`com.crossplatformkorea.moonlitbeacon`.

| | |
| --- | --- |
| Application id | `com.crossplatformkorea.moonlitbeacon` |
| Arch | arm64-v8a |
| Preset | `Android` in `apps/game/export_presets.cfg` |

`pnpm android:bundle` writes a Play AAB with Billing + IAPKit. The key comes
from `IAPKIT_API_KEY` or the macOS Keychain. The generated `iapkit.cfg` is
deleted after export and is gitignored.

## iOS

Physical devices only. The Godot 4.7.1 iOS template has no arm64 simulator
slice, and Apple Silicon simulator OpenGL ES is broken on current runtimes.

```bash
pnpm ios:devices
pnpm ios:run
```

## Docs site

Node 20+ and pnpm:

```bash
pnpm install
pnpm docs:dev
pnpm docs:build
```

| Doc | |
| --- | --- |
| [Intro](apps/docs/docs/intro.md) | overview and how to run |
| [The game](apps/docs/docs/game.md) | scope, rules, scoring |
| [Assets](apps/docs/docs/assets/download-guide.md) | download and license check |
| [Third-party](apps/docs/docs/assets/third-party.md) | art, audio, godot-iap |
| [Monetize](apps/docs/docs/monetize.md) | IAP products and verification |

License text copies live in
[`apps/game/docs/licenses/`](apps/game/docs/licenses/).

## Lessons

Course pages: [`apps/docs/course/`](apps/docs/course/).
Maintainer plans, recording scripts, and the capture pipeline stay in
[`notes/`](notes/) and are not published on the docs site.

Each lesson ships function, art, sound, and UI together so a paused lesson
still looks like a store screenshot.

| Lesson | You learn | On screen |
| --- | --- | --- |
| 1 | Project setup, assets, title | Night-forest diorama, title, tap-to-start |
| 2 | Nodes and scenes | One beacon burning in the clearing |
| 3 | Instances | Three beacons in the arena |
| 4 | First script | Beacons ignite in sequence |
| 5 | Player scene | Four-direction idle |
| 6 | Input | Floating stick walk |
| 7 | Signals | 1.3 s ignite ring |
| 8 | Enemies | Forest spirits chase |
| 9 | Main loop | Moon gate and victory |
| 10 | HUD | Hearts, time, beacons |
| 11 | 0.1.0 on device | Playable on Pixel 10 |
| 12 | Dash | Dash button and afterimage |
| 13 | Three spirits + guardian | Music swap, guardian entrance |
| 14 | Score and ranks | Result panel |
| 15 | Settings, locales, credits | Live language switch |
| 16 | QA and 1.0.0 | Signed APK path |

The course stops at 1.0.0. The tutorial closed with 2.1.0, and the tree now carries the 3.0.0 renewal.

## Credits

```text
Engine
  Godot Engine 4.7.1 — MIT License

Art and UI
  Moonlit Beacon — Original assets

Music and sound
  Ninja Adventure Asset Pack — Pixel-Boy and AAA — CC0
  Kenney UI Audio — Kenney — CC0

Font
  Maplestory — ⓒ NEXON Korea
  Noto Sans CJK SC — Google — SIL Open Font License 1.1

Store SDK
  godot-iap 3.6.1 — OpenIAP contributors — MIT License

Made by
  Hyo Dev
```

Game code is [MIT](LICENSE). Third-party assets keep their own licenses; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the
[third-party assets](apps/docs/docs/assets/third-party.md) list.
Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).
