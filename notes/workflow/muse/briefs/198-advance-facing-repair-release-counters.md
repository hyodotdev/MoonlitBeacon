# Brief 198: Advance the facing repair release counters

## The ask
“ios배포해줘” remains the active release request. The user then reported that side faces are much smaller than front/back faces, so the director is repairing and reviewing those assets before submission. User authorization to finish the review loop, merge and deploy persists. The existing store gallery must remain unchanged.

## Measured release state
The director independently read App Store Connect after deferring submission: app6796293839 version4.0.0 is PREPARE_FOR_SUBMISSION, linked build13 is VALID, and the latest numeric uploaded counter is13. The next available iOS build is14. Android presets currently both carry versionCode18, the last uploaded package. Keep the marketing version exactly4.0.0.

## Do
Change exactly three integer settings in apps/game/export_presets.cfg: both Android version/code values18 to19, and iOS application/version13 to14. Leave both Android version/name and iOS application/short_version as4.0.0. Preserve every other byte, signing/channel setting, bundle identity and renderer.

## Do not
No game code, assets, scenes, tests, docs, gallery, manifest/provenance, credentials, version-lock rules, engine locks, package names, network, native builds, stores or git operations. The director owns all build/submit operations and explicitly reviews this protected file before acceptance.

## Acceptance and deliverable
Exactly apps/game/export_presets.cfg changes, with precisely those three one-line replacements. Android presets agree on19; iOS reads14 through application/version. The marketing version remains4.0.0 everywhere. Return git diff --check and exact diff statistics. No historical release evidence is rewritten.
