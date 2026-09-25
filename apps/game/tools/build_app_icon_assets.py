#!/usr/bin/env python3
"""Check Moonlit Beacon app-icon family and platform-wiring contracts.

The new app icon is painted art of the final Moonlit Warden cupping a glowing beacon flame.
From the tracked source it builds the iOS 1024 master and Android legacy/adaptive sets, and
This script inspects live production PNG size, alpha, safe circle, and platform paths.

The 108×108 fixed shape defs stay for the editor icon and older
marketing-graphic determinism. Keep them for that. The docs site uses
the painted launcher art instead, so these files are managed:

    assets/custom/ui/app_icon_master.png      1024×1024, opaque
    assets/custom/ui/app_icon_main.png        192×192, opaque
    assets/custom/ui/app_icon_foreground.png  432×432, graded alpha
    assets/custom/ui/app_icon_background.png  432×432, opaque
    icon.svg                                  legacy vector mark
    ../docs/static/img/favicon.png            32×32, from app_icon_main.png
    ../docs/static/img/logo.png               192×192, app_icon_main.png bytes
    builds/art-review/a4-ui/app-icon-preview.png

Every visible pixel of the Android adaptive foreground must sit inside the official
132px-radius (66dp diameter) safe circle. Center radius 144px is
the real mask viewport. This condition is pixel-checked in both create and ``--check``.
inspect.
"""

from __future__ import annotations

import argparse
import binascii
import json
import math
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Literal


GAME_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
DOCS_IMAGE_DIR = REPO_ROOT / "apps/docs/static/img"
CUSTOM_UI_DIR = GAME_ROOT / "assets/custom/ui"
REVIEW_DIR = REPO_ROOT / "builds/art-review/a4-ui"

LOGICAL_SIZE = 108
ANDROID_SIZE = 432
MAIN_SIZE = 192
MASTER_SIZE = 1024
MASTER_COLOR_LIMIT = 150_000
MAIN_COLOR_LIMIT = 20_000
FOREGROUND_COLOR_LIMIT = 15_000
BACKGROUND_COLOR_LIMIT = 35_000
ANDROID_SCALE = ANDROID_SIZE // LOGICAL_SIZE
# On a 108dp layer, convert the 72dp center viewport the OEM mask actually uses, and the official
# 66dp safe zone that never clips, converted at 4px/dp.
ADAPTIVE_VIEWPORT_RADIUS = 144.0
ADAPTIVE_SAFE_RADIUS = 132.0
FOREGROUND_SCALE_NUMERATOR = 9
FOREGROUND_SCALE_DENOMINATOR = 10

RGBA = tuple[int, int, int, int]
Point = tuple[int, int]
ShapeKind = Literal["rect", "polygon"]


# Same navy / lavender-blue / warm skin / moonlight family as the Warden production palette.
# Including the foreground's 3 translucent colors still stays under the 256-color cap.
PALETTE: dict[str, RGBA] = {
    "transparent": (0, 0, 0, 0),
    "night": (11, 14, 28, 255),
    "night_mid": (18, 25, 50, 255),
    "night_light": (29, 40, 78, 255),
    "star_dim": (74, 91, 146, 255),
    "star": (139, 166, 222, 255),
    "outline": (29, 36, 64, 255),
    "hood_dark": (61, 65, 113, 255),
    "hood_shadow": (78, 83, 139, 255),
    "hood": (114, 121, 188, 255),
    "hood_light": (170, 185, 238, 255),
    "hair_shadow": (52, 43, 87, 255),
    "hair": (81, 68, 122, 255),
    "hair_light": (117, 101, 167, 255),
    "skin_shadow": (217, 138, 120, 255),
    "skin": (242, 181, 143, 255),
    "skin_light": (255, 205, 163, 255),
    "blush": (241, 142, 158, 255),
    "moon_mid": (117, 207, 224, 255),
    "moon_bright": (214, 243, 255, 255),
    "moon_core": (255, 248, 220, 255),
    "gold": (245, 200, 75, 255),
    "wax_light": (252, 246, 226, 255),
    "wax": (238, 226, 194, 255),
    "wax_shade": (196, 178, 138, 255),
    "flame": (255, 168, 70, 255),
    "flame_core": (255, 236, 170, 255),
    "glow_dim": (255, 186, 96, 64),
    "glow": (255, 226, 160, 128),
}


@dataclass(frozen=True)
class Shape:
    kind: ShapeKind
    color: str
    points: tuple[Point, ...]


def rect(x0: int, y0: int, x1: int, y1: int, color: str) -> Shape:
    return Shape("rect", color, ((x0, y0), (x1, y1)))


def polygon(points: Iterable[Point], color: str) -> Shape:
    return Shape("polygon", color, tuple(points))


class Canvas:
    """Tiny RGBA pixel canvas used without an external image library."""

    def __init__(
        self,
        width: int,
        height: int,
        fill: RGBA = PALETTE["transparent"],
    ) -> None:
        self.width = width
        self.height = height
        self.pixels = bytearray(fill * (width * height))

    def get(self, x: int, y: int) -> RGBA:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return PALETTE["transparent"]
        offset = (y * self.width + x) * 4
        return tuple(self.pixels[offset : offset + 4])  # type: ignore[return-value]

    def pixel(self, x: int, y: int, color: RGBA) -> None:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return
        offset = (y * self.width + x) * 4
        self.pixels[offset : offset + 4] = bytes(color)

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: RGBA) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.pixel(x, y, color)

    def line(self, start: Point, end: Point, color: RGBA) -> None:
        x0, y0 = start
        x1, y1 = end
        dx = abs(x1 - x0)
        sx = 1 if x0 < x1 else -1
        dy = -abs(y1 - y0)
        sy = 1 if y0 < y1 else -1
        error = dx + dy
        while True:
            self.pixel(x0, y0, color)
            if x0 == x1 and y0 == y1:
                break
            doubled = error * 2
            if doubled >= dy:
                error += dy
                x0 += sx
            if doubled <= dx:
                error += dx
                y0 += sy

    def polygon(self, points: Iterable[Point], color: RGBA) -> None:
        vertices = list(points)
        if len(vertices) < 3:
            return
        min_y = max(min(point[1] for point in vertices), 0)
        max_y = min(max(point[1] for point in vertices), self.height - 1)
        for y in range(min_y, max_y + 1):
            scan_y = y + 0.5
            intersections: list[float] = []
            for index, first in enumerate(vertices):
                second = vertices[(index + 1) % len(vertices)]
                x0, y0 = first
                x1, y1 = second
                if y0 == y1:
                    continue
                lower_y = min(y0, y1)
                upper_y = max(y0, y1)
                if not (lower_y <= scan_y < upper_y):
                    continue
                ratio = (scan_y - y0) / (y1 - y0)
                intersections.append(x0 + ratio * (x1 - x0))
            intersections.sort()
            for left, right in zip(intersections[0::2], intersections[1::2]):
                start_x = math.ceil(left - 0.5)
                end_x = math.floor(right - 0.5)
                for x in range(start_x, end_x + 1):
                    self.pixel(x, y, color)
        for index, first in enumerate(vertices):
            self.line(first, vertices[(index + 1) % len(vertices)], color)

    def composite(self, source: "Canvas", x: int = 0, y: int = 0) -> None:
        """Composite an RGBA canvas with source-over."""
        for source_y in range(source.height):
            for source_x in range(source.width):
                source_color = source.get(source_x, source_y)
                source_alpha = source_color[3]
                if source_alpha == 0:
                    continue
                target_x = x + source_x
                target_y = y + source_y
                if not (0 <= target_x < self.width and 0 <= target_y < self.height):
                    continue
                target_color = self.get(target_x, target_y)
                target_alpha = target_color[3]
                out_alpha_numerator = (
                    source_alpha * 255 + target_alpha * (255 - source_alpha)
                )
                if out_alpha_numerator == 0:
                    self.pixel(
                        target_x,
                        target_y,
                        PALETTE["transparent"],
                    )
                    continue
                channels = []
                for channel in range(3):
                    numerator = (
                        source_color[channel] * source_alpha * 255
                        + target_color[channel]
                        * target_alpha
                        * (255 - source_alpha)
                    )
                    channels.append(
                        (numerator + out_alpha_numerator // 2)
                        // out_alpha_numerator
                    )
                out_alpha = (out_alpha_numerator + 127) // 255
                self.pixel(
                    target_x,
                    target_y,
                    (channels[0], channels[1], channels[2], out_alpha),
                )

    def resized_nearest(self, width: int, height: int) -> "Canvas":
        result = Canvas(width, height)
        for y in range(height):
            source_y = min(y * self.height // height, self.height - 1)
            for x in range(width):
                source_x = min(x * self.width // width, self.width - 1)
                result.pixel(x, y, self.get(source_x, source_y))
        return result

    def resized_bilinear(self, width: int, height: int) -> "Canvas":
        """Deterministic bilinear resize used when shrinking painted art."""
        result = Canvas(width, height)
        for y in range(height):
            source_y = ((y + 0.5) * self.height / height) - 0.5
            y0 = max(min(math.floor(source_y), self.height - 1), 0)
            y1 = min(y0 + 1, self.height - 1)
            y_weight = source_y - math.floor(source_y)
            if source_y < 0:
                y_weight = 0.0
            for x in range(width):
                source_x = ((x + 0.5) * self.width / width) - 0.5
                x0 = max(min(math.floor(source_x), self.width - 1), 0)
                x1 = min(x0 + 1, self.width - 1)
                x_weight = source_x - math.floor(source_x)
                if source_x < 0:
                    x_weight = 0.0
                top_left = self.get(x0, y0)
                top_right = self.get(x1, y0)
                bottom_left = self.get(x0, y1)
                bottom_right = self.get(x1, y1)
                channels: list[int] = []
                for channel in range(4):
                    top = (
                        top_left[channel] * (1.0 - x_weight)
                        + top_right[channel] * x_weight
                    )
                    bottom = (
                        bottom_left[channel] * (1.0 - x_weight)
                        + bottom_right[channel] * x_weight
                    )
                    channels.append(
                        round(top * (1.0 - y_weight) + bottom * y_weight)
                    )
                result.pixel(x, y, tuple(channels))  # type: ignore[arg-type]
        return result

    def cropped(self, x: int, y: int, width: int, height: int) -> "Canvas":
        result = Canvas(width, height)
        for target_y in range(height):
            for target_x in range(width):
                result.pixel(
                    target_x,
                    target_y,
                    self.get(x + target_x, y + target_y),
                )
        return result

    def masked(self, mask: str) -> "Canvas":
        result = Canvas(self.width, self.height)
        center_x = self.width / 2
        center_y = self.height / 2
        radius = min(self.width, self.height) / 2
        corner_radius = min(self.width, self.height) * 0.22
        for y in range(self.height):
            for x in range(self.width):
                dx = abs((x + 0.5) - center_x)
                dy = abs((y + 0.5) - center_y)
                keep = True
                if mask == "circle":
                    keep = dx * dx + dy * dy <= radius * radius
                elif mask == "squircle":
                    keep = dx**4 + dy**4 <= radius**4
                elif mask == "rounded":
                    inner = radius - corner_radius
                    corner_dx = max(dx - inner, 0.0)
                    corner_dy = max(dy - inner, 0.0)
                    keep = (
                        dx <= radius
                        and dy <= radius
                        and corner_dx * corner_dx + corner_dy * corner_dy
                        <= corner_radius * corner_radius
                    )
                if keep:
                    result.pixel(x, y, self.get(x, y))
        return result

    def to_png(self) -> bytes:
        stride = self.width * 4
        scanlines = b"".join(
            b"\x00" + bytes(self.pixels[y * stride : (y + 1) * stride])
            for y in range(self.height)
        )
        payload = bytearray(b"\x89PNG\r\n\x1a\n")
        payload += _png_chunk(
            b"IHDR",
            struct.pack(
                ">IIBBBBB",
                self.width,
                self.height,
                8,
                6,
                0,
                0,
                0,
            ),
        )
        payload += _png_chunk(b"IDAT", zlib.compress(scanlines, level=9))
        payload += _png_chunk(b"IEND", b"")
        return bytes(payload)


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(kind + data) & 0xFFFFFFFF
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", checksum)
    )


def read_png_rgba(path: Path) -> Canvas:
    """Read an 8-bit RGBA PNG with no external image library."""
    data = path.read_bytes()
    if not data.startswith(b"\x89PNG\r\n\x1a\n"):
        raise RuntimeError(f"not a PNG: {path}")

    offset = 8
    width = 0
    height = 0
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + length]
        offset += 12 + length
        if kind == b"IHDR":
            width, height, depth, color_type, compression, filtering, interlace = (
                struct.unpack(">IIBBBBB", payload)
            )
            if (depth, color_type, compression, filtering, interlace) != (
                8,
                6,
                0,
                0,
                0,
            ):
                raise RuntimeError(
                    f"unsupported PNG format: {path} "
                    f"(depth={depth}, color={color_type}, interlace={interlace})"
                )
        elif kind == b"IDAT":
            compressed.extend(payload)
        elif kind == b"IEND":
            break

    raw = zlib.decompress(bytes(compressed))
    stride = width * 4
    rows: list[bytearray] = []
    cursor = 0
    for _ in range(height):
        filter_kind = raw[cursor]
        cursor += 1
        row = bytearray(raw[cursor : cursor + stride])
        cursor += stride
        previous = rows[-1] if rows else bytearray(stride)
        for index in range(stride):
            left = row[index - 4] if index >= 4 else 0
            above = previous[index]
            upper_left = previous[index - 4] if index >= 4 else 0
            if filter_kind == 1:
                row[index] = (row[index] + left) & 0xFF
            elif filter_kind == 2:
                row[index] = (row[index] + above) & 0xFF
            elif filter_kind == 3:
                row[index] = (row[index] + ((left + above) // 2)) & 0xFF
            elif filter_kind == 4:
                predictor = left + above - upper_left
                distance_left = abs(predictor - left)
                distance_above = abs(predictor - above)
                distance_upper_left = abs(predictor - upper_left)
                nearest = (
                    left
                    if distance_left <= distance_above
                    and distance_left <= distance_upper_left
                    else above
                    if distance_above <= distance_upper_left
                    else upper_left
                )
                row[index] = (row[index] + nearest) & 0xFF
            elif filter_kind != 0:
                raise RuntimeError(
                    f"unsupported PNG filter: {filter_kind} ({path})"
                )
        rows.append(row)

    canvas = Canvas(width, height)
    canvas.pixels = bytearray().join(rows)
    return canvas


def background_shapes() -> tuple[Shape, ...]:
    """Five-color night-sky background that continues past the platform mask."""
    return (
        rect(0, 0, 107, 107, "night"),
        polygon(
            ((54, 0), (107, 54), (54, 107), (0, 54)),
            "night_mid",
        ),
        polygon(
            ((54, 10), (98, 54), (54, 98), (10, 54)),
            "night_light",
        ),
        rect(15, 23, 17, 25, "star"),
        rect(89, 24, 90, 25, "star_dim"),
        rect(13, 76, 14, 77, "star_dim"),
        rect(92, 72, 94, 74, "star"),
        rect(25, 12, 26, 13, "star_dim"),
        rect(82, 91, 83, 92, "star_dim"),
    )


def _foreground_source_shapes() -> tuple[Shape, ...]:
    """Close-up of a round hood and warm face, two hands cupping a beacon candle."""
    return (
        # Small graded-alpha halo behind the candle. Brighter toward the flame.
        rect(47, 62, 61, 82, "glow_dim"),
        rect(43, 68, 65, 78, "glow_dim"),
        rect(49, 62, 59, 78, "glow"),
        rect(46, 66, 62, 74, "glow"),
        rect(54, 19, 55, 20, "glow"),
        rect(85, 54, 86, 55, "glow"),
        rect(21, 54, 22, 55, "glow_dim"),
        rect(54, 88, 55, 88, "glow_dim"),
        # Short round cape. Gather the lower outline into the circular safe region.
        polygon(
            (
                (34, 57),
                (74, 57),
                (81, 64),
                (83, 72),
                (75, 79),
                (65, 85),
                (43, 85),
                (33, 79),
                (25, 72),
                (27, 64),
            ),
            "outline",
        ),
        polygon(
            (
                (36, 59),
                (72, 59),
                (78, 65),
                (80, 72),
                (74, 78),
                (64, 83),
                (44, 83),
                (34, 78),
                (28, 72),
                (30, 65),
            ),
            "hood_shadow",
        ),
        polygon(
            (
                (39, 61),
                (69, 61),
                (75, 66),
                (76, 72),
                (70, 78),
                (62, 81),
                (46, 81),
                (38, 78),
                (32, 72),
                (33, 66),
            ),
            "hood",
        ),
        polygon(
            ((34, 63), (42, 60), (42, 79), (35, 76), (31, 70)),
            "hood_light",
        ),
        polygon(
            ((66, 60), (74, 64), (77, 70), (72, 76), (66, 79)),
            "hood_dark",
        ),
        # Round lavender-blue hood outline.
        polygon(
            (
                (42, 22),
                (66, 22),
                (75, 28),
                (83, 37),
                (84, 49),
                (79, 59),
                (71, 67),
                (62, 70),
                (46, 70),
                (37, 67),
                (29, 60),
                (24, 50),
                (25, 37),
                (33, 28),
            ),
            "outline",
        ),
        polygon(
            (
                (43, 24),
                (65, 24),
                (75, 29),
                (81, 38),
                (82, 48),
                (77, 57),
                (69, 64),
                (61, 67),
                (47, 67),
                (39, 64),
                (31, 57),
                (27, 49),
                (28, 38),
                (33, 29),
            ),
            "hood",
        ),
        polygon(
            (
                (43, 25),
                (56, 25),
                (45, 29),
                (36, 35),
                (31, 44),
                (31, 52),
                (28, 48),
                (29, 38),
                (34, 30),
            ),
            "hood_light",
        ),
        polygon(
            (
                (66, 26),
                (74, 30),
                (79, 39),
                (80, 48),
                (75, 57),
                (69, 62),
                (73, 51),
                (74, 39),
            ),
            "hood_shadow",
        ),
        # Inside the hood, a short violet bob.
        polygon(
            (
                (40, 31),
                (68, 31),
                (75, 38),
                (76, 49),
                (71, 59),
                (64, 64),
                (44, 64),
                (37, 59),
                (32, 49),
                (33, 38),
            ),
            "hair_shadow",
        ),
        polygon(
            (
                (42, 34),
                (66, 34),
                (72, 39),
                (73, 49),
                (68, 57),
                (62, 61),
                (46, 61),
                (40, 57),
                (35, 49),
                (36, 40),
            ),
            "skin",
        ),
        polygon(
            (
                (39, 36),
                (45, 32),
                (64, 32),
                (70, 36),
                (72, 42),
                (66, 40),
                (63, 45),
                (59, 40),
                (55, 44),
                (51, 39),
                (47, 44),
                (43, 40),
                (36, 43),
            ),
            "hair",
        ),
        polygon(
            ((43, 34), (50, 32), (61, 33), (54, 35), (47, 36)),
            "hair_light",
        ),
        rect(38, 47, 41, 52, "outline"),
        rect(39, 47, 41, 50, "moon_bright"),
        rect(66, 47, 69, 52, "outline"),
        rect(66, 47, 68, 50, "moon_bright"),
        rect(39, 47, 39, 47, "moon_core"),
        rect(67, 47, 67, 47, "moon_core"),
        rect(36, 54, 39, 56, "blush"),
        rect(69, 54, 72, 56, "blush"),
        rect(53, 52, 55, 54, "skin_shadow"),
        rect(48, 57, 49, 58, "skin_shadow"),
        rect(50, 59, 58, 60, "skin_shadow"),
        rect(58, 57, 59, 58, "skin_shadow"),
        rect(51, 60, 57, 60, "skin_light"),
        # A small crescent pin. No protrusion that would read as gear or a muzzle.
        rect(72, 30, 75, 37, "gold"),
        rect(75, 30, 77, 34, "moon_core"),
        rect(74, 30, 77, 31, "moon_core"),
        rect(75, 35, 77, 37, "hood"),
        # Empty hands cupping a seed.
        polygon(
            ((34, 68), (39, 64), (47, 66), (48, 73), (43, 78), (36, 76)),
            "outline",
        ),
        polygon(
            ((37, 68), (40, 66), (45, 68), (46, 72), (42, 75), (38, 74)),
            "skin",
        ),
        rect(38, 67, 40, 69, "skin_light"),
        polygon(
            ((74, 68), (69, 64), (61, 66), (60, 73), (65, 78), (72, 76)),
            "outline",
        ),
        polygon(
            ((71, 68), (68, 66), (63, 68), (62, 72), (66, 75), (70, 74)),
            "skin",
        ),
        rect(68, 67, 70, 69, "skin_light"),
        # Center beacon candle. The icon's brightest focus, instead of a weapon.
        #
        # The game is named moonlight "beacon", but older art held a moonlight seed so
        # it was unreadable. Match the sprite with the same candle.
        rect(46, 71, 62, 87, "outline"),
        rect(47, 72, 61, 86, "wax"),
        rect(47, 72, 51, 86, "wax_light"),
        rect(58, 72, 61, 86, "wax_shade"),
        rect(47, 72, 61, 74, "wax_light"),
        # Dripped wax. A silhouette that reads as a candle at a glance.
        rect(48, 75, 50, 82, "wax_light"),
        rect(56, 76, 58, 80, "wax_light"),
        # Wick.
        rect(53, 70, 55, 73, "outline"),
        # Flame. Start below the chin (y=60) and use only the width between the hands —
        # Taller covers the face; wider covers the hands.
        polygon(
            ((54, 61), (58, 66), (58, 70), (54, 73), (50, 70), (50, 66)),
            "outline",
        ),
        polygon(
            ((54, 63), (57, 67), (57, 70), (54, 72), (51, 70), (51, 67)),
            "flame",
        ),
        polygon(
            ((54, 66), (56, 69), (54, 71), (52, 69)),
            "flame_core",
        ),
    )


def _scale_foreground_coordinate(value: int) -> int:
    """9/10 shrink around center 54. Signed integer rounding pins the result."""
    delta = value - LOGICAL_SIZE // 2
    magnitude = (
        abs(delta) * FOREGROUND_SCALE_NUMERATOR
        + FOREGROUND_SCALE_DENOMINATOR // 2
    ) // FOREGROUND_SCALE_DENOMINATOR
    scaled_delta = magnitude if delta >= 0 else -magnitude
    return LOGICAL_SIZE // 2 + scaled_delta


def foreground_shapes() -> tuple[Shape, ...]:
    """Uniformly scale the original fixed coords into the official 66dp safe zone."""
    result: list[Shape] = []
    for shape in _foreground_source_shapes():
        result.append(
            Shape(
                shape.kind,
                shape.color,
                tuple(
                    (
                        _scale_foreground_coordinate(x),
                        _scale_foreground_coordinate(y),
                    )
                    for x, y in shape.points
                ),
            )
        )
    return tuple(result)


def render(shapes: Iterable[Shape]) -> Canvas:
    canvas = Canvas(LOGICAL_SIZE, LOGICAL_SIZE)
    for shape in shapes:
        color = PALETTE[shape.color]
        if shape.kind == "rect":
            (x0, y0), (x1, y1) = shape.points
            canvas.rect(x0, y0, x1, y1, color)
        else:
            canvas.polygon(shape.points, color)
    return canvas


def _svg_shape(shape: Shape) -> str:
    color = PALETTE[shape.color]
    color_hex = f"#{color[0]:02x}{color[1]:02x}{color[2]:02x}"
    opacity = (
        ""
        if color[3] == 255
        else f' fill-opacity="{color[3] / 255:.3f}"'
    )
    if shape.kind == "rect":
        (x0, y0), (x1, y1) = shape.points
        return (
            f'  <rect x="{x0}" y="{y0}" '
            f'width="{x1 - x0 + 1}" height="{y1 - y0 + 1}" '
            f'fill="{color_hex}"{opacity}/>'
        )
    points = " ".join(f"{x},{y}" for x, y in shape.points)
    return f'  <polygon points="{points}" fill="{color_hex}"{opacity}/>'


def build_svg() -> bytes:
    shapes = (*background_shapes(), *foreground_shapes())
    lines = [
        '<svg width="128" height="128" viewBox="0 0 108 108" '
        'xmlns="http://www.w3.org/2000/svg" shape-rendering="crispEdges">',
        *(_svg_shape(shape) for shape in shapes),
        "</svg>",
        "",
    ]
    return "\n".join(lines).encode("utf-8")


def build_outputs() -> tuple[Canvas, Canvas, Canvas]:
    """Legacy vector-mark based output, for existing marketing-graphic compatibility."""
    background = render(background_shapes()).resized_nearest(
        ANDROID_SIZE,
        ANDROID_SIZE,
    )
    foreground = render(foreground_shapes()).resized_nearest(
        ANDROID_SIZE,
        ANDROID_SIZE,
    )
    combined = Canvas(ANDROID_SIZE, ANDROID_SIZE)
    combined.composite(background)
    combined.composite(foreground)
    main = combined.resized_nearest(MAIN_SIZE, MAIN_SIZE)
    return main, foreground, background


def load_production_outputs() -> tuple[Canvas, Canvas, Canvas]:
    """Read the live iOS/Android ship-icon PNG set."""
    master = read_png_rgba(CUSTOM_UI_DIR / "app_icon_master.png")
    if master.width != MASTER_SIZE or master.height != MASTER_SIZE:
        raise RuntimeError(
            "master size is "
            f"is {master.width}x{master.height} "
            f"(contract {MASTER_SIZE}x{MASTER_SIZE})"
        )
    if _alpha_mode(master) != "opaque":
        raise RuntimeError("master app icon must be opaque")
    master_colors = _visible_colors(master)
    if master_colors > MASTER_COLOR_LIMIT:
        raise RuntimeError(
            "master app icon color count exceeds the contract: "
            f"{master_colors} > {MASTER_COLOR_LIMIT}"
        )
    return (
        read_png_rgba(CUSTOM_UI_DIR / "app_icon_main.png"),
        read_png_rgba(CUSTOM_UI_DIR / "app_icon_foreground.png"),
        read_png_rgba(CUSTOM_UI_DIR / "app_icon_background.png"),
    )


def _alpha_mode(canvas: Canvas) -> str:
    alpha_levels = set(canvas.pixels[3::4])
    if alpha_levels == {255}:
        return "opaque"
    if any(0 < alpha < 255 for alpha in alpha_levels):
        return "graded"
    return "binary"


def _visible_colors(canvas: Canvas) -> int:
    return len(
        {
            tuple(canvas.pixels[index : index + 3])
            for index in range(0, len(canvas.pixels), 4)
            if canvas.pixels[index + 3] > 0
        }
    )


def validate_outputs(
    main: Canvas,
    foreground: Canvas,
    background: Canvas,
) -> float:
    expected = (
        ("main", main, MAIN_SIZE, "opaque", MAIN_COLOR_LIMIT),
        (
            "foreground",
            foreground,
            ANDROID_SIZE,
            "graded",
            FOREGROUND_COLOR_LIMIT,
        ),
        (
            "background",
            background,
            ANDROID_SIZE,
            "opaque",
            BACKGROUND_COLOR_LIMIT,
        ),
    )
    for label, canvas, size, alpha_mode, color_limit in expected:
        if canvas.width != size or canvas.height != size:
            raise RuntimeError(
                f"{label} size is {canvas.width}x{canvas.height} "
                f"(contract {size}x{size})"
            )
        actual_alpha = _alpha_mode(canvas)
        if actual_alpha != alpha_mode:
            raise RuntimeError(
                f"{label} alpha mode is {actual_alpha} "
                f"(contract {alpha_mode})"
            )
        visible_colors = _visible_colors(canvas)
        if visible_colors > color_limit:
            raise RuntimeError(
                f"{label} visible colors are {visible_colors} "
                f"(contract max {color_limit})"
            )

    center = ANDROID_SIZE / 2
    farthest = 0.0
    farthest_pixel = (0, 0)
    for y in range(foreground.height):
        for x in range(foreground.width):
            if foreground.get(x, y)[3] == 0:
                continue
            distance = max(
                math.hypot(corner_x - center, corner_y - center)
                for corner_x in (x, x + 1)
                for corner_y in (y, y + 1)
            )
            if distance > farthest:
                farthest = distance
                farthest_pixel = (x, y)
    if farthest > ADAPTIVE_SAFE_RADIUS:
        raise RuntimeError(
            "Android adaptive foreground left the safe circle: "
            f"pixel={farthest_pixel}, dist={farthest:.2f}px, "
            f"allowed={ADAPTIVE_SAFE_RADIUS:.0f}px"
        )
    return farthest


def build_preview(main: Canvas, foreground: Canvas, background: Canvas) -> Canvas:
    combined = Canvas(ANDROID_SIZE, ANDROID_SIZE)
    combined.composite(background)
    combined.composite(foreground)
    viewport_size = round(ADAPTIVE_VIEWPORT_RADIUS * 2)
    viewport_origin = (ANDROID_SIZE - viewport_size) // 2
    adaptive_viewport = combined.cropped(
        viewport_origin,
        viewport_origin,
        viewport_size,
        viewport_size,
    )
    tile_size = 288
    gap = 28
    margin = 32
    preview = Canvas(
        margin * 2 + tile_size * 4 + gap * 3,
        margin * 2 + tile_size,
        PALETTE["outline"],
    )
    masks = ("none", "circle", "squircle", "rounded")
    sources = (
        main.resized_nearest(ANDROID_SIZE, ANDROID_SIZE),
        adaptive_viewport,
        adaptive_viewport,
        adaptive_viewport,
    )
    for index, (source, mask) in enumerate(zip(sources, masks)):
        tile = source.masked(mask).resized_nearest(tile_size, tile_size)
        preview.composite(tile, margin + index * (tile_size + gap), margin)
    return preview


def _validate_repository_links() -> None:
    presets = (GAME_ROOT / "export_presets.cfg").read_text(encoding="utf-8")
    expected_paths = {
        'launcher_icons/main_192x192="res://assets/custom/ui/app_icon_main.png"': 2,
        (
            'launcher_icons/adaptive_foreground_432x432='
            '"res://assets/custom/ui/app_icon_foreground.png"'
        ): 2,
        (
            'launcher_icons/adaptive_background_432x432='
            '"res://assets/custom/ui/app_icon_background.png"'
        ): 2,
    }
    for setting, count in expected_paths.items():
        actual = presets.count(setting)
        if actual != count:
            raise RuntimeError(
                f"export_presets.cfg icon path count is {actual} "
                f"(contract {count}): {setting}"
            )
    if "res://assets/derived/logo/" in presets:
        raise RuntimeError("export_presets.cfg still has a legacy derived/logo path")

    project = (GAME_ROOT / "project.godot").read_text(encoding="utf-8")
    if (
        'config/icon="res://assets/custom/ui/app_icon_master.png"'
        not in project
    ):
        raise RuntimeError("project.godot config/icon contract changed")

    docusaurus = (
        REPO_ROOT / "apps/docs/docusaurus.config.ts"
    ).read_text(encoding="utf-8")
    if "favicon: 'img/favicon.png'" not in docusaurus:
        raise RuntimeError("Docusaurus favicon path contract changed")
    if "logo: {alt: 'Moonlit Beacon', src: 'img/logo.png'}" not in docusaurus:
        raise RuntimeError("Docusaurus logo path contract changed")

    contracts_path = GAME_ROOT / "tools/custom_asset_contracts.json"
    contracts = json.loads(contracts_path.read_text(encoding="utf-8"))
    by_id = {
        entry["id"]: entry
        for entry in contracts.get("assets", [])
        if isinstance(entry, dict) and isinstance(entry.get("id"), str)
    }
    expected_contracts = {
        "ui.app_icon_master": {
            "status": "final",
            "path": "assets/custom/ui/app_icon_master.png",
            "width": MASTER_SIZE,
            "height": MASTER_SIZE,
            "alpha_mode": "opaque",
            "max_alpha_levels": 1,
        },
        "ui.app_icon_main": {
            "status": "final",
            "path": "assets/custom/ui/app_icon_main.png",
            "width": 192,
            "height": 192,
            "alpha_mode": "opaque",
            "max_alpha_levels": 1,
        },
        "ui.app_icon_foreground": {
            "status": "final",
            "path": "assets/custom/ui/app_icon_foreground.png",
            "width": 432,
            "height": 432,
            "alpha_mode": "graded",
            "max_alpha_levels": 256,
        },
        "ui.app_icon_background": {
            "status": "final",
            "path": "assets/custom/ui/app_icon_background.png",
            "width": 432,
            "height": 432,
            "alpha_mode": "opaque",
            "max_alpha_levels": 1,
        },
    }
    for asset_id, expected in expected_contracts.items():
        actual = by_id.get(asset_id)
        if actual is None:
            raise RuntimeError(f"custom icon contract is missing: {asset_id}")
        mismatches = [
            f"{key}={actual.get(key)!r} (contract {value!r})"
            for key, value in expected.items()
            if actual.get(key) != value
        ]
        if mismatches:
            raise RuntimeError(
                f"{asset_id} custom contract changed: "
                + ", ".join(mismatches)
            )

    legacy_dir = GAME_ROOT / "assets/derived/logo"
    legacy_files = sorted(
        path.name
        for path in legacy_dir.glob("icon_*.png*")
        if path.is_file()
    )
    if legacy_files:
        raise RuntimeError(
            "leftover launcher icon files with no consumer remain: "
            + ", ".join(legacy_files)
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="inspect every production file and platform-path contract without writing",
    )
    args = parser.parse_args()

    main_icon, foreground, background = load_production_outputs()
    farthest = validate_outputs(main_icon, foreground, background)
    svg = build_svg()
    # The launcher PNG set and iOS master use painted art. Do not bake them here.
    #
    # Keep the shape defs (`build_outputs`) and safe-circle check (`validate_outputs`) —
    # New art must keep the same 132px radius rule, and that number lives here.
    # Only the editor icon.svg still comes from the shape definition. The docs
    # site shows the painted launcher art: logo.png is app_icon_main.png bytes,
    # favicon.png its exact 6x nearest decimation to 32×32.
    production: dict[Path, bytes] = {
        GAME_ROOT / "icon.svg": svg,
        DOCS_IMAGE_DIR / "logo.png": (
            CUSTOM_UI_DIR / "app_icon_main.png"
        ).read_bytes(),
        DOCS_IMAGE_DIR / "favicon.png": main_icon.resized_nearest(
            32, 32
        ).to_png(),
    }
    for name in (
        "app_icon_master.png",
        "app_icon_main.png",
        "app_icon_foreground.png",
        "app_icon_background.png",
    ):
        if not (CUSTOM_UI_DIR / name).is_file():
            raise RuntimeError(f"production launcher icon is missing: {name}")

    if args.check:
        _validate_repository_links()
        for path, expected in production.items():
            if not path.is_file():
                raise RuntimeError(f"production app-icon file is missing: {path}")
            if path.read_bytes() != expected:
                raise RuntimeError(
                    f"production app icon differs from the deterministic created result: {path}. "
                    "run build_app_icon_assets.py again"
                )
    else:
        for path, data in production.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        preview = build_preview(main_icon, foreground, background)
        REVIEW_DIR.mkdir(parents=True, exist_ok=True)
        (REVIEW_DIR / "app-icon-preview.png").write_bytes(preview.to_png())

    print(f"App icon master: {MASTER_SIZE}x{MASTER_SIZE}, opaque")
    print(f"App icon main: {MAIN_SIZE}x{MAIN_SIZE}, opaque")
    print(f"App icon foreground: {ANDROID_SIZE}x{ANDROID_SIZE}, graded alpha")
    print(f"App icon background: {ANDROID_SIZE}x{ANDROID_SIZE}, opaque")
    print(
        "Adaptive guaranteed safe circle: "
        f"farthest visible pixel {farthest:.2f}px / "
        f"{ADAPTIVE_SAFE_RADIUS:.0f}px "
        f"(viewport {ADAPTIVE_VIEWPORT_RADIUS:.0f}px)"
    )
    print(
        "check: production icons and platform paths are deterministic"
        if args.check
        else f"review: {REVIEW_DIR / 'app-icon-preview.png'}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
