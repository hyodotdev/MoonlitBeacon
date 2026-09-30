# Brief 012: Verify guaranteed skill discovery without random reappearance

The user asks to finish the immersive renewal and make a stable, merge-ready PR. The director
independently reproduced a flaky check in `test_skills.gd`: two identical isolated runs on the
story integration copy failed then passed, 116/117 then 117/117. The failed assertion is
`every unlocked skill has been offered by cycle 11`, expected 7, got 6. The story implementer
independently reproduced the same failure. Logs are in that copy's `judge/` directory and not
present here. Production relic behavior has no confirmed defect.

`_test_unlocks` guarantees and records newly shown skills at cycle 5, then creates an empty
`shown` dictionary at cycle 11 and expects all seven skills to appear again in 80 random
draws. `_pick_skill` correctly guarantees each unseen open skill first, then uses a 28 percent
random repeat pool. The test forgets the earlier two skills, and incorrectly requires their
random reappearance. Read the production selection and metadata paths before changing it.

Change only `apps/game/tests/test_skills.gd` and necessary test collateral. Accumulate actual
discovery history across unlock epochs and verify all seven guaranteed first sightings by
cycle 11 with bounded draws tied to the unseen count. Keep or strengthen cycle gates, all
nine resource/effect/translation checks, one-time NEW metadata, stack caps, cycles 13 and 16,
and every real-arena skill-effect check. Assert both cycle-5 skills are guaranteed, not just
either one. A separate fresh cycle-11 panel fixture is acceptable if needed. Do not seed an
80-draw lottery, increase the count, delete the seven-skill assertion, loosen expected
coverage, edit production selection/balance, or change other tests, docs, registry, versions,
stories, stores, git, network or devices. Other copies own story, title and spatial tests.

Repeat focused runs sequentially and under contention. Perform a meaningful mutation of the
actual production unseen-skill guarantee; the deterministic coverage check must fail even
if random repeats are possible. Restore bytes and rerun. Report exact case counts, preserved
checks and any environmental limitations. The director reads the full diff, repeats a
negative/restored check, accepts only test changes, and runs final root verification.
