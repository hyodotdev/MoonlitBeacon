# Brief 036: continue from approved IAP version history

## The ask
"심사 제출해줘 최종본으로 다 빌드해서"
The user authorizes final store review submission and explicitly skips unfinished native purchase verification for this release.

## Where things stand
The verified final release is Android 3.0.0 (16), iOS 3.0.0 (11). Google Play production is in review. The director has generated and independently reviewed all seventy new App Store images. The unchanged strict App Store checker and local manifest preparation pass. No App Store write has occurred.

Real GET-only ASC apply preflight rejects all ten existing IAPs with `ASC_IAP_VERSION_STATE_UNSUPPORTED`. An independent GET of each product's `/v2/inAppPurchases/{id}/versions` confirms exactly one version per product: numeric `version: 1`, `state: APPROVED`. These approved histories have no active draft or in-flight review. Prices, availability and existing product metadata match the manifest.

`auditVersionedIapLocalizations` in `scripts/lib/app-store-connect-apply.mjs` currently refuses any nonempty history without a resubmittable draft. That incorrectly prevents creating a fresh review version after approval. Apple documents creating a version to snapshot current localized metadata and review images:
- https://developer.apple.com/documentation/appstoreconnectapi/post-v1-inapppurchaseversions
- https://developer.apple.com/documentation/appstoreconnectapi/working-with-in-app-purchase-versions

## Do
- Add narrow support for a fully approved existing IAP history with no active draft: plan a fresh version using the validated next version number, with current review-image prerequisites, then use existing creation and GET convergence logic.
- Keep approved historical versions immutable and distinct from the new submission's exact ten draft version IDs/states.
- Preserve fail-closed handling for unknown/malformed, in-review or otherwise unsupported states; duplicate or invalid version numbers must still stop before a mutation.
- Add registered regressions that reproduce the real numeric version-1 APPROVED history for all ten products and verify the complete reconciliation/review target contract. Include meaningful negative cases for mixed unsupported history and invalid numbering.

## Do not
- Edit game, export presets, capture tools, proofs, canonical images or metadata/product catalogs. Do not rebuild final artifacts or recapture any screen.
- Weaken confirmation, screenshot provenance, source integrity, price, availability, build-association or exact eleven-item review checks.
- Treat APPROVED as an editable or directly resubmittable draft. Do not perform network/store/git operations.

## Acceptance
- Existing App Store tests pass without skips plus new cases for approved history and rejection before mutation of invalid/unsupported histories.
- An approved-only version-1 fixture plans create version 2; after creation its PREPARE_FOR_SUBMISSION ID is the review target and version 1 is never edited or submitted.
- Removing the narrow history support causes the new positive regression to fail; restoring it passes. Invalid numbering and in-flight-state negative cases still fail closed.
- Only the apply module and its registered test file differ. Game/capture/source proof bytes remain unchanged.

## Deliverables and judgment
The apply module and its existing App Store release/apply test file only. The director reads the complete diff, runs the registered suite and an independent negative control in the sanitized copy, then accepts through Muse and reruns real GET-only preflight. Make the smallest confirmed correction.
