# Brief 025b: distinguish runtime from capture-input freshness

Continue brief 025. The director accepted the three-file candidate after
independently running both Node files: 61/61 pass. The director also changed
only the English validator pin back to the earlier wording; the new CSV
regression fails with exit 1, and exact restoration matches SHA-256
269ca11d1f0f961b20fde2cdbc3082c2c4f7d9070d05f0f0b231518fe6d665ab.
The real-root whole verification is now running. No new tests are needed in
this correction, and both scripts/lib files must stay byte-identical.

Correct one material assertion in notes/plans/3-0-0-build-log.md: the new
entry says `pnpm check:store-screenshots` is unaffected by this change.
Production runtime bytes did stay unchanged, but capture-input freshness is
separate: scripts/capture-store-screenshots.mjs includes
scripts/lib/capture-run-state.mjs in CAPTURE_INPUTS, and
apps/game/tools/build_store_graphics.py includes the same file in its capture
contract. Thus old capture-input attestations are stale and the director
must rebuild that attestation before the real capture retry. Say that
precisely; do not imply the old capture proof still passes.

Only this one build-log paragraph and the new report may change. Do not run
another suite, author runtime/test/script changes, capture, use the network,
operate devices, or touch git. Report that the director's already completed
checks support the code, while this round corrects only the record. The user
has requested fresh imagery of changed screens; the stale attestation alone
is not the reason to recapture.
