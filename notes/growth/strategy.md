# Growth operations

Updated 2026-09-21. `state.json` holds sourced observations, attempts, work and
verdicts; `ledger.md` explains decisions. The current tracker is GitHub **#1**.
The old #44 returns 404 after the repository move. The preserved
`archive-20260918.md` is historical evidence, not current instructions or permission.

## Operating source after the repository move

The new main is `10d31c0`. The primary checkout is working on a separate CI fix.
Growth work lives on the local `chore/growth-monitoring` branch in its managed
worktree. Find it with `git worktree list`. Do not switch the user's checkout,
merge old private history into main, or push this branch without confirmation.
This round rebuilt the missing report/state instead of pretending the former
`1380e68` commit still exists. `AGENTS.md` replaces the absent `CLAUDE.md`.

The remote repository currently reports **private**, despite the public-release
commit title. Do not infer visibility or permission to publish internal analytics
from a commit title. No visibility changes are part of growth monitoring.

## Goal and evidence

Increase people who play and return. KR/Android remains a provisional focus,
not a measured audience. The completed Sep 7–13 window has three Play acquisition
events, all Browse; the country table exposes two in India on Sep 9. Country
suppression/missing rows must not be filled with guesses or read as Korean traffic.

Sep 21 direct observations: Play Aug 23–Sep 19 shows approximately 1.14K device
impressions, 3 acquisitions, 1 displayed first open, 4 monthly active devices,
no D7 value. First-open statistics explicitly warn that some data is unavailable.
The Sep 7–13 first-open table shows 1 (India), with the same warning. Neither
an activation rate nor deterioration can be inferred from these incomplete,
unmatched cohorts. Moving-window totals are not weekly net changes.

ASC Aug 21–Sep 19 UTC now supplies 145 impressions, 13 product-page views and
1 first-time download (Sep 17). These are totals, not unique-device impressions.
Opt-in retention for the selected Sep 19 remains Not Enough Data.

## One active observation

The old E01 recruitment has no launch evidence at its Sep 21 decision date:
**not run**, not a failed product hypothesis. E02 remains queued. Historical
YouTube hypothesis H3 was briefly public, then reverted to unlisted according
to the preserved Sep 18 addendum; the planned Sep 25 public-distribution read is
void. This is not a never-public video and is not proof of YouTube effectiveness.

The Play listing is different: on Sep 21 its currently-published default listing
contains video `2JeLS582sRA`; publishing overview says last published Sep 18.
E03 observes this already-existing change. It does not authorize another upload,
listing edit or public switch. Follow [video-measurement.md](video-measurement.md).
No second live experiment until its Oct 2 decision. Preparation can continue.

## Review cadence and boundaries

Monday/Thursday 10:00 Asia/Seoul. Next Sep 24; monthly decision Oct 2.
Fetch origin/main before each run, preserve other work, and report divergence.
Read state/log/tracker, collect with permitted connectors/browser, judge overdue
hypotheses, finish one grounded action, verify and record. Failed attempts never
refresh an old observation date. Keep original missed deadlines visible.

Use complete, non-overlapping Monday–Sunday windows and matched units/filters.
The latest Grow end is Sep 19, so Sep 14–20 is not complete yet. Retention needs
mature numerator and denominator; Play, ASC opt-in and app-consent cohorts differ.
No review/problem rows is not a measured 0% crash or ANR rate. A rounded UI count
stays a raw display value unless an exact export is observed.

Paid marketing budget remains 0 KRW. No ads, spending, external recruitment or
community posting is authorized by this automation. Prepare a destination,
recipient, exact copy, attribution, budget ceiling and stop rule before requesting
any missing approval. Previously reported account actions are history, not reusable
authorization. Do not ask repeatedly about the same login problem.

In-app telemetry stays disabled. Reusable event code exists, but authentication,
quota, idempotent acknowledgements, consent/withdrawal, TTL/export provenance,
platform device checks and store disclosures must precede activation. The prior
G08 design was reported in this conversation, but its commit/file is absent from
the new repository; do not mark G10 implementation done from that report.

## Commands

`pnpm growth:report` reads recorded data; it does not query consoles.
`pnpm growth:check` validates structure. `pnpm test:growth` tests missing data,
provenance dates, overdue work and experiment constraints. Date override:
`pnpm growth:report -- --date 2026-10-02`.

The heartbeat is updated through the scheduling tool after these local paths are
verified. Local scheduled work needs the computer and app available, with console
access at execution time ([official scheduling documentation](https://learn.chatgpt.com/docs/automations)).
