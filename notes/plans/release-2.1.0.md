# 2.1.0 — A night of choices that continue

## Goal

Keep 2.0.0's content volume and let the player choose risk directly in every region and cycle.
A 2.1.0 run has this rhythm:

`explore → choose how to kindle the beacon → defend or move → Guardian → return or go deeper`

## Product hypothesis

Put risk/reward choices with immediate results at beacons and cycle ends, and if two-relic
combos change behavior even before the final evolution, first-beacon reach rate, first-Guardian
kill rate, and in-run next-cycle choice rate go up.

2.0.0 has no game-event instrumentation, so a true before/after on app events is impossible.
2.1.0 adds instrumentation, consent, and reporting tools, but leaves send disabled on store
builds until a protected collection path is ready. The first baseline is a follow-up version
that has verified App Check or a protected proxy. Store-console D1/D7 stay recorded as a
separate external baseline.

## Features

### Beacon overcharge

- After filling a beacon, choose `Safe Kindle` or `Overcharge`.
- Safe Kindle continues the existing flow as-is.
- Overcharge holds 6.5 seconds beside the beacon. Leave the range and progress drops; wander
  farther and it finishes as a normal kindle.
- Each terrain reuses existing raid formations: forest encircle, field crossfire, camp escort.
- Success grants a weapon core and extra embers. Overcharge all three beacons in a cycle and
  Guardian loot becomes 2 tiers.
- Regular spawns and timed raids pause during overcharge so the mobile enemy cap is not exceeded.

### Return and going deeper

- After picking Guardian loot, cash out the current record and return, or go to the next cycle.
- Closing cycle 8 makes return a true victory; continuing is the infinite `beyond the map` stretch.
- Return uses the current score and shard formula as-is. No extra currency and no time pressure.

### Relic resonance

- Collect two different effects on the same attack path and resonance opens before the final evolution.
- Starfall: the next Moon Disc volley after a dash homing once.
- Full Moon: the next slash after a dash becomes one omnidirectional cut.
- Moon Dance: a weak Moon Dance fires once along the dash path.
- Final-evolution always-on effects and contact dodge stay as they are.

## Analytics contract

### Principles

- Do not collect or retroactively send later until explicitly allowed.
- Do not send names, leaderboard nicknames, purchase/transaction IDs, device IDs, location, or free text.
- Do not send a permanent install ID to the server. Use a temporary ID that lives only in the session and the run.
- D1/D7/D30 fire once only when the app is foregrounded on that exact calendar date in UTC `client_day`.
  Do not backfill past dates from a late return.
- The network must not make the game wait. Cap the queue at 200 events · 14 days, plus retries.
- Do not enable it in the release config until the privacy policy and store data disclosures match.
- Public Firestore create rules only check shape; they do not stop spam or cost attacks.
  Until App Check enforcement plus valid-token send, or an authenticated, quota'd collection proxy,
  is verified on device, do not set `ingestion_hardened=true` and leave analytics disabled.

### Core funnel

1. `analytics_activated`
2. `app_opened`
3. `run_started`
4. `relic_chosen`
5. `beacon_lit`
6. `guardian_started`
7. `guardian_defeated`
8. `cycle_decision`
9. `run_ended`

### Metrics to judge

- Time to first relic and first beacon
- Loss rate before the first beacon
- First-Guardian reach rate and kill rate
- Overcharge pick rate · success rate · leave rate, and differences by terrain
- Next-cycle pick rate after a Guardian
- Pick and evolution rates by resonance path
- Median and top-10% play time per run, cycle count
- Consent-cohort D1/D7 checkpoints

Do not read per-hero results as causes; they are biased by purchase and skill selection.
Hide breakdowns with a sample smaller than 20 from reports.

## Release gates

- Read existing 2.0.0 save and high-score records as-is.
- Choice windows must not auto-select from a finger that was already moving and then released.
- Choice, relic, dialogue, and pause panels must not overlap.
- Death, continue, and region change during overcharge must not leave beacon or scheduled-enemy state behind.
- Debug clear tools use Safe Kindle so capture automation does not stall.
- On analytics decline or withdraw, the queue clears immediately and game rewards do not change.
- Without a protected collection path, analytics does not activate even if a key is present.
- Confirm 5-language 808×360 layout, full regression checks, and a real Android screen.

## Version

- App version: 2.1.0
- Android versionCode: 14
- iOS build: 9
