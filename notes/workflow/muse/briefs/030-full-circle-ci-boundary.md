# Brief 030: fix the confirmed full-circle weapon CI failure

## The ask
The user asked “/loop-review 돌아서 확실하게 해줘 pr 만들어 이번에는 내가 승인”, then store submission, then “했어 다 해줘”.
Resolve the confirmed Linux CI failure before merging or submitting the renewed game.

## Where things stand
The current 3.0.0 branch has five full macOS verification passes, but PR 10's Ubuntu Game check fails one of 355 hero-weapon assertions: `orbit sweep is a full circle — expected 1, got 0`.
Other PR checks (docs, repo rules, Android APK/AAB) pass. The failed check calls `pnpm test:game`; the failure is in `_test_eclipse_orbit` of `apps/game/tests/test_hero_weapons.gd`, targeting an enemy exactly behind at Vector2(-50, 0).
`apps/game/scripts/gameplay/arena.gd` computes `half_arc = PI` for full-moon/orbit and still compares `absf(direction.angle_to(to_spirit)) > half_arc`.
A single-precision Vector2 angle versus the GDScript PI boundary is a plausible cross-platform cause; investigate and demonstrate rather than merely assuming it.
Native iPad capture is running in the real tree; you work only in the isolated copy. Current public version/build values are 3.0.0, Android 15, iOS 10. The director will increment build numbers and rebuild artifacts only if runtime changes are accepted.

## Do
- Read the melee hit logic and weapon tests. Establish why the opposite enemy is skipped and fix the production full-circle contract narrowly if that is the root cause.
- Keep full-circle attacks hitting every eligible target in the permitted radial band, including exact antipodal positions. Keep the Eclipse inner hole, outer range, ordinary weapon arc limits, attack timing and damage unchanged.
- Add meaningful regression cases covering antipodal directions, the precision boundary, full-moon and orbit paths, and ordinary partial arcs. Keep the failing original expectation and other existing assertions.
- Run the relevant Godot scene and `pnpm test:game`; report measured outcomes and any reproduction limit on this host.

## Do not
- Mask the CI failure by moving the enemy away from the opposite boundary, adding tolerance to the assertion, skipping a test, disabling the CI job, or weakening any acceptance gate.
- Change art, audio, balance, unrelated logic, capture pipeline, store tools, version numbers, package metadata, git or the network.
- Rewrite the arena or accept unrelated earlier continuation-race proposals. Fix only this evidence-confirmed defect.

## Acceptance
- Existing `_test_eclipse_orbit` passes with the exact opposite enemy and unchanged expected hit counts.
- Full-circle eligibility is independent of whether a computed vector angle slightly exceeds double PI because of float precision; partial arcs remain directional and range/hole exclusions remain effective.
- Added regressions catch the original defect when the correction is restored to the old behavior in the copy, without relying on a particular host's rounding accident.
- Related game tests pass without skipped assertions, and there are no changes outside the named weapon logic and relevant existing tests.

## Deliverables
The narrow correction in `apps/game/scripts/gameplay/arena.gd` if justified, related existing weapon tests, and the implementer report. The director owns release records and build operations.

## How the director will judge
Read the diff, run the weapon scene and game tests independently, perform a negative control, and require GitHub Linux CI on the new head before merge.
