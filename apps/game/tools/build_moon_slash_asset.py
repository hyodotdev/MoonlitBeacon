#!/usr/bin/env python3
"""Deterministically build Moonlit Warden's dedicated moonlight slash sheet.

Output:

    assets/custom/items/fx/moon_slash.png        192x48
    builds/art-review/a1-player-vfx/slash-preview.png

No generate model. Integer pixels baked to the live hit contract (reach 34, fan 110 deg).
Runtime puts the slash center 13px in front of the player, hand-height pivot
at (0, -6).

The slash node scales X and Y differently by reach, fan, and damage rank.
So a wide crescent that only matches the base size stretches into a long bar late-game and covers outside the hit.
The generator independently combines reach/fan/damage including unbalanced post-relic-drop states, and also checks that every visible pixel of a regular
slash and the full-moon back stay inside the live radius and fan.
"""

from __future__ import annotations

import argparse
import binascii
import math
import struct
import zlib
from pathlib import Path


GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
ASSET_PATH = GAME_ROOT / "assets/custom/items/fx/moon_slash.png"
PREVIEW_PATH = REPO_ROOT / "builds/art-review/a1-player-vfx/slash-preview.png"

CELL = 48
FRAMES = 4
CENTER = 24.0
ARC_DEGREES = 110.0
MAX_LOCAL_REACH = 9.0
SLASH_OFFSET = 13.0
SLASH_PIVOT_REACH = 6.0
ATTACK_RANGE = 34.0
MAX_ATTACK_RANGE = 96.0
MAX_ATTACK_ARC = 360.0
FULL_MOON_REACH = 1.15
RANGE_GROWTH = 1.18
ARC_GROWTH = 1.25
MAX_BULK = 1.45

RGBA = tuple[int, int, int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)
NIGHT: RGBA = (11, 14, 28, 255)
INK_GLOW: RGBA = (59, 54, 67, 96)
MOON_MID: RGBA = (121, 184, 206, 160)
MOON_BRIGHT: RGBA = (205, 225, 255, 224)
MOON_CORE: RGBA = (222, 240, 255, 255)
EMBER: RGBA = (239, 145, 79, 224)
EMBER_CORE: RGBA = (255, 225, 141, 255)


class Canvas:
    def __init__(self, width: int, height: int, fill: RGBA = TRANSPARENT) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(fill * (width * height))

    def pixel(self, x: int, y: int, color: RGBA) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return
        offset = (y * self.width + x) * 4
        self.pixels[offset : offset + 4] = bytes(color)

    def get(self, x: int, y: int) -> RGBA:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return TRANSPARENT
        offset = (y * self.width + x) * 4
        return tuple(self.pixels[offset : offset + 4])  # type: ignore[return-value]

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: RGBA) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.pixel(x, y, color)

    def blit(self, source: "Canvas", x: int, y: int) -> None:
        for source_y in range(source.height):
            for source_x in range(source.width):
                color = source.get(source_x, source_y)
                if color[3] > 0:
                    self.pixel(x + source_x, y + source_y, color)

    def blit_scaled(self, source: "Canvas", x: int, y: int, scale: int) -> None:
        for source_y in range(source.height):
            for source_x in range(source.width):
                color = source.get(source_x, source_y)
                if color[3] == 0:
                    continue
                self.rect(
                    x + source_x * scale,
                    y + source_y * scale,
                    x + (source_x + 1) * scale - 1,
                    y + (source_y + 1) * scale - 1,
                    color,
                )

    def to_png(self) -> bytes:
        stride = self.width * 4
        scanlines = b"".join(
            b"\x00" + bytes(self.pixels[y * stride : (y + 1) * stride])
            for y in range(self.height)
        )
        payload = bytearray(b"\x89PNG\r\n\x1a\n")
        payload += _png_chunk(
            b"IHDR",
            struct.pack(">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0),
        )
        payload += _png_chunk(b"IDAT", zlib.compress(scanlines, level=9))
        payload += _png_chunk(b"IEND", b"")
        return bytes(payload)

    def save(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(self.to_png())


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


def _polar(x: int, y: int) -> tuple[float, float]:
    dx = x + 0.5 - CENTER
    dy = y + 0.5 - CENTER
    return math.hypot(dx, dy), math.degrees(math.atan2(dy, dx))


def _ribbon_shape(frame: int, dx: float, dy: float) -> tuple[bool, float, float]:
    """Return a small S-blade mask that still holds under late-game anisotropic scale.

    Drawing a wide arc in one sheet lets `attack_arc` apply vertical scale again so
    end pixels leave the hit. Instead, inside 12×8px, bend the centerline the other way each frame
    so a still frame reads as a short thick blade, and playback
    read as afterglow drawing a crescent.
    """

    # This per-row outline is a safety mask from checking all four corners, not pixel centers.
    # Dropping a relic can leave reach low while arc and damage stay high, so
    # It must survive even without assuming all four axes rise together.
    row = abs(dy)
    if row <= 0.5:
        safe_left, safe_right = -1.5, 8.5
    elif row <= 1.5:
        safe_left, safe_right = -1.5, 7.5
    elif row <= 2.5:
        safe_left, safe_right = -0.5, 6.5
    elif row <= 3.5:
        safe_left, safe_right = 0.5, 3.5
    else:
        return False, 0.0, 0.0
    if not (safe_left <= dx <= safe_right):
        return False, 0.0, 0.0

    progress = (dx + 1.5) / 10.0
    if frame == 0:
        if not (-0.5 <= dx <= 6.5):
            return False, progress, 0.0
        curve = -1.15 + 2.0 * progress
        thickness = 0.8 + 0.75 * math.sin(math.pi * progress)
    elif frame == 1:
        curve = 1.45 - 2.9 * progress
        thickness = 1.15 + 1.25 * math.sin(math.pi * progress)
    elif frame == 2:
        if not (0.5 <= dx <= 7.5):
            return False, progress, 0.0
        curve = -0.9 + 2.05 * progress
        thickness = 0.75 + 0.85 * math.sin(math.pi * progress)
    else:
        # The last is a clipped afterglow on the same path. More than a plain alpha fade,
        # leftover pixel shards make even a 0.18s attack read one extra frame.
        curve = 0.8 - 1.45 * progress
        thickness = 1.1
        if (int(dx + CENTER) * 3 + int(dy + CENTER) * 5) % 7 < 4:
            return False, progress, abs(dy - curve)

    distance = abs(dy - curve)
    return distance <= thickness, progress, distance


def _ribbon_color(
    frame: int,
    progress: float,
    distance: float,
    x: int,
    y: int,
) -> RGBA:
    if frame == 0:
        if distance < 0.65:
            return MOON_CORE
        return MOON_BRIGHT if progress > 0.25 else MOON_MID
    if frame == 1:
        if progress > 0.78 and (x + y) % 3 == 0:
            return EMBER_CORE
        if distance < 0.7:
            return MOON_CORE
        if distance < 1.55:
            return MOON_BRIGHT
        return MOON_MID
    if frame == 2:
        if progress > 0.82 and (x + 2 * y) % 4 == 0:
            return EMBER
        if distance < 0.72:
            return MOON_BRIGHT
        return MOON_MID if (x + y) % 3 else INK_GLOW
    return MOON_MID if (x + y) % 2 else INK_GLOW


def build_frame(frame: int) -> Canvas:
    canvas = Canvas(CELL, CELL)
    for y in range(CELL):
        for x in range(CELL):
            dx = x + 0.5 - CENTER
            dy = y + 0.5 - CENTER
            inside, progress, distance = _ribbon_shape(frame, dx, dy)
            if not inside:
                continue
            canvas.pixel(
                x, y, _ribbon_color(frame, progress, distance, x, y)
            )
    return canvas


def build_sheet() -> Canvas:
    sheet = Canvas(CELL * FRAMES, CELL)
    for frame in range(FRAMES):
        sheet.blit(build_frame(frame), frame * CELL, 0)
    return sheet


def max_visible_radius(sheet: Canvas) -> float:
    maximum = 0.0
    for frame in range(FRAMES):
        frame_x = frame * CELL
        for y in range(CELL):
            for x in range(CELL):
                if sheet.get(frame_x + x, y)[3] == 0:
                    continue
                radius, _angle = _polar(x, y)
                maximum = max(maximum, radius)
    return maximum


SAFETY_MARGIN = 0.5


def _growth_values(default: float, maximum: float, growth: float) -> list[float]:
    values = [default]
    while values[-1] < maximum:
        next_value = min(values[-1] * growth, maximum)
        if math.isclose(next_value, values[-1]):
            break
        values.append(next_value)
    return values


def _pixel_corners(x: int, y: int) -> tuple[tuple[float, float], ...]:
    left = float(x) - CENTER
    right = float(x + 1) - CENTER
    top = float(y) - CENTER
    bottom = float(y + 1) - CENTER
    return ((left, top), (right, top), (left, bottom), (right, bottom))


def runtime_safety_metrics(sheet: Canvas) -> dict[str, float | str]:
    """Check every independent-upgrade and relic-drop combo by pixel corners.

    Reach and fan use every live relic-multiplier value; damage thickness is split 65 ways between sat values
    and combined independently. States where only reach dropped while fan/damage
    are included. The fixed hand pivot orbits a 6px circle by facing, so
    Add 6px to distance and the circle's max angular error to the angle.
    """

    ranges = _growth_values(ATTACK_RANGE, MAX_ATTACK_RANGE, RANGE_GROWTH)
    arcs = _growth_values(ARC_DEGREES, MAX_ATTACK_ARC, ARC_GROWTH)
    bulks = [
        1.0 + (MAX_BULK - 1.0) * float(index) / 64.0
        for index in range(65)
    ]
    metrics: dict[str, float | str] = {
        "regular_slack": math.inf,
        "regular_case": "",
        "full_moon_slack": math.inf,
        "full_moon_case": "",
        "cone_margin_degrees": math.inf,
        "cone_case": "",
        "default_corner_reach": 0.0,
        "states": float(len(ranges) * len(arcs) * len(bulks)),
        "corners": 0.0,
    }

    visible_corners: list[tuple[int, int, float, float]] = []
    for frame in range(FRAMES):
        frame_x = frame * CELL
        for y in range(CELL):
            for x in range(CELL):
                if sheet.get(frame_x + x, y)[3] == 0:
                    continue
                for dx, dy in _pixel_corners(x, y):
                    visible_corners.append((frame, x, dx, dy))
    metrics["corners"] = float(len(visible_corners))

    for attack_range in ranges:
        reach = attack_range / ATTACK_RANGE
        shown = min(reach, 3.2)
        for attack_arc in arcs:
            width = attack_arc / ARC_DEGREES
            half_arc = math.radians(attack_arc * 0.5)
            for bulk in bulks:
                for frame, x, dx, dy in visible_corners:
                    base_x = SLASH_OFFSET * reach + dx * shown * bulk
                    base_y = dy * shown * width * bulk
                    base_radius = math.hypot(base_x, base_y)
                    regular_slack = (
                        attack_range
                        - SAFETY_MARGIN
                        - base_radius
                        - SLASH_PIVOT_REACH
                    )
                    if regular_slack < float(metrics["regular_slack"]):
                        metrics["regular_slack"] = regular_slack
                        metrics["regular_case"] = (
                            f"frame {frame + 1}, range {attack_range:.3f}, "
                            f"arc {attack_arc:.3f}, bulk {bulk:.3f}, x {x}"
                        )

                    if (
                        math.isclose(attack_range, ATTACK_RANGE)
                        and math.isclose(attack_arc, ARC_DEGREES)
                        and math.isclose(bulk, 1.0)
                    ):
                        metrics["default_corner_reach"] = max(
                            float(metrics["default_corner_reach"]),
                            base_radius + SLASH_PIVOT_REACH,
                        )

                    if half_arc < math.pi and base_radius > SLASH_PIVOT_REACH:
                        pivot_angle = math.asin(
                            min(
                                (SLASH_PIVOT_REACH + SAFETY_MARGIN)
                                / base_radius,
                                1.0,
                            )
                        )
                        visual_angle = abs(math.atan2(base_y, base_x)) + pivot_angle
                        cone_margin = math.degrees(half_arc - visual_angle)
                        if cone_margin < float(metrics["cone_margin_degrees"]):
                            metrics["cone_margin_degrees"] = cone_margin
                            metrics["cone_case"] = (
                                f"frame {frame + 1}, range {attack_range:.3f}, "
                                f"arc {attack_arc:.3f}, bulk {bulk:.3f}, x {x}"
                            )

                    back_x = (
                        SLASH_OFFSET * reach
                        + dx * shown * bulk * 1.08
                    )
                    back_y = (
                        dy * shown * max(width, 1.2) * bulk
                    )
                    full_moon_slack = (
                        attack_range * FULL_MOON_REACH
                        - SAFETY_MARGIN
                        - math.hypot(back_x, back_y)
                        - SLASH_PIVOT_REACH
                    )
                    if full_moon_slack < float(metrics["full_moon_slack"]):
                        metrics["full_moon_slack"] = full_moon_slack
                        metrics["full_moon_case"] = (
                            f"frame {frame + 1}, range {attack_range:.3f}, "
                            f"arc {attack_arc:.3f}, bulk {bulk:.3f}, x {x}"
                        )

    return metrics


def build_preview(sheet: Canvas) -> Canvas:
    scale = 8
    gap = 12
    margin = 20
    width = margin * 2 + CELL * scale * FRAMES + gap * (FRAMES - 1)
    height = margin * 2 + CELL * scale
    preview = Canvas(width, height, NIGHT)
    for frame in range(FRAMES):
        source = Canvas(CELL, CELL)
        for y in range(CELL):
            for x in range(CELL):
                source.pixel(x, y, sheet.get(frame * CELL + x, y))
        preview.blit_scaled(source, margin + frame * (CELL * scale + gap), margin, scale)
    return preview


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="inspect without writing that production PNG matches created result and hit contract",
    )
    args = parser.parse_args()

    sheet = build_sheet()
    local_reach = max_visible_radius(sheet)
    if local_reach > MAX_LOCAL_REACH:
        raise RuntimeError(
            f"slash pixel radius {local_reach:.3f}px "
            f"exceeds the authoring cap {MAX_LOCAL_REACH:.3f}px"
        )
    metrics = runtime_safety_metrics(sheet)
    regular_slack = float(metrics["regular_slack"])
    full_moon_slack = float(metrics["full_moon_slack"])
    cone_margin = float(metrics["cone_margin_degrees"])
    if regular_slack < 0.0:
        raise RuntimeError(
            f"upgraded slash pixel corners exceed hit radius by {-regular_slack:.3f}px "
            f"({metrics['regular_case']})"
        )
    if cone_margin < 0.0:
        raise RuntimeError(
            f"upgraded slash pixel corners exceed the fan by {-cone_margin:.3f} deg "
            f"({metrics['cone_case']})"
        )
    if full_moon_slack < 0.0:
        raise RuntimeError(
            f"full-moon back pixel corners exceed hit radius by {-full_moon_slack:.3f}px "
            f"({metrics['full_moon_case']})"
        )

    expected_png = sheet.to_png()
    if args.check:
        if not ASSET_PATH.is_file():
            raise RuntimeError(f"production slash PNG is missing: {ASSET_PATH}")
        if ASSET_PATH.read_bytes() != expected_png:
            raise RuntimeError(
                "production slash PNG differs from the deterministic created result. "
                "run build_moon_slash_asset.py again"
            )
    else:
        preview = build_preview(sheet)
        sheet.save(ASSET_PATH)
        preview.save(PREVIEW_PATH)

    print(f"Moonlit slash: {sheet.width}x{sheet.height}, {FRAMES} frames")
    print(
        "runtime safety: "
        f"regular {regular_slack:.3f}px, "
        f"full moon {full_moon_slack:.3f}px, "
        f"cone {cone_margin:.3f}deg "
        f"({int(float(metrics['states'])):,} states, "
        f"{int(float(metrics['corners'])):,} corners)"
    )
    print(
        "default reach: "
        f"{float(metrics['default_corner_reach']):.3f}/{ATTACK_RANGE:.1f} "
        f"(local center {local_reach:.3f})"
    )
    print("check: production PNG is deterministic" if args.check else f"preview: {PREVIEW_PATH}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
