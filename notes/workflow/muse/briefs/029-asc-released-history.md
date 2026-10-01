# Brief 029: recognize released App Store version history

## The ask
The user said “스토어에 새로 다 제출도 해줘 스샷이랑” and then “했어 다 해줘”.
Finish the authorized 3.0.0 submission without mistaking released history for a competing submission.

## Where things stand
The director has uploaded iOS 3.0.0 (10), which Apple reports VALID, and is capturing native iPad evidence.
The official GET of the app's iOS version list returns 2.1.0 and 2.0.0, both READY_FOR_DISTRIBUTION (legacy READY_FOR_SALE), and no pre-release or in-review version.
Replaying those public state attributes through `canCreateNewAppStoreVersion` returns false because it demands exactly one released version.
Apple's primary guidance says the current version must be Ready for Distribution, rather than demanding only one historical released entry:
https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version
The existing test with two unidentifiable “live-a/live-b” resources must remain fail-closed if the records lack sufficient identity/version evidence.

## Do
- Inspect `scripts/lib/app-store-release.mjs`, its audit/version-selection callers, and the regression tests.
- Correct this confirmed false blocker narrowly. Recognize unambiguous released-only history with distinct valid iOS version identities/numbers, including the real 2.1.0 and 2.0.0 response shape. Keep duplicate, malformed, unknown, and competing submission states blocked.
- Add meaningful positive and negative regression cases through the audit caller as well as the predicate; test response ordering independence and retain adoption/review safety behavior.
- Run `pnpm test:app-store-release` and report the exact change and results.

## Do not
- Touch game runtime, graphics, capture producer/validator, manifest integrity, pricing, products, version numbers, credentials, signing, git history or the network.
- Remove or loosen unrelated safety checks, blanket-allow two unknown live versions, or modify the PR guard.
- Create or submit a remote version. The director performs remote operations only after independent judgment.

## Acceptance
- Real distinct 2.1.0/2.0.0 released-only history is safely recognized regardless of list order.
- A competing WAITING_FOR_REVIEW/IN_REVIEW/pre-release, unknown state, duplicate version, or missing identity/version evidence in multiple-live history cannot become safe through this change.
- Existing single-version and empty-app behavior remains as documented; adoption remains unambiguous.
- App Store package/apply tests pass without any skipped assertion, and the director can restore the old predicate in the copy to make the new history regression fail.
- No changes in `apps/game/`, capture contracts, package.json, stores, or other protected/watched paths.

## Deliverables
`scripts/lib/app-store-release.mjs`, relevant existing App Store regression tests, and the implementer report. No other files are needed.

## How the director will judge
Read the full diff, independently run the App Store regression suite in the copy, replay the real public response, and perform a negative control. Accept only this release-tool correction before re-verifying the real tree.
