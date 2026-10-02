# Brief 038: request review-item relationship linkage

## The ask
"심사 제출해줘 최종본으로 다 빌드해서"
The user authorizes final review submission and explicitly skips unfinished native purchase verification for this release.

## Where things stand
Android 3.0.0 (16) is published. App Store 3.0.0 (11) has all seventy final images, fifty version-scoped IAP localizations, ten distinct draft version IDs, and the exact build linked. Final real-tree verify passes 497 Node tests, 52 game steps and 122 scripts; all 64 App Store tests pass. Game/capture/image bytes remain unchanged.

The actual Apple submission now has eleven successfully added items (the app version and ten current IAP versions) in READY_FOR_REVIEW. The original readReviewItems GET requests fields but not include; the actual API returns each item id/type/state with no relationships at all. The helper therefore correctly refuses to submit as ASC_REVIEW_SUBMISSION_ITEM_UNSUPPORTED.

Independent real GET of the same endpoint with `include=appStoreVersion,inAppPurchaseVersion` plus the original fields returns all eleven authoritative relationship data objects and included resources. They map to the exact desired app-version UUID and ten current IAP-version UUIDs. Missing/unexpected/duplicate targets must still fail closed. Do not infer targets from opaque item IDs.

Endpoint documentation:
https://developer.apple.com/documentation/appstoreconnectapi/get-v1-reviewsubmissions-_id_-items

The director can use the existing review helper with an official GET client that adds only this supported include query argument, preserving the exact eleven-target verification, to finish the already authorized operation. The repository correction is the same narrow request fix for future use.

## Do
- Add the supported explicit include to readReviewItems so GET supplies actual appStoreVersion/inAppPurchaseVersion linkage. Preserve original fields, pagination and all review target/state/build/confirmation checks.
- Add a registered regression whose injected client returns ids/state without relationships unless the exact include is requested; with include it returns an authoritative eleven-item target set.
- Exercise normal submit and submitted-readback/idempotent paths as appropriate. Existing rejection of unidentified, unexpected, duplicated or missing targets must remain intact.

## Do not
- Decode opaque review item IDs, fabricate relationships, swallow unsupported-target errors or weaken the exact eleven-item check.
- Change game, build/version, images, capture/provenance, catalogs, prices, signing or stores. No network/device/git actions. Do not recapture or rebuild.

## Acceptance
- All registered App Store tests pass without skips, including the real sparse-fields/no-linkage response shape and include-dependent success.
- Removing only the include causes the new regression to fail at the unchanged unsupported-target guard; exact restoration passes.
- Only scripts/lib/app-store-connect-apply.mjs and the existing registered App Store test file(s) differ. The strict target set and original safeguards remain unchanged.

## Deliverables and judgment
The smallest request change and its registered test. The director reads the diff, runs the suite and an independent negative control, accepts through Muse, then runs final real-tree verification and CI. Actual store operation evidence remains separate from fixtures.
