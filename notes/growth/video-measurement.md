# E03 — observe the existing Play listing video

Prepared and source-checked 2026-09-21. This is an observational measurement plan,
not a newly launched A/B test or permission to change store visibility.

## Confirmed exposure and limits

- Currently-published default listing contains `https://www.youtube.com/watch?v=2JeLS582sRA`.
- Publishing overview says latest publish Sep 18; exact video publication time
  and per-country delivery are not independently known. First direct verification
  in this round is Sep 21. Keep these dates distinct.
- Historical YouTube master `LDsiyftf93c` was made public briefly and reverted
  according to the Sep 18 archive. Cancel its Sep 25 public-distribution deadline.
  An unlisted Play-specific video can remain in the listing; it is a separate exposure.
- All Sep 7–13 acquisitions predate the recorded video change. They cannot be
  claimed as video conversions. The same applies to the Sep 17 iOS download.

## Comparable windows

| Window | Dates | Purpose | Collection status |
| --- | --- | --- | --- |
| Before | Sep 7–13, Monday–Sunday | Complete pre-change week | Play Browse acquisition rows 3; first-open displayed 1 with provider warning; listing visitor/click baseline still to collect |
| Transition | Sep 14–20 | Publication and reporting overlap | Exclude from before/after comparison; Grow data only through Sep 19 today |
| After | Sep 21–27, Monday–Sunday | First conservative full week after direct confirmation | Not yet observed; collect only when each source reports through Sep 27 |
| Decision | Oct 2 | Assess comparable data and next action | Do not extend silently or call missing data a win |

Use the same all-country scope initially. Preserve country/source breakdowns only
where provided; do not silently compare KR traffic to India or all countries.
Keep top listing visitors + unique install clicks together and separate from the
default-listing row. Sep 21's top listing report (Aug 20–Sep 16, visitors 31,
install clicks 3, UI click rate 10%) is context only, not the seven-day baseline.
Its window ends before the recorded video publication, so it has no post-video evidence.

Primary read: top listing unique install clicks / visitors, with both counts,
exact time zone/window and filters. Secondary: acquisition events by source/country.
First opens remain an incomplete diagnostic while the console warning exists.
Neither click count nor device acquisition events are unique new people. A simple
before/after rate cannot separate video, traffic mix, seasonality or other changes.

## Decision rule and next actions

1. Sep 24: read the publishing status without modifying it; collect the fixed
   pre-week listing visitor/click baseline and note whether the first-open outage
   remains. If the report cannot supply the fixed window, preserve null + reason.
2. Oct 2: collect the after-week only if the report has reached its end date.
   If either window is unavailable, filters differ, the video is no longer visible,
   or counts are too small to distinguish ordinary variation, verdict **inconclusive**.
   Keep the event history; specify the missing evidence and one next action.
3. Otherwise report the count/rate difference descriptively, together with traffic
   mix and uncertainty. This design cannot establish a causal winner. An observed
   improvement can motivate another test; it does not authorize paid scaling.
4. New crash/review evidence takes precedence over a conversion claim. No new
   screenshots, video re-uploads, campaign starts or public switches are needed
   to execute this read-only plan.

Sources: Play Console `store-listings/default/edit`, `publishing`, and the exact
statistic/report URLs recorded in state.json. Historical publication/reversal
claims are explicitly attributed to archive-20260918.md. No campaign attribution
or in-app conversion SDK is configured by this plan.
