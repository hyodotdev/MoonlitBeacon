#!/usr/bin/env python3
"""Deterministically draw the three terrains' structures.

Unlike decorative free tiles, structures made here pair with `Room`'s real movement-block circles.
Put four 64×64 structures on the first row of each 256×256 sheet, using only transparent pixels and
a fixed palette so they stay sharp under mobile nearest filter.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from build_warden_assets import Canvas


GAME_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = GAME_ROOT / "assets/custom/world/terrain"

RGBA = tuple[int, int, int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)
OUTLINE: RGBA = (18, 22, 30, 255)
SHADOW: RGBA = (22, 27, 38, 255)
MOON_DARK: RGBA = (50, 65, 84, 255)
MOON_MID: RGBA = (79, 105, 126, 255)
MOON_LIGHT: RGBA = (143, 182, 194, 255)
MOON_CORE: RGBA = (207, 231, 224, 255)
WOOD_DARK: RGBA = (54, 39, 42, 255)
WOOD: RGBA = (91, 65, 58, 255)
WOOD_LIGHT: RGBA = (139, 104, 76, 255)
PALE_BARK: RGBA = (172, 166, 143, 255)
THORN_DARK: RGBA = (35, 55, 47, 255)
THORN: RGBA = (57, 88, 65, 255)
THORN_LIGHT: RGBA = (95, 126, 78, 255)
GRASS_DARK: RGBA = (45, 66, 62, 255)
GRASS: RGBA = (73, 105, 81, 255)
EMBER_DARK: RGBA = (115, 48, 43, 255)
EMBER: RGBA = (210, 91, 52, 255)
EMBER_CORE: RGBA = (249, 185, 86, 255)
IRON: RGBA = (75, 73, 82, 255)
IRON_LIGHT: RGBA = (132, 125, 122, 255)


def ellipse(canvas: Canvas, cx: int, cy: int, rx: int, ry: int, color: RGBA) -> None:
    """Filled ellipse using integer pixel centers."""
    if rx <= 0 or ry <= 0:
        return
    for y in range(cy - ry, cy + ry + 1):
        for x in range(cx - rx, cx + rx + 1):
            dx = (x - cx) / rx
            dy = (y - cy) / ry
            if dx * dx + dy * dy <= 1.0:
                canvas.pixel(x, y, color)


def thick_line(
    canvas: Canvas,
    start: tuple[int, int],
    end: tuple[int, int],
    width: int,
    color: RGBA,
) -> None:
    for offset in range(-(width // 2), width // 2 + 1):
        canvas.line((start[0], start[1] + offset), (end[0], end[1] + offset), color)


def cell(sheet: Canvas, index: int) -> Canvas:
    result = Canvas(64, 64)
    _ = sheet
    _ = index
    return result


def place(sheet: Canvas, index: int, artwork: Canvas) -> None:
    sheet.blit(artwork, index * 64, 0)


def forest_sheet() -> Canvas:
    sheet = Canvas(256, 256, TRANSPARENT)

    # A fallen white birch. Roots and branches break the silhouette so it is not a plain brown log.
    art = cell(sheet, 0)
    ellipse(art, 32, 52, 27, 6, SHADOW)
    thick_line(art, (8, 43), (54, 50), 12, OUTLINE)
    thick_line(art, (9, 41), (53, 48), 8, PALE_BARK)
    thick_line(art, (18, 42), (21, 49), 2, WOOD_DARK)
    thick_line(art, (34, 45), (36, 51), 2, WOOD_DARK)
    thick_line(art, (47, 47), (49, 52), 2, WOOD_DARK)
    art.line((43, 43), (53, 31), OUTLINE)
    art.line((44, 43), (54, 31), PALE_BARK)
    art.line((17, 40), (12, 31), OUTLINE)
    art.line((18, 40), (13, 31), PALE_BARK)
    ellipse(art, 9, 43, 6, 7, OUTLINE)
    ellipse(art, 9, 43, 4, 5, WOOD)
    place(sheet, 0, art)

    # A standing stone marked with a moon motif.
    art = cell(sheet, 1)
    ellipse(art, 32, 54, 23, 6, SHADOW)
    art.polygon([(14, 49), (18, 25), (26, 12), (41, 14), (50, 31), (47, 51)], OUTLINE)
    art.polygon([(18, 47), (21, 27), (28, 16), (39, 18), (46, 32), (43, 48)], MOON_DARK)
    art.polygon([(21, 29), (29, 17), (36, 19), (29, 27)], MOON_MID)
    ellipse(art, 34, 34, 8, 10, MOON_LIGHT)
    ellipse(art, 38, 32, 7, 9, MOON_DARK)
    art.pixel(27, 22, MOON_CORE)
    place(sheet, 1, art)

    # Thorn brush tangled together to block the path.
    art = cell(sheet, 2)
    ellipse(art, 32, 54, 28, 6, SHADOW)
    for start, end in [
        ((7, 50), (22, 30)), ((15, 52), (33, 25)), ((23, 54), (43, 29)),
        ((34, 54), (56, 35)), ((50, 53), (38, 25)), ((8, 43), (55, 47)),
    ]:
        thick_line(art, start, end, 3, OUTLINE)
        art.line(start, end, THORN)
    for x, y in [(13, 42), (19, 34), (28, 39), (37, 31), (45, 42), (51, 38)]:
        art.polygon([(x, y), (x - 4, y - 3), (x - 1, y + 3)], THORN_LIGHT)
    place(sheet, 2, art)

    # A moonstone pile wrapped in roots.
    art = cell(sheet, 3)
    ellipse(art, 32, 54, 27, 7, SHADOW)
    ellipse(art, 31, 43, 23, 14, OUTLINE)
    ellipse(art, 31, 41, 20, 12, MOON_DARK)
    ellipse(art, 22, 39, 10, 7, MOON_MID)
    ellipse(art, 43, 44, 8, 7, MOON_MID)
    art.line((7, 51), (26, 45), WOOD_LIGHT)
    art.line((55, 52), (37, 45), WOOD_LIGHT)
    art.line((18, 53), (16, 44), WOOD)
    art.line((47, 53), (49, 44), WOOD)
    ellipse(art, 30, 38, 3, 3, MOON_CORE)
    place(sheet, 3, art)
    return sheet


def field_sheet() -> Canvas:
    sheet = Canvas(256, 256, TRANSPARENT)

    # A tall standing stone shaped like wind grain.
    art = cell(sheet, 0)
    ellipse(art, 32, 55, 18, 5, SHADOW)
    art.polygon([(21, 53), (24, 15), (33, 8), (43, 18), (45, 53)], OUTLINE)
    art.polygon([(25, 50), (27, 17), (33, 12), (39, 20), (41, 50)], MOON_MID)
    art.polygon([(29, 19), (33, 14), (37, 21), (33, 28)], MOON_LIGHT)
    art.line((29, 35), (38, 31), MOON_CORE)
    art.line((28, 39), (37, 35), MOON_CORE)
    place(sheet, 0, art)

    # A low crescent stone pile.
    art = cell(sheet, 1)
    ellipse(art, 32, 54, 27, 6, SHADOW)
    ellipse(art, 17, 47, 11, 9, OUTLINE)
    ellipse(art, 17, 45, 9, 7, MOON_DARK)
    ellipse(art, 34, 42, 16, 14, OUTLINE)
    ellipse(art, 34, 40, 13, 11, MOON_MID)
    ellipse(art, 49, 49, 10, 7, OUTLINE)
    ellipse(art, 49, 47, 8, 5, MOON_DARK)
    ellipse(art, 31, 37, 5, 6, MOON_LIGHT)
    ellipse(art, 35, 36, 5, 6, MOON_MID)
    place(sheet, 1, art)

    # A silver-grass mound laid over by hard wind.
    art = cell(sheet, 2)
    ellipse(art, 31, 54, 28, 6, SHADOW)
    for root_x, tip in [
        (13, (4, 27)), (18, (9, 23)), (24, (17, 20)), (30, (25, 18)),
        (36, (33, 21)), (42, (41, 25)), (49, (50, 30)), (54, (58, 34)),
    ]:
        art.line((root_x, 52), tip, OUTLINE)
        art.line((root_x + 1, 52), (tip[0] + 1, tip[1]), GRASS)
        art.polygon(
            [(tip[0], tip[1]), (tip[0] - 4, tip[1] - 2), (tip[0] + 1, tip[1] + 4)],
            GRASS,
        )
    thick_line(art, (8, 50), (55, 52), 5, GRASS_DARK)
    place(sheet, 2, art)

    # A ruined moon-observing ring.
    art = cell(sheet, 3)
    ellipse(art, 32, 55, 28, 6, SHADOW)
    ellipse(art, 31, 36, 22, 22, OUTLINE)
    ellipse(art, 31, 36, 17, 17, MOON_MID)
    ellipse(art, 31, 36, 12, 12, TRANSPARENT)
    # Silhouette broken at the upper right.
    art.polygon([(35, 8), (59, 8), (59, 31), (48, 32), (43, 21)], TRANSPARENT)
    art.polygon([(42, 42), (56, 50), (51, 56), (37, 49)], MOON_DARK)
    art.polygon([(9, 49), (19, 43), (25, 53), (18, 57)], MOON_DARK)
    place(sheet, 3, art)
    return sheet


def camp_sheet() -> Canvas:
    sheet = Canvas(256, 256, TRANSPARENT)

    # A broken beacon barricade with leftover red cloth.
    art = cell(sheet, 0)
    ellipse(art, 32, 55, 29, 6, SHADOW)
    for x in (13, 31, 49):
        thick_line(art, (x, 24), (x, 55), 7, OUTLINE)
        thick_line(art, (x, 26), (x, 53), 3, WOOD_LIGHT)
    thick_line(art, (7, 46), (57, 32), 9, OUTLINE)
    thick_line(art, (8, 44), (56, 31), 5, WOOD)
    art.polygon([(21, 31), (42, 26), (40, 39), (24, 43)], EMBER_DARK)
    art.line((24, 32), (39, 29), EMBER)
    place(sheet, 0, art)

    # A pile of iron-banded crates.
    art = cell(sheet, 1)
    ellipse(art, 32, 55, 27, 6, SHADOW)
    for x0, y0, x1, y1 in [(7, 36, 31, 54), (30, 31, 57, 54), (18, 18, 43, 36)]:
        art.rect(x0, y0, x1, y1, OUTLINE)
        art.rect(x0 + 3, y0 + 3, x1 - 3, y1 - 3, WOOD)
        art.line((x0 + 3, y0 + 3), (x1 - 3, y1 - 3), WOOD_LIGHT)
        art.line((x1 - 3, y0 + 3), (x0 + 3, y1 - 3), WOOD_DARK)
        art.rect(x0, y0 + 7, x1, y0 + 9, IRON)
    place(sheet, 1, art)

    # A supply cart with a broken wheel.
    art = cell(sheet, 2)
    ellipse(art, 32, 55, 29, 6, SHADOW)
    ellipse(art, 16, 49, 10, 10, OUTLINE)
    ellipse(art, 16, 49, 6, 6, IRON)
    ellipse(art, 49, 49, 10, 10, OUTLINE)
    ellipse(art, 49, 49, 6, 6, IRON)
    art.polygon([(9, 27), (50, 22), (56, 43), (16, 47)], OUTLINE)
    art.polygon([(13, 29), (47, 26), (51, 40), (18, 43)], WOOD)
    art.line((18, 30), (22, 42), WOOD_LIGHT)
    art.line((32, 28), (34, 41), WOOD_LIGHT)
    art.line((46, 26), (48, 39), WOOD_LIGHT)
    art.line((52, 27), (61, 17), IRON_LIGHT)
    place(sheet, 2, art)

    # A watch lantern-stone that never went out.
    art = cell(sheet, 3)
    ellipse(art, 32, 55, 22, 6, SHADOW)
    art.polygon([(17, 53), (20, 29), (27, 22), (39, 22), (46, 31), (47, 53)], OUTLINE)
    art.polygon([(21, 50), (23, 31), (29, 26), (37, 26), (42, 33), (43, 50)], IRON)
    art.rect(25, 30, 40, 45, OUTLINE)
    art.rect(28, 32, 37, 43, EMBER_DARK)
    ellipse(art, 33, 38, 4, 6, EMBER)
    ellipse(art, 33, 39, 2, 3, EMBER_CORE)
    art.line((20, 34), (46, 34), IRON_LIGHT)
    place(sheet, 3, art)
    return sheet


def expected_outputs() -> dict[Path, bytes]:
    return {
        OUTPUT_DIR / "forest_props.png": forest_sheet().to_png(),
        OUTPUT_DIR / "field_props.png": field_sheet().to_png(),
        OUTPUT_DIR / "camp_props.png": camp_sheet().to_png(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="confirm without writing that current PNG matches the deterministic output.",
    )
    args = parser.parse_args()

    stale: list[Path] = []
    for path, payload in expected_outputs().items():
        if args.check:
            if not path.exists() or path.read_bytes() != payload:
                stale.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(path.relative_to(GAME_ROOT))

    if stale:
        for path in stale:
            print(f"stale terrain asset: {path.relative_to(GAME_ROOT)}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
