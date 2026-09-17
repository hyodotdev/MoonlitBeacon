#!/usr/bin/env python3
"""Deterministically draw Moonlit Beacon environment, beacon VFX, and heart atlases.

The canvas and crop coords the Ninja Adventure sheets provided are a runtime contract.
so AtlasTexture, Sprite2D region, and particle frame counts in the scene do not change, keep the same size and
Keep the same frame grid, but redraw pixels from scratch in the Moonlit Beacon palette.

Output contract:

    world/terrain/nature.png       384x336, keep existing KIND coords
    world/terrain/forest_floor.png 256x256, tileable opaque floor
    world/terrain/floor.png        352x417, keep (176,304,80,16)
    world/terrain/field.png         80x240, keep floor and grass-island coords
    world/terrain/camp.png         368x144, keep camp prop and brazier coords
    world/atmosphere/raylight.png  216x102, three 72x102 frames
    world/atmosphere/night_mist.png 1024x420, keep horizontal tile and drift
    world/beacon/clearing.png       288x160, keep beacon-floor canvas
    world/beacon/spark.png           70x8, seven 10x8 frames
    world/beacon/flame.png           96x12, eight 12x12 frames
    world/beacon/smoke.png          192x32, six 32x32 frames
    ui/heart.png                     80x16, five 16x16 frames

Image-create concepts were color and silhouette reference only. The live file uses integer coords and
only a fixed palette, so any machine yields the same bytes.
"""

from __future__ import annotations

import argparse
import hashlib
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from build_warden_assets import Canvas


GAME_ROOT = Path(__file__).resolve().parents[1]
CUSTOM_ROOT = GAME_ROOT / "assets/custom"

RGBA = tuple[int, int, int, int]
Point = tuple[int, int]

TRANSPARENT: RGBA = (0, 0, 0, 0)
NIGHT: RGBA = (10, 15, 32, 255)
OUTLINE: RGBA = (18, 25, 46, 255)
SHADOW: RGBA = (24, 34, 50, 255)
SLATE_DARK: RGBA = (42, 55, 76, 255)
SLATE: RGBA = (65, 82, 106, 255)
SLATE_LIGHT: RGBA = (103, 126, 148, 255)
MOON_DIM: RGBA = (78, 132, 153, 255)
MOON: RGBA = (114, 190, 199, 255)
MOON_LIGHT: RGBA = (172, 224, 226, 255)
MOON_CORE: RGBA = (229, 247, 238, 255)
PINE_DARK: RGBA = (26, 69, 75, 255)
PINE: RGBA = (37, 101, 100, 255)
PINE_LIGHT: RGBA = (64, 139, 128, 255)
MOSS: RGBA = (84, 145, 116, 255)
GRASS_DARK: RGBA = (42, 83, 79, 255)
GRASS: RGBA = (64, 119, 105, 255)
GRASS_LIGHT: RGBA = (104, 161, 130, 255)
WOOD_DARK: RGBA = (57, 47, 59, 255)
WOOD: RGBA = (91, 67, 69, 255)
WOOD_LIGHT: RGBA = (139, 98, 80, 255)
IRON: RGBA = (71, 76, 94, 255)
IRON_LIGHT: RGBA = (119, 127, 143, 255)
EMBER_DARK: RGBA = (121, 48, 49, 255)
EMBER: RGBA = (226, 83, 52, 255)
EMBER_LIGHT: RGBA = (255, 151, 67, 255)
EMBER_CORE: RGBA = (255, 225, 136, 255)

FOREST_FLOOR: RGBA = (48, 74, 88, 255)
FOREST_FLOOR_2: RGBA = (58, 90, 98, 255)
FOREST_FLOOR_3: RGBA = (72, 108, 104, 255)
FIELD_FLOOR: RGBA = (78, 112, 96, 255)
FIELD_FLOOR_2: RGBA = (92, 132, 104, 255)
CAMP_FLOOR: RGBA = (86, 72, 78, 255)
FLOWER: RGBA = (255, 168, 196, 255)
FLOWER_CORE: RGBA = (255, 228, 140, 255)


def ellipse(
    canvas: Canvas,
    cx: int,
    cy: int,
    rx: int,
    ry: int,
    color: RGBA,
) -> None:
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
    start: Point,
    end: Point,
    width: int,
    color: RGBA,
) -> None:
    half = width // 2
    for offset in range(-half, half + 1):
        canvas.line(
            (start[0] + offset, start[1]),
            (end[0] + offset, end[1]),
            color,
        )
        canvas.line(
            (start[0], start[1] + offset),
            (end[0], end[1] + offset),
            color,
        )


def paste(sheet: Canvas, x: int, y: int, artwork: Canvas) -> None:
    sheet.blit(artwork, x, y)


def _pine(variant: int) -> Canvas:
    art = Canvas(32, 32)
    sway = (-2, 0, 2, 1)[variant % 4]
    ellipse(art, 16, 29, 11, 2, SHADOW)
    art.rect(14 + sway // 2, 17, 17 + sway // 2, 29, OUTLINE)
    art.rect(15 + sway // 2, 18, 16 + sway // 2, 28, WOOD)
    crown = [
        [(16 + sway, 2), (7, 16), (12, 15), (5, 23), (27, 23), (20, 15), (25, 16)],
        [(14 + sway, 3), (5, 17), (11, 16), (4, 24), (26, 24), (19, 16), (24, 17)],
        [(18 + sway, 2), (10, 13), (13, 13), (6, 22), (29, 22), (22, 14), (26, 14)],
        [(16 + sway, 4), (9, 15), (12, 15), (6, 24), (28, 24), (20, 15), (24, 16)],
    ][variant % 4]
    art.polygon(crown, OUTLINE)
    inner = [(16 + sway, 5), (10, 16), (13, 16), (8, 22), (25, 22), (19, 15), (23, 17)]
    art.polygon(inner, PINE_DARK)
    art.polygon([(16 + sway, 6), (12, 15), (16, 14), (10, 20), (16, 19)], PINE)
    art.line((12, 22), (22, 20), PINE_LIGHT)
    art.line((10, 18), (16 + sway, 7), PINE_LIGHT)
    art.pixel(17 + sway, 5, MOON_LIGHT)
    if variant % 2 == 0:
        art.pixel(9, 23, MOSS)
        art.pixel(23, 18, MOON_DIM)
    return art


def _grove(variant: int) -> Canvas:
    art = Canvas(64, 48)
    # A 56px oval shadow under the whole grove becomes a flat platform when scaled up.
    # Imply ground only with each tree's small shadow and broken soil grain below.
    positions = [
        (1, 12, 0), (19, 3, 1), (34, 11, 2),
        (3, 9, 3), (21, 11, 0), (35, 2, 1),
        (0, 5, 2), (18, 12, 3), (36, 9, 0),
        (2, 11, 1), (19, 1, 2), (36, 12, 3),
    ][variant * 3 : variant * 3 + 3]
    for x, y, pine_variant in positions:
        paste(art, x, y, _pine(pine_variant))
    # A one-line plinth looks like a shelf across the whole forest when repeated.
    # Leave only short soil grains of mixed length and height so each grove floor breaks asymmetrically.
    ground_strokes = [
        [((7, 42), (17, 41)), ((24, 43), (31, 42)), ((40, 41), (52, 42))],
        [((10, 41), (21, 42)), ((29, 43), (37, 42)), ((46, 42), (55, 41))],
        [((6, 43), (14, 42)), ((22, 41), (34, 42)), ((43, 43), (51, 41))],
        [((9, 42), (18, 43)), ((27, 41), (34, 42)), ((42, 42), (54, 43))],
    ][variant]
    for start, end in ground_strokes:
        art.line(start, end, PINE_DARK)
    for x in (7 + variant * 3, 28, 49 - variant * 2):
        art.pixel(x, 41, GRASS_LIGHT)
        art.pixel(x + 1, 40, MOON_DIM)
    return art


def _dead_grove() -> Canvas:
    art = Canvas(64, 48)
    ellipse(art, 31, 44, 28, 4, SHADOW)
    thick_line(art, (31, 43), (29, 8), 3, OUTLINE)
    thick_line(art, (31, 42), (30, 9), 1, WOOD_LIGHT)
    for start, end in [
        ((29, 17), (16, 8)), ((28, 22), (42, 11)),
        ((30, 29), (14, 24)), ((31, 34), (47, 28)),
    ]:
        thick_line(art, start, end, 2, OUTLINE)
        art.line(start, end, WOOD)
    for x, y in [(15, 8), (42, 11), (13, 24), (47, 28)]:
        art.pixel(x, y, MOON_DIM)
    art.polygon([(23, 43), (29, 35), (38, 43)], PINE_DARK)
    return art


def _moon_shrub() -> Canvas:
    art = Canvas(32, 32)
    ellipse(art, 16, 27, 14, 3, SHADOW)
    for cx, cy, rx, ry in [(8, 22, 6, 6), (16, 18, 8, 9), (24, 22, 6, 6)]:
        ellipse(art, cx, cy, rx + 1, ry + 1, OUTLINE)
        ellipse(art, cx, cy, rx, ry, PINE)
    art.line((7, 22), (16, 15), PINE_LIGHT)
    art.line((17, 16), (24, 22), GRASS_LIGHT)
    art.pixel(15, 12, MOON_LIGHT)
    art.pixel(11, 19, MOON_DIM)
    return art


def _log() -> Canvas:
    art = Canvas(32, 32)
    ellipse(art, 16, 27, 14, 3, SHADOW)
    thick_line(art, (5, 20), (27, 24), 7, OUTLINE)
    thick_line(art, (6, 19), (26, 23), 4, WOOD)
    ellipse(art, 27, 24, 4, 5, OUTLINE)
    ellipse(art, 27, 24, 2, 3, WOOD_LIGHT)
    art.pixel(15, 21, MOON_DIM)
    art.line((10, 18), (8, 12), WOOD_LIGHT)
    return art


def _stump() -> Canvas:
    art = Canvas(32, 32)
    ellipse(art, 16, 27, 13, 3, SHADOW)
    art.polygon([(8, 25), (9, 12), (23, 12), (25, 25)], OUTLINE)
    art.polygon([(10, 24), (11, 14), (21, 14), (23, 24)], WOOD)
    ellipse(art, 16, 13, 8, 4, OUTLINE)
    ellipse(art, 16, 13, 6, 2, WOOD_LIGHT)
    art.line((14, 13), (18, 13), WOOD_DARK)
    art.pixel(11, 18, MOON_DIM)
    return art


def _small_stump(dead: bool = False) -> Canvas:
    art = Canvas(16, 16)
    ellipse(art, 8, 13, 6, 2, SHADOW)
    color = SLATE if dead else WOOD
    art.polygon([(4, 12), (5, 6), (11, 6), (12, 12)], OUTLINE)
    art.polygon([(6, 11), (6, 7), (10, 7), (10, 11)], color)
    ellipse(art, 8, 6, 4, 2, OUTLINE)
    ellipse(art, 8, 6, 2, 1, WOOD_LIGHT if not dead else SLATE_LIGHT)
    return art


def _branch(twig: bool = False) -> Canvas:
    art = Canvas(16, 16)
    ellipse(art, 8, 13, 7, 1, SHADOW)
    art.line((2, 11), (13, 7 if twig else 10), OUTLINE)
    art.line((3, 10), (13, 7 if twig else 9), WOOD_LIGHT)
    art.line((8, 9), (6, 5), WOOD)
    art.line((11, 8), (13, 4), WOOD)
    if twig:
        art.pixel(5, 8, MOON_DIM)
    return art


def _rock(size: int, variant: int) -> Canvas:
    art = Canvas(size, size)
    cx = size // 2
    floor_y = size - 5 if size >= 32 else size - 3
    ellipse(art, cx, floor_y, size // 2 - 2, 2 if size >= 32 else 1, SHADOW)
    if size >= 32:
        points = [(4, 26), (8, 14), (16, 7 + variant), (26, 11), (29, 26)]
        inner = [(7, 25), (10, 15), (17, 10 + variant), (24, 13), (26, 25)]
    else:
        points = [(2, 13), (4, 7), (8, 4 + variant), (13, 7), (14, 13)]
        inner = [(4, 12), (5, 8), (8, 6 + variant), (12, 8), (12, 12)]
    art.polygon(points, OUTLINE)
    art.polygon(inner, SLATE if variant == 0 else SLATE_DARK)
    art.line((inner[1][0], inner[1][1]), (inner[2][0], inner[2][1]), SLATE_LIGHT)
    art.pixel(cx - 2, inner[2][1] + 3, MOON_DIM)
    return art


def _bush() -> Canvas:
    art = Canvas(16, 16)
    ellipse(art, 8, 13, 7, 2, SHADOW)
    for cx, cy in [(4, 10), (8, 7), (12, 10)]:
        ellipse(art, cx, cy, 4, 4, OUTLINE)
        ellipse(art, cx, cy, 3, 3, PINE)
    art.pixel(6, 6, PINE_LIGHT)
    art.pixel(11, 8, MOON_DIM)
    return art


def _grass(variant: int) -> Canvas:
    art = Canvas(16, 16)
    ellipse(art, 8, 14, 6, 1, SHADOW)
    roots = [(4, 13), (7, 14), (10, 14), (12, 13)]
    tips = [
        ((2, 7), (6, 4), (9, 6), (14, 5)),
        ((3, 5), (7, 7), (10, 3), (13, 8)),
        ((1, 8), (6, 5), (11, 6), (14, 4)),
        ((4, 4), (7, 8), (9, 5), (12, 3)),
    ][variant % 4]
    for index, (root, tip) in enumerate(zip(roots, tips)):
        art.line(root, tip, OUTLINE)
        color = GRASS_LIGHT if (index + variant) % 3 == 0 else GRASS
        art.line((root[0], root[1] - 1), (tip[0], tip[1]), color)
    if variant in (3, 7, 10):
        art.pixel(tips[1][0], tips[1][1] - 1, MOON_LIGHT)
    return art


def nature_sheet() -> Canvas:
    sheet = Canvas(384, 336)
    for index, x in enumerate((0, 32, 64, 96)):
        paste(sheet, x, 0, _pine(index))
    paste(sheet, 256, 0, _pine(2))
    paste(sheet, 288, 0, _pine(3))
    for variant, x in enumerate((0, 64, 256, 320)):
        paste(sheet, x, 32, _grove(variant))
    paste(sheet, 0, 80, _dead_grove())
    paste(sheet, 96, 128, _moon_shrub())
    paste(sheet, 0, 128, _log())
    paste(sheet, 32, 128, _stump())
    paste(sheet, 64, 128, _small_stump())
    paste(sheet, 80, 128, _branch())
    paste(sheet, 64, 144, _small_stump(True))
    paste(sheet, 80, 144, _branch(True))
    paste(sheet, 208, 128, _rock(32, 0))
    paste(sheet, 256, 128, _rock(32, 1))
    paste(sheet, 240, 144, _rock(16, 0))
    paste(sheet, 288, 144, _rock(16, 1))
    paste(sheet, 192, 144, _bush())
    for variant in range(11):
        paste(sheet, variant * 16, 160, _grass(variant))
    return sheet


def forest_floor() -> Canvas:
    floor = Canvas(256, 256, FOREST_FLOOR)
    # Low-contrast 8px blobs. Edges are the same ground color so tiling has no seam.
    for gy in range(1, 31):
        for gx in range(1, 31):
            value = (gx * 37 + gy * 61 + gx * gy * 7) % 29
            x = gx * 8 + ((gy * 3) % 5)
            y = gy * 8 + ((gx * 5) % 4)
            if value in (0, 3, 9):
                floor.rect(x, y, x + 2, y + 1, FOREST_FLOOR_2)
            elif value == 17:
                floor.pixel(x, y, FOREST_FLOOR_3)
                floor.pixel(x + 1, y - 1, MOON_DIM)
    # Faint teal grass and moonstone. Small clusters instead of a large regular pattern.
    for x, y in [(28, 43), (92, 20), (154, 66), (220, 38), (56, 142),
                 (122, 118), (204, 160), (26, 218), (109, 230), (183, 211)]:
        floor.line((x, y + 4), (x - 2, y), GRASS_DARK)
        floor.line((x + 1, y + 4), (x + 3, y - 1), GRASS)
        floor.pixel(x + 2, y, MOON_DIM)
    for x, y in [(73, 84), (169, 31), (236, 116), (145, 186), (44, 171)]:
        floor.rect(x, y, x + 4, y + 2, SLATE_DARK)
        floor.line((x + 1, y), (x + 3, y), SLATE)
    for x, y in [(40, 70), (130, 48), (198, 92), (88, 188), (210, 204)]:
        floor.pixel(x, y, FLOWER)
        floor.pixel(x + 1, y, FLOWER_CORE)
        floor.pixel(x, y + 1, FLOWER)

    # Texture reinforcement starts here.
    #
    # The old floor was a few dots on 8px blobs, so at 4× it almost
    # read as solid. When characters and spirits stand on it the floor looks like empty backdrop paper.
    # **The seam rule is unchanged** — stamp only with coords modulo 256 so tiles
    # can be joined without a seam.

    # Moss blotches. A few large masses make screen-scale light and dark.
    #
    # Drawing it like a garden becomes polka dots. Sway radius by angle into a **torn
    # blotch**, and leave inner holes so no even face forms.
    for index, (cx, cy, r) in enumerate([
        (58, 96, 15), (170, 54, 12), (214, 168, 16),
        (96, 200, 13), (30, 148, 10), (140, 132, 11),
        (236, 96, 9), (78, 40, 8),
    ]):
        for dy in range(-r - 3, r + 4):
            for dx in range(-r - 3, r + 4):
                dist: float = (dx * dx + dy * dy) ** 0.5
                # Sway radius by angle. A three-lobe wave so it is not uniform.
                lobe: float = float(
                    ((dx * 5 + dy * 3 + index * 17) % 7)
                    + ((dx * 3 - dy * 7 + index * 11) % 5)) * 0.32
                if dist > float(r) - 2.0 + lobe:
                    continue
                # Inner hole. Reads as a patch where moss peeled off.
                if (dx * 13 + dy * 29 + index * 7) % 11 == 0:
                    continue
                tone = FOREST_FLOOR_2
                if (dx * 3 + dy * 5) % 13 == 0 and dist < float(r) * 0.6:
                    tone = FOREST_FLOOR_3
                floor.pixel((cx + dx) % 256, (cy + dy) % 256, tone)

    # Fallen leaves. Two-pixel diagonals give the floor a facing.
    for index in range(126):
        lx = (index * 53 + 11) % 256
        ly = (index * 97 + 29) % 256
        tone = (MOSS if index % 3 == 0 else FOREST_FLOOR_3) \
            if index % 5 else GRASS_DARK
        floor.pixel(lx, ly, tone)
        floor.pixel((lx + 1) % 256, (ly + 1) % 256, tone)

    # Root grain. Long laid lines make it read as forest floor.
    for index in range(9):
        rx = (index * 61 + 17) % 256
        ry = (index * 113 + 41) % 256
        length = 14 + (index * 7) % 12
        for step in range(length):
            wave = (step * step // 11) % 3 - 1
            floor.pixel((rx + step) % 256, (ry + wave) % 256, SLATE_DARK)
            if step % 4 == 0:
                floor.pixel((rx + step) % 256, (ry + wave - 1) % 256, SLATE)

    # Moonlight specks. Light leaking through leaves, sparse and bright.
    for x, y in [(66, 34), (188, 118), (118, 166), (236, 208), (44, 244)]:
        floor.pixel(x, y, MOON_DIM)
        floor.pixel((x + 1) % 256, y, MOON_DIM)
        floor.pixel(x, (y + 1) % 256, SLATE_LIGHT)
    return floor


def generic_floor_sheet() -> Canvas:
    sheet = Canvas(352, 417)
    # RoomKind.camp floor_region Rect2i(176,304,80,16).
    # Height 16px means any speckle repeats as a horizontal row at 80px screen spacing. Each room
    # 250 interior decorations (42 of them props) are scattered, so the floor itself stays even.
    sheet.rect(176, 304, 255, 319, CAMP_FLOOR)
    return sheet


def _grass_island(light: bool) -> Canvas:
    art = Canvas(48, 48)
    ellipse(art, 24, 40, 21, 5, SHADOW)
    ellipse(art, 24, 36, 20, 10, FIELD_FLOOR)
    ellipse(art, 24, 34, 18, 8, FIELD_FLOOR_2 if light else GRASS_DARK)
    for index, root_x in enumerate(range(7, 43, 5)):
        root = (root_x, 39 - (index % 2))
        tip = (root_x + (-3, 2, -1, 3)[index % 4], 17 + (index * 7) % 12)
        art.line(root, tip, OUTLINE)
        art.line((root[0] + 1, root[1]), (tip[0] + 1, tip[1]),
                 GRASS_LIGHT if light or index % 3 == 0 else GRASS)
        if index in (1, 5):
            art.pixel(tip[0] + 1, tip[1] - 1, MOON_LIGHT if light else MOON_DIM)
    return art


def field_sheet() -> Canvas:
    sheet = Canvas(80, 240)
    paste(sheet, 0, 48, _grass_island(True))
    paste(sheet, 0, 96, _grass_island(False))
    # RoomKind.field tiling floor Rect2i(16,64,16,16) must be fully opaque.
    sheet.rect(16, 64, 31, 79, FIELD_FLOOR)
    # Marks inside a 16px cell become a 64px grid at 4×. Field interior decor
    # (32 of them grass islands) carry the texture, so the repeat tile has no pattern.
    return sheet


def _tent(variant: int) -> Canvas:
    art = Canvas(48, 48)
    ellipse(art, 24, 43, 22, 4, SHADOW)
    art.line((24, 5), (24, 42), OUTLINE)
    art.polygon([(3, 38), (23, 7), (45, 38)], OUTLINE)
    cloth = (SLATE_DARK, WOOD_DARK, IRON)[variant]
    art.polygon([(7, 36), (23, 10), (41, 36)], cloth)
    art.polygon([(23, 10), (41, 36), (27, 34)], SLATE)
    art.line((7, 36), (42, 36), WOOD_LIGHT)
    # Tent door is a crescent ring, not a straight line that would read as a muzzle.
    ellipse(art, 23, 27, 6, 8, OUTLINE)
    ellipse(art, 26, 25, 5, 7, cloth)
    art.pixel(19, 25, MOON_LIGHT)
    if variant == 2:
        art.polygon([(33, 17), (42, 24), (37, 30)], TRANSPARENT)
        art.line((35, 17), (39, 28), EMBER_DARK)
    else:
        art.pixel(31, 18, EMBER_LIGHT if variant == 1 else MOON_DIM)
    return art


def _barrels(lit: bool) -> Canvas:
    art = Canvas(16, 32)
    ellipse(art, 8, 29, 7, 2, SHADOW)
    for x0, y0, height in [(1, 12, 17), (7, 6, 23)]:
        art.rect(x0, y0 + 2, x0 + 7, y0 + height, OUTLINE)
        art.rect(x0 + 2, y0 + 3, x0 + 5, y0 + height - 1, WOOD)
        art.line((x0 + 1, y0 + 7), (x0 + 6, y0 + 7), IRON)
        art.line((x0 + 1, y0 + height - 4), (x0 + 6, y0 + height - 4), IRON)
    if lit:
        art.pixel(11, 11, EMBER_CORE)
        art.pixel(10, 12, EMBER_LIGHT)
    return art


def _chest() -> Canvas:
    art = Canvas(32, 32)
    ellipse(art, 16, 28, 14, 3, SHADOW)
    art.rect(4, 12, 27, 26, OUTLINE)
    art.rect(7, 15, 24, 24, WOOD)
    art.polygon([(4, 13), (8, 7), (23, 7), (27, 13)], OUTLINE)
    art.polygon([(8, 12), (10, 9), (21, 9), (24, 12)], WOOD_LIGHT)
    art.rect(14, 12, 18, 20, IRON)
    art.pixel(16, 16, MOON_LIGHT)
    return art


def _bench() -> Canvas:
    art = Canvas(48, 16)
    ellipse(art, 24, 14, 22, 2, SHADOW)
    art.rect(3, 5, 44, 10, OUTLINE)
    art.rect(5, 6, 42, 8, WOOD_LIGHT)
    art.rect(8, 9, 12, 14, OUTLINE)
    art.rect(36, 9, 40, 14, OUTLINE)
    art.pixel(24, 7, EMBER_DARK)
    return art


def _crate() -> Canvas:
    art = Canvas(16, 16)
    art.rect(1, 2, 14, 14, OUTLINE)
    art.rect(3, 4, 12, 12, WOOD)
    art.line((3, 4), (12, 12), WOOD_LIGHT)
    art.line((12, 4), (3, 12), WOOD_DARK)
    art.rect(1, 7, 14, 9, IRON)
    return art


def _bedroll() -> Canvas:
    art = Canvas(16, 16)
    ellipse(art, 8, 13, 7, 2, SHADOW)
    art.polygon([(2, 10), (5, 5), (13, 6), (14, 12)], OUTLINE)
    art.polygon([(4, 10), (6, 7), (12, 8), (12, 11)], SLATE)
    art.line((5, 6), (6, 12), EMBER_DARK)
    art.pixel(10, 8, MOON_DIM)
    return art


def _beacon_pit() -> Canvas:
    art = Canvas(32, 30)
    ellipse(art, 16, 25, 14, 4, OUTLINE)
    ellipse(art, 16, 24, 11, 3, IRON)
    ellipse(art, 16, 22, 8, 3, EMBER_DARK)
    for x in (6, 12, 20, 26):
        art.line((x, 23), (16, 15), OUTLINE)
        art.line((x + (1 if x < 16 else -1), 22), (16, 16), IRON_LIGHT)
    art.polygon([(12, 20), (16, 8), (20, 20)], EMBER)
    art.polygon([(14, 19), (16, 12), (18, 19)], EMBER_CORE)
    art.pixel(16, 7, MOON_CORE)
    return art


def camp_sheet() -> Canvas:
    sheet = Canvas(368, 144)
    paste(sheet, 64, 0, _tent(0))
    paste(sheet, 112, 0, _tent(1))
    paste(sheet, 160, 0, _tent(2))
    paste(sheet, 48, 16, _barrels(False))
    paste(sheet, 48, 48, _barrels(True))
    paste(sheet, 64, 96, _chest())
    paste(sheet, 0, 112, _bench())
    paste(sheet, 48, 112, _crate())
    paste(sheet, 112, 128, _bedroll())
    paste(sheet, 192, 80, _beacon_pit())
    return sheet


def raylight_sheet() -> Canvas:
    sheet = Canvas(216, 102)
    for frame in range(3):
        x0 = frame * 72
        drift = (-7, 3, 10)[frame]
        # Distinct moonlight columns that finish inside 72x102. Low alpha is outer mist.
        sheet.polygon(
            [(x0 + 14 + drift, 1), (x0 + 31 + drift, 1),
             (x0 + 62 - drift // 2, 100), (x0 + 8, 100)],
            (MOON_LIGHT[0], MOON_LIGHT[1], MOON_LIGHT[2], 46),
        )
        sheet.polygon(
            [(x0 + 20 + drift, 1), (x0 + 28 + drift, 1),
             (x0 + 49 - drift // 3, 100), (x0 + 20, 100)],
            (MOON_CORE[0], MOON_CORE[1], MOON_CORE[2], 86),
        )
        for y in range(12 + frame * 5, 96, 18):
            x = x0 + 20 + ((y * 7 + frame * 13) % 29)
            sheet.pixel(x, y, (MOON_CORE[0], MOON_CORE[1], MOON_CORE[2], 170))
            sheet.pixel(x + 1, y, (MOON_LIGHT[0], MOON_LIGHT[1], MOON_LIGHT[2], 92))
    return sheet


def _wrapped_ellipse(
    canvas: Canvas,
    cx: int,
    cy: int,
    rx: int,
    ry: int,
    color: RGBA,
) -> None:
    """Continue an ellipse that crosses a horizontally tiling texture onto the other side."""
    for offset in (-canvas.width, 0, canvas.width):
        ellipse(canvas, cx + offset, cy, rx, ry, color)


def night_mist() -> Canvas:
    mist = Canvas(1024, 420)
    rgb = MOON_LIGHT[:3]
    # Centers and sizes are a fixed low-res cloud layer. Ellipses past x=0/1024 wrap
    # draw so a 4,400px region has no vertical seam when it tiles.
    clouds = [
        (18, 88, 126, 39), (164, 116, 112, 47), (328, 79, 145, 42),
        (512, 132, 152, 54), (694, 91, 128, 43), (864, 122, 151, 50),
        (70, 286, 154, 49), (248, 246, 127, 42), (405, 304, 162, 51),
        (594, 259, 141, 46), (754, 317, 156, 52), (938, 268, 142, 47),
    ]
    for index, (cx, cy, rx, ry) in enumerate(clouds):
        outer = (rgb[0], rgb[1], rgb[2], 34)
        middle = (rgb[0], rgb[1], rgb[2], 68)
        core = (rgb[0], rgb[1], rgb[2], 102)
        _wrapped_ellipse(mist, cx, cy, rx, ry, outer)
        _wrapped_ellipse(
            mist,
            cx + (-18, 12, 24)[index % 3],
            cy + (-5, 8)[index % 2],
            max(28, rx - 36),
            max(14, ry - 13),
            middle,
        )
        if index % 3 == 1:
            _wrapped_ellipse(
                mist,
                cx + 16,
                cy - 4,
                max(20, rx // 3),
                max(9, ry // 3),
                core,
            )
    return mist


def beacon_clearing() -> Canvas:
    clearing = Canvas(288, 160)
    # Irregular moonstone clearing that keeps the original 288x160 center and padding.
    ellipse(clearing, 144, 83, 130, 66, OUTLINE)
    ellipse(clearing, 139, 78, 124, 61, SLATE_DARK)
    ellipse(clearing, 151, 82, 116, 55, CAMP_FLOOR)
    # Ink-navy moonstone on the edge, but leave the center 48px empty for the beacon base.
    stones = [
        (72, 46, 10, 6), (104, 29, 9, 5), (147, 24, 12, 6),
        (193, 32, 10, 6), (230, 53, 11, 6), (250, 88, 9, 5),
        (224, 120, 11, 6), (183, 136, 10, 5), (135, 140, 12, 5),
        (89, 132, 9, 5), (49, 111, 11, 6), (38, 74, 9, 5),
    ]
    for index, (cx, cy, rx, ry) in enumerate(stones):
        ellipse(clearing, cx, cy + 2, rx + 2, ry + 1, SHADOW)
        ellipse(clearing, cx, cy, rx, ry, SLATE if index % 2 == 0 else SLATE_DARK)
        clearing.line((cx - rx // 2, cy - 1), (cx + 1, cy - ry + 2), SLATE_LIGHT)
        if index in (2, 6, 10):
            clearing.pixel(cx, cy - ry + 1, MOON_DIM)
    # Teal cracks and scarlet embers gathering toward the beacon. A long single line reads as a ruler-drawn ray
    # on a scaled screen, so break it into short shards of mixed direction and spacing.
    cracks = [
        [((92, 86), (101, 84)), ((104, 86), (112, 83)), ((116, 81), (125, 82))],
        [((196, 79), (188, 81)), ((185, 79), (177, 83)), ((173, 85), (164, 82))],
        [((126, 118), (129, 111)), ((131, 108), (134, 104)), ((133, 100), (139, 97))],
        [((164, 48), (161, 55)), ((162, 58), (157, 61)), ((158, 64), (153, 68))],
    ]
    for crack in cracks:
        for start, end in crack:
            clearing.line(start, end, MOON_DIM)
        first = crack[0][0]
        clearing.pixel(first[0], first[1], MOON_LIGHT)
    for start, end in [
        ((110, 84), (108, 79)), ((181, 82), (184, 87)),
        ((132, 105), (127, 103)), ((158, 60), (154, 57)),
    ]:
        clearing.line(start, end, SLATE_LIGHT)
    for x, y in [(62, 92), (212, 96), (111, 53), (181, 112)]:
        clearing.pixel(x, y, EMBER_DARK)
        clearing.pixel(x + 1, y - 1, EMBER_LIGHT)
    return clearing


def spark_sheet() -> Canvas:
    sheet = Canvas(70, 8)
    shapes = [
        [(5, 4)],
        [(5, 3), (5, 4), (4, 4)],
        [(5, 2), (5, 3), (5, 4), (4, 4), (6, 4)],
        [(5, 1), (5, 2), (5, 3), (5, 4), (5, 5), (3, 4), (4, 4), (6, 4), (7, 4)],
        [(5, 2), (5, 3), (5, 4), (5, 5), (3, 4), (4, 4), (6, 4), (7, 4)],
        [(5, 3), (5, 4), (4, 4), (6, 4), (5, 5)],
        [(5, 4), (6, 4)],
    ]
    for frame, points in enumerate(shapes):
        x0 = frame * 10
        for x, y in points:
            color = MOON_CORE if (x, y) == (5, 4) else MOON_LIGHT
            sheet.pixel(x0 + x, y, color)
        if frame in (3, 4):
            sheet.pixel(x0 + 5, 3, EMBER_CORE)
    return sheet


def flame_sheet() -> Canvas:
    sheet = Canvas(96, 12)
    for frame in range(8):
        x0 = frame * 12
        lean = (-1, 0, 1, 0, -1, 1, 0, 1)[frame]
        height = (8, 10, 9, 11, 9, 10, 8, 11)[frame]
        sheet.polygon(
            [(x0 + 2, 11), (x0 + 3 + lean, 7),
             (x0 + 6 + lean, 11 - height), (x0 + 9, 7), (x0 + 10, 11)],
            EMBER_DARK,
        )
        sheet.polygon(
            [(x0 + 4, 10), (x0 + 5 + lean, 6),
             (x0 + 7 + lean, max(2, 12 - height)), (x0 + 8, 10)],
            EMBER_LIGHT,
        )
        sheet.pixel(x0 + 6 + lean, 9, EMBER_CORE)
        sheet.pixel(x0 + 6 + lean, 8, MOON_CORE)
    return sheet


def smoke_sheet() -> Canvas:
    sheet = Canvas(192, 32)
    for frame in range(6):
        x0 = frame * 32
        drift = (-2, -1, 0, 1, 2, 2)[frame]
        size = (4, 6, 8, 10, 11, 12)[frame]
        # Three large concentric ellipses become hard color bands in later frames, and the last cell
        # crossed the right edge. Split the same three colors into asymmetric smoke blobs and overlap them.
        color_outer = (MOON_DIM[0], MOON_DIM[1], MOON_DIM[2], 40)
        color_mid = (SLATE_LIGHT[0], SLATE_LIGHT[1], SLATE_LIGHT[2], 80)
        color_core = (MOON_LIGHT[0], MOON_LIGHT[1], MOON_LIGHT[2], 120)
        cx = x0 + 15 + drift
        cy = 19 - frame
        ry = max(3, size - 3)
        outer_rx = max(2, size * 2 // 3)
        ellipse(sheet, cx - size // 3, cy, outer_rx, ry, color_outer)
        ellipse(sheet, cx + size // 3, cy - 1, outer_rx, max(2, ry - 1), color_outer)
        ellipse(
            sheet, cx, cy - max(1, ry // 2), max(2, size // 2),
            max(2, ry * 2 // 3), color_outer)

        # Midtones are two separate blobs, not a ring around the outline.
        # Put the brightest color on only one blob so there is no concentric center.
        mid_rx = max(2, size // 3)
        mid_ry = max(2, ry // 2)
        ellipse(sheet, cx - size // 3, cy - 1, mid_rx, mid_ry, color_mid)
        if frame > 0:
            ellipse(
                sheet, cx + size // 3, cy - 3, max(1, mid_rx - 1),
                max(1, mid_ry - 1), color_mid)

        core_rx = max(1, size // 6)
        ellipse(
            sheet, cx - size // 3, cy - 2, core_rx,
            max(1, mid_ry // 2), color_core)
        if frame in (2, 4, 5):
            sheet.pixel(cx + size // 3, cy - 4, color_core)
        # Leave two gaps at the bottom so even an oval-stamp outline breaks.
        sheet.pixel(cx - size // 2, cy + ry - 1, TRANSPARENT)
        sheet.pixel(cx + size // 3, cy + max(1, ry - 2), TRANSPARENT)
    return sheet


def _heart_frame(fill: int, pulse: bool = False) -> Canvas:
    art = Canvas(16, 16)
    outline_points = [
        (3, 3), (6, 2), (8, 4), (10, 2), (13, 3), (14, 6),
        (13, 9), (8, 14), (3, 9), (2, 6),
    ]
    art.polygon(outline_points, OUTLINE)
    inner = [
        (4, 4), (6, 3), (8, 5), (10, 3), (12, 4), (13, 6),
        (12, 8), (8, 12), (4, 8), (3, 6),
    ]
    art.polygon(inner, SLATE_DARK)
    if fill > 0:
        # Moonlight rising from below. The outline stays put so the HUD cell does not shake.
        threshold = 12 - fill * 3
        for y in range(max(3, threshold), 13):
            for x in range(3, 14):
                if art.get(x, y) == SLATE_DARK:
                    art.pixel(x, y, MOON if fill < 3 else MOON_LIGHT)
    art.pixel(5, 4, MOON_CORE if pulse or fill >= 4 else MOON_DIM)
    if fill >= 3:
        art.pixel(6, 5, MOON_CORE)
    if pulse:
        for x, y in [(1, 3), (14, 2), (14, 11), (2, 12)]:
            art.pixel(x, y, EMBER_CORE)
    return art


def heart_sheet() -> Canvas:
    sheet = Canvas(80, 16)
    frames = [
        _heart_frame(0),
        _heart_frame(1),
        _heart_frame(2),
        _heart_frame(4, True),
        _heart_frame(4),
    ]
    for frame, artwork in enumerate(frames):
        paste(sheet, frame * 16, 0, artwork)
    return sheet


def expected_outputs() -> dict[Path, bytes]:
    return {
        CUSTOM_ROOT / "world/terrain/nature.png": nature_sheet().to_png(),
        CUSTOM_ROOT / "world/terrain/forest_floor.png": forest_floor().to_png(),
        CUSTOM_ROOT / "world/terrain/floor.png": generic_floor_sheet().to_png(),
        CUSTOM_ROOT / "world/terrain/field.png": field_sheet().to_png(),
        CUSTOM_ROOT / "world/terrain/camp.png": camp_sheet().to_png(),
        CUSTOM_ROOT / "world/atmosphere/raylight.png": raylight_sheet().to_png(),
        CUSTOM_ROOT / "world/atmosphere/night_mist.png": night_mist().to_png(),
        CUSTOM_ROOT / "world/beacon/clearing.png": beacon_clearing().to_png(),
        CUSTOM_ROOT / "world/beacon/spark.png": spark_sheet().to_png(),
        CUSTOM_ROOT / "world/beacon/flame.png": flame_sheet().to_png(),
        CUSTOM_ROOT / "world/beacon/smoke.png": smoke_sheet().to_png(),
        CUSTOM_ROOT / "ui/heart.png": heart_sheet().to_png(),
    }


def _validate_repeat_region(
    name: str,
    canvas: Canvas,
    region: tuple[int, int, int, int],
) -> None:
    """Confirm a tiling floor is opaque solid color so it does not make a 4× grid."""
    x0, y0, width, height = region
    if any(
        canvas.get(x, y)[3] != 255
        for y in range(y0, y0 + height)
        for x in range(x0, x0 + width)
    ):
        raise RuntimeError(f"{name}: tiling floor has transparent pixels")
    top = [canvas.get(x, y0) for x in range(x0, x0 + width)]
    bottom = [canvas.get(x, y0 + height - 1) for x in range(x0, x0 + width)]
    left = [canvas.get(x0, y) for y in range(y0, y0 + height)]
    right = [canvas.get(x0 + width - 1, y) for y in range(y0, y0 + height)]
    if top != bottom or left != right:
        raise RuntimeError(f"{name}: tiling floor opposite edges do not continue")
    colors = {
        canvas.get(x, y)
        for y in range(y0, y0 + height)
        for x in range(x0, x0 + width)
    }
    if len(colors) != 1:
        raise RuntimeError(f"{name}: tiling floor must be unpatterned solid color")


def validate_contracts(outputs: dict[Path, bytes]) -> None:
    expected_sizes = {
        "nature.png": (384, 336),
        "forest_floor.png": (256, 256),
        "floor.png": (352, 417),
        "field.png": (80, 240),
        "camp.png": (368, 144),
        "raylight.png": (216, 102),
        "night_mist.png": (1024, 420),
        "clearing.png": (288, 160),
        "spark.png": (70, 8),
        "flame.png": (96, 12),
        "smoke.png": (192, 32),
        "heart.png": (80, 16),
    }
    canvases = {
        "nature.png": nature_sheet(),
        "forest_floor.png": forest_floor(),
        "floor.png": generic_floor_sheet(),
        "field.png": field_sheet(),
        "camp.png": camp_sheet(),
        "raylight.png": raylight_sheet(),
        "night_mist.png": night_mist(),
        "clearing.png": beacon_clearing(),
        "spark.png": spark_sheet(),
        "flame.png": flame_sheet(),
        "smoke.png": smoke_sheet(),
        "heart.png": heart_sheet(),
    }
    expected_paths = {
        name: CUSTOM_ROOT / (
            "ui/heart.png" if name == "heart.png" else
            "world/atmosphere/" + name if name in {"raylight.png", "night_mist.png"} else
            "world/beacon/" + name if name in {"clearing.png", "spark.png", "flame.png", "smoke.png"} else
            "world/terrain/" + name
        )
        for name in expected_sizes
    }
    if set(outputs) != set(expected_paths.values()):
        raise RuntimeError("output path and canvas contract differ")
    for name, path in expected_paths.items():
        if outputs[path] != canvases[name].to_png():
            raise RuntimeError(f"{name}: output payload and canvas differ")
    for name, size in expected_sizes.items():
        canvas = canvases[name]
        if (canvas.width, canvas.height) != size:
            raise RuntimeError(f"{name}: canvas {(canvas.width, canvas.height)} != {size}")
    opaque_floor = canvases["forest_floor.png"]
    if any(opaque_floor.get(x, y)[3] != 255 for y in range(256) for x in range(256)):
        raise RuntimeError("forest_floor.png: tiling floor has transparent pixels")
    _validate_repeat_region("field.png", canvases["field.png"], (16, 64, 16, 16))
    _validate_repeat_region("floor.png", canvases["floor.png"], (176, 304, 80, 16))

    # Particle frames are independent 32px cells. Using the edge blends the next frame or
    # the last frame is cropped.
    smoke = canvases["smoke.png"]
    for frame in range(6):
        x0 = frame * 32
        touches_edge = any(
            smoke.get(x0, y)[3] > 0 or smoke.get(x0 + 31, y)[3] > 0
            for y in range(32)
        ) or any(
            smoke.get(x, 0)[3] > 0 or smoke.get(x, 31)[3] > 0
            for x in range(x0, x0 + 32)
        )
        if touches_edge:
            raise RuntimeError(f"smoke.png: frame {frame} touches the cell edge")
    # No frame or region a live consumer crops may be empty.
    required_regions: dict[str, list[tuple[int, int, int, int]]] = {
        "nature.png": [
            (0, 0, 32, 32), (32, 0, 32, 32), (64, 0, 32, 32),
            (96, 0, 32, 32), (256, 0, 32, 32), (288, 0, 32, 32),
            (0, 32, 64, 48), (64, 32, 64, 48), (256, 32, 64, 48),
            (320, 32, 64, 48), (0, 80, 64, 48), (96, 128, 32, 32),
            (0, 128, 32, 32), (32, 128, 32, 32), (64, 128, 16, 16),
            (80, 128, 16, 16), (64, 144, 16, 16), (80, 144, 16, 16),
            (208, 128, 32, 32), (256, 128, 32, 32),
            (240, 144, 16, 16), (288, 144, 16, 16), (192, 144, 16, 16),
            *[(index * 16, 160, 16, 16) for index in range(11)],
        ],
        "floor.png": [(176, 304, 80, 16)],
        "field.png": [(16, 64, 16, 16), (0, 48, 48, 48), (0, 96, 48, 48)],
        "camp.png": [
            (64, 0, 48, 48), (112, 0, 48, 48), (160, 0, 48, 48),
            (48, 16, 16, 32), (48, 48, 16, 32), (64, 96, 32, 32),
            (0, 112, 48, 16), (48, 112, 16, 16), (112, 128, 16, 16),
            (192, 80, 32, 30),
        ],
        "raylight.png": [(index * 72, 0, 72, 102) for index in range(3)],
        "night_mist.png": [(0, 0, 1024, 420)],
        "clearing.png": [(0, 0, 288, 160)],
        "spark.png": [(index * 10, 0, 10, 8) for index in range(7)],
        "flame.png": [(index * 12, 0, 12, 12) for index in range(8)],
        "smoke.png": [(index * 32, 0, 32, 32) for index in range(6)],
        "heart.png": [(index * 16, 0, 16, 16) for index in range(5)],
    }
    for name, regions in required_regions.items():
        canvas = canvases[name]
        for x0, y0, width, height in regions:
            visible = any(
                canvas.get(x, y)[3] > 0
                for y in range(y0, y0 + height)
                for x in range(x0, x0 + width)
            )
            if not visible:
                raise RuntimeError(f"{name}: empty consumer region {(x0, y0, width, height)}")
    if len(outputs) != len(expected_sizes):
        raise RuntimeError("output file count and canvas contract count differ")


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
                print(f"stale world asset: {shown}")
            else:
                print(f"OK {shown} sha256={digest}")
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(f"{shown} sha256={digest}")
    return 1 if stale else 0


if __name__ == "__main__":
    raise SystemExit(main())
