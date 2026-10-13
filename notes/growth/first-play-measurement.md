# Course channel measurement contract (E04)

Prepared 2026-10-13. Read-only reporting rules for the single coordinated
course program: the course-to-store attributed read plus the five manual
first-play sessions in [first-play-protocol.md](first-play-protocol.md).
No publication proof exists; no clock has started. This contract replaces
nothing: E01, E02, H3, and E03 keep their history and verdicts. The earlier
E01b/E02-course scaffolding is superseded by this one coordinated identity.

## Launch facts (initially null)

- Actual launch timestamp: null (recorded only from verified publication
  evidence, kept by the director).
- Launch proof: null.
- Do not start any window until both are filled.

## Window and identity

- Read seven COMPLETE reporting days after verified publication. Record the
  fixed start/end dates and the Console timezone at the first read; never
  shift them afterward.
- Play reports expose UTM source and campaign, not medium. Channel identity
  is exact: `utm_source=moonlit_course` with
  `utm_campaign=course_first_play_20261013`
  (see `apps/docs/src/storeLinks.ts`). Only rows matching both count as
  course-attributed. `utm_medium=referral` stays on the URL as annotation
  only; it is never a matching key.
- iOS links carry no attribution by design and are unmeasured. Never claim
  a measured iOS course read.

## Metrics and their limits

- Primary: course-attributed listing visitors and unique Install/Open clicks
  from the store listing report. Context only: global Grow acquisitions and
  first opens, unless matching campaign attribution is independently exposed
  for them. Keep clicks, acquisitions, and first opens separate — clicks are
  not acquisitions, acquisitions are not first opens, and none of them are
  unique new people.
- No rows means unknown, not zero: small campaign rows can be suppressed
  into Other. First-open data carried a provider outage warning when
  observed on Sep 21; that warning was not freshly verified on Oct 13, so
  do not present it as a current outage.
- Quantitative verdicts need at least 100 listing visitors in the window;
  below that, the read is descriptive or inconclusive. Never claim 100%
  activation, a causal winner, or an activation division at any sample size.

## Decision

- After the window closes and every source reports through its end date:
  report counts descriptively with traffic mix and uncertainty, or verdict
  **inconclusive** when a window is unavailable, filters differ, or counts
  are too small to distinguish ordinary variation.
- Keep the event history; specify the missing evidence and one next action.
  An observed improvement can motivate another test; it does not authorize
  paid scaling.
