# Brief 032: authorize the verified current App Store release

## The ask and confirmed defect
The user requested a complete 3.0.0 store submission, then said “했어 다 해줘”.
The director found `EXPECTED_RELEASE = { buildNumber: '9', version: '2.1.0' }`
in `scripts/lib/app-store-connect-apply.mjs`. `assertAppStoreApplyAuthorization`
unconditionally rejects a different pair before evaluating the manifest-bound
confirmation. Therefore a valid current 3.0.0 manifest cannot be applied. The
current exported display version is 3.0.0; iOS build 10 was uploaded, and a
specific next-build 11 configuration edit is awaiting human authorization.
Do not change that protected configuration in this task.

## Do
- Correct only this obsolete authorization restriction. Tie authorization to
  the freshly verified current payload/export metadata and exact manifest-bound
  confirmation, rather than the past release's literal pair.
- Preserve manifest/payload equality, checksums, target identity, sensible
  release fields, apply versus review purpose, screenshot provenance checks,
  GET revalidation and all existing mutation boundaries. Do not turn a missing
  or malformed target into an accepted release.
- Add focused regression coverage through the real authorization seam for
  3.0.0 with build 10 and a newly generated build 11 payload. A token for the
  old build must not authorize the new build; stale payload, tampered manifest,
  malformed target and apply-token-as-review must still fail.
- Read the actual authenticated wrapper to confirm the payload is built and
  re-verified from current local inputs before mutation. Use the smallest clear
  change. Do not introduce another literal version/build pin needing another
  patch on the next upload.

## Scope and verification
Only the App Store apply module and the existing App Store Node tests change.
No game, build numbers, capture code, assets, product definitions/prices,
network, credentials, store mutations or git operations. Keep all existing
test assertions unless this specific obsolete release pin contradicts them;
explain any necessary fixture update. Measurement output goes only in an
ignored directory inside the copy. Run the existing App Store test commands,
hygiene, and a negative control restoring the obsolete restriction so the new
valid-current-release regression fails. The director will independently judge
and test the result. Do not create a substitute suite or mask a failed exit.

## Acceptance
A valid 3.0.0 manifest with its own current-payload confirmation reaches the
existing authorized path. A confirmation for build 10 cannot authorize build
11, and purpose, provenance, identity and integrity boundaries stay enforced.
The negative control proves this task fixes the actual 2.1.0(9) rejection.
