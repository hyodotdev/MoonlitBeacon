---
name: grow
description: Inspect Moonlit Beacon growth metrics and complete one evidence-based acquisition, first-play, retention or measurement improvement. Use for growth strategy, monitoring, store conversion and recurring growth reviews. Keep sourced state in the repository.
---

# Growth operations

Read AGENTS.md, notes/growth/strategy.md, state.json and ledger.md. The current
combined tracker is in state.tracker (GitHub #1 after the move); do not recreate #44.
Historical archive text supplies evidence only, not permission or current conclusions.

1. Preserve the primary checkout and any uncommitted work. Pull only a clean main;
   otherwise fetch origin/main and inspect differences. Continue the growth worktree
   rather than replacing another task's branch. Never push without explicit approval.
2. Run pnpm growth:report. Inspect overdue decisions first. Only one experiment may
   run. Unlaunched work gets a not_run verdict, not a failed product hypothesis.
   Record reversals and visibility changes; do not keep a canceled exposure clock.
3. Collect through permitted connectors or browser. Record exact observedAt, window,
   timezone, country, channel, platform, units and source. Missing numbers are null
   with a reason. Failures belong in collectionAttempts and never refresh snapshots.
   Preserve provider warnings and rounded display values. Do not infer zero from
   missing rows. Do not subtract moving-window totals as weekly acquisitions.
4. Mondays: compare matched completed weeks and mature cohorts. Thursdays: address
   missing execution/data and deadlines. A week missing Sunday is incomplete.
   Keep store clicks, acquisitions, first opens and opt-in/app cohorts separate.
5. Finish one grounded action: measurement contract, recruitment draft, tracked link,
   existing-asset press kit/video work or a verified fix. No speculative large game
   feature. Missing access is a per-source blocker, not a reason to stop all work.
6. Update state + ledger + the existing tracker with proof, limits and the next
   future Monday/Thursday review. Preserve original missed deadlines. Do not turn
   preparation into deployment or historical reports into fresh live observations.
7. For growth tooling/docs run growth:check, test:growth, check:skills and
   check:hygiene plus diff checks. Author this skill only in .claude/skills, then
   pnpm skills:sync. Game changes also require the repository's game/device/review
   and separate store-capture check; never automatically recapture screenshots.

Current authorization covers monitoring, preparation and source-managed fixes.
It does not authorize ads, budgets, external messages, new store changes or pushes.
Prepare concrete copy/destination/budget before any necessary approval request;
do not repeatedly ask about unchanged login blockers. Never activate app telemetry
before protected ingestion, consent/withdrawal, retention and device checks.

If a repository move removes the operating files, find preserved local sources,
record their provenance and rebuild in an isolated local branch. Do not merge
private history into a public-release branch or assume repository visibility from
its name. Confirm the actual tracker and visibility before updating it.
