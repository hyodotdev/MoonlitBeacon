# Brief 039: audit review-ready versions without permitting metadata edits

## The ask
"심사 제출해줘 최종본으로 다 빌드해서"
Finish the authorized final store review submission. The user explicitly waives unfinished native purchase verification for this release.

## Where things stand
Briefs 036 through 038 are accepted. All 65 App Store tests pass independently; removing the new include causes the unchanged unsupported-target guard to fail. Game, final binaries, screenshot sources and seventy image bytes remain unchanged.

The real final version was PREPARE_FOR_SUBMISSION with a converged 106-none audit. Adding its app version item to the existing review submission succeeded and legitimately changed both the app version and its App Info to READY_FOR_REVIEW. All eleven items (app plus ten IAP versions) now have authoritative exact relationships. No submitted:true PATCH has happened.

A new real GET-only audit at 04:45 UTC reports ASC_APP_STORE_VERSION_NOT_ADOPTABLE for exact desired 3.0.0 READY_FOR_REVIEW, then incorrectly omits localizations and invents twenty create actions because the versionSelectionBlocker prevents reading them. The read-only App Info GET independently has one historical READY_FOR_DISTRIBUTION plus exactly one READY_FOR_REVIEW. Existing selectAppInfoForVersion can match the correct state.

The repository must distinguish verifying an exact, already-prepared review version from permission to edit its metadata. READY_FOR_REVIEW must not become an adoptable or editable metadata state. A submitted-state readback must also be usable for idempotent review verification, with the existing supported review states and exact item/build guards preserved.

## Do
- Add a narrow read-only audit path for the exact requested IOS/version in READY_FOR_REVIEW and supported submitted states (WAITING_FOR_REVIEW, IN_REVIEW, COMPLETING), so it reads actual App Info, review notes, version localizations, screenshot sets and build/IAP targets and compares every desired value normally. Do not substitute historical audit data or fabricated states.
- Preserve standalone default adoption behavior and the editable-state allowlist. Never adopt a different version in a review state. Unknown, unresolved, duplicate or ambiguous states/resources still fail closed.
- Wire the versioned apply preflight to this read-only capability. A metadata/build mutation in a review state must still refuse before any network write, even when a mismatch is found. Review-only submission may proceed only from a fully converged actual GET audit.
- Add registered injected-client regressions for the real transition from PREPARE_FOR_SUBMISSION to READY_FOR_REVIEW after add-for-review, fully matching metadata/images, exact state App Info selection, successful exact-target submission, and submitted idempotent readback. Prove a metadata mismatch in review state cannot mutate and unsupported/duplicate states are still blocked.

## Do not
- Add READY_FOR_REVIEW or submitted states to ADOPTABLE_APP_VERSION_STATES or editable-state guards. Do not suppress mismatches or unresolved entries, reuse stale audits, manufacture server state, or weaken eleven-target/build/confirmation checks.
- Change game, builds, versions, screenshots, capture/provenance, prices, catalogs or store state. No network/device/git actions; no recapture or rebuild.

## Acceptance and deliverables
Only scripts/lib/app-store-release.mjs, scripts/lib/app-store-connect-apply.mjs and existing registered App Store test files may change. All registered App Store tests pass with zero skips. Removing only the read-only wiring/path makes the transition regression fail; restoring exact bytes passes. The director independently reads diff, runs tests and negative control, accepts through Muse, then runs real-tree verify and fresh official GET audit before the original review helper transmits.
