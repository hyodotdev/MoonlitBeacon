# Hero facing repair: director review

## Request and release boundary

The user reported that the basic hero's profile face was much smaller than its front and back views, and asked whether the other heroes had the same problem. All six heroes were audited at equal world scale. Earlier explicit authorization covers the review loop, PR, push, merge and replacement store release. Marketing version remains 4.0.0, with iOS build 14 and Android versionCode 19. Existing store screenshots and IAP review images are retained by the user's instruction. Physical purchase verification remains explicitly waived.

## Findings and accepted implementation

Warden, Knight and Eclipse had genuinely undersized profile heads. The implementer calibrated their canonical painted donor heads uniformly, rather than stretching the whole body or swapping in frontal artwork. The corrected head is shared by walking, standing and articulated attacks. Other heroes, front/back artwork and portraits are unchanged. Measured side/front face-height and skull-width ratios changed from 0.80/0.74 to 1.15/0.91 for Warden, 0.60/0.89 to 1.00/1.05 for Knight, and 0.86/0.88 to 1.00/0.96 for Eclipse. Natural profile narrowing and the unaffected heroes' hair/beard occlusion are reviewed separately.

Knight's standing cloak also had a transparent horizontal slit. The first correction retained part of the former gray rear shin and accepted transparent cloth with hidden RGB. The director rejected that candidate and continued the same implementer run with brief 199. The accepted correction joins the blue/gold cloak and excludes the old gray leg fragment. The registered continuity test requires alpha >= 200 with RGB tolerance 40. Actual maximum RGB drift is 6 at blended joins; the implementer report's phrase "zero drift" does not establish byte equality there.

Accepted runs are 20261005-2028-harmonize-hero-faces-across-facings, completed through correction brief 199, and 20261005-2105-advance-facing-repair-release-counters. The director read the complete final 1434-line product patch, ran independent checks in the isolated copy, dry-applied and accepted it through the runner. The counter run changes only the two Android version codes and the iOS build counter. Briefs 196–199 and the audit preserve the rationale and rejected alternatives.

## Independent source and motion evidence

- All 192 source cells were inspected at 4x nearest: six heroes, four facings, idle/walk, four frames. The final eight Knight side idle cells were reviewed again; the other 184 reconcile byte-for-byte to their reviewed candidate.
- All 192 canonical head bands and 24 walk/idle head matches pass independent measurement. Actual attack face cores retain idle identity. All 24 original small-profile controls fail both calibrated bounds.
- The six-case registered stance suite passes. Independent negatives reject transparent cloth and a restored original gray shin pixel in every one of the eight Knight side idle cells.
- Face tests pass independently on macOS and offline Linux. Full generation produces all 89 committed RGBA outputs exactly on both platforms, with equal cross-platform RGBA digests.
- Real Player headless motion passes 1416 checks over 103 samples. Two desktop movies contain 2838 original 60fps frames each, with and without attack effects. The director inspected 36 contact pages covering 60 consecutive original frames for each of 24 attack facings in both modes, plus complete mover overviews for all six heroes.
- Desktop title movement was inspected over 20 seconds, including a consecutive six-second sequence. Faces/body scale remain stable when walking changes to standing. Forced harness teardown warnings are retained as harness diagnostics, not presented as a clean production shutdown.

Evidence is under builds/verify/hero-facing-round3-source-candidate, hero-facing-round1-director-head-proof.json, hero-facing-round3-director-cloth-negatives.json, hero-facing-round3-determinism-proof.json and hero-facing-round3-render-snapshot. These are internal QA artifacts, not marketing captures.

## Root verification and packed native artifacts

The full root pnpm verify passed with exit 0 and zero Node failures. Game, IAP, save/auth, UI, locale, assets, documentation, anchors, NUL stripping, skill mirrors and hygiene passed, including a clean production headless smoke check. The receipt is builds/verify/hero-facing-root-verify-receipt.json; log SHA-256 is 9821472ed6e8e2943be9db558d769d277c97107d4942abf0dc422b451364c414.

The separate store-capture check reports the expected changed runtime fingerprint after this visual correction. Independent readback confirms all 160 retained store image files remain byte-identical. No capture pipeline or store image upload was run.

Android 4.0.0 (19) was built through the channel-isolating wrapper. Its APK SHA-256 is 83709692e4c0bd13b1884ba259e7455cc538f0fdaa00ddf7298c64f2413a969d. All 94 packed PNGs and six rig JSON files match the final root import payload. Preserving upgrades on Pixel_10 emulator and the connected Galaxy Z Flip5 retain the original game files exactly; neither uninstall nor SDK preference reset is used. The attached physical Android is a Galaxy, not a Pixel 10.

Normal iOS development export/build succeeds with the asset catalog and AppIcon, Apple sign-in entitlements and native artifact checks. Build 14 was installed on the connected iPad without uninstall; pre/post-install game files match. All 100 corresponding packed asset/rig payloads match the final source/imports. The existing signing identities were recovered by unlocking the existing release keychain and temporarily adding it to the user search list. No certificate was created or revoked, and no access-control partition was weakened. Restore the recorded search list after distribution signing.

## Actual iPad observation and preservation limits

QuickTime was set to the iPad screen source and an actual 54.807667-second title recording was captured. All five contact pages, covering 27 original sampled frames, were inspected. The six intro heroes retain consistent face/body proportions during walking and stopping. This is actual iPad title evidence, not an all-24-direction gameplay matrix. Evidence: builds/verify/hero-facing-14-ipad-title-review/proof.json.

Account-scoped journey and backup files remain byte-identical through the preserving upgrade and a cold title launch. The user confirmed Continue on the previous build. This correction does not claim a new build-14 Continue gesture, new Google/Apple authentication, or a new purchase test. Evidence: builds/verify/hero-facing-14-ipad-cold-start-journey-proof.json.

## Native visual review and release status

The first complete emulator procedural matrix has all 24 bound still observations, six walk/dash movies and zero current-process native errors, but several trees obscure silhouettes. Those images are not approved as visual evidence. Original probes, failed routes and their exact restore proofs are retained. An input-closed route was cleaned up with byte-exact game restoration. The final selected Pixel_10 emulator review approves all 24 facing stills and six complete walk/dash movies on clear real terrain. One Warden movie that touched a pine is excluded and replaced by a fresh clear-corridor movie. Five other movie records and all 24 distinct facing cells reconcile to the earlier reviewed capture. Every direction exposes four distinct actual walk frames. Each run restores game files exactly, leaves SDK preferences untouched, and has zero current-process native errors. The assembled evidence is builds/verify/hero-facing-19-emulator-final-director-proof.json. No proof predicate was relaxed.

The final Galaxy Z Flip5 matrix also passes director visual review: 24 bound full-body facing cells and six walk/dash movies. All 57 consecutive-frame contact pages, six complete 2fps overviews and six four-facing rows were inspected and SHA-256 pinned. Every direction exposes all four actual walking frames. Current-process native logs contain zero errors; game files are restored byte-exact and SDK preferences remain untouched. The final evidence is builds/verify/hero-facing-19-galaxy-final-director-proof.json. Earlier 24px input probes fell within the physical device touch slop and are excluded; actual 36px gestures produced all four frames without changing product code or weakening proof predicates.

Two final review rounds are clean: source/desktop regression and visual review after the accepted correction, then packed native artifact and emulator/physical Android visual reconciliation. No further confirmed product defect remains. This establishes native Android direction/motion coverage; the iPad observation retains the title-only scope described above.

At this recorded checkpoint, pending: final PR/CI/review/merge; distribution IPA build 14 and AAB 19 from merged main; retained-gallery binary-only store submission and actual review-state readback. Release receipts remain ignored operational artifacts so main can remain clean.
