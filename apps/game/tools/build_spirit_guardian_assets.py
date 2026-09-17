#!/usr/bin/env python3
"""Build final pixel sheets for 7 regular spirits and 3 terrain guardians.

Moonlit bestiary concepts from an image-create model were silhouette and material reference only.
The live runtime PNG is redrawn on integer coords and a fixed palette so the same input
always makes the same bytes.

Regular spirits are 192x192 sheets, columns=4 facings, rows=4 frames. Guardians are facing-less
64px-wide sheets, 6 idle frames and 4 combat-state frames.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Callable

from pixel_canvas import Canvas


GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
SPIRIT_ROOT = GAME_ROOT / "assets/custom/actors/spirits"
GUARDIAN_ROOT = GAME_ROOT / "assets/custom/actors/guardians"
REVIEW_DIR = REPO_ROOT / "builds/art-review/a1-enemies"

RGBA = tuple[int, int, int, int]
Point = tuple[int, int]

TRANSPARENT: RGBA = (0, 0, 0, 0)
OUTLINE: RGBA = (15, 19, 31, 255)
NIGHT: RGBA = (12, 17, 33, 255)
NAVY: RGBA = (25, 37, 61, 255)
BLUE: RGBA = (44, 75, 113, 255)
CYAN: RGBA = (67, 190, 205, 255)
MOON: RGBA = (157, 225, 232, 255)
PALE: RGBA = (225, 245, 238, 255)
VIOLET_DARK: RGBA = (43, 32, 72, 255)
VIOLET: RGBA = (93, 65, 132, 255)
VIOLET_LIGHT: RGBA = (174, 122, 199, 255)
EMBER_DARK: RGBA = (91, 39, 36, 255)
EMBER: RGBA = (225, 79, 39, 255)
GOLD: RGBA = (247, 169, 55, 255)
FLAME: RGBA = (255, 224, 105, 255)
WOOD_DARK: RGBA = (43, 45, 38, 255)
WOOD: RGBA = (75, 72, 50, 255)
MOSS: RGBA = (62, 105, 70, 255)
MOSS_LIGHT: RGBA = (111, 162, 94, 255)
STONE_DARK: RGBA = (45, 54, 68, 255)
STONE: RGBA = (76, 91, 108, 255)
STONE_LIGHT: RGBA = (127, 146, 153, 255)

ENEMY_CELL = 48
ENEMY_DIRECTIONS = 4
ENEMY_FRAMES = 4
GUARDIAN_CELL = 64


def _disc(canvas: Canvas, cx: int, cy: int, radius: int, color: RGBA) -> None:
    """Fill a pixel circle."""
    threshold = radius * radius + radius
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= threshold:
                canvas.pixel(x, y, color)


def _outlined_disc(
    canvas: Canvas,
    cx: int,
    cy: int,
    radius: int,
    outline: RGBA,
    fill: RGBA,
) -> None:
    _disc(canvas, cx, cy, radius, outline)
    _disc(canvas, cx, cy, max(radius - 1, 0), fill)


def _ring(
    canvas: Canvas,
    cx: int,
    cy: int,
    radius: int,
    thickness: int,
    color: RGBA,
) -> None:
    outer = radius * radius + radius
    inner_radius = max(radius - thickness, 0)
    inner = inner_radius * inner_radius
    for y in range(cy - radius, cy + radius + 1):
        for x in range(cx - radius, cx + radius + 1):
            distance = (x - cx) ** 2 + (y - cy) ** 2
            if inner <= distance <= outer:
                canvas.pixel(x, y, color)


def _outlined_polygon(
    canvas: Canvas,
    outer: list[Point],
    inner: list[Point],
    fill: RGBA,
) -> None:
    canvas.polygon(outer, OUTLINE)
    canvas.polygon(inner, fill)


def _diamond(
    canvas: Canvas,
    cx: int,
    cy: int,
    radius: int,
    color: RGBA,
) -> None:
    canvas.polygon(
        [(cx, cy - radius), (cx + radius, cy),
         (cx, cy + radius), (cx - radius, cy)],
        color,
    )


def _rune_eye(canvas: Canvas, cx: int, cy: int, color: RGBA = PALE) -> None:
    _diamond(canvas, cx, cy, 2, OUTLINE)
    canvas.rect(cx - 1, cy, cx + 1, cy, color)
    canvas.pixel(cx, cy - 1, color)
    canvas.pixel(cx, cy, NIGHT)


def _bob(frame: int) -> int:
    return (0, -1, 0, 1)[frame]


def _cute_eyes(
    canvas: Canvas, left_x: int, right_x: int, eye_y: int, pale: RGBA = PALE
) -> None:
    for eye_x in (left_x, right_x):
        canvas.rect(eye_x, eye_y, eye_x + 3, eye_y + 3, OUTLINE)
        canvas.rect(eye_x + 1, eye_y + 1, eye_x + 2, eye_y + 2, pale)
        canvas.pixel(eye_x + 1, eye_y + 1, CYAN)


def _draw_wisp(facing: int, frame: int) -> Canvas:
    """Round moonfire ghost. Big eyes and a short tail."""
    if facing == 3:
        return _draw_wisp(2, frame).mirrored()
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    bob = _bob(frame) * 2
    sway = (-2, 0, 2, 0)[frame]
    cx, cy = 24, 20 + bob
    _outlined_disc(canvas, cx, cy, 12, OUTLINE, NAVY)
    canvas.disc(cx, cy + 2, 8, BLUE)
    canvas.polygon(
        [(cx - 6, cy + 10), (cx - 2 + sway, cy + 20), (cx + 4, cy + 12)],
        OUTLINE,
    )
    canvas.polygon(
        [(cx - 4, cy + 10), (cx - 1 + sway, cy + 17), (cx + 2, cy + 11)],
        BLUE,
    )
    canvas.pixel(cx - 6, cy - 6, MOON)
    canvas.pixel(cx - 5, cy - 7, MOON)
    canvas.pixel(cx - 4, cy - 6, MOON)
    if facing == 0:
        _cute_eyes(canvas, cx - 7, cx + 3, cy - 2)
    elif facing == 1:
        canvas.rect(cx - 2, cy - 1, cx + 2, cy, CYAN)
        canvas.pixel(cx, cy - 2, MOON)
    else:
        canvas.rect(cx - 9, cy - 2, cx - 6, cy + 1, OUTLINE)
        canvas.rect(cx - 8, cy - 1, cx - 7, cy, PALE)
        canvas.pixel(cx - 8, cy - 1, CYAN)
    return canvas


def _draw_stalker(facing: int, frame: int) -> Canvas:
    """Horned moonlight bug. Low, cute charger."""
    if facing == 3:
        return _draw_stalker(2, frame).mirrored()
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    bob = 0 if frame % 2 == 0 else -2
    stride = (-2, 0, 2, 0)[frame]
    cx, cy = 24, 26 + bob
    _outlined_ellipse(canvas, cx, cy, 14, 10, OUTLINE, VIOLET_DARK)
    canvas.polygon([(cx - 8, cy - 8), (cx - 14, cy - 16), (cx - 4, cy - 6)], OUTLINE)
    canvas.polygon([(cx + 8, cy - 8), (cx + 14, cy - 16), (cx + 4, cy - 6)], OUTLINE)
    canvas.polygon([(cx - 8, cy - 8), (cx - 12, cy - 13), (cx - 5, cy - 6)], VIOLET_LIGHT)
    canvas.polygon([(cx + 8, cy - 8), (cx + 12, cy - 13), (cx + 5, cy - 6)], VIOLET_LIGHT)
    canvas.rect(cx - 12 + stride, cy + 10, cx - 6 + stride, cy + 16, OUTLINE)
    canvas.rect(cx + 6 - stride, cy + 10, cx + 12 - stride, cy + 16, OUTLINE)
    if facing == 0:
        _cute_eyes(canvas, cx - 8, cx + 3, cy - 2, FLAME)
    elif facing == 1:
        canvas.rect(cx - 4, cy - 2, cx + 4, cy, VIOLET)
    else:
        canvas.rect(cx - 12, cy - 2, cx - 8, cy + 1, OUTLINE)
        canvas.pixel(cx - 11, cy - 1, FLAME)
    return canvas


def _outlined_ellipse(
    canvas: Canvas, cx: int, cy: int, rx: int, ry: int, outline: RGBA, fill: RGBA
) -> None:
    canvas.ellipse(cx, cy, rx, ry, outline)
    canvas.ellipse(cx, cy, max(rx - 1, 1), max(ry - 1, 1), fill)


def _draw_swarm(facing: int, frame: int) -> Canvas:
    """Swarm of three small moonfires swapping places."""
    if facing == 3:
        return _draw_swarm(2, frame).mirrored()
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    pulse = frame % 4
    positions = [
        (14 + (pulse % 2) * 2, 14 + ((pulse + 1) % 2) * 2),
        (32 - (pulse % 2) * 2, 16 - ((pulse + 1) % 2) * 2),
        (22 + (-2 if pulse == 1 else 2 if pulse == 3 else 0), 30),
    ]
    if facing == 1:
        positions = [(x, 46 - y) for x, y in positions]
    elif facing == 2:
        positions = [(y, x) for x, y in positions]
    sizes = (6, 6, 8)
    for index, ((x, y), size) in enumerate(zip(positions, sizes)):
        _outlined_disc(canvas, x, y, size, OUTLINE, EMBER_DARK)
        canvas.disc(x, y, 2, FLAME if index == 2 else GOLD)
        if facing == 0 and index == 2:
            canvas.pixel(x - 2, y - 1, PALE)
            canvas.pixel(x + 2, y - 1, PALE)
        tail = (-2 if (frame + index) % 2 == 0 else 2)
        canvas.pixel(x + tail, y + size, EMBER)
    if facing == 0:
        canvas.pixel(22, 40, GOLD)
    elif facing == 1:
        canvas.pixel(24, 6, GOLD)
    elif facing == 2:
        canvas.line((6, 22), (8, 22), GOLD)
    return canvas


def _draw_ember(facing: int, frame: int) -> Canvas:
    """Charcoal body and a swaying flame head."""
    if facing == 3:
        return _draw_ember(2, frame).mirrored()
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    bob = _bob(frame) * 2
    flare = (0, 2, 0, -2)[frame]
    cx, cy = 24, 26 + bob
    canvas.polygon(
        [(cx - 8, cy - 8), (cx - 10 + flare, cy - 18), (cx - 2, cy - 12),
         (cx, cy - 22), (cx + 4, cy - 12), (cx + 10 - flare, cy - 18),
         (cx + 8, cy - 8)],
        OUTLINE,
    )
    canvas.polygon(
        [(cx - 6, cy - 8), (cx - 6, cy - 14), (cx, cy - 18),
         (cx + 6, cy - 14), (cx + 6, cy - 8)],
        EMBER,
    )
    _outlined_ellipse(canvas, cx, cy + 2, 12, 11, OUTLINE, EMBER_DARK)
    if facing == 0:
        _cute_eyes(canvas, cx - 8, cx + 3, cy - 1, FLAME)
    elif facing == 1:
        canvas.rect(cx - 3, cy - 1, cx + 3, cy, STONE_DARK)
    else:
        canvas.rect(cx - 10, cy - 1, cx - 6, cy + 2, OUTLINE)
        canvas.pixel(cx - 9, cy, FLAME)
    return canvas


def _draw_drifter(facing: int, frame: int) -> Canvas:
    """Round moon moth."""
    if facing == 3:
        return _draw_drifter(2, frame).mirrored()
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    wing = (0, -3, 0, 3)[frame]
    bob = 0 if frame in (0, 2) else -2
    cx, cy = 24, 22 + bob
    canvas.polygon(
        [(cx - 4, cy), (cx - 16, cy - 10 + wing), (cx - 20, cy - 2 + wing),
         (cx - 12, cy + 8), (cx - 4, cy + 6)],
        OUTLINE,
    )
    canvas.polygon(
        [(cx - 5, cy), (cx - 14, cy - 7 + wing), (cx - 16, cy - 2 + wing),
         (cx - 10, cy + 6), (cx - 4, cy + 4)],
        BLUE,
    )
    canvas.polygon(
        [(cx + 4, cy), (cx + 16, cy - 10 - wing), (cx + 20, cy - 2 - wing),
         (cx + 12, cy + 8), (cx + 4, cy + 6)],
        OUTLINE,
    )
    canvas.polygon(
        [(cx + 5, cy), (cx + 14, cy - 7 - wing), (cx + 16, cy - 2 - wing),
         (cx + 10, cy + 6), (cx + 4, cy + 4)],
        VIOLET,
    )
    _outlined_disc(canvas, cx, cy + 2, 7, OUTLINE, NAVY)
    if facing == 0:
        _cute_eyes(canvas, cx - 5, cx + 1, cy, PALE)
    elif facing == 1:
        _diamond(canvas, cx, cy + 2, 2, CYAN)
    else:
        canvas.pixel(cx - 4, cy, PALE)
    canvas.line((cx - 2, cy + 8), (cx - 6, cy + 18), OUTLINE)
    canvas.line((cx + 2, cy + 8), (cx + 6, cy + 18), OUTLINE)
    return canvas


def _draw_weaver(facing: int, frame: int) -> Canvas:
    """Cute nucleus with an orbit ring and four tentacles."""
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    bob = _bob(frame) * 2
    cx, cy = 24, 18 + bob
    _ring(canvas, cx, cy, 14, 3, OUTLINE)
    _ring(canvas, cx, cy, 12, 2, CYAN)
    turn = frame % 4
    erase = (
        [(cx - 1, cy - 14), (cx, cy - 14), (cx + 1, cy - 14)],
        [(cx + 14, cy - 1), (cx + 14, cy), (cx + 14, cy + 1)],
        [(cx - 1, cy + 14), (cx, cy + 14), (cx + 1, cy + 14)],
        [(cx - 14, cy - 1), (cx - 14, cy), (cx - 14, cy + 1)],
    )[turn]
    for x, y in erase:
        canvas.pixel(x, y, TRANSPARENT)
    _outlined_disc(canvas, cx, cy, 8, OUTLINE, VIOLET_DARK)
    if facing == 0:
        _cute_eyes(canvas, cx - 5, cx + 1, cy - 2)
    elif facing == 1:
        _diamond(canvas, cx, cy, 3, MOON)
    else:
        canvas.pixel(cx - 3 if facing == 2 else cx + 3, cy, PALE)
    shift = (-2, 0, 2, 0)[frame]
    tentacles = [
        [(cx - 6, cy + 8), (cx - 10 + shift, cy + 16), (cx - 14, cy + 24)],
        [(cx - 2, cy + 8), (cx - 4 - shift, cy + 18), (cx - 6, cy + 26)],
        [(cx + 2, cy + 8), (cx + 4 + shift, cy + 18), (cx + 6, cy + 26)],
        [(cx + 6, cy + 8), (cx + 10 - shift, cy + 16), (cx + 14, cy + 24)],
    ]
    for points in tentacles:
        canvas.line(points[0], points[1], OUTLINE)
        canvas.line(points[1], points[2], OUTLINE)
        canvas.pixel(points[1][0], points[1][1] - 1, VIOLET)
    return canvas


def _draw_caster(facing: int, frame: int) -> Canvas:
    """Round moon-mask robe caster."""
    if facing == 3:
        return _draw_caster(2, frame).mirrored()
    canvas = Canvas(ENEMY_CELL, ENEMY_CELL)
    bob = _bob(frame) * 2
    pulse = frame % 2
    cx, cy = 26, 22 + bob
    canvas.ellipse(cx, cy + 6, 11, 13, OUTLINE)
    canvas.ellipse(cx, cy + 6, 9, 11, VIOLET_DARK)
    _outlined_disc(canvas, cx, cy - 2, 9, OUTLINE, PALE)
    if facing == 0:
        _cute_eyes(canvas, cx - 6, cx + 2, cy - 3, NIGHT)
    elif facing == 1:
        canvas.ellipse(cx, cy - 2, 8, 7, NAVY)
        _diamond(canvas, cx, cy - 2, 2, BLUE)
    else:
        canvas.rect(cx - 8, cy - 3, cx - 5, cy, OUTLINE)
        canvas.pixel(cx - 7, cy - 2, CYAN)
    canvas.line((cx - 14, cy), (cx - 18, cy + 16), OUTLINE)
    canvas.line((cx - 13, cy), (cx - 17, cy + 16), GOLD)
    _ring(canvas, cx - 16, cy - 4, 4 + pulse, 1, MOON)
    canvas.pixel(cx - 16, cy - 4, CYAN)
    return canvas


ENEMY_DRAWERS: dict[str, Callable[[int, int], Canvas]] = {
    "wisp": _draw_wisp,
    "stalker": _draw_stalker,
    "swarm": _draw_swarm,
    "ember": _draw_ember,
    "drifter": _draw_drifter,
    "weaver": _draw_weaver,
    "caster": _draw_caster,
}


def validate_wisp_readability() -> None:
    """Ensure the wisp is not an empty frame and front/back read as different."""
    wisp_palette = frozenset((
        TRANSPARENT, OUTLINE, NAVY, BLUE, CYAN, MOON, PALE,
    ))
    for frame in range(ENEMY_FRAMES):
        down = _draw_wisp(0, frame)
        up = _draw_wisp(1, frame)
        left = _draw_wisp(2, frame)
        right = _draw_wisp(3, frame)
        if bytes(right.pixels) != bytes(left.mirrored().pixels):
            raise RuntimeError(f"wisp f{frame}: left/right are not an exact mirror")
        if bytes(down.pixels) == bytes(up.pixels):
            raise RuntimeError(f"wisp f{frame}: front/back are the same")
        for facing, canvas in ((0, down), (1, up), (2, left), (3, right)):
            unexpected = {
                canvas.get(x, y)
                for y in range(ENEMY_CELL)
                for x in range(ENEMY_CELL)
                if canvas.get(x, y) not in wisp_palette
            }
            if unexpected:
                raise RuntimeError(
                    f"wisp facing {facing} f{frame}: off-palette colors {sorted(unexpected)}"
                )
            opaque = sum(
                1
                for y in range(ENEMY_CELL)
                for x in range(ENEMY_CELL)
                if canvas.get(x, y)[3] > 0
            )
            if opaque < 80:
                raise RuntimeError(
                    f"wisp facing {facing} f{frame}: silhouette too small ({opaque})"
                )


def validate_swarm_side_readability() -> None:
    """Swarm left/right are exact mirrors."""
    for frame in range(ENEMY_FRAMES):
        left = _draw_swarm(2, frame)
        right = _draw_swarm(3, frame)
        if bytes(right.pixels) != bytes(left.mirrored().pixels):
            raise RuntimeError(
                f"swarm side f{frame}: inner lights/tails are not an exact mirror"
            )


def build_enemy_sheet(name: str) -> Canvas:
    sheet = Canvas(ENEMY_CELL * ENEMY_DIRECTIONS, ENEMY_CELL * ENEMY_FRAMES)
    draw = ENEMY_DRAWERS[name]
    for frame in range(ENEMY_FRAMES):
        for facing in range(ENEMY_DIRECTIONS):
            sheet.blit(
                draw(facing, frame),
                facing * ENEMY_CELL,
                frame * ENEMY_CELL,
            )
    return sheet


def _forest_guardian(frame: int, state: str) -> Canvas:
    """Forest continuous-charge guardian that reads as horns, wood arms, and roots."""
    canvas = Canvas(GUARDIAN_CELL, GUARDIAN_CELL)
    bob = (0, -1, 0, 1, 0, -1)[frame % 6]
    branch = (-2, 0, 2, 0)[frame % 4]
    lean = (frame % 2) * 2 if state == "charge" else 0
    if state == "recover":
        bob += 3

    # Left/right horns are the tallest silhouette; they fold back on charge.
    if state == "charge":
        canvas.line((22 + lean, 15 + bob), (8, 9 + branch // 2), OUTLINE)
        canvas.line((42 + lean, 15 + bob), (26, 5 - branch // 2), OUTLINE)
        canvas.line((10, 9 + branch // 2), (5, 13), MOSS_LIGHT)
        canvas.line((28, 6 - branch // 2), (20, 3), MOSS_LIGHT)
    else:
        canvas.line((25, 17 + bob), (17 + branch, 4), OUTLINE)
        canvas.line((17 + branch, 5), (10 + branch, 9), OUTLINE)
        canvas.line((18 + branch, 7), (13 + branch, 3), MOSS_LIGHT)
        canvas.line((39, 17 + bob), (47 - branch, 4), OUTLINE)
        canvas.line((47 - branch, 5), (54 - branch, 9), OUTLINE)
        canvas.line((46 - branch, 7), (51 - branch, 3), MOSS_LIGHT)

    # Long arms. recover plants them on the ground; charge stretches them back as one mass.
    if state == "charge":
        _outlined_polygon(
            canvas,
            [(18 + lean, 23 + bob), (6, 21 + bob), (3, 27 + bob),
             (9, 34 + bob), (22 + lean, 35 + bob)],
            [(18 + lean, 25 + bob), (8, 23 + bob), (6, 27 + bob),
             (10, 31 + bob), (21 + lean, 32 + bob)],
            WOOD,
        )
        _outlined_polygon(
            canvas,
            [(43 + lean, 23 + bob), (58, 17 + bob), (61, 22 + bob),
             (55, 31 + bob), (43 + lean, 35 + bob)],
            [(44 + lean, 25 + bob), (56, 20 + bob), (58, 22 + bob),
             (54, 28 + bob), (43 + lean, 32 + bob)],
            WOOD,
        )
    else:
        arm_drop = 5 if state == "recover" else 0
        _outlined_polygon(
            canvas,
            [(21, 23 + bob), (10, 25 + bob), (4, 37 + bob + arm_drop),
             (7, 49 + bob + arm_drop), (14, 50 + bob + arm_drop),
             (18, 36 + bob)],
            [(20, 26 + bob), (12, 28 + bob), (7, 38 + bob + arm_drop),
             (9, 46 + bob + arm_drop), (12, 47 + bob + arm_drop),
             (15, 34 + bob)],
            WOOD,
        )
        _outlined_polygon(
            canvas,
            [(43, 23 + bob), (54, 25 + bob), (60, 37 + bob + arm_drop),
             (57, 49 + bob + arm_drop), (50, 50 + bob + arm_drop),
             (46, 36 + bob)],
            [(44, 26 + bob), (52, 28 + bob), (57, 38 + bob + arm_drop),
             (55, 46 + bob + arm_drop), (52, 47 + bob + arm_drop),
             (49, 34 + bob)],
            WOOD,
        )

    _outlined_polygon(
        canvas,
        [(20 + lean, 16 + bob), (32 + lean, 11 + bob),
         (44 + lean, 17 + bob), (48 + lean, 34 + bob),
         (42 + lean, 50 + bob), (22 + lean, 50 + bob),
         (16 + lean, 34 + bob)],
        [(23 + lean, 18 + bob), (32 + lean, 14 + bob),
         (41 + lean, 19 + bob), (44 + lean, 34 + bob),
         (39 + lean, 47 + bob), (25 + lean, 47 + bob),
         (20 + lean, 34 + bob)],
        WOOD_DARK,
    )
    # Leaf shoulders make a wide triangle.
    canvas.polygon(
        [(17 + lean, 19 + bob), (9 + lean, 18 + bob),
         (13 + lean, 28 + bob), (23 + lean, 30 + bob)],
        MOSS,
    )
    canvas.polygon(
        [(47 + lean, 19 + bob), (55 + lean, 18 + bob),
         (51 + lean, 28 + bob), (41 + lean, 30 + bob)],
        MOSS,
    )
    canvas.pixel(12 + lean, 20 + bob, MOSS_LIGHT)
    canvas.pixel(52 + lean, 20 + bob, MOSS_LIGHT)

    core_radius = 5 if state == "windup" else 4
    _outlined_disc(canvas, 32 + lean, 29 + bob, core_radius, OUTLINE, CYAN)
    _diamond(canvas, 32 + lean, 29 + bob, 2, PALE)
    _cute_eyes(canvas, 26 + lean, 34 + lean, 22 + bob, PALE)
    canvas.line((32 + lean, 34 + bob), (32 + lean, 43 + bob), MOSS_LIGHT)
    canvas.line((26 + lean, 38 + bob), (32 + lean, 43 + bob), MOSS)
    canvas.line((38 + lean, 38 + bob), (32 + lean, 43 + bob), MOSS)

    # Roots touch the floor and leave a huge mass.
    root_y = 62
    canvas.polygon(
        [(21 + lean, 47 + bob), (29 + lean, 47 + bob),
         (28 + lean, 58), (20 + lean, root_y), (8 + lean, root_y),
         (16 + lean, 57)],
        OUTLINE,
    )
    canvas.polygon(
        [(23 + lean, 48 + bob), (27 + lean, 49 + bob),
         (26 + lean, 56), (20 + lean, 60), (14 + lean, 60),
         (19 + lean, 55)],
        WOOD,
    )
    canvas.polygon(
        [(35 + lean, 47 + bob), (43 + lean, 47 + bob),
         (48 + lean, 57), (56 + lean, root_y), (43 + lean, root_y),
         (36 + lean, 58)],
        OUTLINE,
    )
    canvas.polygon(
        [(37 + lean, 49 + bob), (41 + lean, 48 + bob),
         (45 + lean, 55), (50 + lean, 60), (44 + lean, 60),
         (38 + lean, 56)],
        WOOD,
    )
    if state == "recover":
        canvas.line((26 + lean, 28 + bob), (31 + lean, 32 + bob), PALE)
        canvas.line((38 + lean, 28 + bob), (33 + lean, 32 + bob), PALE)
    return canvas


def _field_guardian(frame: int, state: str) -> Canvas:
    """Floating field guardian with crescent wings and a mask, no tail."""
    canvas = Canvas(GUARDIAN_CELL, GUARDIAN_CELL)
    bob = (0, -2, -1, 1, 2, 1)[frame % 6]
    spread = (0, 2, 1, -1)[frame % 4]
    folded = state == "recover"

    # Large crescent wings make a horizontal silhouette opposite the tree and keep types.
    left_outer = (
        [(28, 22 + bob), (19, 8 + bob), (8, 4 + bob), (3, 12 + bob),
         (8, 29 + bob), (22, 37 + bob), (29, 33 + bob)]
        if not folded else
        [(28, 22 + bob), (21, 13 + bob), (14, 10 + bob),
         (11, 18 + bob), (17, 33 + bob), (27, 38 + bob)]
    )
    left_inner = (
        [(26, 23 + bob), (18, 11 + bob), (9, 7 + bob), (6, 12 + bob),
         (11, 26 + bob), (22, 33 + bob), (27, 31 + bob)]
        if not folded else
        [(26, 23 + bob), (21, 16 + bob), (16, 13 + bob),
         (14, 18 + bob), (19, 30 + bob), (27, 34 + bob)]
    )
    _outlined_polygon(canvas, left_outer, left_inner, BLUE)
    right = Canvas(GUARDIAN_CELL, GUARDIAN_CELL)
    _outlined_polygon(right, left_outer, left_inner, VIOLET)
    canvas.blit(right.mirrored(), 0, 0)

    # Moon-gates at the outer wing tips. Cross vs radial windup differs by kind.
    canvas.line((9, 12 + bob), (20, 28 + bob), CYAN)
    canvas.line((55, 12 + bob), (44, 28 + bob), VIOLET_LIGHT)
    if state == "cross":
        canvas.rect(6 - spread, 16 + bob, 21, 18 + bob, PALE)
        canvas.rect(14, 8 + bob - spread, 16, 25 + bob, PALE)
        canvas.rect(43, 16 + bob, 58 + spread, 18 + bob, PALE)
        canvas.rect(48, 8 + bob - spread, 50, 25 + bob, PALE)
    elif state == "radial":
        for x, y in (
            (7 - spread // 2, 10), (12, 7 - spread // 2), (21, 9),
            (57 + spread // 2, 10), (52, 7 - spread // 2), (43, 9),
            (8, 27 + spread // 2), (56, 27 + spread // 2),
        ):
            _diamond(canvas, x, y + bob, 2, PALE)

    # Mask and a long scattering cloud robe.
    _outlined_polygon(
        canvas,
        [(23, 18 + bob), (32, 11 + bob), (41, 18 + bob),
         (43, 31 + bob), (38, 40 + bob), (26, 40 + bob),
         (21, 31 + bob)],
        [(26, 19 + bob), (32, 14 + bob), (38, 19 + bob),
         (40, 30 + bob), (36, 37 + bob), (28, 37 + bob),
         (24, 30 + bob)],
        VIOLET_DARK,
    )
    _outlined_disc(canvas, 32, 21 + bob, 8, OUTLINE, PALE)
    _cute_eyes(canvas, 26, 34, 19 + bob, NIGHT)
    _diamond(canvas, 32, 26 + bob, 2, BLUE)
    _outlined_disc(canvas, 32, 35 + bob, 5, OUTLINE, CYAN)
    _diamond(canvas, 32, 35 + bob, 2, PALE)

    wave = (-2, 0, 2, 0)[frame % 4]
    tendrils = [
        [(27, 38 + bob), (20 + wave, 47 + bob), (13, 52 + bob), (8, 49 + bob)],
        [(30, 39 + bob), (27 - wave, 49 + bob), (22, 57 + bob), (17, 58 + bob)],
        [(34, 39 + bob), (37 + wave, 49 + bob), (42, 57 + bob), (47, 58 + bob)],
        [(37, 38 + bob), (44 - wave, 47 + bob), (51, 52 + bob), (56, 49 + bob)],
    ]
    for index, points in enumerate(tendrils):
        for first, second in zip(points, points[1:]):
            canvas.line(first, second, OUTLINE)
            canvas.pixel(first[0], first[1] - 1, CYAN if index < 2 else VIOLET_LIGHT)
    return canvas


def _camp_guardian(frame: int, state: str) -> Canvas:
    """Slow camp siege guardian with a gate-shield and beacon brazier."""
    canvas = Canvas(GUARDIAN_CELL, GUARDIAN_CELL)
    bob = (0, -1, 0, 1, 0, -1)[frame % 6]
    hammer = (-1, 0, 1, 0)[frame % 4]
    opened = state == "recover"

    # Hammer arm.
    _outlined_polygon(
        canvas,
        [(24, 25 + bob), (13, 27 + bob), (7, 38 + bob),
         (12, 44 + bob), (22, 36 + bob)],
        [(22, 28 + bob), (15, 30 + bob), (10, 38 + bob),
         (13, 41 + bob), (20, 34 + bob)],
        STONE,
    )
    canvas.line((12, 39 + bob), (7 + hammer, 53), OUTLINE)
    canvas.line((13, 39 + bob), (8 + hammer, 53), GOLD)
    _outlined_polygon(
        canvas,
        [(3 + hammer, 49), (13 + hammer, 47), (18 + hammer, 54),
         (12 + hammer, 61), (3 + hammer, 59)],
        [(6 + hammer, 51), (12 + hammer, 50), (15 + hammer, 54),
         (11 + hammer, 58), (6 + hammer, 57)],
        STONE_DARK,
    )
    canvas.pixel(8 + hammer, 53, FLAME)

    # The body makes a rectangular mass from vertical plate and a roof.
    _outlined_polygon(
        canvas,
        [(20, 15 + bob), (39, 12 + bob), (48, 21 + bob),
         (48, 51 + bob), (41, 58), (24, 58),
         (18, 48 + bob)],
        [(23, 18 + bob), (38, 15 + bob), (45, 22 + bob),
         (45, 49 + bob), (39, 55), (26, 55),
         (21, 47 + bob)],
        STONE_DARK,
    )
    canvas.polygon(
        [(18, 16 + bob), (23, 9 + bob), (40, 9 + bob),
         (47, 16 + bob), (43, 20 + bob), (22, 20 + bob)],
        OUTLINE,
    )
    canvas.polygon(
        [(22, 15 + bob), (25, 11 + bob), (38, 11 + bob),
         (43, 15 + bob), (41, 17 + bob), (24, 17 + bob)],
        STONE,
    )
    canvas.rect(30, 5 + bob, 34, 10 + bob, OUTLINE)
    canvas.polygon(
        [(29, 6 + bob), (32, 3 + bob), (35, 6 + bob)],
        GOLD,
    )

    # Brazier head. Flame grows on windup; the door opens on recover and the core shows.
    flame_height = 9 if state == "windup" else 6
    canvas.rect(25, 17 + bob, 39, 29 + bob, OUTLINE)
    canvas.rect(28, 19 + bob, 36, 27 + bob, EMBER_DARK)
    canvas.polygon(
        [(29, 26 + bob), (28, 21 + bob), (31, 23 + bob),
         (32, 17 + bob - flame_height // 3), (34, 23 + bob),
         (37, 19 + bob), (36, 26 + bob)],
        EMBER,
    )
    canvas.polygon(
        [(31, 26 + bob), (31, 22 + bob), (33, 19 + bob),
         (35, 23 + bob), (35, 26 + bob)],
        FLAME,
    )
    canvas.rect(28, 29 + bob, 37, 33 + bob, GOLD)
    canvas.rect(30, 30 + bob, 35, 32 + bob, OUTLINE)

    if opened:
        # Two plates open and a bright weak point shows.
        canvas.polygon(
            [(21, 33 + bob), (29, 35 + bob), (27, 51 + bob),
             (20, 47 + bob)],
            STONE,
        )
        canvas.polygon(
            [(43, 33 + bob), (35, 35 + bob), (37, 51 + bob),
             (44, 47 + bob)],
            STONE,
        )
        _outlined_disc(canvas, 32, 42 + bob, 6, OUTLINE, EMBER)
        _diamond(canvas, 32, 42 + bob, 3, FLAME)
    else:
        canvas.rect(24, 34 + bob, 40, 50 + bob, STONE)
        canvas.rect(26, 36 + bob, 38, 48 + bob, STONE_DARK)
        _ring(canvas, 32, 42 + bob, 5, 2, GOLD)
        canvas.pixel(32, 42 + bob, EMBER)

    # Gate shield. A separate large square so it never overlaps another boss.
    shield_x = 45 if not opened else 48
    _outlined_polygon(
        canvas,
        [(shield_x, 20 + bob), (59, 17 + bob), (61, 22 + bob),
         (61, 57), (54, 62), (shield_x, 57)],
        [(shield_x + 2, 22 + bob), (57, 20 + bob), (59, 23 + bob),
         (59, 55), (54, 59), (shield_x + 2, 55)],
        STONE,
    )
    canvas.line((shield_x + 4, 27 + bob), (57, 27 + bob), GOLD)
    canvas.line((shield_x + 4, 48 + bob), (57, 48 + bob), GOLD)
    _ring(canvas, 53, 38 + bob, 6, 2, OUTLINE)
    _diamond(canvas, 53, 38 + bob, 3, GOLD)

    # Two heavy feet.
    canvas.polygon(
        [(23, 50 + bob), (31, 50 + bob), (30, 59),
         (26, 62), (18, 62), (20, 57)],
        OUTLINE,
    )
    canvas.polygon(
        [(25, 52 + bob), (29, 52 + bob), (28, 57),
         (25, 60), (21, 60), (23, 56)],
        STONE,
    )
    canvas.polygon(
        [(34, 50 + bob), (42, 50 + bob), (44, 57),
         (46, 62), (36, 62), (34, 58)],
        OUTLINE,
    )
    canvas.polygon(
        [(36, 52 + bob), (40, 52 + bob), (41, 56),
         (42, 60), (38, 60), (36, 57)],
        STONE,
    )
    return canvas


def _paint_thorns(canvas: Canvas, frame: int, state: str) -> Canvas:
    """Cycle-2 forest — more horns and violet thorns."""
    bob = (0, -1, 0, 1, 0, -1)[frame % 6]
    lean = (frame % 2) * 2 if state == "charge" else 0
    for x0, y0, x1, y1 in (
        (18 + lean, 10 + bob, 10 + lean, 4 + bob),
        (46 + lean, 10 + bob, 54 + lean, 4 + bob),
        (22 + lean, 20 + bob, 12 + lean, 12 + bob),
        (42 + lean, 20 + bob, 52 + lean, 12 + bob),
    ):
        canvas.line((x0, y0), (x1, y1), OUTLINE)
        canvas.pixel(x1, y1, VIOLET_LIGHT)
    canvas.pixel(32 + lean, 16 + bob, VIOLET)
    canvas.pixel(31 + lean, 17 + bob, VIOLET_LIGHT)
    return canvas


def _forest_thorn_guardian(frame: int, state: str) -> Canvas:
    return _paint_thorns(_forest_guardian(frame, state), frame, state)


def _paint_storm(canvas: Canvas, frame: int) -> Canvas:
    """Cycle-2 field — lightning crescents on the wing tips."""
    bob = (0, -2, -1, 1, 2, 1)[frame % 6]
    for x, y in ((6, 8 + bob), (58, 8 + bob), (10, 22 + bob), (54, 22 + bob)):
        _diamond(canvas, x, y, 2, GOLD)
        canvas.pixel(x, y, FLAME)
    canvas.line((8, 14 + bob), (18, 22 + bob), CYAN)
    canvas.line((56, 14 + bob), (46, 22 + bob), CYAN)
    return canvas


def _field_storm_guardian(frame: int, state: str) -> Canvas:
    return _paint_storm(_field_guardian(frame, state), frame)


def _paint_siege(canvas: Canvas, frame: int, state: str) -> Canvas:
    """Cycle-2 camp — a hammer on the other side too, and a larger brazier."""
    bob = (0, -1, 0, 1, 0, -1)[frame % 6]
    hammer = (1, 0, -1, 0)[frame % 4]
    _outlined_polygon(
        canvas,
        [(40, 25 + bob), (51, 27 + bob), (57, 38 + bob),
         (52, 44 + bob), (42, 36 + bob)],
        [(42, 28 + bob), (49, 30 + bob), (54, 38 + bob),
         (51, 41 + bob), (44, 34 + bob)],
        STONE,
    )
    canvas.line((52, 39 + bob), (57 + hammer, 53), OUTLINE)
    canvas.line((53, 39 + bob), (58 + hammer, 53), GOLD)
    _outlined_disc(canvas, 32, 22 + bob, 4, OUTLINE, FLAME)
    # Crown thorns poke above the existing silhouette so it is distinct from cycle-1 plate.
    canvas.line((28, 10 + bob), (24, 4 + bob), OUTLINE)
    canvas.line((36, 10 + bob), (40, 4 + bob), OUTLINE)
    canvas.pixel(24, 4 + bob, GOLD)
    canvas.pixel(40, 4 + bob, GOLD)
    if state == "windup":
        canvas.pixel(32, 18 + bob, GOLD)
        canvas.pixel(30, 20 + bob, EMBER)
        canvas.pixel(34, 20 + bob, EMBER)
    return canvas


def _camp_siege_guardian(frame: int, state: str) -> Canvas:
    return _paint_siege(_camp_guardian(frame, state), frame, state)


GUARDIAN_DRAWERS: dict[str, Callable[[int, str], Canvas]] = {
    "forest": _forest_guardian,
    "field": _field_guardian,
    "camp": _camp_guardian,
    "forest_thorn": _forest_thorn_guardian,
    "field_storm": _field_storm_guardian,
    "camp_siege": _camp_siege_guardian,
}


def build_guardian_sheet(name: str, state: str, frames: int) -> Canvas:
    sheet = Canvas(GUARDIAN_CELL * frames, GUARDIAN_CELL)
    draw = GUARDIAN_DRAWERS[name]
    for frame in range(frames):
        sheet.blit(draw(frame, state), frame * GUARDIAN_CELL, 0)
    return sheet


def _production() -> dict[Path, Canvas]:
    # Regular spirit sheets have been made by pack_grok_spirits.py since the 2026-08 art refresh.
    # Grok/Ludo ghost sources. This file owns only guardians.
    # (ENEMY_DRAWERS is left as a record of the old procedural create — silhouette checks
    # still reference them, and they can be turned back on here if we ever revert.)
    production: dict[Path, Canvas] = {}

    guardian_states = {
        "forest": (
            ("forest.png", "idle", 6),
            ("forest_windup.png", "windup", 4),
            ("forest_charge.png", "charge", 4),
            ("forest_recover.png", "recover", 4),
        ),
        "field": (
            ("field.png", "idle", 6),
            ("field_windup_cross.png", "cross", 4),
            ("field_windup_radial.png", "radial", 4),
            ("field_recover.png", "recover", 4),
        ),
        "camp": (
            ("camp.png", "idle", 6),
            ("camp_windup.png", "windup", 4),
            ("camp_recover.png", "recover", 4),
        ),
        "forest_thorn": (
            ("forest_thorn.png", "idle", 6),
            ("forest_thorn_windup.png", "windup", 4),
            ("forest_thorn_charge.png", "charge", 4),
            ("forest_thorn_recover.png", "recover", 4),
        ),
        "field_storm": (
            ("field_storm.png", "idle", 6),
            ("field_storm_windup_cross.png", "cross", 4),
            ("field_storm_windup_radial.png", "radial", 4),
            ("field_storm_recover.png", "recover", 4),
        ),
        "camp_siege": (
            ("camp_siege.png", "idle", 6),
            ("camp_siege_windup.png", "windup", 4),
            ("camp_siege_recover.png", "recover", 4),
        ),
    }
    # Guardian sheets come from painted art since 2.0.0 — `pack_ludo_guardians.py`.
    # Do not bake them here.
    #
    # Do not delete `GUARDIAN_DRAWERS` and `build_guardian_sheet()`. Frame counts
    # (idle 6, combat 4) and state names are written here, and the new packer follows that table
    # as-is. File existence and spec are the `check_custom_assets.py` contract.
    for name, states in guardian_states.items():
        for filename, _state, _frames in states:
            if not (GUARDIAN_ROOT / filename).is_file():
                raise RuntimeError(f"production guardian sheet is missing: {filename}")
    return production


def build_preview(production: dict[Path, Canvas]) -> Canvas:
    scale = 4
    margin = 12
    enemy_gap = 8
    enemy_width = ENEMY_CELL * scale
    width = margin * 2 + 7 * enemy_width + 6 * enemy_gap
    enemy_y = margin
    boss_y = enemy_y + ENEMY_CELL * scale + 24
    boss_scale = 3
    boss_width = GUARDIAN_CELL * boss_scale
    boss_gap = (width - margin * 2 - boss_width * 3) // 2
    height = boss_y + GUARDIAN_CELL * boss_scale + margin
    preview = Canvas(width, height, NIGHT)

    for index, name in enumerate(ENEMY_DRAWERS):
        sheet = production[SPIRIT_ROOT / f"{name}.png"]
        first = Canvas(ENEMY_CELL, ENEMY_CELL)
        for y in range(ENEMY_CELL):
            for x in range(ENEMY_CELL):
                first.pixel(x, y, sheet.get(x, y))
        preview.blit_scaled(
            first,
            margin + index * (enemy_width + enemy_gap),
            enemy_y,
            scale,
        )

    for index, name in enumerate(("forest", "field", "camp")):
        if GUARDIAN_ROOT / f"{name}.png" not in production:
            continue                      # guardians are baked by a separate packer
        sheet = production[GUARDIAN_ROOT / f"{name}.png"]
        first = Canvas(GUARDIAN_CELL, GUARDIAN_CELL)
        for y in range(GUARDIAN_CELL):
            for x in range(GUARDIAN_CELL):
                first.pixel(x, y, sheet.get(x, y))
        preview.blit_scaled(
            first,
            margin + index * (boss_width + boss_gap),
            boss_y,
            boss_scale,
        )
    return preview


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="inspect without writing that production PNG matches the deterministic result",
    )
    args = parser.parse_args()
    validate_wisp_readability()
    validate_swarm_side_readability()
    production = _production()

    if args.check:
        for path, canvas in production.items():
            if not path.is_file():
                raise RuntimeError(f"production spirit PNG is missing: {path}")
            if path.read_bytes() != canvas.to_png():
                raise RuntimeError(
                    f"production spirit PNG differs from the created result: {path}. "
                    "run build_spirit_guardian_assets.py again"
                )
    else:
        for path, canvas in production.items():
            canvas.save(path)
        preview = build_preview(production)
        preview.save(REVIEW_DIR / "spirit-guardian-preview.png")

    print(
        f"Moonlit bestiary: {len(ENEMY_DRAWERS)} regular spirits, "
        f"{len(production) - len(ENEMY_DRAWERS)} guardian sheets"
    )
    print(
        "check: production PNGs are deterministic"
        if args.check
        else f"review: {REVIEW_DIR / 'spirit-guardian-preview.png'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
