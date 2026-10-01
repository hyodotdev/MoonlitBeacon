# Brief 026: align the consumer's Chronicle persistence contract

## The ask
"너가봤을 때 어때 훨씬 쎄련되고 재밌어? 꼼꼼히 2~3번 점검해주고 괜찮으면 머지하고 스토어 스크린샷 등다 새로 올리고 직접 배포도 해줘"
The director is preparing current 3.0.0 screenshots and release artifacts.

## Where things stand and the confirmed defect
Two corrected-root full verify runs pass. Phone (40 PNGs), seven-inch (30) and ten-inch (30) genuine five-locale captures finished and their original images were reviewed. `pnpm store:screenshots:play` nevertheless fails at apps/game/tools/build_store_graphics.py:2864: `Pixel phone permanent file list differs from the fixed contract`. The Node producer's exact ordered ANDROID_CAPTURE_PERSISTENT_FILES in scripts/lib/android-capture-persistence.mjs has 20 entries including chronicle.json and chronicle.json.tmp. The Python consumer tuple at line 517 has only the older 18 entries and is also aliased as the iOS list. Captures report the full 20 entries and byte-exact before/restored equality, including removal of capture-created Chronicle state. Existing tests construct fixtures from the consumer's own tuple, so this producer/consumer drift goes unnoticed.

## Do
- Align the Python ordered Android/iOS persistent-file contract with the accepted producer, preserving all entries and strict exact-set/hash/byte-restoration/signature checks.
- Add a meaningful cross-language regression to the existing registered boundary suite that loads the actual producer list and actual Python consumer, compares their complete ordered sets and pins Chronicle coverage. Add negative controls for missing Chronicle proof and mismatched Chronicle before/restored bytes rather than constructing every expected list from the consumer alone. Retain existing signature, settings, path, missing/extra-file rejection tests.
- Record the observed failure, narrow correction and measured test results in notes/plans/3-0-0-build-log.md. Say the generator is a pinned capture input: previous current captures become stale after this tools-file correction despite unchanged production runtime/pixels. Do not claim capture or submission completion after the correction.

## Do not
No game runtime, CSV, art, audio, export preset, version, capture producer or signing change. No weakened checker, dynamic acceptance of arbitrary report file lists, fingerprint exclusions, edited/forged capture proofs, hash refresh shortcuts or copied attestations. No device operations, captures, network, stores or git. Do not edit director records. Do not remove the old strict list constraint to make the current report pass.

## Acceptance
- `node --test scripts/lib/store-graphics-boundary.test.mjs scripts/lib/android-capture-persistence.test.mjs` passes.
- Removing either new entry from the Python tuple fails the independent cross-language regression. Genuine fixtures with missing Chronicle map entries or changed Chronicle restored hash still fail.
- All existing 20 producer paths are checked exactly, in the same order, for Android and iOS. Production runtime remains byte-identical; capture proofs remain unmodified. The director will make new attestations/captures after acceptance.

## Deliverables and judgment
apps/game/tools/build_store_graphics.py, scripts/lib/store-graphics-boundary.test.mjs, notes/plans/3-0-0-build-log.md. Keep scope narrow. The director reads the actual diff, independently runs the two suites and a stale-list negative control, then rebuilds authorized captures and invokes the unmodified strict generator/checker.
