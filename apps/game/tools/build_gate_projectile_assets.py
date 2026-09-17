#!/usr/bin/env python3
"""Deterministically build moonlight-gate and ally/enemy projectile pixel assets.

Output:

    assets/custom/world/gate/moon_gate.png                    34x52
    assets/custom/items/projectiles/moon_arrow.png           128x32
    assets/custom/items/projectiles/hostile_moon_bolt.png     40x40

The three assets keep the source sizes runtime already consumes. No external image or
without remixing third-party pixels, drawing only ink-navy, moon-silver, teal, and scarlet/red-violet.
Draw them. ``--check`` inspects production PNG bytes and each frame's visible-pixel contract together.
inspect.
"""

from __future__ import annotations

import argparse
import binascii
import math
import struct
import zlib
from pathlib import Path


GAME_ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = GAME_ROOT / "assets/custom/world/gate/moon_gate.png"
ARROW_PATH = GAME_ROOT / "assets/custom/items/projectiles/moon_arrow.png"
BOLT_PATH = GAME_ROOT / "assets/custom/items/projectiles/hostile_moon_bolt.png"

RGBA = tuple[int, int, int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)

# Shared Moonlit Beacon palette. Keep enough ink-dark area that outlines survive bright runtime modulate.
# use more ink-dark area than midtones.
NIGHT: RGBA = (8, 16, 37, 255)
INK: RGBA = (15, 29, 54, 255)
SLATE: RGBA = (31, 55, 78, 255)
BLUE_GREY: RGBA = (62, 91, 112, 255)
MOON_SHADE: RGBA = (111, 151, 163, 255)
MOON: RGBA = (176, 213, 218, 255)
MOON_BRIGHT: RGBA = (231, 246, 240, 255)
TEAL_DARK: RGBA = (22, 91, 99, 255)
TEAL: RGBA = (44, 185, 169, 255)
TEAL_BRIGHT: RGBA = (120, 239, 205, 255)
EMBER: RGBA = (225, 80, 48, 255)
EMBER_BRIGHT: RGBA = (255, 156, 82, 255)
MAGENTA_DARK: RGBA = (72, 24, 65, 255)
MAGENTA: RGBA = (161, 46, 114, 255)
MAGENTA_BRIGHT: RGBA = (242, 85, 148, 255)
TEAL_HALO: RGBA = (44, 185, 169, 70)
MOON_HALO: RGBA = (176, 213, 218, 58)
DANGER_HALO: RGBA = (242, 85, 148, 62)
DANGER_GLOW: RGBA = (225, 80, 48, 110)


class Canvas:
    def __init__(self, width: int, height: int) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(TRANSPARENT * (width * height))

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

    def line(
        self,
        x0: int,
        y0: int,
        x1: int,
        y1: int,
        color: RGBA,
        thickness: int = 1,
    ) -> None:
        """Integer Bresenham line. Thick lines also stay on the pixel grid."""

        dx = abs(x1 - x0)
        sx = 1 if x0 < x1 else -1
        dy = -abs(y1 - y0)
        sy = 1 if y0 < y1 else -1
        error = dx + dy
        radius = max(0, thickness - 1) // 2
        while True:
            self.rect(x0 - radius, y0 - radius, x0 + radius, y0 + radius, color)
            if x0 == x1 and y0 == y1:
                break
            doubled = 2 * error
            if doubled >= dy:
                error += dy
                x0 += sx
            if doubled <= dx:
                error += dx
                y0 += sy

    def ellipse(
        self,
        center_x: float,
        center_y: float,
        radius_x: float,
        radius_y: float,
        color: RGBA,
    ) -> None:
        for y in range(self.height):
            for x in range(self.width):
                dx = (x + 0.5 - center_x) / radius_x
                dy = (y + 0.5 - center_y) / radius_y
                if dx * dx + dy * dy <= 1.0:
                    self.pixel(x, y, color)

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


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


def _draw_gate() -> Canvas:
    gate = Canvas(34, 52)

    # A very thin teal threshold left in open space. Sparse visible pixels so, even overlapping the Halo node, it does not look like an opaque plate.
    # keep visible pixels sparse so it does not look like an opaque plate.
    gate.line(10, 20, 17, 12, TEAL_HALO)
    gate.line(17, 12, 24, 20, TEAL_HALO)
    gate.line(17, 13, 17, 43, TEAL_HALO)
    for y in (22, 29, 36, 42):
        gate.pixel(16, y, TEAL_BRIGHT if y % 2 == 0 else TEAL)
        gate.pixel(18, y + 1, TEAL)

    # Two pillars. Outer ink line, blue ash face, silver inner corners so they read as a structure
    # so they read as a structure even on a small screen.
    gate.rect(2, 20, 10, 48, NIGHT)
    gate.rect(24, 20, 31, 48, NIGHT)
    gate.rect(4, 21, 9, 47, SLATE)
    gate.rect(25, 21, 29, 47, SLATE)
    gate.rect(8, 22, 9, 45, BLUE_GREY)
    gate.rect(25, 22, 26, 45, BLUE_GREY)
    gate.line(5, 24, 5, 43, MOON_SHADE)
    gate.line(28, 24, 28, 43, MOON_SHADE)

    # Moon runes on the pillars. Teal on the left, beacon scarlet on the right, so destination and danger
    # are shown at once.
    gate.rect(4, 29, 6, 31, TEAL_DARK)
    gate.pixel(5, 28, TEAL_BRIGHT)
    gate.pixel(5, 30, TEAL)
    gate.rect(27, 35, 29, 37, EMBER)
    gate.pixel(28, 34, EMBER_BRIGHT)
    gate.pixel(28, 36, MOON_BRIGHT)

    # Test outer/inner arch ellipses separately and draw the band directly. The middle is truly transparent so
    # background terrain and the Halo behind it stay visible.
    center_x, center_y = 17.0, 20.0
    for y in range(2, 26):
        for x in range(1, 33):
            outer = ((x + 0.5 - center_x) / 15.0) ** 2 + (
                (y + 0.5 - center_y) / 18.0
            ) ** 2
            inner = ((x + 0.5 - center_x) / 8.0) ** 2 + (
                (y + 0.5 - center_y) / 11.0
            ) ** 2
            if outer > 1.0 or inner < 1.0:
                continue
            color = NIGHT
            if outer < 0.86:
                color = SLATE
            if 0.86 <= inner <= 1.28:
                color = MOON_SHADE
            gate.pixel(x, y, color)

    # Asymmetric crescent crown on the arch. A unique silhouette, not a plain doorframe.
    for y in range(1, 13):
        for x in range(8, 25):
            outer = math.hypot(x + 0.5 - 16.0, y + 0.5 - 7.0) <= 6.0
            cut = math.hypot(x + 0.5 - 18.5, y + 0.5 - 5.5) <= 4.7
            if outer and not cut:
                gate.pixel(x, y, NIGHT)
    for x, y in ((12, 4), (11, 5), (11, 6), (12, 7), (13, 8), (14, 9)):
        gate.pixel(x, y, MOON_BRIGHT if (x + y) % 2 else MOON)
    gate.pixel(20, 4, TEAL_BRIGHT)
    gate.pixel(22, 7, TEAL)
    gate.pixel(20, 10, EMBER_BRIGHT)

    # The plinth gives the gate the weight of being planted in the floor. Only the bottom uses the edge;
    # Leave 1px left and right empty to stop atlas bleed.
    gate.rect(1, 47, 32, 51, NIGHT)
    gate.rect(4, 47, 29, 48, BLUE_GREY)
    gate.rect(7, 49, 26, 50, SLATE)
    gate.rect(12, 49, 21, 49, MOON_SHADE)
    gate.pixel(16, 48, TEAL_BRIGHT)
    gate.pixel(17, 48, EMBER_BRIGHT)
    return gate


def _crescent_mask(x: int, y: int, angle: float) -> bool:
    center = 15.5
    dx = x + 0.5 - center
    dy = y + 0.5 - center
    if dx * dx + dy * dy > 10.8 * 10.8:
        return False
    # Offset-carve the inner circle in the rotation direction so all four frames are distinct crescents.
    cut_x = math.cos(angle) * 4.0
    cut_y = math.sin(angle) * 4.0
    shifted_x = dx - cut_x
    shifted_y = dy - cut_y
    return shifted_x * shifted_x + shifted_y * shifted_y > 8.2 * 8.2


def _draw_arrow_frame(sheet: Canvas, frame: int) -> None:
    origin_x = frame * 32
    angle = (-0.55, 0.30, 1.12, 2.05)[frame]
    center = 15.5

    # Thin moon-silver halo. Do not draw inside 2px of the frame-cell edge.
    for y in range(2, 30):
        for x in range(2, 30):
            radius = math.hypot(x + 0.5 - center, y + 0.5 - center)
            if 11.0 < radius <= 12.6 and (x + y + frame) % 2 == 0:
                sheet.pixel(origin_x + x, y, MOON_HALO)

    mask = {
        (x, y)
        for y in range(2, 30)
        for x in range(2, 30)
        if _crescent_mask(x, y, angle)
    }
    for x, y in mask:
        boundary = any(
            (x + offset_x, y + offset_y) not in mask
            for offset_x, offset_y in ((-1, 0), (1, 0), (0, -1), (0, 1))
        )
        if boundary:
            color = NIGHT
        else:
            lighting = (x - center) * math.cos(angle) + (y - center) * math.sin(angle)
            color = MOON if lighting < 1.5 else MOON_BRIGHT
            if (x * 3 + y * 5 + frame) % 11 == 0:
                color = MOON_SHADE
        sheet.pixel(origin_x + x, y, color)

    # Teal moonstone on the spin axis and a scarlet ember at the tip are instantly distinct from the enemy's red-violet orb.
    sheet.rect(origin_x + 13, 13, origin_x + 18, 18, NIGHT)
    sheet.rect(origin_x + 14, 14, origin_x + 17, 17, TEAL)
    sheet.pixel(origin_x + 15, 14, TEAL_BRIGHT)
    sheet.pixel(origin_x + 16, 17, MOON_BRIGHT)
    tip_x = int(round(center - math.cos(angle) * 10.0))
    tip_y = int(round(center - math.sin(angle) * 10.0))
    sheet.pixel(origin_x + tip_x, tip_y, EMBER_BRIGHT)
    sheet.pixel(origin_x + tip_x + (1 if math.sin(angle) >= 0 else -1), tip_y, EMBER)


def _draw_arrow() -> Canvas:
    sheet = Canvas(128, 32)
    for frame in range(4):
        _draw_arrow_frame(sheet, frame)
    return sheet


def _draw_hostile_bolt() -> Canvas:
    bolt = Canvas(40, 40)
    center = 19.5

    # Enemy shots are not round moon discs but a spiked red-violet eclipse. Even at 0.42×
    # Draw thicker than one pixel so four long spikes and a bright center survive.
    for y in range(2, 38):
        for x in range(2, 38):
            radius = math.hypot(x + 0.5 - center, y + 0.5 - center)
            if 14.0 < radius <= 17.0 and (x * 5 + y * 3) % 4 == 0:
                bolt.pixel(x, y, DANGER_HALO)
            elif 11.5 < radius <= 14.0 and (x + y) % 3 == 0:
                bolt.pixel(x, y, DANGER_GLOW)

    for angle in range(0, 360, 45):
        radians = math.radians(float(angle))
        inner_x = int(round(center + math.cos(radians) * 7.0))
        inner_y = int(round(center + math.sin(radians) * 7.0))
        reach = 16.0 if angle % 90 == 0 else 12.5
        outer_x = int(round(center + math.cos(radians) * reach))
        outer_y = int(round(center + math.sin(radians) * reach))
        bolt.line(inner_x, inner_y, outer_x, outer_y, NIGHT, 3)
        bolt.line(inner_x, inner_y, outer_x, outer_y, EMBER if angle % 90 == 0 else MAGENTA)
        bolt.pixel(outer_x, outer_y, MAGENTA_BRIGHT if angle % 90 else EMBER_BRIGHT)

    bolt.ellipse(center, center, 9.5, 9.5, NIGHT)
    bolt.ellipse(center, center, 7.0, 7.0, MAGENTA_DARK)
    # A scarlet ring wraps a dark eclipse so it does not read as a bright heal item.
    for y in range(11, 29):
        for x in range(11, 29):
            radius = math.hypot(x + 0.5 - center, y + 0.5 - center)
            if 5.4 <= radius <= 7.2:
                bolt.pixel(x, y, MAGENTA_BRIGHT if (x + y) % 3 else EMBER)
    bolt.ellipse(center, center, 4.7, 4.7, INK)
    bolt.rect(18, 17, 21, 22, NIGHT)
    bolt.pixel(18, 18, EMBER_BRIGHT)
    bolt.pixel(21, 21, MAGENTA_BRIGHT)
    return bolt


def _visible_pixels(canvas: Canvas, x0: int, y0: int, width: int, height: int) -> int:
    return sum(
        1
        for y in range(y0, y0 + height)
        for x in range(x0, x0 + width)
        if canvas.get(x, y)[3] > 0
    )


def _validate(gate: Canvas, arrow: Canvas, bolt: Canvas) -> None:
    expected = ((gate, 34, 52), (arrow, 128, 32), (bolt, 40, 40))
    for canvas, width, height in expected:
        if (canvas.width, canvas.height) != (width, height):
            raise RuntimeError(
                f"wrong production size: {canvas.width}x{canvas.height}, expected {width}x{height}"
            )

    gate_visible = _visible_pixels(gate, 0, 0, 34, 52)
    bolt_visible = _visible_pixels(bolt, 0, 0, 40, 40)
    arrow_frames = [
        _visible_pixels(arrow, frame * 32, 0, 32, 32) for frame in range(4)
    ]
    if not 350 <= gate_visible <= 1050:
        raise RuntimeError(f"moonlight-gate visible pixel count is abnormal: {gate_visible}")
    if not 150 <= bolt_visible <= 800:
        raise RuntimeError(f"enemy-projectile visible pixel count is abnormal: {bolt_visible}")
    if any(amount < 110 for amount in arrow_frames):
        raise RuntimeError(f"player projectile has an empty frame: {arrow_frames}")
    frame_bytes = {
        b"".join(
            bytes(arrow.get(frame * 32 + x, y))
            for y in range(32)
            for x in range(32)
        )
        for frame in range(4)
    }
    if len(frame_bytes) != 4:
        raise RuntimeError("player projectile four frames are not unique")

    # Leave cell edges empty so bilinear bleed cannot happen. The gate, because of its plinth, only
    # may use the bottom edge; left/right/top must always stay transparent.
    if any(gate.get(x, 0)[3] for x in range(34)):
        raise RuntimeError("moonlight gate has visible pixels on the top edge")
    if any(gate.get(0, y)[3] or gate.get(33, y)[3] for y in range(52)):
        raise RuntimeError("moonlight gate has visible pixels on the left/right edges")
    for frame in range(4):
        for x in range(frame * 32, (frame + 1) * 32):
            if arrow.get(x, 0)[3] or arrow.get(x, 31)[3]:
                raise RuntimeError(f"player projectile frame {frame + 1} vertical edge is filled")
        for y in range(32):
            if arrow.get(frame * 32, y)[3] or arrow.get(frame * 32 + 31, y)[3]:
                raise RuntimeError(f"player projectile frame {frame + 1} horizontal edge is filled")


def _outputs() -> dict[Path, Canvas]:
    gate = _draw_gate()
    arrow = _draw_arrow()
    bolt = _draw_hostile_bolt()
    _validate(gate, arrow, bolt)
    return {GATE_PATH: gate, ARROW_PATH: arrow, BOLT_PATH: bolt}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="inspect without writing that production PNG matches the deterministic created result",
    )
    args = parser.parse_args()
    outputs = _outputs()
    for path, canvas in outputs.items():
        encoded = canvas.to_png()
        if args.check:
            if not path.is_file():
                raise RuntimeError(f"production PNG is missing: {path}")
            if path.read_bytes() != encoded:
                raise RuntimeError(
                    f"production PNG differs from the deterministic created result: {path.name}"
                )
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(encoded)
        print(f"{path.relative_to(GAME_ROOT)}: {canvas.width}x{canvas.height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
