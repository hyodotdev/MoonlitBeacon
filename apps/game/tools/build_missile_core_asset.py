#!/usr/bin/env python3
"""Deterministically build the 4-frame moonlight-core kill-loot pixel sheet.

Output:

    assets/custom/items/pickups/power_gem.png  96x24

a transparent moonlight crystal, inner ember, and four spinning lock wings inside a 24px cell.
Draw them. Do not use pixels from an external asset or an image-create model.
"""

from __future__ import annotations

import argparse
import binascii
import struct
import zlib
from pathlib import Path


GAME_ROOT = Path(__file__).resolve().parents[1]
ASSET_PATH = GAME_ROOT / "assets/custom/items/pickups/power_gem.png"
CELL = 24
FRAMES = 4

RGBA = tuple[int, int, int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)
HALO_DIM: RGBA = (88, 187, 255, 54)
HALO: RGBA = (110, 211, 255, 112)
OUTLINE: RGBA = (25, 35, 63, 255)
BLUE_DARK: RGBA = (65, 114, 190, 255)
BLUE: RGBA = (92, 184, 238, 255)
ICE: RGBA = (178, 230, 255, 255)
WHITE: RGBA = (235, 248, 255, 255)
GOLD: RGBA = (242, 183, 74, 255)
EMBER: RGBA = (255, 226, 126, 255)


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

    def rect(self, x0: int, y0: int, x1: int, y1: int, color: RGBA) -> None:
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
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


def _draw_frame(canvas: Canvas, frame: int) -> None:
    x = frame * CELL
    pulse = (0, 1, 0, -1)[frame]
    top = 4 - pulse
    bottom = 19 + pulse

    # Translucent moonlight halo. Leave the outer 1px empty to stop atlas bleed.
    canvas.rect(x + 7, 3, x + 16, 20, HALO_DIM)
    canvas.rect(x + 4, 8, x + 19, 15, HALO_DIM)
    canvas.rect(x + 8, 5, x + 15, 18, HALO)
    canvas.rect(x + 6, 9, x + 17, 14, HALO)

    # Four lock wings that rotate clockwise each frame.
    if frame % 2 == 0:
        canvas.rect(x + 10, top, x + 13, 8, OUTLINE)
        canvas.rect(x + 11, top + 1, x + 12, 7, ICE)
        canvas.rect(x + 10, 15, x + 13, bottom, OUTLINE)
        canvas.rect(x + 11, 16, x + 12, bottom - 1, BLUE)
        canvas.rect(x + 4, 10, x + 8, 13, OUTLINE)
        canvas.rect(x + 5, 11, x + 8, 12, BLUE)
        canvas.rect(x + 15, 10, x + 19, 13, OUTLINE)
        canvas.rect(x + 15, 11, x + 18, 12, ICE)
    else:
        canvas.rect(x + 5, 5, x + 9, 9, OUTLINE)
        canvas.rect(x + 6, 6, x + 9, 8, BLUE)
        canvas.rect(x + 14, 5, x + 18, 9, OUTLINE)
        canvas.rect(x + 14, 6, x + 17, 8, ICE)
        canvas.rect(x + 5, 14, x + 9, 18, OUTLINE)
        canvas.rect(x + 6, 14, x + 9, 17, BLUE_DARK)
        canvas.rect(x + 14, 14, x + 18, 18, OUTLINE)
        canvas.rect(x + 14, 14, x + 17, 17, BLUE)

    # Octagon crystal outline and a small ember inside.
    canvas.rect(x + 9, 7, x + 14, 16, OUTLINE)
    canvas.rect(x + 7, 9, x + 16, 14, OUTLINE)
    canvas.rect(x + 9, 8, x + 14, 15, BLUE_DARK)
    canvas.rect(x + 8, 10, x + 15, 13, BLUE)
    canvas.rect(x + 10, 9, x + 13, 14, ICE)
    canvas.rect(x + 11, 10, x + 12, 13, WHITE)
    canvas.pixel(x + 10, 9, WHITE)
    canvas.pixel(x + 11, 11, GOLD)
    canvas.pixel(x + 12, 11, GOLD)
    canvas.pixel(x + 11, 12, EMBER)
    canvas.pixel(x + 12, 12, EMBER)


def build() -> Canvas:
    canvas = Canvas(CELL * FRAMES, CELL)
    for frame in range(FRAMES):
        _draw_frame(canvas, frame)
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="inspect without writing that production PNG matches the deterministic created result",
    )
    args = parser.parse_args()
    canvas = build()
    encoded = canvas.to_png()
    if args.check:
        if not ASSET_PATH.is_file():
            raise RuntimeError(f"production moonlight-core PNG is missing: {ASSET_PATH}")
        if ASSET_PATH.read_bytes() != encoded:
            raise RuntimeError(
                "production moonlight-core PNG differs from the deterministic created result. "
                "run build_missile_core_asset.py again"
            )
    else:
        ASSET_PATH.parent.mkdir(parents=True, exist_ok=True)
        ASSET_PATH.write_bytes(encoded)
    print(f"Moonlight core: {canvas.width}x{canvas.height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
