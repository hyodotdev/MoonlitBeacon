# Skill emblem sources

One keyed (transparent background) PNG per skill card that unlocks as cycles pass.
`tools/build_skill_icons.py` fits them to the 48x48 emblems under `assets/custom/ui/icons/`.

**Drawn with ChatGPT's image generator on 2026-09-29**: the first six as one 3 x 2 grid on flat
magenta, shown the sixteen existing emblems so the style matches, and cut apart with
`tools/cut_lineup.py --rows 2`; the last three as one row of three, the same way, cut with
`--rows 1`. The raw grids are not in git (`_asset_sources/chatgpt_icons_2026-09-29/`).

| Skill | Emblem |
| --- | --- |
| lantern_familiar | a round paper lantern with two glowing eyes, a flame on top and two sparkles circling it |
| moon_ward | a golden crescent inside a soft blue-white bubble |
| comet_call | a golden-white comet with a long fiery tail |
| star_magnet | a gold-tipped horseshoe magnet pulling small stars in |
| thorn_bloom | a dark rose with gold-edged petals in thorny vines |
| second_light | a bright flame rising inside a golden heart-shaped halo |
| moon_burst | a golden crescent inside a bright ring of light with rays and sparkles flying out |
| winter_bell | a silver-blue bell with a golden clapper, a snowflake and two ice crystals |
| comet_trail | a gold-white comet dashing sideways, three glowing round marks trailing behind it |

To change one, replace its PNG here and run
`node scripts/python.mjs -B apps/game/tools/build_skill_icons.py`.
