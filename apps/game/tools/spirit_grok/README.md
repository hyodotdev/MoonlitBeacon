# Spirit sources

One front-view, keyed (transparent background) PNG per normal enemy. `tools/pack_grok_spirits.py`
turns them into the 192x192 sheets under `assets/custom/actors/spirits/`.

The folder name is historical: the first set was drawn with Grok. **The current set was
drawn with ChatGPT's image generator on 2026-09-29**, as one lineup of seven creatures on
flat magenta, and cut apart with `tools/cut_lineup.py`. The raw lineups are not in
git (`_asset_sources/chatgpt_spirits_2026-09-29/`); the old Grok sources are in git history.

| Kind | Design | Role (unchanged) |
| --- | --- | --- |
| wisp | cloud puff with a curl on top | default chase |
| drifter | sleepy leaf moth | high-inertia float |
| ember | round flame spirit | fast chase |
| caster | mushroom-cap mage with a lantern staff | keep-distance fire |
| weaver | jellyfish trailing glowing threads | orbit around the player |
| stalker | shy cat-bat with big ears | straight charge |
| swarm | fluffy dandelion-puff pup | weak, fast cluster |

The prompt asked for chibi proportions, big shiny eyes, chunky pixel art with a one-pixel
outline and three-tone shading, and **silhouettes that differ from each other and from a
plain ghost**, while keeping each creature's colour and role. A design is judged at the
size it ships at, 15 to 24 pixels tall: bold shapes and a big face survive, fine detail
does not.

To change one creature, replace its PNG here and run
`node scripts/python.mjs -B apps/game/tools/pack_grok_spirits.py`; `--check` (part of
`pnpm check:assets`) then confirms the committed sheet matches its source.
