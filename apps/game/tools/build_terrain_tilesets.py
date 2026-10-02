#!/usr/bin/env python3
"""Recolour the shared nature sheet into one sheet per later terrain.

`nature.png` holds the trees, stumps, rocks and grass the first three terrains scatter. It has
only sixteen colours, so a new terrain does not need new drawings to look like somewhere else:
the same shapes in a different palette are enough for the *scatter*, and the four big drawn
structures in each terrain's own props sheet carry the identity.

Each map below sends every colour of the source to a colour of the new place. A map is used
instead of a hue rotation on purpose: the source's dark outlines and shadow ellipse should stay
close to what the ground under them expects, and a table lets each highlight be chosen by eye.

    python3 apps/game/tools/build_terrain_tilesets.py          # bake
    python3 apps/game/tools/build_terrain_tilesets.py --check  # is current

Output:

    assets/custom/world/terrain/frost_nature.png
    assets/custom/world/terrain/marsh_nature.png
    assets/custom/world/terrain/ruins_nature.png
"""

from __future__ import annotations

import argparse
import io
import sys
from pathlib import Path

from PIL import Image

from terrain_sheet_check import check_sheet

GAME_ROOT = Path(__file__).resolve().parents[1]
TERRAIN_DIR = GAME_ROOT / "assets/custom/world/terrain"
SOURCE = TERRAIN_DIR / "nature.png"

RGB = tuple[int, int, int]

## Source colour -> colour in each place. Comments name what the source colour is drawn as.
PALETTES: dict[str, dict[RGB, RGB]] = {
    # Icy blue pines with a near-white glint at the tip, rocks capped with snow.
    "frost": {
        (18, 25, 46): (20, 27, 52),        # outline
        (24, 34, 50): (24, 34, 56),        # ground shadow
        (26, 69, 75): (52, 82, 130),       # foliage, dark
        (37, 101, 100): (86, 124, 176),    # foliage, mid
        (64, 119, 105): (128, 164, 206),   # foliage, mid-light
        (64, 139, 128): (150, 184, 222),   # foliage, light
        (84, 145, 116): (176, 204, 236),   # foliage, highlight
        (104, 161, 130): (196, 220, 244),  # foliage, top light
        (78, 132, 153): (140, 180, 226),   # cool highlight
        (172, 224, 226): (236, 246, 255),  # glint
        (91, 67, 69): (100, 80, 84),       # bark
        (139, 98, 80): (150, 116, 104),    # bark, lit
        (42, 55, 76): (66, 80, 116),       # rock, dark
        (65, 82, 106): (98, 116, 152),     # rock, mid
        (103, 126, 148): (156, 176, 208),  # rock, lit
        (57, 47, 59): (60, 52, 72),        # stump heart
    },
    # Murky olive and moss, wet dark wood, rocks gone green.
    "marsh": {
        (18, 25, 46): (14, 26, 32),
        (24, 34, 50): (18, 32, 38),
        (26, 69, 75): (36, 58, 44),
        (37, 101, 100): (56, 84, 54),
        (64, 119, 105): (80, 106, 58),
        (64, 139, 128): (96, 120, 62),
        (84, 145, 116): (118, 140, 74),
        (104, 161, 130): (138, 152, 84),
        (78, 132, 153): (92, 132, 120),
        (172, 224, 226): (216, 232, 170),
        (91, 67, 69): (84, 64, 52),
        (139, 98, 80): (122, 96, 64),
        (42, 55, 76): (36, 58, 60),
        (65, 82, 106): (62, 84, 82),
        (103, 126, 148): (100, 130, 116),
        (57, 47, 59): (52, 50, 44),
    },
    # Dusk indigo growth and violet-grey stone, so the trees read as part of the ruin.
    "ruins": {
        (18, 25, 46): (24, 22, 40),
        (24, 34, 50): (28, 26, 44),
        (26, 69, 75): (44, 52, 74),
        (37, 101, 100): (66, 76, 104),
        (64, 119, 105): (84, 94, 126),
        (64, 139, 128): (98, 108, 140),
        (84, 145, 116): (130, 140, 176),
        (104, 161, 130): (150, 158, 186),
        (78, 132, 153): (120, 132, 170),
        (172, 224, 226): (222, 224, 244),
        (91, 67, 69): (84, 74, 86),
        (139, 98, 80): (126, 110, 116),
        (42, 55, 76): (56, 54, 80),
        (65, 82, 106): (86, 84, 112),
        (103, 126, 148): (132, 128, 158),
        (57, 47, 59): (64, 52, 70),
    },
}


def _recolour(source: Image.Image, palette: dict[RGB, RGB]) -> Image.Image:
    out = source.copy()
    pixels = out.load()
    for y in range(out.height):
        for x in range(out.width):
            red, green, blue, alpha = pixels[x, y]
            if alpha == 0:
                continue
            mapped = palette.get((red, green, blue))
            if mapped is None:
                raise SystemExit(
                    f"nature.png has a colour the palettes do not map: {(red, green, blue)}")
            pixels[x, y] = (*mapped, alpha)
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
    source = Image.open(SOURCE).convert("RGBA")
    problems: list[str] = []
    for name, palette in PALETTES.items():
        baked = _recolour(source, palette)
        target = TERRAIN_DIR / f"{name}_nature.png"
        if args.check:
            problem = check_sheet(target, baked)
            if problem is not None:
                problems.append(problem)
            continue
        target.write_bytes(_png(baked))
        print(f"wrote {target.relative_to(GAME_ROOT)}")
    if args.check:
        if problems:
            print("terrain tilesets are not what build_terrain_tilesets.py bakes:",
                  *problems, sep="\n  ")
            return 1
        print("check: terrain tilesets are current")
    return 0


if __name__ == "__main__":
    sys.exit(main())
