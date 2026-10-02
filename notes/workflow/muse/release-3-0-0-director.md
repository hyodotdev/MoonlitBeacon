# 3.0.0 store-release continuation

## Authorization and scope (2026-10-01)

The user asks whether the renewal is more polished and fun, requests two or
three careful reviews, and explicitly authorizes merge when satisfactory,
new store screenshots and deployment. This supersedes the earlier no-merge
and no-store-capture instruction. It does not create the human PR signal or
provide the separate push confirmation required by the repository.

Baseline: `becf316`, `feat/3-0-0-ui-story`, 48 commits over main; the only
untracked unrelated directory is `.playwright-mcp/`. Earlier independent
root verification and two reviews passed. Implementation is accepted and
local; no PR, merge or store operation has happened yet.

Locked before capture: app 3.0.0, both Android presets code 15, iOS build 10.
Do not modify runtime after capture without recording its consequences.

## Replacement decision before capture

All six existing marketing screens show materially older presentation:
combat, guardian and core-recovery shots change hero/weapon/guardian art,
terrain and HUD; title, shrine and hero preview change art, layout and copy.
Capture the same six filenames for en-US, ko-KR, ja-JP, zh-Hans and zh-Hant:

- `01-moonlight-barrage.png`
- `02-field-guardian.png`
- `03-missile-core-drop.png`
- `04-title.png`
- `05-moonlit-shrine.png`
- `06-hero-preview.png`

Canonical runtime sources: `builds/shots/store-localized/<locale>/` and
`builds/shots/store-platform/{android,ios}/<device>/<locale>/`.
Submission outputs: Play phone/seven-inch-tablet/ten-inch-tablet and App
Store iphone-6.5/ipad-13 in the existing locale output trees. The iPhone
submission target may use the explicitly labelled Android-Pixel fallback;
the iPad source must be physical. Native device identity and submission
geometry are distinct, and the report must say which one was observed.

IAP review images are compared before upload. Only visually changed app UI
or hero art is replaced; unchanged existing icons/product images remain
byte-identical. Source/provenance failure alone is not a replacement reason.
No old canonical capture tree is present at continuation start.

## Evidence rows kept separate

1. Code/source: fresh original `pnpm verify`, related defect checks and
   generator output comparisons; retain earlier 667-file runtime witness,
   live music/mix and exhaustive art/motion evidence when bytes still match.
2. Device/play: Android emulator first; final physical Android device must
   be identified and its installed hash compared. Pixel 10 currently absent;
   connected Galaxy use is a pending user decision. No existing store app is
   uninstalled and no physical user save is wiped. Observe walk/dash/camera,
   all six weapons, UI, guardian, progression/defeat/result/restart.
3. Package/store: new localized runtime shots and settled proofs, submitted
   image inspection, signed store artifacts, dry-run/remote audits and actual
   readback. Both native test purchase paths remain separate from code tests.

## Pending human inputs

- Explicit push approval and human-created `.claude/allow-pr`.
- A user-run iPad root tunnel (`sudo ./scripts/ios-tunnel.sh`) kept open;
  no tunnel REST service is currently reachable.
- Dedicated test Pixel connection or explicit use of the connected Galaxy.
  That Galaxy has accounts but the existing app installer is null, so it
  does not prove a Play test-track purchase setup.

Continue independent Android capture/build/review work while these are
pending. Do not infer approval from a default option or elapsed time.

## Operation log

- Initial Play local apply check fails because no current prepared package
  exists; it made no remote request or mutation. iPad is connected; physical
  phones reported by the iOS tool are unavailable. Full root review 1 is
  started in `builds/verify/director-release-review-1.log`.
- Review 1 fails one of 71 late-game performance cases: Knight Lv40 peak
  1202 exceeds the unchanged 1200 cap. Candidate work remains 1472/91 ticks,
  40 spirits and 16 detonations. Brief 024 starts an implementer investigation;
  capture is held until the runtime is stable.
- A separate fresh-home scene execution passes the same 71 cases at peak
  1187, 40 spirits and 16 detonations. This does not cancel the full-run
  failure. The cause is still unestablished. An initial standalone invocation
  used `--script` and failed without autoload symbols; it was stopped and is
  excluded from evidence. The corrected `.tscn` run is
  `builds/verify/director-release-cannon-baseline-2.log`.
- Pixel_10 emulator is booted with host GPU, and the previous final debug
  APK installs and launches. Title, settings in English/Korean, shrine and
  IAP panel were inspected in `builds/shots/director-release-review/`.
  These are review captures of the pre-correction APK, not final store proofs.
  The app's shop panel and hero copy visibly differ from existing IAP review
  images; final IAP captures must replace the affected layout/art.
- Store credential names are configured and the two referenced credential
  files exist. No values were printed, no remote request was made and no
  store operation has been performed.
- GET-only remote audits confirm Play internal and production still publish
  2.1.0 code 14. Ten existing purchase options are ACTIVE; the existing hero
  bundle is INACTIVE. This is recorded, not silently changed. ASC shows 2.1.0
  READY_FOR_SALE and existing valid builds, including build 9; there is no
  3.0.0 version/build uploaded. Evidence is in the two
  `builds/verify/director-release-{play,asc}-readback.json` files.
- The installed Pixel_10 AVD base APK hash equals the local pre-correction
  debug APK, `22e9a4e9a49d186095bb12c76c169f975404740eae66d0297b4c069b60a33f76`.
  The Keeper debug selector consumes once without forging ownership. A
  39.74-second silent video/contact sheet shows normal early combat,
  tutorial, level choice and defeat, but includes idle time and modals;
  it is not the clean direction/motion matrix or proof of long-run fun.
  A settled title center tap starts successfully; earlier taps during panel
  closure were not treated as a confirmed title defect.
- Seven-inch AVD also boots with host GPU at API 36. Physical Android
  selection and the iPad root tunnel remain pending human input.
- Cannon candidate 20261001-1750-late-cannon-node-budget is accepted after
  two rounds (round 2 only corrects prose). Three director-run isolated live
  samples pass 73 cases at 1187, 1187, 1186 nodes, with 40 spirits and 16
  detonations. Director negative control fails the new split-tick assertion
  (expected 2 pops, got 3) and restores the source hash exactly. Quick judge
  checks pass with no failure lines. Windowed Knight strong/early four-side
  captures pass 108/89 checks; all 32 body crops were viewed at 4x nearest,
  plus actual combat/impact frames. Detonation still reads clearly.
  These are host rendering proofs, distinct from physical-device evidence.
  The original full verify is restarted after acceptance in
  `builds/verify/director-release-review-1-fixed.log`.
- Original full verify finishes exit 0 after the correction: game suite,
  122 script compile, five locales, asset/audio/graphics determinism, repo
  rules and docs/anchors pass. The 667-file runtime witness differs from
  the prior kinetic evidence only in `scripts/actors/moon_arrow.gd`.
  New witness is `builds/verify/director-release-runtime-witness.json`.
  The earlier debug APK is comparison material; final capture rebuilds it.
  A fresh Knight natural run also checks the changed visual-RNG path.
- Authorized phone capture starts with `--fresh --serial=emulator-5554`
  against the dedicated Pixel_10 AVD, with the default fresh capture build.
  No physical phone data is altered. Log:
  `builds/verify/director-release-phone-capture.log`.

- Current-root Knight natural play finished with exit 0: 408.7 simulated seconds, 481 kills, nine hits, one loop completed, level 24, zero stuck events and zero frame spikes. This is one policy/seed sample, not a human enjoyment measurement. Evidence: `builds/play/director-release-knight.json`.
- Fresh phone capture built and installed the corrected runtime but stopped at the 90-second title-ready gate. Two host-GPU AVDs were running; adb screenshot retrieval also stalled. Closed only the director-started seven-inch emulator. Afterward the phone reached Godot main loop and emitted `store_capture_title_runtime.ready`; retry uses the same attested APK and installed package (`--skip-build --reuse-install`) with no weakened readiness gate. First failure log: `builds/verify/director-release-phone-capture.log`; retry: `builds/verify/director-release-phone-capture-r2.log`.

- Capture retry passed the real direct-distribution runtime boundary and title/shrine captures, then confirmed stale independent Node Keeper description pins (old damage bonus versus the current lantern shotgun copy). No screen bug or relaxed gate is inferred. Brief 025 delegates exact five-locale pins plus a CSV-backed regression to the implementer. Failed unpublished staging is not submission evidence.
- Corrected capture APK independently verified: 109,914,213 bytes, SHA-256 `90e21f76abb9158e0c6dee40890dfdde51ef2c033d2a3ec4490e4c20ea733780`, v2 signature valid, package identity correct, 3.0.0/code 15/arm64-v8a, no tests/tools/IAPKit configuration or BillingClient dex. Inspection: `builds/verify/director-release-capture-apk-inspection.json`.

- Current Play AAB build completed with exit 0. Independent `inspectAndroidBundle` confirms 3.0.0/code 15, the configured release signer pin, and store runtime/resource/billing/IAP/localized-name boundaries. 60,356,869 bytes; SHA-256 `80372b8fe995b6d301d4d0ff990ed13a175ef275a5839d620168983bc0f1b7f9`. Evidence: `builds/verify/director-release-aab-inspection.json`. The ordinary self-signed upload-key chain warning is retained in the jarsigner log; it is not a failed signature. No Publisher write was made.

- Direct-distribution release APK built with exit 0 and independently passes configured-release-signer pin, no development resources, no IAPKit config/BillingClient, and localized app-name checks. 3.0.0/code 15/arm64-v8a, 104,144,820 bytes, SHA-256 `8990b568d398c63f5cfeb34e5388150c72580201860f3d32edf546cb62bf60ac`. Evidence: `builds/verify/director-release-direct-apk-inspection.json`. This is a local artifact, not an itch.io or store upload.

- Brief 025 accepted after director review of all three paths. Independent combined Node run: 61 tests, 61 pass, 0 fail, 37.764 seconds (`builds/muse/director-copy-acceptance.log`). Director reverted only the independent English pin as a negative control; the CSV-backed regression fails with exit 1 and one live-description failure. Exact restoration SHA-256 `269ca11d1f0f961b20fde2cdbc3082c2c4f7d9070d05f0f0b231518fe6d665ab` matches before/after. Evidence: `builds/verify/director-release-copy-negative-proof.json`. No production runtime changed. A fresh root `pnpm verify` started in `builds/verify/director-release-review-2-fixed.log` before rebuilding capture attestation.

- Brief 025 round-2 notes correction was judged, but the original tag was already accepted; `muse accept --check` could not reapply the cumulative patch, and `accept` refused the already accepted tag. Root retains the verified round-1 code and notes. No bypass or manual ordinary-note edit was performed. The notes-only brief is rerun as a fresh task on the current root, so only the freshness paragraph will apply. Corrected scripts are committed in bc9daf0; round-1 notes/briefs in a0f6780.

- Fresh notes-only tag `20261001-1906-025b-capture-attestation-record` changes one paragraph. Reviewed the actual diff, checked clean application, and accepted it through Muse. Both capture scripts remain byte-identical to their verified round-1 correction. The record now correctly says old capture-input proofs are stale even though production runtime did not change. All 667 files also match the release runtime witness after Android exports.

- Renewed-root full `pnpm verify` after the capture guard fix finished with exit 0: 468 Node checks across 16 suites/groups, all 52 game steps, 122 script compilations, five locales, unchanged IAP metadata, skills/hygiene/assets/store graphics/docs/anchors. Knight Lv40 node peak again 1186; 73 late-game checks pass. Evidence: `builds/verify/director-release-review-2-fixed.log`.
- Canonical five-locale phone capture restarted with a fresh build/install on the only running Pixel_10 host-GPU AVD. Log: `builds/verify/director-release-phone-capture-r3.log`. The previous failed staging is not reused or submitted.

- Canonical phone capture R3 finished exit 0 with 40 PNGs and signed report. All 40 original 2424×1080 PNGs pass complete PIL integrity verification. Reviewed five six-screen locale boards and ten IAP review tiles; exact live copies and safe panel framing match. A perceived missing preview portrait was a false positive: native RGBA crop hashes are identical in all five locales (`3d9dabc6c33e2c2a6b9f9f5fce9a220fe1ed270330462336a57ebac7d8c5c1b8`), all 89,975 crop pixels have alpha 255, and the expanded en/ko/ja crop visibly contains the portrait. No game defect or speculative fix is claimed. Evidence: `builds/shots/director-release-review/preview-five-locale-pixel-crosscheck.json`. The Traditional Chinese shrine title is also complete in the full original.
- Seven-inch canonical capture started on the sole running host-GPU Moonlit_7_API36 AVD, using its own fresh build/attestation and all five locales. Log: `builds/verify/director-release-tablet-7-capture.log`.

- Seven-inch canonical capture completed exit 0 with 30 original 1024×600 PNGs across all five locales. All pass full PIL integrity verification, and all five native-size six-screen review boards were personally viewed. Its own fresh APK/build attestation and signed report are retained in `builds/shots/store-platform/android/seven-inch-tablet/`. The seven-inch AVD was closed; ten-inch capture starts on the sole running host-GPU Moonlit_10_API36 at 1280×800, with an independent fresh build and all five locales. Log: `builds/verify/director-release-tablet-10-capture.log`.

- Ten-inch canonical capture completed exit 0 with thirty original 1280×800 PNGs. All pass full integrity checks and all five native-size locale boards were personally viewed. The strict Play generator then failed on a confirmed stale Python permanent-file contract: eighteen consumer entries versus twenty Node producer entries, specifically missing `chronicle.json` and `chronicle.json.tmp`. Both producer maps include these files and before/restored hashes are equal. An in-memory diagnostic aligns only the constant, without writing any source, proof or submission file; all other phone and tablet report checks pass. This is diagnostic evidence, not a passing unmodified generator. Brief 026 starts the implementer correction and cross-language/Chronicle regressions. The generator itself is a pinned capture input, so the current reviewed captures will need new authorized attestations/captures after acceptance; no report hash edits or fingerprint exclusions are allowed.

- Platform-specific source inspection corrects the preceding broad staleness assumption: only the phone source/attestation inputs pin `build_store_graphics.py`. Both tablet reports' four source maps and own APK attestations exclude it; their 42 source inputs and production runtime remain unchanged. Brief 026c corrects only the record before acceptance. The director will run the unchanged strict tablet checker after acceptance and retain the current tablet captures if it passes. Do not recapture these tablets merely from an assumed shared pin.

- Brief026 accepted after the code/test review plus two record-only corrections. Director independent suites pass 33/33; removing each Chronicle tuple entry fails the new producer/consumer regression, then restores the exact generator SHA-256 `0ecda3d2703b322cd33403c1fec7bacc03277153b95e42f7a29f8a902095cb05`. Root unmodified strict tablet report validation passes both existing tablet captures. The old phone proof is correctly rejected; exact fingerprint comparison identifies only the generator input hash and identical production runtime. Evidence: `builds/verify/director-release-persistence-root-proof.log`. The first diagnostic used an overly narrow error-message assertion and exited 1; the corrected exact-delta/runtime check exits 0 without any source or proof edit. Code/test commit `4c92f86`, notes/briefs `a5561bd`. Original phone canonical is retained under `builds/phone-capture-work/stale-canonical-pre-3.0.0-20261001-1108`; authorized fresh phone R4 starts on the sole Pixel_10 AVD. Tablet captures are retained unchanged.

- Phone R4 fresh build/install passes and captures English six screens plus Korean title/shrine/preview/barrage, then an ADB daemon restart interrupts private runtime-state reads. Cleanup also reports one pre-restore observation error and rejects publication; no failed proof is used. A subsequent independent serial-scoped private-directory listing confirms all twenty production persistent files are absent again (R4 was a fresh install before first launch), with only profileInstalled/shader_cache left. No physical app or data was touched. Evidence: `builds/verify/director-release-phone-r4-cleanup-observation.json`. ADB restart cause remains unestablished; the third full verify was running concurrently, so all further capture/build/verify operations are sequenced to avoid shared-tool interference. Phone R5 will reuse only the byte-identical attested APK and clean installed package after full verify completes; no readiness gate is relaxed.

- Third current-root full `pnpm verify` completed exit 0 after the Chronicle capture-consumer correction, including all game steps, 122 compilations, registered Node suites, locale/IAP checks, deterministic assets/audio/graphics, hygiene/skills and docs/anchors. Knight Lv40 node peak is 1187 with the unchanged budget and 73 cases. Evidence: `builds/verify/director-release-review-3.log`. Phone R5 now runs alone using the byte-identical fresh R4 APK/attestation and clean installed package (`--skip-build --reuse-install`); this does not reuse any failed screenshot proof.

- Phone R5 completed exit 0: forty native 2424×1080 PNGs, canonical publication eligible, signed runtime/provenance and byte-exact persistent-file restoration. The director viewed all five six-screen boards and all ten Korean IAP originals, then closed the sole phone emulator. A perceived missing preview portrait was independently disproved again by identical opaque RGBA hashes across all five locales; no asset change was made. Evidence: `director-release-phone-capture-r5.log`, `phone-r5-*-review.png`, `phone-r5-preview-pixel-crosscheck.json`.

- Play generation R2 completed exit 0 and internally deterministically validated all ninety generated submission images; dimensions/RGB/integrity checks also pass. Before any store sync/upload the director viewed Korean phone/7-inch/10-inch final boards and found a real framing defect: three phone combat images still removed the lower 180 source rows, losing the new dialogue ribbon and clipping the dash control. These generated images remain a review checkpoint, not an approved upload set. Brief 027 corrects the obsolete crop; its continuation also aligns the contradictory screenshot instructions. Tablets preserve the whole viewport already.

- Brief 027 candidate independent registered package suites pass 211/211. A director double-sided negative control restoring the old 180-row crop makes the new real compositor regression fail on 900 retained source rows; both candidate files are restored to their exact original SHA-256 and the targeted regression then passes. Evidence lives in the candidate `builds/director-phone-framing-{tests,negative,restored}.log` and `director-phone-framing-negative-proof.json`. Acceptance, current phone recapture and regenerated final visual review are still pending at this checkpoint.

- Final local Play AAB build completed exit 0. Independent inspection verifies 3.0.0/code15, the pinned release key, localized resources and billing/IAP/runtime archive boundaries. It is byte-identical to the prior corrected AAB checkpoint: 60356869 bytes, SHA-256 `80372b8fe995b6d301d4d0ff990ed13a175ef275a5839d620168983bc0f1b7f9`. Evidence: `director-release-aab-final.log`, `director-release-aab-final-inspection.json`. No upload or remote store action is implied.

- Brief 027 accepted once after both rounds finished, five reviewed paths. Code/config/test commit `dd13ee1`, framing instructions `4079503`. Root unmodified strict tablet validation passes both retained sets again (`director-release-framing-retained-tablet-proof.log`). A final real-tree full verify is running; production runtime remains unchanged. Local App Store preparation rejects the absent/currently incomplete App Store screenshot contract, and the human iPad tunnel endpoint still refuses connection. No proof or gate was altered to pass it.

- The final framing root full `pnpm verify` completed exit 0 (`director-release-review-4-framing.log`): this is the fourth corrected full pass, the first including the full-viewport compositor regression (211 Play-package cases). Knight Lv40 peaks at 1186 with 73 checks. All 667 reviewed production runtime files retain exact bytes (`director-release-framing-runtime-proof.json`). R5 canonical is retained at `builds/phone-capture-work/stale-canonical-pre-framing-20261001-1159`; only the invalidated phone capture is now rebuilt on the dedicated Pixel_10 AVD, with no other build/import/capture run in parallel.

- Final full TAP totals are 470 tests across sixteen groups, zero failures. The first R6 framing capture invocation rejects `emulator-5554` as offline before any build/install/capture operation; the freshly booting emulator was not yet ready. Explicit serial-scoped `get-state=device` and `sys.boot_completed=1` are now observed before the retry. Failed log is retained as `director-release-phone-capture-r6-framing.log`; actual fresh retry runs under `director-release-phone-capture-r6-framing-retry.log`. No capture evidence is reused from a failed attempt, and no physical user device is affected.

- All ten final Play tablet six-screen review boards (two devices × five languages) have now been viewed at original resolution. Full dialogue strips, complete controls, localized title/shrine/preview and guardian scenes stay within the sharp viewport. Their pre-framing output hashes are retained in `director-release-play-before-framing-hashes.json`; the final generation must match these exact sixty tablet outputs before retaining this visual review. The five phone boards will be reviewed from the newly generated current set.

- Phone R6 actual retry completed exit 0: forty native PNGs fully decode at 2424×1080, canonical publication eligible, signed persistence restoration byte-exact, capture APK hash exactly matches the installed APK and the earlier reviewed `90e21f76…` binary. All five raw six-screen boards and the ten IAP originals were viewed; the preview portrait ROI again has exactly identical opaque pixels across all languages, SHA-256 `3d9dabc6…`. Evidence: `phone-r6-integrity-summary.json`, `phone-r6-*-review.png`, `phone-r6-preview-pixel-crosscheck.json`. Only our Pixel AVD was closed afterward. The post-capture AAB build also completed exit 0 and independent inspection retains the same release-signed `80372b8f…` AAB. Final Play 90-image generation/embedded deterministic verification is running. No external writes have occurred.

- Read-only final Git audit fetches current main `17761af561e5de06e27eb1e3e05869a3b403affc`. Current head `6b0451b` is 58 commits ahead; `git merge-tree --write-tree origin/main HEAD` exits 0 without conflicts, with merge tree `9ee9045b15966ba52b2228f3ed62171f0d697b0a`. Existing PR lookup returns none. These are local conflict/readback checks, not CI success or an actual merge (`director-release-git-readiness-final.json`). Push approval and the human PR signal remain absent.


- Final Play image generation completed exit 0 in `director-release-play-images-final-framing.log`. Ninety RGB submission PNGs fully decode at their required dimensions; generation and package preparation independently rerender them and pass the unchanged strict source, signature, restoration, semantic, framing and deterministic checks. All fifteen final locale/device six-screen boards were viewed. The sixty tablet outputs remain byte-identical to the ten earlier personally viewed boards; all thirty phone outputs use the final R6 proof and corrected full-screen combat framing. Exact portrait-region pixels agree across all five final preview languages, rather than relying on a perceived image-display difference.
- Minimum-change local synchronization replaces exactly ninety changed Play screenshots and preserves all seventy-two other baseline PNGs byte-for-byte. These are local candidates only. Commit `99cbdf9` contains exactly the ninety authorized PNG paths, with no unrelated files; no images were uploaded. Evidence: `director-release-play-minimum-sync.json` and `director-release-play-final-integrity.json`.
- `pnpm store:prepare-play` completes exit 0 with the final version 3.0.0/code 15 AAB, five listings, five release notes, ninety screenshots, ten unchanged app graphics and seven non-consumable payload files. Product application is not authorized by this preparation and is not planned. `apply-play-release.mjs --check --json` completes exit 0, ready=true and blockers=[], manifest digest `49a36ba1dfe649f221615d716d66de56a0d3ec1af6bd640da46e7e6ec24eb073`. This check is local and makes no network request.
- The director initially misread the prepared manifest's generic default attestation gates as a missing account-owner confirmation. This was corrected after inspecting the actual existing `google-play-remote-apply.json`, where both owner attestations are already recorded. No new legal approval, configuration edit or product mutation is required by that local check.
- The combined `pnpm check:store-screenshots` passes the Play portion then exits 1 because `builds/release/app-store/screenshot-provenance.json` is missing. No proof was fabricated and no physical-iPad capture was substituted. Android screenshot scope is complete; both-store screenshot validation is incomplete.
- Normal `pnpm ios:archive` stops with Xcode exit 65: the automatic development signing identity lacks its private key. A manual normal-archive operation using the existing Moonlit distribution identity also fails with an invalid-signing-certificate error, before asset-catalog compilation. No archive, IPA or store-capable fallback is claimed. The original user keychain search list was restored after each temporary operation.
- Read-only certificate/profile diagnosis confirms the Moonlit certificate serial `19F65871DA390FC3B64CEF652D9A092C` is absent from the current Apple certificate inventory, local trust reports `CSSMERR_TP_CERT_REVOKED`, and Moonlit App Store profile `9a54e148-1fd1-4924-8593-474db7881835` is `INVALID`. Its printed validity dates alone did not establish validity. A second stale profile relationship returns HTTP 404 and is recorded as unavailable, not reused. Evidence: `director-release-ios-certificate-readback.json`, `director-release-ios-profile-readback.json` and the public identity inventory.
- Another existing local distribution identity matches a current Apple certificate serial `2001D7702688287111C61425F906978A`. A temporary Mach-O probe initially reports no identity; with a temporary search-list inclusion it reaches signature replacement but waits for signing-key access and is terminated at fifteen seconds. Search settings are restored exactly. The human is asked to unlock that existing keychain and allow codesign access. No unrelated password was read, no key was exported, and no certificate or remote provisioning profile was created or revoked. iOS signing remains a real blocker.

- App Store preparation continues without claiming a complete submission set: the existing renderer generates thirty five-locale iPhone 6.5-inch previews plus ten per-product IAP review images in `builds/release/app-store-preview/`, explicitly using the permitted Android Pixel AVD source mode. All forty fully decode as 2778×1284 RGB; the five six-screen boards and ten-product board were personally viewed. Every combat frame retains the entire source viewport. The preview portrait pixel ROI matches exactly across all languages (SHA-256 `90d340ef…`, 22,358 green pixels each). These files are partial local previews; no native iPad proof, full App Store provenance, submission-ready manifest or upload is asserted. The tracked App Store images remain unchanged.
- Final post-candidate hygiene check passes: 1,924 tracked files, 35 clips within the 903KB maximum and all ten locked project settings. Production runtime/source remains the reviewed capture witness. The human PR signal is absent and the iPad tunnel REST service is unreachable at the final local preparation checkpoint.

## Final binary internal delivery (2026-10-02)

- Final signed release artifacts are preserved under
  builds/release/final-3.0.0-build16-11/: Android APK/AAB 3.0.0 (16),
  iOS IPA 3.0.0 (11). The IPA passes local and Apple remote validation,
  uploads successfully and is COMPLETE/VALID, then is assigned to the
  existing internal TestFlight group. Assignment is not a purchase test.
- Briefs 035/035b produce a separate binary-only Play internal updater.
  The director reproduces a newer-remote-code downgrade hole in round 1
  before any real store mutation. Round 2 blocks it before edit or intent.
  Independent registered tests pass 225/225; neutralizing the guard in a
  sanitized measurement copy fails both added cases, exact restore passes.
  Candidate module SHA-256 is
  32a61b554ca283097029b746aff8b6a46328ab6e8ab14ea4488d4bf72ba573b3.
  All four deliverables are judged and accepted via Muse.
- Play binary-only update commits internal code 16 on edit
  11168174040830595564. Independent post-commit track and all five listing
  /100 ordered image hash readbacks pass; durable receipt is APPLIED.
  Retained screenshots are explicitly historical gallery evidence, not
  final-runtime capture or native purchase evidence. No production
  promotion, listing/image/product write or review submission is done.
- The signed release APK is preserved before the fresh phone capture can
  replace the canonical APK path with a debug build. Existing canonical
  phone captures are also copied byte-exactly before recapture.
- New App Store screenshots are authorized by the user's earlier explicit
  renewal request. Actual title navigation/layout and every requested
  combat/shrine/hero screen changed versus the existing 2.0 gallery. Scope:
  five languages, six named screens each, iPhone and physical iPad sources;
  no unnecessary Android tablet recapture or existing Play media upload.
- PR 10 remains open without human review or merge. Native Play-installed
  and iPad Sandbox ten-product purchase checks are still pending; no E2E
  or public review completion is claimed. Full real-tree verification after
  tooling acceptance is running.

The user explicitly authorizes this submission to proceed with real-device
purchase verification unfinished, and confirms the iPad will remain
connected, landscape and unlocked for fresh captures. This overrides the
skill purchase gate only for this release; native evidence remains
NOT_DONE, never PASS. Both-store review submission authorization persists.
