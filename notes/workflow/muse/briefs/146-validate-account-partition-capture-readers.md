# Brief 146: Validate account-partition capture readers

## The ask
“물어보지말고 끝까지 진행해줘 배포까지”
Finish the release pipeline while preserving existing player data.

## Where things stand
The real phone capture producer fails before its first launch while backing
up a valid account-partition file. `ANDROID_CAPTURE_PERSISTENT_DYNAMIC_PATTERN`
already permits uppercase account tokens, but `assertFileName()` in
`scripts/lib/android-capture-persistence.mjs` accepts lowercase only.
`decodeAndroidPrivateFileBase64()` and
`isAndroidPrivateFileMissingBase64Error()` therefore reject a valid synthetic
name such as `journey.MB-00000000000000000000000000000000.json`.
Existing dynamic snapshot tests use an in-memory reader without passing
through this production Base64 reader boundary, so they miss the failure.
The tree starts clean apart from this director brief. No game save was wiped.

## Do
- Make both native-file reader helpers accept precisely validated dynamic
  partition names with public MB IDs and mixed-case Firebase tokens.
- Add an integration regression that enumerates dynamic files, reads them
  through the real Base64 decoder/missing-file helper, snapshots mutations,
  restores them, and checks byte equality plus deletion of new partitions.
- Cover valid backups/revisions/rejections/cloud partitions and malformed
  names, separators, traversal, shell text, overlong tokens and suffixes.

## Do not
Do not widen the dynamic filename pattern, touch the fixed-file contract,
remove data-protection assertions, alter game code, author marketing assets,
touch signing/credentials or bypass capture attestation. Do not simply accept
every uppercase filename. Preserve the existing lowercase reader contract.

## Acceptance and director judgement
The synthetic public-ID and mixed-case UID names pass both reader helpers;
invalid lookalikes fail. The whole snapshot/read/restore regression passes,
fails when the original lowercase-only guard is restored, and passes again
after exact restoration. Run the Android persistence, capture-run-state,
capture signing and store-graphics boundary Node tests. The director reads
the entire diff and reruns those checks independently, then retries the real
phone producer. No changes outside the two persistence source/test files.

## Deliverables
`scripts/lib/android-capture-persistence.mjs` and its existing `.test.mjs`.
