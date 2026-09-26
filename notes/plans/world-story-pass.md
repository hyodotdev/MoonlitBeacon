# World + story pass (bible)

Author-only design authority for the story/world/boss/map polish.
Canon first, then the exact keys and wiring. Follow-up slices reference
this file; do not contradict it without updating it.

## Canon

- The dark is a hunger, not a villain. Beacons draw lines it cannot
  cross (cycle 7). Burning three beacons a night pushes it back.
- Spirits do not hate the living (cycle 4). They follow light the way
  moths do; the dark spits out what it cannot digest and they shamble
  toward the nearest flame. Scattering them is pushing, not killing —
  the score calls it "spirits scattered", never kills.
- Guardians are swallowed light clotted into a body (cycle 2, voice).
  Each one keeps a habit of the place it ate: forest charges down
  corridors, field answers with crossfire, camp turtles behind armor.
  Elites are the same hunger older and angrier (cycle 6).
- The Warden order kept beacon lines across forest, field, and camp.
  Playable heroes are its last members; the camp hearth (cycle 3) is
  where a line failed before.
- Past cycle 9 the night is off the map. Nothing down there has a name
  yet, so the Warden only mutters asides.

## Spirit motivations (first-sight lines)

One line each, said once per run on first sight. They explain why it
fights without pausing the game.

| Kind | Truth | Key |
| --- | --- | --- |
| drifter (night bat) | Drawn to moving light; bites what glows | VOICE_MEET_DRIFTER_1 |
| ember | A cinder that never went out; wants company in burning | VOICE_MEET_EMBER_1 |
| caster | Chants to the dark to be noticed; its shots are prayers | VOICE_MEET_CASTER_1 |
| weaver | Stitches dark over light; thinks it is mending | VOICE_MEET_WEAVER_1 |
| stalker | Remembers being a keeper; hunts the flame it lost | VOICE_MEET_STALKER_1 |
| swarm | Hunger with wings; no thought, only mouths | VOICE_MEET_SWARM_1 |
| wisp | Curious and harmless until crowded; fear makes it sting | VOICE_MEET_WISP_1 |

## Guardian first meetings

One line each, said instead of the generic guardian line on the first
meeting per run. Name + dodge rule still come from the HUD banner.

| Guardian | Key |
| --- | --- |
| Thornwood Pursuer | VOICE_MEET_GUARDIAN_FOREST_1 |
| Azure Fieldwing | VOICE_MEET_GUARDIAN_FIELD_1 |
| Emberclad Warden | VOICE_MEET_GUARDIAN_CAMP_1 |
| Thorn King Pursuer | VOICE_MEET_GUARDIAN_FOREST_THORN_1 |
| Storm Fieldwing | VOICE_MEET_GUARDIAN_FIELD_STORM_1 |
| Siegeclad Warden | VOICE_MEET_GUARDIAN_CAMP_SIEGE_1 |

## Deep-night asides (cycles 10+)

`_show_cycle_story` already falls back to `_say("cycle")` past 9. Four
more asides join VOICE_CYCLE_1/2: VOICE_CYCLE_3..6. No pausing dialogue
down there — balloons only.

## Boss fun: call of the dark

At 50% HP, once per guardian, it calls two swarm escorts and the Warden
answers (VOICE_CALL_DARK_1/2). Reuses `_summon` with a forced swarm
kind at the guardian's position. The existing 30% haste stays; this is
the visible mid-fight beat that was missing.

## Map variety: colder nights

`_apply_time_tone` multiplies the time tone by a cycle shade so later
cycles read colder even at the same beacons: cycles 1-3 identity,
4-6 ×(0.95, 0.96, 1.0), 7+ ×(0.88, 0.92, 1.0). GPT obstacle batch lands
in room Details later; art first, collision never without a decision.

## Follow-ups (not this slice)

- Per-hero voices (table is hero-agnostic today).
- A fourth terrain (needs GPT art + room scene + world-step wiring).
- New guardian attack patterns per family.
