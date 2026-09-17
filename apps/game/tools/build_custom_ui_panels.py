#!/usr/bin/env python3
"""Deterministically build Moonlit Beacon 16×16 nine-patch UI.

Keep the existing UI ``StyleBoxTexture`` margins (5px normal panel, 6px relic card)
so both PNGs are 16×16 RGBA. Ink-navy fill, moon-silver outline,
teal inner line, beacon-scarlet rivets. No external image library.

Output:

    assets/custom/ui/panel_moonlit.png
    assets/custom/ui/nine_path_panel_moonlit.png
    assets/custom/ui/button_{normal,hover,pressed,disabled,focus}_moonlit.png
"""

from __future__ import annotations

import argparse
import binascii
import hashlib
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path


GAME_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = GAME_ROOT / "assets/custom/ui"
SIZE = 16

RGBA = tuple[int, int, int, int]
TRANSPARENT: RGBA = (0, 0, 0, 0)
INK: RGBA = (6, 11, 25, 255)
OUTER_NIGHT: RGBA = (12, 21, 42, 255)
MOON_SHADOW: RGBA = (63, 82, 115, 255)
MOON_SILVER: RGBA = (137, 164, 194, 255)
MOON_LIGHT: RGBA = (199, 221, 232, 255)
FOCUS_LIGHT: RGBA = (235, 249, 255, 255)
TEAL_DARK: RGBA = (24, 79, 91, 255)
TEAL: RGBA = (42, 149, 158, 255)
TEAL_LIGHT: RGBA = (84, 211, 207, 255)
PANEL_NIGHT: RGBA = (14, 27, 52, 255)
PANEL_LIGHT: RGBA = (19, 35, 65, 255)
PANEL_HOVER: RGBA = (22, 48, 76, 255)
PANEL_PRESSED: RGBA = (8, 18, 39, 255)
DISABLED_EDGE: RGBA = (70, 82, 103, 255)
DISABLED_PANEL: RGBA = (24, 30, 43, 255)
EMBER_DARK: RGBA = (129, 47, 35, 255)
EMBER: RGBA = (235, 88, 44, 255)
EMBER_LIGHT: RGBA = (255, 151, 72, 255)


@dataclass(frozen=True)
class OutputSpec:
    filename: str
    margin: int
    canvas: "Canvas"


class Canvas:
    """Tiny RGBA pixel canvas used without Pillow."""

    def __init__(self, width: int = SIZE, height: int = SIZE) -> None:
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

    def get(self, x: int, y: int) -> RGBA:
        offset = (y * self.width + x) * 4
        return tuple(self.pixels[offset : offset + 4])  # type: ignore[return-value]

    def png_bytes(self) -> bytes:
        stride = self.width * 4
        scanlines = b"".join(
            b"\x00" + bytes(self.pixels[y * stride : (y + 1) * stride])
            for y in range(self.height)
        )
        payload = bytearray(b"\x89PNG\r\n\x1a\n")
        payload += _png_chunk(
            b"IHDR",
            struct.pack(
                ">IIBBBBB", self.width, self.height, 8, 6, 0, 0, 0
            ),
        )
        payload += _png_chunk(b"IDAT", zlib.compress(scanlines, level=9))
        payload += _png_chunk(b"IEND", b"")
        return bytes(payload)


def _png_chunk(kind: bytes, data: bytes) -> bytes:
    checksum = binascii.crc32(kind + data) & 0xFFFFFFFF
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", checksum)


def _draw_cut_corner_silhouette(canvas: Canvas) -> None:
    """Leave the same 12 transparent corner pixels as the original 16px panel."""
    canvas.rect(2, 0, 13, 0, INK)
    canvas.rect(1, 1, 14, 1, INK)
    canvas.rect(0, 2, 15, 13, INK)
    canvas.rect(1, 14, 14, 14, INK)
    canvas.rect(2, 15, 13, 15, INK)


def _draw_standard_panel() -> Canvas:
    canvas = Canvas()
    _draw_cut_corner_silhouette(canvas)

    # Outer moon-silver metal: the top takes moonlight, the bottom sinks into ink-navy shadow.
    canvas.rect(2, 1, 13, 1, MOON_SHADOW)
    canvas.rect(1, 2, 14, 2, MOON_SILVER)
    canvas.rect(1, 3, 1, 12, MOON_SHADOW)
    canvas.rect(14, 3, 14, 12, MOON_SHADOW)
    canvas.rect(2, 13, 13, 13, MOON_SHADOW)
    canvas.rect(2, 14, 13, 14, OUTER_NIGHT)
    canvas.pixel(3, 1, MOON_LIGHT)
    canvas.pixel(4, 1, MOON_SILVER)

    # Teal inner band and even center face. The 5px nine-patch center is solid so scaling
    # does not make large blotches or stripes.
    canvas.rect(2, 3, 13, 12, TEAL_DARK)
    canvas.rect(3, 3, 12, 3, TEAL)
    canvas.rect(3, 4, 12, 12, PANEL_NIGHT)
    canvas.rect(4, 4, 11, 4, PANEL_LIGHT)
    canvas.rect(4, 5, 11, 11, PANEL_LIGHT)
    canvas.rect(5, 5, 10, 10, PANEL_NIGHT)

    # Beacon rivets live only inside the fixed corner pieces.
    for x, y in ((3, 3), (12, 3), (3, 12), (12, 12)):
        canvas.pixel(x, y, EMBER_DARK)
    canvas.pixel(12, 3, EMBER_LIGHT)
    canvas.pixel(3, 12, EMBER)
    return canvas


def _draw_relic_panel() -> Canvas:
    canvas = Canvas()
    _draw_cut_corner_silhouette(canvas)

    # Relic cards use stronger moon-silver corners and a scarlet seal so they are distinct from normal buttons.
    canvas.rect(2, 1, 13, 1, MOON_SILVER)
    canvas.rect(1, 2, 14, 2, MOON_LIGHT)
    canvas.rect(1, 3, 1, 12, MOON_SHADOW)
    canvas.rect(14, 3, 14, 12, MOON_SHADOW)
    canvas.rect(2, 13, 13, 13, MOON_SHADOW)
    canvas.rect(2, 14, 13, 14, OUTER_NIGHT)

    canvas.rect(2, 3, 13, 12, OUTER_NIGHT)
    canvas.rect(3, 3, 12, 3, TEAL)
    canvas.rect(2, 4, 2, 11, TEAL_DARK)
    canvas.rect(13, 4, 13, 11, TEAL_DARK)
    canvas.rect(3, 12, 12, 12, TEAL_DARK)
    canvas.rect(3, 4, 12, 11, PANEL_NIGHT)
    canvas.rect(4, 4, 11, 4, PANEL_LIGHT)
    canvas.rect(4, 5, 11, 10, PANEL_LIGHT)
    canvas.rect(5, 5, 10, 10, PANEL_NIGHT)

    # Beacon seal inside the 6px margin. Leave the center 4×4 solid.
    canvas.rect(3, 3, 4, 3, EMBER_DARK)
    canvas.rect(11, 3, 12, 3, EMBER_DARK)
    canvas.pixel(3, 4, EMBER)
    canvas.pixel(12, 4, EMBER_LIGHT)
    canvas.pixel(3, 11, EMBER_LIGHT)
    canvas.pixel(12, 11, EMBER)
    canvas.pixel(2, 7, MOON_SILVER)
    canvas.pixel(13, 8, MOON_SILVER)
    return canvas


def _draw_button_panel(state: str) -> Canvas:
    """Draw button states shared by the 5px and 6px nine-patches.

    focus is an overlay Godot draws on top of the default state, so leave the inside
    transparent. The other four states have solid center 6×6 and 4×4 so
    solid, so neither 5px nor 6px margins get scale stripes.
    """
    if state == "focus":
        canvas = Canvas()
        canvas.rect(2, 0, 13, 0, FOCUS_LIGHT)
        canvas.rect(1, 1, 14, 1, MOON_LIGHT)
        canvas.rect(0, 2, 0, 13, MOON_LIGHT)
        canvas.rect(15, 2, 15, 13, MOON_LIGHT)
        canvas.rect(1, 14, 14, 14, TEAL_LIGHT)
        canvas.rect(2, 15, 13, 15, TEAL)
        for x, y in ((1, 2), (14, 2), (1, 13), (14, 13)):
            canvas.pixel(x, y, FOCUS_LIGHT)
        return canvas

    canvas = Canvas()
    _draw_cut_corner_silhouette(canvas)

    if state == "hover":
        edge_top = MOON_LIGHT
        edge_side = MOON_SILVER
        accent = TEAL_LIGHT
        fill = PANEL_HOVER
        rivet = EMBER_LIGHT
    elif state == "pressed":
        edge_top = MOON_SHADOW
        edge_side = OUTER_NIGHT
        accent = TEAL_DARK
        fill = PANEL_PRESSED
        rivet = EMBER
    elif state == "disabled":
        edge_top = DISABLED_EDGE
        edge_side = OUTER_NIGHT
        accent = DISABLED_EDGE
        fill = DISABLED_PANEL
        rivet = MOON_SHADOW
    elif state == "normal":
        edge_top = MOON_SILVER
        edge_side = MOON_SHADOW
        accent = TEAL
        fill = PANEL_NIGHT
        rivet = EMBER
    else:
        raise ValueError(f"unknown button state: {state}")

    # Hover brightens top-left, press brightens bottom-right, for a 3D response.
    canvas.rect(2, 1, 13, 1, edge_top)
    canvas.rect(1, 2, 14, 2, edge_top)
    canvas.rect(1, 3, 1, 12, edge_side)
    canvas.rect(14, 3, 14, 12, edge_side)
    canvas.rect(2, 13, 13, 13, edge_side)
    canvas.rect(2, 14, 13, 14, OUTER_NIGHT)

    canvas.rect(2, 3, 13, 12, accent)
    canvas.rect(3, 4, 12, 11, fill)
    canvas.rect(4, 4, 11, 11, fill)
    canvas.rect(5, 5, 10, 10, fill)

    for x, y in ((3, 3), (12, 3), (3, 12), (12, 12)):
        canvas.pixel(x, y, rivet)
    if state == "hover":
        canvas.pixel(3, 3, FOCUS_LIGHT)
        canvas.pixel(12, 3, EMBER_LIGHT)
    elif state == "pressed":
        canvas.pixel(3, 12, EMBER_LIGHT)
        canvas.pixel(12, 12, EMBER_DARK)
    return canvas


def build_outputs() -> tuple[OutputSpec, ...]:
    panels = (
        OutputSpec("panel_moonlit.png", 5, _draw_standard_panel()),
        OutputSpec("nine_path_panel_moonlit.png", 6, _draw_relic_panel()),
    )
    buttons = tuple(
        OutputSpec(
            f"button_{state}_moonlit.png",
            5,
            _draw_button_panel(state),
        )
        for state in ("normal", "hover", "pressed", "disabled", "focus")
    )
    return panels + buttons


def _validate(spec: OutputSpec) -> None:
    canvas = spec.canvas
    if (canvas.width, canvas.height) != (SIZE, SIZE):
        raise RuntimeError(f"{spec.filename}: is not 16×16")
    transparent = sum(
        1
        for y in range(SIZE)
        for x in range(SIZE)
        if canvas.get(x, y)[3] == 0
    )
    is_focus = spec.filename == "button_focus_moonlit.png"
    expected_transparent = 176 if is_focus else 12
    if transparent != expected_transparent:
        raise RuntimeError(
            f"{spec.filename}: transparent pixels must be {expected_transparent}px "
            f"({transparent})"
        )
    start = spec.margin
    end = SIZE - spec.margin
    center_colors = {
        canvas.get(x, y)
        for y in range(start, end)
        for x in range(start, end)
    }
    expected_center = {TRANSPARENT} if is_focus else {canvas.get(7, 7)}
    if center_colors != expected_center:
        raise RuntimeError(
            f"{spec.filename}: {spec.margin}px nine-patch center must be solid"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="confirm without writing that production PNG matches the deterministic result",
    )
    args = parser.parse_args()

    for spec in build_outputs():
        _validate(spec)
        encoded = spec.canvas.png_bytes()
        path = OUTPUT_DIR / spec.filename
        if args.check:
            if not path.is_file() or path.read_bytes() != encoded:
                raise RuntimeError(
                    f"{spec.filename}: production PNG differs from the generator result"
                )
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(encoded)
        digest = hashlib.sha256(encoded).hexdigest()
        print(
            f"{path.relative_to(GAME_ROOT)} — 16x16 RGBA, "
            f"margin {spec.margin}px, sha256 {digest}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
