# Brief 134: retire dismissed Hall requests

## The ask
"/loop-review돌리고 메인 다 클린한상태로 둔 다음 할까"
Fix the confirmed menu race before the final clean review rounds.

## Where things stand
Continue the documentation copy from briefs 132/133 and keep its four changes. The director independently reproduced a real production-entry race with a delayed host Hall reply, using the real title, gate, and settings scenes under an isolated scene harness:

1. `Title._open_ladder()` parks title chrome and starts `ProductionEntry._on_hall()`; the host's `request_hall()` remains held.
2. Android-back handler `_on_back()` is invoked, then the exit prompt is cancelled, and Settings is opened normally.
3. Release the earlier Hall response.

Measured current result: `request_feedback=false`, `settings_before=true`, `hall_after_dismiss=true`, `settings_after=true`, exit 0, no ScriptErrors. The old Hall request opens its panel over Settings despite the user's navigation. `_on_hall` currently guards only `is_inside_tree()` after await; it owns no dismissible request intent.

## Do
- Give one Hall-opening request a monotonic owned intent before the first await. A dismissed or superseded intent must never open a Hall or park/unpark newer title/menu/card state when its response lands.
- Make Back while the Hall request is pending dismiss that intent and restore the original title directly, rather than offering app exit. Keep the existing visible Hall Close/Back behavior and existing menu styling. A later fresh Hall request must still work; an older response cannot replace the newer result. Scene teardown also must be safe.
- Add focused delayed-response regressions to the already registered title-tap/entry test path. Prove pending Back → Settings → late result stays in Settings; old A → new B with out-of-order results keeps B; ordinary current Hall still opens/closes; no account or credential mutation is introduced. Exercise real pointer routing in a windowed run for navigation where practical, and distinguish that from direct handler state checks.
- Finish the confirmed documentation discrepancy flagged by round 133: `game.md` section 4 still says the current online ladder types a name with no account. Scope that sentence to legacy behavior and describe current optional guest/provider identity plus the owned Hall from source, consistent with the corrected 4.0.0 section.

## Do not
- Change other screens, login behavior, account/save/rank services, combat, assets, versions, dependencies, test runners, or external settings.
- Add seeded leaderboard rows or claim a device/release test happened.
- Fix this by ignoring late responses only when Settings happens to be visible; ownership must handle a new chooser, newer Hall, and teardown too.

## Acceptance
- In addition to the four earlier documentation files, change only `apps/game/scripts/ui/production_entry.gd` and `apps/game/tests/test_title_tap.gd` (its scene is already registered).
- The delayed-production-menu scenarios above pass. A one-line guard removal in the copy causes the new delayed assertions to fail; restoring exact bytes makes them pass.
- Existing title-tap headless and real-window routing cases pass with no ScriptErrors. The director will run them independently and repeat the held-response probe.
- No altered visual asset/layout or default control; only pending navigation behavior and accurate reference text change.

## How the director will judge
Read the full six-file diff. Independently run the delayed-request tests, the negative control with byte-exact restoration, the original reproducer, and the real-window title routing suite; then normal integrated verification on the accepted tree. Keep the temporary Firestore reproduction and provider-readiness boundaries from the earlier briefs accurate.
