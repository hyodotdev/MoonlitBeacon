# Brief 231: prepare the 4.0.1 store update

## The ask
“제대로 검증하고 /loop-review 돌리고 메인 클린하게 다 머지되고 배포까지마무리해줘 ios android 리뷰 받아”

Prepare the accepted gate-lodge and attendance work for a real new store
submission. The director handles review, git, builds and remote operations.

## Where things stand
- The accepted game, public docs, automatic-release policy and validation
  notes are locally committed. Root `pnpm verify` passed completely.
- A fresh read-only store audit found iOS 4.0.0 build 14 already
  READY_FOR_DISTRIBUTION, and Android 4.0.0 code 19 PUBLISHED on internal
  and production. Reusing the released display version is inappropriate.
  The director has selected 4.0.1, iOS build 15 and Android code 20.
- `buildAppStoreReviewNotes` still says the guest goes directly from the
  identity card into New expedition. The actual first entry now visits
  Lumi, claims a unique name online, practices movement/dash and departs.
- `createPlayBinaryOnlyUpdatePlan` rejects every display-version change.
  This prevents the new patch version despite preserving the uploaded
  gallery. The existing retained package refers to 4.0.0, and must stay
  intact; neither historical capture evidence nor images become fresh.

## Do
- Bump only the display version and counters in project.godot,
  export_presets.cfg (both Android presets and the iOS application keys),
  and the existing store-page release identity to 4.0.1 / 20 / 15. Preserve
  every locked engine/render/package/control value and all signing data.
  The preset is protected: the director will review its exact diff and
  use the normal named-path acceptance mechanism; do not change guards.
- Update generated App Review entry instructions to explain the actual
  guest / new-name / Lumi movement-and-dash / departure path, verified
  cached-name offline behavior, preserved living resume, terminal defeat
  and paid coin continue. Explain rolling twelve-hour attendance and
  optional local reminders accurately. Keep all ten sale IAP IDs and
  restore guidance, no demo password, and the 4000-character bound.
- Write concise truthful 4.0.1 What's New copy in the five existing store
  languages. Do not rewrite unrelated listing titles, descriptions,
  promotional copy, prices, product rows or image references.
- Extend the retained-gallery Play binary-only path narrowly to permit
  a strictly newer semantic display version as well as a newer code.
  Reject downgrades, malformed versions and inconsistent preset/package
  identity; preserve same-version replacement support. Verify the actual
  historical internal release against its retained name/code before any
  mutation. Bind the proposed identity and current five-language release
  notes into tokens and receipts, while checking retained listings and
  ordered image bytes against the historical package. Never mutate any
  image, listing, product or price. Keep remote-boundary protections.
- Append a version-scoped update to the existing privacy store audit:
  nickname/intro/attendance documents and the public Hall alias now exist.
  Preserve historical 4.0.0 facts as history; remove no old evidence.
  Explain the local-only unnamed escape separately from the normal online
  first-name path. Official definitions map nicknames to Play Name and
  screen names/handles to Apple User ID. Existing declarations already
  include Name and User ID; the director will verify the remote form.
  Sources: https://support.google.com/googleplay/android-developer/answer/10787469
  and https://developer.apple.com/app-store/app-privacy-details/.
- Register focused regressions for the changed review-entry instructions,
  counters and version transition, metadata/token binding, and retained
  gallery protections. Add a factual author release note describing this
  new-version retained-gallery path and a short build-log entry.

## Do not
- No gameplay/native/art changes or new assets. No marketing capture,
  canonical gallery replacement, fake updated provenance, credential,
  network, git-history, PR or store operation from your copy.
- Do not remove remote readback, readonly-version, releaseType
  AFTER_APPROVAL, signature, account-owner or bundle-freshness guards.
- No AGENTS/skill/runner/standing-order changes. No broad cleanup.
- Do not claim actual purchases, permission taps or twelve-hour delivery.

## Acceptance
- All app/export/store identities agree on 4.0.1 / Android 20 / iOS 15;
  all other protected preset and project values are unchanged.
- Generated review notes stay within 4000 characters and truthfully lead
  a fresh guest through the name room before the Arena, while explaining
  the existing saved-account path and attendance without false claims.
- Five-language What's New names the actual new room/name/attendance/
  defeat changes and passes `pnpm check:store-metadata`.
- Related registered App Store and Play suites pass. Focused regressions
  fail when the new room guidance is removed or a downgraded version is
  accepted, and pass after byte-exact restoration.
- Same-version binary replacement remains supported; valid newer-version
  reuse works; older/malformed/incorrect retained identities fail before
  mutation. Gallery bytes are unchanged and all image mutation paths
  remain unreachable in reuse mode.

## Deliverables
Minimal release identity, review-note, retained-gallery planner and tests
changes, existing release prose, and notes/plans/3-0-0-build-log.md. List
every changed file and every independent command needed for judgment.

## How the director will judge
Read the entire patch (protected preset twice), independently run related
tests and negative controls in your copy, compare all canonical image
hashes and locked values, accept only the reviewed named paths, then run
real-tree verification and build the final store binaries. No network
operation is delegated to the implementer.
