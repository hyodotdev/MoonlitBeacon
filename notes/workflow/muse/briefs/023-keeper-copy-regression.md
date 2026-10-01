# Brief 023: Reconcile the independent Keeper copy regression

The kinetic renewal (six primary weapons and three arena / three guardian
tracks) is accepted into the real tree. All production/gameplay/audio work
is complete. This is one newly confirmed integration-test defect in the
mandatory final full check; do not build more features.

The director ran the original `pnpm verify` on the staged accepted root.
It stops at `test:play-release-package`: 207/208 Node checks pass, and
`Python release gate validates every first-party state_guard field` fails
with `keeper preview localized copy contract is incomplete`.

`scripts/lib/store-graphics-boundary.test.mjs`, around lines 804–888, pins
`expected_hero_copy` independently in five locales. Those literals still
expect the old flat-damage description, whereas accepted
`apps/game/tools/build_store_graphics.py` and `HERO_KEEPER_DESC` now describe
the actual lantern shotgun (hearts/move/dash/openings retained, no flat
stat superiority). Reconcile the test literals with the accepted descriptions.

Only write that regression file and a short factual entry in
`notes/plans/3-0-0-build-log.md`, plus the report. Preserve all other guard
fields, literal independence, source-key checks, corruption/swap/actual-and-
expected-both-wrong cases. Do not compute expected copy from the module under
test, delete assertions, weaken the Python gate or alter production to fit
old expectations. No new suite or broad cleanup.

Run `node --test scripts/lib/store-graphics-boundary.test.mjs` and
`pnpm test:play-release-package`. Existing negative cases must still fail
closed. Run hygiene on the tracked/staged set. The director repeats the
complete original root `pnpm verify` after acceptance. Keep game/audio/art,
IAP catalog, capture generator, other tests and all locked values unchanged.
No network, git-history, device/store/capture/user-save operations. Earlier
store-screenshot proof failure is reported only, never a recapture order.
