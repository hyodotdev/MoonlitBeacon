# Brief 126: align the production host fixture with the accepted account scroll

## The ask
"ipad 안드로이드 실기기 다 연결되어 있으니까 제대로 테스트 해주면서 해"
Restore the existing production regression's full execution after the accepted Account layout change.

## Why, and what good feels like
The Account card now correctly bounds its middle inside Card/Stack/Scroll/ScrollBox, leaving header and footer pinned. Its real pointer wheel review passed and the panel is usable at 808x360. However, an older production-host test still looks for the ID and deletion controls directly under Card/Stack; Godot raises Node not found / null-instance and silently skips remaining assertions while reporting exit 0. A clean test means all those assertions actually run.

## Where things stand
- apps/game/tests/test_production_host.gd: _test_menus_open_close around line 2531 gets Card/Stack/StableId. The Account deletion path around lines 2424/2427 references Card/Stack/AccountActions/DeleteAccount and Card/Stack/DeleteConfirm/DeleteNow.
- apps/game/scripts/ui/gate_account_panel.gd: accepted scroll hierarchy is Card/Stack/Scroll/ScrollBox containing those nodes; Card/Stack/Links/Close stays pinned.
- Director ran pnpm godot:isolated --timeout 150 res://tests/test_production_host.tscn after resource import: output reports 534 cases but prints a real missing StableId node and null-instance Script Error. The prior clean count before the Account layout was 537.
- NativeIdentityAdapter's confirmed request-id completion fix was just accepted; do not alter it. Forecourt and Guest-order packets are isolated elsewhere and must remain untouched.

## Do
- Update only obsolete production-host fixture lookups to the actual accepted Account subtree. Keep every original behavioral assertion and action.
- Use safe explicit existence assertions where useful so a missing test control fails rather than an exception making a falsely green report. Do not generalize the production API for a test.
- Run the real production_host.tscn suite and inspect its full output for Script Error / missing nodes, not just exit code. It must execute the ID, closing, deletion and routing assertions that were skipped.

## Do not
Change production code, UI, flow, services, auth/native/backends, rendering, unrelated tests, test runner, package/version/presets, protected paths or store files. Do not remove/skip/assert fewer conditions to get green. No network, adb, device, push or capture.

## Acceptance
pnpm godot:isolated --timeout 150 res://tests/test_production_host.tscn exits 0 with no SCRIPT ERROR, missing-node or invalid-null-access lines and at least the 537 originally completed cases (explain any added existence-assertion count). All prior behavior assertions remain. The director will independently repeat the suite against the accepted tree.

## Deliverables
Narrow change to apps/game/tests/test_production_host.gd only. No author note needed.

## Constraints specific to this task
One confirmed stale fixture after an intentional production layout change. Keep this a test alignment, no new feature or infrastructure.

## Settle these yourself
Prefer the actual node paths within the scroll box, or safe existing panel references if already available. No need to add a production helper.

## How the director will judge
Read all changed hunks, verify original behavior assertions are intact, independently run the scene suite and inspect errors and completed assertion count.
