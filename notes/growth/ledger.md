# Growth ledger

Current strategy: strategy.md. Structured evidence: state.json. Tracker: #1.
Preserved Sep 18 history: archive-20260918.md. Its old conclusions and permissions
are not authoritative over the current user instructions or newer observations.

## 2026-09-22 — Strategy round and first-play verification

### Repository and continuity

- Main is `f4b283f` after merging the CI fix, growth monitoring, and the MCP
  untrack. CI and Android packages both success on the push. Remote still
  reports **private**.
- `fix/ci-pnpm-version-conflict` deleted (merged, no unique content).
  `chore/growth-monitoring` deleted with its managed worktree (merged via
  `f66077a`; worktree was clean). `private/pre-public-full` deleted at the
  user's explicit request with no backup: its three campaign drafts survive
  only as described in the archive. Strategy no longer references them as
  live files.
- This round works on `feat/first-play-and-growth`, pushed as PR #2, unmerged.
  Loop-review runs before any merge decision.

### Device playtest (main build, Pixel_10 emulator, software GL 1–20fps)

- Covered: boot, title, tap-to-start, intro dialogue (2 lines), objective
  teach, swipe move, auto-attack, chains, embers, missile hints, six
  level-ups with evolution picks, Moon Dance T1 completion, three deaths,
  result count-up with grade and shards, three retries, debug beacon plus
  Blue Dawn brightening, tutorial announces (move, dash, beacon, embers).
- Checked and cleared: result tappability (known prior block, works),
  missile-core timer during modals (tree pause freezes it, correct), a
  suspected "cooldwon" typo (font misread; CSV, engine-loaded value, and 4x
  magnification all read "cooldown").
- Shipped: title-to-arena transition veil with threaded load. The load hung
  on dead black with no feedback; the load now overlaps the flare and the
  veil covers only the leftover. Fast devices see no change. Regression test
  `test_title_transition` (11 cases) plus device tap-to-arena pass.
- Recorded, not acted on: three unassisted runs ended under 25s with zero
  beacons. Confounded by emulator lag and tester skill; tuning waits on
  funnel telemetry (G10). Follow-ups noted in strategy, none implemented.

### Strategy and state

- Diagnosis: top of funnel is the binding constraint (3 acquisitions/28d, 1
  iOS download); all rates are noise. KR focus stays provisional (observed
  traffic is Browse/India). Geo-agnostic until data says otherwise.
- **G13 done:** itch.io launch approval package (P1). Staged Sep 17 set must
  be re-verified against a fresh build; upload and public switch stay
  user-side. UTM attribution, 7-day read, stop rule included.
- **G14 done:** E02 design. Starts after the E03 verdict; runs only on
  channels actually live; decision moved Oct 2 → Oct 9. Queued, not launched.
- P2 (YouTube public switch), P3 (recruitment without community posts), P4
  (course deploy dependency) prepared as yes/no packages in strategy.md.
- E03 unchanged and still the only running experiment. Budget still 0 KRW.
  No ads, posts, uploads, or telemetry activation in this round.

## 2026-09-21 — Monday review and operating-memory repair

### Repository and continuity

- Preserved clean primary checkout `fix/ci-pnpm-version-conflict` at `536a547`.
  Fetched origin/main successfully: `10d31c0`, primary checkout 1 ahead / 0 behind.
- Main now has a single public-release preparation commit; remote API still reports
  **private**. The move removed CLAUDE.md, grow skill, strategy/state/ledger and
  growth:report. The requested command failed as missing before repair. #44 returned 404.
- Existing replacement **#1** was found and read; no new issue created. Its text
  lagged the Sep 18 preserved log. Old local growth commit `1380e68` is unavailable
  in this repository. Prior conversation reports are not recreated as new measurements.
- Read grow and growth-log from `private/pre-public-full` (`d74380b`). Preserved the
  latter verbatim under a provenance header. Isolated current-main-based work on
  `chore/growth-monitoring`; no merge of the old private history, no change to the CI branch.
- Rebuilt source-managed state/report/grow workflow using AGENTS.md and current #1.
  The report is a reader/validator, not a console collector. Failures and observations
  have separate dates. Schema 2 identifies reconstruction instead of pretending
  byte-for-byte restoration of the lost schema 1 files.

### Direct observations (all read today)

- Play Grow **Aug 23–Sep 19**, all countries / device: impressions **about 1.14K**
  (UI `1.14천`, exact count unavailable), acquisition events **3**, displayed first
  opens **1**, monthly active devices **4**, D7 **Data unavailable**.
- The acquisition table contains only **Sep 8: 1; Sep 9: 2**, all Browse. These are
  the same dates seen in the Sep 14 conversation; no new acquisition date appears
  through Sep 19. The lower 28-day total is not evidence of churn or negative new installs.
- Completed **Sep 7–13** week: Browse acquisition events **3**. Country table:
  all countries Sep 8=1/Sep 9=2; India Sep 9=2 and Sep 8=`-`. No KR value.
  Do not guess the country of the remaining event or read `-` as zero.
- First-open detail for that week shows **Sep 9: all 1, India 1**, with an explicit
  provider warning: **some first-open device data is currently unavailable**.
  This invalidates an unqualified activation baseline. No 1/3 activation claim.
  The latest Grow end Sep 19 means Sep 14–20 is still incomplete.
- Play listing top **Aug 20–Sep 16**: visitors **31**, unique install clicks **3**,
  UI rounded click rate **10%**. The separate default row is **48 / 6.3%**, row
  window unconfirmed. Top window ends before the video publication; no post-video result.
- Play reviews all-time **2008-10-01–Sep 21**: ratings with reviews **0**, users **0**.
  Vitals **Aug 24–Sep 21**, all categories / user-perceived filter removed / unarchived:
  no issue rows; update label Sunday 9:00 PM. Crash and ANR rates/denominators missing.
- ASC login works again. **Aug 21–Sep 19 UTC**: total impressions **145**, product-page
  views **13**, first-time downloads **1**, on **Sep 17**. Downloads were previously
  unavailable in this thread; do not infer the change from an assumed historical zero.
  Sep 19 selected / Opt-in Only retention remains **Not Enough Data**.
- Exact URLs, filters and limitations are in the 10 new snapshots. No past observation
  date was refreshed and no failed login state was copied forward as today's outcome.

### Verdicts and completed action

- **E01: not_run**, original Sep 21 decision date. No recruitment/publication proof.
  This is an execution miss, not failure of the first-beacon hypothesis. E02 remains queued.
- Preserved Sep 18 addendum says YouTube master was public 22:39–22:59 UTC on Sep 17,
  then reverted unlisted. **H3 public distribution: inconclusive / clock canceled**;
  Sep 25 seven-day read is void. Do not repeat the archive's contradictory never-public
  or still-running statements. Studio visibility was not freshly inspected this round.
- Existing trailer files were found in the primary checkout: EN 21,154,719 bytes,
  KO 20,598,919, Play-specific master 26,668,378. Creation/visual-check evidence is
  attributed to the Sep 17 archive, not a new review or capture today.
- **G12 completed:** video-measurement.md. The currently-published default listing
  contains `2JeLS582sRA`, and publishing overview shows latest publish Sep 18.
  E03 observes this already-shipped listing change; Sep 21 is our first direct
  confirmation/enrollment, not a claimed publication timestamp. Only E03 is running.
- Defined matched pre-week Sep 7–13, transition Sep 14–20 excluded, conservative
  after-week Sep 21–27, and Oct 2 verdict. Keep top listing clicks/visitors together,
  source/country mix separate, first-open outage explicit, no causal winner or ad scaling.
  Fixed pre-week listing click/visitor baseline is still to collect on Sep 24.
- G03 remains overdue (KR and D1), G06 blocked (external approval), G09 and G10 due
  today and incomplete. Original dates retained. G07 is no longer falsely labeled
  unproduced. This round prioritized operating continuity and existing-video measurement
  over implementing a server from a missing design artifact.

### Validation and next run

- Growth structure validation, growth regression tests (7), skill sync tests (4)
  and byte-identical mirror check passed. Tests cover failure/observation separation,
  invalid dates, false zeros, overdue work, no-launch verdicts, single active experiment,
  completion proof, budget approval and provider warning preservation.
- Heartbeat `automation` was updated through the scheduling tool, preserving ACTIVE,
  the same thread and Monday/Thursday 10:00 cadence. It now points to the managed
  growth worktree, AGENTS.md and tracker #1. Sep 19 completion is not evidenced; no
  successful run is invented. Next **Sep 24**, E03/monthly decision **Oct 2**.
- Local operations and measurement documents only: no game changes, telemetry
  activation, screenshot capture, store mutation, outbound promotion, paid spend or push.
  No app redeployment is needed for these changes.

- Final checks: saved heartbeat target/cadence/thread re-read successfully; existing #1
  updated and re-fetched body matched exactly. G11 completed. Repository hygiene and
  diff checks passed. The primary checkout was preserved; source commit stays local.

## 2026-09-26 round (PR #3, merged da0e0db)

- English course-clip reshoot shipped: 33 clips + 32 posters, Lesson 15-16
  staged via Movie Maker, 3 prose notes where the final game differs.
  `pnpm verify` exit 0; review-self loop ran 5 rounds, last two clean.
- Course site dependency (strategy P4) closed: repo API visibility PUBLIC
  verified Sep 26, Pages deploy workflow success, 16/16 lesson pages and
  70/70 media assets HTTP 200 by direct fetch. E02 still needs tracked
  store links on the course pages for attribution.
- Sep 24 scheduled review was missed (no successful heartbeat run evidenced;
  none invented). Next review Sep 28. Overdue items carried unchanged:
  G03/G09/G10 ready-overdue, G06 blocked on recruitment approval, E01
  not_run. E03 running, decision Oct 2. Budget stays 0 KRW.
- Tracker #1 body updated with this round; "API reports private" corrected.
