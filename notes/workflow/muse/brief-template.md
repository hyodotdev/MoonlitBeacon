# Brief template

Copy to `notes/workflow/muse/briefs/NNN-slug.md` (next free number) and fill it in. A brief is the whole of what the
implementer knows about the task besides `AGENTS.md` and the standing orders: it has no memory of the conversation
with the user. Say what you would say to a capable colleague who just joined. Do not name a model anywhere in it.

```markdown
# Brief NNN: <title>

## The ask
The user's own words, verbatim (in their language), then one sentence of what that means for the game.

## Why, and what "good" feels like
What the player should experience. What was wrong before. Who will judge it and how.

## Where things stand
What already exists (files, functions, tests), what was measured last and with which command, what is
uncommitted work that this builds on. Point at files instead of pasting them.

## Do
- The work, in the order it should be done, each item small enough to check.

## Do not
- What is out of scope, and which nearby thing looks tempting and is wrong to touch.

## Acceptance
Each criterion is a thing the director can check without trusting the report: a command and the result it must
give, a number and its band, a screen and what it shows. "Feels better" is not a criterion; say how it is measured.

## Deliverables
Code, tests (registered in the runner), docs (`apps/docs/docs/game.md`), notes (`notes/plans/3-0-0-build-log.md`),
assets and manifest rows. Name the files.

## Constraints specific to this task
Budgets, locked numbers, tests that pin behaviour and must stay as they are.

## Settle these yourself
Open questions, each with the default to take if you have no better reason. The director cannot answer mid-run.

## How the director will judge
Which commands will be run on your result, which numbers will be compared, and what is read by eye.
```

## Writing rules

- One task per brief. If the list of "Do" items runs past a screen, split it into two briefs.
- Quote measured numbers with their command; a claim without one is a guess and should be labelled as such.
- A correction to a finished round is a new short brief (`--continue`): what was wrong, the evidence, what to change.
  Do not fix the implementer's work by hand; send it back.
- Never put a secret, a token, a private path or a personal detail in a brief. Some implementer models may use what
  they receive to improve the provider's products (`pnpm muse who` says whether the configured one does).
