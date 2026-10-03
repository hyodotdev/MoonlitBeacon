# 4.0.0 production host handoff — tooling/inventory note

For the later preservation-inventory and integration/tooling task. Exact
production files this round added or changed, and what must keep working.

## New production files (preserve all)

- `apps/game/scripts/net/production_host.gd` (autoload `ProductionHost`)
- `apps/game/scenes/menus/production_entry.tscn` (new main scene)
- `apps/game/scripts/ui/production_entry.gd`
  (`class_name ProductionEntry`)

## New test/tool files (not shipped, keep for verification)

- `apps/game/tests/test_production_host.gd`
- `apps/game/tests/test_production_host.tscn`
- `apps/game/tools/prod_host_exercise.gd`
- `apps/game/tools/prod_host_exercise.tscn`

## Modified production files

- `apps/game/scripts/net/player_account.gd` (adoption, bindings,
  fresh-guest opt-in, session hydration)
- `apps/game/scripts/ui/gate_account_panel.gd` (link/sign-out/delete)
- `apps/game/scripts/ui/hud.gd` (rank chip, `moonlit_hud` group)
- `apps/game/scenes/ui/hud.tscn` (Rank label)
- `apps/game/scripts/gameplay/settings.gd` (`reduced_motion` persist)
- `apps/game/scripts/gameplay/arena.gd` (`TITLE_SCENE` only)
- `apps/game/localization/gate_entry.csv` (+18 keys × 5 locales)
- `apps/game/project.godot` (main scene + autoload only)
- `apps/docs/docs/game.md` (player docs)

## Modified author-only files

- `notes/plans/4-0-0-production-host-log.md` (new)
- `notes/plans/4-0-0-production-host-handoff.md` (this file, new)

## Handoff to the separate Hall correction

The Hall correction (another task) will make rank snapshots carry the
actual owned best hero, score, cycles, and ID alongside the standing.
This host is ready for it and needs nothing changed on receipt:

- `_push_rank_to_hud` shows only `#standing · source` today, so a new
  hero's low live score can never be paired with an old best rank. When
  the snapshot carries the owned best, keep that rule: display a rank
  only with the best it was computed from (same snapshot), and keep the
  source label (`live` / `cached` / `offline` / `unregistered`) honest.
- `_map_hall_rows` already assigns competition standings (equal scores
  share one, matching the backend's strictly-greater count plus one).
  The correction must not reintroduce consecutive positions for ties.
- No host API change is needed: `rank_view()` passes the coordinator
  snapshot through, and the `ties` host test pins board/rank agreement.

## Registration owed to the tooling task

- Register `res://tests/test_production_host.tscn` in the shared
  regression runner (left out by brief order). Standalone command:
  `pnpm godot:isolated --timeout 300 res://tests/test_production_host.tscn`
- The exercise tool stays standalone (it loads the real Arena):
  `pnpm godot:isolated --timeout 600 res://tools/prod_host_exercise.tscn`

## Capture/tooling migration (deliberate, truthful)

- Main scene is now `production_entry.tscn`; the old
  `title_menu.tscn` still exists for its suites and capture boards.
- `TestLauncher` is instanced in the production entry, so debug boosts
  and store-capture boot launches keep working. Its title-ready proof
  (`Ui/Screen` + version) does not fire here by design; automation
  should read `debug_store_capture_state({"kind": "title"})` on the
  production entry instead, which reports the honest gate state plus
  `debug_production_state()` timings.
- `debug_prepare_store_capture` / `debug_open_iap_store` keep their
  signatures; `shrine` / `hero_preview` / `iap_review` kinds forward to
  the same panels.
- `pnpm check:store-screenshots` is red (any `apps/game/` touch does
  that). Do not recapture without instruction.
