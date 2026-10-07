# 4.0.1 store update note (brief 231) — author-only note

A read-only store audit found iOS 4.0.0 build 14 already
READY_FOR_DISTRIBUTION and Android 4.0.0 code 19 PUBLISHED on internal
and production, so the gate-lodge and attendance work ships as a new
patch: display 4.0.1, Android versionCode 20, iOS build 15. This round
changes release identity, reviewer guidance, release prose, and the
retained-gallery Play planner only. No game, art, sound, listing,
image, product, price, signing, or guard change.

## Identity (4.0.1 / 20 / 15)

- `apps/game/project.godot`: `config/version` 4.0.0 → 4.0.1.
- `apps/game/export_presets.cfg`: both Android presets
  `version/code` 19 → 20 and `version/name` 4.0.0 → 4.0.1; iOS
  `application/short_version` 4.0.0 → 4.0.1 and
  `application/version` 14 → 15. Every other preset line is
  byte-identical (package, signing, team, SDK, render, control).
- `notes/release/store-page.md`: itch.io Version row and APK file row
  to 4.0.1. All other listing copy untouched.

The `project.godot` edit changes the capture `runtime_sha256`, so
`pnpm check:store-screenshots` goes red; the gallery is intentionally
reused (see below), never recaptured here.

## Reviewer guidance

- `buildAppStoreReviewNotes` (`scripts/lib/app-store-release.mjs`):
  a first guest entry no longer goes straight to the Arena. The note
  now walks the gate lodge — Lumi greets, one unique adventurer name
  is claimed over a connection, the player walks and dashes on the
  open floor, then steps through the moon gate — followed by the
  returning-account path (device-cached verified name, offline
  identification, living resume, sealed defeat with a one-coin
  revive) and rolling twelve-hour attendance with optional local
  reminders. Ten IAP IDs, restore guidance, no demo password, and the
  4,000-character bound are unchanged.
- `notes/release/google-play-review-entry.txt`: same lodge path in
  one short Play Console paragraph.

## Release prose

- The five Google Play release-note blocks and the five App Store
  What's New paste blocks in `notes/release/store-page.md` are now
  4.0.1 copy naming the new room (gate lodge), name (adventurer
  handle), attendance (two coins per rolling twelve hours), and
  defeat (sealed runs, one-coin revive) changes. Titles,
  descriptions, promotional copy, prices, product rows, and image
  references are untouched. Every note stays within the 500-character
  Play limit; `pnpm check:store-metadata` passes.

## New-version retained-gallery Play path

- `createPlayBinaryOnlyUpdatePlan`
  (`scripts/lib/play-binary-only-update.mjs`) now permits a strictly
  newer `major.minor.patch` display version next to a strictly newer
  versionCode, in addition to same-version replacement. Downgrades,
  malformed versions, and AAB/preset/project identity mismatches
  refuse before any mutation. The historical internal release is
  still re-verified against its retained name/code immediately before
  mutation, and remote-newer, duplicate-code, listing-locale, and
  ordered-image-hash gates are unchanged.
- Release notes: a newer display version carries the current
  five-language store notes; a same-version replacement keeps the
  retained notes and refuses when the store page notes drifted. The
  store page left byte-currency for this reason, but current listings
  (title, short, full per locale) must equal the retained gallery,
  so listing changes still refuse and still need the full path.
- Binding: the proposed code/name plus the served notes are bound
  into the check/apply confirmation token (as before) and now also
  into the update receipt via `releaseNotesDigest` and
  `retainedVersionName` (receipt schema 1 → 2). Promotion and review
  tokens keep binding the served notes. No image, listing, product,
  or price mutation path was added; the Publisher client allow-list
  is unchanged.

## Privacy audit

- `notes/release/privacy-four-zero-store-audit.md` §9 scopes the new
  `mb_adventurers_v1` / `mb_names_v1` / `mb_attendance_v1` documents
  and the public Hall alias, the seven-step deletion commit, and the
  local-only unnamed escape next to the normal online first-name
  path. §0–§8 stay the untouched 4.0.0 record. Per the
  director-read official definitions, nicknames map to Play Name and
  screen names/handles to Apple User ID; both are already declared,
  and the director verifies the remote form.

## Tests

- `scripts/lib/app-store-release.test.mjs`: the fixture-manifest test
  asserts the new lodge/name/attendance fragments and the removal of
  the old direct path; a focused test pins every room-guidance
  fragment plus the 4,000-character/byte bounds; a real-tree test
  asserts project/preset/store-page identity agreement.
- `scripts/lib/play-release-package.test.mjs`: display-version
  comparator units; newer-version plan acceptance with current-note
  binding and token rebind; newer-version apply proving the served
  notes ride the track update and the receipt binds identity plus
  notes digest; same-version replacement keeping retained notes and
  refusing listing drift; the old reject-newer-version case is now a
  downgrade/malformed rejection.
- Negative controls: removing the room guidance fails the focused
  review test, and disabling the downgrade guard fails the version
  test; both pass again after byte-exact restoration.

## Explicitly not done here

No device or sandbox purchase test, no twelve-hour delivery or
permission-tap claim, no Apple/Google provisioning, no review
submission, no binary build, and no remote or git operation. Those
remain director-side steps; nothing in this round claims them
complete.
