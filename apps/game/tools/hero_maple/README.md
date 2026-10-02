# Hero sources

`pack_maple_heroes.py` reads the transparent PNGs here and assembles
`assets/custom/actors/heroes/<id>/{idle,walk,portrait}.png`. Right is an exact flip of
left.

The folder name is historical: the first set was Maple-style art. **The current set was
drawn with ChatGPT's image generator on 2026-09-29.** The raw pictures are not in git
(`_asset_sources/chatgpt_heroes_2026-09-29/`); the old sources are in git history.

| Hero | Design |
| --- | --- |
| warden | violet hood with a crescent pin, holding a lit beacon candle |
| dancer | pink bob with a mint ribbon, crescent blades at both hands |
| keeper | green hooded cloak, a glowing lantern held in front |
| knight | silver helmet with a crescent crest, white cape, sword |
| eclipse | black hood with a red rim, a red orb held in front |
| sage | teal star-hood with a gold staff and two floating orbs |

## How they were made

Each view is one picture of all six heroes on flat magenta, because a generator keeps six
characters in one style far better in a single image than in six. The front view was drawn
first and approved; the back and left views were drawn from it, so the designs match.

| File | Source picture | Cut with |
| --- | --- | --- |
| `<hero>/front.png` | one row of six | `cut_lineup.py lineup.png out warden dancer keeper knight eclipse sage` |
| `<hero>/back.png`, `<hero>/left.png` | one row of six each | the same |
| `<hero>/walk_<facing>_<0..3>.png` | a 6 x 4 grid, one row per hero, four walk frames | `cut_lineup.py --rows 6 --frames 4 grid.png out warden_0 warden_1 … sage_3` |

The four frames of a walk are: contact with one foot forward, passing pose with the feet
together, contact with the other foot forward, passing pose again. `--frames 4` cuts the four
of one hero onto one shared canvas with the feet on the same baseline, so a walk keeps its
stride and does not jitter. The front grid needed `--gap 3`, because the hero above and the
hero below stand close together in it.

The game shrinks these to a 48 x 64 cell with a hero about 36 pixels tall, and the engine
filter stays Nearest, so a design is judged there: a big face, a bold silhouette and one bright prop
survive, fine cloth detail does not.

## What the packer does

- Fits each view to 36 pixels tall, feet on the cell floor, binary alpha.
- Uses the four `walk_<facing>_<0..3>.png` frames of a facing as they are, on one shared scale
  and bounding box; on the left view each frame is also centred so the body does not slide.
- With only two frames for a facing it falls back to the second frame plus a nudge, and with
  none it only shifts the boots of the standing view.
- Idle is the standing view with a small brightness pulse; the portrait is the head of the
  front view on a 96 x 96 canvas.

To change one hero, replace its PNGs here and run
`node scripts/python.mjs -B apps/game/tools/pack_maple_heroes.py`. Run
`pnpm check:assets` afterwards: it checks the sheets against the asset contract.
