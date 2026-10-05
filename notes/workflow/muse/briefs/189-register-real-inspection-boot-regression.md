# Brief 189: Register the real inspection boot regression

## Confirmed finding
The director read the brief-187 clean-UI suite and the real-scene harness.
The suite checks only `ResourceLoader.exists` for the harness. It never runs
that scene, and the regression runner has no row for it. The implementer ran
the harness separately, which proves the current answer once but does not
keep the real title-to-Arena, unboosted Lv1 and journey-preservation checks
running in `pnpm test:game` or CI. A file existence check is not execution.

## One correction
Keep the accepted scope's minimal boot repair and its actual scene harness.
Register `test_store_capture_inspection_boot.tscn` as an ordinary isolated
scene row in the existing regression runner. This one runner-row edit
supersedes brief 187's earlier prohibition on editing the runner. Do not
spawn a nested Godot process from the clean-UI script or duplicate the runner.
Adjust that suite's comment so it honestly describes its resource/wiring
guard and the separately registered executable scene, rather than implying
that existence runs the scene.

## Verification
Run the registered full game suite and show the inspection-boot row and its
real assertion count. Restore only the original production boot/launcher in
the copy and demonstrate that the registered real scene row exits nonzero;
restore the repair and pass again. Keep the boosted-launch and dropped-journey-
guard negative controls meaningful. Do not hide script errors or change any
timeout, assertion or readiness threshold to bless the new path.

## Preservation
No hero art, Player, forecourt, hero tests, docs, music, balance, login/save/IAP,
version counters, galleries, network/device/store/git work. Brief 186/188 is
still independently repairing standing identity and does not own the runner.
No other runner rows may be changed or removed. Return the minimal diff and
actual report; the director will independently repeat the checks before
acceptance and native inspection.
