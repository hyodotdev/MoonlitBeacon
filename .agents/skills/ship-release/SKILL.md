---
name: ship-release
description: The full loop that actually puts Moonlit Beacon on the App Store and Google Play and takes it through review. Use when asked to store-deploy or submit for review — "deploy it", "ship it and get it reviewed", "put it on the store", "put 1.0.x up". Runs develop → self-review → e2e → PR → PR review → re-verify → merge → both-store deploy in order, and repeats until it passes.
---

# Store-release loop

`/release` is for itch.io and the direct-distribution APK. **This skill is
the loop that goes through App Store and Google Play review submission.**

The core is **repeat until e2e passes**. Run it once, fail, and do not stop
there. Fix and run again.

---

## Order

```text
1. Develop        implement the feature or fix
2. review-self    .claude/skills/review-self — fix only evidence-confirmed defects and re-verify
3. e2e            device/emu purchase e2e + pnpm verify
   └ on failure go back to 1. Until it passes.
4. /commit --pr   branch → commit → push → PR (labels required)
5. PR review      take review-bot findings on the PR plus CI results
6. e2e again      after review landings, run 3 again
   └ on failure go back to 1.
7. Merge          onto main after confirming CI passed
8. Deploy         App Store + Google Play review submission
```

4–7 follow the rules in [`.claude/commands/commit.md`](../../../.claude/commands/commit.md).
The repo rule **do not push without user confirmation** still applies here.

:::note There is no dedicated slash command for step 5
This repo has no `/review-pr`. PR review is given by bots on the PR and by
CI. Looking again yourself when there is no human reviewer is
[`review-self`](../review-self/SKILL.md); looking at in-progress changes is
[`/review`](../../../.claude/commands/review.md).
:::

---

## What step-3 e2e is

It always means both code and a real purchase. A release that changed
screen or art also adds visual E2E. If any applicable row is missing, do not
say you did e2e for that scope.

### Code level

```bash
pnpm verify
```

The same checks as CI. Game/IAP regressions, locale, repo rules, assets,
store metadata, and the docs build. The strict screenshot
fingerprint/provenance freshness check runs separately only on a store-release
path where you have already decided which screens to replace.

### Screen and art-change e2e

Follow the whole [visual E2E evidence contract](../moonlit-workflows/references/visual-e2e.md).
Report Pixel 10 physical device of the final APK, full production-PNG zoom,
and generator/Godot automated checks separately. Do not substitute a
representative combat capture for device evidence of every hero and every
direction.

### Real-purchase e2e — physical Pixel + Play test track, physical iPad + Sandbox

```bash
node scripts/apply-play-release.mjs --check   # internal-track status
```

**Three prerequisites.** If any is missing, Play Billing does not respond.

| | How to confirm |
| --- | --- |
| The app is on the internal track | `--check` is `ready` |
| A Google account is signed in on the Pixel | `adb shell dumpsys account \| grep Accounts:` is not 0 |
| That account is an internal tester + license tester | Play Console settings |

:::danger Account sign-in is done by a human
Google-account sign-in is credential entry, so **the agent does not do it**.
If accounts are 0, stop there and hand it to the user.
:::

:::danger A sideloaded APK cannot purchase
If `installerPackageName=null`, Play cannot verify the signature.
Play App Signing re-signs the AAB, so a local APK signed with the upload key
is different.
**Install from the Play Store via the internal-test opt-in link.**
`adb shell dumpsys package com.crossplatformkorea.moonlitbeacon | grep installerPackageName`
must be `com.android.vending`.
:::

Confirm all 10 products. The 7 non-consumables (`supporter`, 5 heroes,
`lantern_colors`) are purchase → grant → survives restart → restore; the 3
consumables (`continue_coin`, `_5`, `_10`) are exact 1/5/10 grant → survives
restart → native consume → repurchase of the same product. On iOS, confirm
the same grant counts and restart survival after StoreKit verification.

---

## Step 8 deploy — both stores

### Google Play

Start from a state already applied to the `internal` track.

```bash
export GOOGLE_APPLICATION_CREDENTIALS="$HOME/Library/Application Support/MoonlitBeacon/signing/moonlit-play-google.json"
node scripts/apply-play-release.mjs --check
```

`--check` **uses no network at all.** Remote work uses only the printed
token. The full procedure is
[`notes/release/google-play-publisher-apply.md`](../../../notes/release/google-play-publisher-apply.md).

Production promotion is a separate boundary with a separate confirm token.
It does not touch AAB, listing, images, or products; it only moves an already
committed versionCode.

### App Store

```bash
export MOONLIT_ASC_KEY_ID=<10 characters>
export MOONLIT_ASC_ISSUER_ID=<UUID>
export MOONLIT_ASC_PRIVATE_KEY="$HOME/Library/Application Support/MoonlitBeacon/signing/AuthKey_<KEYID>.p8"
export MOONLIT_PUBLIC_SITE_URL=https://moonlit-beacon-support.hyodev.chatgpt.site
export MOONLIT_SUPPORT_EMAIL=<public support email>

pnpm ios:archive             # must be newer than project.godot
pnpm ios:export-appstore     # distribution-signed IPA — needs ASC credentials
pnpm ios:validate:dry-run    # no network
pnpm ios:validate            # ASC remote validation
pnpm ios:upload              # TestFlight
node scripts/app-store-release.mjs --check
node scripts/app-store-release.mjs --check --remote-audit
```

Review submission uses `--submit-review` together with a dedicated confirm
token.
**The TestFlight build must have finished processing** before it can attach
to a version.

---

## Where credentials live

All outside the repo, mode `600`.

```text
~/Library/Application Support/MoonlitBeacon/signing/
  AuthKey_*.p8                  App Store Connect API key
  moonlit-play-google.json      Play service account (GOOGLE_APPLICATION_CREDENTIALS)
  moonlit-beacon-upload.jks     Android upload keystore
  moonlit-release-keychain-password
```

IAPKit publishable key is in the macOS Keychain — service
`dev.openiap.kit.moonlitbeacon`, account `MoonlitBeacon Mobile`.

**Issuer ID is stored nowhere.** Read it from App Store Connect →
Users and Access → Integrations. If it is missing, ask the user.

---

## Things that often bite

| Symptom | Cause |
| --- | --- |
| `iOS release artifact is older than project.godot` | The Android build touched `project.godot` mtime. Start again from `pnpm ios:archive` |
| `App Store Connect auth environment variables are missing` | `export-appstore` also uses the ASC key. It has to fetch a distribution profile |
| `App Store release manifest differs from current metadata and images` | Ran without `MOONLIT_PUBLIC_SITE_URL` and `MOONLIT_SUPPORT_EMAIL`. Set them **together** |
| `Google service account blocked` | `GOOGLE_APPLICATION_CREDENTIALS` not set |
| `receipt already exists` | That versionCode is already applied. Do not apply twice |
| A codesign password dialog appears | The release keychain is locked. `security unlock-keychain` + `set-key-partition-list` with `signing/moonlit-release-keychain-password` |

## Recapture a screen only when what the store actually shows has changed

The default is to reuse existing uploads. Do not recapture for version/build
changes, non-visual code, IAP E2E, price/product registration, or
fingerprint/provenance failure alone. List exactly the screens whose layout,
art, visible copy, or framing is completely different versus the existing
image, then shoot. If you only need a new IAP review image, add the new
product files and leave existing marketing images and existing IAP images
alone.

Use the full capture commands below only when the affected screens have
actually changed together with the existing generator's full contract. If
the full tool would rebuild existing files you do not need, first make a
minimum-target path.

| Target | Command | Contract |
| --- | --- | --- |
| Phone 5 locales | `node scripts/capture-store-screenshots.mjs --fresh` | Pixel_10 AVD auto-boot |
| 7- and 10-inch | `capture-android-tablet-evidence.mjs --serial … --avd Moonlit_{7,10}_API36 --target …-tablet --apk builds/android/MoonlitBeacon.apk --fresh-build --all-locales` | `--fresh-build` APK path **must** be `builds/android/MoonlitBeacon.apk`. Reusing phone attestation is structurally impossible (input lists differ, 53 vs 42) |
| iPad 13 | `capture-ios-device-evidence.mjs --target ipad-13 --device-id … --rsd-host … --rsd-port … --all-locales` | See the tunnel section below |

When a real recapture is needed, stash the existing canonical first.
If previous results sit in `builds/shots/store-platform/{android,ios}/`,
the publish step refuses to overwrite.
Move them to `builds/{tablet-evidence,ios-device-evidence}/stale-canonical-pre-<version>-<time>/`.

### iPad capture needs a sudo tunnel first

iOS 17+ screen capture sits behind a RemoteXPC tunnel, and the tunnel
requires root.
**The user** leaves it up in a terminal:

```bash
sudo pymobiledevice3 remote tunneld
```

The script's automatic RSD discovery is often wrong. Read the tunnel
address yourself and pass it:

```bash
curl -s http://127.0.0.1:49151/   # → tunnel-address, tunnel-port
```

The `moonlight_barrage` scene fails intermittently because of game RNG (you
have to observe the moment Moonfire awakening turns off within 45 seconds).
Fixing game code breaks the fingerprint, so **retry** is the right answer.

### Commit the final submission into `stores/`

`builds/` is not in git, so assets you actually newly uploaded also stay in
`stores/`. Do not overwrite the whole folder. Copy only files newly uploaded
or actually replaced in this submission onto the same relative path, and keep
existing uploaded assets byte-identical.

---

## Places you must stop

The agent does not do these. Hand them to the user.

- Google-account sign-in, App Store Connect sign-in — credential entry
- Values only a human knows, such as Issuer ID
- Review submit/cancel, production promotion — hard-to-undo external work
  **tell them what you are sending immediately before running, and get
  confirmation**

## When only screenshots change (no binary resubmit)

The path when the store screen has actually changed but the binary stays.
It exists because the first 2.0.0 cut went out with the hero buried in
speech balloons and banners.

```bash
pnpm store:capture-screenshots        # phone 5 locales
node scripts/capture-android-tablet-evidence.mjs --serial <emu> \
  --avd Moonlit_7_API36 --target seven-inch-tablet \
  --apk builds/android/MoonlitBeacon.apk --fresh-build --all-locales
#   (once more for 10-inch with Moonlit_10_API36 · ten-inch-tablet)
pnpm store:screenshots:play           # generate + verify
pnpm check:store-screenshots:play
pnpm store:sync-play                  # byte-verified copy into stores/google-play
pnpm android:bundle                   # for package freshness — do not upload
pnpm store:prepare-play
pnpm play:images:check                # issue a token
pnpm play:images:apply -- --confirm-listing-images <token>
```

- Image-only apply has no code that touches bundles, tracks, or products.
- **Show the user the final set and get approval before upload.** Do not
  create a second time where a human discovers a bad cut on the store.
- If a tablet canonical already exists, publish refuses — move it aside as
  `.stale-*` and run again. An emulator that has been up a long time can
  take over 30 seconds to launch the app and fail launcher proof — cold-boot
  a fresh one.

### When App Store assets go too

The iPhone 6.5 set is derived from the Android Pixel capture. **Only the
iPad 13 set needs a physical device** — the simulator never shows a screen
because of upstream issues on both Godot and Apple.

```bash
sudo ./scripts/ios-tunnel.sh          # separate window. Do not close it
curl -s http://127.0.0.1:49151/       # read tunnel-address and tunnel-port
node scripts/capture-ios-device-evidence.mjs --target ipad-13 \
  --device-id <COREDEVICE_UUID> --rsd-host <address> --rsd-port <port> --all-locales
pnpm store:screenshots:app-store:android-pixel-avd
pnpm check:store-screenshots:app-store
pnpm store:sync-app-store
```

- **Do not start the tunnel with `remote start-tunnel`.** It is one-shot, so
  closing the terminal or the iPad locking kills it, and you run capture
  without knowing it is dead. `scripts/ios-tunnel.sh` starts it as a
  `tunneld` daemon and brings it back if it dies.
- **Pass the RSD address by hand.** The capture script's `lsof` auto-detect
  in tunneld mode picks the wrong port and dies with `rsd-info exit 1`. The
  real endpoint lives only on tunneld's REST API.
- The capture-only app is a separate bundle, so **the first install must
  trust the profile on the iPad** (Settings → General → VPN & Device
  Management → Developer App). Without that, launch is blocked with
  `invalid code signature` while the exit code is 0, so it looks like
  success.
- iPad canonical has a preemption guard too — move it aside as `.stale-*`
  and run.
