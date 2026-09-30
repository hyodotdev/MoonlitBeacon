# Guardian sources

One front-view, keyed (transparent background) PNG per guardian: six terrains and each
terrain's evolved form. `tools/pack_ludo_guardians.py` bakes them into the 44 sheets under
`assets/custom/actors/guardians/` by deforming the one body, so windup, charge and recover
are always the same creature.

The folder name is historical: the first set came from ludo.ai. **The current set was drawn
with ChatGPT's image generator on 2026-09-29**, as two 3x2 grids on flat magenta (the first
three places, then the later three), each cut apart with `tools/cut_lineup.py --rows 2 --gap 1`.
The raw grids are not in git (`_asset_sources/chatgpt_guardians_2026-09-29/`); the old ludo.ai
sources are in git history.

| Source | Design | Attack it carries |
| --- | --- | --- |
| forest | mossy leaf-winged golem with a glowing core | wind-up, charge |
| forest_thorn | the same golem, cracked with red veins and horned with thorns | wind-up, charge |
| field | moth sprite with big wings holding a glowing orb | cross and radial wind-ups |
| field_storm | the same moth with a storm-purple body and lightning wings | cross and radial wind-ups |
| camp | stone furnace golem with a lit hatch | wind-up |
| camp_siege | the same golem in riveted iron, with cannons on its flanks | wind-up |
| frost | snowy owl with a crystal crown and big blue wings holding an ice gem | wind-up, charge |
| frost_rime | the same owl with antlers of ice, icicle feathers and violet wing tips | wind-up, charge |
| marsh | round toad with a lily-pad hat holding a glowing orb | wind-up, charge |
| marsh_glow | the same toad with a crown of glowing mushrooms and cattails, purple spots | wind-up, charge |
| ruins | stone cat with a gold crescent on its brow and floating stones round it | wind-up |
| ruins_halo | the same cat plated in gold, with a ring of stones and crescents above it | wind-up |

The prompt asked for chibi proportions and big shiny eyes like the mobs, with an evolved form
that is the same body plus an obvious change, so a player who has met the first form reads
the second as its grown-up version. A guardian is judged at the size it ships at, a body of
at most 54 pixels in a 64 pixel cell: bold shapes and one bright core survive, fine detail does
not.

To change one, replace its PNG here and run
`node scripts/python.mjs -B apps/game/tools/pack_ludo_guardians.py`; `--check` (part of
`pnpm check:assets`) then confirms the committed sheets match their sources.
