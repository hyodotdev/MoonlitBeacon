#!/usr/bin/env python3
"""Bake the obstacle sheets of the three later terrains from twelve drawn structures.

The first three terrains draw their structures in code (`build_terrain_obstacles.py`). Frost
Pass, Mirewood Marsh and Moonlit Ruins are richer, so their structures are drawn as one
ChatGPT grid on flat magenta, cut apart by `cut_lineup.py` into `tools/terrain_structures/`
(see the README there), and packed here into the same sheet shape `Room` already reads:
a 256x256 sheet, four 64x64 cells on the first row, feet near y=50.

    python3 apps/game/tools/pack_terrain_structures.py          # bake
    python3 apps/game/tools/pack_terrain_structures.py --check  # is current

The contract wants binary alpha and at most 64 colors per sheet, so each cell is downscaled with
a filter, alpha is thresholded, and the four structures are clustered to a shared palette.
Each drawing keeps its own baked contact shadow, like the structures it stands beside.
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

from PIL import Image

GAME_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = Path(__file__).resolve().parent / "terrain_structures"
OUT_ROOT = GAME_ROOT / "assets/custom/world/terrain"

CELL = 64
SHEET = 256
## Erase pixels fainter than this: the contract is binary alpha.
ALPHA_CUT = 128
## The contract cap is 64 colors a sheet. Leave room for the alpha edge.
MAX_COLORS = 56
## Room a drawing may fill inside its cell. The bottom of the contact shadow sits at `FLOOR`,
## which is where the existing structures stand (feet at y=50, shadow just below).
BOX_W = 60
BOX_H = 55
FLOOR = 61

SHEETS: dict[str, tuple[str, str, str, str]] = {
    "frost": ("frost_crystals", "frost_snowman", "frost_lantern", "frost_log"),
    "marsh": ("marsh_mushrooms", "marsh_log", "marsh_jar", "marsh_frog"),
    "ruins": ("ruins_pillar", "ruins_altar", "ruins_arch", "ruins_menhir"),
}


def _fit(source: Image.Image) -> Image.Image:
    art = source.convert("RGBA")
    art.putalpha(art.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0))
    box = art.getbbox()
    if box is None:
        raise RuntimeError("empty source")
    art = art.crop(box)
    scale = min(BOX_W / art.width, BOX_H / art.height)
    size = (max(1, round(art.width * scale)), max(1, round(art.height * scale)))
    art = art.resize(size, Image.LANCZOS)
    art.putalpha(art.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0))
    return art


def _bake(names: tuple[str, ...]) -> Image.Image:
    sheet = Image.new("RGBA", (SHEET, SHEET), (0, 0, 0, 0))
    for index, name in enumerate(names):
        art = _fit(Image.open(SOURCE_ROOT / f"{name}.png"))
        x = index * CELL + (CELL - art.width) // 2
        y = FLOOR - art.height
        sheet.alpha_composite(art, (x, y))
    alpha = sheet.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    flat = sheet.convert("RGB").quantize(
        colors=MAX_COLORS, method=Image.MEDIANCUT, dither=Image.NONE)
    out = flat.convert("RGBA")
    out.putalpha(alpha)
    # Clear the colour under transparent pixels so a later resize never bleeds a hue in.
    pixels = out.load()
    for y in range(out.height):
        for x in range(out.width):
            if pixels[x, y][3] == 0:
                pixels[x, y] = (0, 0, 0, 0)
    return out


def _png(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if the sheets on disk differ from what this tool bakes")
    args = parser.parse_args()
    problems: list[str] = []
    for terrain, names in SHEETS.items():
        payload = _png(_bake(names))
        target = OUT_ROOT / f"{terrain}_props.png"
        if args.check:
            if not target.exists():
                problems.append(f"missing {target.name}")
            elif target.read_bytes() != payload:
                problems.append(f"out of date {target.name}")
            continue
        target.write_bytes(payload)
        print(f"wrote {target.relative_to(GAME_ROOT)}")
    if args.check:
        if problems:
            print("terrain structure sheets are not what pack_terrain_structures.py bakes:",
                  *problems, sep="\n  ")
            return 1
        print("check: terrain structure sheets are current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
