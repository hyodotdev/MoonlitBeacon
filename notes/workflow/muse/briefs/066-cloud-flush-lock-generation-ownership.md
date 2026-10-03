# Brief 066: old account replies must not unlock the new account's upload

## The ask
Continue the owned-journey coordinator only. Round 059 independently passes 704 cases. The three original director reproductions now behave correctly: foreign progress is a conflict with no checkpoint overwrite; local unpaid recovery grants 15 once; a newer seal survives an older commit.

## Confirmed defect
The director added an ignored real orchestration probe with two separately gated senders. Account A is ready, its flush is parked on a GET; configure B, make B ready, park B's own flush on another GET. `flush_running` is true for B. Open A's sender while B stays blocked. A correctly returns cancelled/stale-reply, but B's `flush_running` becomes **false** even though its own sender has not answered. Opening B later lets its original flush finish normally.

Cause: stale exits in `_flush_async(captured)` unconditionally assign `_flush_running = false`; that flag belongs to the newer generation after reconfiguration. This allows another flush/choice/restore to overlap B's outstanding upload and invalidates the one-owner contract. The existing switch-during-await test did not start the new account's upload before the old reply.

## Do
- Make release of the upload lock conditional on ownership (generation plus operation ticket if needed), in every early, success, failure, stale and retry path. A late old completion must not reset any newer account's upload lock or mutable save state.
- Audit the analogous old-generation completion bookkeeping in transport and checkpoint helpers. Fix only concrete ownership defects with deterministic interleaving coverage, not broad refactoring.
- Add a permanent two-sender test that genuinely runs two generations concurrently, proves A retires while B remains locked, refuses a third flush/restore/choice during B's wait, then proves B completes and releases its own lock. Also cover `close` and late replies without emitting new active-account state.

## Scope and acceptance
Same coordinator-owned paths as briefs 053/059; no native/UI/art/arena/shared runner/package/project/network/store/device/history. Preserve all 704 cases, all new baseline/receipt/pending behavior and the exact host contract. Director will rerun the gated probe, coordinator suite, related cloud/Journey suites and real Firestore rules suite before acceptance. No polling loop in production; test gates may wait frames to control interleavings.
