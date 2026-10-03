# Brief 141: Update generated App Review entry instructions for 4.0.0

## The ask
“로그인이랑 스토어 검증하고 메인까지 다 머지하고 확실하게 커밋한거 없게 된 상태에서 배포까지 진행해줘 리뷰 제출해”
Make the generated review submission accurately explain guest entry, account IDs and optional provider login.

## Confirmed defect
scripts/lib/app-store-release.mjs still generates “No app account or demo login is required.” The 4.0.0 ProductionHost has a Tap to start login chooser, guest entry with a permanent player ID and optional native Google/Apple sign-in. Reviewers must be able to reach the game, Store, restore and resume without obtaining an external demo account. No external-account/password requirement should be invented.

## Do
Read current production entry/shop behavior and rewrite the generated review note in clear English: Tap to start, choose guest to get a player ID, choose New expedition/hero to play, or Resume the gate when a checkpoint exists. Google/Apple are optional ways to link/recover the account; no developer demo credentials are necessary for core play or purchases. Describe where actual Store/Restore navigation is now, with the smallest useful reviewer instruction. Preserve existing ten-product consume/grant/restart semantics and contacts. Notes must not claim actual device/purchase tests, Apple server provisioning, review submission or remote main merge complete.

Update meaningful existing tests only where they assert the note contract; ensure generated review note contains the actual guest path and no obsolete “no app account” claim. Use behavior verification for payload generation rather than a standalone prose snapshot. No game/runtime/image changes, credentials, stores, networking, git or version changes.

## Deliverables
scripts/lib/app-store-release.mjs, its related existing test file if needed, and a short distinct notes/release/four-zero-review-entry.md. Do not touch store-page.md or store-localizations.csv, which are being independently corrected in another implementer copy.

## Acceptance
Director reads full diff, generates the review-note payload using existing fixtures, and runs App Store release and related apply tests. All identities/prices/contact boundaries unchanged. No guard weakening or store activity. The generated current note truthfully walks a reviewer through guest entry and existing Store/Restore.
