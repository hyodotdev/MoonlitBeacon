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
| Project version | 3.0.0 (iOS build 10 / Android versionCode 15) |

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
- Nine **skills** join the level-up cards as cycles pass, on the free third
  card. The first time one becomes available it is shown next and marked
  "New skill"; after that roughly one offer in four carries one that is open.
  Each is something that happens, and each deals damage with the same
  multiplier as your other weapons, so one picked late is worth as much as
  one picked early.

| Skill | From cycle | Max | What it does |
| --- | --- | --- | --- |
| Lantern Familiar | 5 | 3 | a lantern spirit circles you and shoots the nearest spirit every 1.5s |
| Moon Ward | 5 | 3 | a bubble swallows one hit, then recharges in 26s (x0.74 per extra stack) |
| Comet Call | 8 | 4 | every 9s (1.4s faster per extra stack) a comet marks and hits the thickest cluster |
| Star Magnet | 8 | 3 | embers, dew, and cores fly to you from 2.2x, 3.4x, 4.6x as far |
| Moon Burst | 10 | 4 | choosing a card bursts moonlight round you (86 wide, +12 per stack) that hurts and pushes back what is near |
| Thorn Bloom | 11 | 3 | a hit bursts thorns that hurt and push back what is near |
| Second Light | 11 | 2 | once a cycle a lethal hit leaves you standing, with 3s of safety |
| Winter Bell | 13 | 3 | every 13s (1.8s faster per extra stack) a ring of frost slows every spirit within 150 by 42% for 2.6s; a guardian feels a third of it |
| Comet Trail | 16 | 3 | a dash leaves three marks of moonlight (up to five) that burst behind you, one after another |

A new skill opens every few cycles, so the endless stretch keeps offering
something you have not seen: two at cycle 5 and 8, one at 10, two at 11, and
one each at 13 and 16.

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
  and most of the lost tier comes back with it — 70% of the next tier's
  kill value, so the rest must be fought for again; miss it and the
  lower power is locked. The HUD's second countdown and an edge arrow
  point at the core.

### Enemies

| Kind | Traits |
| --- | --- |
| 7 normal spirits | original silhouettes. Chase, fast chase, orbit, charge, ranged, and other distinct motion |
| Elites | mix in at random from cycle 2, and the camp elite ember carrier appears from cycle 1. Tougher, leave gold embers. Guarantee one rescue dew only when you are on one heart and the field has no dew |
| 3 terrain guardians + 3 promotions | original per-terrain bosses. Appear at the third beacon. Forest uses chained charges, field uses cross and radial barrages, camp uses fans and opening armor. From cycle 2 the same terrain gets thorn, storm, and siege promotions |
| 3 later guardians + 3 promotions | the places that open from cycle 3 have guardians of their own grammar (see *Guardians of the later places*). The first time you meet one it is the younger form, every time after the grown-up one |

New spirit kinds mix in over time, and a current-terrain raid arrives at
intervals. Each cycle also raises health multiplier, elite chance, and
the simultaneous-spawn cap. From cycle 4 guardians harden faster than
fodder, telegraphs, barrages, and charges pack tighter, and even finished
firepower takes longer to kill. Every guardian attack is telegraphed
first, and hit stun cannot lock the pattern. See *Reading a guardian's
attack* below for how.

### Terrain and day/night

Lighting one beacon in a cycle takes you through a moonlight gate to the
next terrain. Floor, tint, trees, and props actually swap. **Cycle 1 walks
the classic route** (forest, field, camp) through one gate each time, so
the first loop teaches the game and stays the same for everyone. From
cycle 2 a gate is a fork; see *Forks* below.

| Terrain | Dedicated raid | Play it asks for |
| --- | --- | --- |
| Night Forest | surround that leaves the unlit-beacon side open | slip the gap or break toward the next beacon |
| Moonlit Field | both battle lines and casters' crossfire | push one line first and hold the safe half |
| Abandoned Camp | elite ember carrier and wedge escort | ambush the carrier for a large ember, or keep distance |
| Frost Pass | a wall of spirits marching straight in, with a two-lane gap in it | slip through the gap or dash through it |
| Mirewood Marsh | three tight pods rising round you, with a wide gap between each pair | pick a gap and keep moving through it |
| Moonlit Ruins | a group ahead of you, then three seconds later a second group from behind | plan the way out of the first for the second |

Frost Pass and Mirewood Marsh join the forks at cycle 3, Moonlit Ruins at
cycle 4. Each has its own floor, its own trees and stones, four structures
of its own that block the path, and its own light: warm lanterns in the snow,
glowing mushrooms and wisp jars in the bog, gold moon altars in the ruins.

Even inside one cycle, lighting beacons brightens the background
**night → blue dawn → sunrise → day**. Player, enemies, and projectiles
are excluded from the tint so combat readability stays.

### Forks

From cycle 2 lighting a beacon opens **two gates on different rims**. Each
carries the name of the place it leads to, in that place's colour, and an
arrow points at each. The gate you run for decides the next terrain and
the side you arrive on. The gate after the second beacon also names the
**guardian** waiting there, so the route is a choice of boss. A third,
quieter line hints the **memory** waiting in that place — ribbons, chimes,
a kettle, a bell, a boat, a lens — without moving the dodge information.
A new cycle opens somewhere other than where the last guardian fell. The
choices are drawn from the run's seed, so a route is repeatable and
testable.

The classic three places grow their guardian with the cycle. The later
places grow theirs with how often you have met it: the gate names the younger
form the first time and the grown-up one after.

### Beacons and cycles

- Each cycle places one beacon in each of three regions.
- Each beacon needs **1.3 seconds** inside the radius to activate.
- Leaving the radius drains the fill you had.
- After a full charge, choose Safe Kindle or Overcharge. Overcharge is
  the choice to last 6.5 seconds inside the beacon radius against the
  place's own raid formation. Leaving
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
- Closing cycle 8 resolves Nari's promise out loud: her signal answers,
  she reaches home, and the kettle is warm. Returning then is the official
  win. Choosing to continue is a voluntary expedition for other forgotten
  roads past the map. There is no time limit or separate final exit.

### The endless stretch: Depth

Past cycle 8 the count is **Depth** (cycle 9 is Depth 1). Cycles 1 to 8 are
exactly the game that shipped; what follows is built to be played for as
long as you like, getting a little harder each time and never a wall.

- **A gentle curve.** Fodder toughness grows x1.35 a cycle through cycle 3
  and x1.58 a cycle from cycle 4 through cycle 8. Past it, x1.22, and a
  guardian's own extra health x1.10. The elite chance keeps climbing to
  45%. The spirit cap stays at 40 for the phone.
- **A tempo you can read.** A guardian's windups, gaps, bolt speed and charge
  speed harden one step a cycle through cycle 8 exactly as they shipped, then a
  quarter as fast. Left to grow one for one, a cycle-14 windup would last a
  fifth of a second; this way a deep guardian is a little quicker each time
  and still a thing you read and step out of. However quick it has grown, a
  fan, a ring or a charge shows itself for at least 0.45 seconds and a circle
  on the floor stays at least 0.85 seconds before it bursts.
- **Omens.** Each zone carries one rule that changes a single thing, one
  from Depth 1 and two from Depth 5, shown on the world line and on the
  gate that leads there, so an omen is part of the route you choose.

| Omen | Effect |
| --- | --- |
| Blood Moon | more elites, and embers are worth 1.5x |
| Swarm Tide | spirits arrive faster (x0.72 interval) and are weaker (x0.65 health) |
| Iron Night | six fewer spirits at once, and each x1.45 tougher, arriving slower |
| Lantern Bloom | beacons kindle in 60% of the time |
| Dew Rain | moon dew drops 2.2x as often |
| Gale | spirits move 16% faster |

- **Moonless Trial.** Every fifth Depth (cycle 13, 18, ...) the guardian is a
  trial: one more mutation than its cycle grants, and two tiers of loot
  whatever you did at the beacons.

### Guardian mutations

A guardian is a body plus what it has gained. A mutation is one small,
readable rule hung on the move machine every guardian already has, so it
works on any of them. Slots by cycle: none to cycle 4, one at 5 to 7, two at
8 to 10, three at 11 to 14, four after, and a trial adds one. They are drawn
from the seed and never repeat within one guardian, so the same guardian
met again fights differently. Its numeral counts the meetings ("Thornwood
Pursuer II"), the mutations are named in a banner just after it appears, and
they stay under its health bar.

| Mutation | What it adds |
| --- | --- |
| Echo | a volley comes again 0.7s later, turned a little; a run of fans repeats once, after its last fan, and the repeat is drawn beside the volley from the moment it winds up |
| Spiral | the safe gap of each volley turns further round than the last |
| Summoner | at two thirds and one third of its health it calls a pack, within the spirit cap |
| Frenzy | everything it does runs 22% faster |
| Aegis | a ring of light stands up for 2.4s and nothing lands; it never opens during the rest after a volley |
| Meteors | while it rests, marked circles fall on and around you and burst after a second |

### Guardians of the later places

The three guardians of the places that open from cycle 3 are built from the
same parts as the first three (a fan, a ring, a marked circle, a dive) and
put together differently. Every one rests for a moment after its pattern, and
that rest is marked with a mint glow: the window to dive in.

| Guardian | Pattern |
| --- | --- |
| Hoarfrost Owl, then Rimecrown Owl (Frost Pass) | glides in wide circles, blows a fan of feathers twice (the second aimed where you fled; the grown-up Rimecrown Owl blows a third, with fewer feathers in each), then dives through where you were standing and perches |
| Mirewood Toad, then Glowcap Toad (Mirewood Marsh) | waddles, then hops onto a circle marked on the floor, twice; the third leap is a flop with a wider circle and a ring of bolts after it, then a long rest. The circle bursts as the toad lands |
| Moonstone Sentinel, then Halo Sentinel (Moonlit Ruins) | keeps a little way off, writes glowing circles round you (one where you stand), then a ring of bolts with a gap facing you, then rests; more circles and a shorter rest as the cycles go on |

### Reading a guardian's attack

Every guardian attack is marked on the floor before it lands, in one
language for all of them: **coral light is where it will hurt, mint light is
where it will not**, and the boss's own colour only tints the ring at its
feet. A charge shows the lane it will run, exactly as long and as wide as
the charge really is, with arrowheads streaming down it and a bright fill
racing to the end as the wind-up runs out. A ring of bolts shows a ray for
each bolt and a calm mint wedge for the gap. A fan shows a wedge that
strengthens toward its edge, and a single shot a soft band with dots streaming
down it. A ground mark (Meteors, or your own Comet Call) is a circle lit
faintly from the start, so its reach is honest, with a brighter disc that
grows to fill it: the fill is the time you have left.

The warning has a floor. Enrage, frenzy and the cycles can quicken a
guardian's gaps, its bolts and its charges, but a fan, a ring or a charge is
always shown for at least 0.45 seconds (the first fan of a sequence, the
widest thing a guardian aims, for at least 0.75), and a circle on the floor
stays lit for at least 0.85 seconds before it bursts. In cycle 1 nothing is
quickened, so every warning keeps the length it was drawn with.

The picture is the volley. A fan is drawn as wide as it really is and a ring
with one ray for every bolt it will fire, so the mint way through a ring is
exactly as wide as the clear space between its bolts and never wider. Growing
volleys add bolts, not width: a fan never spreads past about 70 degrees and
carries at most seven feathers (five when the run is three fans, so the run and
the repeat of its last fan still fit the two dozen bolts the field holds), a
ring or a cross always leaves at least 16 degrees of clear way either side of
the aim (a cross never carries more than eleven arms, a ring never more than
thirty-two spokes), and from cycle 5 the fans that follow the first are
narrower spears, because you are still running when they come. The repeat of
an Echo is shown the same way, faintly beside the volley while it winds up and then until the repeat fires, and
a single aimed shot is drawn as a soft band all the way to you and past,
because the bolt does not stop where the line does. A guardian's bolts fly
about a third of the screen's width and fade out, which is as far as their
pictures reach: beyond it there is nothing to be hit by.

### Bullets

Bullets are the night's small change: slow pastel orbs that drift across
the room between one warned attack and the next. Casters loose a fan where
their aim line pointed, weavers drop a single orb as they circle, wisps let
fall a slow ring, and even the chasers spit a slow orb now and then; a
guardian sheds a thin aura for the whole fight and a heavier stream while
it is not winding anything up.

Slip between them. Every orb is slower than the slowest hero on foot, leaves
a wide gap to its neighbours, and fades out soon after passing you, so a way
through is always there if you keep moving for it. Cover is
cover: orbs stop on trees, stones and walls, and when a guardian falls,
everything it threw turns to sparks. The first seconds in a new place are
quiet — nothing ordinary throws until you have had a look round.

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
permanent growth. Past cycle 8 the closing line also names the Depth
(cycle 9 is Depth 1), the same count the HUD shows in the endless stretch;
the depth is a caption and adds no points. Below the table a road line
states the waves reached and how many of the six places were remembered,
and a settlement window glows on an official win, waits dim on an early
return, and stays hidden on defeat.

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
| `chronicle.json` | which story beats, place memories, first-sight lines and endings have been seen (the Chronicle page) |
| `chronicle.json.tmp` | temp file used only while swapping the chronicle in |
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

### UI and story structure (3.0.0)

3.0.0 replaces the 2.x screens and gives the story a shape. The course keeps
teaching the 2.1.0 build (tag `release-2.1.0`); this page tracks the current
game.

**One UI kit.** Every panel, button, card, progress bar and banner is a chunky,
rounded pixel nine-patch from `assets/custom/ui/kit/`, generated by
`tools/build_ui_kit.py`. Scenes do not draw their own boxes. They point at the
shared style resources under `resources/ui/` (`buttons`, `buttons_gold`,
`buttons_berry`, `buttons_ghost`, `cards`, `panels`, `bars`), and the screens
that build rows in code load the same files, so changing the look is a change
in the kit and not in seventeen scenes. The colour of a button's rim says its
role: gold is primary, lavender is secondary, berry is danger, ghost is quiet.
Dense screens (shrine, shop) use `panels/panel_tight`, the same art with less
padding, because they fill the whole safe height.

**A combat HUD you can read in a fight.** Hearts, and one brazier per beacon of
the current wave: a cold brazier lights the moment its beacon burns. Level,
defeated count and time sit beside them. The secondary lines (evolution, missile
power, moonfire, the region caption) rest dim and brighten only when their value
changes, so what just changed is what you see. Relics are emblem icons with a
`×N` corner badge instead of a wall of names, and the boss bar wears each
guardian's accent.

**A night that has depth.** The camp and field floors used to be a single flat
colour; they now repeat a seamless textured tile (`tools/build_ground_tiles.py`),
the arena carries a screen-space vignette, and the camp's lanterns and lit barrels
throw a warm pool of light on the ground (`RoomLights`, one node for every pool).

On top of that the room is lit as one scene, with moonlight from the upper left:

- every tree, rock, tent and structure casts a soft shadow that leans away from the
  moon, and the pieces themselves catch a pale rim on that side
  (`RoomShadows`, `shaders/world_polish.gdshader`);
- the floor has life: wide patches of moss and moonlit blue break up the repeating
  tile, dappled light breathes through the canopy, and small mushrooms, flowers and
  grass tufts glow on the ground (`RoomTone`, `RoomFlora`, and the additive
  `RoomLights`);
- the air moves: two banks of mist slide at different speeds so walking through a
  room shows its depth, slanted shafts of moonlight sway, and motes drift
  (`RoomAtmosphere`);
- a colour grade over the world (`shaders/night_grade.gdshader`) deepens the shadows
  with a cool cast, keeps warm light warm, and lets the far edge of the frame sink
  into the dark; the HUD is drawn after it and is not graded;
- heroes, spirits and guardians share one actor shader
  (`shaders/actor_polish.gdshader`): a moonlit rim, an outline coloured from the art
  it surrounds, and bright details such as a lantern or a flame that stay lit in the
  dark. It works from each sprite's own colour and alpha, so it needs no extra art and
  follows whatever the sheets show;
- a defeated spirit bursts into moon dust in its own colour (`KillSparks`, one node
  for every burst).

Every terrain describes its own palette in its `RoomKind` resource (colour patches,
plants, mist, shafts, motes), so a new terrain needs numbers and no new art. All of
it is drawn by code in a handful of nodes, and the arena's node budget is unchanged
in kind: the late-game test still caps the standing node count.

**The story.** Home is Lantern Hollow, and Nari, its signal keeper, went to
repair the beacon road and never came back. Her last message asks the hero to
keep the road home lit — and the kettle on the hearth is on, so keep it warm.
The opening dialogue says all of that before you move; the first beacon you
light restores its place's memory and speaks one discovery line. Pause any
time to reread the objective: the road, the current Wave, and how many of
the six places you have remembered. Eight completed cycles resolve the
promise out loud — her signal answers, she reaches home, and the kettle is
warm — on the continue choice and, if you cash out, on the result screen,
where the settlement window glows. An early return shows the lamp still
waiting; defeat names the lamp and invites another run. Neither claims she
was rescued.

**Acts.** Cycles are grouped into three acts and an epilogue. The card for an act
plays on the cycle it begins, before that cycle's dialogue, and pauses the game
the way the dialogue does.

| Act | Begins on cycle | What is learned |
| --- | --- | --- |
| I · The Promise | 1 | Nari is gone; keep the road home lit |
| II · The Lost | 3 | What pursues you is lost, not hateful |
| III · The Road | 6 | Beacons must remember one another to form a road |
| Epilogue · The Road Home | 9 | The road home restored; other lights wait past the map |

**Place memories.** Each terrain keeps one concrete memory beside its beacon:
trail ribbons in the forest, wind chimes in the field, her kettle at the
camp, a signal bell in the frost, a paper boat in the marsh, a signal lens
in the ruins. Each motif stands dim until its beacon burns, and the first
restoration of that terrain in a run speaks its line — kept readable for
three seconds while the fork and guardian lines that share the beacon wait
their turn. Restoring is optional — the main arc runs on cycles alone and
the official win needs no particular terrain.

**The chronicle.** Entries are written into `chronicle.json` as their moments
occur; a place memory is recorded when its beacon is restored. A discovery or
first-sight line may wait until the screen is quiet, with its record already
kept. The title screen's Chronicle page lists all forty entries, the unmet
ones as blanks.
It has its own save file on purpose: purchases and shards live in the Vault,
whose writes are verified and backed up, and a reading log is not worth that
risk. A missing or unreadable chronicle simply starts empty.

**Hero voices.** Each hero except the Warden opens a run in their own words and
has their own line for the first beacon, a fallen guardian and low health. The
Warden carries Nari's message; the Keeper tends its hearths; the Knight once
guarded its road; the Dancer misses its festival; the Sage charted its
signals; Eclipse recognizes the first missing light. Their line is offered
first; the shared pool fills in after, and no line is ever said twice in a
run.

Store screenshots taken before 3.0.0 no longer match the game and were **not**
recaptured; recapturing is a separate, explicit decision.


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
  two collision structures are visible. Player and spirits walk the
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
course closed with store `2.1.0` for iOS and Android. 2.0.0 is the build
with a full art swap, a protagonist holding a beacon candle, and
eight-cycle dialogue. 2.1.0 adds beacon Safe Kindle / Overcharge,
pre-final-evolution relic resonance, return-or-continue after a
guardian, and anonymous event instrumentation, consent, and reporting
tools. 2.1.0's submission build ships collection disabled; the real
baseline starts from a later version with a protected ingest path on.
2.1.0 is the last recorded store release.

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
release-2.1.0      # final tutorial release: the game and course as taught
```

3.0.0 is not part of the course, and it is not yet tagged. It takes the
game to a new UI, a structured story, six places with forks, an endless
stretch that stays playable, and more guardians and skills; the lessons
keep describing the `release-2.1.0` screens on purpose. The premise is a
road home: Nari, the signal keeper of Lantern Hollow, went to repair the
beacon road and never came back, and each run keeps the road home lit.
Each restored place speaks one discovery line — trail ribbons, wind
chimes, her kettle, a signal bell, a paper boat, a signal lens.
