# Brief 001b: Wrap up. The time is used; stop tuning and finish

This continues brief 001 in the same copy. The round's time limit was reached while you were still tuning: many
batches, many small parameter moves. Everything you have written is kept. Your job now is to bring it to a finished,
honest state, not to search further.

## What to do, in this order

1. Read `git diff baseline --stat`, then the diff itself. Decide which numbers are your best set. If the current files
   are not the best set you measured, put the best set back. Say in the report which batch it came from.
2. Freeze the numbers. Do **not** start another tuning batch, except the two confirmations in step 3.

   The bands in brief 001 were too tight, and the director says so plainly. Two independent copies measured the *same*
   command on the *same untouched tree* and got 1.01 and 1.42 hits a minute, and 26% and 25% weaving, with kills a
   minute from 29 to 40 in one copy alone: the bot's outcome depends on the frame rate of the machine it runs on.
   A band narrower than about plus or minus 0.3 hits a minute, or five points of weaving, or 25% of kills, cannot be
   met or missed by tuning; it is noise. So the bands are now these, read as the mean of your last two natural batches:
   hits 0.8 to 1.6 a minute; weaving at least 30%; kills a minute within 30% of the untouched tree's mean; bullets peak
   at most 110; no soft lock. Gauntlet: at least 75% of fights won, 0.8 to 3.0 hits a fight, bullets peak at most 110.
   If your best set meets these, it is done. Do not chase the last point of weave share on the bot: a person, not the bot,
   decides whether it is fun. What matters more: no shooter is unfair (the tests say so), the first minute is not a wall,
   and the numbers are not fitted to seed 5.
3. Run once, each, as confirmation of the frozen set, and report their numbers as they come out:
   the natural batch (`tag=final_nat`, the command in brief 001) and the guardian gauntlet (`tag=final_gaunt`).
   Run `pnpm test:game` once and `pnpm check:hygiene`, `pnpm check:locale`, `pnpm check:scripts`, `pnpm game:check`.
4. Make sure the deliverables of brief 001 exist and are true to the frozen numbers: the two registered tests
   (mutation-checked, and say which value you broke), the documentation in `apps/docs/docs/game.md` and
   `notes/plans/3-0-0-build-log.md` (what was built, the numbers, what bit you, what is left), and a picture harness
   the director can run on a real display (`tools/shot_*`) that stages a guardian mid-stream on at least three places,
   a busy zone and a caster fan (say how to run it and what it writes).
5. Write `IMPLEMENTER_REPORT.md` at the root of your copy (not inside `.muse/`, which you cannot write) in the format of
   the standing orders, with no "TBD" left in it. Be plain about what is not met, what was fitted to the bot, and what a
   person should judge. You cannot render pictures in your sandbox (the Metal shader compiler crashes headless, and
   there is no display): say so, keep `shot_*` harness staged and validated, and the director will render and look.

## Time

You have about ninety minutes. Plan to have the report written with at least twenty minutes left. If a step cannot be
finished in time, skip it and say so in the report; a short honest report is worth more than a long tuning tail.
