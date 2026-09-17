# Release checklist

Used in **Lesson 16 (QA / Export / Release)**.
Copy for store pages is in [store-page.md](./store-page.md).
Release targets are **iOS·iPadOS App Store and Android Google Play**.
APK/itch.io is a separate direct-distribution check; Windows / Web builds are
out of scope.
**Do not ship if any P0 or P1 bug remains.**

| Item | Value |
| --- | --- |
| Package name | `com.crossplatformkorea.moonlitbeacon` |
| App name | Moonlit Beacon |
| Architecture | arm64-v8a |
| Version | 2.1.0 (iOS build 9 / Android versionCode 14) |
| Reference devices | iPad + Android phone, 7-inch, 10-inch tablet |
| Orientation | landscape locked (Sensor Landscape) |

## Bug priority

```text
P0: cannot run, save corruption, cannot progress
P1: cycle progress · defeat · result · restart failure
P2: broken UI, sound issues, small balance issues
P3: minor visual issues
```

## 1. Game flow

- [ ] Start
- [ ] First/second beacon → moonlight gate → next region
- [ ] Beacon charge complete → choose safe light or overcharge
- [ ] Defend forest/field/camp overcharge raid for 6.5s → core and extra embers
- [ ] Leave overcharge range, progress drops; leave far → normal light with no reward
- [ ] Overcharge all three beacons in one cycle → Guardian loot 2 tiers
- [ ] After the gate opens, move while avoiding the chase pack
- [ ] Third beacon → current-region Guardian
- [ ] Two distinct effects on the same attack route → resonance, next attack after dash changes once
- [ ] Guardian kill → loot choice → cash out current or next cycle
- [ ] Cycle-8 cash out → formal victory; continue → endless stretch
- [ ] Hit
- [ ] Relic drop on hit → pick up again to reclaim
- [ ] Dash
- [ ] Pause
- [ ] Defeat
- [ ] Result → local and global ladders
- [ ] Restart
- [ ] Settings change
- [ ] Language change
- [ ] Quit the app then relaunch

## 2. Repeat tests

- [ ] 10 consecutive restarts
- [ ] Guardian kill and loot choice, then next cycle
- [ ] After Guardian kill/loot, cash out 5 times and continue 5 times
- [ ] Lifting the move finger does not auto-select beacon/cycle choice windows
- [ ] After death during overcharge, coin continue, or region switch, charge/reserved enemies/HUD state does not linger
- [ ] After resonance fires, only the next attack once changes, and it does not stack-explode even overlapping a final evolution's always-on effect
- [ ] Progress 3 cycles with different start regions
- [ ] Restart after defeat
- [ ] Quit the app while paused
- [ ] Home button during play → return (does it come back paused)
- [ ] Incoming call / notification during play → return
- [ ] Screen off → unlock and return
- [ ] Delete the save file
- [ ] Corrupted save file → restore defaults
- [ ] Max enemy-count state

## 3. Controls (touch)

- [ ] A move stick appears at the press except on the bottom-right dash button
- [ ] Pressing the bottom-right dash button while moving does not break the move stick
- [ ] The dash button dashes in the current move direction
- [ ] Dragging a finger off-screen and back does not release the stick
- [ ] The stick vanishes immediately after the finger lifts
- [ ] The move stick can still be operated over non-press HUD such as HP and evolution
- [ ] The stick does not cover beacons or enemies enough to hurt judgment
- [ ] A left-handed press on the other side of the screen still creates the same move stick

## 4. Screen tests

- [ ] Pixel 10 (2424 × 1080, 20:9) — reference device
- [ ] 16:9 device or emulator — UI does not overlap when sides are narrower
- [ ] 21:9+ ultrawide — background does not break when sides are wider
- [ ] Tablet 4:3 — HUD position when extra height remains
- [ ] Rotating 180° (both landscape directions) rotates correctly
- [ ] Holding portrait still keeps landscape (`orientation=4` confirmed)
- [ ] Notch / punch-hole / gesture bar do not cover UI
- [ ] Game UI is unaffected when system font size is maxed
- [ ] UI is not clipped in Korean / English / Japanese / Simplified Chinese / Traditional Chinese

## 5. Performance and heat

- [ ] Max enemy count
- [ ] Max particles
- [ ] Frames hold on forest/field/camp Guardian max patterns
- [ ] Whether 60fps holds on low-end GPU devices (older Adreno / Mali)
- [ ] Low-spec options (fewer particles / screen shake off) actually help
- [ ] Device temperature and frame drops after 20 minutes continuous play
- [ ] Battery drain over 20 minutes continuous play (`adb shell dumpsys batterystats`)
- [ ] No CPU use while backgrounded

## 6. Android build

```bash
pnpm android:release
adb install -r builds/android/MoonlitBeacon.apk
adb shell monkey -p com.crossplatformkorea.moonlitbeacon -c android.intent.category.LAUNCHER 1
```

:::danger Do not call Godot export directly
`android:release` first cleans Gradle products and temporarily isolates the
GodotIap Android plugin. Bypassing that path can leave Play Billing
permission or a previous build's DEX in the direct-distribution APK.
:::

### Signing

- [ ] A release keystore was made and kept **outside the repo**
- [ ] The keystore password is nowhere in the repo
      (`.godot/export_credentials.cfg` is gitignored)
- [ ] The release build is signed with the **release key**, not the debug key
- [ ] `aapt dump permissions` has no `com.android.vending.BILLING`
- [ ] The APK DEX has no `com/android/billingclient`
      (the output below must not contain `CN=Android Debug`)
- [ ] Keystore and password were backed up separately (lose them and you
      cannot ship updates)

```bash
MOONLIT_ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Library/Android/sdk}}"
"$MOONLIT_ANDROID_SDK/build-tools/36.0.0/apksigner" verify \
  --print-certs builds/android/MoonlitBeacon.apk
```

### Package info

- [ ] Package name `com.crossplatformkorea.moonlitbeacon`
- [ ] App name `Moonlit Beacon`
- [ ] `version/code` was **raised** for this release (cannot redistribute the
      same value)
- [x] `version/name` is `2.1.0`, Android `version/code` is `14`
- [ ] Architecture arm64-v8a checked, others unchecked
- [x] Three app icons (adaptive foreground / background / legacy) generated
      on custom paths and wired to Android and Android Play presets
- [x] Every visible pixel of the adaptive foreground is inside the center
      radius 132px (66dp) safe circle
      (`build_app_icon_assets.py --check`)
- [ ] Face, hands, and seed are not clipped under circle/squircle launcher
      masks and the Android 12 splash
- [ ] No unused permissions besides `INTERNET` for the global ladder and
      optional anonymous analytics

### Device install and run

- [ ] Installed with `adb install -r`
- [ ] Launched with `monkey`
      (`am start -n .../com.godot.game.GodotApp` failing as not exported is
      expected)
- [ ] Launches from the launcher icon
- [ ] Opens **landscape** immediately (no portrait flash even for one frame)
- [ ] Splash → title does not leave a black screen for long
- [ ] Hangul displays correctly
- [ ] Save works (personal best kept after relaunch)
- [ ] Works after uninstall and reinstall
- [ ] Dev logs removed (no debug output in `adb logcat -s godot`)

### Back button

Implemented in Lesson 16 and confirmed on Pixel 10
(`config/quit_on_go_back=false`).

- [x] Back during play → **pause** (the app does not quit)
- [x] Back from pause → title
- [x] Back from title → confirm then quit
- [ ] Same behavior with gesture navigation (swipe)
- [ ] Back on the result screen does not break the game

## 7. Export security

- [ ] `export_presets.cfg` is committed (no secrets)
- [ ] `.godot/export_credentials.cfg` is **never committed**
      — the Android keystore password is stored here
- [ ] The release keystore file (`.keystore` / `.jks`) is not in the repo
- [ ] The repo has no keys or passwords
- [ ] A web API key from `firebase.cfg` injected outside the repo does not
      enter logs or analytics events
- [ ] The final product's `firebase.cfg` uses `[analytics] enabled=true` only
      after the real public policy and Firestore deploy are done. A config
      with only public mobile keys does not turn collection on

## 8. Anonymous-analytics release gate

The items below are not completed by source and automatic tests alone. 2.1.0
submits disabled with no analytics config, and a later build that turns on
protected analytics is not submitted if any item below is empty. Store
answers and public copy are matched to each final binary's real state.

- [ ] When protected analytics collection is enabled, 5-language privacy-
      policy URLs actually open and describe optional game-usage analytics
      items, purpose, 90-day server retention, and consent withdrawal.
      A build with no analytics config, like this one, discloses the disabled
      state as-is
- [ ] App Store App Privacy and Google Play Data safety match the real final
      binary.
      Analytics-disabled 2.1.0 reflects only existing purchase-verification
      collection; add Product Interaction/App interactions as optional
      Analytics collection only on a later build that turns protected
      analytics on
- [ ] `firestore.rules` and `firestore.indexes.json` were deployed to the
      target Firebase project, and `analytics_events_v1.expires_at` TTL 90
      days plus unused-index exclusion are applied remotely
- [ ] Schema rules on public REST create alone cannot stop spam/cost attacks.
      Real App Check enforcement and valid-token send were attached, or the
      collection path was replaced with an authenticated, quota-limited
      protected proxy and load/deny tests passed
- [ ] Release `firebase.cfg` has the correct `[firebase] web_api_key` and
      `[analytics] enabled=true`, `ingestion_hardened=true`. The last value
      is set only after the protection above is confirmed remotely; do not
      leave the config original in the repo, logs, or the direct-distribution
      APK
- [ ] Debug builds are `allow_debug=true` only during separate verification
      and do not send by default
- [ ] Consent `unset/denied` has local queue and requests both 0; events
      appear only after allow
- [ ] Withdrawing consent immediately clears the max 200-item · 14-day queue
      and local cohort metadata
- [ ] Names, ladder nicknames, IAP product/transaction IDs, device/ad/
      permanent-install IDs, and free text are absent from Firestore
      documents and network captures
- [ ] Offline play does not stop, and reconnect retries without duplicates
      using deterministic document IDs
- [ ] On-device, confirm allow/deny/withdraw send separately on the later
      Android and iOS builds that first turn protected analytics on
- [ ] Run
      `pnpm analytics:report -- --file <path> --version <active-version> --to YYYY-MM-DD`
      on an admin Firestore export JSON/JSONL and a report is created.
      Play events split by app version, retention by first-consent version,
      and a return after an update stays in the original consent cohort.
      `--to` matches the last UTC observation day actually included in the
      export
- [ ] Interpret D1/D7/D30 as rates only when the consent-active cohort meets
      the default minimum `n=20`

2.0.0 has no in-app game events and 2.1.0 is an analytics-disabled submit, so
there is no app-event funnel baseline. Make a baseline from a later version's
live consent cohort and verified export that first turns protected collection
on, then compare same-schema experiments on the next version.

## 9. itch.io page

All copy is prepared in [store-page.md](./store-page.md).
Nine screenshots and the cover are newly made in `builds/release/`.

:::tip Remake screenshots
Put each scene on a Pixel 10 device and take a source PNG with
`pnpm android:shot`.
Copy the received `builds/shots/android.png` into
`builds/release/screenshots/` under the agreed names below. Movie Maker's
1616 × 720 window render is not the 2424 × 1080 device contract, so do not
use it for release screenshots.
:::

- [x] Game title
- [ ] One-line description
- [ ] Korean description
- [ ] English description
- [ ] Controls (floating move stick · bottom-right dash button · auto attack)
- [ ] Feature intro
- [ ] 9 screenshots — **2424 × 1080 device landscape captures**
- [ ] Cover image 630 × 500
- [ ] Credits
- [ ] Mark supported platforms as **Android** and mark the APK file as
      `Android`
- [ ] Check "This file will be downloaded on Android"
- [ ] Minimum requirements (Android 7.0+ / arm64-v8a — template minSdk 24)
- [ ] APK filename includes the version (`MoonlitBeacon-2.1.0.apk`)
- [ ] 2.1.0 release notes
- [ ] How to report bugs
- [ ] Test first as `Restricted` or private, then switch to Public

## 10. After release

- [ ] Install the APK downloaded from itch.io on a **wiped device** and run
- [ ] Wrote "unknown sources" install instructions on the download page
- [ ] `git tag release-2.1.0` and attach final products to a GitHub Release
- [ ] Insert the final video ID in the Lesson 16 notes on the docs site

## 1.0.2 submit record (2026-08-04)

| | |
| --- | --- |
| Google Play | production `PUBLISHED` — review passed, official name/icon/everyone rating confirmed (versionCode 4) |
| App Store | `WAITING_FOR_REVIEW` — build 4, review submission `27d8168f`, 8 items (version + 7 IAPs) |
| IAP | Play 7 ACTIVE · 173 regions (China excluded), App Store 7 included in review |
| Device verification | Pixel 10 real-money purchase and grant confirmed for all 7 on the 1.0.2 production build. IAPKit verify precedes every purchase — code cannot grant or finish without verify success. Color-pack unlock/select confirmed |
| Submit assets | committed to `stores/google-play` · `stores/app-store` (byte-match vs builds originals verified) |

## 1.0.2 resubmit prep record (2026-08-07)

| | |
| --- | --- |
| Google Play | production versionCode 11(1.0.2) uploaded at 100% rollout and submitted for review with 5-locale release notes. Play Console state is `Changes in review` with automatic pre-review in progress |
| Android consumables | `continue_coin` / `_5` / `_10` test orders succeeded. Displayed prices ₩700 / ₩2,800 / ₩5,000, balance 21 → 22 → 27 → 37, all three orders native-consumed |
| IAPKit | three new orders verified first as `Valid / Ready to consume`, then 6 minutes later converged to `Invalid / Consumed`. No 429, `REPEATED_FAILURE`, or duplicate grants |
| App Store | physical iPad 1.0.2(5) confirmed `continue_coin_5` / `continue_coin_10` real-money purchase, grant, persist across restart, and IAPKit verify. ASC 2 products registered. build 6 and 10 IAPs (3 consumables + 7 non-consumables) submitted together as review submission `bab9ff97-f20d-4664-90d0-7864f9ade034`, `WAITING_FOR_REVIEW`. Existing marketing and existing IAP images kept; only the 2 new coin review images added |
| Full check | code, IAP, store metadata, Android/iOS build, docs checks passed. Existing screens did not change, so fingerprint/provenance failure alone did not trigger a full recapture |

## 2.1.0 submit prep record (2026-08-26)

| | |
| --- | --- |
| Source version | app 2.1.0 · Android versionCode 14 · iOS build 9 aligned |
| Play | beacon safe-light/overcharge, two-effect resonance, cash-out/continue after Guardian loot implemented. Full regression, 5 languages, and device confirmation needed before external store submit |
| Analytics | anonymous queue that stores only allowed events after explicit consent, plus Firestore export reporting tool prepared. No 2.0 event baseline or 2.1 live numbers |
| Remaining release gates | privacy notices and store labels, remote deploy of Firestore rules/indexes/TTL, release `firebase.cfg`, Android/iOS on-device network verification. Analytics-enabled submit forbidden until done |

## 2.1.0 store reflection (2026-09-04 console)

| | |
| --- | --- |
| App Store | **2.1.0 Ready for Distribution** — live |
| Google Play | **2.1.0(14) live (2026-09-04)** — promote, review submit, and pass all the same day |
| Remaining | none. **Both stores matched at 2.1.0** |

The console notice is "Your app update has been published", the overview
`Last published` changed from 27 August 2026 to **4 September**, and
`Changes in review` is empty.
Same-day pass, as with 2.0.0.

The 8-cycle victory screen and off-map endless stretch now go to users on
both sides.

### Play track actual state (2026-09-04 Publisher API)

Track state at query time:

| Track | versionCode | State |
| --- | ---: | --- |
| production | 12 | completed — Moonlit Beacon 2.0.0 |
| internal | **14** | completed — Moonlit Beacon 2.1.0 |

Uploaded bundles: 1, 3, 4, 8, 9, 10, 11, 12, 14

**`--apply` was already done.** 2.1.0(14) had been committed to internal on
8/27, and a retry upload without knowing that hit 403. Remaining were only
`--promote-production` and `--submit-production-review`, and those two do not
touch AAB, listings, images, or products, so **there is no store-screenshot
reupload.**

The same day both commands were run, production became 14, and it was sent
to review with 5-language release notes. Right after promotion lifecycle was
`NOT_SENT_FOR_REVIEW`; after review submit the overview became `Changes in
review`. **Promote and stop, and nothing enters review — the two commands
are a pair.**

:::danger Do not read Play 403 PERMISSION_DENIED as a permission problem
Re-uploading an already-used versionCode, Google answers like this.

```json
{"error":{"code":403,"message":"Version code 14 has already been used.",
 "status":"PERMISSION_DENIED"}}
```

`apply-play-release` keeps only the response `status` and `reason` and drops
`message`, so the screen shows only `HTTP 403 PERMISSION_DENIED`. Suspecting
service-account permission from that alone wastes time — Play Console app
permissions (production release, test-track release) were actually fine, and
the account was `active · no expiry`.

The way to split the cause is **fetch the original `message` yourself**.
Get a token as the service account and reproduce `edits.insert` →
`/upload/...` session → byte PUT, and the body comes back as-is. Delete the
diagnostic edit with `DELETE`.

The same account's `inappproducts.list` separately returns `"Please migrate
to the new publishing API."` You hit this wall again when using product
sync (`--include-products`).
:::
