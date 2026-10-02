# Brief 025: align capture copy pins with the current Keeper

## The ask
"너가봤을 때 어때 훨씬 쎄련되고 재밌어? 꼼꼼히 2~3번 점검해주고 괜찮으면 머지하고 스토어 스크린샷 등다 새로 올리고 직접 배포도 해줘"
The director is checking and capturing the renewed 3.0.0 game before release.

## Why, and what good feels like
The genuine new Keeper preview must pass strict capture validation. Its lantern shotgun description is correct, but the independent Node capture validator still pins the earlier damage-bonus description. Preserve the guard against stale or wrong-language screenshots.

## Where things stand
Current root includes accepted cannon correction, commit 9ead292. No production edits are required here. Full current-root pnpm verify passes. On the real Pixel_10 emulator, capture passes title and shrine, then fails in scripts/lib/capture-run-state.mjs:1754 with `Hero-preview live description differs from current-locale Keeper copy.` The live English description is `Lantern shotgun · 6 hearts · move -15% · dash CD +30% · Moonlit Ripple/Tenacious Life`; both the live source and expected source are HERO_KEEPER_DESC, description_copy_valid is true, locale en and ready true. The independent checker at line 451 and its test fixture at scripts/lib/capture-run-state.test.mjs:202 retain the pre-renewal description. apps/game/localization/moonlit.csv, apps/game/tests/test_shrine_portraits.gd and scripts/lib/store-graphics-boundary.test.mjs hold the accepted new five-language copy.

## Do
- Read all five authoritative current HERO_KEEPER_DESC rows and align the independent capture-run-state description pins and matching fixtures exactly.
- Add or extend a meaningful regression that constructs five-locale hero-preview proof from actual locale data, so changing only a self-consistent duplicated fixture cannot silently leave the live capture guard stale. Preserve independent wrong-copy/source/locale rejection tests.
- Record the narrowly confirmed capture defect, fix and measured checks in notes/plans/3-0-0-build-log.md. Correct the existing statement that no title recapture is planned: the user now requested changed title imagery as well. Do not claim new captures or store publication are finished.

## Do not
Do not edit apps/game runtime, CSV, scenes, art, audio, export presets or product prices. Do not weaken exact text/source/locale/readiness assertions, alter canonical atomic publication rules, create capture proofs, run device operations, touch git or perform any network/store action. Do not edit director workflow records. A root title readiness failure while two host-GPU AVDs ran was resolved by closing the extra AVD; do not change startup deadlines from that observation.

## Acceptance
- All five current live Keeper descriptions pass the capture validator with strict locale/source/readiness checks intact; the old damage-bonus wording and another locale's copy still fail.
- `node --test scripts/lib/capture-run-state.test.mjs scripts/lib/store-graphics-boundary.test.mjs` passes; an intentionally stale description pin must fail a current-CSV regression.
- Production runtime files remain byte-identical, so only capture input attestation changes.
- Notes distinguish authorization from completion and report only observed checks.

## Deliverables
scripts/lib/capture-run-state.mjs, scripts/lib/capture-run-state.test.mjs, notes/plans/3-0-0-build-log.md; another test only if genuinely needed for CSV parsing. Keep scope narrow and report exact commands/results.

## How the director will judge
Review the diff, independently run the related Node checks, demonstrate failure of the stale-pin negative control and restore it exactly. After acceptance the director will rebuild capture attestation and retry the real five-locale phone capture.
