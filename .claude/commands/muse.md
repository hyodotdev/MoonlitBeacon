# Hand work to the implementer

Brief → run → judge → accept. The director (you) does not build the game; the implementer does. The rules of the split
are in [`AGENTS.md`](../../AGENTS.md#director-and-implementer). Who the implementer is, and with which model, is set in
[`scripts/muse.config.json`](../../scripts/muse.config.json) and nowhere else: `pnpm muse who` prints it.

## Usage

```text
/muse <what the user asked for>    write the brief, run it, judge the result
/muse status                       runs so far (pnpm muse status)
/muse accept <tag>                 after you have judged it
```

---

## 0. Before you write anything

1. `pnpm muse doctor` once per session. It checks the config against the CLI, the sign-in and the standing orders.
2. Look at what exists and **measure the current state** with the commands the task will be judged by (tests, the play
   bot, node budgets, a screenshot). A brief with a measured starting point is a brief the result can be compared to.
3. Ask the user only when the decision is theirs: art taste, what ships, anything public or irreversible. Everything
   else: decide, and say what you decided in the brief.

## 1. Write the brief

Copy [`brief-template.md`](../../notes/workflow/muse/brief-template.md) to
`notes/workflow/muse/briefs/NNN-slug.md` (next free number). One task per brief. The implementer has no memory of the
conversation, so put in: the user's words verbatim, where things stand (files, numbers, the commands that produced
them), what to do and not to do, acceptance criteria a command or a number can settle, and the deliverables by file
name. Never put a secret, a token, a private path or a personal detail in it, and never name a model.

## 2. Run it

```bash
pnpm muse run notes/workflow/muse/briefs/NNN-slug.md
```

It copies the repo without secrets and without a git remote into `builds/muse/<tag>/work`, hands the standing orders
and the brief to the implementer, and waits. A round can take an hour or more: run it in the background and wait for
it to finish; do not poll. `pnpm muse status [tag]` shows where a run is. On finish the runner prints the
implementer's report and a summary of what changed, with protected and watched paths marked.

**If starting it is refused** (a permission prompt, a classifier), stop and tell the user what you tried and why. Do
not start it another way.

## 3. Judge

While a round runs, `pnpm muse log <tag>` shows what it has been doing (commands, files read and written) and
`pnpm muse diff <tag>` what it has changed so far; both only read.

A report is a claim. Check the work:

- **Diff against report.** `pnpm muse diff <tag>` (`--full`, `--names`). Does every claim in the report have a change
  behind it, and every change a reason? Anything outside the brief's scope is a finding.
- **Protected and watched paths.** A protected path (guide, `.claude/`, guard, version lock, secrets) blocks `accept`.
  A watched one (`package.json`, `project.godot`, `stores/`, release notes) is read twice.
- **Read the code**: new files in full, changed hunks with their surroundings. Look for: constants instead of
  magic numbers, typed GDScript, `##` doc comments that say a role, no leftover debug, no weakened test.
- **Run the checks yourself, in the copy.** `pnpm muse judge <tag>` runs the standard battery there (quick checks,
  the node budget, all game tests, the natural-loop and guardian-gauntlet bot batches, the store fingerprint) and keeps
  each output under `builds/muse/<tag>/judge/`; `--steps nat,gauntlet` picks some. Or by hand
  (`cd builds/muse/<tag>/work`): `pnpm test:game` (or the touched tests
  with `pnpm godot:isolated`), `pnpm game:check`, `pnpm check:hygiene`, `pnpm check:locale`, `pnpm check:assets`,
  `pnpm docs:build` as the change calls for. Repeat the measurements the brief named and compare them with the
  numbers you took in step 0. Numbers you did not reproduce are not evidence.
- **Spot-check the tests**: break one guarded line in the copy and watch its test fail. A test that cannot fail is
  worth nothing.
- **Look at it.** For anything a player sees, render it with the desktop harnesses (`tools/shot_*.tscn`, in the
  foreground) and look at the pictures against the rules in [`/review`](./review.md) and the art direction in
  `AGENTS.md`. Never a phone or emulator without the user's word.
- **Rules.** The one banned word, the locked values, the store-screenshot fingerprint
  (`pnpm check:store-screenshots` is expected to be red after any `apps/game/` change; it is not a reason to recapture).

## 4. Decide

| Verdict | What you do |
| --- | --- |
| Good | `pnpm muse accept <tag> --check`, then `pnpm muse accept <tag>`. It applies the change to the working tree. Then `/verify` on the real tree |
| Not yet | Write a short correction brief (what is wrong, the evidence, what to change) and `pnpm muse run <brief> --continue <tag>`. It works in the same copy and, where the CLI allows, the same session. After three rounds on one defect, tell the user instead of a fourth |
| Wrong | `pnpm muse discard <tag>` and say why in the next brief |
| Accepted by mistake | `pnpm muse revert <tag>` |

**You do not patch the implementer's work by hand**, not even one line: send it back. That is what keeps the two roles
honest, and it is what the user asked for.

`accept` refuses a change that no longer applies because the real tree moved on since the copy was made. Start a new
run from a fresh copy, or send the correction to the same copy if only the brief was stale.

## 5. Report to the user

In player terms first: what changed in the game. Then the evidence: the commands and the numbers, before and after.
Then what the implementer got wrong and how it was fixed, what is left, and what needs the user. Credit the
implementer with the line `pnpm muse who --line` prints. Never present the implementer's work as your own, and never
say a check passed that you did not run.

## Operations stay with the director

Builds, test runs, measurements, captures, `/verify`, `/device`, commits and the like are operations, not authoring. Run
them yourself, under the same confirmations as ever (no push, no pull request, no upload, no store screenshot
recapture without the user's explicit instruction). When an operation needs a file changed first, that change goes
through a brief.

## Commit trailer

After the tool's own attribution line, add the implementer's:

```text
Implemented-by: <the line pnpm muse who --line prints>
```

## Failure modes

| Symptom | What to do |
| --- | --- |
| The report says done and the checks fail in the copy | Return the failing output in a correction brief. The round is not accepted |
| The report claims something the diff does not contain | Say so in the correction brief. Treat the rest of the report with more suspicion |
| A protected path changed | Refuse. If the change is right, review it, then `accept --allow <path>`; otherwise return it |
| A command was blocked by the implementer's sandbox | Run it yourself as an operation and put the output in the correction brief |
| The run hung or hit the time limit | `pnpm muse status <tag>`, read `events-N.jsonl`; return with a narrower scope |
| The CLI refused the model or effort | `pnpm muse models`, fix `scripts/muse.config.json`, `pnpm muse doctor` |
