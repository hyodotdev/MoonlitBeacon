The 3.0.0 renewal gives each run a purpose: light the road that lets Nari return to Lantern Hollow. Rebuilt combat, characters, maps and presentation carry that story through an expedition, its ending and the optional Depth stretch.

## Changes

- Replace the title, HUD, shrine, shop, cards and results, with original art for six heroes, seven regular spirits and twelve guardian forms. Preserve automatic attacks, the floating joystick and landscape controls.
- Give each hero a distinct primary weapon: broad sword, alternating twin blades, five-pellet lantern shotgun, delayed cannon blast, orbiting scythe or piercing rifle. Increase movement responsiveness and dash availability; keep prices and visual tiers out of weapon damage.
- Build six terrains with route forks, cover, place clues, dim/lit motifs and guardian encounters. Add mutations, formations and nine skills while retaining projectile and node budgets.
- Connect Nari and Lantern Hollow through three acts, an epilogue, hero voices and forty Chronicle entries. Preserve player progression and IAP save contracts. Complete the main story after cycle eight; early return and defeat have separate lines, and Depth is voluntary. Paid heroes and complete memory collection are unnecessary for the ending.
- Protect discovery reading time when a beacon also opens a fork or summons a guardian. Keep route captions clear of the hero/HUD and separate the ending's Road detail from score rows.
- Use three arena tracks and three faster guardian tracks in separate shuffled bags, without adjacent repeats. Rotate at whole phrases and preserve pause, encounter and release transitions. Add distinct weapon, hit, kill and growth cues with bounded voice overlap.
- Give ordinary barrages separated volleys, gaps and arrival quiet time. Retain guardian warnings, collision, damage protection and the shared bullet cap.
- Align reference docs and five-language store descriptions with the game. Preserve all one hundred IAP metadata rows and purchase/restore behavior. Commit ninety refreshed Play image candidates for the six visibly changed marketing screens.
- Fix the split-tick cannon effect budget, independent Keeper capture-copy pins, Chronicle capture persistence and phone framing that cropped the dialogue/dash controls. Add regression and negative controls without relaxing acceptance gates.

## Validation

- Renewed whole-branch loop review ends with two consecutive rounds finding no confirmed defect. A proposed continuation-race correction is rejected because its failed fixtures skip production timing; the original code separately passes 977 natural continuation/discovery checks.
- Five corrected-root `pnpm verify` runs pass. The latest includes all 52 game steps (two imports and fifty game scenes), 122 script compilations, 470 Node checks across sixteen groups, five-language locale/store metadata, skills, hygiene, deterministic assets/store graphics, docs build and internal anchors.
- Late-game cannon regression: 73 checks, forty spirits and a 1,200-node cap; the latest Lv40 peak is 1,186. Disabling the split-tick correction fails its regression; exact restoration passes. These are host measurements, not mobile frame-rate claims.
- Windowed primary-weapon diagnostics passed 729 observations. Four facings/aims, actual hits, gun flight and cannon recoil were observed; 192 hero motion frames, 112 spirit cells, 200 guardian cells and settled five-language beacon panels were inspected. These are desktop diagnostics.
- Live audio checks cover six decoded loops, 3,000 draws per pool, whole-phrase rotation at time scales 1/3, pause/resume, simultaneous weapon cues and release. The bounded maximum-volume fixture peaks at 0.902 without clipping.
- Six-hero baseline bots cover 24.34 simulated minutes, 1,432 kills and no stuck state. Three ranged heroes finish the first cycle and three melee heroes are defeated under this policy/seed. The paired guardian cohort completes all six fights; the corrected Knight sample separately completes a first loop. These samples do not establish universal human balance.
- All 667 reviewed runtime files match the final witness. All 100 IAP metadata rows match main field-for-field. Asset inventory is 276 files / 30,771,043 bytes. Original art/audio and unchanged marketing images are preserved.
- Local signed Android artifacts are inspected for package/version/signer and channel isolation: direct APK and Play AAB are 3.0.0/code 15. Tests/tools are excluded; the direct channel excludes Billing/IAPKit. Artifact hashes still match the independent inspection records.
- Phone and both Android tablet capture reports pass strict persistence, source and semantic checks. Ninety final RGB Play composites pass deterministic checks; all fifteen locale/device review boards were inspected. Internal 3.0.0 (15) is now published on Play. Independent remote readback confirms all ninety screenshot hashes and five-language listings match the inspected package.
- See [the renewed loop-review record](notes/workflow/muse/loop-review-3-0-0.md) and [release evidence](notes/workflow/muse/release-3-0-0-director.md) for commands, negative controls and limits.

## Release boundaries

- Play internal 3.0.0 (15), ninety new screenshots and five-language descriptions are applied. Production still carries 2.1.0 (14); no production promotion or review submission is claimed. Unchanged graphics and existing App Store images remain byte-identical.
- Physical-device visual/play confirmation and native purchase checks remain pending. Emulator/desktop results are not the physical Pixel 10 direction matrix or native ten-product purchase evidence.
- Thirty iPhone and ten IAP preview images use the explicit Android Pixel AVD source mode. Physical iPad capture is pending, so the combined screenshot check fails on missing App Store provenance.
- Normal iOS 3.0.0 (10) archive and distribution IPA pass, including AppIcon/Assets.car, package identity, source freshness, entitlements and resource boundaries. Apple remote validation and actual TestFlight upload pass; the official upload readback confirms PROCESSING with zero errors/warnings. New Mac-owned development/distribution certificates and a matching App Store profile resolve the old signing blockage without revoking existing certificates. Processing completion and public review are pending. The isolated iPad capture starts successfully, but the physical framebuffer is portrait, so its untouched landscape proof rejects the image. No App Store screenshot upload or fabricated capture is claimed.
- The title-transition suite passes but prints a 33-object teardown warning. Verbose inspection identifies zero-reference `RefCounted` instances without an audio-node/resource leak; the cause remains unestablished. The ordinary game smoke check is clean.
- Analytics remains off by default. Native E2E, any applicable Firestore deployment, public store review submissions and the release tag are subsequent release gates. Current submission evidence is in [the store operation record](notes/workflow/muse/store-submit-3-0-0.md).
- The user approved branch publication and PR creation. GitHub CI will be checked on the published head before a merge decision; this PR does not claim a completed store release.

Implementation was carried out by the repository's configured Muse implementer. The director supplied briefs, reviewed the diffs and ran independent checks.
