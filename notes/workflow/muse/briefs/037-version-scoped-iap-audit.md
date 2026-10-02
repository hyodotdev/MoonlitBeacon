# Brief 037: use version-scoped IAP localization audit

## The ask
"심사 제출해줘 최종본으로 다 빌드해서"
The user authorizes final review submission on both stores and expressly skips unfinished native purchase verification for this release.

## Where things stand
All seventy strictly verified new App Store images are now uploaded. The actual apply creates version 2 of the first product successfully, then stops before further writes with: `remote IAP com.crossplatformkorea.moonlitbeacon.continue_coin localization is duplicated: en-US`.

Independent real GET shows version 1 APPROVED and version 2 PREPARE_FOR_SUBMISSION. The deprecated `/v2/inAppPurchases/{id}/inAppPurchaseLocalizations` returns ten resources: each of the five locales twice, once APPROVED and once PREPARE_FOR_SUBMISSION. The version-scoped `/v1/inAppPurchaseVersions/{id}/localizations` returns exactly the five correct IDs for each version, with no within-version duplicates. Apple documentation deprecates the unscoped endpoint in favor of the version-scoped endpoint:
- https://developer.apple.com/documentation/appstoreconnectapi/get-v2-inapppurchases-_id_-inapppurchaselocalizations
- https://developer.apple.com/documentation/appstoreconnectapi/get-v1-inapppurchaseversions-_id_-localizations

`auditAppStoreConnectApplyReadiness` calls the legacy base audit, which throws on unscoped duplicates before its legacy localization entries are filtered away. It then already has a separate strict version-scoped audit. That legacy intermediate work is inappropriate in this versioned apply path. No game change is needed.

Baseline independent checks after brief 036: 61 registered App Store tests, zero skips; full real-tree verify 494 Node tests, 52 game steps and 122 scripts, all required checks pass. All 667 game source hashes and seventy image hashes are unchanged. Actual submission is still not sent; Play code 16 is in review. Do not mutate stores or repeat uploads.

## Do
- Make the versioned apply preflight avoid deprecated unscoped IAP localization auditing entirely, and depend on its existing strict chosen-version localization audit. A narrow explicit option on the base audit, defaulting to existing legacy behavior, is a possible approach.
- Preserve standalone legacy audit defaults and duplicate rejection. Preserve chosen-version duplicate rejection, localization differences, exact ten draft IDs/states, approved-history handling and all source/build/price/availability/review guards.
- Add registered regressions using an APPROVED v1 plus PREPARE v2 and five duplicated unscoped locales. Exercise full apply readiness with an injected client: it must use v2-scoped resources, avoid the legacy path, keep v1 immutable, and produce the correct draft ID/localization plan.
- Negative tests: a duplicate locale within the chosen draft must still reject; changed draft text must produce a correction even when approved text matches. Default standalone behavior remains unchanged.

## Do not
- Pick the first duplicate or collapse locales by locale alone. Do not swallow duplicate errors or filter by localization state as a substitute for actual version identity.
- Change game, versions, assets, capture or provenance, screenshots, store metadata/catalogs, signing, confirmation logic or exact eleven-item review targets.
- Perform network/store/git/device actions. Do not recapture or rebuild. Existing uploaded images and the existing new draft must be reusable by normal GET reconciliation after the director accepts the fix.

## Acceptance
- Both registered App Store test files pass without skips, plus meaningful full versioned-readiness, within-draft duplicate and differing-draft-text regressions.
- Restoring legacy unscoped audit in apply causes the new mixed-history regression to fail. Exact restoration passes.
- The configured final payload still targets 3.0.0 (11), ten products and eleven review items. Version 1 is never a mutation/review target.
- Only scripts/lib/app-store-release.mjs, scripts/lib/app-store-connect-apply.mjs and the existing registered App Store test file(s) differ. Keep the smallest confirmed correction.

## Deliverables and judgment
The two audit modules and registered App Store tests only. The director independently reads the complete diff, runs the suite and negative controls, accepts through Muse, runs final real-tree verification and repeats actual GET-only readiness before resuming the already authorized submission.
