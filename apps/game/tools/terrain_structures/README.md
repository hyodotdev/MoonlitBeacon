# Terrain structure sources

Twelve keyed (transparent background) PNGs, four for each of the later places, drawn with
ChatGPT's image generator on 2026-09-29 as one 4x3 grid on flat magenta and cut apart with

    python3 apps/game/tools/cut_lineup.py --rows 3 --gap 5 grid.png apps/game/tools/terrain_structures \
        frost_crystals frost_snowman frost_lantern frost_log \
        marsh_mushrooms marsh_log marsh_jar marsh_frog \
        ruins_pillar ruins_altar ruins_arch ruins_menhir

The raw grid is not in git (`_asset_sources/terrain_structures/`).

| Place | Sources, in the order they sit on the sheet |
| --- | --- |
| Frost Pass | ice-crystal cluster, scarfed snowman, snow-capped stone lantern, frozen hollow log |
| Mirewood Marsh | glowing mushrooms, mossy log with reeds, wisp jar on a post, mossy frog statue |
| Moonlit Ruins | broken pillar, moon altar, crumbling arch, glowing menhir |

`tools/pack_terrain_structures.py` packs each place's four into a 256x256 obstacle sheet (four
64x64 cells on the first row, contact shadow at y=61, at most 56 colours, binary alpha) under
`assets/custom/world/terrain/<place>_props.png`. To change one, replace its PNG here and run

    node scripts/python.mjs -B apps/game/tools/pack_terrain_structures.py

`--check` confirms the committed sheets match their sources.
