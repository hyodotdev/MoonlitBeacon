# Game regression tests

Run:

```bash
node apps/game/tools/run_regression_tests.mjs
```

The runner creates a temporary `HOME` · `XDG_DATA_HOME` · `APPDATA` and passes
them to Godot. Each test also checks that `user://` sits under that temporary
path, so it never reads or overwrites the `vault.cfg` · `ladder.json` from
normal play.

Coverage:

- Settings-screen privacy-policy and support-URL validation, hiding empty
  values, and mobile touch sizes
- 808×360 layout of 5-language credits, including the Noto CJK notice and the
  IAP supporter line
- Custom walk/idle sheets for six heroes and the Player safety fallback
- Real shrine cards consuming `48×48` Hero portrait textures
- Kill cores, missile growth `0…8`, hit eject/reclaim, and damage budget
- Real collision of the three-region structures, safe placement, and region
  cycling
- Value correction of older vault saves while keeping valid progress
- Deduction, duplicate-request blocking, and restore after relaunch for boon
  and hero purchases
- Non-consumable IAP ledger save-first, plus finish retries after
  pending/fail/duplicate/restore/restart
- Atomic grant of the hero bundle and separate shard/IAP unlock sources
- Lantern-color entitlement and restore of the chosen palette after relaunch
- Rollback of shards and purchase state when a save fails
- 808×360 result-screen layout in 5 languages and the play-again / shrine
  button signals
- Keeping the player's chosen destination before and after rank registration
- Migration of older rank records, newest-app-version sort, and version at
  the end of the row
- Title consuming a shrine-open request only once
- Project version in the title's bottom-right corner and layout in the 5
  release languages

Godot can print a runtime error and still return exit code `0`. The runner
treats `ERROR:` logs as failure as well as the exit code.
