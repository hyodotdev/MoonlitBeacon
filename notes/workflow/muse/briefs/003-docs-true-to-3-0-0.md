# Brief 003: Docs true to 3.0.0

## The ask

The user: "3.0.0 최종 릴리즈 상태로 잘 작업해줘 끝까지" (work 3.0.0 through to a final release state, to the very end).
The docs a reader opens first must say what the release is, and every number in them must be one the game really has.

## Why, and what "good" feels like

`apps/docs/docs/game.md` is the reference students and the user read. Its 3.0.0 sections were written while the game was
being built, partly from memory. The release is not done until each claim in them has been checked against the code and
the tests, and the front doors (README, the version passage) say 3.0.0. The tone stays plain: what the player sees and
how to answer it. No editorial policy or presenter directions (see AGENTS.md).

## Where things stand

- `README.md` line 37: `| Version | **2.1.0** (both stores live) |`; line 194: "The course stops at 1.0.0. The tree
  continues through store release 2.1.0."
- `apps/docs/docs/game.md`: sections Forks, The endless stretch: Depth, Guardian mutations, Guardians of the later
  places, Reading a guardian's attack, UI and story structure (3.0.0), and "9. Version tags" (mentions 2.1.0 and says
  3.0.0 is not part of the course, which is right: the lessons keep describing the 2.1.0 screens on purpose).
- The version is locked at 3.0.0 (Android code 15, iOS build 10) in `project.godot` and `export_presets.cfg`. Both stores
  currently have 2.1.0 live; 3.0.0 has not been submitted or tagged.
- `pnpm check:assets` and `pnpm check:store-metadata` are green today. `pnpm docs:build` is the check that finds dead
  links.
- Other briefs are being written in parallel and touch other files: one changes `game.md` only by adding a "Bullets"
  section and edits `notes/plans/3-0-0-build-log.md` and `3-0-0-expedition.md`; another edits the store text; another
  the release record. Do not edit `notes/plans/3-0-0-build-log.md`, `notes/plans/3-0-0-expedition.md`,
  `notes/release/` or anything under `stores/`.

## Do

1. README: the version row says 3.0.0 (Android code 15, iOS build 10) and that 2.1.0 is what is live on the stores;
   the sentence about the course says the course stops at 1.0.0, the tutorial closed with 2.1.0, and the tree now
   carries 3.0.0. Do not claim a tag, a store status or a release date that does not exist.
2. `game.md`, "Version tags": one short paragraph saying what 3.0.0 is (a new UI, a structured story, six places with
   forks, an endless stretch that stays playable, more guardians and skills), not part of the course, and not yet
   tagged. Keep the tag list as it is.
3. **Audit `game.md` against the code.** For every number and rule stated in the 3.0.0 sections (unlock cycles, caps,
   counts, tables of places, guardians, omens, mutations, skills, budgets, timings), find where the game defines it
   (`apps/game/scripts/gameplay/expedition.gd`, `spirit.gd`, `arena.gd`, `player_skills.gd`, the resources, and the
   tests that pin them) and make the doc say the same. Fix the doc, never the code; if the code looks wrong, say so in
   the report and leave it. Quote in the report, per section, how many claims you checked and which you corrected.
4. Search the docs for statements that are stale after 3.0.0 (a screen, a control or a rule that changed) and fix them
   in the reference pages. Lesson prose under `apps/docs/course/` keeps describing the 2.1.0 screens on purpose: do not
   touch it.
5. `pnpm docs:build` and `pnpm check:docs` pass.

## Do not

- Do not touch `apps/game/`, `stores/`, `notes/release/`, `notes/plans/`, `scripts/`, or the lesson prose.
- Do not describe anything the game does not do, or promise anything for later.
- Do not add screenshots or clips; there is a store capture pass later and the docs clips stay silent and under 1MB.

## Acceptance

1. `pnpm docs:build`, `pnpm check:docs`, `pnpm check:hygiene` and `pnpm check:assets` pass.
2. No line in `README.md` or `game.md` claims 2.1.0 is current, and none claims a tag or store status that does not
   exist (`grep -n "2\.1\.0"` shows only historical statements).
3. The report lists, per 3.0.0 section of `game.md`, the claims checked, the source of each (file and constant), and
   every correction made.
4. The diff touches only `README.md` and `apps/docs/docs/game.md`, plus other reference pages under `apps/docs/docs/`
   if a stale statement was found there.

## Deliverables

`README.md`, `apps/docs/docs/game.md`, any stale reference page, `IMPLEMENTER_REPORT.md`.

## Settle these yourself

- How to phrase "not yet submitted" in the README (default: leave store status out and say what the tree carries).
- Whether a claim is doc-wrong or code-wrong when they disagree (default: the code and its tests are the truth; the
  report flags anything that looks like a code bug).

## How the director will judge

The director spot-checks ten of the audited claims against the code, reads the diff, and runs the acceptance
commands in your copy.
