# Complete the binary-only Play release path

## User request / current state

The user wants the canceled/reworked release shipped to both stores and says
not to take new screenshots. The director has persistent authorization to
submit and deploy. App Store now has an explicit retained-gallery path.
Google Play has `apply-play-binary-only-update.mjs` that verifies the committed
gallery byte for byte and uploads only the new AAB to internal. Both internal
and production currently carry 4.0.0 (17); the configured replacement is
4.0.0 (18). No remote actions belong to this implementer task.

The remaining Play gap: normal `createGooglePlayApplyPlan` requires a newly
prepared full package and `verifyManifestInputsAreCurrent`. The retained
package intentionally records 17, and a newly prepared full package demands
fresh capture evidence. Reusing it would select the old build; bypassing
the freshness verifier or relabeling the capture as fresh is unacceptable.

## One task

Provide a small supported promotion/review path for the **exact successfully
applied binary-only replacement**, using the existing promotion and review
mutation implementations in `google-play-publisher-apply.mjs`. Extend the
binary-only CLI/lib (or a focused companion if clearer), not the full image
apply mode. Explicit reuse flags/tokens and honest retained evidence remain.

The path must first rebuild/verify the current binary-only plan and read a
mode-0600 `APPLIED` receipt bound to its package, retained gallery digest,
new AAB SHA-256, new versionCode, and verified internal track. Reject missing,
unapplied, mismatched or stale receipt/artifact before credentials/network.
Use exactly that newly applied versionCode and notes; do not select 17 from
the retained manifest. Bind separate promotion and review confirmation tokens
to the new verified binary plan/receipt and operation; ordinary full-mode
tokens or binary-upload tokens cannot authorize them. Preserve existing
crash-safe receipts, exact remote internal/production identity checks,
ERROR_IF_IN_REVIEW promotion behavior and explicit review lifecycle readback.
The review path must retain the existing behavior for changes already
published/in review rather than blindly resubmitting them.

Promotion/review must never invoke AAB upload, metadata, image mutation,
prices, or products. Existing GET gallery verification can run where needed;
do not claim zero image endpoint calls. No recapture or provenance changes,
no fresh-capture label and no weakening of the normal package verifier.
Document exact local-check → binary apply → promotion/review commands and
receipt paths. Handle old receipts by refusing and explaining remote
verification/archival, never deleting them automatically.

## Acceptance / scope

Meaningful tests: missing/mismatched/stale/not-APPLIED receipt causes zero
network; wrong/cross-mode confirmation causes zero network; exact replacement
18 is passed to the existing production functions with the retained gallery
marker; race/readback failure is preserved; recording clients see no image
mutation/upload/metadata/product requests; the existing binary/full promotion
and review tests remain green. Use fixtures only, no network or real builds.

Only scripts/lib/CLI, related Node tests, and release documentation. Do not
touch any game file, counters, actor/tests/docs, other concurrent Muse work,
protected files, credentials, git history, stores, machine, or images. The
director will independently test and run the real operation after final
game approval. Keep changes focused; reuse existing production functions
rather than copy their mutation implementation.
