# 3.0.0 build log

Author-only. What was actually built for 3.0.0, why it is shaped the way it is,
and what bit us. The plan it followed is `3-0-0-ui-story.md`; this is the record.

3.0.0 is a completely new UI and a structured story on top of the 2.1.0 game
(`release-2.1.0`). The art stays a cute little mini-game.

## What changed

### The night has depth

- `camp` and `field` floors were a **single flat colour** (`floor.png` held one
  untextured strip; the field cropped an equally flat 16px tile). No tint fixes
  that, so they now repeat a seamless 96px tile from `tools/build_ground_tiles.py`.
  The forest already had a real textured floor and is untouched.
- The camp room tint was `(0.5, 0.38, 0.34)` — a red-brown multiply that turned a
  night camp into a daytime dirt lot. Re-toned cool; lantern light supplies the warmth.
- `NightVignette` on the arena's `Ui` layer. The title had one; the arena did not,
  and `room.tscn` carried the gradient resources with no node using them.
- `RoomLights`: one node draws every lantern pool additively. `RoomKind.light_*`
  lets each terrain declare its own sources instead of `Room` hardcoding names.

### The night, lit as one scene (second pass)

The first pass gave the arena a vignette and lantern pools. It still read as a flat
floor with small sprites on it, and the user's verdict on the result was that
nothing about the characters or the map had changed. The second pass is a rendering
pass, not an art pass: **no sheet was redrawn**, and every effect is code.

The reference is HD-2D: pixel sprites under modern lighting. One light direction
(moon, upper left) is used everywhere so the scene agrees with itself.

- `RoomShadows`: one node, one `_draw()`, a cast ellipse plus a contact patch per
  piece. Sizes come from a `SHADOW` table measured from each tile's alpha
  (`base width`, `height`, `strength`); tiles under 16px cast nothing.
- `shaders/world_polish.gdshader`: rim on the moonward edge, brighter crown, darker
  foot, optional crown sway on the nature sheet's trees. **One shared material per
  sheet, not per tile height.** A material per height is tidier and breaks the
  y-sorted decor's draw batches on every neighbour; the shader instead reads each
  sprite's height off its own quad (a varying that is 0 at the top vertices and 1 at
  the bottom interpolates to "how far down the piece"). Sway is limited to the
  sheet rows that hold trees (`tree_rows_above`).
- `RoomTone` (colour patches over the repeating floor), `RoomFlora` (mushrooms,
  flowers, tufts as `draw_rect` pixels, so no sheet), and `RoomLights` grew
  breathing dapples and plant glows. Own RNG keyed on seed and terrain, so the
  amount of floor life never moves a tree or a structure.
- `RoomAtmosphere`: mist on two `Parallax2D` layers (0.88x and 1.25x scroll), slanted
  light shafts (one baked soft-edged texture, each shaft that texture sheared to lean
  away from the moon, drawn once), and motes drawn by the script around the camera.
  **The mist is procedural noise, not the title's painted cloud sheet**: painted clouds
  have hard tone steps that read as stacked discs once the fog is bright enough to see.
- `RoomLayer`: the base of the shadow, tone, flora and light layers. One node draws
  about three thousand small pieces for a 1900x1180 map and the screen shows a tenth
  of it, and one canvas item cannot be culled in part. The layer draws **only what the
  camera can see**, padded, and redraws when the padded view crosses into a new cell of
  a 192px grid: walking redraws a tenth of the layer about once a second, standing
  still costs nothing. The alternative, a node per chunk, would spend the node budget.
- `shaders/night_grade.gdshader`: a full-screen grade on the `Ui` layer, first child, so
  it grades the world and nothing drawn after it. One screen-texture read.
- `shaders/actor_polish.gdshader` on the hero, spirits and guardians: moonlit rim,
  outline coloured from the neighbouring art (a purple hood gets a deep purple line),
  bright saturated pixels lifted past the night tint. The outline reads one pixel past
  the art, so **every frame needs a clear pixel on its left, right and top edge**;
  `tests/test_room_depth.gd` checks every hero, spirit and guardian sheet and proves
  the check can fail. The bottom row is exempt: feet touch it and nothing is drawn below.
- `KillSparks`: one node draws every burst (a list of rows, not a node per kill).
  Spirits reach it through a group, so a spirit in a test with no arena dies quietly.
- `SoftDisc` replaces four copies of the same radial-gradient builder.

Node budget: the late-game test's peak went from 1152 to 1179 of 1200. These effects
are about a dozen standing nodes (three room layers, the atmosphere scene's seven, the
grade, the spark pool, the hero's moon pool). **Twenty-one nodes of headroom are left;**
spending more here needs a matching cut somewhere else.

What to check by eye is under `tools/`, all excluded from the capture fingerprint:
`shot_actors` (every actor kind, at game zoom and 3x, plus a spark burst), `shot_rooms`,
`shot_tour` (camera at the four corners, to see the mist tile and the shafts land) and
`shot_arena` (the real scene a few seconds into a run, HUD included, with `Ui/Grade`
style arguments to delete a layer and compare).

### New mob designs

The 2.5D re-art attempt (PR #6) was closed for regressing the mobs, and 3.0.0 left their
sheets alone. Afterwards the user asked for the characters and mobs to actually change, and
chose to have them drawn with ChatGPT's image generator (driven through Chrome, on their
account). Two lineups of seven were made from the same brief and shown side by side:

- **Ghost family kept**, with expression and props doing the work (rejected);
- **Different silhouettes** (chosen): wisp = cloud puff, drifter = sleepy leaf moth,
  ember = round flame, caster = mushroom mage with a lantern staff, weaver = jellyfish,
  stalker = shy cat-bat, swarm = dandelion-puff pup. Colours and roles are unchanged.

The lineup is one picture on flat magenta, because a generator draws seven creatures that
share a style far better in one image than in seven. `tools/cut_lineup.py` cuts it
apart into keyed sources (Pillow only, refuses a wrong creature count instead of guessing),
`pack_grok_spirits.py` packs them, and `--check` still confirms every committed sheet matches
its source. The raw lineups are in `_asset_sources/chatgpt_spirits_2026-09-29/` (not in git);
the old Grok sources are in git history.

Things that mattered:

- **A mob ships 15 to 24 pixels tall**, so a design is judged there. Silhouette and a big face
  survive; wing veins and mushroom spots do not.
- **The first-sight lines had to change with the art.** Drifter said "Night bats" for a moth,
  Wisp said "flame" for a cloud (Ember is the flame) and Swarm said "with wings" for a
  dandelion. Rewritten in all five languages. Stalker, Caster, Weaver and Ember still fit.
- The docs manifest described a 24px-cell bestiary that no longer existed; it now describes the
  192x192 sheets and the new designs.

### Guardians and heroes redrawn

The user then asked for the guardians and the six heroes to be redrawn the same way, and said
the store images can be shot again afterwards.

- **Guardians.** One 3 x 2 grid on magenta: three terrains, each with its evolved form. Forest
  is a mossy leaf-winged golem (thorn form: cracked with red veins, horned), Field a blue moth
  sprite holding an orb (storm form: purple with lightning wings), Camp a stone furnace golem
  (siege form: riveted iron with cannons). The existing names still fit (Thornwood Pursuer,
  Azure Fieldwing, Emberclad Warden and their promotions), so no strings changed.
  `pack_ludo_guardians.py` still bakes its 22 sheets by deforming the one body.
- **Heroes.** Three lineups of the six on magenta (front first, then back and left drawn from
  it) plus three 6 x 4 walk-cycle grids, one per facing, so every facing has four drawn
  frames instead of a boot shift. The designs are described in `tools/hero_maple/README.md`.
  The heroes stayed 36px tall in the same 48 x 64 cell, so no combat or layout code moved.
- `cut_lineup.py` grew `--rows`, `--gap` and `--frames`; `--frames 4` puts the four frames of
  one walk on a shared canvas with the feet on one baseline.

### One UI kit

`tools/build_ui_kit.py` generates 36 nine-patch PNGs, two beacon icons, the shared
`resources/ui/**/*.tres` style files and the asset-contract entries, from one
registry that keeps each margin next to its art.

Rules it enforces, each written after a real seam or stripe showed up:

- the stretched centre is **one solid colour**;
- every stretched edge strip is **uniform along its axis** (a border tone that
  changes inside the stretched band draws a seam down every tall panel);
- alpha is binary.

Why textures and not rounded `StyleBoxFlat`: with `canvas_items` stretch a flat box
is tessellated at device resolution, so its corners come out smooth-vector next to
pixel sprites.

All 17 UI scenes were migrated by editing scenes (via a block-based `.tscn` editor
that round-trips every scene byte for byte) and the code-built rows in shrine, shop,
hero preview and the voice strip. The old `panel_moonlit` / `button_*_moonlit` art,
its generator and its contract entries are deleted: nothing referenced them any more.

Screens that got a real layout change, not just a reskin: the relic picker (card
with emblem, name, description and route inside a 9-slice), the combat HUD
(brazier strip, emblem chips, quiet secondary lines, rounded boss bar), pause,
settings, result, the run-choice modals, and the title (a fifth button).

### The story has a shape

- `Acts`: three acts and an epilogue over cycles 1 / 3 / 6 / 9, each with a title
  card that plays ahead of the cycle's dialogue.
- `Chronicle`: 28 entries, written as they are seen, listed on a title-screen page.
  Own file (`user://chronicle.json`), deliberately **not** in the Vault.
- Per-hero openings and three moment lines for the five non-Warden heroes.
- The Moonless: the endless stretch gets a name at cycle 10, and cycle 12 says why
  it is not an enemy. Two new asides keep the deep night talking about it.
- 5 languages throughout (`moonlit.csv`, 458 rows). Cells may not contain ASCII commas.

### Result depth, one Wave, whole shop blurbs

- Past cycle 8 the result epitaph shares its full-width line with the Depth
  (`HUD_DEPTH`, from the same `Expedition.depth()` the HUD reads). A second
  line under the epitaph was tried first and does not fit: the six-line score
  table already needs 117px of its 110px box, so a two-line epitaph breaks the
  title/table gaps in every language. Same-line keeps every rect untouched.
  Score arithmetic, ladder format and the five breakdown lines are unchanged.
- English now names the loop Wave everywhere: `SCORE_CYCLES` is "Waves %d" and
  the two relic strings say "wave". Japanese `周回` became `巡` in the same two
  relic strings, and `SCORE_CYCLES` in the other languages keeps only its one
  term. No key renamed.
- Shop non-coin cards show the whole blurb: three lines instead of two (card
  minimum 98 to 117, actual 105 to 118). The probe found the ellipsis not only
  on hero cards in English and Japanese but on the supporter (English) and
  lantern (Korean, English, Japanese) cards too, so every non-coin card grew
  and the row stays uniform. The frame grows 328 to 333, still inside the
  337px safe area; `test_iap_hero_previews` (603 cases) passes unchanged.
- New test `test_result_depth` (past the win shows the depth, at the win it
  does not, score untouched) registered in `run_regression_tests.mjs`;
  `test_result_layout` covers the depth caption in five languages. The new
  test was broken on purpose (depth never shows) and failed 10 cases, then
  passed again when restored.
- The expedition plan's "Not done" named a first-fork hint as missing; it
  exists (`VOICE_FORK_1/2`, `_say("fork")` in `_open_fork`), so that line and
  the "Cycles N past the win" line are removed there. This log's "Not done"
  never named the fork hint, so there was nothing to correct in it.

## Expedition: six places, forks and an endless stretch that stays playable

Plan and reasoning: `3-0-0-expedition.md`. Player-facing description: `apps/docs/docs/game.md`
(*Forks*, *The endless stretch: Depth*, *Guardians of the later places*).

What is in the tree:

- **`Expedition`** holds the rules as plain functions of (run seed, cycle, zone): the six-place table,
  the fork draw, the difficulty curve, guardian mutations, omens and the Moonless Trial. Cycles
  1 to 8 keep their shipped numbers (tests pin them); past the win mobs grow x1.22 a cycle instead
  of x1.58 and guardians x1.10.
- **Forks.** From cycle 2 a beacon opens two gates on different rims, each naming its place
  (and the omen, or on the way to the last zone the guardian). Only real runs (`RunEntry.from_title`)
  get forks; a hand-built arena keeps the one classic gate, so every capture and older test is unchanged.
- **Three new places**: Frost Pass, Mirewood Marsh, Moonlit Ruins (from cycle 3, 3 and 4). Each has its
  own floor, tree sheet, four structures, light and raid formation (a wall with a gap, three pods,
  a group ahead then one behind).
- **Three new guardians** in three new grammars (owl: fans then a dive; toad: hop, hop, flop on a
  marked circle; sentinel: glowing circles then a ring with a gap), each with a younger and a grown-up
  form. The later places meet the younger form first, then the grown-up.
- **Nine skill cards** that unlock by cycle (5, 5, 8, 8, 10, 11, 11, 13, 16), **omens** per zone and a **Depth** label on the HUD.
- **Guardian attack markers** were redrawn as soft coral (hurt) and mint (safe) light decals after
  the thin red lines were called low effort. See `scripts/actors/telegraph_art.gd`.

New tests: `test_expedition`, `test_fork_travel`, `test_omens`, `test_guardian_mutations`,
`test_guardian_staging`, `test_skills`, `test_raid_formations`, `test_guardian_new_styles`; the
terrain, depth, visual and story tests cover the six places and twelve guardians.

New tools: `tools/soak_run.tscn` (an invulnerable stand-still bot through 14 cycles on the real
arena, JSON per cycle), `tools/shot_expedition.tscn`, `tools/shot_telegraphs.tscn`,
`tools/shot_new_guardians.tscn`, `tools/shot_skills.tscn`, `tools/count_terrain_nodes.tscn` (the node
count of each room), `tools/route_stats.gd` (how evenly the fork draw offers the six places),
`tools/pack_terrain_structures.py`, `tools/build_terrain_tilesets.py`, `tools/build_skill_icons.py`.

What the soak measured: the same seed (7), the same stand-still invulnerable bot, 60 s a zone, speed 4,
fourteen cycles, the old and the new curve differing only in the growth past cycle 8.

| | cycles 2 to 8 | cycles 9 to 14 |
| --- | --- | --- |
| Average life of an ordinary spirit, new curve (x1.22) | 25 s | 28 s |
| the same, old curve (x1.58) | 27 s | 36 s |
| Kills a minute, new curve | 33 | 19 (15 to 23, steady) |
| the same, old curve | 26 | 11 (falling to 5) |
| Player level at cycle 14 | 75 new | 60 old |

Toughness at cycle 14 is 59 on the new curve and 279 on the old. The old curve is the wall the plan
described: fights stretch, kills a minute fall to a third and the player stops growing. The new one
keeps the loop turning and creeps up about 9% in spirit lifetime over six cycles, which is the "a
little harder each time".

In the final run the bot travelled through all six places and met eight different guardians (both forms
of the owl and of the toad among them), with no error output. The harness's node peak is 1330 because
it counts its own nodes; the arena's late-game budget test reads 1176 of 1200. Over 400 seeds and
cycles 3 to 14 every place opens 15 to 19% of the cycles and is offered at 15 to 18% of the gates.

A stand-still bot cannot judge guardian fights (the camp and sentinel styles keep away from it and time
out), so the guardian time-to-kill column is not evidence of anything, and it cannot say whether the
stretch is fun; only play can.

### A player that plays: the bot, and what playing it found

`tools/play_bot.tscn` plays the real arena headless through the arena's own input (the stick's value, the
dash handler), and writes `builds/play/<tag>.json` (`tools/play_report.py` summarises). It looks ten times a
second, notices a warning on the floor a quarter of a second after it appears (`react=`), holds a comfortable
distance from a guardian, steps out of what is marked, sidesteps or dashes when boxed in, takes cards, ends a
run after one or two loops (an endless game is judged by its loops). Usage is in the file's header; the memory
note `moonlit-play-bot` has the traps. It is a proxy player, not a person: it never gets bored and never
misjudges a gap, and it reacts on a fixed schedule. It is good at telling **two versions of the game apart**
and at finding things a stand-still soak cannot.

What was run (36 natural runs of one or two loops on this tree and 12 on the 2.1.0 tree, 12 invulnerable
two-loop runs, 12 boosted runs at cycles 3 to 16 that met all six places and took all nine new skills, and about a
thousand isolated guardian fights, some 26 hours of play in all):

- **Does play work as before?** The same bot on the 2.1.0 tree (`git archive HEAD apps/game` in the
  scratchpad, with a handful of members patched in) and on this one, same seeds and heroes. Invulnerable, the
  two trees give the same kills a minute (35 and 39), the same player levels at each zone and the same
  spirit counts. Mortal, with the final bot, 9 of 12 runs ended their loops alive on the 2.1.0 tree and 7 of 12 on
  this one, at 0.64 and 0.66 hits a minute and 35 and 38 kills a minute: the same, within what twelve runs can
  tell. (Its first version died in the first loop on both trees, which is why its verdicts were not trusted
  until it was fixed.) Cycle 1 to 4 numbers did not move; the tests pin them too.
- **Pacing** (invulnerable natural loops): a zone takes 60 s (forest), 80 to 85 s (field) and 70 to 100 s
  (camp), a guardian 35 to 45 s, a loop about four and a half minutes. Twelve seconds with nothing near
  happened about once in four minutes. No soft locks in 100 runs; the stuck reports were the bot refusing to
  walk within 26 px of the wall, fixed in the bot.
- **The bot's first verdict on the guardians was wrong, twice**, and both times it was the bot's. It skipped
  every spirit farther than 110 px, warnings included, so it never dodged a volley from where it fought; and
  it held one wedge width for every cycle. Fixing them moved the win rate of the isolated gauntlet (six places
  x cycles 2, 4, 6, 8, 9, 12, 14 x warden and knight, 84 fights) from 75% to 94%. Those are bot numbers.
  What was the game's is below.

What playing it found in the game, in the order found, and what was done:

1. **Windups fell to a fifth of a second** past cycle 6 (haste divides them). Floors now: 0.45 s for a fan, a
   ring or a charge, 0.75 s for the first fan of a sequence, 0.85 s for a circle on the floor. Cycle 1 keeps
   every authored windup. **What differs from 2.1.0 at cycles 1 to 4** (everything here, checked against
   `git show HEAD:...spirit.gd`): the forest's second charge is 0.03 to 0.10 s longer at cycles 2 to 4, the camp's
   second fan 0.42 s to 0.45 at cycle 4, a camp fan carries 7 bolts and not 8 at cycle 4 (the grown-up camp 7 and
   not 8 or 9 from cycle 3, and its span 1.2 and not 1.28 at cycle 4), the field's cross is turned so that the aim
   falls between two arms whatever their number (it was a quarter turn, right only for four arms), and every
   guardian bolt fades out after 260 px, cycle 1 included (it flew to the wall). Past cycle 4 the floors, the
   caps and the ranges are what changed the game.
2. **The pictures said less than the bolts did** (see the plan, section 6). Wedge width, ring gaps, the second
   ring, the echo, the aim line. Shared angle lists now feed the bolts, the pictures and the bot; an echo is
   drawn faintly beside its volley while it winds up and until it fires, and only the last fan of a run
   repeats (the owl's three fans and the camp's two are one attack: six fans in two seconds is not a
   pattern); the aim line is a soft band to the player and past.
3. **Fans became unleavable from cycle 7.** Width grew 0.08 rad a cycle to 2 rad, the owl blew three aimed fans
   0.45 s apart, and the bolts kept speeding up. Now: a fan is at most 69 degrees, the ones after the first
   are narrower, bolt speed stops at 1.4x, a ring or cross keeps at least 16 degrees of clear way, and a
   volley carries at most 22 bolts (a ring of 26 plus a second ring of 9 could not all fire under the cap of 24
   in the air, so the second ring never came and the drawn ring was a lie), and a whole run of fans plus the
   repeat of its last one fits under the same cap (the owl's third fan fired nothing from cycle 8; a fan carries
   at most 7 feathers, 5 in a run of three; the young owl blows two fans at every cycle and the grown-up
   Rimecrown Owl three, which is what its rule line always said). `test_volley_fairness` holds all
   thirteen guardians at eighteen cycles (up to 100) to it, with a model of the slowest hero reacting in a third of a
   second; it failed against the old numbers and fails again if a cap is removed (checked).
4. **Guardian bolts flew 900 px** while their pictures reached 96 to 150. They now fly 260 px (the moon arrows
   reach 240) and fade over the last 40, and the pictures reach 210 to 230.
5. **The pictures were drawn in the guardian's scaled space** (its body is 0.72 to 0.9), so a wedge of 190 px was
   160 and the aim line ended before the player it was aimed at. Found in review, not in play. Volleys and the aim
   line are now drawn in world pixels.
6. **Bot fixes** that changed what the numbers mean: warnings read at any distance, the drawn shape read
   instead of a fixed wedge, a reaction delay, holding a distance instead of orbiting (an orbit walked into
   the bolts it had just dodged), short sidesteps as well as runs, a dash judged by where it lands, echo ghosts,
   the wall margin for pickups.

Final isolated gauntlet on this tree (two seeds, 168 fights, the bot at 0.25 s): **89% won, 1.4 hits a fight**;
cycles 2 to 6 72 of 72 won with 0.5 hits, cycles 8 to 14 80% won with 2.05 hits (at the start, 58% and 3.1). Hits a
fight at cycles 8 to 14 by place: forest 1.1, marsh 1.1, ruins 1.3, field 2.7, camp 2.9, frost 3.3. The owl was the
worst, so its first fan got its 0.75 s floor and the width cap moved to 1.2 rad; a follow-up of 24 fights each
(fresh seeds) gave camp 2.5 and frost 3.0, and after the fans were fitted under the bolt cap (seven feathers, the
young owl two fans) camp 2.7 and frost 2.4 with 75% and 92% won. A 0.12 s bot and a 0.4 s bot on the late cycles (48 fights each) won 85%
and 90%: the fights do not turn on how quick the reader is. Where the hits still come from: fans that are left a
beat late (most of the owl's happen while it is already winding up its dive) and pokes at a player who stands still.
The spread between places is a fact about the grammars, not a target. The noise is large (the same seed twice moved
1.1 to 1.4 hits a fight), so read differences under 0.3 as nothing.

What it can not say: whether any of this is fun, how a thumb on glass does against a 0.45 s warning, and how the
game feels at 120 fps on a phone. Those stay with people (and the emulator only shows what things look like).

### Bullet weaving: the fights are two-sided now

The user watched the game being played and called it one-sided: the player auto-attacks while spirits and
guardians barely answer. The ask was a shoot-'em-up drift — missiles everywhere, weave while attacking —
kept cute. The shape that was already in the tree: `scripts/actors/bullet_field.gd` holds up to 150 small
enemy bullets in packed arrays in one node (moved, hit-tested against the player's chest, stopped on
structures, faded at range end, drawn as tinted `hostile_moon_bolt.png`), `bullet_emitter.gd` shoots
spiral/aimed/ring/wave shapes into it, `guardian_streams.gd` builds each guardian's never-stopping aura plus
a heavier stream while it is not winding anything up, and ordinary casters/weavers/wisps throw fans, aimed
shots and rings off `SpiritKind.Barrage` settings. The arena wires one `Bullets` node, clears it on room
change, dissolves it when a guardian falls, and grants a few seconds of quiet on arrival. This round registered
the tests, pinned the fairness rules, tuned both layers against the bot, and documented it.

Fairness rules (`tests/test_barrages.gd`, 2581 cases, registered in `run_regression_tests.mjs` next to the
newly registered `test_bullet_field.gd`): every bullet slower than the slowest hero (keeper, 81.6 px/s, read
off the hero resources); one shot's neighbours leave 27 px at 150 px (the player's hit width plus a drawn
orb); every ring and arm set refires turned; one guardian stays under 110 in the air and a guardian plus the
casters' worst case under the field's 150; intensity 0.6 at cycle 1, 1.0 at 4, 2.0 at 17 and after, monotonic;
the stream silent while a volley or charge winds up, the aura never stopping. Each rule was broken on purpose
after passing (old 0.075 slope, camp aura 66, camp fan spread 0.1, field ring step 0, rate cap 4.0, streams
ticking in every move) and failed. Getting there changed the tree: guardian stream speeds 92–98 to 54–59
(they outran the slowest hero), camp aura 66 to 59, caster 92 to 52, weaver 84 to 46, wisp 38 to 34,
intensity slope to 1/13 so cycle 17 is exactly 2.0, and a new `GuardianStreams.MAX_RATE` of 2.0 with `stream_rate(cycle, haste)`
(the old uncapped rate hit 12x at cycle 100 and would have held the field permanently full). The old angle name in the two bullet scripts became `angle`/`first_angle`:
the hygiene check bans a certain word case-insensitively and the new files had slipped through with six hits.

Tuning, measured with the play bot (it dodges worse than a person, so its hit rate is a floor; and the bot's
numbers move with the machine's frame rate, so gaps under ~0.3 hits a minute or five points of weaving are
noise — the bands were widened for that in round 2):

- Natural first loops, twelve runs across the heroes (`tag=nat runs=12 seed=5 speed=3 loops=1`): before,
  1.42 hits a minute with 5.6 bullets in the air on average and weaving 25% of the time; after the speed cuts
  1.01 with 8.2 and 29% (slower bullets live longer, so presence rose while hits fell); after the density pass
  (weaver share 0.6 to 0.75 and interval 2.6 to 2.3, wisp 0.1 to 0.2 and 4.6 to 4.2, caster interval 2.9 to 2.7,
  the shared volley gap 1.3 to 1.1). Twelve tuning batches moved speed, density, ranges, quiets and first-shot delay; the finding that stuck is that density alone buys almost no weaving while it costs farm efficiency, so the frozen set uses short lives with fast near-rates: mob ranges down to 175/110/100, first shot at 0.15-0.5 of an interval, per-spirit quiet 0.5 s, arrival quiet 4 s. The last gap was the four chaser kinds, which never shot: stalker, ember, drifter and swarm now spit a rare slow single (share 0.2, every 6.5 s, 40 px/s, new `Source.MOB`). Frozen numbers: nat12 (frozen tree) 1.03 hits/min, peak 71, avg 11.7, weave 35.25 exact, kills 25.2/min; confirmation final_nat 0.91, peak 54, avg 12.4, weave 33.83, kills 31.7/min; mean of the two 0.97, 34.54, 28.5 — inside the round-2 bands (0.8–1.6, ≥30%, within 30% of the untouched 29.0). Same tree and command gave different numbers across runs (frame-rate dependence), which is why the bands are means.
- Guardian gauntlet, eighteen runs over all six places at cycles 2, 6 and 12 (`tag=gaunt`, same seeds):
  23 fights (some runs fought twice), 19 won (83%), 1.48 hits a fight, bullets peaking at 57, no frame spike
  over 100 ms inside a fight (the 146 ms spikes all land in the first 3 s, while the debug boost grants dozens
  of relic levels, before any fight starts). Aura and stream hits are a third of fight hits; the old tree
  without them measured 89% won at 1.4. The camp siege (3.2 hits a fight) and the ruins got a gentler stream
  interval (1.7 to 1.9, 1.25 to 1.4). Early reads were 23-24 fights, 83% won, 1.3-1.5 hits a fight,
  bullets peaking under 60. Frozen (`tag=final_gaunt` on the frozen tree): 25 fights, 24 won (96%), 1.6 hits a fight, bullets peaking at 61, all frame spikes in the first 3 s of setup, none during a fight.
- 2026-09-30 correction, gauntlet measures one fight: the battery command leaves `loops` unset, and the bot
  applied its natural one-or-two-loop draw to gauntlet runs too, so some runs fought twice (all counts above
  are dated observations of that behavior and stand). Gauntlet mode now targets exactly one loop; natural mode
  still draws from `loops=` (`tools/bot_modes.gd`, held by `tests/test_play_bot_modes.gd`). The director's
  partial gauntlet batch is reported honestly: run 10 (knight, frost, cycle 2, seed 1021) won its fight, then
  kept exploring the next cycle until the 2400 s bot cap — a harness run-cap artifact, not a game soft-lock;
  the batch was stopped and is being repeated with explicit `loops=1`. Separately, the director repeated the
  natural batch on another machine: 12 runs, 46.89 simulated minutes, 1.173 hits/min, 23.12 scattered/min,
  mean weaving 33.08%, bullet peak 52, no stuck or soft lock — an independent observation; brief 007
  reconciles the full records.
- The casters stayed the zone threat (about half the bullet hits), weavers second, chaser spit nearly harmless
  (no attributed hits in the frozen batch). Everything shoots from cycle 1: gating kinds to cycle 2 would have
  thinned the first loop, and the arrival quiet plus the per-spirit quiet already keep the first minute from
  being a wall (forest runs at a fraction of a hit a minute).

Look: `tools/shot_barrages.tscn` stages all six guardians mid-stream on their own floors plus a busy zone and
a caster fan through the real shooting code, and validates headless (32–66 bullets per guardian scene, 35 in the zone, a 5-fan mid-flight). Tints
kept: every tint measures at least 4.4:1 against every place floor's average (most over 6:1), so nothing
vanishes. No screenshots could be rendered in the implementer sandbox (all render harnesses crash headless in
the engine's Metal backend and windowed runs exit without a display); the director renders
`node scripts/godot.mjs --path apps/game res://tools/shot_barrages.tscn -- <tag> 6` on a machine with a
display. What a player sees is in `apps/docs/docs/game.md` under *Bullets*.

## Things that bit us

- **`Script.reload` is a built-in.** A static function named `reload` on a
  `class_name` script is shadowed by the engine's `GDScript.reload()`, which
  re-parses the file and resets every static variable. `Chronicle.reload()` silently
  wiped `path` and the cache. Renamed `forget_cache()`.
- **The test runner fails on any `ERROR:` in the output.** `ConfigFile.load` and the
  static `JSON.parse_string` both print one on a truncated file. Persistence that a
  test must corrupt on purpose uses `JSON.new().parse()`, which just returns a code.
- **The first cut of the atmosphere cost about 2ms a frame.** Measured with vsync off
  (a windowed A/B that hides each layer in turn): the drifting mist and the ground layers
  were free, but the light shafts (forty polygons redrawn every frame) cost about 1.2ms
  and a map-wide `GPUParticles2D` of 260 motes about 0.9ms, more than the rest of the pass
  together. Shafts are now baked once and breathe through their node's `modulate`; motes
  are a few dozen sparks drawn around the camera. The whole depth pass is now about 0.3ms
  on the dev Mac. Measure a rendering change like this before trusting that it is cheap.
- **A backgrounded windowed Godot is throttled by macOS.** A harness that takes 3s in
  the foreground ran for minutes started with `&`. Run `tools/shot_*.tscn` as an
  ordinary foreground call, and run the editor import (`--headless --editor --quit`)
  as its own call first, or a new `class_name` is unknown and the harness hangs after
  its parse error.
- **The late-game node budget is 1200 and was already at 1172.** New UI pushed Lv40 to
  1208 (`tools/count_nodes.tscn` breaks the arena's standing nodes down by branch).
  Fixes that cost nothing visible: the act card is built on demand instead of
  standing in the arena, relic chips are two nodes not three, the relic card draws
  its emblem with `Button.icon`, and tiny room decor is trimmed about 10%.
- **The right HUD's pinned width is measured, not guessed.** `tools/measure_hud.tscn`
  found 311px worst case (English, cycle 99, six-digit kills). Pinning it lower would
  have let the panel jump in a deep run.
- **Godot inherits a crashing environment unless it is stripped.** On the implementer Mac,
  `node scripts/godot.mjs --headless` (full environment) dies in the engine's Metal backend
  on any run that draws, while `pnpm godot:isolated` (eight variables plus a throwaway HOME)
  runs the same scene. Checks that invoke `godot.mjs` directly (`check:locale`'s second half,
  `check:scripts`, `game:check`) can only be verified through the isolated runner there; the
  content they check was verified that way instead.
- **A running bot pins scripts but loads resources lazily.** GDScript compiles at startup,
  so a `.gd` edit mid-run cannot affect that run; a `.tres` is read from disk on first load and
  cached. The baseline batch launched before any edit (every shooting kind unlocks within the
  first minute of run 1, long before the first tuning edit), and the final batches ran on a
  frozen tree: nothing under `apps/game/` was touched while they ran.
- **The shrine test asserts its frame stays inside the safe inset.** The roomy panel
  padding pushed it two pixels past, so dense screens use `panels/panel_tight`.
- **`user://` inventories are guarded.** Store-capture tooling lists every persistent
  save file; `chronicle.json` had to be classified in `ios-device-evidence.mjs` and
  `android-capture-persistence.mjs` before the tests would pass.
- The repo checks read `git ls-files`, which ignores untracked files and chokes on
  files deleted but not staged. To check a working tree without staging anything, copy
  `.git/index` somewhere, run `git add -A` against the copy, and point `GIT_INDEX_FILE`
  at it for the check.

- **A cut let its neighbours bleed in.** `cut_lineup.py` keyed every pixel inside a 6px pad
  around a creature, so the boots of the row above (or the edge of the creature beside it)
  came along whenever the gap was smaller than the pad. It showed as a stray dash above the
  Sage's crest, and it had quietly widened four of the six guardian sources by 6 to 12px, which
  shifts the fit and the centring. Only the creature's own box is keyed now; the spirit and
  hero sources recut byte-identical, the four guardian sources were replaced.
- **A background browser tab goes stale.** An image that finished generating kept showing
  "Thinking" in a tab that was not in front; reloading showed it. While a conversation is
  generating an image, opening that same conversation elsewhere can fail with "Could not load
  this conversation" until it finishes.
- **Running one regression test by hand needs the runner's environment.** Without
  `MOONLIT_VAULT_TEST_ROOT` the debug "every hero open" switch is on and the shrine test fails
  on "shards alone do not unlock Dancer". The editor import must also not run under a temporary
  `HOME`: it took ten minutes instead of five seconds.

- **A guardian's tempo had no ceiling.** Haste, charge speed and bolt speed grew per cycle without a
  cap, which nobody meets while the shipped game ends at cycle 8 but an endless stretch does: cycle 14
  was 3.6x haste (a 0.2 s windup) and cycle 30 seven times. Measuring TTK on a stand-still bot would
  never show it. Reading the numbers a guardian is actually fed at cycle 14 did.
- **A stand-still soak at eight times speed looks hung.** The frame-time death spiral (catch-up
  loops that spawn work faster than they clear it) makes a run that takes minutes at 4x seem to freeze
  at 8x. The tool caps at 4.
- **A finished cycle leaves the tree paused.** A test that ends a cycle leaves the cash-out panel up,
  and `get_tree().paused` stays true for the next test's arena, which then never advances. Unpause in the
  teardown.
- **A plant half a pixel inside the edge is outside it once rounded.** `RoomFlora.add_plant` rounds
  the position, so a point at y=1081.6 passed the clearance check and was stored as 1082.0, which
  fails it. The placement now judges the rounded pixel.
- **The nature sheet has sixteen colours,** so the three later places recolour it through a table
  instead of a hue rotation; every highlight was chosen by eye and the outlines stay close to the
  ground shadow they sit on.

## Verification

- `pnpm verify` — see the final report for the last run.
- `pnpm check:store-screenshots` is **expected to be red**: `apps/game/` changed, and
  the capture fingerprint hashes all of it. That is the standing rule, not a defect.
  No recapture was done and none is proposed here.
- `pnpm check:store-graphics` is **expected to be red** after the hero redraw:
  `notes/release/store-assets/iap/hero-bundle-512.png` (and the other store art that shows a
  hero) is composed from the hero sheets, so it no longer matches. It is not regenerated here;
  it belongs to the store-image redo the user plans. `tools/shot_actors.tscn` takes an `all`
  argument to photograph all six guardians and heroes on a forest floor.
- Screens were checked with `tools/shot_ui.tscn` (every screen, per locale, over a
  real forest room) and on a Galaxy Z Flip 5 (title, forest and camp arenas at 120fps).

### Device testing rule

A debug-launched run that ends **writes to the real save**: the result goes through
`Records` and the vault like any run. `force-stop` after a screenshot is too slow.
Never let a run finish on a phone. Toggle `Invuln` right after launch, or stop while
the story screens still hold the game paused. On this checkout the global ladder is
off (no `firebase.cfg`), so only the local save is affected.

## A road home: the Lantern Hollow story pass

Brief 006, still uncommitted. The user asked for a world worth caring
about; the director's answer is one integrated journey, not a lore
encyclopedia. Home is **Lantern Hollow** (등불마을); **Nari / 나리**,
the signal keeper, went to repair the beacon road and disappeared, her
last message asking the hero to keep the road home lit and the kettle
warm. The kettle pays off at the cycle-8 settlement.

What is in the tree:

- **Canon copy in five languages** (`moonlit.csv`, 557 rows): opening,
  cycles 1–9 and 12B, all three epitaphs, act titles/epigraphs, all
  five non-Warden hero voices rewritten into their relationship to the
  place, six guardian first-meetings tied to their places' habits, fork
  lines, and the beyond-the-map choice reframed as a voluntary
  expedition. English story uses Wave for the loop word. No combat,
  shop, score or unlock numbers moved.
- **Six place memories** (`scripts/gameplay/place_memory.gd`,
  `scripts/objectives/place_motif.gd`): a crafted motif beside each
  beacon clearing (dim until lit), one nonblocking discovery line on
  first restoration per run, and one chronicle entry each. The motif is
  one reused node plus its sprite; repeats and fresh runs still restore
  visibly. Fork gates hint the waiting memory on a third label line;
  guardian/omen naming is untouched.
- **Objective and endings**: pause carries the immediate objective
  (road + Wave/Depth + places count), refreshed on open. The result
  screen states the real road state and shows the settlement window —
  lit on an official win, dim on an early return, hidden on defeat —
  so it never claims Nari is home early. All buttons and the score
  arithmetic are unchanged.
- **Art**: `tools/build_place_motifs.py` bakes `places/motifs.png`
  (192x64, six terrains × dim/lit) and `places/window.png` (64x32)
  from integer coords and a fixed palette, with `--check` wired into
  `check:assets` and contract entries. Node peak measured 1133 of
  1200 on the late-game test.
- **Tests**: `tests/test_place_memories.tscn` (533 cases, registered):
  real first-beacon path, six places plus fork clues on both forks,
  fresh-run restoration, old-record persistence, no popup during any
  modal/transition/capture, all three endings plus the ungated win,
  story independence from places, five-language existence and fit, and
  budget/teardown. The once-per-run guard was mutation-checked (3
  failures with the guard removed, green restored). The story-structure
  test now pins 40 entries and 8 sections.
- **Harness**: `tools/shot_lantern_hollow.tscn` stages opening, six
  terrains dim/lit, fork clues, a resumed chronicle and all three
  endings; `validate` mode (151 cases) runs headless, `shot=` captures
  on a real display.

What bit us: the CSV was edited after the editor import, so the new
English lines did not appear until a second `--import` regenerated the
`.translation` files; the voice strip fits ~375 px at 13 px, which
forced two discovery lines shorter; the late-game arena marks ambient
first-sight entries while any test runs, so "nothing recorded" had to
be scoped to place and story ids.

## A road home, integrated: brief 008 on the current tree

Round 006's patch no longer applied after the accepted UI polish, so
brief 008 reintegrates the whole Lantern Hollow change on this baseline
and fixes the three defects the director's real-path diagnostics found.
Only `result_panel.gd` and this log conflicted; both reconciliations
keep the two independent changes.

- **Result reconciliation.** The accepted epitaph Depth caption stays
  exactly as it was (it is pinned by the result tests). The road line's
  reach therefore always reads as a Wave count — past cycle 8 the
  epitaph above already carries Depth, and the card must not say it
  twice. Score arithmetic untouched.
- **Discovery guard (defect 1).** A fresh place discovery owns the
  voice strip for three seconds. The fork, guardian-meet and moonfire
  lines that fire on the same beacon are taken at once — run
  consumption and `test_fork_travel`'s spent assertion are unchanged —
  and spoken after the interval; gate labels, the guardian banner and
  its bolts never wait. A first meet is recorded at once. A discovery
  suppressed by a modal, transition or capture is queued, never marked
  seen, and plays when the screen clears; its chronicle entry is
  recorded at restore time instead of speak time, so it is never
  silently lost. The flush pump speaks nothing past `_finish` (run
  generation), over a modal, or during capture. Other strip lines keep
  last-wins; only the deterministic same-beacon clobbers wait.
- **Nari comes home (defect 2).** Eight completed cycles resolve the
  promise out loud in all five languages: the continue choice is titled
  NARI IS HOME with the kettle in the subtitle, and the cash-out
  epitaph answers her signal, brings her home and warms the kettle.
  Cycle 9 stays a voluntary expedition for other forgotten roads.
  Earlier return and defeat keep the waiting lamp and name no rescue.
  No new save IDs; acts at 1/3/6, epilogue at 9, no-hate canon kept.
- **Road geometry (defect 3).** Measured, not guessed: the six-line
  score table needs 117 px but its box was 110, so it grew 6.5 px into
  Road. The card now gives Detail 120, Road 16, and shifts Hint/Goal/
  the buttons down inside the card. All labels fit their boxes and the
  boxes run in order on win, early, defeat, deep and large-score cards
  in all five languages.
- **Tests.** `test_place_memories` grows 533 → 951 cases: real
  `debug_light_next_beacon` fork/guardian preservation (strip readable
  same-frame and a second later, deferred line arrives, gates/banner
  immediate), all six terrains on the real path, repeat runs, modal and
  capture suppression with replay, five-language resolution copy with a
  no-rescue guard on early/defeat lines, and full-card Road geometry
  with a Depth-once assertion. Both guards were mutation-checked
  (bypassed guard: 4 preservation failures; Road moved back: every
  geometry case fails; green restored). `test_fork_travel`,
  `test_omens`, `test_story_structure`, both result tests and the
  run-choice tests pass unchanged.
- **Harness.** `shot_lantern_hollow` gains `choice_beyond`,
  `discovery_fork` and `discovery_guardian` (the last two drive the
  real arena paths) and `validate` grows 151 → 221 cases. Terrain lit
  staging really ignites its beacon after a reset — bare beacons
  instantiate lit, so the old dim shot showed a burning beacon and the
  old lit shot snapped the flag with no flare.

What bit us: the first flush pump spoke during the modal test's 0.3 s
quiet gap, so it waits a 1 s settle before delivering anything; the
third beacon also speaks moonfire in the same frame, which the
diagnostic had not named; a bare staged beacon instantiates lit.

## Not done

- Bullet-weaving pictures were staged (`tools/shot_barrages.tscn`, eight scenes) but not rendered: the
  implementer sandbox cannot draw. Render them on a machine with a display before judging tints, size and
  contrast by eye; the analytic contrast (4.4:1 minimum) is no substitute for a look.
- Store screenshots (phone, 7-inch, 10-inch, iPad) were not recaptured or uploaded.
- The result screen is restyled but its layout is the 2.1.0 one; a rank seal would be
  a good next step.
- Store imagery that shows the redrawn characters: the IAP hero images, the hero bundle image
  and the marketing screenshots still show the 2.1.0 art. They are redone together with the
  store set, on the user's word, and are not touched here.
- The title screen keeps its own atmosphere and does not get the grade. Its store
  capture checks inspect the title's own nodes, and a recapture is not planned.
