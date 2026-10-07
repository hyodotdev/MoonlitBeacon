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
  passed again when restored. The director independently repeated the guards:
  the Depth guard mutation failed 10 cases, then the exact restoration passed
  55 Depth cases and 135 layout cases, and all twenty four-screen/five-language
  renders were inspected.
- The expedition plan's "Not done" named a first-fork hint as missing; it
  exists (`VOICE_FORK_1/2` in `moonlit.csv`, spoken from `_open_fork` in
  `arena.gd` via `_say_after_discovery("fork")`, so the discovery guard takes
  it at once and speaks it after the 3 s interval while gates and the guardian
  banner stay immediate), so that line and the "Cycles N past the win" line are
  marked Done there. This log's "Not done" carries no fork-hint claim.

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

Tuning, measured with the play bot. The bot is an automated proxy: it reads warnings on a fixed
schedule, never gets bored and never misjudges a gap, and its numbers move with the machine's frame
rate, so every measurement below names its seed, loops and command, gaps under ~0.3 hits a minute or
five points of weaving are noise, and no human difficulty or fun verdict follows from any of them
(the bands were widened for that in round 2):

- Natural first loops, twelve runs across the heroes (`tag=nat runs=12 seed=5 speed=3 loops=1`): before,
  1.42 hits a minute with 5.6 bullets in the air on average and weaving 25% of the time; after the speed cuts
  1.01 with 8.2 and 29% (slower bullets live longer, so presence rose while hits fell); after the density pass
  (weaver share 0.6 to 0.75 and interval 2.6 to 2.3, wisp 0.1 to 0.2 and 4.6 to 4.2, caster interval 2.9 to 2.7,
  the shared volley gap 1.3 to 1.1). Twelve tuning batches moved speed, density, ranges, quiets and first-shot delay; the finding that stuck is that density alone buys almost no weaving while it costs farm efficiency, so the frozen set uses short lives with fast near-rates: mob ranges down to 175/110/100, first shot at 0.15-0.5 of an interval, per-spirit quiet 0.5 s, arrival quiet 4 s. The last gap was the four chaser kinds, which never shot: stalker, ember, drifter and swarm now spit a rare slow single (share 0.2, every 6.5 s, 40 px/s, new `Source.MOB`). Frozen numbers: nat12 (frozen tree) 1.03 hits/min, peak 71, avg 11.7, weave 35.25 exact, kills 25.2/min; confirmation final_nat 0.91, peak 54, avg 12.4, weave 33.83, kills 31.7/min; mean of the two 0.97, 34.54, 28.5 — inside the round-2 bands (0.8–1.6, ≥30%, within 30% of the untouched 29.0). Same tree and command gave different numbers across runs (frame-rate dependence), which is why the bands are means. These implementer batches ran in the implementer copy on the development machine; the director independently repeated the natural battery on the same development machine (see the one-fight note below).
- Guardian gauntlet, eighteen runs over all six places at cycles 2, 6 and 12 (`tag=gaunt`, same seeds) — dated observations of the loops-unset behavior, kept as history:
  23 fights (some runs fought twice), 19 won (83%), 1.48 hits a fight, bullets peaking at 57, no frame spike
  over 100 ms inside a fight (the 146 ms spikes all land in the first 3 s, while the debug boost grants dozens
  of relic levels, before any fight starts). Aura and stream hits are a third of fight hits; the old tree
  without them measured 89% won at 1.4. The camp siege (3.2 hits a fight) and the ruins got a gentler stream
  interval (1.7 to 1.9, 1.25 to 1.4). Early reads were 23-24 fights, 83% won, 1.3-1.5 hits a fight,
  bullets peaking under 60. Frozen (`tag=final_gaunt` on the frozen tree): 25 fights, 24 won (96%), 1.6 hits a fight, bullets peaking at 61, all frame spikes in the first 3 s of setup, none during a fight.
- 2026-09-30 correction, gauntlet measures one fight (accepted): the battery command left `loops` unset,
  and the bot applied its natural one-or-two-loop draw to gauntlet runs too, so some runs fought twice (all
  counts above are dated observations of that behavior and stand). Gauntlet mode now targets exactly one
  loop and fight regardless of the natural draw; natural mode still draws from `loops=`
  (`tools/bot_modes.gd`, held by `tests/test_play_bot_modes.gd`). The director's partial batch stays on
  record honestly: run 10 (knight, frost, cycle 2, seed 1021) won its fight, then kept exploring the next
  cycle until the 2400 s bot cap — a harness run-cap artifact, not a game soft-lock; that partial batch was
  stopped and is neither a green batch nor soft-lock proof. The explicit one-fight repeat supersedes its
  status: `director_gaunt_one runs=18 seed=11 speed=3 loops=1 gauntlet=1 guardians=0,1,2,3,4,5 starts=2,6,12`
  gave 18 runs and 18 fights, 16 won (88.9%), mean 1.17 hits a fight, bullet peak 62, zero stuck or soft
  lock; cycles 2/6/12 and the six places were paired cyclically, not as a full Cartesian matrix, and the
  machine recorded 98 setup spikes all before 3.4 s and none after. A mode diagnostic on the corrected rule
  (`director_mode runs=4 seed=11 speed=3 loops=2 gauntlet=1 guardians=3 starts=2`) settled all four runs
  after one fight in 41.6 s wall time. Separately, the director repeated the natural battery on the same
  development machine: 12 runs, 46.89 simulated minutes, 1.173 hits/min, 23.12 scattered/min, mean weaving
  33.08%, bullet peak 52, no pickup stuck or soft lock — inside the frozen bands; guardian confirmation stays
  separate, and no human difficulty or fun verdict follows. Brief 007 reconciles the release records
  independently (it owns the release plan, checklist, expedition plan and store copy, not this log).
- The casters stayed the zone threat (about half the bullet hits), weavers second, chaser spit nearly harmless
  (no attributed hits in the frozen batch). Everything shoots from cycle 1: gating kinds to cycle 2 would have
  thinned the first loop, and the arrival quiet plus the per-spirit quiet already keep the first minute from
  being a wall (forest runs at a fraction of a hit a minute).

Look: `tools/shot_barrages.tscn` stages all six guardians mid-stream on their own floors plus a busy zone and
a caster fan through the real shooting code, and validates headless (32–66 bullets per guardian scene, 35 in the zone, a 5-fan mid-flight). The
analytic tint check measured at least 4.4:1 against every place floor's average (most over 6:1); an average
does not prove a tint never vanishes on every composite, so that number is kept as a dated analytic fact, not
as a visibility proof. No screenshots could be rendered in the implementer sandbox (all render harnesses crash
headless in the engine's Metal backend and windowed runs exit without a display) — that limitation is dated;
the director rendered and visually inspected all eight barrage stages on a machine with a display. The
inspected visual scope is exactly this: the eight barrage stages, the six terrain composites
(`shot_rooms.tscn -- director-baseline`, inspected at original resolution), and thirty map corner/center views
(five per terrain, seed 20260929, no seam, edge band or missing terrain layer confirmed). Those are harness
views, not movement or device proof. What a player sees is in `apps/docs/docs/game.md` under *Bullets*.

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

- Registry recount, reproduced in this copy: `apps/game/tools/run_regression_tests.mjs` holds 50
  entries — two import steps (`Reimport resources`, `Confirm resource import`) plus 48 game checks.
  Every registry count in this log is game checks unless import steps are named with it.
- Reproduced in this copy, 2026-09-30: `pnpm check:hygiene` passes (repo rules ok),
  `pnpm check:store-graphics` passes (tracked art deterministic, 8 IAP artworks), `pnpm check:assets`
  passes. The older note that store graphics were expected red after the hero redraw is dated history
  (the hero art mismatch at redraw time); the current reproducible result is the pass above.
  `tools/shot_actors.tscn` takes an `all` argument to photograph all six guardians and heroes on a
  forest floor.
- This record-only round ran no full `pnpm test:game`, `pnpm verify`, build, capture or device step.
  Final full-root verification and the Android build are still pending; that evidence lives in the
  director continuity and the PR body, not here, and this log manufactures none of it.
- Director root evidence already on record (cited, not re-run here): after the story, title, spatial
  and skill acceptances the root registry passed all 46 game checks plus the two import steps (log
  `builds/verify/director-story-accepted-game.log`); import, all 118 scripts and startup passed
  independently. Caption correction 010b and the docs audit were accepted after it; the store/record
  reconciliation (007) runs independently; final full verification follows them.
- `pnpm check:store-screenshots` is **expected to be red**: `apps/game/` changed, and
  the capture fingerprint hashes all of it. That is the standing rule, not a defect.
  No recapture was done, none is proposed here, and no store operation is authorized in this continuation.
- Screens were checked with `tools/shot_ui.tscn` (every screen, per locale, over a
  real forest room) and on a Galaxy Z Flip 5 (title, forest and camp arenas at 120fps) — dated
  implementer-era observations; the director's own harness renders are named where they supersede them
  (barrage stages, terrain composites, corner/center views, story stages, rim and outcome cards above).

### Device testing rule

A debug-launched run that ends **writes to the real save**: the result goes through
`Records` and the vault like any run. `force-stop` after a screenshot is too slow.
Never let a run finish on a phone. Toggle `Invuln` right after launch, or stop while
the story screens still hold the game paused. On this checkout the global ladder is
off (no `firebase.cfg`), so only the local save is affected.

## A road home: the Lantern Hollow story pass

Brief 006, round 1 (dated history; not accepted, superseded by the brief 008 integration below).
The user asked for a world worth caring
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
be scoped to place and story ids. Round 1 was not accepted: the director's
real-path probe failed 2/536 (the first fork and the classic third beacon
overwrite discovery), the Road rectangle probe failed 1/535 (a 6.5 px score
overlap), and the Nari ending needed an explicit resolution; the 533 place
cases and 151 staging cases above are the dated round-1 counts.

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

Director independent evidence (accepted, same development machine): place memories 951, layout 135,
Depth 55, run choice 331, story structure 695 and scene staging validate 221 all passed. Disabling the
actual discovery guard failed four same-frame/one-second fork and third-guardian preservation cases;
restoring the exact production bytes returned 951 pass. All new story stages were generated in five
languages; personally inspected were the opening, both real-path discovery collision stages, the official
continue/cash-out choice and win/early-exit/defeat for each language, plus all six dim/lit terrain
composites. Fast desktop rendering exposed frame-count-only capture before the result fade finished, so
brief 010 requires an elapsed-time settle and final-alpha assertions — fading images are not final cards.

A later different-seed diagnostic is not the calibration: `director_story_nat runs=12 seed=11 speed=3
loops=2` measured 61.05 simulated minutes, 0.753 hits/min, 46.47 scattered/min, 26.08 percent mean
weaving, bullet peak 73, six guardian fights, zero stuck or soft lock. It started before arena's final
deferred-strip cleanup (combat did not change) and is not an exact-final-source run; the frozen seed-5
measurement remains the comparison. A separate isolated-save desktop diagnostic observed the Promise act,
kettle/road dialogue, an actual first-beacon ribbon discovery, joystick movement and the road-home pause
objective with debug shield and beacon controls — not mobile verification, not a full human eight-cycle
ending, and not a human difficulty verdict.

## Readable at the edge and in Japanese: brief 010 on the current tree

Two visual defects from a different review angle, both measured first.
A fork gate on the top rim carried its three-line destination above
itself at y=-64..-12 while its compass hid (the gate was visible), so
the choice was unreadable with no arrow either. The Japanese quit title
is 266 px at font 26 — wider than the 260 px card, whose Label spanned
the whole viewport instead of the card.

- **Gate captions.** `moon_gate.gd` keeps the existing label and fonts
  and nudges the caption the smallest distance that lands it fully
  inside the usable screen (safe rect, below the 126 px top HUD the
  compass also avoids) while its gate is on screen; off-screen gates
  keep the plain above spot so the caption leaves with the gate and the
  compass carries the choice. The usable shift alone crossed the hero's
  face under a top-rim gate, so a wired player clears next: the caption
  moves to the nearest usable spot outside the hero's real sprite bounds
  plus 6 px, with 1 px separation past that. The arena's gate-naming
  path wires the player into each gate it names. The label stays
  tap-through.
- **Quit card.** The card grows 260 → 300 px and the title is fitted to
  it at 276 px (12 px padding each side), so all five titles
  (196/177/266/181/181 px) fit on one line. Cancel keeps default focus;
  both buttons keep their behaviors.
- **Tests.** New registered `test_gate_captions` (71 cases: four rims
  through the real arena camera and compass with hero clearance, all six
  heroes' footprints at the top placement, real-fork player wiring,
  plain gate, close reset) and `test_quit_layout` (24 cases:
  five-language fit, Cancel focus and wiring). All guards were
  mutation-checked (unshifted label: top rim fails at y=-64 exactly as
  diagnosed, left/right rims clip the HUD; clearance alone disabled:
  round-1 placement fails 9 hero cases; 260 px card: all five padding
  cases fail; green restored).
- **Harness.** `shot_lantern_hollow` `_snap` now settles a minimum 0.6
  real seconds before its post-draw sync, so fast-desktop captures no
  longer beat the result card's 0.5 s fade; endings additionally wait
  for final alpha and stamp scale and fail the capture otherwise. The
  guardian discovery pre-wait drops 0.8 → 0.3 s so its banner still
  holds at the shutter. New `gate_rim_*` stages (real arena, settled
  past the 1.2 s gate fade) wire the player like production and finish
  the tutorial ladder plus clear its banner, so the shot judges a quiet
  gate and hero; `validate` grows 221 → 248 cases.

What bit us: the gate label's live height is 48 px with three lines,
not the 39 px it is created with, so guard and test both read the live
size; a caption placed exactly touching the cleared hero rect still
fails `intersects` through float dust in the screen round-trip, so
production separates one extra pixel past the margin; `frame_post_draw`
never fires headless, so captures only validate in the sandbox and
render on a real display.

The 71 gate, 24 quit and 248 staging counts above are the implementer's measured counts and stand.
Round 1 was not accepted: the upper-rim real-camera caption at y=132..184 crossed the actual hero at
x=404 (head/body around y=146..180), obscuring the caption's second line, and the bottom-rim diagnostic
held the initial tutorial banner over the third line — forced early staging, not natural-route proof, so
the rim diagnostic went quiet. Correction 010b is accepted. The director independently passed 71 gate
cases, 248 scene-staging cases, 951 place cases and 50 fork cases; disabling only the actual hero
clearance failed nine assertions, and exact restoration passed 71 (SHA-256
14785feb443ed804629c32efb1b86c4f615e10e2f1c7360fdfbaebbfad6a40a0). Personally inspected at original
resolution: all twenty rim pictures, fifteen fully settled win/escape/defeat cards, ten discovery
collisions and five quit cards across five locales. These are diagnostic desktop stages — debug controls
were visible on the rim/discovery stages — not marketing images and not device proof.

## Six weapons, a faster pulse, and a rewarding sound: brief 017 (2026-09-30)

One combat-feel pass. The six heroes ran one shared slash plus one shared
volley with decoration-only profiles; now each hero fires a real primary
with its own hit shape and cadence on the same two arena clocks, traversal
is ~17% quicker, and combat audio is original synthesized loops and cues.

- **Weapons.** New `scripts/gameplay/hero_weapons.gd` holds the per-profile
  spec table both clocks read in `_base_stats` (so `_recompute` restores
  it after a hit exactly like speed and damage). Warden wide sword cone
  (46px/130°/0.50s); Dancer alternating twin cuts (38px/85°/0.30s,
  ±28° sides); Eclipse timed orbit ring (64px band, 0.62s, safe hole at
  55%); Sage rifle (300px, pierce 6, 1.20s, whole budget on one bolt);
  Keeper shotgun (125px, five even-split pellets, 30° fan, 1.0s); Knight
  cannon (150px/s shell, 2.3s, 48px delayed blast on hit or burnout).
  Each kit keeps a reduced sidearm on the other clock (~1/3 output, also
  profile-parameterized) so every relic family, core, resonance, and
  evolution keeps working for every hero with no second free full weapon.
  Rate floors and overflow-to-damage cover both clocks as before.
- **Traversal.** `DEFAULT_SPEED` 96 → 112, dash cooldown 1.15 → 0.95s,
  accel 900 → 1100, friction 1200 → 1500. Hero speed/dash multipliers,
  enemy windups, story typing, and modal timers untouched. Dancer's
  localized speed marker moved +43.75% → +41.07% in all five locales.
- **Visuals.** Bounded drawn layer, no new sheets: `WeaponRig` (held
  weapon per hero plus cut/muzzle flashes, ≤0.22s, self-clearing) and
  `ScytheOrbit` (twin circling blades plus sweep pulse) as `Player`
  children, cannon recoil as one short killed-by-next-shot tween, cannon
  splash as one blast flash. Hero and beacon copy rewritten in all five
  locales (no ASCII commas); beacon choices now say safe-immediate-no-
  bonus versus defend-within-88px-for-6.5s.
- **Audio.** New `tools/build_combat_audio.py` bakes 13 original cues
  (fixed-seed LCG noise, `--check` registered in `check:assets`): a
  14.55s driving arena loop and a 17.14s escalating guardian loop on one
  shared motif (whole bars, edge fades, boundary step exactly 0.0, peak
  0.62), six weapon voices, impact/kill/level/core/overcharge cues.
  Three bounded players (polyphony 3/4/2) plus per-voice rate floors;
  projectiles report hits through `moonlit_combat_sfx` instead of
  carrying audio nodes; combat ducks under dialogue/choices; title theme
  and UI sounds kept. Old arena/guardian OGGs stay on disk because
  course lessons reference them; the manifest says so.
- **Tests.** New registered `test_hero_weapons` (183 cases: six hit
  shapes with intentional misses on the live arena, twin alternation,
  rifle pierce, even pellet split, delayed blast, orbit hole, invalid
  and freed targets, both rate floors, reset/growth, price/tier
  independence, result/VFX cleanup, deterministic same-target comparison —
  Warden 135, others 100–102 over 6s, i.e. 0.74–0.76x — and a grouped
  tradeoff comparison) and `test_combat_audio` (88 cases: waveform
  headroom/silence/boundary, per-hero wiring, impact/kill/reward
  handlers, loop config, ducking, bus mutes, release cleanup).
  `test_hero_combat_profiles` keeps its resource/decoration/vfx-tier
  contract; its power-0 budget math is revised to the spec-aware formula
  ([3,3,41,16,4,24], melee side primary ≥12 vs sidearm ≤10) with the old
  decoration-only assertions intact. Both new tests were mutation-checked
  (warden reach 46→40 fails two; twin cue swapped fails two; green
  restored).
- **Harness.** New `tools/shot_weapons.tscn`: real arena per hero at
  early and strong (fixed 8-relic + 5-core) builds, live spirit in the
  weapon's pocket, capture only after a production hit lands with live
  effects; four-frame motion strips; beacon panel in five locales × both
  core states. `validate=1` runs the 46 observations headless (green in
  the sandbox); PNGs render on a real display. Audio audition:
  `build_combat_audio.py --audition builds/audio/audition.wav`.

What bit us: physics runs 30 ticks a second, so the first comparison
drove 12 melee-seconds against 6 volley-seconds (Warden read 242, not
132) until both clocks advanced 1/30 per tick; Godot 4.7 rejects an
inner-enum static return type, so `primary_side` returns int; shots leave
the muzzle 20px above the aim point, so close-range test geometry must
follow the firing ray and bodies sit 6px above their roots, which breaks
fan symmetry enough that lane-test distances are hand-derived; swapping
the BGM stream without stopping first orphans looped playback, and the
release-then-quit race in the audio test needs the 0.25s settle the
`AudioFlush` docs describe.

The 183 weapon, 88 audio, 840 profile, and 46 harness counts above are
the implementer's measured counts and stand. Screenshots were staged and
headless-validated only; no PNG was rendered in the sandbox. Bot smoke,
guardian fights, and the full suite ran separately; see the report.
Late in the round the suite replica caught three of ours: the Warden
sidearm cadence returned to 1.15 for the Lv40 fire-rate stage, terrain
Keeper pins moved to the new bases, and Keeper copy was updated in the
shrine test plus the preview panel's pinned table. Shrine en/ja safe
margins fail identically on the untouched baseline (sandbox font
metrics), so they were left alone.

## Runtime boundaries and six-track combat rotation: brief 018 (2026-09-30)

Corrections to brief 017 plus a music rotation: three arena tracks and three
faster guardian tracks on a no-repeat bag (region/entry draw, guardian draw,
arena return), QOA loop endpoints in decoded samples, a separate growth
voice with primary-loud/sidearm-quiet mapping, guided lane/budget agreement,
a beacon defense ring with unit-free copy, weapon-first hero descriptions,
a repaired capture harness, the rig moved to hand height with six distinct
silhouettes, and a Knight rebalance (cannon 4.0/2.10s, chop 0.55) that holds
the 102 total at a 65/35 primary split.

- **Guided cloning.** `guided_lane_damages` sized its split by power volley
  while the arena fired `max(hero lanes, power volley)`; extra lanes fell
  back to the anchor's whole damage — a power-0 Keeper dealt 205 (5×41).
  The split now takes the live lane count; the arena passes `_ranged_lanes`.
- **Shrine margins, corrected record.** The 8 en/ja failures are a round-1
  desc-length regression, not baseline: HEAD CSV fails 0, round-1 CSV fails
  the identical 8, round-2 reorder fails the identical 8. The round-1
  "untouched baseline" note was a stale-import artifact (`.translation`
  files are gitignored, so a stash without reimport keeps the long strings).
  Layout left alone: resizing the shrine risks the capture-gate rects.
- **Music determinism.** Track choice uses a dedicated RNG; bot seeds and
  gameplay `randf` are untouched by music. Two same-config natural batches
  (seed 17): 2568 kills, 0.73 hits/min; knight 0 spikes in both.
- **Sandbox notes.** Bare `godot --headless` segfaults in Metal before game
  code, so `test:game` as shipped cannot run here; all 50 checks ran via
  `pnpm godot:isolated`. Display captures need the director's real display;
  the harness validates headless (`validate=1`).

## Preserve primary weapon sound on simultaneous clocks: brief 019 (2026-09-30)

Corrections to brief 018, all confirmed against the round-2 source by the
director's own probes. The primary weapon owns its voice and the sidearm owns
a second capped voice, so a same-tick backup can never swallow the signature
cue; the music bag rolls on at the end of each whole track inside one mode,
read off the audio clock so pause, time scale and release cannot strand it;
gun heroes fire from the muzzle with a side-hand seat on vertical aims while
melee heroes keep the candle backup; the capture harness stages four real
body facings; hero descriptions drop the flat cross-hero damage percent and
fit the shrine in all five locales; GrowthSfx joins the release path; the two
new audio/weapon tests and the harness refuse to run without the isolated
test root; and the cannon budget is measured live (real Knight, 34/40
spirits, max-power growth, repeated volleys: ~14 visits/step against 256).

- **Shared-gate swallow.** The melee call ran first in `_process` and armed
  the one 70 ms gate, so the later primary call died silently — Knight heard
  sword at -15 dB instead of cannon. Two voices with two gaps; both director
  probes now exit 0.
- **Release race.** `music_player.release()` no-ops when no frame has passed
  since `play()`, so a same-frame cue survived release even once listed.
  `_release_audio` now stops and drops every stream explicitly after the
  release call, and the test asserts all eight players silent and streamless.
- **Wrap, not countdown.** `get_playback_position()` wraps 12.0 → 0.0 on the
  loop boundary (probed), so a 2.0-margin wrap detector rolls the bag with no
  timers, no nodes, and no time-scale skew. Seeks only ever jump forward, so
  the detector cannot false-fire on a seek.
- **Side-hand two-pass aim.** Shifting the grip 10px sideways without
  re-aiming would fire parallel past the mark; the second pass aims through
  the shifted hand so muzzle, flash, cast cue and target share one line.
- **Shrine is a copy fit.** en Keeper/Sage wrapped to 3 lines (frame 365 vs
  352 budget). Dropping the damage percent fixed ja; en needed "fan"/"line"
  trimmed and the Sage tail reordered — both pinned, both deterministic.
- **Billion-pierce staging lies about nodes.** Stress pierce lets each shell
  strike half the roster, and the impact VFX alone spikes past 1200. The
  Knight sample keeps its recomputed real pierce; work lands at ~14/step and
  the 1203-crest worst case is reported with its cause, not optimized.
- **`set()` bounces typed arrays.** Assigning an untyped Array to
  `Array[Relic] _taken` via `set()` silently keeps the old one; mutate the
  live array in place instead.

## Keep the late cannon budget and capture claims: brief 020 (2026-09-30)

Narrow corrections to round 3. The Knight sample holds the 1200-node budget
again via a minimal production tweak (same-tick strike pops share one flash
per shell; detonation still flashes big): 1201 -> 1186-1187 across three
samples, work ~14/step against 256, with a revert-catching negative control.
The capture harness stages controlled stationary targets (spawns suppressed,
one still live mark, quiet-room top-up) and asserts the anchored primary aim
per strip instead of inferring it from body facing; beacon captures wait for
the fade to settle and choices to arm. The sequential-runner missile-loop
failure was shared-vault contamination (an earlier shrine select leaves
Keeper equipped): origins are now staged explicitly for all six profiles
with independent seat/shift/side literals, and the perf defaults pin Warden
after the same contamination tripped the Lv20 cadence assert.

- **Tautological expectations.** The first origin rewrite derived expected
  muzzles from `muzzle_origin()` itself and passed with guns forced to the
  candle. My own mutant caught it; literals now pin both sides.
- **Suppression starves the anchor.** Clearing wild spirits removed the
  backup targets that kept the 6s primary poll fed; one-shot kills left the
  wait quiet (4 misses). Top-up resummon when the room empties fixed it.
- **Staged kills paused later stages.** A kill levels, the level opens the
  relic draft, the draft pauses with no cancel path, and the pause outlives
  the freed arena — every later stage staged frozen (29 fails, timing-flaky
  with the kill/draft/teardown race). Staging now calls the sanctioned
  `debug_freeze_capture_progress`, with unpause insurance at setup and
  teardown. Firing, damage, HP, and perish stay production.
- **Outer fan lanes cross the axis by design.** At dancer's close pocket the
  muzzle sits ~30° off the compass axis; the symmetric ±16° fan then crosses
  45° while centered on the mark. The volley center (fan cancels) now
  carries the lane aim; a negated-average mutant fails exactly it.
- **`pnpm test:game` cannot run in-sandbox.** The two `--editor` import
  steps fail before any test (editor-settings save blocked, no audio
  hardware, no adb). A shared-HOME 50-check replica in runner order went
  50/50 green; the director runs the original outside.

## Finish the combat reference and capture evidence: brief 021 (2026-09-30)

Reference-only round plus one harness assertion swap; production,
tests, balance, and other tools byte-identical. The combat overview no
longer says power 3 always homes: normal fire stays straight at every
power, homing needs evolved Starfall or Awakening at power 3+, and the
missile table is labeled the baseline core curve with native floors
(Keeper five pellets, Dancer/Eclipse two at power 0). Thresholds and
historical figures unchanged.

- **Survivors are not a volley.** The director's windowed run failed
  `dancer early right volley center flies right`: averaging surviving
  arrows cannot reconstruct a volley (hits eat the center lane, even
  volleys alternate the unpaired side). Each lane is now judged alone
  against its own origin-to-mark line within the hero's live fan plus
  6° slack — muzzle for gun primaries, candle for melee backups, via
  the same `muzzle_origin` production launches from. Rig-aim, body,
  hit, primary-effect, recoil, strip, and beacon evidence untouched.
- **Negative control reverses flight, not aim.** Negating the launch
  direction fails `lane flies its mark` on gun and candle lanes while
  rig aim still passes and dancer's melee hits still land; restored
  byte-identical (sha256 matched). Full six-hero headless validate
  green (730 checks); windowed rendering stays the director's.
- **Hygiene now sees staged files.** `check-hygiene` scans `git
  ls-files`, so the round-5 staging surfaced a pre-existing local
  oscillator variable name in `build_combat_audio.py` (round-4
  untracked: green). Out of that round's change surface; reported,
  not fixed.

## Remove the staged generator's forbidden token: brief 022 (2026-09-30)

Small naming correction plus one capture-tool sampling fix; production,
tests, balance, music, and approved evidence unchanged. The staged audio
generator's local oscillator variable is renamed to `angle`, and the
brief-021 log entry no longer quotes the old name. Synthesis expression,
sample parameters, RNG calls, and call order identical; all seventeen
combat WAVs byte-identical and `check:hygiene` green.

- **Per-frame primary anchor.** The director's windowed round-5 harness
  failed `dancer strong left primary shows for the strip` (1/718): the
  0.25s poll sampled cooldown gaps while the slash showed on frames
  between polls (frame observer: 1/119 with a rising per-frame
  counter). The wait now inspects every process frame until the same
  bounded six-second wall deadline, latching only a primary observed
  live that frame. Six repeated dancer strong-left stages and the full
  six-hero headless validate all green; the windowed repeat stays the
  director's. This is a new sampling defect, distinct from the fixed
  lane-direction average and the pause leak.

## Reconcile the Keeper copy regression: brief 023 (2026-10-01)

Integration-test-only fix for the staged `test:play-release-package` gate
(`keeper preview localized copy contract is incomplete`). The five
`expected_hero_copy` description literals in
`scripts/lib/store-graphics-boundary.test.mjs` still pinned the old
flat-damage wording; they now pin the accepted lantern-shotgun wording
(hearts/move/dash/openings retained, no flat stat superiority), matching
accepted `STORE_CAPTURE_HERO_COPY` and `HERO_KEEPER_DESC` in all five
locales. Names, states, source keys, literal independence, and all
corruption/swap/both-wrong negative cases unchanged; no production,
capture-generator, catalog, or locked-value change. `node --test
scripts/lib/store-graphics-boundary.test.mjs` 21/21 green,
`pnpm test:play-release-package` 208/208 green, `pnpm check:hygiene`
green. Old literals verified to fail the gate before the fix was
restored.

## Stabilize the late cannon node budget: brief 024 (2026-10-01)

The fresh `pnpm verify` failure (Knight Lv40 node_peak=1202 over the
unchanged 1200 cap) is a tick-alignment flake in impact-pop transient
nodes: split-tick strikes can produce eight extra two-node pops in the
unchanged live stress stage. Staged
knight shells are pierce 2 (measured `pierce=2, blast=48, volley=8`):
each shell strikes twice, and brief 020's same-tick sharing collapses
the pair to one pop only when both strikes land on the same physics
tick. Wall-clock warmup/sample timing decides the alignment, so a
volley costs 16 pops (32 nodes, peak ~1186) when strikes share a tick
and 24 pops (48 nodes, peak 1202-1203) when they split. A temporary
probe (deleted after use) caught both: 12 samples at 1186-1187 with
maxpops=16, one at 1202 and one at 1203 with maxpops=24, everything
else identical (8 fading shells, 40 spirits, 0 hostile/embers).

Minimal production fix in `moon_arrow.gd` `_strike`: a blast shell
that exhausts its pierce on a strike skips the small strike pop,
because `_finish` detonates later in the same tick and the 2.4x
detonation flash lands within a body radius of the mark, so the skipped
pop hides under the big flash for its 0.16s life by construction. Whether
that reads identically on screen is the director's rendering check; no
visual pass is claimed here.
Same-tick behavior is unchanged (the pair already shared one pop);
split-tick pairs now also cost one strike pop plus the detonation, so
every shell costs exactly two pops regardless of alignment. Damage,
pierce, timing, 48px geometry, detonation count and all other heroes'
pops are untouched; no cap, count, budget or seed changed.

Measured, all isolated: original test passes four consecutive runs at
node_peak 1186 (71 -> 73 cases; detonations=16, spirit_peak=40,
candidate work well inside 256/step); eight probe samples peak
1186-1188 with maxpops=16 every time (residual ±2 is starfall-missile
node presence). New deterministic fixture pins the mechanism
(pierce-2 shell, strikes on two physics ticks, exactly 2 pops, both
strikes still deal 22); with the fix disabled it fails 2-vs-3 and
nothing else. `test_hero_combat_profiles` (1128), missile loop (244),
missile progression, game smoke, script compile (122) and hygiene all
green; `check:store-screenshots` red as expected after touching
`apps/game` (no recapture).

Limitations, explicit: headroom is 12-14 nodes, and the gate still
samples wall-clock windows, so scheduling decides which alignments
get observed — the fix works by making every alignment cost the
same, not by widening the margin. Staged pierce is deterministically
2; live relic stacking beyond that reintroduces up to one extra
strike pop per shell per additional split-tick strike, but live play
is not gated and each extra pop is two nodes for 0.16s.

- **Peak composition, not just peak.** The brief's numbers alone
  (1202 vs 1187) could not name the culprit; per-frame node-class
  counts (live/fading arrows, pops, missiles, spirits) showed the
  +16 is exactly eight extra two-node pops and nothing else.
- **Sharing must cover the worst alignment, not the typical one.**
  Brief 020's same-tick sharing fixed the common case and measured
  green three times, but the split-tick case it left behind failed
  two of fourteen pre-fix samples here. The new fixture forces the split across a
  real physics frame instead of hoping the live sample catches it.

## Align capture copy pins with the current Keeper: brief 025 (2026-10-01)

Capture-input attestation fix only; no production change. The director
reported that the real Pixel_10 capture passed title and shrine, then
failed in `scripts/lib/capture-run-state.mjs:1754` with `Hero-preview
live description differs from current-locale Keeper copy`: the live
English description is the renewed lantern-shotgun wording
(`HERO_KEEPER_DESC`, `description_copy_valid` true, locale en, ready
true) while the independent `HERO_PREVIEW_COPY_BY_GAME_LOCALE` pins and
the `HERO_PREVIEW_COPY` test fixture retained the pre-renewal
damage-bonus wording in all five locales. Confirmed in this copy by
reading the pins against `apps/game/localization/moonlit.csv` row 283
(the renewed five-language `HERO_KEEPER_DESC`), `test_shrine_portraits.gd`,
and the accepted `expected_hero_copy` in
`store-graphics-boundary.test.mjs`; no device run was made from here.

The five validator pins and the five fixture literals now pin the
current copy exactly (lantern shotgun lead, hearts/move/dash/openings,
no flat damage percent). Source keys, state keys, names, states, and
every strict text/source/locale/readiness assertion are unchanged, as
are the canonical atomic publication rules. A new regression,
`hero-preview Keeper proof built from moonlit.csv passes every locale
pin`, builds the five-locale hero-preview proof (name, locked-state,
description) from the live CSV rows instead of the duplicated fixture,
so a stale-but-self-consistent pin/fixture pair can no longer pass
silently; it also pins the two negative controls (pre-renewal
damage-bonus wording fails, another locale's current copy fails). All
pre-existing wrong-copy/source/locale rejection cases are preserved.

Measured in this copy: `node --test
scripts/lib/capture-run-state.test.mjs
scripts/lib/store-graphics-boundary.test.mjs` 61/61 green (40 + 21).
Negative control demonstrated both ways: one stale pin fails the new
CSV regression, and a stale-consistent pin/fixture pair passes the old
hero-preview test while failing the new one; both were restored
exactly and the suite re-ran green. `git diff --name-only` lists only
the two `scripts/lib` files plus this log — `apps/game`, the CSV,
scenes, art, audio, export presets, and prices are byte-identical, so
production runtime bytes are unchanged. Capture-input freshness is
separate and is not preserved: `scripts/capture-store-screenshots.mjs`
lists `scripts/lib/capture-run-state.mjs` in CAPTURE_INPUTS, and
`apps/game/tools/build_store_graphics.py` lists the same file in its
capture contract, so the old capture-input attestations are stale and
the director must rebuild that attestation before the real capture
retry; the old capture proof does not still pass. (Correction, brief
025b: the earlier wording claimed `pnpm check:store-screenshots` was
unaffected by this change; that was wrong as stated.)

Authorization versus completion: the user requested merge on good
review, fresh store screenshots including changed title imagery, and
direct deployment. None of that is done here: no capture was run, no
screenshot recaptured or uploaded, no store or network action taken,
nothing merged or deployed. Attestation rebuild and the real
five-locale phone capture retry stay with the director.

## Align the consumer's Chronicle persistence contract: brief 026 (2026-10-01)

Tools-file correction only; no production change. The director
reported `pnpm store:screenshots:play` failing at
`apps/game/tools/build_store_graphics.py:2864` with `Pixel phone
permanent file list differs from the fixed contract`, after genuine
five-locale phone (40 PNGs), seven-inch (30) and ten-inch (30)
captures whose reports carry the full 20-entry
`persistent_data_files` list with byte-exact before/restored
equality, including removal of capture-created Chronicle state. Root
cause confirmed in this copy: the accepted Node producer
`ANDROID_CAPTURE_PERSISTENT_FILES`
(`scripts/lib/android-capture-persistence.mjs`, mirrored as
`IOS_CODE_PERSISTENT_FILES` in
`scripts/lib/ios-device-evidence.mjs`) lists 20 ordered entries with
`chronicle.json` and `chronicle.json.tmp` at indices 3-4, while the
Python consumer tuple at line 517 (aliased as
`IOS_CAPTURE_PERSISTENT_FILES`) still held the older 18. Reproduced
exactly here: a genuine 20-entry report is rejected by
`_validate_android_capture_persistence` with the reported message.
Every existing boundary fixture was built from the consumer's own
tuple, so the drift passed all 32 acceptance tests silently.

The consumer tuple now lists the same 20 entries in the same order
(two added lines; the iOS alias follows). All strict checks are
untouched: exact ordered file-list equality, exact hash-map sets,
SHA-256 shape, before/restored equality, byte-exact restore flags,
the settings.cfg proof, the anchor transcript cross-check, and the
signature gate. A new cross-language regression in the registered
`store-graphics-boundary.test.mjs` suite, `Python capture
persistence contract matches the Node producer including Chronicle
state`, loads the actual Node producer lists and the actual Python
consumer, asserts complete ordered equality for Android and iOS
plus explicit Chronicle positions, then validates a genuine
producer-driven fixture (settings mutation, capture-created
`chronicle.json` removed on restore, `chronicle.json.tmp`
round-tripped) through the real
`_validate_android_capture_persistence` including anchor and
signature descriptor, with seven Android negative controls (each
Chronicle file dropped from the list, an extra file, each
Chronicle map entry dropped, a Chronicle restored hash changed, a
capture-created Chronicle kept) and two iOS negative controls
(Chronicle dropped from the iOS file list and before map) through
the real `_validate_ios_capture_persistence`. All pre-existing
signature, settings, path, and missing/extra-file rejection cases
are preserved.

Measured in this copy: the new regression fails on the uncorrected
tree with `missing=['chronicle.json', 'chronicle.json.tmp']`;
after the fix, `node --test
scripts/lib/store-graphics-boundary.test.mjs
scripts/lib/android-capture-persistence.test.mjs` is 33/33 green,
and the full registered `pnpm test:play-release-package` is
210/210 green. Each stale-list negative control was demonstrated:
removing either Chronicle entry from the Python tuple fails the
new regression (`missing=['chronicle.json']` /
`missing=['chronicle.json.tmp']`); both were restored exactly and
the suites re-ran green. Each committed negative was attributed to
its intended strict gate (file list, hash map, before/restored,
iOS file list, iOS hash). `git diff --name-only` lists only the
generator, the boundary suite, and this log — no game runtime,
CSV, art, audio, export preset, version, producer, or signing
change, and no capture proof touched, so production runtime bytes
and pixels are unchanged (`tools/` is excluded from
`_runtime_fingerprint`). Capture freshness splits by device: the
phone capture becomes stale, because the generator is a pinned
phone capture input (phone `CAPTURE_INPUTS` and the generator's
own phone contract). The completed seven-/ten-inch captures do
not become stale from this fix: the generator appears in neither
the tablet capture script's source/build inputs nor the
`ANDROID_DEVICE_CAPTURE_SOURCE_INPUTS` tuple, and production
runtime excludes `tools/` — so the tablet reports remain current
if their unchanged strict source/build/runtime/persistence checks
pass. Those post-acceptance tablet validations have not happened
here, and no capture or submission completion is claimed.

Authorization versus completion: the user requested merge on good
review, fresh store screenshots, and direct deployment. None of
that is done here: no capture was run, no screenshot recaptured or
uploaded, no store or network action taken, nothing merged or
deployed. Phone attestation rebuild and the authorized phone
capture retry stay with the director; the tablet reports stand on
their unchanged checks without implying a tablet recapture.

## Preserve the full phone combat viewport: brief 027 (2026-10-01)

Storefront framing correction only; no production change. The
director examined the actual final Korean composites against the
clean 2424×1080 phone originals and confirmed the defect by crop
dimension: the three combat entries (01 barrage, 02 guardian, 03
core) carried `crop_bottom: 180` from
`notes/release/store-assets/screenshots.json`, so
`_render_play_screenshot` cropped each source to 2424×900 before
fitting 1920×1080. At the 3× device scale that deletes the lower
60 internal pixels — the new hero/story dialogue ribbon is gone
and the bottom-right dash circle is clipped in all three final
Play images. The renderer itself already fits a full viewport
with room for captions and brand, and tablet screenshots already
preserve the whole screen, so only the obsolete combat crop
contract was wrong.

The fix sets the combat crop contract to zero in both pinned
places: the three combat `crop_bottom` values in
`screenshots.json`, and `SCENE_CROP_BOTTOM["combat"]` plus the
three combat `SCREENSHOT_CONTRACTS` literals in
`apps/game/tools/build_store_graphics.py` (seven changed
numbers, no logic change). Title keeps 90, shrine and
hero-preview keep 0, and every strict check is untouched:
exact six-output set, per-locale real-UI sources, 1:1 unique
hashes, label literals, brand literals, provenance, and the
scene/crop literal gate that rejects arbitrary values. No game
runtime, scene, art, audio, locale, IAP, price, version, export
preset, capture producer, signature, or fingerprint-exclusion
change.

A new regression in the registered
`store-graphics-boundary.test.mjs` suite, `Play phone combat
screenshots preserve the full 2424x1080 viewport`, drives the
real `_screenshot_entries` (real manifest against the real
literal contracts) and the real `_render_play_screenshot` for
all six entries at 2424×1080, then asserts on the emitted
ffmpeg filter graph: each combat call crops the full
`2424:1080:0:0`, scales `1920:854`, and centers the game frame
at y=113 with its gold border, so the restored bottom strip
(source rows 900..1080, the dialogue ribbon and whole dash
circle) lands at output y 824..967 — inside the game frame and
above the brand caption zone that starts at y=995. It also pins
the unchanged policies (title `2424:990`/`1920:784`, shrine and
hero-preview full viewport). No existing test covered the phone
compositor's crop dimensions, so this guard is not a repeated
literal: it verifies full-source rows reach the compositor and
where they land.

Measured in this copy: the compositor probe confirms full-fit
1920×854 versus the old cropped 1920×712 for all three combat
entries, with title/shrine/preview unmodified; the new guard
fails on an intentionally restored double-sided 180-pixel
combat crop (`crop=2424:900`, `scale=1920:712`) and a
single-sided manifest-only restore fails at the literal
contract (`scene/crop/locale copy differs`); both were restored
exactly and the full registered `pnpm
test:play-release-package` is 211/211 green (210 existing + 1
new). `pnpm check:store-graphics` passes (tracked graphics
deterministic). `pnpm check:store-screenshots` fails as expected
in this copy because the gitignored capture proofs are absent
(`device capture proof file is missing`), before any crop logic
runs — reported, never recaptured. `git diff --name-only`
lists the screenshot config, the generator, the boundary suite,
the framing README (brief 027b alignment below), and this log —
five files — so production runtime bytes and pixels are
unchanged (`tools/` is excluded from `_runtime_fingerprint`).
Capture freshness splits by device: the phone proofs become
stale, because the screenshot config and the generator are both
pinned phone capture inputs (phone `CAPTURE_INPUTS` and the
generator's own `_source_fingerprints`). The completed
seven-/ten-inch captures do not become stale from this fix: the
tablet source/build maps (`ANDROID_DEVICE_CAPTURE_SOURCE_INPUTS`
and the tablet evidence inputs) include neither the screenshot
JSON nor the generator, and production runtime excludes
`tools/` — so the tablet reports can remain current after their
unchanged strict source/build/runtime/persistence validation.
Those post-acceptance validations have not happened here, and
no capture or submission completion is claimed.

Authorization versus completion: the user requested careful
review, merge on good review, fresh store screenshots, and
direct deployment. None of that is done here: no capture was
run, no screenshot recaptured or uploaded, no store or network
action taken, nothing merged or deployed. Phone proof rebuild
and the authorized current submission set stay with the
director; the tablet reports stand on their unchanged checks
without implying a tablet recapture.

Brief 027b alignment (same acceptance): the
accepted-in-principle generator/config/test diff above is
unchanged. Only `notes/release/store-assets/README.md` was
edited: the two combat debug-strip cropping passages now state
that capture automation hides the debug UI before each shot and
the three clean combat sources keep the full viewport including
the dialogue ribbon and dash control, the title's existing
90-pixel policy is recorded as unchanged, and the tablet
sentence now states the seven-/ten-inch sets use their
respective native Android tablet captures rather than a Pixel
phone capture. Minimum-change recapture rules and strict
provenance requirements are untouched. No new tests, no
runtime, capture, or remote operations; final screenshots and
deployment remain pending with the director.

## Resolve the embedded title in the distribution probe: brief 156 (2026-10-04)

The phone producer reached the direct-distribution installed-binary probe
with every store proof green except the title UI: `title_screen_visible`
and `title_store_button_present` were false, so `ready` stayed false.
Cause was the same embedding the boot marker had just been repaired for:
`store_capture_probe.gd` resolved `Ui/Screen` on the scene root, but the
production scene nests the original title under its `Title` child.

The probe now resolves through real scene identity — the `Title` child
under `production_entry.tscn`, the root itself under `title_menu.tscn`,
null otherwise — and fails closed while a gate card, panel, loader, or
confirm covers the production title. The resolver is structural on
purpose: naming `TestLauncher` or `ProductionEntry` from the probe broke
the `--script` clean-UI regression, which compiles without autoload
symbols, through `production_entry.gd`'s `Settings` reference. The live
Shop singleton, export feature, unavailable state, paid-SKU memory
fixture, `owns()` call, immediate byte-equivalent restore, and every
exported field are untouched.

What bit us: the first version reused the marker's resolver through the
global class name and turned the clean-UI suite red with compile errors
(caught before anything else ran). The second lesson was a missing
`await` on the new test's parity helper, which freed the production
entry mid-check and silently skipped four asserts behind a passing
count — the count is only trustworthy with the error stream next to it.

Coverage is `test_direct_distribution_title` (108 cases, registered in
the regression runner): production and standalone UI fields against the
actual embedded nodes, bare/decoy/missing rejection, card/panel/loader/
confirm occlusion parity with the marker, and the Shop memory/revision/
disk boundary. A headless engine proves every component but not the
final `ready`; the installed APK proves that. Reverting to the old root
lookup fails 10 of the 108, then restores exact bytes (sha256 pinned in
the report). One stale host pin was noticed along the way
(`capture-run-state.test.mjs` still demanded the pre-repair inline
marker shape in `test_launcher.gd`), but brief 155 fixed it
independently in the real tree, so this copy leaves that file at
baseline and the director gates on the current-root suites after
acceptance. Other debug helpers were inspected — arena/shot harnesses
already resolve their own roots or forward through `has_method` — and no
further embedding mistake was found. `check:store-screenshots` fails as
expected after the `apps/game` touch; no recapture (non-visual).

## One standing hero through walk, stop, and attack: briefs 186/188/190 (2026-10-05)

The user stopped a release over this: at rest the heroes stood legs-spread in a
frozen stride, and stopping changed the face (the idle head was visibly larger
than the moving one). The bake used turnaround row 0 for idle but separate
sidewalk donors for side walk, and idle rescaled the whole figure every breath.
All three rounds below landed in one diff; the director judged pixels twice
before accepting the approach a third time.

Round 1 rebuilt the side idle by gathering legs toward the contact feet and
kept row-0 reuse for down/up. The director read the result as a shortened step
(rear shin angled, feet split) with 12 untouched front/back strides, and sent
it back. Round 2 rebuilt all 24 idle cells from painted parts in the packer:
sides articulate about hip pivots (shin rotates, boot replants flat, profile
feet overlap at center 72±5), front/back mirror the walk's own planted leg
into a symmetric pair below the garment hem (keeper's bridged back-view boots
needed a one-boot donor erase to avoid a mirrored bar). Idle breath shrank to
a torso-band-only resample so head and feet stay byte-identical. Round 3 fixed
what round 2 measured but left open: every walk frame now wears its fitted
row-0 head pixel-fixed (the shared scale alone never registered painted
faces), and the down/up columns fit at one row-0 scale instead of equalizing
every frame's height (up to 4% face pulse, gone).

Two motion fights are worth recording. The side-stance file check first
demanded two sole runs, which honest profile overlap can never show; it now
checks the stance extent (26–38 gathered vs 56–68 stride, bound 20–46). The
knight's cannon kick briefly dropped 7.0→5.0 to satisfy the reach clamp on the
donor's tucked arm; the brief sent that back, and the honest fix was
recalibrating the shoulder onto the pauldron crown with solver-consistent
elbows — original 7.0 recoil and all motion floors pass unweakened.

Forecourt grounding uses the idle|walk union bounds per facing now, so stops
and same-facing departures never rescale or lift the actor; the paint tables
were re-measured from the final sheets. The attack harness movers lane runs a
synchronized stop cycle (walk, stop, planted attack, recover) with stops
turning through all four facings. Coverage: canonical-head bytes and boxes in
every walk/idle frame plus the attack torso and live transitions, standing
geometry for all 24 cells, below-neck stride motion (bounds alone go blind
once heads stop bobbing), and mirrored negative controls that fail on the
baseline stride heads, split stances, and single-boot fronts.

## End defeated journeys without a free retry: brief 200 (2026-10-07)

The user asked why death offered a restart from the defeated stage instead of
a coin continue or a return to the beginning. The loss screen now gives three
honest roads — one coin to revive in place, a fresh expedition, or the title —
and a sealed defeat stays sealed across title, relaunch, backup and cloud.

The representation is an additive `ended: true` on the checkpoint dict, kept
at the last alive seal's id with the final live score/shard echo. Absent
means alive, so every checkpoint sealed before the defeat rules reads
unchanged; a present non-bool refuses the whole save like any mistyped field.
`read_checkpoint` returns a valid ended main as-is and never falls through to
an older alive backup, while `has_valid_checkpoint` and `summary` treat it as
non-resumable, which is what the title, the production host and the arena's
resume entry all gate on. Death settles the final live score once through the
untouched receipt ledger (redelivery reads `DUPLICATE`) and records submit
once; a failed seal blocks every result exit until the marker lands.

The paid continue is transactional: seal a new alive checkpoint of the live
state first, spend the coin, then revive. A failed seal spends nothing; a
failed spend rewrites the marker. Either way the run cannot become resumable
without payment. Cloud precedence is same-journey scoped: a sealed defeat
outranks a stale alive payload of the same journey without a dialog
(`defeat-kept` locally, `defeat-adopted` from the server), explicit conflict
choices that would resurrect are refused, and a strictly newer alive seal or
a different journey still opens a real dialog with the sealed side marked.

What bit: the arena's `_restart` reloads the scene, so route tests assert the
wiring through the scene-blocking spy while the real-arena tests drive what
`begin_fresh` arms. The `show_result` signature lost its gate flag, which
touched the result-layout test and the UI shot harness too. The `.translation`
files are gitignored build artifacts, so the isolated single-test runs needed
the editor import first or the new `RESULT_START_OVER` key reads back raw.

Coverage: `test_defeat_terminal.tscn` (95 cases: terminal-vs-backup, title
hide/show, fresh reset with permanents kept, coin success, zero-coin and
injected journey/Vault/seal failures, alive quit) registered beside the
rewritten journey death tests (519 cases); six coordinator cases for tombstone
round trip, offline retry, restore keep/adopt, both refused choices and the
still-explicit different-journey dialog; a summary-marker case in the
checkpoint suite; and a production-host case proving resume refusal and
confirmation-free fresh planning over a sealed run.

## Defeat and paid-continue crash boundaries: brief 203 (2026-10-07)

Correction to brief 200. The director reproduced two crash defects in
isolated storage: the real defeat writer rotated the previous alive main
into the backup, so a corrupt terminal main fell back to a resumable
checkpoint; and `continue_run` wrote the alive seal and notified its
stable hook before the coin debit, so a death at that boundary stranded
a free resume. Both are fixed at the persistence order, superseding the
round-1 "seal first, spend, best-effort rollback" line above.

An ended write now mirrors the seal into both files, backup first, and
never rotates the older alive main behind it: either crash ordering stays
terminal, and the stable hook fires only once the sealed main lands.
Reads converge the pair toward the seal. A paid continue journals the
debit plus the exact revive seal in the Vault first (`begin_continue_txn`),
materializes the seal from the journal, then clears it (`ack_continue_txn`).
Every entry point settles the journal before reading
(`recover_paid_continue` → `recovered`/`delivered`/`stale`/`none`/`failed`),
so a crash before the debit leaves no resume and a crash after it recovers
exactly one paid continuation without another charge; a new journey clears
a moot journal. A seal that cannot materialize is stuck, not resumed: the
arena redirects to the title, the host reports `revive_stuck` instead of a
save, and the title shows the failure and confirms before anything boots.
Cloud keeps its generation/account guards and retires a stale ended
download only against an acknowledged newer seal (`stale-ended-retired`);
a legitimate newer alive seal still restores over an observed defeat by
explicit remote choice, and the intermediate journal never uploads.

What bit: fallback reads heal the main back, so a test that deletes "both"
files must delete the main again after its last read. `begin_fresh` arms
the fresh run but the arena boot writes it, so the abandon-half of the
stuck test boots a real arena to assert the cleared journal and the new
journey. Breaking the mirror (main-only seal) fails 7 crash cases; swapping
the debit order fails 7 more, including the stranded free resume.

Coverage: `test_crash_boundaries.tscn` (112 cases: the real writer's pair
under corrupt/deleted main, title/host gate hiding, debit-before-seal with
a mid-transaction relaunch, a reverse-ordered control documenting the leak
the journal closes, blocked purse alone and both-failures with retry,
stuck host/title/ask/abandon, double tap) registered in
`run_regression_tests.mjs`; one cross-client coordinator case (acknowledged
revive installs over the observed defeat while the journal neither poisons
the comparison nor uploads); defeat 116, Vault 237, production host 814,
coordinator 1218.

## Paid revive recovery stays in its account: brief 206 (2026-10-07)

Correction to brief 203. The director reproduced two defects with the real
journal API: a debit journaled under A materialized into B's empty slot on
`use_account(B)` while clearing A's receipt, and the loss-result button
sent a last-coin player to the shop instead of retrying the journaled
revive. Both are fixed at the ownership check, not the call sites.

Every journal entry now carries its owning scope (`Journey.active_account`
at debit time), and one receipt can pend per scope: the flat entry plus a
persisted `continue_txn_parked` map. All reads go through
`scoped_continue_txn()`; recovery with only a foreign receipt returns
`deferred` — no file touch, no stable-hook notify, no consume — and
`settle_continue_txn` rechecks the owner as defense in depth. Same-attempt
retry requires the exact acknowledged seal bytes, not just equal numbers;
a rival attempt in the same scope refuses without overwriting, while the
same numbers in another scope journal a separate debit. `begin_journey`
clears only its own scope, so B's fresh start never abandons A's receipt;
abandoning still takes the confirmed fresh action in the owning scope.
Slot moves carry the receipt (`rekey_continue_txn_owner`, refusing
occupied targets): legacy migration adopts it once no legacy files remain,
canonical adoption rekeys it with the renamed slot, and account deletion
drops only the deleted scope's entry. Link and token refresh never change
the public ID, so keying on the slot is stable across them. The result
panel routes to `continue_requested` — with a localized `RESULT_CONTINUE_RETRY`
save-retry label — whenever the scope holds a receipt, even at zero
balance; a true zero with no receipt still goes to the shop, and the
retry rebuilds the byte-identical seal, so it never recharges.

What bit: `account_state()` settles eagerly through the gate summary, so a
receipt journaled before `begin_guest` lands in the guest slot before the
adoption move runs — the canonical test blocks installs to keep the
receipt pending past the status read, proving the move itself carries it.
Pre-fix the new suite failed 23/78, reproducing both probes; post-fix it
passes 92/92. Breaking the settle check fails 3, the scoped read 12+, and
the button route 5.

Coverage: `test_account_recovery.tscn` (92 cases: the A→empty-B probe with
late hooks and switch-back, B fresh/play/quit/continue beside A's pending
receipt with byte-identical B files, exact-seal validation and no
free-ride, the real button/signal route with a true-zero control,
rekey/clear primitives) registered in `run_regression_tests.mjs`; host
deletion, canonical-adoption and token-rotation extensions (production
host 844); Vault 237, crash 112, defeat 116, journey 519, coordinator
1218, result layout 216.

## Paid journals survive canonical slot moves: brief 207 (2026-10-07)

Correction to brief 206. The director ran the real
`CloudCoordinator._move_slot_to_canonical()` with a guest seal 5, an
acknowledged journal for alive seal 6, and `Vault.TEMP_SAVE_PATH` blocked:
it moved both journey files into the canonical slot, ignored
`rekey_continue_txn_owner()` returning false, adopted anyway, and reported
no save error — the receipt stayed owned by the now-empty guest scope and
recovery deferred forever. The same ignored-failure shape sat at all three
`adopt_legacy_continue_txn()` call sites.

Both adoptions are now rekey-first through one gate,
`Vault.prepare_receipt_move()`, returning `ready` (nothing pending or the
rekey landed), `kept` (the target holds its own receipt or journey — adopt
without moving, round-3 occupied behavior), or `failed` (unsavable rekey —
move nothing). The coordinator holds the move on `failed` or on a failed
file move: it stays on the guest and the reserve reports error with code
`slot-move-failed` on both snapshots instead of adopting over a stranded
receipt. A crash between rekey and move leaves the receipt ahead of its
bytes, and the post-restart retry completes the move with no second debit.
Legacy adoption is one joint `Vault.adopt_legacy_slot()` (rekey, then raw
file moves that faults cannot half-stop): a failed rekey migrates nothing,
an occupied slot keeps files and receipt jointly legacy, and a legacy
receipt with no legacy files left is never adopted blindly, so no settle
can install a foreign seal into an empty slot. Host startup and account
moves honor the hold through `_run_legacy_adoption` and carry
`legacy-adopt-held` in `account_state()["legacy_hold"]` until the next
startup retries. The unsafe `adopt_legacy_continue_txn()` is gone; its
three sites call the joint op.

What bit: status reads settle eagerly, and `delivered` needs no install,
so an install block cannot hold a seal that already landed — the legacy
fault test journals after parts are built and blocks installs throughout,
keeping the receipt itself (not just its ack) pending so the retry proves
receipt and bytes travel together. A pre-fix leftover journal in one test
also masquerades as another test's `deferred`, which is why each adoption
test now asserts its own no-orphan tail. Breaking prepare fails the vault
contract (2) and every canonical adoption; ignoring the move result
reproduces the probe exactly (10 host failures, orphan receipt, lost seal,
empty save code); skipping the legacy hold fails 7.

Coverage: host adoption extensions (fault-adopt hold with restart retry,
legacy clean + fault/rotation/retry, occupied canonical, rekey-move crash
window — production host 923); `prepare_receipt_move` contract in Vault
249. Coordinator 1218, journey 519, crash 112, defeat 116, account 92,
result route 76 / layout 216 / depth 55 stay green.

Known edge: a receipt stranded by the old files-first order (files moved,
rekey never landed — only round-3 builds could write this) reads as an
occupied target and stays retained-but-deferred rather than healing; the
choice is deliberate, since healing by journey-id match could import a
foreign seal on an integer-id collision.

## Unique adventurer names for scores: brief 201 (2026-10-07)

The name service the lodge room will use in brief 202. No room yet, no
entry gating: this is the account-owned unique-name and score contract.

Preservation prerequisite first. The director's probe showed
`prepare_receipt_move()` returning `ready` as soon as the source had no
paid journal, before checking the canonical target: an unrelated living
source journey imported over target C's acknowledged one-coin receipt
for seal 6, and recovery then called C's original receipt `stale` and
deleted it. The gate is now target-first: a target with a pending paid
recovery or an existing journey is occupied even when the source has no
receipt, returning `kept` with the source bytes retained and the target's
exact acknowledged seal recovered, never a second debit. Breaking the
reorder reproduces the probe (import over paid target, `stale` delete);
vault 276 and host 1013 hold it.

Names are an immutable pair bound to the canonical UID/public-ID before
and after every atomic write: private `mb_adventurers_v1/{public_id}`
(owner-only) plus the public collision index `mb_names_v1/{name_key}`
(handle plus the already-public ID, no UID, no credentials). First-wins
atomic commit; lone or mismatched halves are rejected at both boundaries.
`CloudSchema.normalize_adventurer_name()` is the shared allow-list both
sides mirror: 2-12 BMP characters (Latin, digits, underscore, precomposed
Hangul, hiragana, katakana plus U+30FC, CJK ideographs, single interior
spaces), trimmed, keyed by `to_lower()` so mixed-case Latin collides.
Host/coordinator ops are generation-bound; claim also caches the verified
handle into the bounded (8, per-public-ID) vault cache for offline use
and backfills it onto the existing best row at the row's own saved hero,
cycles, and score — never a zero row, never a downgrade. The intro bit
flips only false to true; deletion removes the pair with the Hall row in
one verified commit. A Firebase-registered guest claims; a local-only
guest cannot certify uniqueness. `Arena._on_result_record()` routes a
verified named player to a read-only named view with no editable field
and no legacy `GlobalLadder` upload.

What bit: committing raw Unicode document names while URI-encoding only
HTTP URL path segments (a percent-encoded document ID would reserve the
wrong name); cold caches must preserve the stored Hall display rather
than blank it; and the local-guest guard has to run before the
account-not-ready guard or guests get the wrong error. Breaking the
commit body fails the store contract; blanking cold display or swapping
the guard order fails host.

Coverage: cloud_name 129, hall display/backfill 269, named deletion 52,
vault cache 276, host 1013 (7 name cases plus re-registered adoption),
coordinator 1218, ladder 121, result route 82, journey 519, crash 112,
defeat 116, recovery 92. Rules: 62 tests / 13 suites syntax-ok with the
combined splice verified (677 lines); the real emulator run is the
director's operation. Player-care Hall/deletion/retention disclosure
updated in all five locales with the site rebuilt and its 15 + 21 tests
green. Callable lodge contract: `notes/plans/gate-account-protocol.md`.

## Name boundaries and token switches: brief 208 (2026-10-07)

Correction to brief 201, from four director emulator/production probes
plus two inspection items. All preceding defeat, recovery, adoption, and
name coverage stays green.

Fresh owners could not start naming: the adventurer read rule touched
`resource.data.uid`, so a missing row denied with 403 instead of reading
404. The rule now proves ownership from the canonical pair alone, giving
the proven owner an authoritative missing-row read while other owners,
the unregistered, and lists stay denied. The client keeps returning
`permission-denied` truthfully on every claim path; taken still arrives
only as a commit conflict plus a missing own-row recheck.

A living name could be released under a living account: both halves'
delete rules now require the Hall row and both canonical halves gone
with them, so only the full atomic deletion (with or without a Hall row
yet) frees a name, missing-row no-ops still resume, and the reverse
(pair halves while the name stays) stays denied.

A name request could cross a token wait onto the next coordinator. All
four host wrappers now capture an account/coordinator ticket before the
token await and verify it after every async boundary: a parked switch,
deletion-shape retirement, or shutdown cancels with `account-retired`
or `host-closed` instead of dispatching, and a failed token fails the
call without sending any mutation.

A name restore dropped the tutorial bit and regressed the cache. Every
successful claim now carries the real `intro_complete`, and the vault
bit is monotone per same-name entry: a late incomplete response keeps
its bytes in the result but never clears the durable bit, while a new
account still starts incomplete.

Also: the Hall mapper and panel now show the verified handle on each
named headline with the MB ID on its own line (unnamed rows unchanged),
and `_submit_best` pushes the refreshed standing to the Arena chip
again — the insertion had orphaned that call below a return.

What bit: Godot 4.7 forbids un-awaited async calls outright, so parking
a wrapper coroutine is impossible; the mid-flight tests interleave
through timers and a recorder-dispatched signal while awaiting the real
wrapper. Re-injection churns account signals, so the swap is a narrow
white-box seam. Breaking the ticket reproduces the probe exactly (B
receives, old request ok); breaking the mapper, the HUD push, the
monotone guard, or the restore bit fails exactly its new tests.

Coverage: host 1085 (restore-bit, 4-route switch, token
failure/timeout, shutdown, stale completion, retirement, submit-HUD,
mapper-to-panel), cloud_name 137, vault 282. Rules: 69 tests / 13
suites, splice verified (690 lines); the real emulator run stays the
director's operation.

## Two attendance coins per twelve hours: brief 204 (2026-10-07)

The deletion ticket now pins the deletion generation as well as the
account/coordinator lifetime, so a name/attendance request parked at
token refresh stays cancelled even when the deletion fails on the same
account, while a genuinely new request after the failure proceeds. All
five wrappers (claim/load/intro/backfill/attendance) refuse to start
while a deletion ticket is in flight.

Attendance is one private row per account, `mb_attendance_v1/{public_id}`,
with a server-enforced rolling 43200-second cooldown: the first visit
grants two coins and days away still grant two, never a stockpile.
Eligibility derives from server read/commit timestamps only, so device
clock changes cannot move it. The wallet grant is idempotent under the
stable key `attendance:{public_id}:{seconds}:{install_id}`, which binds
each reward to its receiving install; replay state stays bounded (newest
8 keys plus a watermark, purchased keys never evicted). Entry and
foreground triggers are nonblocking skips that never gate play, and the
five-language receipt shows only after the durable grant — never over an
IME field or open NPC dialogue. Deletion removes the row with the rest
of the account and clears the local marks; granted coins stay in the
device ledger.

What bit: the host suite shares one Vault across tests, so every
attendance test after the first saw a duplicate grant key until the
adopt helper cleared `attendance:*` keys; sender-call assertions need an
adopt baseline (the adopt itself makes two calls). The new locale row
needed an editor reimport before `tr()` resolved it. Breaking the
receipt gate (cooldown queuing a receipt) fails exactly the cooldown
test; breaking the deletion-generation pin fails exactly the
pre-deletion attendance cancel.

Coverage: host 1215 (first claim, cooldown, uncertain ack, wallet
failure, skips, double tap, receipt flush/suppression, foreground,
offline, link, deletion barrier), cloud_attendance 62, vault 324.
Rules: 84 tests / 14 suites, splice verified (741 lines); the real
emulator run stays the director's operation.

## Earned attendance and deletion boundaries: brief 209 (2026-10-07)

Correction to brief 204, from three director probes against the real
Vault, coordinator/service/transport, and deletion route. All preceding
defeat, recovery, adoption, name, and attendance coverage stays green.

Ten owners granting one minute apart evicted the first owner's receipt
key and watermark together, and its identical replay granted again. The
vault now folds every evicted owner watermark into one durable global
floor: an untracked owner at or below the floor fails closed as
`attendance-replay-ambiguous` with the wallet untouched, while a
just-landed conditional commit bypasses the floor (the twelve-hour rule
makes it provably new), so genuine new accounts, new periods, and
same-second cross-owner ties still grant. Purchases never evict.

A server-acknowledged reward lost to a blocked wallet save never
recovered once the next period went eligible: the advance overwrote the
row and paid only the new two. Eligible advances now backfill first —
the read row's current stamp when this install received it, plus any
carried previous stamp from this install — and commit only after every
owned reward lands, carrying the overwritten stamp and install byte for
byte (the rules require exactly that pair, forbid it on create). A
failed backfill stops before the commit; results name any backfill in
`backfilled` plus `backfilled_receipt`, and the entry receipt counts
fresh plus backfilled coins. The carry preserves one generation.

The account-deletion commit omitted the attendance row while the rules
require it gone with the canonical halves, so attended deletions died
with `permission-denied`. The client plan, commit body, and
remaining/completed steps now include attendance (seven steps named,
five unnamed, after checkpoint); missing rows stay server no-ops, and
native Auth deletion still runs only after the data commit acks.

What bit: the rules chain compares exact timestamps, but the client
tracks whole seconds — the carry passes the raw RFC 3339 read through
untouched (sub-second fractions survive; a truncation test pins it).
Breaking the floor re-grants the evicted replay; skipping the backfill
fails exactly the five new recovery tests and nothing else.

Coverage: vault 354 (multi-owner reload replay), cloud_attendance 86
(eligible/advance split, carry parse, advance races), host 1288
(backfill-before-advance with restart, foreign carry, cooldown backfill,
replay idempotence, uncertain advance, ambiguous stop), account 56
(five/seven steps). Rules: 88 tests / 14 suites authored (carry
required/forged/absent/create-denied/overwrite), splice verified (757
lines); the real emulator run stays the director's operation.

## Enter the gate lodge with Lumi: brief 202 (2026-10-07)

First-login refuge on the reviewed name service. Cloud-linked accounts
whose durable cache holds no verified handle or no acknowledged lesson
bit route through the lodge before the Arena; completed accounts plan
the Arena directly and local-only guests play through unnamed as
before. Two round-10 repairs land with it: a pruned attendance return
now skips the ambiguous old receipt and advances a genuinely new
eligible claim instead of freezing the account, and the RFC 3339 parser
rejects malformed server dates before the engine call, so the full log
stays clean.

Routing lives in the host, not the buttons: `needs_lodge_lesson()` is a
sync cache read, `plan_entry` refuses unsettled accounts with
`needs_lodge`, `plan_lodge_entry` holds the entry lock without arming
any journey, and `plan_lodge_exit` re-plans exactly like the title
(Resume vs confirmed fresh; sealed runs never resume). The entry
detours into the lodge loader with the same confirm/cancel/retry
semantics. Ten restore tests gained a settled-handle seed: they judge
the restore gate, and the lodge gate now precedes the plans they make.

The room packs both plates reproducibly (`build_lodge_assets.py`: wide
1881×836, tablet 1448×1086) and Lumi as four 869px-tall facings on one
scale and one bottom-center foot anchor (visible heights 853/850/851/
852, 0.35% spread) plus a bust crop. Layout is pure math over measured
plate fractions (aspect ≥ 1.7 takes the wide plate); the room covers,
actors scale with it from matching bases, walls clamp, the desk and
Lumi push out, the gate triggers on feet. Thirty-three `gate.lodge.*`
strings ship in all five locales. The lesson (greet, name, walk, dash,
gate seal, departure) completes only from performance plus server acks;
sticky vault gates and the durable onboarding mark resume after
restart; every await re-checks the bound account and retires to the
title on a move. Result recording still routes verified handles to
`ask_named` with no second prompt.

What bit: the engine clamps `Control.size` to the combined minimum at
assignment time, and wrapped-label minima recompute a frame after the
width pins — sizing in the same breath freezes the stale tall minimum
and the panel never shrinks back, which the headless 808×808 validate
framing caught (panels at 1079px). Seating now pins widths, waits a
frame, then sizes from the fresh minimum. `Rect2.has_point` includes
the top/left edge, so the desk push-out steps one pixel clear.
Breaking the move threshold fails the lesson chain; forcing the lodge
gate false fails 25 host cases.

Coverage: lodge 542 (layout/Lumi/strings/flow/guards), host 1353
(routing, exit guards, defeat never resumes, seeded restore), vault
381 (sticky gates, cap, malformed drop), entry state 10315 / layout
85722 / exported locales green, review validate 297 headless;
room/contact/≤120-frame clip render windowed for the director.
Contracts: 7 lodge rows in `custom_asset_contracts.json` (271 files
pass), manifest rows, builder `--check` wired into `check:assets`.
Hero rasters byte-identical (empty diff). Windowed capture, the full
game sweep, and the Android touch pass stay the director's operation.

## Scale Lumi in the rendered lodge: brief 210 (2026-10-07)

Two director-confirmed defects in the round-10 scene. First, the guide
drew her 869px packed source at node scale ~1.0 (871px in a 360px
room): the source-to-world conversion never reached the sprite. The
guide node now converts itself (`BASE_SCALE`, `set_actor_scale` for
the room zoom), sized at 42 world px — 1.5x the tallest measured hero
opaque body (28.05, all five heroes agree within 0.5px), not the
assumed 64px hero. Brief 211 plants the boots: the world bob moved
the painted feet 4px peak to peak, so the idle is now a still body
with a breathing shadow (alpha 0.85 +/- 0.04, period 2.6 s); a new
planted test measures the opaque foot line through the real sprite
transform at five idle phases per facing and allows at most 0.5px.
The shadow recomputes from world units, and packed art is untouched.
Second, a cold cache recovering a completed row practiced
anyway (state 1/GREET); the recovery branch now trusts the host's
cached readiness and departs straight to Resume/confirmed fresh, while
a failed cache write still re-seals at the gate.

The harness room `state=greet` now captures the true unnamed greeting,
the contact sheet uses the self-scaling guide, and the clip drives the
real lesson (taps, walk, dash, neutral stop, gate steer) over 600 sim
frames with ≤120 saved, printing observed phases and exiting nonzero
unless movement, dash, stop, and departure all complete.

What bit: per-sheet opaque measurement must fold the 4×4 cell grid on
both axes (single-axis folding reported a 174px hero); the headless
viewport runs 808×808, so the new 808×532 iPad-mini-ratio framing
joins the pure layout math instead. Breaking the conversion fails 37
lodge checks (854px opaque body); forcing practice fails the 4 cold
checks with state 1 vs 7.

Coverage: lodge 624 (world-bounds bodies at four framings incl.
808×532, cold-completed with living save), host 1353, entry state
10315 / layout 85722 / exported locales, validate 347 (guide
conversion audit added), scripts 172, assets 271, heroes still
byte-identical. Windowed rendering stays the director's operation.

## Not done

- Store screenshots: the fresh five-locale Android originals (phone 40 PNGs, seven-inch 30, ten-inch 30)
  were genuinely captured and reviewed. The phone proofs become stale pinned-input evidence when their pinned
  screenshot config or generator changes — as with this combat viewport fix — so current phone submission
  images are still pending with the director, as are the iPad captures. The tablet source/build maps exclude
  the screenshot JSON and the generator, so the seven-/ten-inch sets can remain current after their unchanged
  strict source/build/runtime/persistence checks pass — those validations are pending, not claimed. Nothing has
  been uploaded.
- Later deployment and release gates are uncompleted: merge when review is good and deployment are now
  requested by the user. Local checkpoints exist — the director independently built and verified the
  3.0.0/code15 Play AAB and direct release APK — but they are local artifacts, not store uploads: no iOS
  archive, no native store purchase E2E, and no physical-device E2E is claimed from this copy. Firestore
  rules are committed but not deployed, analytics collection stays gated, and no store submission, release
  tag or merge has happened. Push confirmation, the human PR signal and the physical-device/tunnel
  prerequisites remain pending with the director.
- An Echo on a ring guardian (field, forest, toad, sentinel) still trims the repeat under the hostile
  projectile cap while its picture shows the whole ring — the safe way to be wrong. No evidence justifies
  uncapping the mobile budget; the limitation stays visible.
- The result screen is restyled but its layout is the 2.1.0 one; a rank seal would be
  a good next step.
- Store imagery that shows the redrawn characters: the IAP hero images and the hero bundle image were
  regenerated (`pnpm check:store-graphics` passes, reproduced in this copy); the marketing screenshots
  still show the 2.1.0 art. They are redone together with the store set, on the user's word, and are not
  touched here.
- The title screen keeps its own atmosphere and does not get the grade. Its store
  capture checks inspect the title's own nodes. Correction to the earlier
  "no recapture planned" line: the user has now requested changed title
  imagery as well, so a title recapture is authorized and pending with the
  director — not done here.

## Attendance reminders: brief 205 (2026-10-07)

Local twelve-hour attendance notices with a Settings switch, on the
reviewed attendance service. A host-owned `AttendanceReminders`
controller reads the server-confirmed `next_eligible_utc` as its single
authority and drives a separate reminder API on the MoonlitIdentity
natives (no Firebase gating): status, permission, schedule, cancel,
open-settings, pending diagnostics, and a QA-only short one-shot.
Intent persists in Settings with its own fail-closed disabled mark;
scheduling decisions query the live native permission while an
identical-inputs skip keeps title refreshes from shifting the
deadline. Android holds one inexact `RTC_WAKEUP` alarm re-armed after
boot with a monochrome beacon icon and a five-language channel; iOS
holds a one-shot first fire plus a 43200-second repeat with
app-only `NSUserDefaults` metadata declared by an app-owned
`PrivacyInfo.xcprivacy` (CA92.1). Foreground delivery is suppressed on
both platforms; the notice never grants coins.

What bit: the reconcile writes the OS display cache, which emits
`Settings.changed` back into refresh — on the never-recorded refusal
path the granted/denied flip-flop recursed until the stack blew. A
reentrancy guard (nested passes are redundant) fixed it, and the new
denial test pins the path. The taller settings card overflowed 808x360
by 26px; the upper rows moved into the dead air under the title plate
and the lower block compresses to 2px gaps (all rows verified on
screen in five locales at both framings). The lodge name form now
reports keyboard visibility/height plus real field/action bounds for
entry QA and lifts above a covering keyboard, measuring from the
unshifted seat so the correction cannot oscillate.

## Real reminder bridges: brief 212 (2026-10-07)

Three director-confirmed boundaries from the round-13 reminder work.
First, the Android bridge failed with unresolved `R.drawable`: the
standalone Gradle renderer copied templates plus Kotlin but never
`src/main/res`, so the owned beacon icon and channel strings never
reached the AAR. The renderer now stages the whole res tree, and two
new contract tests render the project and prove every generated `R`
reference resolves to a staged file. Second, the iOS reminder methods
sat after the worker's `@end` (18 compiler errors); they now live
inside `@implementation MoonlitIdentityWorker`, matching the file's
properties-only interface pattern, with a placement test that slices
the implementation span instead of grepping names. Third, the
controller skipped any window under 60 seconds, permanently stranding
a newly enabled install 30 seconds from eligibility; only the
already-eligible visit (`remaining == 0`) skips now, and the 30-second
probe is a registered case asserting one schedule at the confirmed
deadline with no short repeat.

What bit: proving the placement test required temporarily restoring
the broken layout, and the restore script cut at the first method's
closing brace, splitting the section across `@end`. Repaired
deterministically (all ten selectors back inside, braces balanced,
each defined exactly once) and re-greened.

## iOS reminder horizon: brief 213 (2026-10-07)

The round-13 iOS shape (one-shot at the remaining delay plus a repeat
anchored to now) double-fired on fresh rewards and drifted on
halfway enables (+6/+12/+24 instead of +6/+18/+30). Scheduling now
writes a bounded horizon of 48 non-repeating slot requests at
eligibility plus N * 43200 (24 days, under the 64-request OS budget):
elapsed slots skip instead of bursting, identical refreshes skip
while the horizon is live, a nearly consumed horizon refills from the
same anchor, and a new claim resets it. Cancel removes the horizon
plus legacy first/repeat/debug ids and delivered copies; scheduling
replaces legacy pending copies so the migration cannot double-fire.
Diagnostics report each held trigger plus a horizon block (anchor,
slot count, held slots). Player-facing text now states the bound
honestly (48 notices in EN to respect the day-count freshness
needle; 24 days elsewhere).

## Keep the player visible during lodge dialogue: brief 214 (2026-10-07)

Three measured stage defects, one per layer. The wide spawn sat the
hero's opaque feet 5.7px under the greeting card at 880x360 (0.7px at
808x360): WIDE_HERO moved from y 0.66 to 0.634, about 10px up, still
deep in the walk band and clear of desk, Lumi, and gate. A new live
regression sweeps every idle frame against every greeting and
name-recovery card at both wide viewports in all five locales through
the real canvas transform. The name form fed raw device keyboard
pixels straight into viewport layout (432px at 3x produced a 354px
lift and negative displacement); the height now converts through the
inverse screen transform (144 viewport px, 66px lift), the lift parks
at the safe top when cramped, and the QA report names
keyboard_height_device and keyboard_occlusion separately. The contact
board seated its camera current-before-add (engine ERROR) and
captured on the first tick's lagging interpolation, which drew the
last actor huge; the harness now seats, resets, settles, then
audits four rendered silhouettes from the captured pixels and fails
the run when a slot is empty or outsized. What bit, twice: under
project-wide physics interpolation a fresh tree's canvas transform
lags reality until reset — both the new test and the board reset
before judging pixels.

## Converge reminder state after OS changes and return: brief 216 (2026-10-07)

The identical-input skip ran before the live permission check, so an
OS revocation on the same deadline never surfaced; the controller now
re-checks permission first (denial keeps intent and record, schedules
nothing), and iOS status answers pending with a fresh async verdict
whose bounded outcome runs the schedule tail once — a tail that never
re-queries status, so it cannot loop. The iOS horizon finally refills:
the first future slot derives from the anchor, 48 future slots plan
under stable ordinal ids whenever fewer than 8 remain, and the held
base/end persist into the receipt and pending diagnostics; the game
records the window and re-asks only when it runs low, never moving
the deadline. The settings row builds lazily on first open (knight
Lv40 node peak 1202 → 1199 against the unchanged 1200 budget) and an
undetermined OS state shows a truthful new string instead of on.
Android status weighs the global switch, runtime grant, and channel
on every version; pending diagnostics separate persisted intent from
token existence, retiring cancels the tokens, and the schedule
receipt reports an unbounded -1 horizon. What bit: muting the suite's
spare host-owned controller exposed the locale test's hardcoded "en"
as a no-op that had passed on interference; it now picks a genuinely
different locale. The divergent JS horizon simulation is gone,
replaced by structural contracts over the production planner plus
real controller tests.

## Match the actual native plugin APIs: brief 215 (2026-10-07)

The real toolchains typed what the regex tests could not. Android:
`onMainRequestPermissionsResult` returns Unit in the pinned Godot core
(Boolean was the back-press callback), and `Godot` is not a `Context`,
so the five `activity ?: godot` fallbacks became activity-or-honest
retryable `no_activity` errors; the two null-host paths already there
took the same code. The game controller now treats a native `error`
as a reason to retry, never to cancel: the owned delivery, its
record, and the cached display state survive, and the next refresh
converges. iOS: the 64-bit anchor rides an NSNumber through
`setObject`/`longLongValue` (no longLong selectors exist),
`nextTriggerDate` is read only from concrete interval/calendar
triggers, and the ephemeral grant hides behind `@available(iOS 14)`.
What bit: the reminders scene also runs the host autoload's own
controller, and both reconcile the shared Settings record — a test
that emits between plant and assert watches the other controller
retire it through the real bridge. The new transient-error test sets
the display cache directly and asserts across one direct refresh.

## Keep the name action above a tall keyboard: brief 217 (2026-10-07)

The clamp math was honest but the card was not: parking a 228px panel
at the safe top still buries the confirm action under a 180px
keyboard. The production hook now compacts when the lift runs out —
bust, header, and hint hide, the card shrinks to its live minimum
(138 at 808x360 ko), and field, feedback, and confirm lift clear with
the 8px margin. Hide restores chrome, geometry, and the typed value,
then re-seats for the current view; resize never fights a shifted
form. An all-screen keyboard is dismissed once per height instead of
promising impossible UI, and the keyboard's own submit still files
the claim. The lodge scene camera and the contact-board camera ride
the physics callback (verified `CAMERA2D_PROCESS_PHYSICS = 0` from
the engine, not memory). What bit, twice: headless owns no window
(`window_get_size` reads 0,0), so the tests stage the window they
resized to through a second hook parameter; and a coroutine test
helper called without `await` interleaved the lift asserts with the
compact case, printing chrome states exactly inverted from the
returned modes until the missing `await` went in.

## Close the remaining real reminder refill boundaries: brief 218 (2026-10-07)

Three native/game disagreements and one build break. Android:
`OPSTR_POST_NOTIFICATION` is not in the compile SDK, so the pre-24
app-global check now resolves `OP_POST_NOTIFICATION` by reflection
exactly like NotificationManagerCompat, with the same safe-true
fallback; and both schedule paths (direct and boot) move an overdue
first trigger onto the anchor grid's next future slot instead of
firing the backlog immediately. iOS: the planner is integer
milliseconds in a shared header — due-now counts as future, so the
equal-time boundary holds 48 slots and day 25 plans from slot 50 —
and every success receipt carries its held window, duplicates
included. The game side schedules expired known anchors (future-only,
no coins), holds under the exact native duplicate rule from the
recorded base/anchor, derives legacy bases once, and never replaces
known metadata with a bare duplicate's zero. Proof is execution, not
simulation: a node test compiles the production header with the
system C compiler and runs the vectors, while the GDScript suite
mirrors the same agreement fixtures. What bit: the contract suite
pinned the old bugs (OPSTR reference, `maxOf(eligible, now)`, the
`<= now` skip, the metadata-less duplicate), so each fix updated its
contract to pin the corrected shape instead. The numeric proof
compiles the production header itself, never a copy of its math.

## Respect off after a late native status result: brief 219 (2026-10-07)

The granted async-status tail called the schedule function directly,
bypassing the reconcile head's enabled/source gates: pending, then
off, then a late grant scheduled one delivery while off. The gates
now live in the shared tail itself, so both paths honor current
intent and ownership; the late verdict still corrects the OS display
cache, and a later genuine re-enable schedules exactly once. What
bit: nothing — the new tests failed first on the unpatched code with
the director's exact signature (schedule_log 1 while off).

## Reminder release and preservation contracts: brief 220 (2026-10-07)

Two root integration defects, both producer-side. The reminder off
sentinel `user://attendance_reminders.disabled` is a real preserved
preference that was missing from every fixed inventory, so the
Android and iOS save inventories reported it unclassified. It now
sits in both Node producers and the Python consumer (33 entries),
with every mirror pin updated and a registered regression proving
its presence round-trip, mutation detection, and tampered-proof
rejection. The Android notification vector carried
`android:tint="?attr/colorControlNormal"`, which release AAPT cannot
resolve in the standalone library while debug stays green; the tint
is gone, the white silhouette and resource name stay, and the
drawable contract now rejects any `?attr/` theme reference. What
bit: nothing — both inventory suites failed first with the exact
unclassified sentinel, and the new tests fail on purpose when the
list entry or the tint is reverted.

## Keep new lodge terms within repo rules: brief 221 (2026-10-07)

Root hygiene flagged four whole-word hits in the new lodge files:
the Lumi guide's idle comment and breathing-angle local, plus one
practice assertion string in the lodge test. Renamed the local to
`pulse_angle` and reworded both strings; every number, expression,
and behavior is untouched. Lodge regression (2435 checks), the
174-script compile, and hygiene (zero product hits) are green. What
bit: the copy's `.godot` import cache predated the new lodge art,
so the compile check failed on missing `.ctex` preloads until one
editor `--import` refreshed the cache (sandbox-blocked editor
settings save, as usual; no repo files from the import).

## Fit the attendance label beside its button: brief 224 (2026-10-07)

English `Attendance reminders` is 164px at font 15 in a 128px
column, so the centered label grew both ways to (214,229,164,34)
and overlapped the button at x368 by 10px; the old probe checked
viewport containment only and missed the sibling overlap. The
settings row now measures the label like the status button and
shrinks 15→11 (119px, the locale-button size) in English while
staying 15 in the other four locales, recomputed on every redraw
so locale changes and repeated opens never stick. The regression
checks text width, combined minimum, rect separation, and a 6px
visible-text-to-button gap at 808x360/532/606 in all five locales
across off/on/denied/unknown/unsupported, plus translation-update
and reopen recompute with no second lazy row. What bit: nothing —
the new checks fail first on the unpatched code with the
director's exact signature (164px label, -10px gap).

## Free the vault regression's temporary nodes: brief 228 (2026-10-07)

`_test_continue_txn_atomicity` and `_test_prepare_receipt_move` built ten
plus three temporary normal/failing Vault nodes (including the
malformed-journal loop) and never freed them: 13 leaked Nodes, 16 leaked
ObjectDB instances, 2 scripts still in use, and the strict runner's
correct failure on an otherwise 381-green run. Every fixture now frees
its nodes like the older tests, and each of the two functions asserts
orphan-node baseline equality via
`Performance.OBJECT_ORPHAN_NODE_COUNT`, so an omitted free fails the
registered test instead of only warning at exit. Vault is 383 green
with zero teardown diagnostics; defeat (116), crash boundaries (112),
account recovery (92), IAP store (852), and journey (519) are green
too. The negative control (two frees omitted) fails both guards with
exact orphan deltas and restores clean. What bit: nothing — the probe
confirmed the monitor is synchronous before the guard was written.
Production bytes unchanged; only `tests/test_vault.gd` differs.

## Project desk collisions onto walkable floor: brief 229 (2026-10-07)

The lodge's `_push_out_of_desk` picked the nearest desk edge with
float-equality ties and no walk check. At 880x360 the desk center
(167.2, 74.4) exited the top to (167.2, 14.73), off the walk band
(min y 117.42); the player's bounds clamp then settled it back to
(167.2, 117.42), inside the desk again — a frame-order flake the
suite caught once in full verify and never standalone. The push-out
now delegates to pure `GateLodge.desk_exit_for`, which takes the
nearest exit that stays inside the inclusive walk bounds and breaks
near-ties (0.001px) in fixed left/right/top/bottom order; a clamped
fallback covers the no-valid-exit case no real framing reaches. The
registered lodge suite gained per-framing guards over all four judged
sizes plus 880x360 — center, edge midpoints, corners, and overlap
strips through the real method, both constraints after projection
and after real physics settling, sliding sides preserved, live-loop
checks — plus a labeled 880x360 negative control that catches the
old rule stranding off-walk and re-entering on clamp. Lodge is 2850
green across three clean runs; the old method restored fails the new
guard 84 times with the director's exact 880x360 signature.
Production host (1353), gate entry state (10315) and layout (85722),
terrain movement (536), and gate loading (346) are green too. What
bit: float32/float64 disagree on the center tie (Python picks top at
808x360 where Godot picks bottom), so the tie was never a rule —
and the copy needed one editor import for the gitignored
`gate_entry` translations before any string-dependent check.

## Default iOS releases to after approval: brief 230 (2026-10-07)

Future iOS submissions select automatic release immediately after
approval. `scripts/lib/app-store-release.mjs` gains
`APP_STORE_VERSION_RELEASE_TYPE = 'AFTER_APPROVAL'`, generated into
`payload.release.releaseType`, required by manifest verification, and
planned on version create/update with no `earliestReleaseDate`;
`fields[appStoreVersions]` GET selection and `audit.remote`
now carry the actual remote `releaseType`.
`scripts/lib/app-store-connect-apply.mjs` blocks review submission
with `ASC_AUTOMATIC_RELEASE_NOT_VERIFIED` unless the GET readback is
`AFTER_APPROVAL`, before any submission POST/PATCH. Read-only review
and published boundaries are unchanged: non-adoptable versions keep
`ASC_APP_STORE_VERSION_NOT_ADOPTABLE`, and editable-state checks keep
refusing read-only mutation. Three focused tests in
`scripts/lib/app-store-release.test.mjs` cover create, editable
MANUAL/SCHEDULED update, already-matching idempotence, bad-readback
submission block with zero requests, and read-only/published refusal;
83 App Store node tests pass. Negative controls: dropping the create
`releaseType` fails the new default test plus two existing create
asserts; removing the submission guard fails the new readback test.
Author default noted in `notes/release/iap-store-setup.md`. What bit:
nothing — existing create/submit/read-only fixtures needed the new
field added to keep their other guarantees.
