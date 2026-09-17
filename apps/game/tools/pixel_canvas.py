#!/usr/bin/env python3
"""Deterministic RGBA pixel canvas. Bakes PNG without an external image library."""

from __future__ import annotations

import binascii
import math
import struct
import zlib
from pathlib import Path
from typing import Iterable

RGBA = tuple[int, int, int, int]
Point = tuple[int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)


class Canvas:
    """Integer-coordinate RGBA canvas."""

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
        for y in range(min(y0, y1), max(y0, y1) + 1):
            for x in range(min(x0, x1), max(x0, x1) + 1):
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
            doubled = 2 * error
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

    def disc(self, cx: int, cy: int, radius: int, color: RGBA) -> None:
        threshold = radius * radius + radius
        for y in range(cy - radius, cy + radius + 1):
            for x in range(cx - radius, cx + radius + 1):
                if (x - cx) ** 2 + (y - cy) ** 2 <= threshold:
                    self.pixel(x, y, color)

    def ellipse(self, cx: int, cy: int, rx: int, ry: int, color: RGBA) -> None:
        if rx <= 0 or ry <= 0:
            return
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                nx = (x - cx + 0.5) / rx
                ny = (y - cy + 0.5) / ry
                if nx * nx + ny * ny <= 1.0:
                    self.pixel(x, y, color)

    def outlined_disc(
        self, cx: int, cy: int, radius: int, outline: RGBA, fill: RGBA
    ) -> None:
        self.disc(cx, cy, radius, outline)
        if radius > 0:
            self.disc(cx, cy, max(radius - 1, 0), fill)

    def outlined_ellipse(
        self, cx: int, cy: int, rx: int, ry: int, outline: RGBA, fill: RGBA
    ) -> None:
        self.ellipse(cx, cy, rx, ry, outline)
        self.ellipse(cx, cy, max(rx - 1, 1), max(ry - 1, 1), fill)

    def ring(
        self, cx: int, cy: int, radius: int, thickness: int, color: RGBA
    ) -> None:
        outer = radius * radius + radius
        inner_radius = max(radius - thickness, 0)
        inner = inner_radius * inner_radius
        for y in range(cy - radius, cy + radius + 1):
            for x in range(cx - radius, cx + radius + 1):
                distance = (x - cx) ** 2 + (y - cy) ** 2
                if inner <= distance <= outer:
                    self.pixel(x, y, color)

    def outline_opaque(self, outline: RGBA) -> None:
        """Paint only transparent neighbors of the opaque silhouette as outline."""
        marks: list[Point] = []
        for y in range(self.height):
            for x in range(self.width):
                if self.get(x, y)[3] != 0:
                    continue
                for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
                    if self.get(nx, ny)[3] > 0:
                        marks.append((x, y))
                        break
        for x, y in marks:
            self.pixel(x, y, outline)

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

    def mirrored(self) -> "Canvas":
        result = Canvas(self.width, self.height)
        for y in range(self.height):
            for x in range(self.width):
                result.pixel(self.width - 1 - x, y, self.get(x, y))
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
