# 4.0.0 App Review entry instructions (brief 141) — author-only note

`buildAppStoreReviewNotes` in `scripts/lib/app-store-release.mjs` generated
“No app account or demo login is required,” which no longer describes the
4.0.0 entry. The production entry (`ProductionEntry` + `ProductionHost` +
`GateEntry`) opens on the original title, and a tap raises a login chooser
over it. This round rewrites only the generated review note to match that
entry. No game, store-page, localization, version, or signing change.

## Actual entry, as the note now describes it

- Launch: the title screen shows Tap to start plus a Store door.
- Tap the screen to open the entry card, then Continue as guest. The game
  issues a permanent player ID, shown on the identity card.
- From the identity card: New expedition starts a run; Resume the gate
  continues when a saved checkpoint is listed.
- Sign in with Google and Sign in with Apple are optional ways to link or
  recover the same account (Account panel: Link an account). Core play,
  Store, Restore purchases, and resume all work fully as guest, with no
  developer demo account or password.
- Store sits on the title screen; Restore purchases sits in the Store
  footer and idempotently restores the seven non-consumables. Continue
  Coin consume/grant/resume semantics and the hero_bundle exclusion are
  unchanged, as are product IDs, prices, and contacts.

## What changed

- `scripts/lib/app-store-release.mjs`: entry + provider + Store paragraphs
  above replace the obsolete “no app account” sentence. The ten-product
  list, hero/supporter/lantern/coin/restoration paragraphs, and the 4,000
  character/byte guard are untouched.
- `scripts/lib/app-store-release.test.mjs`: the fixture-payload test now
  asserts the generated note walks the guest path (Tap to start, Continue
  as guest, permanent player ID, New expedition, Resume the gate, both
  providers, no developer demo credentials) and no longer contains the
  obsolete “no app account” claim. Assertions stay on the generated
  payload, not on a prose snapshot.

## Explicitly not done here

No device or sandbox purchase test, no Apple server provisioning, no
review submission, and no remote main merge. Those remain director-side
steps; nothing in this round claims them complete.
