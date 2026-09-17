# Maple-style hero sources

`pack_maple_heroes.py` reads `{front,back,left}.jpg` here and assembles
`assets/custom/actors/heroes/<id>/{idle,walk,portrait}.png`.
Right is an exact flip of left.

Sources are full-body illustrations on a magenta background. Game cells shrink
to 48×64, and the engine filter stays Nearest.

## Walk frames

If all four `walk_<facing>_<0..3>.png` files exist, that facing uses those four
frames as-is (`facing` is `left`/`back`/`front`). PNGs with alpha are used
without keying; magenta JPGs are keyed as before. The four frames share a
common bbox and scale so stride and floor alignment stay consistent between
frames.

Four-frame walk sources are made with ludo.ai Sprite Generator Animate.
Upload an idle source (`left.jpg`/`back.jpg`) as the first frame, describe a
"walk cycle", then Export → Animation Pack (transparent background, floor
aligned) and pick four plant/cross frames from the 25. For warden that was
left: 3·8·13·18, back: 4·9·19·23. Measuring leg spread (bbox width) and boot
height makes the stride timing obvious.

If there are only two PNGs, it falls back to the older path (second frame +
nudge). If none, it falls back to a substitute step that only nudges the boots
from idle.
