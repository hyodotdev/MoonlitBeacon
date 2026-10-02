# Brief 002: Result screen depth, one English word for a cycle, and the shop's clipped lines

## The ask

The user: "3.0.0 최종 릴리즈 상태로 잘 작업해줘 끝까지" (work 3.0.0 through to a final release state, to the very end).

The director photographed all 22 UI screens in all five languages with `tools/shot_ui.tscn` and found nothing
blocking: text fits, every language is present, no placeholders. Three polish items remain, all small.

## Why, and what "good" feels like

A player who passes the map's end (cycle 8) enters the endless stretch, where the HUD counts **Depth**. Their result
screen should say the same thing, and the game should call its loop by one English word everywhere. Nothing on a
screen should end in an ellipsis where a line is cut short.

## Where things stand

- Result screen: `apps/game/scripts/ui/result_panel.gd` (`LEGEND_CYCLE = 8`, title, epitaph, rows counted up from
  `Score.lines()`). The first row is `SCORE_CYCLES` ("Cycles %d"). The HUD already shows `HUD_DEPTH` ("Depth %d")
  through `Expedition.depth(cycle)`, which is `cycle - 8`. The harness's `result_win` sample has cycles 9, so it would
  read Depth 1.
- English wording for the same idea, in `apps/game/localization/moonlit.csv`: `CYCLE_CHOICE_TITLE` "WAVE %d SECURED",
  `CYCLE_CHOICE_RIGHT_TITLE` "NEXT WAVE", `CYCLE_REWARD_*` "Wave %d", `CYCLE_CLEARED` "Wave %d", `SCORE_CYCLES`
  "Cycles %d", `HUD_DEPTH` "Depth %d". The other four languages already use one term each (순환, 巡, 轮, 輪).
- Shop: `apps/game/scripts/ui/iap_shop_panel.gd`. The hero cards clip the stat line with an ellipsis in English,
  Japanese and Chinese ("3 hearts · move +43.75% · dmg -10% · dash CD -40% · Moon Rin…").
- Tests that must keep passing: `test_result_layout` (five-language layout), `test_ladder` (versioned ladder save,
  sort, display), `test_result_route`, `test_iap_hero_previews`, `pnpm check:locale`.

Harness artifacts, not defects, so leave them alone: English boss name and banner in the HUD sample (the harness passes
raw strings), the settings panel's language highlight, dim buttons on the consent panel and the pale act-card title
(the shot is taken while they fade in).

## Do

1. On the result screen, when the run went past the win (cycles above `LEGEND_CYCLE`), show the depth in the player's
   language. Keep the "Cycles" row: its points are part of the score. Do not change how the score is computed or what
   the versioned ladder stores. Where the depth goes (a caption under the title, next to the epitaph, an added row that
   scores nothing) is your call; choose what the layout test and the pictures show reads best, and keep every language
   inside its panel.
2. Choose one English word for the loop, Wave by default, and apply it to every English string that names the loop:
   `SCORE_CYCLES` becomes "Waves %d" and so on. Do not rename a key. Change the other four languages only where a
   string is inconsistent with its neighbours.
3. Make the shop's hero cards show their whole stat line in all five languages without an ellipsis: wrap it on two
   lines inside the card, or shorten the stat text. Nothing may overlap the price or the Buy button.
4. Add a test for item 1 (past the win the result shows the depth, at the win it does not) and put it in
   `apps/game/tools/run_regression_tests.mjs`; extend `test_result_layout` for the new line in five languages if that
   is where it belongs. The test must be able to fail: break it and watch it.
5. Update `apps/docs/docs/game.md` (result screen) and add a short entry to `notes/plans/3-0-0-build-log.md`. That log's
   "Not done" list and `notes/plans/3-0-0-expedition.md`'s still name a first-fork hint as missing: it exists
   (`VOICE_FORK_1/2`, `_say("fork")` in `arena.gd`). Correct both lists.

## Do not

- Do not change the score arithmetic, the ladder format or anything the balance tests pin.
- Do not rename translation keys or touch the store text.
- Do not recapture store screenshots or touch `stores/`.

## Acceptance

1. `pnpm test:game` passes, the new test is registered and fails when its guarded behaviour is broken.
2. `pnpm check:locale`, `pnpm game:check`, `pnpm check:hygiene` pass; `pnpm check:store-screenshots` is run and its result
   reported (red is expected).
3. `pnpm godot:isolated --windowed --timeout 900 res://tools/shot_ui.tscn -- en,ko,ja,zh_CN,zh_TW result_win,result_lose,choice_cycle,shop`
   produces `builds/shots/ui/<locale>/*.png` in which the result shows the depth in all five languages, no line in the
   shop ends in an ellipsis, and nothing overflows (the director looks at these).
4. A search of the English column finds one word for the loop.
5. The two "Not done" lists no longer claim the fork hint is missing.

## Deliverables

`result_panel.gd` (and `score.gd` only if the depth needs it), `iap_shop_panel.gd` and its scene, `moonlit.csv`, the new
or extended test and its registration, `apps/docs/docs/game.md`, `notes/plans/3-0-0-build-log.md`,
`notes/plans/3-0-0-expedition.md`, `IMPLEMENTER_REPORT.md`.

## Settle these yourself

- Where the depth line goes and what it says (default: "Depth N" under the epitaph, only past the win).
- The English loop word (default: Wave).
- Wrap or shorten in the shop (default: wrap to two lines if the card height allows, else shorten).

## How the director will judge

The director repeats the acceptance commands in your copy, breaks the new test once to see it fail, reads the diff, and
looks at the five-language pictures of the four screens.
