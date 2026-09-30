# 3.0.0 Expedition — more places, a real endless stretch

Author-only. Written 2026-09-29 after the user asked for: more varied maps, travel between
places lighting beacons, an endless loop past the official win that stays fun, more guardians
that do not bore on repeat, skills that keep appearing, difficulty that rises only slightly.

**Status: built, in the working tree, uncommitted.** This file was the plan; where the build differs
from it the text below says what was built. The build log (`3-0-0-build-log.md`) has the measured
results and what bit us; `apps/docs/docs/game.md` has the player-facing description.

## What is wrong now (read from the code, not guessed)

- `WORLD_STEPS` holds **three terrains** and `_world_step()` rotates them by
  `(cycle - 1) + zone`. No choice, and the order repeats every three zones.
- A guardian is `guardians[min(cycle - 1, 1)]`: the base form on cycle 1, the promoted form on
  every cycle after. From cycle 2 the same fight comes back with bigger numbers only.
- `toughness()` is x1.35 a cycle to cycle 3 and **x1.58 a cycle after that**. Cycle 8 is 17.9,
  cycle 12 is 112, cycle 16 is 700. Guardian sustain floors at 0.018 (a 50 second wall) from
  cycle 8. The stretch past the official win is a wall, not an endless game.
- Relic picks continue forever (`LEVEL_CAP` caps the kills a level costs, not the level), so the
  player keeps growing; nothing new ever *appears* for them after the sixteen relics are known.
- Cycles 1 to 8 are pinned by tests (`test_guardian_balance` pins cycle-3 HP and TTK). **They stay
  exactly as they are.** Everything below either starts at cycle 9 or is additive.

## Design (as built)

### 1. Places: three terrains became six

Frost Pass, Mirewood Marsh and Moonlit Ruins join the forest, field and camp. Each has its own
floor, tree sheet, four structures, light, raid formation (`RoomKind.Encounter`) and guardian.
The rows are appended to `Expedition.TERRAINS`; the index is the terrain id everywhere.

| Terrain | Opens at | Raid formation | Guardian (younger, then grown-up) |
| --- | --- | --- | --- |
| Frost Pass | cycle 3 | **Squall**: a wall of spirits marching straight in with a two-lane gap | Hoarfrost Owl, Rimecrown Owl (glide, two feather fans, a dive) |
| Mirewood Marsh | cycle 3 | **Tide**: three tight pods round you with a wide gap between each pair | Mirewood Toad, Glowcap Toad (hop, hop, flop on a marked circle) |
| Moonlit Ruins | cycle 4 | **Vigil**: a group ahead now, a second from behind 3.2 s later | Moonstone Sentinel, Halo Sentinel (glowing circles, then a ring with a gap) |

Why the formations changed from the first draft ("sweeping columns", "a ring that closes", "a
pincer"): the forest already rings you, the field already flanks you and a pincer is the field
again. A wall, three pods and a second wave are three different answers (slip, pick a gap, plan for
what comes behind).

A room's layout seed hashes its `encounter`, so every place needs a value of its own or two places
would build the same map from one seed.

### 2. Travel: two gates

- **Cycle 1 is the classic route** (forest, field, camp; one gate), and so is every hand-built arena:
  forks exist only in real runs (`RunEntry.from_title`), so every capture and older test is unchanged.
- **From cycle 2 each gate is a fork.** Two gates open on different rims, each naming its place in
  the place's colour and the omen waiting there; the gate after the second beacon names the
  **guardian** instead, so the route is a choice of boss.
- A new cycle opens somewhere other than where the last guardian fell. Choices are deterministic
  in the run seed. The later places join the pool at their `from_cycle`.
- The classic three grow their guardian with the cycle; the later places grow theirs with how often
  you have met it (`Arena._guardian_path_for`), so a first meeting is always the younger form.

### 3. Guardians that stay fresh

Mutations are small readable rules hung on the move machine every guardian has, so they work on
every style, including the three new ones (tested on every combination for 75 s of play):
Echo, Spiral, Summoner, Frenzy, Aegis, Meteors. Slots by cycle: none to cycle 4, one at 5 to 7, two
at 8 to 10, three at 11 to 14, four after, plus one for a Trial. Staging: a numeral for repeated
meetings ("Thornwood Pursuer II"), a banner naming the mutations, and a line under the health bar.

The three new grammars reuse the parts the old ones use (fan, ring, marked circle, dive) and combine
them differently, and each rest is marked with a mint glow.

### 4. The endless stretch: Depth

Depth = cycle - 8. The wall is replaced by a curve:

- Mob toughness x1.22 a cycle past cycle 8 (was x1.58); a guardian's own extra health x1.10 (was
  x1.22). The elite chance keeps climbing to 45%. The spirit cap stays 40 (mobile).
- **Guardian tempo eases past the win.** Windup haste, charge and bolt speed and the rest shrinking
  were `guardian_cycle`-driven with no cap: cycle 14 came to 3.6x haste (a 0.2 s windup) and cycle 30
  to 7x. `Spirit._tempo_cycle()` keeps them as shipped through cycle 8 and grows them a quarter as fast
  after it (cycle 30 is 3.4x). HP and the burst floor were already bounded.
- **Omens** per zone (one from Depth 1, two from Depth 5), shown on the gate that leads there:
  Blood Moon, Swarm Tide, Iron Night, Lantern Bloom, Dew Rain, Gale.
- **Moonless Trial** every fifth Depth: one more mutation than the cycle grants and two tiers of
  loot. (The draft also doubled the shard payout; that was not built.)

### 5. Skills that keep appearing

Nine relic cards unlock as cycles pass, each guaranteed on its first sighting and marked "New skill":
Lantern Familiar and Moon Ward from cycle 5, Comet Call and Star Magnet from 8, Moon Burst from 10,
Thorn Bloom and Second Light from 11, Winter Bell from 13 and Comet Trail from 16. A new one opens every
few cycles, so the endless stretch keeps offering something unseen. They are carried out by
`PlayerSkills` (one node, one `_draw`) and scale with the same damage multiplier as the other weapons.
Winter Bell needed a slow on `Spirit` (`chill()`, applied in `_glide` so every kind of motion feels it;
a guardian feels a third); Moon Burst hooks the card pick and Comet Trail the dash button.

### 6. Reading an attack

The guardian attack markers were redrawn after the thin red lines were called low effort: soft
gradient decals in one language, coral where it hurts and mint where it is safe
(`scripts/actors/telegraph_art.gd`).

Playing it with the bot (see the build log) found that the redrawn markers, like the ones before them,
**said less than the bolts did**: the fan's wedge stayed at one width while the fan grew from five bolts to a
dozen, a ring's drawn gap stayed at twelve spokes while the ring reached thirty, the second ring (cycle 6)
and the echo of a volley were not drawn at all, and a single aimed shot was drawn 118 px long though the bolt
flies on. So every volley is now one list of angles (`Spirit.volley_shape()`), and the bolts, the picture and
the bot's eyes read that list; a fan is capped at 69 degrees, a ring or cross keeps a way through of at least
16 degrees either side, a volley carries at most 22 bolts, the first fan of a sequence is shown for at least
0.75 s and the ones after it are narrower, an echo is drawn beside its volley while it winds up and until it fires (and only the last fan of a run repeats), and
guardian bolts have a range (260 px) the pictures reach. `tests/test_volley_fairness.gd` holds every
guardian at cycles 1 to 100 to those rules, including a model of a person (the slowest hero, a reaction of a
third of a second) getting out of a fan; `tests/test_telegraph_floors.gd` holds the minimum warning times.

## Budgets and rules this must respect

- Late-game node budget 1200: measured 1097 (Lv20) and 1167 (Lv40) on the forest, and every later
  room is lighter than the forest (frost 586, marsh 696, ruins 529 room nodes against 766).
- Hostile bolts stay capped at 24; ground marks at 8 alive; skills draw in one node.
- New strings in five languages; the CSV rule (no ASCII commas in a cell) applies.
- The repo bans one word for a stage of a plan or a fight; use "stage" or "step" in code, comments and docs.
- Store screenshots are not touched. `apps/game/` is already fingerprint-invalid.

## Verification

1. **Pure functions** (`Expedition`): curve, slots, route, omen and mutation draws are tested for
   monotonic growth, caps, determinism and no repeats (72,000 cases).
2. **Real arena**: forks (one gate on cycle 1, two from cycle 2, the later places from 3 and 4),
   omens, guardian staging, skills, the raid formations as queued positions.
3. **Live guardians**: each new grammar stepped for bolts and marks, then every mutation on every
   new guardian for 75 s.
4. **Soak**: `tools/soak_run.tscn`, an invulnerable stand-still bot through 14 cycles on the real
   arena, JSON per cycle (which places and guardians it met included). It answers "is there a cliff" and
   does not answer "is it fun". Measured: spirit lifetime 25 s to 28 s across the win on the new curve,
   against 27 s to 36 s and a collapse of kills a minute on the old one.
5. **Play**: `tools/play_bot.tscn` plays the real arena (see the build log): a guardian gauntlet (every
   place at cycles 2 to 14), natural first loops, invulnerable two-loop runs for pacing, boosted runs at
   cycles 3 to 16. It found the telegraph and windup problems above; it is not a person.
6. **Feel**: the emulator (`emu-5554` only); the phone only when the user says so.

## Not done

- A player's-eye judgement of the curve. The soak shows the growth stays in step with a growing player and
  the bot shows the fights can be answered by something that reads the picture; only a person can say whether
  it is enjoyable or how hard it feels. Add telemetry (depth reached, omen chosen) if tuning is wanted.
- The repeat of a **ring** (an Echo on the field, forest, toad or sentinel guardian) is still trimmed by the cap of
  two dozen bolts when the first ring is in the air (a ring of 17 to 22 leaves room for 2 to 7 more), while its
  picture shows the whole ring. That is the safe way to be wrong. Fixing it means either fewer spokes when an
  Echo is present or a higher cap, and the late-game node budget (1167 of 1200) does not have room for the second.
- A first-fork hint line for the hero.
- The result screen still says "Cycles N" past the win; a "Depth N" line would suit it.
- Store screenshots were not touched (see `AGENTS.md`).
