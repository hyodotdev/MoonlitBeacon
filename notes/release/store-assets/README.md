# Store graphics

Release originals built from the app icon and custom art for six heroes.
Size and transparency contracts are locked so they can be uploaded to Google
Play and IAPKit as-is.

The new app icon is the final Moonlit Warden design in
`source/app-icon-approved.png`. Android splits use
`source/app-icon-night-crescent.png` and `source/app-icon-warden-moonlight.png`.
The round hood, gold crescent, and glowing beacon flame must read together
even at a small launcher size.
iOS uses `apps/game/assets/custom/ui/app_icon_master.png`; Android uses the
three legacy/adaptive files made from the same source.

| File | Use | Contract |
| --- | --- | --- |
| `play/icon-512.png` | Google Play app icon | 512×512, opaque PNG |
| `play/feature-graphic-1024x500.png` | Google Play feature graphic | 1024×500, 24-bit RGB PNG |
| `iap/moonlit-supporter-512.png` | Moonlit Supporter | 512×512, opaque PNG |
| `iap/hero-dancer-512.png` | Shadow Dancer individual unlock | 512×512, opaque PNG |
| `iap/hero-keeper-512.png` | Beacon Keeper individual unlock | 512×512, opaque PNG |
| `iap/hero-knight-512.png` | Silver Moon Knight individual unlock | 512×512, opaque PNG |
| `iap/hero-eclipse-512.png` | Eclipse Mage individual unlock | 512×512, opaque PNG |
| `iap/hero-sage-512.png` | Constellation Sage individual unlock | 512×512, opaque PNG |
| `iap/lantern-colors-512.png` | Lantern Colors | 512×512, opaque PNG |
| `iap/hero-bundle-512.png` | Legacy hero-bundle archive · do not upload new | 512×512, opaque PNG |

The app icon uses the new 1024px master. The feature graphic and existing IAP
images keep the existing locked shapes and the six hero portraits in
`assets/custom/actors/heroes/` to avoid changing the submission set.
Generation/edit sources and split originals for the new icon are kept together
in `source/` above.

The ten files above are tracked by the repo. New operational uploads manage
only 2 app graphics and 7 sale-product graphics. `hero-bundle-512.png` is an
archive for past-purchase restore copy and deterministic-generation
compatibility; do not upload it newly to Google Play, App Store Connect, or
IAPKit. Whether generator and result always match is checked with:

```bash
pnpm store:graphics
pnpm check:store-graphics
```

## Play and App Store screenshots

`screenshots.json` selects only six on-device captures that show the title and
the current 2-head-tall heroes. Combat captures have test controls and a
performance HUD at the bottom, so that bottom strip is cropped.
Do not overpaint game pixels or composite a scene. Remaining real screen keeps
aspect ratio and sits inside a per-store night-sky marketing frame. The game
screen is not stretched; title and brand marks are drawn only in the margin
outside real UI.

Default release reuses already-uploaded screenshots as-is. Run the full
capture below only when layout, art, visible copy, or composition has fully
changed versus the existing images. Version/build, non-visual code, IAP
wiring/purchase verification, price/product registration, and
fingerprint/provenance check failure are not recapture reasons. If only a new
IAP review image is needed, add only the new product file and keep existing
marketing screens and existing product images byte-identical.

```bash
pnpm store:capture-screenshots
pnpm store:capture-ios-device -- --target ipad-13 --all-locales
pnpm store:screenshots:play
pnpm store:screenshots:app-store:android-pixel-avd
pnpm check:store-screenshots:play
pnpm check:store-screenshots:app-store
```

The default iPhone source mode of `store:screenshots:app-store` is
`physical-ios`, so use it only when physical iPhone and iPad proofs both
exist. Releases without a physical iPhone must use the
`android-pixel-avd` command above **explicitly**. That mode is a marketing
composite of Pixel 10 AVD's 2424×1080 Android runtime into the iPhone 6.5
submission size, aspect preserved; it is not labeled as a physical iPhone
capture. The iPad set still uses only physical `ipad-13` sources.

| Output folder | Count and contract |
| --- | --- |
| `builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/screenshots/` | 6 phone shots per locale, 1920×1080 |
| `builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/seven-inch-tablet/` | 6 seven-inch tablet shots per locale, 1920×1080 (16:9) |
| `builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/ten-inch-tablet/` | 6 ten-inch tablet shots per locale, 2560×1440 (16:9) |
| `builds/release/app-store/en-US/iphone-6.5/` | 6 shots, 2778×1284 |
| `builds/release/app-store/en-US/ipad-13/` | 6 shots, 2732×2048 |
| `builds/release/app-store/{ko,ja,zh-Hans,zh-Hant}/iphone-6.5/` | 6 shots per language, 2778×1284 |
| `builds/release/app-store/{ko,ja,zh-Hans,zh-Hant}/ipad-13/` | 6 shots per language, 2732×2048 |
| `builds/release/app-store/iap-review/*.png` | 10 review screens, one per sale IAP, each 2778×1284 |
| `builds/release/app-store/screenshot-provenance.json` | iPhone/iPad source mode, capture report, 1:1 SHA-256 proof of 60 source→output images |

The feature graphic and every screenshot are encoded as PNG color type 2,
8-bit/channel, 24-bit RGB so App Store and Google Play do not mistake them
for alpha. App and IAP icons are RGBA PNGs with no transparent pixels.
Outputs are build products and are not tracked by the repo.

iPad 13" places the physical iPad framebuffer with aspect preserved and uses
only a dark, strongly blurred background from the same iPad source in empty
areas. Play 7-inch and 10-inch sets are the official large-screen 16:9 spec:
the full Android source shot on Pixel 10 sits centered with no distortion or
crop, and only a neutral dark extension of that same Android source fills
empty area. No extra device frame or marketing copy, and iPad outputs are not
reused. The sharp front screen shows the full UI at the same ratio; letters
and UI in the background cannot be read.

### 5-locale real-UI strategy

The first submission set uses current 2-head-tall hero runtime screens
reshoot on a 2424×1080 AVD matching Pixel 10. The first three shots
reproduced real late-game barrage, region Guardian, and hit missile drop on
a debug build; only the bottom test buttons and performance meter are removed
with `crop_bottom`. en/ko/ja/zh_CN/zh_TW are actually chosen on the settings
screen, then the saved `settings.cfg` is reread to confirm the switch.
English, Korean, Japanese, Simplified Chinese, and Traditional Chinese sets
each use a different real UI source, and marketing titles in the same
language sit in the frame outside real UI. Do not overpaint a translation
onto original UI.

Capture automation records SHA-256 of 30 per-locale game sources and 10
Korean IAP review sources per sale SKU, saved locale, product ID, debug-UI
hide completion proof, and UI/translation/font input hashes in
`builds/shots/store-localized/capture-report.json`. Title and combat grab the
full source only after a completion file confirms TestLauncher, ArenaTools,
and FrameMeter on the debug APK are hidden. Release export turns this
handshake process off and removes debug nodes. Right after the build, APK
hash and the same input hashes are bound as
`capture-build-attestation.json` and compared again on `--skip-build` partial
captures and when writing the final report. The actually installed debug APK
is first copied byte-identical as `capture-debug.apk` in the same folder, so
later `android:release` overwriting the canonical APK does not change capture
evidence. The generator fails on source size other than 2424×1080, non-unique
paths/hashes, UI changes after the preserved APK/capture, and missing glyphs
in the CJK marketing font.

App Store generation verifies 60 shots, 10 IAP shots, and
`screenshot-provenance.json` in one staging tree, then atomically replaces
the whole directory. It does not copy fallback iPhone sources into
`builds/shots/store-platform/ios/iphone-6.5/`, and if that physical source
and a fallback exist at the same time it fails as an ambiguous origin.
The check command takes no source-mode argument and recompares the published
provenance's exact mode against current source, proof, and output hashes.

```json
{
  "localized_sources": {
    "en-US": "builds/shots/store-localized/en-US/04-title.png",
    "ko-KR": "builds/shots/store-localized/ko-KR/04-title.png",
    "ja-JP": "builds/shots/store-localized/ja-JP/04-title.png",
    "zh-Hans": "builds/shots/store-localized/zh-Hans/04-title.png",
    "zh-Hant": "builds/shots/store-localized/zh-Hant/04-title.png"
  }
}
```

Google Play console locales are `en-US/ko-KR/ja-JP/zh-CN/zh-TW`; App Store
Connect locales are `en-US/ko/ja/zh-Hans/zh-Hant`. The generator makes folders
with this mapping and deletes old `play/screenshots`, `app-store/ko-KR`, and
`app-store/ja-JP` folders. Check mode fails if those old folders remain,
treating them as upload-target confusion.

IAP review sources are reshot by the same automation opening the current
debug APK's real `IapShopPanel` in Korean. It moves the real horizontal
`ScrollContainer` to each product position and makes 10 shots where the
product card, product name, buy button, and always-visible restore button are
identifiable. The 7 permanent-product shots also show that card's hero or
cosmetic preview; the 3 consumable-coin shots use a real shop screen where
the coin card's grant count and buy button can be read. On a direct-
distribution debug APK it leaves the real `device store only` price and
App Store/Google Play notices as-is, shows buy/restore copy, and proves both
buttons are disabled. Capture code does not synthesize price or purchase
possibility. It 1:1 matches `capture-report.json` `product_id` to the final
file, and fails if legacy `hero_bundle` or the old shared `iap-review.png`
exists. These review images are not uploaded to the marketing gallery.

Replace affected locale sets only when the actual screen of an existing
console upload has fully changed versus the current app. For new locales or
new IAPs that had no review material, add only the needed files and leave
existing sets that still match the current screen.
