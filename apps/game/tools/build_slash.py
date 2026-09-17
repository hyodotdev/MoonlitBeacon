"""Bake the moonlight-blade slash VFX.

Makes `assets/derived/fx/moon_slash.png`. Four 32x32 cells in a row, a
128x32 sheet.

    python apps/game/tools/build_slash.py

## Why bake a picture file

The asset pack has no slash art. Drawing by hand would mean redrawing every time the angle changes,
and the fan angle must be **the same value as** `player.gd` `ATTACK_ARC` —
If the visible range and the real hit range differ, it becomes "I clearly hit them and they did not die".
So code bakes it. If you change `ATTACK_ARC`, change `ARC_DEGREES` here too and rerun.

## Spec

- Bake only the picture facing right (+x). The game rotates facing.
  Drawing all four facings means four places to fix.
- The four frames **spread and fade.** A cut from inside out.
- Color is moonlight. White with a hint of blue.

No dependencies. It must run on a machine without PIL.
"""
import math
import struct
import zlib
from pathlib import Path

CELL = 32
FRAMES = 4
ARC_DEGREES = 110.0                # must match player.gd ATTACK_ARC
CENTER = CELL / 2.0

# Per frame (inner radius, outer radius, brightness)
# Start inside and spread outward while fading.
STAGES = [
    (5.0, 10.0, 1.00),
    (7.5, 13.5, 0.92),
    (10.0, 15.5, 0.55),
    (12.0, 16.0, 0.22),
]

MOON = (222, 240, 255)             # moonlight. white with a hint of blue


def _alpha_at(x: int, y: int, inner: float, outer: float, gain: float) -> int:
    """Alpha of one pixel. Nonzero inside the fan, 0 outside.

    A hard edge is a visible stair even in pixel art. Feather one pixel in both the radius
    and angle directions.
    """
    dx = x + 0.5 - CENTER
    dy = y + 0.5 - CENTER
    dist = math.hypot(dx, dy)
    if dist < 0.001:
        return 0

    mid = (inner + outer) * 0.5
    half = (outer - inner) * 0.5
    radial = 1.0 - abs(dist - mid) / half
    if radial <= 0.0:
        return 0

    # Right (+x) is 0 degrees. Opens half up and half down.
    angle = abs(math.degrees(math.atan2(dy, dx)))
    limit = ARC_DEGREES * 0.5
    if angle > limit:
        return 0
    angular = 1.0 - (angle / limit) ** 2   # densest at the center

    a = radial * angular * gain
    return max(0, min(255, int(a * 255.0)))


def _png(width: int, height: int, pixels: bytes) -> bytes:
    """Wrap RGBA bytes as PNG. Uses nothing but zlib."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)                       # no filter
        raw += pixels[y * stride:(y + 1) * stride]

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    return (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


def main() -> None:
    width = CELL * FRAMES
    buf = bytearray(width * CELL * 4)

    for index, (inner, outer, gain) in enumerate(STAGES):
        ox = index * CELL
        for y in range(CELL):
            for x in range(CELL):
                a = _alpha_at(x, y, inner, outer, gain)
                if a == 0:
                    continue
                p = (y * width + ox + x) * 4
                buf[p] = MOON[0]
                buf[p + 1] = MOON[1]
                buf[p + 2] = MOON[2]
                buf[p + 3] = a

    out = Path(__file__).resolve().parents[1] / "assets/derived/fx/moon_slash.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(_png(width, CELL, bytes(buf)))
    print(f"{out.relative_to(out.parents[3])} — {width}x{CELL}, {FRAMES} frames, "
          f"fan {ARC_DEGREES:.0f} deg")


if __name__ == "__main__":
    main()
