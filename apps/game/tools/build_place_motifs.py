#!/usr/bin/env python3
"""Deterministically draw the six place-memory motifs and the settlement window.

Each terrain keeps one small concrete memory in the world: trail ribbons, wind
chimes, a camp kettle, a signal bell, a paper boat, a signal lens. The motif
stands near its beacon clearing, dim while the beacon is out and lit once it
burns. The window answers Nari's opening message on the result screen: lit on
an official win, dim on an early return, hidden on defeat.

    python3 apps/game/tools/build_place_motifs.py          # bake
    python3 apps/game/tools/build_place_motifs.py --check  # is current

Output:

    assets/custom/world/places/motifs.png  192x64, six 32x32 cells by terrain,
                                           dim row then lit row
    assets/custom/world/places/window.png  64x32, two 32x32 cells, dim then lit

Only integer coords and a fixed palette, so any machine yields the same bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

from pixel_canvas import RGBA, Canvas

GAME_ROOT = Path(__file__).resolve().parents[1]
PLACES_DIR = GAME_ROOT / "assets/custom/world/places"

CELL = 32
TERRAINS = ["forest", "field", "camp", "frost", "marsh", "ruins"]

TRANSPARENT: RGBA = (0, 0, 0, 0)
OUTLINE: RGBA = (18, 25, 46, 255)
WOOD_DARK: RGBA = (57, 47, 59, 255)
WOOD: RGBA = (91, 67, 69, 255)
WOOD_LIGHT: RGBA = (139, 98, 80, 255)
SLATE_DARK: RGBA = (42, 55, 76, 255)
SLATE: RGBA = (65, 82, 106, 255)
SLATE_LIGHT: RGBA = (103, 126, 148, 255)
IRON: RGBA = (71, 76, 94, 255)
IRON_LIGHT: RGBA = (119, 127, 143, 255)
DIM_DARK: RGBA = (48, 60, 88, 255)
DIM: RGBA = (86, 98, 128, 255)
DIM_LIGHT: RGBA = (120, 134, 160, 255)
MOON: RGBA = (114, 190, 199, 255)
MOON_LIGHT: RGBA = (172, 224, 226, 255)
MOON_CORE: RGBA = (229, 247, 238, 255)
CORAL: RGBA = (226, 83, 52, 255)
CORAL_LIGHT: RGBA = (255, 151, 67, 255)
GOLD: RGBA = (255, 206, 92, 255)
EMBER_CORE: RGBA = (255, 225, 136, 255)
SNOW: RGBA = (196, 220, 244, 255)
SNOW_DARK: RGBA = (150, 184, 222, 255)
LEAF: RGBA = (64, 139, 128, 255)
LEAF_DARK: RGBA = (37, 101, 100, 255)
PAPER: RGBA = (255, 236, 180, 255)
PAPER_FOLD: RGBA = (255, 206, 140, 255)


## Light dots are drawn after the silhouette outline, so they read as glow
## instead of growing a dark rim of their own.
_EMIT_SPARKLE = True
_SPARKLE_COLORS = {MOON_LIGHT[:3], MOON_CORE[:3]}


def _sparkle(canvas: Canvas, dots: list[tuple[int, int]], color: RGBA) -> None:
    if not _EMIT_SPARKLE:
        return
    for x, y in dots:
        canvas.pixel(x, y, color)


def _draw_forest(canvas: Canvas, lit: bool) -> None:
    ribbon_a = CORAL if lit else DIM
    ribbon_b = CORAL_LIGHT if lit else DIM_LIGHT
    post = WOOD if lit else DIM_DARK
    canvas.rect(14, 12, 17, 27, post)
    canvas.rect(13, 10, 18, 12, WOOD_DARK if lit else DIM_DARK)
    canvas.polygon([(14, 13), (6, 16), (7, 20), (14, 17)], ribbon_a)
    canvas.polygon([(17, 13), (25, 15), (24, 19), (17, 17)], ribbon_b)
    canvas.disc(15, 13, 2, ribbon_a)
    if lit:
        _sparkle(canvas, [(6, 22), (25, 21), (10, 24)], MOON_LIGHT)


def _draw_field(canvas: Canvas, lit: bool) -> None:
    pole = WOOD if lit else DIM_DARK
    bar = WOOD_DARK if lit else DIM_DARK
    chime = GOLD if lit else DIM
    canvas.rect(15, 8, 16, 27, pole)
    canvas.rect(9, 9, 22, 10, bar)
    canvas.line((11, 10), (11, 14), chime)
    canvas.line((16, 10), (16, 16), chime)
    canvas.line((21, 10), (21, 14), chime)
    canvas.rect(10, 14, 12, 18, chime)
    canvas.rect(15, 16, 17, 21, chime)
    canvas.rect(20, 14, 22, 18, chime)
    canvas.pixel(11, 19, EMBER_CORE if lit else DIM_LIGHT)
    canvas.pixel(16, 22, EMBER_CORE if lit else DIM_LIGHT)
    canvas.pixel(21, 19, EMBER_CORE if lit else DIM_LIGHT)
    if lit:
        _sparkle(canvas, [(7, 21), (24, 20), (16, 25)], MOON_LIGHT)


def _draw_camp(canvas: Canvas, lit: bool) -> None:
    stone = SLATE if lit else DIM_DARK
    body = IRON if lit else DIM_DARK
    trim = IRON_LIGHT if lit else DIM
    fire = CORAL if lit else DIM_DARK
    coal = EMBER_CORE if lit else DIM
    canvas.disc(10, 25, 3, stone)
    canvas.disc(22, 25, 3, stone)
    canvas.polygon([(12, 27), (16, 22), (20, 27)], fire)
    canvas.polygon([(14, 27), (16, 24), (18, 27)], coal)
    canvas.ellipse(16, 20, 6, 4, body)
    canvas.rect(13, 15, 19, 17, trim)
    canvas.line((13, 20), (13, 16), trim)
    canvas.line((13, 16), (19, 16), trim)
    canvas.line((19, 16), (19, 20), trim)
    canvas.line((21, 20), (24, 17), body)
    if lit:
        _sparkle(canvas, [(24, 14), (25, 11), (9, 15)], MOON_LIGHT)


def _draw_frost(canvas: Canvas, lit: bool) -> None:
    post = SNOW if lit else DIM
    shade = SNOW_DARK if lit else DIM_DARK
    bell = GOLD if lit else DIM
    canvas.rect(14, 10, 17, 27, post)
    canvas.rect(16, 10, 17, 27, shade)
    canvas.ellipse(15, 9, 4, 2, MOON_CORE if lit else DIM_LIGHT)
    canvas.rect(17, 11, 24, 12, shade)
    canvas.polygon([(19, 13), (25, 13), (23, 20), (21, 20)], bell)
    canvas.pixel(22, 21, CORAL_LIGHT if lit else DIM_DARK)
    if lit:
        _sparkle(canvas, [(15, 14), (16, 11), (28, 14), (29, 11)], MOON_LIGHT)


def _draw_marsh(canvas: Canvas, lit: bool) -> None:
    water = LEAF_DARK if lit else DIM_DARK
    reed = LEAF if lit else DIM
    hull = PAPER if lit else DIM_LIGHT
    fold = PAPER_FOLD if lit else DIM
    canvas.ellipse(16, 26, 10, 3, water)
    canvas.line((7, 26), (6, 18), reed)
    canvas.line((25, 26), (26, 17), reed)
    canvas.pixel(6, 17, MOON_CORE if lit else DIM_LIGHT)
    canvas.pixel(26, 16, MOON_CORE if lit else DIM_LIGHT)
    canvas.polygon(
        [(9, 22), (13, 16), (16, 21), (19, 16), (23, 22), (19, 26), (13, 26)],
        hull,
    )
    canvas.line((16, 21), (16, 26), fold)
    if lit:
        _sparkle(canvas, [(16, 13), (11, 12), (22, 12)], MOON_LIGHT)


def _draw_ruins(canvas: Canvas, lit: bool) -> None:
    stone = SLATE if lit else DIM_DARK
    dark = SLATE_DARK if lit else DIM_DARK
    lens = MOON if lit else DIM_DARK
    canvas.rect(10, 25, 22, 27, dark)
    canvas.ring(16, 18, 8, 2, stone)
    canvas.ring(16, 18, 8, 1, SLATE_LIGHT if lit else DIM)
    canvas.disc(16, 18, 4, lens)
    canvas.pixel(10, 13, dark)
    canvas.pixel(22, 13, dark)
    if lit:
        canvas.pixel(15, 17, MOON_CORE)
        _sparkle(canvas, [(16, 7), (7, 18), (25, 18)], MOON_LIGHT)


def _draw_window(canvas: Canvas, lit: bool) -> None:
    glass = EMBER_CORE if lit else SLATE_DARK
    canvas.rect(6, 6, 26, 26, WOOD if lit else DIM_DARK)
    canvas.rect(9, 9, 23, 23, glass)
    canvas.line((16, 9), (16, 23), WOOD_DARK if lit else DIM_DARK)
    canvas.line((9, 16), (23, 16), WOOD_DARK if lit else DIM_DARK)
    canvas.rect(5, 26, 27, 28, WOOD_DARK if lit else DIM_DARK)
    if lit:
        canvas.disc(16, 16, 3, CORAL_LIGHT)
        canvas.pixel(16, 16, MOON_CORE)
        _sparkle(canvas, [(4, 10), (28, 10)], MOON_LIGHT)
    else:
        canvas.pixel(12, 12, MOON_LIGHT)
        canvas.pixel(20, 11, DIM_LIGHT)


_DRAW = {
    "forest": _draw_forest,
    "field": _draw_field,
    "camp": _draw_camp,
    "frost": _draw_frost,
    "marsh": _draw_marsh,
    "ruins": _draw_ruins,
}


def _cell(draw, lit: bool) -> Canvas:
    global _EMIT_SPARKLE
    _EMIT_SPARKLE = False
    canvas = Canvas(CELL, CELL)
    draw(canvas, lit)
    canvas.outline_opaque(OUTLINE)
    if lit:
        # Second pass: only the glow dots a transparent pixel is missing.
        _EMIT_SPARKLE = True
        fresh = Canvas(CELL, CELL)
        draw(fresh, True)
        for y in range(CELL):
            for x in range(CELL):
                glow = fresh.get(x, y)
                if glow[3] > 0 and glow[:3] in _SPARKLE_COLORS \
                        and canvas.get(x, y)[3] == 0:
                    canvas.pixel(x, y, glow)
    _EMIT_SPARKLE = True
    return canvas


def build_motifs() -> Canvas:
    sheet = Canvas(CELL * len(TERRAINS), CELL * 2)
    for column, terrain in enumerate(TERRAINS):
        sheet.blit(_cell(_DRAW[terrain], False), column * CELL, 0)
        sheet.blit(_cell(_DRAW[terrain], True), column * CELL, CELL)
    return sheet


def build_window() -> Canvas:
    sheet = Canvas(CELL * 2, CELL)
    sheet.blit(_cell(_draw_window, False), 0, 0)
    sheet.blit(_cell(_draw_window, True), CELL, 0)
    return sheet


def expected_outputs() -> dict[Path, bytes]:
    return {
        PLACES_DIR / "motifs.png": build_motifs().to_png(),
        PLACES_DIR / "window.png": build_window().to_png(),
    }


def validate_contracts(outputs: dict[Path, bytes]) -> None:
    expected_sizes = {
        "motifs.png": (CELL * len(TERRAINS), CELL * 2),
        "window.png": (CELL * 2, CELL),
    }
    if set(expected_sizes) != {p.name for p in outputs}:
        raise RuntimeError("output file set and canvas contract set differ")
    for path, _payload in outputs.items():
        width, height = expected_sizes[path.name]
        canvas = build_motifs() if path.name == "motifs.png" else build_window()
        if (canvas.width, canvas.height) != (width, height):
            raise RuntimeError(f"{path.name}: size contract broken")
        for y in range(0, height, CELL):
            for x in range(0, width, CELL):
                visible = any(
                    canvas.get(px, py)[3] > 0
                    for py in range(y, y + CELL)
                    for px in range(x, x + CELL)
                )
                if not visible:
                    raise RuntimeError(f"{path.name}: empty cell at {(x, y)}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="confirm without writing that current PNG matches the deterministic output.",
    )
    args = parser.parse_args()
    outputs = expected_outputs()
    validate_contracts(outputs)
    stale: list[Path] = []
    for path, payload in outputs.items():
        digest = hashlib.sha256(payload).hexdigest()
        shown = path.relative_to(GAME_ROOT)
        if args.check:
            if not path.exists() or path.read_bytes() != payload:
                stale.append(path)
                print(f"stale place asset: {shown}")
            else:
                print(f"OK {shown} sha256={digest}")
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(f"{shown} sha256={digest}")
    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
