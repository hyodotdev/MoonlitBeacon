# Growth strategy

Revised 2026-09-22. `state.json` holds sourced observations, attempts, work and
verdicts; `ledger.md` explains decisions. The current tracker is GitHub **#1**.
The preserved `archive-20260918.md` is historical evidence, not current
instructions or permission.

## Operating source after the repository move

Main is `f4b283f`. The remote API still reports **private** despite the
public-release commit title; do not infer visibility or permission to publish
internal analytics from a title. The Sep 21 growth branch and the CI fix are
merged; the managed growth worktree is removed. The `private/pre-public-full`
snapshot branch was deleted at the user's request on Sep 22 — its three
campaign drafts (cowork-handoff, trailer-distribution, youtube-aeo) survive
only as described inside `archive-20260918.md`. Do not reference them as live
files.

This round works on `feat/first-play-and-growth`, unmerged. No visibility
changes are part of growth monitoring.

## Diagnosis: the constraint is the top of the funnel

Sep 21 direct observations: Play Aug 23–Sep 19 shows approximately 1.14K device
impressions, 3 acquisitions, 1 displayed first open, 4 monthly active devices,
no D7 value. First-open statistics explicitly warn that some data is unavailable.
The Sep 7–13 first-open table shows 1 (India), with the same warning. Neither
an activation rate nor deterioration can be inferred from these incomplete,
unmatched cohorts. Moving-window totals are not weekly net changes.

ASC Aug 21–Sep 19 UTC now supplies 145 impressions, 13 product-page views and
1 first-time download (Sep 17). These are totals, not unique-device impressions.
Opt-in retention for the selected Sep 19 remains Not Enough Data.

At this scale every rate is noise. Retention, conversion, and difficulty work
all wait on one thing: more first opens. The KR/Android focus stays provisional.
Observed acquisitions are Browse/India; no Korean value exists anywhere. Stay
geo-agnostic — English-first creative, no KR-only spend — until data says
otherwise.

## One active observation

E03 observes the already-published Play listing video (`2JeLS582sRA`, last
publish Sep 18). Follow [video-measurement.md](video-measurement.md). No
second live experiment until its Oct 2 decision. Preparation below is not a
launch.

The old E01 recruitment has no launch evidence: **not_run**, not a failed
product hypothesis. Its replacement is P3, not a rerun.

## Approval packages (prepared, not executed)

Each package is ready for a yes/no. Nothing here spends, posts, or ships
without the user. Ordered by readiness.

### P1 — itch.io page launch (most ready)

Everything is staged since Sep 17: 9 screenshots (2424x1080, viewed clean),
`cover-630x500.jpg`, signed direct APK 2.1.0 (versionCode 14, apksigner
passes) in `builds/release/`, plus KO/EN/JA/ZH page copy in
`notes/release/store-page.md`. The game changed since (title transition veil,
transition-only, no rest-state pixels), so re-verify the staged set against a
fresh build before upload; do not trust it blind.

- Destination: new itch.io project on the user's account. Upload and the
  public switch are user-side; the agent prepares and verifies only.
- Steps: restricted test upload → wiped-device install check (release
  checklist section 10) → public switch.
- Attribution: UTM-tagged store links on the page
  (`utm_source=itch_io&utm_medium=store_link&utm_campaign=launch`); itch
  referrers as the second source.
- First read 7 days after public: page views, downloads, click-through.
- Stop rule: 200+ views with 0 downloads in 7 days pauses the page for a
  cover/copy revisit before any other move. Reversible: unpublish anytime.

### P2 — YouTube trailer public switch

Asset `LDsiyftf93c` is unlisted on the 2,035-sub channel with AEO copy,
captions, and thumbnail done. The Sep 17 twenty-minute public stint voided
H3; a fresh switch restarts its clock.

- What it takes: user flips to public, optionally pins the store-links
  comment (links already in the description).
- 7-day read from switch day: views, click-through to stores, search/AEO
  pickup. H3 verdict rule from the archive applies to the new clock.
- Stop rule: under 100 views in 7 days means reach, not creative, is the
  problem — fix distribution (P1, P4) before any recut.
- The Sep 18 revert signals real hesitation. This package asks the decision
  plainly instead of assuming it.

### P3 — First-play observations without community posts (E01b)

Reddit/X posts stay out per the user's Sep 18 call, so G06 remains blocked on
a destination. Options for the user to pick exactly one: (a) itch.io devlog
plus comments ask after P1, (b) testers from the user's own network (user
recruits; agent drafts the ask and the consent script), (c) course readers
after P4. Target: five observations.

- Per observation: device, OS, consent note, first-open to beacon-1 reached
  (yes/no plus time), deaths under 60s, quit point, one verbatim quote.
- No PII, no recording without consent, manual notes until G10 lands.
- Exact copy is drafted after the destination pick, never before.

### P4 — Course site deploy (dependency, growth does not own it)

Sixteen chapters are written and the site is undeployed; the repo is private
and Pages needs a public repo or a Team-or-above org. Growth value if it
ships: a course-to-game funnel with tracked store links (E02 attribution
input) plus a search/AEO surface that compounds. Action belongs to the user:
decide repo visibility first.

## E02 design (queued, starts after the E03 verdict)

Question: which owned channel converts to installs. Candidates are whichever
of P1/P2 went live. If neither is live on Oct 2, E02 stays queued — say so
explicitly instead of running a phantom experiment.

- Attribution: per-channel UTM links, console source rows where available,
  itch referrers. Keep store clicks, acquisitions, and first opens separate
  per the standing rules.
- Window: 7 days from channel launch; decision Oct 9.
- Verdict: descriptive installs per channel at small n; inconclusive on zero
  across the board. A winner needs at least 5 attributed installs plus a
  qualitative replication (second week or second creative). No paid scaling
  off this read.

## First-play evidence (Sep 22 device round, recorded not acted on)

Played the main build on the Pixel_10 emulator (shared instance, software
rendering, 1–20fps): title, tap-to-start, intro dialogue, move, auto-attack,
chains, embers, missile hints, five level-ups, two evolutions, three deaths,
result count-up with grade and shards, three retries, debug beacon plus
brightening, tutorial announces. Result tappability, core-timer pause
behavior, and a suspected copy typo were all checked and cleared — the typo
was a font misread, confirmed against the CSV and the engine-loaded value.

Two outcomes. Shipped in this branch: a title-to-arena transition veil with
threaded load (the load hung on dead black with no feedback; fast devices
see no change). Deliberately not shipped: difficulty tuning. Three
unassisted runs ended under 25 seconds with zero beacons kindled, but that
read is confounded by emulator lag and tester skill. Tuning waits on funnel
telemetry (G10): first-open to beacon-1, deaths under 60s, quit points. Do
not tune on the anecdote.

Noted follow-ups, none in this round: intro-story frequency (repeat-by-design
today, needs a product call), matching veils for retry and arena-to-title
returns, device passes for dash feel, pause, shrine, and guardian (all
unverified at 1fps).

## Review cadence and boundaries

Monday/Thursday 10:00 Asia/Seoul. Next Sep 24; E03 decision Oct 2, E02
decision Oct 9 if it launches. Fetch origin/main before each run, preserve
other work, and report divergence. Read state/log/tracker, collect with
permitted connectors/browser, judge overdue hypotheses, finish one grounded
action, verify and record. Failed attempts never refresh an old observation
date. Keep original missed deadlines visible.

Use complete, non-overlapping Monday–Sunday windows and matched units/filters.
Retention needs mature numerator and denominator; Play, ASC opt-in and
app-consent cohorts differ. No review/problem rows is not a measured 0% crash
or ANR rate. A rounded UI count stays a raw display value unless an exact
export is observed.

Paid marketing budget remains 0 KRW. No ads, spending, external recruitment or
community posting is authorized by this automation. Prepare a destination,
recipient, exact copy, attribution, budget ceiling and stop rule before requesting
any missing approval. Previously reported account actions are history, not reusable
authorization. Do not ask repeatedly about the same login problem.

In-app telemetry stays disabled. Reusable event code exists, but authentication,
quota, idempotent acknowledgements, consent/withdrawal, TTL/export provenance,
platform device checks and store disclosures must precede activation.

## Commands

`pnpm growth:report` reads recorded data; it does not query consoles.
`pnpm growth:check` validates structure. `pnpm test:growth` tests missing data,
provenance dates, overdue work and experiment constraints. Date override:
`pnpm growth:report -- --date 2026-10-02`.

The heartbeat is updated through the scheduling tool after these local paths are
verified. Local scheduled work needs the computer and app available, with console
access at execution time ([official scheduling documentation](https://learn.chatgpt.com/docs/automations)).
