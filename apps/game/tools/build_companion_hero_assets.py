#!/usr/bin/env python3
"""Deterministically build cute 48×64 sheets and the boot splash for the five paid heroes."""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

from build_warden_assets import (
    COAT,
    COAT_DARK,
    COAT_LIGHT,
    build_portrait as build_warden_portrait,
    build_sheet as build_warden_sheet,
)
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


GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
HERO_ROOT = GAME_ROOT / "assets/custom/actors/heroes"
REVIEW_DIR = REPO_ROOT / "builds/art-review/a0-player"

D_HAIR: RGBA = (128, 52, 108, 255)
D_HAIR_LIGHT: RGBA = (188, 92, 140, 255)
D_CLOTH_DARK: RGBA = (78, 36, 86, 255)
D_CLOTH: RGBA = (148, 64, 118, 255)
D_CLOTH_LIGHT: RGBA = (214, 118, 164, 255)
D_PETAL: RGBA = (255, 168, 196, 255)
D_MINT: RGBA = (56, 186, 148, 255)
D_MINT_LIGHT: RGBA = (156, 236, 204, 255)

K_HAIR: RGBA = (48, 68, 56, 255)
K_HAIR_LIGHT: RGBA = (86, 112, 92, 255)
K_HOOD_DARK: RGBA = (28, 56, 46, 255)
K_HOOD: RGBA = (52, 92, 70, 255)
K_HOOD_LIGHT: RGBA = (96, 142, 108, 255)
K_COAT_DARK: RGBA = (32, 64, 52, 255)
K_COAT: RGBA = (62, 108, 80, 255)
K_COAT_LIGHT: RGBA = (108, 152, 116, 255)
K_AMBER: RGBA = (255, 176, 72, 255)
K_AMBER_CORE: RGBA = (255, 228, 140, 255)

N_HAIR: RGBA = (156, 158, 196, 255)
N_HAIR_DARK: RGBA = (78, 80, 118, 255)
N_HOOD: RGBA = (176, 190, 214, 255)
N_HOOD_DARK: RGBA = (80, 94, 128, 255)
N_HOOD_LIGHT: RGBA = (244, 246, 242, 255)
N_COAT: RGBA = (154, 170, 202, 255)
N_COAT_DARK: RGBA = (66, 80, 114, 255)
N_COAT_LIGHT: RGBA = (230, 236, 238, 255)
N_BLUE: RGBA = (96, 176, 232, 255)
N_BLUE_LIGHT: RGBA = (198, 234, 255, 255)

E_HAIR: RGBA = (78, 32, 56, 255)
E_HAIR_DARK: RGBA = (36, 18, 36, 255)
E_HOOD: RGBA = (132, 24, 48, 255)
E_HOOD_DARK: RGBA = (40, 16, 32, 255)
E_HOOD_LIGHT: RGBA = (228, 40, 58, 255)
E_COAT: RGBA = (102, 22, 42, 255)
E_COAT_DARK: RGBA = (32, 16, 30, 255)
E_COAT_LIGHT: RGBA = (198, 34, 50, 255)
E_RED: RGBA = (255, 56, 56, 255)
E_RED_LIGHT: RGBA = (255, 132, 78, 255)
E_CORE: RGBA = (18, 12, 28, 255)

S_HAIR: RGBA = (82, 64, 118, 255)
S_HAIR_DARK: RGBA = (40, 36, 74, 255)
S_HOOD: RGBA = (16, 142, 150, 255)
S_HOOD_DARK: RGBA = (10, 64, 78, 255)
S_HOOD_LIGHT: RGBA = (64, 216, 196, 255)
S_COAT: RGBA = (20, 116, 128, 255)
S_COAT_DARK: RGBA = (10, 56, 68, 255)
S_COAT_LIGHT: RGBA = (56, 186, 172, 255)
S_GOLD: RGBA = (255, 196, 58, 255)
S_GOLD_LIGHT: RGBA = (255, 232, 132, 255)

SPLASH_NIGHT: RGBA = (6, 12, 24, 255)
SPLASH_NIGHT_LIGHT: RGBA = (48, 78, 112, 255)

DANCER_STYLE = CuteHeroStyle(
    "dancer", D_CLOTH_DARK, D_CLOTH, D_CLOTH_LIGHT,
    D_CLOTH_DARK, D_CLOTH, D_PETAL, D_HAIR, D_HAIR, D_HAIR_LIGHT,
    D_MINT, D_MINT_LIGHT, MOON_CORE, (168, 120, 188, 255), "crescent",
    36, 28, 24,
)
KEEPER_STYLE = CuteHeroStyle(
    "keeper", K_HOOD_DARK, K_HOOD, K_HOOD_LIGHT,
    K_COAT_DARK, K_COAT, K_COAT_LIGHT, K_HAIR, K_HAIR, K_HAIR_LIGHT,
    K_AMBER, K_AMBER_CORE, MOON_CORE, (112, 168, 156, 255), "lantern",
    36, 28, 24,
)
KNIGHT_STYLE = CuteHeroStyle(
    "knight", N_HOOD_DARK, N_HOOD, N_HOOD_LIGHT,
    N_COAT_DARK, N_COAT, N_COAT_LIGHT, N_HAIR_DARK, N_HAIR, N_HOOD_LIGHT,
    N_BLUE, N_BLUE_LIGHT, MOON_CORE, (180, 198, 220, 255), "silver",
    36, 28, 24,
)
ECLIPSE_STYLE = CuteHeroStyle(
    "eclipse", E_HOOD_DARK, E_HOOD, E_HOOD_LIGHT,
    E_COAT_DARK, E_COAT, E_COAT_LIGHT, E_HAIR_DARK, E_HAIR, E_HOOD_LIGHT,
    E_RED, E_RED_LIGHT, E_CORE, (186, 96, 176, 255), "eclipse",
    36, 28, 24,
)
SAGE_STYLE = CuteHeroStyle(
    "sage", S_HOOD_DARK, S_HOOD, S_HOOD_LIGHT,
    S_COAT_DARK, S_COAT, S_COAT_LIGHT, S_HAIR_DARK, S_HAIR, S_HOOD_LIGHT,
    S_GOLD, S_GOLD_LIGHT, MOON_CORE, (88, 196, 188, 255), "stars",
    36, 28, 24,
)


@dataclass(frozen=True)
class HeroArt:
    name: str
    style: CuteHeroStyle
    light_colors: tuple[RGBA, ...]


def draw_dancer_frame(direction: int, frame: int, idle: bool) -> Canvas:
    return draw_hero_frame(DANCER_STYLE, direction, frame, idle)


def draw_keeper_frame(direction: int, frame: int, idle: bool) -> Canvas:
    return draw_hero_frame(KEEPER_STYLE, direction, frame, idle)


def draw_knight_frame(direction: int, frame: int, idle: bool) -> Canvas:
    return draw_hero_frame(KNIGHT_STYLE, direction, frame, idle)


def draw_eclipse_frame(direction: int, frame: int, idle: bool) -> Canvas:
    return draw_hero_frame(ECLIPSE_STYLE, direction, frame, idle)


def draw_sage_frame(direction: int, frame: int, idle: bool) -> Canvas:
    return draw_hero_frame(SAGE_STYLE, direction, frame, idle)


def build_dancer_portrait() -> Canvas:
    return build_hero_portrait(DANCER_STYLE)


def build_keeper_portrait() -> Canvas:
    return build_hero_portrait(KEEPER_STYLE)


def build_knight_portrait() -> Canvas:
    return build_hero_portrait(KNIGHT_STYLE)


def build_eclipse_portrait() -> Canvas:
    return build_hero_portrait(ECLIPSE_STYLE)


def build_sage_portrait() -> Canvas:
    return build_hero_portrait(SAGE_STYLE)


def build_sheet(art: HeroArt, idle: bool) -> Canvas:
    return build_hero_sheet(art.style, idle)


def validate_role_palettes() -> None:
    if not D_CLOTH[0] > D_CLOTH[2] > D_CLOTH[1]:
        raise RuntimeError("Dancer main color must be plum (red > blue > green)")
    if not D_MINT[1] > D_MINT[2] > D_MINT[0]:
        raise RuntimeError("Dancer accent must be mint (green > blue > red)")
    if not K_COAT[1] > K_COAT[2] > K_COAT[0]:
        raise RuntimeError("Keeper main color must be forest (green > blue > red)")
    if not K_AMBER[0] > K_AMBER[1] > K_AMBER[2]:
        raise RuntimeError("Keeper accent must be amber (red > green > blue)")
    if max(N_HOOD_LIGHT[:3]) - min(N_HOOD_LIGHT[:3]) > 8:
        raise RuntimeError("Knight highlight must be low-chroma silver-white")
    if not (E_RED[0] > E_RED[1] and E_RED[0] > E_RED[2]):
        raise RuntimeError("Eclipse accent must be high-chroma crimson")
    if not S_HOOD[2] > S_HOOD[1] > S_HOOD[0]:
        raise RuntimeError("Sage main color must be teal (blue > green > red)")
    if not S_GOLD[0] > S_GOLD[1] > S_GOLD[2]:
        raise RuntimeError("Sage accent must be gold (red > green > blue)")


def _mix_splash_color(foreground: RGBA, background: RGBA, amount: int) -> RGBA:
    return tuple(
        (foreground[index] + background[index] * (amount - 1)) // amount
        for index in range(3)
    ) + (255,)


def _draw_splash_circle(
    canvas: Canvas, center_x: int, center_y: int, radius: int, color: RGBA
) -> None:
    radius_squared = radius * radius
    for y in range(center_y - radius, center_y + radius + 1):
        distance = radius_squared - (y - center_y) ** 2
        if distance < 0:
            continue
        half_width = int(math.sqrt(distance))
        canvas.rect(center_x - half_width, y, center_x + half_width, y, color)


def _draw_splash_diamond(
    canvas: Canvas, center_x: int, center_y: int, half_width: int, half_height: int, color: RGBA
) -> None:
    canvas.polygon(
        [
            (center_x, center_y - half_height),
            (center_x + half_width, center_y),
            (center_x, center_y + half_height),
            (center_x - half_width, center_y),
        ],
        color,
    )


def _draw_splash_triangle(
    canvas: Canvas, center_x: int, tip_y: int, base_y: int, half_width: int, color: RGBA
) -> None:
    span = max(base_y - tip_y, 1)
    for y in range(tip_y, base_y + 1):
        half = (half_width * (y - tip_y)) // span
        canvas.rect(center_x - half, y, center_x + half, y, color)


def _draw_splash_pine(
    canvas: Canvas, center_x: int, base_y: int, height: int, half_width: int, color: RGBA
) -> None:
    tiers = (
        (base_y, (height * 11) // 20, half_width),
        (base_y - (height * 13) // 50, (height * 27) // 50, (half_width * 41) // 50),
        (base_y - (height * 1) // 2, (height * 1) // 2, (half_width * 31) // 50),
    )
    for tier_base, tier_height, tier_half in tiers:
        _draw_splash_triangle(
            canvas, center_x, tier_base - tier_height, tier_base, tier_half, color
        )


def build_boot_splash() -> Canvas:
    width = 2048
    height = 1152
    canvas = Canvas(width, height, SPLASH_NIGHT)
    bands = 24
    band_height = height // bands
    moon_x = 1024
    moon_y = 330
    moon_band = moon_y // band_height
    for index in range(bands):
        lift = max(0, 10 - abs(index - moon_band))
        color: RGBA = (5 + lift, 12 + lift * 2, 26 + lift * 3, 255)
        top = index * band_height
        bottom = height - 1 if index == bands - 1 else top + band_height - 1
        canvas.rect(0, top, width - 1, bottom, color)
    for index in range(40):
        x = 61 + (index * 379) % 1926
        y = 36 + (index * 173) % 700
        size = index % 3
        star = MOON_CORE if index % 5 == 0 else MOON_MID if index % 2 == 0 else SPLASH_NIGHT_LIGHT
        canvas.rect(x, y, x + size, y + size, star)
    for x, y, ray in ((348, 236, 11), (1682, 214, 13), (1500, 618, 8)):
        _draw_splash_diamond(canvas, x, y, 2, ray, MOON_MID)
        _draw_splash_diamond(canvas, x, y, ray, 2, MOON_MID)
        canvas.rect(x - 1, y - 1, x + 1, y + 1, MOON_CORE)
    _draw_splash_circle(canvas, moon_x, moon_y, 168, _mix_splash_color(MOON_MID, (12, 26, 47, 255), 10))
    _draw_splash_circle(canvas, moon_x, moon_y, 138, (27, 57, 91, 255))
    _draw_splash_circle(canvas, moon_x, moon_y, 120, (156, 210, 229, 255))
    _draw_splash_circle(canvas, moon_x + 39, moon_y - 25, 108, (12, 27, 48, 255))
    far_line = 900
    far_color: RGBA = (13, 28, 50, 255)
    canvas.rect(0, far_line, width - 1, height - 1, far_color)
    for index in range(17):
        x = -40 + index * 132
        if abs(x - 1024) < 200:
            continue
        _draw_splash_pine(canvas, x, far_line, 128 + (index * 53) % 72, 64, far_color)
    near_line = 972
    near_color: RGBA = (6, 13, 26, 255)
    canvas.rect(0, near_line, width - 1, height - 1, near_color)
    for index in range(16):
        x = -70 + index * 148
        if abs(x - 1024) < 240:
            continue
        _draw_splash_pine(canvas, x, near_line, 156 + (index * 97) % 92, 84, near_color)
    flame_x = 1024
    _draw_splash_circle(canvas, flame_x, 856, 96, _mix_splash_color((245, 200, 75, 255), (9, 20, 38, 255), 8))
    _draw_splash_circle(canvas, flame_x, 866, 62, _mix_splash_color((245, 200, 75, 255), (9, 20, 38, 255), 5))
    canvas.rect(960, 936, 1088, 954, (24, 34, 52, 255))
    canvas.rect(984, 916, 1064, 936, (36, 48, 66, 255))
    canvas.rect(996, 906, 1052, 916, (52, 66, 88, 255))
    canvas.rect(1002, 896, 1046, 906, (20, 24, 34, 255))
    flame_deep: RGBA = (222, 120, 44, 255)
    gold: RGBA = (245, 200, 75, 255)
    _draw_splash_diamond(canvas, flame_x, 838, 30, 62, flame_deep)
    _draw_splash_circle(canvas, flame_x, 872, 26, flame_deep)
    _draw_splash_diamond(canvas, flame_x, 850, 20, 44, gold)
    _draw_splash_circle(canvas, flame_x, 872, 17, gold)
    _draw_splash_diamond(canvas, flame_x, 862, 10, 26, MOON_CORE)
    _draw_splash_circle(canvas, flame_x, 874, 8, MOON_CORE)
    for x, y, size, spark in (
        (1004, 758, 2, gold), (1036, 734, 2, MOON_CORE), (1014, 702, 1, gold),
        (1046, 676, 2, gold), (1008, 648, 1, MOON_CORE), (1032, 622, 1, gold),
    ):
        canvas.rect(x, y, x + size, y + size, spark)
    _draw_splash_diamond(canvas, flame_x, 962, 150, 12, _mix_splash_color(gold, (16, 26, 44, 255), 6))
    return canvas


def build_preview(results: dict[str, dict[str, Canvas]]) -> Canvas:
    scale = 3
    margin = 12
    sheet_width = CELL_WIDTH * DIRECTIONS * scale
    sheet_height = CELL_HEIGHT * FRAMES * scale
    portrait_width = 96 * scale
    hero_width = max(sheet_width, portrait_width)
    hero_names = tuple(results)
    width = margin * (len(hero_names) + 1) + hero_width * len(hero_names)
    height = margin * 4 + sheet_height * 2 + 96 * scale
    preview = Canvas(width, height, (10, 13, 28, 255))
    for hero_index, hero_name in enumerate(hero_names):
        origin_x = margin + hero_index * (hero_width + margin)
        for section, key in enumerate(("idle", "walk")):
            origin_y = margin + section * (sheet_height + margin)
            preview.blit_scaled(results[hero_name][key], origin_x, origin_y, scale)
        portrait_x = origin_x + (hero_width - portrait_width) // 2
        portrait_y = margin * 3 + sheet_height * 2
        preview.blit_scaled(results[hero_name]["portrait"], portrait_x, portrait_y, scale)
    return preview


def _bounds_for(style: CuteHeroStyle) -> dict[str, int]:
    return {
        "min_height": 50,
        "max_height": 60,
        "max_width": style.max_front_width,
        "max_lower_body_width": style.max_lower_body_width,
        "min_opaque_pixels": 700,
        "max_opaque_pixels": 1700,
        "side_min_opaque_pixels": 550,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    validate_role_palettes()
    arts = (
        HeroArt("dancer", DANCER_STYLE, (MOON_MID, MOON_BRIGHT, MOON_CORE, D_MINT, D_MINT_LIGHT)),
        HeroArt("keeper", KEEPER_STYLE, (K_AMBER, K_AMBER_CORE, MOON_CORE)),
        HeroArt("knight", KNIGHT_STYLE, (N_BLUE, N_BLUE_LIGHT, MOON_CORE)),
        HeroArt("eclipse", ECLIPSE_STYLE, (E_RED, E_RED_LIGHT, E_CORE, MOON_CORE)),
        HeroArt("sage", SAGE_STYLE, (S_GOLD, S_GOLD_LIGHT, MOON_CORE)),
    )
    drawers: dict[str, Callable[[int, int, bool], Canvas]] = {
        "dancer": draw_dancer_frame,
        "keeper": draw_keeper_frame,
        "knight": draw_knight_frame,
        "eclipse": draw_eclipse_frame,
        "sage": draw_sage_frame,
    }
    portraits: dict[str, Callable[[], Canvas]] = {
        "dancer": build_dancer_portrait,
        "keeper": build_keeper_portrait,
        "knight": build_knight_portrait,
        "eclipse": build_eclipse_portrait,
        "sage": build_sage_portrait,
    }
    from pack_maple_heroes import pack_all

    pack_all(check=args.check)
    # The boot splash uses painted art from 2.0.0. Do not bake it here.
    #
    # Leave `build_boot_splash()` in place — night-sky band and moon placement
    # color refs are written here, and you consult those values when re-pulling art.
    # Whether the file actually exists, and the spec, is the `check_custom_assets.py` contract.
    splash_path = GAME_ROOT / "assets/custom/ui/boot_splash.png"
    if not splash_path.is_file():
        raise RuntimeError(f"production boot-splash PNG is missing: {splash_path}")
    print("companion heroes ready")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
