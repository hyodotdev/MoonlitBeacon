# Release

Build a signed release APK and upload it to itch.io. Used in **Lesson 16**.

## Usage

```text
/release 0.1.0        intermediate complete (Lesson 11)
/release 1.0.0        full release (Lesson 16)
/release --dry-run    build and verify only, no upload
```

---

## Guards before you start

**Do not ship if any P0 or P1 bug remains.**
Finish the [release checklist](../../notes/release/checklist.md) first.

```text
P0: cannot launch, save corruption, cannot progress
P1: cycle progress · defeat · results · restart failures
```

**Upload only after user confirmation.** itch.io is a public distribution.
Even if you take a build down, it stays with people who already downloaded it.

---

## 1. Align the version

Align **seven keys** together: shared config plus the three per-platform
presets. If even one display version is off, store and game screen show
different versions; skip a build number and App Store Connect or Play Console
rejects the upload.

| Location | Key |
| --- | --- |
| `apps/game/project.godot` | `config/version` |
| `apps/game/export_presets.cfg` · `Android` | `version/name` |
| `apps/game/export_presets.cfg` · `Android` | `version/code` (integer, +1 every release) |
| `apps/game/export_presets.cfg` · `iOS` | `application/short_version` |
| `apps/game/export_presets.cfg` · `iOS` | `application/version` (build number, increases every release) |
| `apps/game/export_presets.cfg` · `Android Play` | `version/name` |
| `apps/game/export_presets.cfg` · `Android Play` | `version/code` (integer, +1 every release) |

```bash
grep -n 'config/version' apps/game/project.godot
grep -nE '^(version/(code|name)|application/(short_version|version))=' \
  apps/game/export_presets.cfg
```

The title-screen version string is read from `ProjectSettings`, so editing
`project.godot` alone updates the screen too.

## 2. Full check

```bash
/verify
```

Confirm game exit code 0, docs build pass, and all 10 `project.godot` values.

## 3. Build the release APK

```bash
pnpm android:release
```

When every check finishes, the script writes
`builds/android/MoonlitBeacon-<version>.apk` identical to the canonical APK.
If build, signing, or cleanup fails, it deletes both files so you cannot
mistake a previous success for this release.

:::danger `--export-release` needs a release keystore
A debug build (`--export-debug`) auto-signs with the debug keystore;
release needs a **keystore you made**. Without it, export fails.

Keep the keystore file outside the repo and restrict permissions to `600`
or tighter. In this project's macOS dev environment,
`scripts/android-build.mjs` reads a dedicated signing folder outside the
repo plus Keychain items, and passes them only as Godot
`GODOT_ANDROID_KEYSTORE_RELEASE_*` environment variables.
In other environments, set the same three environment variables yourself.
The script also checks that the signer certificate is currently valid and
valid past Google Play's required date of 22 October 2033
([Android app signing requirements](https://developer.android.com/studio/publish/app-signing)).

Configuring signing in the Godot editor can create
`.godot/export_credentials.cfg`.
**Never commit this file.** `.gitignore`'s `.godot/` blocks it.
:::

Always use the `android:release` script. It installs and cleans the Gradle
template and moves the GodotIap Android plugin out of the project during
export so the itch.io direct-distribution build does not pick up Play Billing
permissions or SDK. Calling `godot --export-release` yourself bypasses that
channel-split procedure.

## 4. Verify the signature

```bash
MOONLIT_ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"

# Signature is attached
"$MOONLIT_ANDROID_SDK/build-tools/36.0.0/apksigner" verify --verbose builds/android/MoonlitBeacon-<version>.apk

# Not signed with the debug key — if the output contains "CN=Android Debug" it is not a release
"$MOONLIT_ANDROID_SDK/build-tools/36.0.0/apksigner" verify --print-certs builds/android/MoonlitBeacon-<version>.apk | grep -i "Subject\|Issuer"
```

## 5. Final device check

```bash
adb uninstall com.crossplatformkorea.moonlitbeacon
adb install builds/android/MoonlitBeacon-<version>.apk
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1
```

**Confirm on a clean install.** Overlaying without wiping the debug build is
rejected because the signature differs, and leftover save files hide the
first-run path.

- [ ] Launches from the home-screen icon
- [ ] Locks to landscape
- [ ] 3 beacons → guardian → loot → next cycle continues
- [ ] Defeat → results → leaderboard or restart continues
- [ ] No debug strings on screen
- [ ] Version string is correct

## 6. Store materials

What goes on the store:

| Item | Spec |
| --- | --- |
| Google Play screenshots | `builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/screenshots/`, 1920×1080 per language, 6 shots |
| Google Play 7-inch tablet | `builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/seven-inch-tablet/`, 1920×1080 (16:9) per language, 6 shots |
| Google Play 10-inch tablet | `builds/release/play/{en-US,ko-KR,ja-JP,zh-CN,zh-TW}/ten-inch-tablet/`, 2560×1440 (16:9) per language, 6 shots |
| App Store iPhone | `builds/release/app-store/{en-US,ko,ja,zh-Hans,zh-Hant}/iphone-6.5/`, 2778×1284 per language, 6 shots |
| App Store iPad | `builds/release/app-store/{en-US,ko,ja,zh-Hans,zh-Hant}/ipad-13/`, 2732×2048 per language, 6 shots |
| App Store IAP review | `builds/release/app-store/iap-review/*.png`, 10 shots per paid SKU, 2778×1284 |
| App Store provenance | `builds/release/app-store/screenshot-provenance.json`, 1:1 SHA-256 of 60 source→output shots |
| itch.io cover image | 630 × 500 |
| Short blurb | Two lines |
| Controls | Full-screen floating move · bottom-right dash · auto attack |
| **License notice** | Ninja Adventure (CC0), Kenney (CC0), Galmuri11 · Noto Sans CJK (OFL 1.1), Godot (MIT) |

After the support and privacy site is public, reflect the real HTTPS URL and
public support email in app settings **before rebuilding a store binary**.
First dry-run the 5 App Store locales and the game's `{locale}` link plan;
apply with the explicit confirm option only after the actual seller has
approved publishing the address.
The site URL must be an HTTPS origin with no path (e.g.
`https://support.example.com`).

```bash
node scripts/configure-store-contact.mjs \
  --site-url "https://<public support site>" \
  --support-email "<public support email>"

node scripts/configure-store-contact.mjs \
  --site-url "https://<public support site>" \
  --support-email "<public support email>" \
  --apply --confirm-public-contact
```

In the game, Korean, English, Japanese, Simplified Chinese, and Traditional
Chinese open `/ko` · `/en` · `/ja` · `/zh-Hans` · `/zh-Hant` respectively.
APK, AAB, xcarchive, and IPA built before applying this setting are previous
artifacts with no public links; do not use them as the final submission.
Setting the same two values on `MOONLIT_PUBLIC_SITE_URL` and
`MOONLIT_SUPPORT_EMAIL` makes `pnpm app-store:release` include App Store
privacy and support URLs for all 5 languages in the same release manifest.
Setting only one of them fails.

Reuse existing store-screenshot uploads first. Run the full capture commands
below only when layout, art, visible copy, or framing has changed enough
versus the existing set that replacement is required. Do not run them for
version/build changes, non-visual code changes, IAP E2E, pricing, product
registration, or fingerprint/provenance failure alone. If you only need a
new IAP review image, add that product's files and leave the existing
gallery and existing IAP files alone.

Android screenshot sources come up automatically after you boot the Pixel 10
AVD with the [`/device`](./device.md) procedure. Turn on Do Not Disturb so
status-bar notifications stay off. File names and scenes follow the
per-platform, per-language, per-device 6-shot contract in
[`store-page.md`](../../notes/release/store-page.md). The commands below
switch all five languages in the real game settings, produce 31 source shots
plus capture proofs under `builds/shots/store-localized/`, then compose the
final specs.

```bash
pnpm store:capture-screenshots
pnpm store:screenshots:play
pnpm check:store-screenshots:play

# When you have physical ipad-13 proofs for 5 locales and no physical iPhone
pnpm store:screenshots:app-store:android-pixel-avd
pnpm check:store-screenshots:app-store
```

`store:screenshots:app-store` requires both physical iPhone and iPad proofs
by default. `android-pixel-avd` mode is a fallback that letterbox-composites
the Pixel AVD runtime onto the iPhone 6.5 **submission target**; it does not
label that as a physical iPhone capture or copy it as a
`store-platform/ios/iphone-6.5` source. iPad always uses physical proof.
The check does not override mode via arguments; it re-validates
`screenshot-provenance.json` mode, capture report, sources, proofs, and
output hashes. App Store release-manifest generation and remote mutation
must pass this dedicated check first too.

Final screenshot composition needs `ffmpeg` and HarfBuzz `hb-shape` /
`hb-view`. Prepare with `brew install ffmpeg harfbuzz` on macOS or
`sudo apt-get install ffmpeg libharfbuzz-bin` on Ubuntu. `hb-view` takes
each locale's `en` · `ko` · `ja` · `zh-cn` · `zh-tw` language tag and
renders Japanese plus Simplified/Traditional regional glyphs as a transparent
layer.

:::warning Do not skip the license notice
The Godot engine needs an MIT notice. Fonts are OFL 1.1.
Put it on **both** the credits screen (Lesson 15) and the itch.io page
description. Source copies live in `apps/game/docs/licenses/`.
:::

## 7. iOS App Store distribution artifacts

`ios:archive` makes the source archive; `ios:export-appstore` makes a
distribution-signed IPA with Apple-supported `xcodebuild -exportArchive` and
`method=app-store-connect`. Keep the App Store Connect API key `.p8` outside
the repo at mode `600`, and put the actual seller's values in the three
environment variables below. Do not copy values into docs, logs, or shell
history.

```bash
export MOONLIT_ASC_KEY_ID="<App Store Connect Key ID>"
export MOONLIT_ASC_ISSUER_ID="<Issuer UUID>"
export MOONLIT_ASC_PRIVATE_KEY="<absolute path to AuthKey_*.p8 outside the repo>"

pnpm ios:archive
pnpm ios:export-appstore
pnpm ios:validate:dry-run
pnpm ios:upload:dry-run
```

Both dry-runs re-check all of the following with no network transfer.

- The archive is newer than the game, iOS plugins, and distribution scripts
- Archive and IPA bundle ID, display version, build number, and arm64 match the config
- The IPA Godot game payload is byte-identical to the verified archive
- The IPA is signed with Apple Distribution and `get-task-allow` is off
- The embedded provisioning profile is an unexpired App Store distribution profile
- The actual IPA signer certificate is included in the embedded provisioning profile
- Only the IAPKit publishable key is present and test/production-tool resources are omitted
- The `.p8` is a P-256 EC private key outside the repo and is not world-readable

Remote Validate does not upload the binary as a TestFlight build, but it
talks to Apple servers. Run it after user confirmation.

```bash
pnpm ios:validate
```

Upload only the same IPA that passed Validate, after a final confirmation.
`ios:upload` internally requires `--confirm-upload`, and after upload you
confirm Processing → Complete and warnings under App Store Connect Build
Uploads.

```bash
pnpm ios:upload
```

The artifact is `builds/ios-app-store/MoonlitBeacon.ipa`. Apple's official
references are
[command-line archive export](https://developer.apple.com/library/archive/technotes/tn2339/_index.html)
and
[App Store Connect build upload](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/).

## 8. Upload (after confirmation)

**Stop here and get user confirmation.** Show what is going where.

- File: `builds/android/MoonlitBeacon-<version>.apk` (size)
- Destination: itch.io project page
- Visibility: public / private

After confirmation the user uploads themselves. Do not run iOS automatic
upload either until you have shown the dry-run and Validate results and the
target IPA, and received a final confirmation.

## 9. Tag and record

```bash
git tag release-<version>
# Push after user confirmation
```

Update the status in the `apps/docs/course/intro.md` table of contents, and
leave the release result in `notes/release/checklist.md`.

---

## Version rules

| Version | When | Contents |
| --- | --- | --- |
| `0.0.1` | Lesson 1 | Title screen |
| `0.1.0` | Lesson 11 | First complete build that plays a full run on a phone |
| `0.9.0-rc1` | Early Lesson 16 | Release candidate |
| `1.0.0` | Lesson 16 | APK + itch.io full release |
