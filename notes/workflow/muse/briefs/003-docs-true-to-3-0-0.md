# Brief 003: Docs true to 3.0.0

## The ask

The user asks to continue the 3.0.0 renewal, strengthen the world and immersive story, review the game until stable,
and prepare a merge-ready PR without merging. The docs a reader opens first must say what the tree implements,
and every number in them must be one the game really has.

## Why, and what "good" feels like

`apps/docs/docs/game.md` is the reference students and the user read. Its 3.0.0 sections were written while the game was
being built, partly from memory. The release is not done until each claim in them has been checked against the code and
the tests, and the front doors (README, the version passage) say 3.0.0. The tone stays plain: what the player sees and
how to answer it. No editorial policy or presenter directions (see AGENTS.md).

## Where things stand

- Read the actual README on this main-integrated baseline. Its version/course passages still describe the tree as
  2.1.0. Preserve current main's IAP 3.6.1 / Shop documentation and vendor/license explanation.
- `apps/docs/docs/game.md`: sections Forks, The endless stretch: Depth, Guardian mutations, Guardians of the later
  places, Reading a guardian's attack, UI and story structure (3.0.0), and "9. Version tags" (mentions 2.1.0 and says
  3.0.0 is not part of the course, which is right: the lessons keep describing the 2.1.0 screens on purpose).
- The version is locked at 3.0.0 (Android code 15, iOS build 10) in `project.godot` and `export_presets.cfg`. 2.1.0 is the last
  recorded store release (not a fresh remote audit); 3.0.0 has not been submitted or tagged.
- `pnpm check:assets` and `pnpm check:store-metadata` are green today. `pnpm docs:build` is the check that finds dead
  links.
- The accepted game includes slow bullet weaving, the result Depth caption and shop wrapping, and the Lantern
  Hollow / Nari road-home story with six place restorations. Audit the actual final files, not an earlier brief's
  intent. Brief 007 runs separately on store copy and author records; it does not edit README or reference pages.
  Do not edit `notes/plans/3-0-0-build-log.md`, `notes/plans/3-0-0-expedition.md`,
  `notes/release/` or anything under `stores/`.

## Do

1. README: the version row says 3.0.0 (Android code 15, iOS build 10), with 2.1.0 as the last recorded store release;
   the sentence about the course says the course stops at 1.0.0, the tutorial closed with 2.1.0, and the tree now
   carries the 3.0.0 renewal. Describe 2.1.0 as the last recorded store release, not a newly verified store audit.
   Do not claim a tag, submission, live 3.0.0 build or release date that does not exist.
2. `game.md`, "Version tags": one short paragraph saying what 3.0.0 is (a new UI, a structured story, six places with
   forks, an endless stretch that stays playable, more guardians and skills), not part of the course, and not yet
   tagged. Explain the concrete road-home premise and discoveries briefly. Keep the tag list as it is.
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
- Do not add screenshots or clips; no store recapture is authorized and existing docs clips stay silent and under 1MB.

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
