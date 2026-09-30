# World + story pass (bible)

Author-only design authority for the story/world/boss/map polish.
Canon first, then the exact keys and wiring. Follow-up slices reference
this file; do not contradict it without updating it.

## Canon

- Home is **Lantern Hollow** (등불마을). **Nari / 나리** is its signal
  keeper and a friend of the chosen hero. She left to repair the failing
  beacon road and disappeared in the Moonless. Her last message: keep the
  road home lit — and the kettle on the hearth is on, keep it warm till
  she is back. Eight completed cycles resolve the promise out loud: her
  signal answers, she reaches home, and the kettle is warm. Nobody claims
  Nari herself is home before the road is complete; until then the window
  lamp waits for her.
- The dark is a hunger, not a villain. It swallows light and with it
  paths, names and shared memories. Beacons draw lines it cannot cross.
- Spirits do not hate the living. They are lost fragments that follow
  light the way moths do; the dark spits out what it cannot digest and
  they shamble toward the nearest flame. Scattering them is pushing, not
  killing — the score calls it "spirits scattered", never kills.
- Guardians are swallowed light clotted into a body. Each one keeps a
  habit of the place it ate: forest charges the old patrol paths, field
  answers with the old signal cross, camp curls round a stolen hearth,
  the owl still guards its pass, the toad hops the old ferry stones, the
  sentinel keeps a vigil no one set. Elites are the same hunger older and
  angrier (cycle 6). Recovering the light restores a way home.
- One beacon is a fire. Beacons must remember one another to make a road;
  each flame holds the next one's name. That is the line the dark cannot
  cross (cycles 6–7).
- Past cycle 8 Nari is home and the road home burns. Continuing into
  Depth is a voluntary expedition for other forgotten roads, never a claim
  that the ending did not matter. The Moonless gets its name at cycle 10:
  it does not hate, it only forgot light, so the hero reminds it one road
  at a time.
- Defeat and early return close compassionately and name a concrete
  reason to try again: the lamp stays lit for your return; her lamp
  still waits.

## The heroes

Each hero has a different relationship to the same place and promise.
The Warden carries Nari's message; the Keeper tends its hearths; the
Knight guarded its road; the Dancer misses its lighting festival; the
Sage charted its signals; Eclipse read the first missing light. Paid
heroes are alternative voices, never prerequisites for the main story.

## Place memories

Each terrain reveals a local memory through a recognizable object and a
sensory detail. A crafted motif stands beside the beacon clearing, dim
until the beacon burns; the first restoration of a terrain in a run speaks
one nonblocking discovery line and records one chronicle entry (recorded at
restore time, so a suppressed line never loses its entry). Repeats and
fresh runs still restore the motif visibly. Fork gates hint the waiting
memory on their own line; terrain, omen and guardian naming is unchanged.
A fresh discovery owns the voice strip for three seconds: the fork,
guardian-meet and moonfire lines that fire on the same beacon are taken at
once and spoken after, while gate labels, the guardian banner and its bolts
stay immediate. A discovery suppressed by a modal, a transition or capture
is queued, never marked seen, and plays when the screen is quiet.

| Terrain | Motif | Discovery key |
| --- | --- | --- |
| forest | trail ribbons, still fluttering | PLACE_MEMORY_FOREST |
| field | wind chimes ringing the signal back | PLACE_MEMORY_FIELD |
| camp | her kettle; the camp breathes again | PLACE_MEMORY_CAMP |
| frost | a bell under the snow cutting the wind | PLACE_MEMORY_FROST |
| marsh | a paper boat carrying her wish | PLACE_MEMORY_MARSH |
| ruins | a lens in the stones catching the moon | PLACE_MEMORY_RUINS |

## Acts

| Act | Cycles | Movement |
| --- | --- | --- |
| I · The Promise | 1–2 | A promise and a trail: who Nari is, what was lost, what to do |
| II · The Lost | 3–5 | What pursues the hero is lost rather than hateful |
| III · The Road | 6–8 | Beacons must remember one another to form a road |
| Epilogue · The Road Home | 9+ | The road home restored; other lights wait beyond the map |

## Beat-to-trigger map

| Beat | Trigger | Keys |
| --- | --- | --- |
| Opening: Nari, the kettle, the promise | run starts from the title, before movement | STORY_OPEN_A/B + STORY_CYCLE_1_A/B |
| Goal: three beacons a Wave | same dialogue | STORY_CYCLE_1_A/B |
| Discovery in a place | first `lit_changed` of that terrain in the run | PLACE_MEMORY_* + motif lights |
| Discovery guard | fork, guardian meet or moonfire fires on a restoring beacon | line taken at once, strip speaks after 3 s |
| What pursues is lost | cycles 3–5 open | STORY_CYCLE_3/4/5 |
| The road must remember itself | cycles 6–7 open | STORY_CYCLE_6/7 |
| Last Wave | cycle 8 opens | STORY_CYCLE_8_A/B |
| Nari is home | cycle choice at cycle 8+ | CYCLE_CHOICE_MAP_BEYOND_TITLE/SUBTITLE |
| The road home burns | cycle 9 opens | STORY_CYCLE_9_A/B |
| The Moonless named | cycles 10 and 12 open | STORY_CYCLE_10/12 |
| Guardian habits | first meeting per run, per form | VOICE_MEET_GUARDIAN_* |
| Route memory hints | fork gates open from cycle 2 | PLACE_CLUE_* on gate line 3 |
| Objective reminder | pause opens | OBJECTIVE_ROAD + OBJECTIVE_PLACES |
| Early return | settlement before cycle 8 | STORY_EPITAPH_ESCAPE + dim window |
| Official win | settlement at cycle 8+ | STORY_EPITAPH_WIN + lit window |
| Defeat | health 0 | STORY_EPITAPH_LOSE, no window |
| Voluntary expedition | continue chosen at cycle 8+ | CYCLE_CHOICE_MAP_BEYOND_RIGHT_* |

Main beats depend on cycle progression only, never on terrain RNG. An
official win needs no particular terrain and no purchased hero.

## First minutes (what a person actually sees)

Title → hero pick → the opening dialogue: Nari is gone, her message
asks the hero to keep the road home lit and the kettle warm, and the
goal is three beacons a Wave starting with this forest. Dismiss it and
move: the first beacon lights its motif and speaks the forest memory.
Pause any time to reread the objective. The chronicle on the title keeps
everything seen so far.

## Spirit motivations (first-sight lines)

One line each, said once per run on first sight. They explain why it
fights without pausing the game.

| Kind | Truth | Key |
| --- | --- | --- |
| drifter (night moth) | Drawn to moving light; clings to what glows | VOICE_MEET_DRIFTER_1 |
| ember | A cinder that never went out; wants company in burning | VOICE_MEET_EMBER_1 |
| caster | Chants to the dark to be noticed; its shots are prayers | VOICE_MEET_CASTER_1 |
| weaver | Stitches dark over light; thinks it is mending | VOICE_MEET_WEAVER_1 |
| stalker | Remembers being a keeper; hunts the flame it lost | VOICE_MEET_STALKER_1 |
| swarm | Hunger on the wind; no thought, only mouths | VOICE_MEET_SWARM_1 |
| wisp | Curious and harmless until crowded; fear makes it sting | VOICE_MEET_WISP_1 |

## Guardian first meetings

One line each, said instead of the generic guardian line on the first
meeting per run. Name + dodge rule still come from the HUD banner. Each
line ties the form to the habit of its place.

| Guardian | Key |
| --- | --- |
| Thornwood Pursuer | VOICE_MEET_GUARDIAN_FOREST_1 |
| Azure Fieldwing | VOICE_MEET_GUARDIAN_FIELD_1 |
| Emberclad Warden | VOICE_MEET_GUARDIAN_CAMP_1 |
| Thorn King Pursuer | VOICE_MEET_GUARDIAN_FOREST_THORN_1 |
| Storm Fieldwing | VOICE_MEET_GUARDIAN_FIELD_STORM_1 |
| Siegeclad Warden | VOICE_MEET_GUARDIAN_CAMP_SIEGE_1 |
| Hoarfrost Owl | VOICE_MEET_GUARDIAN_FROST_1 |
| Rimecrown Owl | VOICE_MEET_GUARDIAN_FROST_RIME_1 |
| Mirewood Toad | VOICE_MEET_GUARDIAN_MARSH_1 |
| Glowcap Toad | VOICE_MEET_GUARDIAN_MARSH_GLOW_1 |
| Moonstone Sentinel | VOICE_MEET_GUARDIAN_RUINS_1 |
| Halo Sentinel | VOICE_MEET_GUARDIAN_RUINS_HALO_1 |

## Deep-night beats (cycles 10+)

Cycles 10 and 12 play full pausing dialogue (STORY_CYCLE_10_A/B,
STORY_CYCLE_12_A/B): the Moonless gets its name and the hero answers it
one road at a time. Other deep cycles fall back to the nonblocking strip
aside (`_say("cycle")`, VOICE_CYCLE_1..8).

## Boss fun: call of the dark

At 50% HP, once per guardian, it calls two swarm escorts and the Warden
answers (VOICE_CALL_DARK_1/2). Reuses `_summon` with a forced swarm
kind at the guardian's position. The existing 30% haste stays; this is
the visible mid-fight beat that was missing.

## Guardian pressure pass (done)

Each guardian now has a second answer so fights alternate instead of
looping one trick. Forest slams a shockwave ring after its charge combo
(gap faces the player — hold ground, the opposite of the charges).
Field fires one aimed bolt per strafe with a short aim line. Camp fires
a re-aimed second fan before its armor opens. All reuse existing
telegraphs, sheets, and bolts; HP and damage budgets are untouched, so
the balance contract still holds. HUD dodge rules stay as they are —
the main lesson per boss did not change.

## Map variety: colder nights

`_apply_time_tone` multiplies the time tone by a cycle shade so later
cycles read colder even at the same beacons: cycles 1-3 identity,
4-6 ×(0.95, 0.96, 1.0), 7+ ×(0.88, 0.92, 1.0). GPT obstacle batch lands
in room Details later; art first, collision never without a decision.
