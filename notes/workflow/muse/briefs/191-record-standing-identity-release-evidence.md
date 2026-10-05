# Brief 191: Record standing identity release evidence accurately

## The ask
“캐릭터 일관성이 젤 중요해 크기 이런거 항상 잘 확인해 이것때문에 계속 배포를 못하고 취소하고 하자나”
Record the completed identity repair in the correct release log and make the QA harness comment describe its actual coverage.

## Where things stand
The three-round standing/head repair is finished. This is a separate documentation task; do not revisit or alter that art or its runtime behavior. The director inspected all 192 idle/walk production cells at 4× nearest, all 24 attack facings with and without VFX on consecutive original 60fps frames, and 50 actual forecourt overview frames across 25 seconds. The director independently ran canonical-head 1,896 checks, forecourt 13,218 checks on the earlier snapshot, gait 354 checks, painted-world 1,176 checks, and manual harness 1,416 checks. Final full verification and native build/device checks are separate director operations, still pending; do not claim them complete.

Two documentation defects remain: the comment above `STOP_WALK_CYCLES` in `apps/game/tools/shot_hero_attack_motion.gd` says the 24-cell close block also performs the walk/stop cycle at 2×. In reality the close block stays planted and shows attacks/recovery; only the six movers execute repeated walk → stop → attack → recovery → walk and turn across four facings. The implementation added its release entry to the historical `notes/plans/3-0-0-build-log.md`; the current release log is `notes/plans/4-0-0-build-log.md`.

## Do
- Correct only that comment, preserving all code bytes and behavior outside it. Explicitly distinguish the stationary 24-cell close block from six moving actors and avoid promising enlarged mover visibility.
- Add an accurate 4.0.0 build-log entry describing fixed canonical heads, shared idle/walk forecourt transforms, supported neutral feet, preserved original attack/recoil behavior and measured tests. Point to the director's `notes/workflow/muse/hero-attack-replacement-validation.md` for evidence. Distinguish inspected source/movie coverage from pending final native APK/iPad validation, PR/merge and submissions. Preserve existing log entries; leave the historical 3.0.0 entry as historical evidence.

## Do not
- Change any art, generator, rig, runtime, test, threshold, version, manifest, login/save/store/hosting configuration, gallery image or capture provenance.
- Claim a native matrix, upload, merge or submission completed; these are director operations outside this task.
- Network, git, credentials or device operations.

## Acceptance
Exactly two deliverable files changed. The GDScript change is comments only. Existing code behavior and all 100 packed hero payloads remain untouched. The 4.0.0 entry names the actual release and actual coverage without rounding a source review into final device approval. `git diff --check` is clean. No additional standing-art round is performed.

## Deliverables
`apps/game/tools/shot_hero_attack_motion.gd`, `notes/plans/4-0-0-build-log.md`, and a precise implementer report listing the two changes and checks actually run.

## How the director will judge
Read the diff, compare GDScript with comments removed, check changed-path count and read the new release entry against the recorded director evidence. Any final verification or native-device evidence will be added separately by the director to the workflow journal.
