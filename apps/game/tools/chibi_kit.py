#!/usr/bin/env python3
"""Shared kit that deterministically draws cute 2-head 48×64 heroes.

Move the old 24×32 'little guardian' silhouette up 2×. Head is a round hood, body a
short tapering cloak, face is only eyes and cheeks. Cramming in a nose and mouth on a small screen
looks grotesque. Freeze the torso outline on walk frames to stop a double outline at 4×.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

from pixel_canvas import RGBA, Canvas, TRANSPARENT


CELL_WIDTH = 48
CELL_HEIGHT = 64
DIRECTIONS = 4
FRAMES = 4
PORTRAIT_SIZE = 96
LIGHT_Y = 44
JOIN_Y = 38

OUTLINE: RGBA = (36, 28, 54, 255)
SKIN: RGBA = (255, 214, 186, 255)
SKIN_SHADOW: RGBA = (232, 164, 142, 255)
BLUSH: RGBA = (255, 132, 156, 255)
BLUSH_SOFT: RGBA = (255, 176, 192, 255)
EYE_WHITE: RGBA = (255, 252, 248, 255)
EYE_LINE: RGBA = (48, 32, 64, 255)
MOON_MID: RGBA = (126, 214, 232, 255)
MOON_BRIGHT: RGBA = (220, 246, 255, 255)
MOON_CORE: RGBA = (255, 250, 224, 255)
GOLD: RGBA = (255, 206, 92, 255)


@dataclass(frozen=True)
class CuteHeroStyle:
    name: str
    hood_dark: RGBA
    hood: RGBA
    hood_light: RGBA
    coat_dark: RGBA
    coat: RGBA
    coat_light: RGBA
    hair_dark: RGBA
    hair: RGBA
    hair_light: RGBA
    accent: RGBA
    accent_light: RGBA
    core: RGBA
    rim: RGBA
    motif: str
    max_front_width: int = 34
    max_side_width: int = 26
    max_lower_body_width: int = 22


HEAD_CX = 24
HEAD_CY = 22
HEAD_R = 13
BODY_CY = 48


def moon_seed_color(frame: int, idle: bool) -> RGBA:
    if not idle:
        return MOON_BRIGHT
    return (MOON_MID, MOON_BRIGHT, MOON_CORE, MOON_BRIGHT)[frame]


def _plump_disc(
    canvas: Canvas,
    cx: int,
    cy: int,
    radius: int,
    fill: RGBA,
    highlight: RGBA | None = None,
    shadow: RGBA | None = None,
) -> None:
    """A round mass. Top highlight and bottom shadow make it read as a ball, not an egg."""
    canvas.disc(cx, cy, radius, fill)
    if highlight is not None and radius > 3:
        canvas.ellipse(cx - 1, cy - 2, max(radius - 4, 2), max(radius - 5, 2), highlight)
        canvas.pixel(cx - radius + 3, cy - 2, highlight)
    if shadow is not None and radius > 3:
        canvas.ellipse(cx, cy + radius - 3, max(radius - 3, 2), 3, shadow)


def _draw_hood_shell(canvas: Canvas, style: CuteHeroStyle, cx: int, cy: int) -> None:
    canvas.disc(cx, cy, HEAD_R + 2, style.hood)
    canvas.ellipse(cx, cy - 3, HEAD_R - 1, HEAD_R - 3, style.hood_light)
    canvas.ellipse(cx, cy - HEAD_R + 2, 6, 4, style.hood_dark)
    if style.motif == "crescent":
        canvas.disc(cx - 8, cy - HEAD_R + 1, 4, style.hood)
        canvas.disc(cx + 8, cy - HEAD_R + 1, 4, style.hood)
        canvas.disc(cx - 8, cy - HEAD_R + 1, 2, style.hood_light)
        canvas.disc(cx + 8, cy - HEAD_R + 1, 2, style.hood_light)
    elif style.motif == "lantern":
        canvas.ellipse(cx, cy - HEAD_R + 1, 5, 4, style.hood_dark)
        canvas.pixel(cx, cy - HEAD_R - 1, style.accent)
    elif style.motif == "stars":
        canvas.pixel(cx, cy - HEAD_R - 1, GOLD)
        canvas.pixel(cx - 1, cy - HEAD_R, GOLD)
        canvas.pixel(cx + 1, cy - HEAD_R, GOLD)


def _draw_cute_eye(
    canvas: Canvas, left: int, top: int, blink: bool, iris: RGBA, wide: bool = True
) -> None:
    width = 6 if wide else 4
    height = 5 if wide else 4
    if blink:
        canvas.rect(left, top + 2, left + width, top + 2, EYE_LINE)
        canvas.pixel(left, top + 1, EYE_LINE)
        canvas.pixel(left + width, top + 1, EYE_LINE)
        return
    canvas.rect(left, top, left + width, top + height, EYE_LINE)
    canvas.rect(left + 1, top + 1, left + width - 1, top + height - 1, EYE_WHITE)
    iris_left = left + (2 if wide else 1)
    canvas.rect(iris_left, top + 2, iris_left + 2, top + height - 1, iris)
    canvas.pixel(iris_left + 1, top + 3, EYE_LINE)
    canvas.pixel(left + 1, top + 1, MOON_CORE)
    if wide:
        canvas.pixel(left + 2, top + 1, MOON_CORE)


def _draw_smile(canvas: Canvas, cx: int, cy: int) -> None:
    canvas.pixel(cx - 2, cy, SKIN_SHADOW)
    canvas.pixel(cx - 1, cy + 1, SKIN_SHADOW)
    canvas.pixel(cx, cy + 1, SKIN_SHADOW)
    canvas.pixel(cx + 1, cy + 1, SKIN_SHADOW)
    canvas.pixel(cx + 2, cy, SKIN_SHADOW)


def _draw_blush(canvas: Canvas, left: int, right: int, y: int) -> None:
    canvas.rect(left, y, left + 2, y + 1, BLUSH_SOFT)
    canvas.rect(right, y, right + 2, y + 1, BLUSH_SOFT)
    canvas.pixel(left + 1, y + 1, BLUSH)
    canvas.pixel(right + 1, y + 1, BLUSH)


def _draw_bangs(canvas: Canvas, style: CuteHeroStyle, cx: int, cy: int) -> None:
    canvas.ellipse(cx, cy - 4, 10, 6, style.hair)
    canvas.disc(cx - 8, cy - 1, 4, style.hair)
    canvas.disc(cx + 8, cy - 1, 4, style.hair)
    canvas.pixel(cx - 6, cy - 6, style.hair_light)
    canvas.pixel(cx - 5, cy - 7, style.hair_light)
    canvas.pixel(cx + 5, cy - 6, style.hair_light)


def _draw_front_face(canvas: Canvas, style: CuteHeroStyle, blink: bool) -> None:
    canvas.disc(HEAD_CX, HEAD_CY + 3, 11, SKIN)
    canvas.ellipse(HEAD_CX, HEAD_CY + 5, 8, 7, SKIN)
    _draw_bangs(canvas, style, HEAD_CX, HEAD_CY)
    _draw_cute_eye(canvas, 14, 21, blink, style.hair_dark)
    _draw_cute_eye(canvas, 28, 21, blink, style.hair_dark)
    _draw_blush(canvas, 13, 33, 30)
    _draw_smile(canvas, HEAD_CX, 34)


def _draw_side_face(canvas: Canvas, style: CuteHeroStyle, blink: bool) -> None:
    canvas.disc(16, HEAD_CY + 3, 7, SKIN)
    canvas.ellipse(18, HEAD_CY + 4, 6, 6, SKIN)
    canvas.ellipse(20, HEAD_CY - 3, 8, 6, style.hair)
    canvas.disc(22, HEAD_CY - 1, 5, style.hair)
    canvas.pixel(18, HEAD_CY - 6, style.hair_light)
    canvas.pixel(19, HEAD_CY - 7, style.hair_light)
    _draw_cute_eye(canvas, 11, 22, blink, style.hair_dark, wide=False)
    canvas.pixel(11, 30, BLUSH)
    canvas.pixel(12, 31, BLUSH_SOFT)
    canvas.pixel(16, 33, SKIN_SHADOW)
    canvas.pixel(17, 34, SKIN_SHADOW)
    canvas.pixel(18, 34, SKIN_SHADOW)


def _draw_front_body(canvas: Canvas, style: CuteHeroStyle) -> None:
    _plump_disc(
        canvas, HEAD_CX, BODY_CY, 10, style.coat, style.coat_light, style.coat_dark
    )
    canvas.ellipse(HEAD_CX, BODY_CY + 2, 7, 8, style.coat_dark)
    canvas.disc(HEAD_CX - 8, 42, 3, style.coat)
    canvas.disc(HEAD_CX + 8, 42, 3, style.coat)
    canvas.pixel(HEAD_CX - 8, 40, style.coat_light)
    canvas.pixel(HEAD_CX + 8, 40, style.coat_light)
    _draw_hood_shell(canvas, style, HEAD_CX, HEAD_CY)


def _draw_side_body(canvas: Canvas, style: CuteHeroStyle) -> None:
    _plump_disc(canvas, 21, BODY_CY, 8, style.coat, style.coat_light, style.coat_dark)
    canvas.ellipse(21, BODY_CY + 2, 6, 8, style.coat_dark)
    canvas.disc(15, 43, 3, style.coat)
    _draw_hood_shell(canvas, style, 21, HEAD_CY)
    canvas.ellipse(26, HEAD_CY, 8, 12, style.hood)
    canvas.ellipse(26, HEAD_CY - 2, 6, 8, style.hood_light)


def _draw_back_hair(canvas: Canvas, style: CuteHeroStyle) -> None:
    canvas.disc(HEAD_CX, HEAD_CY + 2, 11, style.hair)
    canvas.ellipse(HEAD_CX, HEAD_CY + 6, 10, 7, style.hair)
    canvas.ellipse(HEAD_CX, HEAD_CY - 2, 10, 8, style.hood)
    canvas.pixel(HEAD_CX - 4, HEAD_CY, style.hair_light)
    canvas.pixel(HEAD_CX + 4, HEAD_CY, style.hair_light)
    canvas.pixel(HEAD_CX, HEAD_CY + 4, style.hair_dark)
    canvas.pixel(HEAD_CX - 7, HEAD_CY + 6, style.hair_dark)
    canvas.pixel(HEAD_CX + 7, HEAD_CY + 6, style.hair_dark)


def _draw_motif(canvas: Canvas, style: CuteHeroStyle, frame: int, idle: bool, side: bool) -> None:
    glow = moon_seed_color(frame, idle)
    cx = 17 if side else 24
    cy = LIGHT_Y
    if style.motif == "seed":
        canvas.outlined_disc(cx, cy, 5, MOON_MID, glow)
        canvas.disc(cx, cy, 2, MOON_CORE)
        if not side:
            canvas.rect(cx - 8, cy + 1, cx - 6, cy + 3, SKIN)
            canvas.rect(cx + 6, cy + 1, cx + 8, cy + 3, SKIN)
        else:
            canvas.rect(cx + 4, cy + 1, cx + 6, cy + 3, SKIN)
    elif style.motif == "crescent":
        canvas.ring(cx - 6, cy, 4, 2, glow)
        canvas.ring(cx + 6, cy, 4, 2, glow)
        canvas.pixel(cx - 6, cy, style.core)
        canvas.pixel(cx + 6, cy, style.core)
        canvas.pixel(cx, cy, style.accent_light)
    elif style.motif == "lantern":
        canvas.rect(cx - 3, cy - 4, cx + 3, cy + 4, style.accent)
        canvas.rect(cx - 2, cy - 3, cx + 2, cy + 3, glow)
        canvas.pixel(cx, cy, style.core)
        canvas.rect(cx - 1, cy - 6, cx + 1, cy - 5, GOLD)
        canvas.rect(cx - 4, cy + 2, cx - 3, cy + 3, SKIN)
        canvas.rect(cx + 3, cy + 2, cx + 4, cy + 3, SKIN)
    elif style.motif == "silver":
        canvas.outlined_disc(cx, cy, 5, style.accent, glow)
        canvas.pixel(cx, cy - 1, MOON_CORE)
        canvas.pixel(cx - 2, cy, style.core)
        canvas.pixel(cx + 2, cy, style.core)
    elif style.motif == "eclipse":
        canvas.outlined_disc(cx, cy, 5, style.accent, style.hood_dark)
        canvas.disc(cx + 1, cy - 1, 2, glow)
        canvas.pixel(cx, cy, style.core)
    elif style.motif == "stars":
        canvas.pixel(cx, cy - 3, style.accent)
        canvas.pixel(cx, cy, glow)
        canvas.pixel(cx, cy + 3, style.accent_light)
        canvas.pixel(cx - 4, cy, style.accent)
        canvas.pixel(cx + 4, cy, style.accent_light)
        canvas.pixel(cx - 2, cy - 2, MOON_CORE)
        canvas.pixel(cx + 2, cy + 2, MOON_CORE)
    else:
        canvas.outlined_disc(cx, cy, 5, MOON_MID, glow)
        canvas.disc(cx, cy, 2, style.core)


def _draw_front_feet(canvas: Canvas, style: CuteHeroStyle, frame: int, idle: bool) -> None:
    if idle:
        poses = ((16, 59), (26, 59))
    else:
        poses = (
            ((14, 59), (28, 57)),
            ((16, 57), (26, 59)),
            ((15, 59), (29, 57)),
            ((17, 57), (27, 59)),
        )[frame]
    for x0, top in poses:
        canvas.rect(x0, top, x0 + 6, top + 4, OUTLINE)
        canvas.rect(x0 + 1, top + 1, x0 + 5, top + 3, style.coat_dark)
        canvas.pixel(x0 + 2, top + 2, style.coat_light)
        if top + 4 >= CELL_HEIGHT - 1:
            canvas.rect(x0, CELL_HEIGHT - 1, x0 + 6, CELL_HEIGHT - 1, style.coat_dark)


def _draw_side_feet(canvas: Canvas, style: CuteHeroStyle, frame: int, idle: bool) -> None:
    if idle:
        poses = ((14, 59), (22, 59))
    else:
        poses = (
            ((12, 59), (24, 57)),
            ((15, 57), (22, 59)),
            ((13, 59), (25, 57)),
            ((16, 57), (23, 59)),
        )[frame]
    for x0, top in poses:
        canvas.rect(x0, top, x0 + 6, top + 4, OUTLINE)
        canvas.rect(x0 + 1, top + 1, x0 + 5, top + 3, style.coat_dark)
        if top + 4 >= CELL_HEIGHT - 1:
            canvas.rect(x0, CELL_HEIGHT - 1, x0 + 6, CELL_HEIGHT - 1, style.coat_dark)


def _draw_pin(canvas: Canvas, style: CuteHeroStyle, x: int, y: int) -> None:
    canvas.pixel(x, y, GOLD)
    canvas.pixel(x + 1, y + 1, GOLD)
    canvas.pixel(x + 1, y, style.core)


def _apply_rim(canvas: Canvas, rim: RGBA) -> None:
    for y in range(1, 34):
        for x in range(canvas.width):
            if canvas.get(x, y) != OUTLINE:
                continue
            if canvas.get(x, y - 1)[3] != 0:
                continue
            if y > 28 and 12 < x < 36:
                continue
            canvas.pixel(x, y, rim)


def _freeze_upper(base: Canvas, canvas: Canvas, through_y: int) -> None:
    for y in range(through_y + 1):
        for x in range(canvas.width):
            canvas.pixel(x, y, base.get(x, y))


def _paint_hero_pose(
    style: CuteHeroStyle, direction: int, frame: int, idle: bool
) -> Canvas:
    if direction == 3:
        return _paint_hero_pose(style, 2, frame, idle).mirrored()

    canvas = Canvas(CELL_WIDTH, CELL_HEIGHT)
    blink = idle and frame == 2
    if direction == 0:
        _draw_front_body(canvas, style)
        _draw_front_face(canvas, style, blink)
        _draw_motif(canvas, style, frame, idle, side=False)
        _draw_pin(canvas, style, 32, 14)
        canvas.outline_opaque(OUTLINE)
        _draw_front_face(canvas, style, blink)
        _draw_motif(canvas, style, frame, idle, side=False)
        _draw_front_feet(canvas, style, frame, idle)
    elif direction == 1:
        _draw_front_body(canvas, style)
        _draw_back_hair(canvas, style)
        _draw_motif(canvas, style, frame, idle, side=False)
        canvas.outline_opaque(OUTLINE)
        _draw_back_hair(canvas, style)
        _draw_motif(canvas, style, frame, idle, side=False)
        _draw_front_feet(canvas, style, frame, idle)
    else:
        _draw_side_body(canvas, style)
        _draw_side_face(canvas, style, blink)
        _draw_motif(canvas, style, frame, idle, side=True)
        _draw_pin(canvas, style, 28, 14)
        canvas.outline_opaque(OUTLINE)
        _draw_side_face(canvas, style, blink)
        _draw_motif(canvas, style, frame, idle, side=True)
        _draw_side_feet(canvas, style, frame, idle)

    _apply_rim(canvas, style.rim)
    return canvas


def draw_hero_frame(style: CuteHeroStyle, direction: int, frame: int, idle: bool) -> Canvas:
    if direction == 3:
        return draw_hero_frame(style, 2, frame, idle).mirrored()
    canvas = _paint_hero_pose(style, direction, frame, idle)
    if idle:
        return canvas
    base = _paint_hero_pose(style, direction, 0, True)
    _freeze_upper(base, canvas, 54)
    if direction == 2:
        _draw_side_feet(canvas, style, frame, False)
    else:
        _draw_front_feet(canvas, style, frame, False)
    return canvas


def build_hero_sheet(style: CuteHeroStyle, idle: bool) -> Canvas:
    sheet = Canvas(CELL_WIDTH * DIRECTIONS, CELL_HEIGHT * FRAMES)
    for frame in range(FRAMES):
        for direction in range(DIRECTIONS):
            sheet.blit(
                draw_hero_frame(style, direction, frame, idle),
                direction * CELL_WIDTH,
                frame * CELL_HEIGHT,
            )
    return sheet


def build_hero_portrait(style: CuteHeroStyle) -> Canvas:
    canvas = Canvas(PORTRAIT_SIZE, PORTRAIT_SIZE)
    canvas.ellipse(48, 70, 28, 22, style.coat)
    canvas.ellipse(48, 72, 20, 16, style.coat_dark)
    canvas.ellipse(48, 38, 30, 32, style.hood)
    canvas.ellipse(48, 36, 24, 26, style.hood_light)
    canvas.ellipse(48, 44, 22, 20, SKIN)
    canvas.ellipse(48, 28, 24, 12, style.hair)
    canvas.rect(28, 22, 44, 36, style.hair)
    canvas.rect(52, 22, 68, 36, style.hair)
    canvas.pixel(34, 24, style.hair_light)
    canvas.pixel(35, 23, style.hair_light)
    _draw_cute_eyes(canvas, 32, 54, 38, False, style.hair_dark)
    canvas.rect(30, 52, 36, 55, BLUSH_SOFT)
    canvas.rect(60, 52, 66, 55, BLUSH_SOFT)
    canvas.pixel(31, 55, BLUSH)
    canvas.pixel(65, 55, BLUSH)
    canvas.pixel(42, 59, SKIN_SHADOW)
    canvas.rect(44, 60, 52, 61, SKIN_SHADOW)
    canvas.pixel(54, 59, SKIN_SHADOW)
    _draw_pin(canvas, style, 64, 20)
    canvas.outlined_disc(48, 78, 8, MOON_MID, moon_seed_color(1, True))
    canvas.disc(48, 78, 3, style.core)
    canvas.ellipse(36, 76, 6, 5, SKIN)
    canvas.ellipse(60, 76, 6, 5, SKIN)
    canvas.outline_opaque(OUTLINE)
    _draw_cute_eyes(canvas, 32, 54, 38, False, style.hair_dark)
    return canvas


def validate_chibi_frames(
    name: str,
    draw: Callable[[int, int, bool], Canvas],
    *,
    min_height: int,
    max_height: int,
    max_width: int,
    max_lower_body_width: int,
    min_opaque_pixels: int,
    max_opaque_pixels: int,
    face_color: RGBA,
    light_colors: tuple[RGBA, ...],
    side_min_opaque_pixels: int | None = None,
    join_y: int = JOIN_Y,
    light_y: int = LIGHT_Y,
    stable_walk_alpha_through: int | None = 52,
    min_face_pixels: int = 24,
    min_foot_pixels: int = 6,
    max_foot_pixels: int = 18,
) -> None:
    light_palette = frozenset(light_colors)
    rendered: dict[tuple[bool, int, int], Canvas] = {}
    for idle in (False, True):
        state = "idle" if idle else "walk"
        for direction in range(DIRECTIONS):
            for frame in range(FRAMES):
                canvas = draw(direction, frame, idle)
                rendered[(idle, direction, frame)] = canvas
                points = [
                    (x, y)
                    for y in range(canvas.height)
                    for x in range(canvas.width)
                    if canvas.get(x, y)[3] > 0
                ]
                if not points:
                    raise RuntimeError(f"{name} {state} d{direction} f{frame}: empty frame")
                left = min(x for x, _y in points)
                right = max(x for x, _y in points)
                top = min(y for _x, y in points)
                bottom = max(y for _x, y in points)
                width = right - left + 1
                height = bottom - top + 1
                label = f"{name} {state} d{direction} f{frame}"
                if bottom != CELL_HEIGHT - 1:
                    raise RuntimeError(
                        f"{label}: feet must touch y={CELL_HEIGHT - 1} (bottom={bottom})"
                    )
                if not min_height <= height <= max_height:
                    raise RuntimeError(
                        f"{label}: chibi height is outside {min_height}..{max_height}px "
                        f"(height={height})"
                    )
                if width > max_width:
                    raise RuntimeError(
                        f"{label}: silhouette is too wide (width={width}, max={max_width})"
                    )
                opaque_pixels = len(points)
                frame_min_opaque = (
                    side_min_opaque_pixels
                    if direction in (2, 3) and side_min_opaque_pixels is not None
                    else min_opaque_pixels
                )
                if not frame_min_opaque <= opaque_pixels <= max_opaque_pixels:
                    raise RuntimeError(
                        f"{label}: opaque area is out of range ({opaque_pixels}px)"
                    )
                head_height = join_y - top + 1
                body_height = bottom - join_y
                if head_height < body_height - 4:
                    raise RuntimeError(
                        f"{label}: head is too small vs body "
                        f"(head={head_height}, body={body_height})"
                    )

                def row_span(y: int) -> int:
                    row = [x for x, point_y in points if point_y == y]
                    return max(row) - min(row) + 1 if row else 0

                lower_body_width = max(row_span(y) for y in range(54, 57))
                if lower_body_width > max_lower_body_width:
                    raise RuntimeError(
                        f"{label}: lower body is too wide ({lower_body_width}px)"
                    )
                foot_xs = sorted(x for x, y in points if y == CELL_HEIGHT - 1)
                if not min_foot_pixels <= len(foot_xs) <= max_foot_pixels:
                    raise RuntimeError(
                        f"{label}: floor contact width is wrong ({len(foot_xs)}px)"
                    )
                face_pixels = sum(
                    canvas.get(x, y) == face_color
                    for y in range(top, join_y + 1)
                    for x in range(canvas.width)
                )
                if direction == 1:
                    if face_pixels:
                        raise RuntimeError(f"{label}: face must not be visible facing up")
                elif face_pixels < min_face_pixels:
                    raise RuntimeError(
                        f"{label}: front/side face is gone ({face_pixels}px)"
                    )
                light_pixels = sum(
                    canvas.get(x, light_y) in light_palette
                    for x in range(canvas.width)
                )
                if light_pixels < 1:
                    raise RuntimeError(
                        f"{label}: moonlight prop at attack origin y={light_y} is gone"
                    )

    for idle in (False, True):
        state = "idle" if idle else "walk"
        for frame in range(FRAMES):
            down = rendered[(idle, 0, frame)]
            up = rendered[(idle, 1, frame)]
            left = rendered[(idle, 2, frame)]
            right = rendered[(idle, 3, frame)]
            if bytes(down.pixels) == bytes(up.pixels):
                raise RuntimeError(f"{name} {state} f{frame}: front/back art is the same")
            if bytes(right.pixels) != bytes(left.mirrored().pixels):
                raise RuntimeError(
                    f"{name} {state} f{frame}: left/right art is not an exact mirror"
                )
        required_unique_frames = 2 if idle else FRAMES
        for direction in range(DIRECTIONS):
            if not idle and stable_walk_alpha_through is not None:
                top_edges = []
                upper_masks = []
                for frame in range(FRAMES):
                    canvas = rendered[(idle, direction, frame)]
                    top_edges.append(min(
                        y
                        for y in range(canvas.height)
                        for x in range(canvas.width)
                        if canvas.get(x, y)[3] > 0
                    ))
                    upper_masks.append(tuple(
                        canvas.get(x, y)[3] > 0
                        for y in range(stable_walk_alpha_through + 1)
                        for x in range(canvas.width)
                    ))
                if len(set(top_edges)) != 1:
                    raise RuntimeError(
                        f"{name} walk d{direction}: torso bobs up and down "
                        f"(top={top_edges})"
                    )
                if len(set(upper_masks)) != 1:
                    raise RuntimeError(
                        f"{name} walk d{direction}: head/torso outline sways per frame"
                    )
            unique_frames = {
                bytes(rendered[(idle, direction, frame)].pixels)
                for frame in range(FRAMES)
            }
            if len(unique_frames) < required_unique_frames:
                raise RuntimeError(
                    f"{name} {state} d{direction}: not enough frame change "
                    f"({len(unique_frames)}/{required_unique_frames})"
                )
