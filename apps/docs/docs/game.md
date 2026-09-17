---
title: The game we are making
---

# The game we are making — Moonlit Beacon

## 1. Overview

| Item | Detail |
| --- | --- |
| Korean title | Moonlit Beacon |
| English title | Moonlit Beacon |
| Genre | top-down survivor action / auto-attack / single-player |
| Platforms | **iOS / iPadOS + Android** (App Store · Google Play) |
| Reference devices | iPad + Android phones and tablets, arm64 |
| Orientation | landscape locked (Sensor Landscape) |
| Internal resolution | 808 × 360 — exactly 1/3 of Pixel 10 landscape, integer 3× scale |
| Stretch | mode `canvas_items` / aspect `expand` |
| Controls | full-screen floating move stick / bottom-right dash button / auto-attack |
| Engine | Godot 4.7.1 Standard, GDScript |
| Run length | you can cash out after each guardian — keep going after an 8-cycle official win |
| Project version | 2.1.0 (iOS build 9 / Android versionCode 14) |

### One-line pitch

> Light the beacons, grow your weapons with spirit embers, weapon cores,
> and relics, and take on guardians and harder cycles — a 2D top-down
> survivor action game.

The first complete build from Lessons 1–16 was a 90-second dodge game:
light the beacons and escape through the moonlight gate. After that we
played it ourselves and added attack, growth, and endless cycles.
**This page's shipping scope is the expanded current complete build.**
Moonlight gates and dual sticks still in each lesson body describe the
screen as it looked when that lesson was finished.

## 2. Flow of a run

1. Pick a character on the title, and spend collected moon shards on
   permanent boons.
2. Enter the night forest and scatter spirits with automatic slashes and
   Moon Disc missiles.
3. Walk up to moonlight embers spirits leave behind and fill the
   **Moonfire gauge**. Ten pips raise every weapon's damage for 6.5
   seconds and speed up slash and Moon Disc.
4. When kill value hits a stepped threshold, a **weapon core** drops.
   Each pickup raises missile power from 0 to 8, and the volley grows
   from 1 shot to 8.
5. Kill count levels you up and you pick one of three relics. You can
   pick the same relic again and keep stacking the main weapon.
6. After filling a region's beacon, choose **Safe Kindle** or
   **Overcharge**. Safe Kindle continues immediately. Overcharge holds a
   terrain raid beside the beacon for 6.5 seconds in exchange for a
   weapon core and extra embers. The first two beacons fill Moonfire and
   open a moonlight gate with a pursuit pack. Break through the gate and
   you move to the next region.
7. The third beacon locks Moonfire awakening until the guardian falls.
   Beat that terrain's guardian, pick **one dedicated loot tier** from
   one of the three attack paths, and restore one heart. If you
   Overcharged all three beacons, you receive two loot tiers.
8. After picking loot, cash out the current score and shards and return,
   or enter the next cycle where region order and enemies change. An
   8-cycle return is the official win; you can keep going forever after
   that if you want.
9. Returning or hitting 0 health shows cycle, beacons, survival time,
   level, kill score, and rank. Moon shards and records carry into the
   next run.

## 3. Exact shipping-version scope

### Controls — one move stick and a dash button

The move stick is not a fixed pad. It is a **floating stick that appears
where you press.** Only dash is a separate bottom-right button. Attack
fires automatically at the nearest spirit.

| Input | Role |
| --- | --- |
| Anywhere except the dash button | a move stick appears where you press |
| Bottom-right button | dash in the direction you are walking. Standing still, dash the way you face |
| Attack | aims and fires automatically, no extra button |

- The stick is **invisible until you press.** It appears around the press
  point and vanishes on release.
- The dash button takes the touch first, so trying to dash does not spawn
  a move stick.
- The dash button's filling graphic and ready-pop show cooldown.

During desktop development, mouse drag is emulated as touch.
`pointing/emulate_touch_from_mouse=true` in `project.godot` makes the
virtual stick work from mouse drag alone.

### Combat and in-run growth

- The basic weapons are a close-range slash and a long-range Moon Disc.
  Moon Disc starts at power 0 as a single straight shot, and picking up
  cores to power 3 turns it into homing missiles that split among several
  enemies.
- There are 16 relics. Besides raising damage, speed, range, and Moon
  Disc volley power, there are new weapons like Moon Ring and Moonlit
  Ripple.
- Stacking the same relic keeps growing the numbers. Collecting different
  effects unlocks three evolutions that change how you fight.
- Collecting **two different effects on the same attack path** opens
  resonance before the final evolution. Resonant Starfall homes the next
  Moon Disc volley once after a dash, Full Moon turns the next slash
  omnidirectional once, and Moon Dance leaves a weak attack on the dash
  path once. After the final evolution, each path's always-on effect
  continues.

| Evolution | Investment needed | Combat after evolution |
| --- | --- | --- |
| Starfall | learn all 4 Moon Disc effects and reach 6 tiers | opens a homing volley even before power 3, and later Moon Disc investment keeps stacking on the meteor volley |
| Full Moon | learn all 4 slash effects and reach 6 tiers | the third slash and the slash right after a dash sweep 360 degrees |
| Moon Dance | learn Moon Ring and Ripple and reach 5 tiers | ring and ripple strengthen together and the dash path attacks too |

- Missile power is a separate growth track from relic cards. A normal
  spirit counts as kill value 1, an elite as 3, a guardian as 10. You
  **must pick up** a core dropped at the next table's threshold to gain
  a tier.

| Current power | Kill value for next core | Shots | Fire mode |
| ---: | ---: | ---: | --- |
| 0 | 2 | 1 | straight |
| 1 | 3 | 2 | straight |
| 2 | 4 | 3 | straight |
| 3 | 4 | 3 | homing |
| 4 | 5 | 4 | homing |
| 5 | 5 | 5 | homing |
| 6 | 6 | 6 | homing |
| 7 | 6 | 7 | homing |
| 8 | max | 8 | homing |

- A larger volley does not clone one shot's damage. A per-power total
  damage budget is split across the volley so early bosses do not melt,
  while overall firepower still climbs as tiers rise.
- The first relic pick shows each of the three evolution paths once.
  Later cards prefer missing effects on the path you are growing. Card
  footers and the HUD show evolution progress.
- Every spirit leaves moonlight embers. A normal ember fills one Moonfire
  pip, an elite ember four. You have to walk onto them to pick them up.
- Ten Moonfire pips raise all weapon damage 22% for 6.5 seconds and cut
  slash and Moon Disc intervals 14%. Collecting more embers during
  awakening extends the duration a little.
- When you are hurt, a spirit can drop Moon Dew. Pick it up to restore
  one heart. Normal dew drops at most once every 12 seconds across the
  whole field. If you are on one heart and there is no dew on the field,
  defeating an elite guarantees one rescue dew.
- Taking a hit at missile power 1 or above keeps relics and **exactly one
  power tier** pops out as an orange core. Reclaim it within 9 seconds
  and it restores immediately; miss it and the lower power is locked.
  The HUD's second countdown and an edge arrow point at the core.

### Enemies

| Kind | Traits |
| --- | --- |
| 7 normal spirits | original silhouettes. Chase, fast chase, orbit, charge, ranged, and other distinct motion |
| Elites | mix in at random from cycle 2, and the camp elite ember carrier appears from cycle 1. Tougher, leave gold embers. Guarantee one rescue dew only when you are on one heart and the field has no dew |
| 3 terrain guardians + 3 promotions | original per-terrain bosses. Appear at the third beacon. Forest uses chained charges, field uses cross and radial barrages, camp uses fans and opening armor. From cycle 2 the same terrain gets thorn, storm, and siege promotions |

New spirit kinds mix in over time, and a current-terrain raid arrives at
intervals. Each cycle also raises health multiplier, elite chance, and
the simultaneous-spawn cap. From cycle 4 guardians harden faster than
fodder, telegraphs, barrages, and charges pack tighter, and even finished
firepower takes longer to kill. Every guardian attack is telegraphed
first with a line, fan, or safe gap, and hit stun cannot lock the pattern.

### Terrain and day/night

Lighting one beacon in a cycle takes you through a moonlight gate to the
next terrain, and the next cycle also rotates the starting terrain.
Floor, tint, trees, and props actually swap.

| Terrain | Dedicated raid | Play it asks for |
| --- | --- | --- |
| Night Forest | surround that leaves the unlit-beacon side open | slip the gap or break toward the next beacon |
| Moonlit Field | both battle lines and casters' crossfire | push one line first and hold the safe half |
| Abandoned Camp | elite ember carrier and wedge escort | ambush the carrier for a large ember, or keep distance |

Even inside one cycle, lighting beacons brightens the background
**night → blue dawn → sunrise → day**. Player, enemies, and projectiles
are excluded from the tint so combat readability stays.

### Beacons and cycles

- Each cycle places one beacon in each of three regions.
- Each beacon needs **1.3 seconds** inside the radius to activate.
- Leaving the radius drains the fill you had.
- After a full charge, choose Safe Kindle or Overcharge. Overcharge is
  the choice to last 6.5 seconds inside the beacon radius against a
  forest surround, field crossfire, or camp escort formation. Leaving
  the radius drains progress; leaving far away finishes as a normal
  kindle with no reward.
- A successful Overcharge grants a weapon core and extra embers. Overcharging
  all three beacons in a cycle grows guardian loot from one tier to two.
- The first and second beacons each fill one third of the Moonfire gauge.
  If you are already awakened, duration extends 0.5 seconds instead of
  the gauge.
- After the first and second beacons, follow the on-screen `ESCAPE` arrow
  to the moonlight gate. A pursuit pack attaches from the far side of the
  gate; passing through switches terrain and time of day.
- The third beacon locks Moonfire awakening and opens guardian music and
  a health bar.
- Defeating the guardian grants one relic tier from **the guardian's 3-pick-1
  trove**, one card each from Starfall, Full Moon, and Moon Dance, and
  restores one heart.
- After loot, cash out the current record and return, or enter the next
  cycle. The next cycle starts from night again, with a different starting
  terrain and terrain guardian.
- Closing cycle 8 and returning is the official win. Choosing to continue
  enters the `beyond the map` endless stretch. There is no time limit or
  separate final exit.

### Time and score

```text
final score = completed cycles × 1,500
            + beacons lit in the current cycle × 300
            + seconds survived × 12
            + (level - 1) × 120
            + per-kind score of spirits scattered
```

Ranks are **S / A / B / C / D**. Thresholds are 140,000 / 60,000 /
20,000 / 6,000. It is an endless-survival game, so rank is not cut by
win/lose or remaining health.

The result screen shows those five lines not only on a loss but also on
a return after a guardian, and pays moon shards on a square-root curve of
score. Longer runs pay more, without one run's gap dominating all
permanent growth.

### Save data

| File | What remains |
| --- | --- |
| `records.cfg` | best score and best rank |
| `records.cfg.tmp` | temp file used only while atomically saving the best record |
| `settings.cfg` | language, music and SFX volume, anonymous analytics consent, local cohort start/version and D1/D7/D30 check bits |
| `analytics_consent.revoked` | local refusal marker so a save error cannot turn anonymous analytics back on next launch |
| `vault.cfg` | moon shards, 6 boon tiers, unlocked characters, continue-coin balance and grant-transaction ledger |
| `ladder.json` | local top 10 with name, character, app version, score, rank, cycle |
| `ladder.json.tmp` | temp file used only while atomically saving the ladder |
| `analytics.json` | allowed events not yet sent after consent. Max 200 events / 14 days; revoked consent deletes immediately |

A missing or corrupt save still launches with defaults.

The online ladder is implemented with Firestore REST. Only when a
shipping build includes a separate API-key config does it upload name,
character, app version, score, rank, and cycle, and fetch global top
records. This repository has no key file, so default builds use the local
ladder only. Missing connection or a failed request leaves play and local
records working. Android export has the internet permission on for this
optional feature.

Anonymous game analytics is a **opt-in consent feature** separate from
the global ladder. It only runs when the shipping build's `firebase.cfg`
has `[analytics] enabled=true`, `ingestion_hardened=true`, and a Firebase
web API key, **and** Settings explicitly allows it. The protection check
is turned on only after App Check is actually enforced and sends valid
tokens, or after the ingest path is replaced with an authenticated,
quota-bearing one. Name, ladder nickname, purchase/transaction IDs,
device ID, permanent install ID, and free text are never sent. Only a
temporary ID used for app launch and one run records allowed game events
and aggregated D1/D7/D30 return checkpoints. Returns count only when the
app is foregrounded on the exact UTC calendar D1/D7/D30, and do not
backfill late relaunches. Refuse or revoke and the queue and local
analytics cohort are cleared; rewards and game progress do not change.

2.0.0 had no in-app game-event instrumentation, and the 2.1.0 store
submission also ships analytics disabled because a protected ingest path
was not ready. Do not compare those two versions' event funnels. The
first baseline is the consent cohort of a later version that has verified
App Check or a protected proxy. Summarize Firestore export JSON/JSONL
with
`pnpm analytics:report -- --file <path> --version <active-version> --to YYYY-MM-DD`.
`--version` splits play-event app version from retention's first-consent
version, so a return after an update stays in the original consent
cohort. `--to` is the UTC observation end date when the export completed,
and is required. Retention hides rates below a default minimum sample of
20. Privacy policy, store data notices, deploying Firestore rules,
indexes, and 90-day TTL, ingest protection against spam and cost
attacks, and confirming release config plus real-device transmission are
**shipping gates** that source code alone does not finish.

### Languages

- Korean (ko)
- English (en)
- Japanese (ja)
- Simplified Chinese (zh_CN)
- Traditional Chinese (zh_TW)

You can change them in Settings during play without restarting.

## 4. What this game will not include

The current shipping scope excludes the following.

- Accounts and login
- Analytics accounts, advertising IDs, and device fingerprinting
- Ads and energy / gacha-style IAP
- Multiplayer
- A manual attack button and a traditional slot inventory
- **Windows / Web builds** (desktop runs are development tests only)

The online ladder is an optional feature that types a name with no
account. Unconnected builds show only the local top 10.

Seven non-consumables are implemented: Moonlit Supporter, five companion
heroes, and the Lantern Colors pack, plus three consumable continue-coin
SKUs (1, 5, and 10). The free Moonlit Warden alone can play every region
and cycle. Paid heroes are balanced options with different starting
relics and visuals, not a power ladder by price. Continue coins are an
optional convenience that resumes a run where you fell; you can start a
new run immediately without them. Past Hero Bundle buyers still restore
Shadow Dancer and Beacon Keeper after that SKU left the new-sale list.
All 10 sale products are registered on both stores, and purchase,
verification, grant counts, restart persistence, and consume paths were
checked on a physical Pixel and iPad. Product and verification
boundaries are in [Monetization design](./monetize.md).

## 5. Game states

```text
TITLE ──→ PLAYING ⇄ PAUSED
  │           │
  ├─ Shrine   ├─ guardian → loot → return → RESULT → record → restart
  └─ Ladder   │                    └─ continue → next cycle → PLAYING
              └─ health 0 → RESULT ──→ coin continue → PLAYING
```

Android **Back** sends `PLAYING` to `PAUSED`.
Pressing it again from `PAUSED` returns to the title. The app is not
left to quit on its own.
We handle `NOTIFICATION_WM_GO_BACK_REQUEST` and
`quit_on_go_back` is off.

Going to the background (`NOTIFICATION_APPLICATION_PAUSED`) auto-pauses.
Health does not drain during a phone call.

## 6. Map

- The map is **1900 × 1180** and the camera follows the player.
- The actual walkable area is `Rect2(90, 90, 1720, 1000)`. Outside is a
  tree belt.
- A seed mixing run, cycle, and terrain builds the edge and interior
  decoration. The same cycle of the same run is reproducible; the next
  cycle changes terrain and decoration layout together.
- Separate from decoration, 32 forest, 28 field, and 30 camp original
  structures are placed. Whichever 3×3 camera cell you are in, at least
  three collision structures are visible. Player and spirits walk the
  same circular bounds, and enemy bullets vanish if they hit a structure
  first.
- Beacon positions are re-rolled from cycle number and run seed, preferring
  candidates far from the player in each terrain so the search path exists.
- A compass arrow points when the objective or guardian is off-screen.
- Because of `expand`, visible horizontal width differs by device, but
  play area and camera limits stay in world coordinates.

## 7. Audio buses

```text
Master
├── Music
└── Sfx
```

Combat, beacon, and UI SFX share the `Sfx` bus.

## 8. Mapping to the official tutorial

The table below is **the history of the Lessons 1–16 first complete
build.** Each lesson puts gameplay, art, sound, and UI in together, but
the order of concepts is the official intro course. Design calls and
verification for the current survivor complete build continue in
[2.0 rebuild — fixing a game that was not fun](./rebuild.md).

| Godot official learning flow | Moonlit Beacon course | Lesson |
| --- | --- | --- |
| Setting up the project | version, resolution, orientation, folders, assets, licenses, title screen | Lesson 1 |
| Nodes and Scenes | beacon as its own scene, night-forest arena scene | Lesson 2 |
| Creating instances | instantiate the beacon scene three times and change per-instance values | Lesson 3 |
| Creating your first script | beacon kindle state and presentation script | Lesson 4 |
| Creating the player scene | player node, 4-facing sprite, shadow | Lesson 5 |
| Listening to player input · Coding the player | left floating joystick and 8-way movement | Lesson 6 |
| Using signals | beacon activate, hit, game-over events | Lesson 7 |
| Creating the enemy | enemy scene and chase logic | Lesson 8 |
| The main game scene | enemy spawn, game state, moonlight gate and win/lose | Lesson 9 |
| Heads-up display | health, time, beacon count, result screen | Lesson 10 |
| Finishing up | Android export, device install, pause and restart | Lesson 11 |
| Extra expansion | dash, enemy variants, guardian, score and save, localization, QA, itch.io | Lessons 12–16 |
| Complete-build redesign | auto-attack, relic growth, large map, endless cycles, permanent growth and ladder | after Lesson 16 |

## 9. Version tags

These tags preserve the screen as it looked during the course. The
current working tree has grown from `release-1.0.0` through store
`2.1.0` for iOS and Android. 2.0.0 is the build with a full art swap, a
protagonist holding a beacon candle, and eight-cycle dialogue. 2.1.0 adds
beacon Safe Kindle / Overcharge, pre-final-evolution relic resonance,
return-or-continue after a guardian, and anonymous event instrumentation,
consent, and reporting tools. 2.1.0's submission build ships collection
disabled; the real baseline starts from a later version with a protected
ingest path on.

A lesson's start point is the previous lesson's complete point, so we
only keep complete tags.
To see the repo state at the start of Lesson 2, look at
`chapter-01-complete`.

```text
chapter-01-complete
chapter-02-complete
...
chapter-16-complete

release-0.1.0      # Lesson 11, first complete build that plays a full run on a phone
release-0.9.0-rc1  # early Lesson 16, release candidate
release-1.0.0      # Lesson 16, APK + itch.io release
```
