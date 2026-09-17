#!/usr/bin/env python3
"""Deterministically build Moonlit Warden cute 48×64 sheets.

Output:

    assets/custom/actors/heroes/warden/walk.png      192x256
    assets/custom/actors/heroes/warden/idle.png      192x256
    assets/custom/actors/heroes/warden/portrait.png  96x96
    builds/art-review/a0-player/warden-preview.png   review zoom
"""

from __future__ import annotations

import argparse
from pathlib import Path

from chibi_kit import (
    CELL_HEIGHT,
    CELL_WIDTH,
    DIRECTIONS,
    FRAMES,
    MOON_BRIGHT,
    MOON_CORE,
    MOON_MID,
    SKIN,
    CuteHeroStyle,
    build_hero_portrait,
    build_hero_sheet,
    draw_hero_frame,
    validate_chibi_frames,
)
from pixel_canvas import RGBA, Canvas

# Name another generator used. Re-export it for compatibility.
TRANSPARENT: RGBA = (0, 0, 0, 0)
NIGHT: RGBA = (11, 14, 28, 255)
OUTLINE: RGBA = (36, 28, 54, 255)
HAIR_SHADOW: RGBA = (72, 48, 112, 255)
HAIR: RGBA = (132, 96, 188, 255)
HAIR_LIGHT: RGBA = (198, 164, 236, 255)
COAT_DARK: RGBA = (58, 72, 128, 255)
COAT_SHADOW: RGBA = (78, 94, 156, 255)
COAT: RGBA = (104, 126, 198, 255)
COAT_LIGHT: RGBA = (156, 176, 232, 255)
READABILITY_RIM: RGBA = (132, 164, 220, 255)
GOLD: RGBA = (255, 206, 92, 255)


GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
ASSET_DIR = GAME_ROOT / "assets/custom/actors/heroes/warden"
REVIEW_DIR = REPO_ROOT / "builds/art-review/a0-player"

WARDEN_STYLE = CuteHeroStyle(
    name="warden",
    hood_dark=COAT_DARK,
    hood=COAT,
    hood_light=COAT_LIGHT,
    coat_dark=COAT_DARK,
    coat=COAT,
    coat_light=COAT_LIGHT,
    hair_dark=HAIR_SHADOW,
    hair=HAIR,
    hair_light=HAIR_LIGHT,
    accent=MOON_MID,
    accent_light=MOON_BRIGHT,
    core=MOON_CORE,
    rim=READABILITY_RIM,
    motif="seed",
    max_front_width=34,
    max_side_width=28,
    max_lower_body_width=22,
)


def draw_frame(direction: int, frame: int, idle: bool) -> Canvas:
    return draw_hero_frame(WARDEN_STYLE, direction, frame, idle)


def build_sheet(idle: bool) -> Canvas:
    return build_hero_sheet(WARDEN_STYLE, idle)


def build_portrait() -> Canvas:
    return build_hero_portrait(WARDEN_STYLE)


def build_preview(walk: Canvas, idle: Canvas, portrait: Canvas) -> Canvas:
    scale = 4
    gap = 12
    margin = 16
    block_width = CELL_WIDTH * DIRECTIONS * scale
    block_height = CELL_HEIGHT * FRAMES * scale
    width = margin * 2 + block_width
    height = margin * 4 + block_height * 2 + 96 * scale
    preview = Canvas(width, height, NIGHT)
    for section, sheet in enumerate((idle, walk)):
        origin_y = margin + section * (block_height + margin)
        preview.blit_scaled(sheet, margin, origin_y, scale)
    portrait_y = margin * 3 + block_height * 2
    portrait_x = (width - 96 * scale) // 2
    preview.blit_scaled(portrait, portrait_x, portrait_y, scale)
    return preview


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="inspect without writing that production PNG matches the deterministic created result",
    )
    args = parser.parse_args()

    from pack_maple_heroes import pack_all

    pack_all(check=args.check)
    print("warden maple sheet ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
