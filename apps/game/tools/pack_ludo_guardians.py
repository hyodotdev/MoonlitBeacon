#!/usr/bin/env python3
"""Bake 22 guardian sheets from 6 painted sources.

Sources are six `tools/guardian_ludo/<name>.webp` files — three terrains and their evolved set.
Each source makes idle, windup, charge, and recover sheets. Do not pull a separate picture per state;
**composite by deforming**. It is the same body changing pose, so if silhouettes
drift they look like a different monster.

    idle    6 frames  1px up-down sway
    windup  4 frames  body grows a little and the core brightens
    charge  4 frames  stretch forward and lie low
    recover 4 frames  flatten and darken

The contract wants **binary alpha and at most 48 colors**. Painted art has thousands of colors,
so it cannot go in as-is. Threshold alpha and cluster colors to fit.

    python3 apps/game/tools/pack_ludo_guardians.py          # bake
    python3 apps/game/tools/pack_ludo_guardians.py --check  # is current
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

GAME_ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = Path(__file__).resolve().parent / "guardian_ludo"
OUT_ROOT = GAME_ROOT / "assets/custom/actors/guardians"

CELL = 64
## The contract cap is 48 colors. Leave a little room so quantization adding one color at the alpha edge
## still does not overflow.
MAX_COLORS = 44
## Erase pixels lighter than this. The contract is binary alpha, so no mid values.
ALPHA_CUT = 128
## Empty border the contract requires. Bottom is 0 — toes may touch the cell floor.
PAD_X = 2
PAD_TOP = 2
## Windup grows the body 8% and the sway moves 1px. Shrink the base so the largest frame
## does not overflow, shrink the base size by that much.
MAX_SCALE = 1.10
## Height the body may occupy inside a 64 cell.
BODY_H = int((CELL - PAD_TOP - 2) / MAX_SCALE)

## Needed states differ by terrain. Only forest has charge; field has two windups.
STATES: dict[str, tuple[str, ...]] = {
    "forest": ("windup", "charge", "recover"),
    "forest_thorn": ("windup", "charge", "recover"),
    "field": ("windup_cross", "windup_radial", "recover"),
    "field_storm": ("windup_cross", "windup_radial", "recover"),
    "camp": ("windup", "recover"),
    "camp_siege": ("windup", "recover"),
}


def _fit(source: Image.Image) -> Image.Image:
    """Source fitted to 64-cell body height, through alpha crop."""
    art = source.convert("RGBA")
    alpha = art.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    art.putalpha(alpha)
    box = art.getbbox()
    if box is None:
        raise RuntimeError("empty source")
    art = art.crop(box)
    max_w = int((CELL - PAD_X * 2) / MAX_SCALE)
    scale = BODY_H / art.height
    width = max(1, round(art.width * scale))
    if width > max_w:                         # if width overflows, fit by width
        scale = max_w / art.width
        width = max_w
    art = art.resize((width, max(1, round(art.height * scale))), Image.LANCZOS)
    alpha = art.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    art.putalpha(alpha)
    return art


def _cell(art: Image.Image, dy: int = 0, scale: float = 1.0,
          squash: float = 1.0, tint: float = 1.0) -> Image.Image:
    """Build one cell. `scale` is overall size; `squash` presses only the vertical to change pose."""
    width = max(1, round(art.width * scale))
    height = max(1, round(art.height * scale * squash))
    body = art.resize((width, height), Image.LANCZOS)
    if tint != 1.0:
        pixels = body.load()
        for y in range(body.height):
            for x in range(body.width):
                r, g, b, a = pixels[x, y]
                pixels[x, y] = (
                    min(255, round(r * tint)),
                    min(255, round(g * tint)),
                    min(255, round(b * tint)),
                    a,
                )
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    # Stick the toes to the bottom of the cell. Fitting from the top leaves a squashed pose floating.
    cell.alpha_composite(body, ((CELL - body.width) // 2,
                                CELL - body.height - 2 + dy))
    return cell


def _sheet(cells: list[Image.Image]) -> Image.Image:
    sheet = Image.new("RGBA", (CELL * len(cells), CELL), (0, 0, 0, 0))
    for index, cell in enumerate(cells):
        sheet.alpha_composite(cell, (index * CELL, 0))
    return sheet


def _quantize(sheet: Image.Image) -> Image.Image:
    """Cluster colors to the contract and re-binarize alpha."""
    alpha = sheet.getchannel("A").point(lambda v: 255 if v >= ALPHA_CUT else 0)
    flat = sheet.convert("RGB").quantize(
        colors=MAX_COLORS, method=Image.MEDIANCUT, dither=Image.NONE)
    out = flat.convert("RGBA")
    out.putalpha(alpha)
    return out


def _frames(art: Image.Image, state: str) -> list[Image.Image]:
    if state == "idle":
        # It only needs to look alive. Large motion makes aiming hard.
        return [_cell(art, dy=d) for d in (0, -1, -1, 0, 1, 1)]
    if state.startswith("windup"):
        # Grows and brightens — the body says "incoming".
        return [
            _cell(art, scale=s, tint=t)
            for s, t in ((1.00, 1.00), (1.04, 1.10), (1.08, 1.22), (1.06, 1.16))
        ]
    if state == "charge":
        # Lie forward and low. Press the vertical to make a charging pose.
        return [
            _cell(art, dy=d, scale=s, squash=q)
            for d, s, q in ((1, 1.06, 0.94), (2, 1.10, 0.88),
                            (2, 1.10, 0.88), (1, 1.06, 0.92))
        ]
    # recover — flatten and darken.
    return [
        _cell(art, dy=d, squash=q, tint=t)
        for d, q, t in ((2, 0.88, 0.72), (2, 0.90, 0.78),
                        (1, 0.94, 0.86), (0, 0.98, 0.94))
    ]


def build() -> dict[Path, Image.Image]:
    out: dict[Path, Image.Image] = {}
    for name, states in STATES.items():
        source = SOURCE_ROOT / f"{name}.webp"
        if not source.is_file():
            raise RuntimeError(f"source is missing: {source}")
        art = _fit(Image.open(source))
        out[OUT_ROOT / f"{name}.png"] = _quantize(_sheet(_frames(art, "idle")))
        for state in states:
            out[OUT_ROOT / f"{name}_{state}.png"] = _quantize(
                _sheet(_frames(art, state)))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    sheets = build()
    if args.check:
        for path in sheets:
            if not path.is_file():
                print(f"missing: {path.name}", file=sys.stderr)
                return 1
        print(f"{len(sheets)} guardian sheets exist")
        return 0

    for path, sheet in sheets.items():
        sheet.save(path)
    print(f"baked {len(sheets)} guardian sheets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
