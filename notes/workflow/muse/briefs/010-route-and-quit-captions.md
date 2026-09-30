# Brief 010: Keep captions readable at the edge and in Japanese

## The ask and confirmed evidence

The user asked for the whole 3.0.0 renewal to be inspected and improved, with immersive playable story,
then a merge-ready PR without merging. This fixes two visual defects found from a different review angle.

The director rendered the production fork gate at the actual upper rim candidate `(950,124)` with the
player near it at `(950,220)`. The gate was visible, so its compass hid, but its three-line destination
label projected to y=-64..-12 in the internal viewport. The label's fixed above-gate placement loses the
terrain and memory clue. This was a diagnostic placement at a valid gate candidate, not a natural route
capture; the geometry defect is reproducible. Left/right/bottom placements need checking too.

All five settings/relic/shrine/consent and ladder/pause/quit/credits boards were inspected. Japanese quit
title `ゲームを終了しますか？` extends outside the 260 px card at font 26; source still gives its Label the
whole viewport width and does not fit it to the card. Other four quit titles fit the staged card.
Old credit screenshots show 3.5.1, but current main has already corrected the source to 3.6.1; do not
change that based on stale imagery.

A separate director font measurement on the current root confirms the Japanese title is 266 px at
font 26, wider than the entire 260 px panel (236 px with 12 px padding each side). The other four are
196/177/181/181 px. This is production-font evidence, not just a visual impression.

## Do

1. Keep a fork gate's actual destination, guardian/omen and memory caption readable as the camera approaches
   any of the four rims. Use the existing label and fonts; position it inside the usable screen when an
   above-gate placement clips or hides behind HUD. Keep it associated with its gate and preserve tap-through
   movement. Do not let a hidden compass remove the only readable choice information.
2. Fit the quit title inside its panel with real padding in all five languages, including Japanese. Keep
   default focus on Cancel, both actions and their behaviors. Use a modest width or font adjustment, not
   truncated wording or a new dialog flow.
3. Add meaningful registered geometry/layout checks for four rim gates with the real arena camera/HUD and
   five-language quit titles. Include no fork/plain gate and closing/reset behavior. Mutation-check a
   representative edge or width guard. Render diagnostic desktop stages after animations settle.

## Scope and acceptance

Only gate/quit presentation, necessary tests/harness and a concise related build-log note. The accepted
story canon, discovery scheduling, result card, combat tuning, score, IAP, save IDs, locks and versions stay
unchanged. No protected files, stores, course prose, network, devices, git operations or marketing capture.

The director reads the full diff, repeats tests and the negative case, renders edge captions and all five
quit titles, then runs final verification. Report commands, exact cases and remaining limits honestly.
