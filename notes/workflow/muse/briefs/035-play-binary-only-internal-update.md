# Brief 035: preserve committed Play media during a binary update

## The ask
“심사 제출해줘 최종본으로 다 빌드해서”

The director must upload the final corrected binary while preserving the
already approved and committed 3.0.0 store gallery. You implement tools;
the director alone builds, signs, reads the remote state and uploads.

## Where things stand
Current presets are Android 3.0.0 (16), iOS 3.0.0 (11). Build 15 and the
90 new 3.0.0 Play screenshots plus 5 listings are already committed on
internal. The only later runtime change is the reviewed non-visual circular
melee predicate; all 667 corrected runtime hashes still match the witness.
Assets, visual code, layouts, fonts and copy are unchanged. Native purchase
checks remain pending and production must not be promoted yet.

The existing full `apply-play-release.mjs` always deletes and reuploads all
100 listing images. Its package preparation requires fresh capture proofs,
which have correctly gone stale. Repo policy says to preserve existing
screenshots for non-visual fixes and build-number changes. Do not weaken
that full path or label historical captures as final-runtime captures.

## Do
- Add a separate binary-only **internal** update CLI/module that reuses
  already committed listings and images. Default is local check only.
- Use existing real AAB inspection (configured release signer, manifest,
  IAP/Billing, localized names, release resources) and current project/
  presets identity/version, freshness and immutable SHA-256 binding.
- Bind a dedicated confirmation token to current binary, release notes and
  exact retained local gallery/listing content. Require valid existing
  account-owner legal/config approval and internal-only scope.
- Immediately before mutation, GET actual committed internal/production
  releases and all five listings/100 ordered image hashes. Reuse is allowed
  only if the current same-version 3.0.0 internal release exists, the new
  code is strictly newer and every retained listing/image equals remote.
- Insert an edit, upload only the AAB, update only internal, validate and
  commit with ERROR_IF_IN_REVIEW. Independently read back exact new code and
  unchanged listings/images. Make a durable owner-only receipt before
  commit; uncertain commit must never be blindly retried or discarded.
- Keep this path incapable of touching metadata, images, prices, products,
  production or reviews. A source/gallery reuse decision is explicit in
  the CLI's mode/token; it is not fresh native or capture evidence.

## Do not
Do not run network, devices, builds or store operations. Do not edit
runtime, assets, presets, package.json, guides or guards. Do not forge,
rebind or modify existing capture reports/provenance, or relax the existing
full-package/check paths. Do not use the pending native evidence as a pass.

## Acceptance and deliverables
Use the smallest separate module/CLI, two read-only Publisher client methods
if needed, and meaningful regressions in the already registered
`scripts/lib/play-release-package.test.mjs`. Cover wrong identity/version/
signer or stale artifact, one changed/missing/reordered remote image or copy,
duplicate code, unexpected remote track, invalid confirmation, uncertain
commit, failed validation, unchanged-media readback and exact successful
mutation call set. Existing tests must still pass. Demonstrate at least one
negative control, restore source exactly and report every real exit code.
No unrelated docs/code edits and no caller-supplied production bypass.

## How the director will judge
Read every changed line, independently run the registered suite, mutate one
guard in the isolated copy to demonstrate failure, inspect current real AAB
in a local-only check, then perform only the user's authorized internal
update. Public submission remains gated by native purchase evidence.
