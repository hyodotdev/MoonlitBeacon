# 4.0.0 production host log — moon gate journey host

Round 1 of assignment 20261003-0216-production-moon-gate-journey-host. This
round connects the accepted foundations into the production playable flow:
the moon gate entry, durable player identity, real native/cloud services,
Journey saves, the Arena, and the Hall. No native SDK, coordinator,
Vault, Journey-money, asset, runner, rules, store, or version-lock change.

Round 2 (brief 073) finishes the real first-login and account deletion
paths on the same ownership: first-entry provider/guest selection,
pending-aware native deletion with an account ticket, sequential cloud
deletes with early abort, and competition tie standings. No new
persistent production files this round; all changes land in round-1
files. Same no-touch list as round 1.

Round 4 (briefs 080/081; round 3 stalled with no edits) replaces the
two frame-counted native waits with monotonic wall-clock deadlines:
`_wait_for_deletion` waits the full nominal 30 seconds and
`_wait_for_token` the full 15. Tests narrow the bounds only through
`inject_services` (`clock` + short `*_seconds`); production keeps the
fixed constants on the engine monotonic clock. Same ownership and
no-touch list; terminal, ticket, draining, and preservation behavior
unchanged.

Round 5 (brief 088) fixes the owned-cloud composition defect:
`_delete_owned_cloud_rows` sent four sequential DELETEs, which the live
4.0.0 rules deny (profile and reservation halves go only together with
the Hall row already gone), so deletion could never complete. The host
now sends one atomic four-row `documents:commit` through the existing
CloudAccount helper on the real transport, checks the ticket before the
commit and after its acknowledgement, runs native Auth deletion only on
that ack, and preserves the slot/binding ledgers on every failure. New
seams `delete_commit_request()` (static, replayable) and
`last_delete_commit_evidence()` expose the exact method/path/body for the
director's emulator run. Same suite gains commit-shape fixtures plus
timeout, duplicate-tap, sync native error/cancel, and identical-retry
cases; the ties/rank fixtures queue the owned-best row GET the accepted
Hall contract reads before the greater-count. No rules, native,
provider, purchase, network, visual, or registration change.

## What was built

New production files (exact list for the preservation-inventory tooling;
details in `4-0-0-production-host-handoff.md`):

- `apps/game/scripts/net/production_host.gd`: the persistent host node,
  registered as the `ProductionHost` autoload. Joins PlayerAccount, the
  real NativeIdentityAdapter, CloudHttpSender, CloudCoordinator, and Vault.
  Lazy boot (children only), explicit `startup()`, token-first cloud
  configure, canonical adoption, Hall/rank mapping, entry planning,
  ordered account deletion, HUD rank push, debug snapshot with timings.
- `apps/game/scenes/menus/production_entry.tscn` +
  `scripts/ui/production_entry.gd` (`class_name ProductionEntry`): the new
  main scene. GateEntry surface, existing menu panels (Shrine, Shop/IAP,
  Settings, Credits, Chronicle), TestLauncher, approved
  title BGM flow, code-built new-journey confirm, back/exit/cancel unwind,
  generation-guarded Arena swap with pre-swap drain wait, and
  capture/debug-compatible hooks.
- `apps/game/tests/test_production_host.tscn/.gd`: 247-case scene suite
  (130 round 1 + 86 round 2: first-entry choice, deletion order/failure,
  competition ties; +31 round 4: elapsed-deadline waits) with injected
  fakes only in tests (fake adapter + fake sender; real account,
  coordinator, Vault, Journey, entry, HUD).
- `apps/game/tools/prod_host_exercise.tscn/.gd`: isolated production
  exercise printing first-paint/load/handoff measurements (22 checks).

Extended in place:

- `scripts/net/player_account.gd`: durable canonical-ID adoption
  (`adopt_canonical_id`, conflict on differing bindings, rollback on I/O
  failure), per-UID binding cache (`player_bindings.cfg`, sha256 keys, no
  raw UID/token/email on disk), fresh-guest-on-sign-out opt-in plus
  `rotate_to_fresh_guest`, `refresh_native_session` hydration when the
  adapter supplies it (snapshot otherwise), `uid_bound` in state.
  Default sign-out/delete behavior unchanged.
- `scripts/ui/gate_account_panel.gd`: link row, sign-out and two-tap
  delete actions with `link_requested` / `sign_out_requested` /
  `delete_requested` signals. All hidden unless the host data enables
  them, so existing gate suites see no layout change.
- `scripts/ui/hud.gd` + `scenes/ui/hud.tscn`: compact cloud-rank chip
  (`set_cloud_rank` / `clear_cloud_rank`, hidden when unranked) and the
  `moonlit_hud` group for host pushes. Never in the quiet set.
- `scripts/gameplay/settings.gd`: persisted `reduced_motion` taste,
  applied to the gate at entry boot (no panel toggle in this round).
- `scripts/gameplay/arena.gd`: `TITLE_SCENE` now points at the
  production entry; open-shrine/store meta keys unchanged.
- `localization/gate_entry.csv`: 18 new keys × 5 locales (account
  link/sign-out/delete, local-guest/cloud labels, fresh confirm, rank
  sources, provider labels), no ASCII commas.
- `project.godot`: main scene + `ProductionHost` autoload only. All ten
  locked values, package, version, IAP, and plugins untouched.
- `apps/docs/docs/game.md`: player-facing moon-gate section, save-file
  rows, gate states diagram, exclusion list updated.

## What bit

- Sync-sender reentrancy: with scripted fakes the reservation finishes
  *inside* `configure_host`, before `_configured_uid` was set, so the
  ready handler skipped adoption. The host now claims the UID before the
  call and clears it only when the call refuses.
- Round 2: the error's follow-up change clobbered the deletion waiter
  (failure relabeled `delete_cancelled`). Waiter release is now
  first-terminal-wins.
- Round 2: scripted HTTP 500s cannot prove early abort — the transport
  rightly retries retryable codes itself. First-step-failure tests use
  403; deferred adoption work is settled before the sender is reset so
  queued replies and call counts stay exact.
- Round 2: a guest tap while native registration is pending must not sit
  on an unchanged choice card; `begin_guest` returns early and the entry
  shows busy-with-cancel from `is_login_pending()`. Desktop (unsupported)
  still plays local with no registration call and no error.
- Round 4: both native waits counted 0.05 invented seconds per frame, so
  a 144fps machine timed a nominal 30s delete out at 4190ms. The loops
  now compare `Time.get_ticks_msec()` against a deadline computed once;
  a frozen test clock over 125 frames proves frames are not time, and a
  short real deadline proves genuine elapsed expiry. A token refresh
  that expires keeps serving the previously cached token; the test
  asserts that instead of an empty supply.
- Session-echo binding poisoned adoption: binding UID→guest at sign-in
  made every restored canonical ID a false conflict. Bindings now land
  only through `adopt_canonical_id`; the echo path was removed.
- Adoption's own change signal wiped the fresh token. Token retirement
  is now UID-guarded: same UID keeps the token, a moved UID retires it.
- `class_name` + same-name autoload is a parse error, so the host has no
  `class_name` (tests preload the script). `strip_edges()` takes bools,
  not chars; `Object.get()` takes one arg.
- Teardown races: coordinator `close()` emits during `_exit_tree`, after
  the tree is gone. Host handlers check `_closing`; entry handlers check
  `is_inside_tree()`.
- Engine `ERROR:` lines fail the regression runner, so the generation
  test loads tiny real scenes, never bogus paths.
- The exercise tool's 39 leaked RefCounteds at exit reproduce exactly on
  the pre-existing `test_title_transition` suite: a threaded-arena-load
  characteristic, not new code.
- Round 5: the fake adapter dropped its session on every sync delete
  receipt, including errors, so a sync-error retry silently took the
  local-guest path with no commit. Only sync ok drops the session now,
  like the real SDK; error/cancel keep the account for a truthful retry.
- Round 5: transport timeouts retry 3x inside the transport, so the
  commit-timeout fixture queues three timeout replies and asserts three
  bounded calls; 403 stays single-call because denials are not retryable.

## Contracts honored

- Cloud-coordinator contract: guest ID reserved verbatim, sync token
  supplier held in memory only, re-configure switches accounts, explicit
  conflict choice with rejected bytes preserved, foreign integer IDs only
  through the mapping/floor path, ledgers never synced, Hall reads
  labeled and throttled/bounded by the coordinator.
- GateEntry/GateLoadingOverlay: no service edits to either; the host
  waits for `has_pending_drain()` before the freeing swap; loader tokens
  and paths are re-checked at finish; no arena preload before first
  paint.
- Native boundary: no adapter/SDK/export edits. `refresh_native_session`
  is called only when present; `get_session` stays a snapshot.
- Money: planning, conflict UI, and restore paths seal nothing; the
  reward-safety case asserts byte-identical checkpoints across planning.

## Left for later rounds

- Shared-runner registration of the new suite (tooling task owns it).
- Windowed render proof of the gate surface on a real display (sandbox
  cannot run `shot_*` harnesses; staged only).
- Provider task: real Google/Apple/Play Games capabilities on device.
- Source version bump (integration task owns it).
- Reduced-motion panel toggle (setting persisted and applied; no UI).
- Store-screenshot recapture decision (check is red; never recapture
  without instruction).

## Commands

```bash
pnpm godot:isolated --timeout 300 res://tests/test_production_host.tscn
pnpm godot:isolated --timeout 600 res://tools/prod_host_exercise.tscn
pnpm godot:isolated --timeout 150 --script res://tests/test_player_identity.gd
pnpm godot:isolated --timeout 150 res://tests/test_gate_entry_state.tscn
pnpm godot:isolated --timeout 150 res://tests/test_gate_loading.tscn
pnpm godot:isolated --timeout 300 res://tests/test_journey.tscn
node apps/game/tools/run_coordinator_tests.mjs
node apps/game/tools/run_cloud_tests.mjs
```

## Round 6: persistent sign-in error and local guest escape (brief 089)

The director reproduced a composition defect through the real
ProductionEntry + ProductionHost + PlayerAccount signals: after an async
Google `network_error`, three frames later both Ready and Error were
invisible and the screen sat silently on the choices. Root cause: an
async failure emits `production_error`, then one `production_changed`
from the error fold, then a second benign `production_changed` from the
settled account change. `_on_production_changed` cleared the one-beat
`_error_hold` on the first repaint, so the duplicate swallowed the
error. Fixed in `production_entry.gd` only: the hold now persists across
duplicate changes (same public ID, same cloud UID) and retires on an
explicit intent (provider choice, retry, cancel, guest, link, sign-out
via `_retire_failure()`) or on a genuine new outcome (the ID or UID
moved, e.g. a cloud login or canonical adoption). No timer, no one-frame
delay, no fabricated status; the friendly translated title is unchanged
and the screen still carries no UID, token, request id, or raw code.

The Error screen's guest button now escapes to the durable local guest
through a narrow `begin_guest(true)` host option: same ID, no native
anonymous registration call, no cloud/owner/save/purchase touch. The
default `begin_guest()` behavior for the original first selection is unchanged.
Choosing guest also clears the stale `_busy_provider` intent. Pending
(which covers draining) and deletion guards still refuse first, so a
mutation in flight cannot be bypassed. Provider-conflict switching
(`can_switch` text, retry-as-switch) and the draining lock are
preserved; no Gate, service, native, rules, purchase, or registration
change.

Tests: six new cases in `test_production_host.gd` (suite 376 → 468),
all through real entry buttons/signals and PlayerAccount folding:
Google+Apple async failure with triple duplicates and screen-secrecy
checks, retry with stale-then-error-then-success, busy/error cancel
plus sign-out with no-resurrection negative controls, provider and
anonymous failure→local guest with zero extra native calls, draining
refusal with terminal landing, and conflict-switch preservation.
Negative controls proven by breaking the hold (17 failures) and the
local escape (4 failures), then restoring green. Atomic deletion and
all monotonic-deadline tests untouched and passing.
