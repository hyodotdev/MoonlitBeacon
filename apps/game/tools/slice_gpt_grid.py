#!/usr/bin/env python3
"""Slice a ChatGPT grid drop into a horizontal game strip.

Drops come as R x C grids (idle 2x3, states 2x2). Each cell is cropped
to its alpha bbox, fitted into a square game cell, and concatenated
left-to-right, top-to-bottom. Stdlib only, like the other art tools.

Usage:
    python3 slice_gpt_grid.py <drop.png> --rows 2 --cols 3 --cell 64 \\
        --out builds/slice/forest.png
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixel_canvas import Canvas

ALPHA_CUTOFF = 8
FRAME_FILL = 60  # bbox longest side in px inside the game cell


def read_png(path: Path) -> tuple[int, int, bytes]:
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, raw, width, height, channels = 8, b"", 0, 0, 0
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos : pos + 4])
        kind = data[pos + 4 : pos + 8]
        chunk = data[pos + 8 : pos + 8 + length]
        if kind == b"IHDR":
            width, height, _bd, ctype, _, _, _ = struct.unpack(">IIBBBBB", chunk)
            channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
        elif kind == b"IDAT":
            raw += chunk
        pos += 12 + length
    assert channels in (3, 4), f"unsupported channels: {channels}"
    px = zlib.decompress(raw)
    stride = width * channels
    out = bytearray(width * height * channels)
    prev = bytearray(stride)
    for y in range(height):
        line = px[y * (stride + 1) : (y + 1) * (stride + 1)]
        ftype = line[0]
        cur = bytearray(stride)
        for i in range(stride):
            a = cur[i - channels] if i >= channels else 0
            b = prev[i]
            c = prev[i - channels] if i >= channels else 0
            if ftype == 0:
                v = line[i + 1]
            elif ftype == 1:
                v = (line[i + 1] + a) & 255
            elif ftype == 2:
                v = (line[i + 1] + b) & 255
            elif ftype == 3:
                v = (line[i + 1] + (a + b) // 2) & 255
            else:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                v = (line[i + 1] + pr) & 255
            cur[i] = v
        out[y * stride : (y + 1) * stride] = cur
        prev = cur
    if channels == 3:
        rgba = bytearray(width * height * 4)
        for i in range(width * height):
            rgba[i * 4 : i * 4 + 3] = out[i * 3 : i * 3 + 3]
            rgba[i * 4 + 3] = 255
        return width, height, bytes(rgba)
    return width, height, bytes(out)


def alpha_of(buf: bytes, width: int, x: int, y: int) -> int:
    return buf[(y * width + x) * 4 + 3]


def cell_bbox(
    buf: bytes, width: int, x0: int, y0: int, cw: int, ch: int
) -> tuple[int, int, int, int] | None:
    min_x, min_y, max_x, max_y = cw, ch, -1, -1
    for y in range(ch):
        for x in range(cw):
            if alpha_of(buf, width, x0 + x, y0 + y) > ALPHA_CUTOFF:
                if x < min_x:
                    min_x = x
                if x > max_x:
                    max_x = x
                if y < min_y:
                    min_y = y
                if y > max_y:
                    max_y = y
    if max_x < 0:
        return None
    return (x0 + min_x, y0 + min_y, max_x - min_x + 1, max_y - min_y + 1)


def fit_cell(
    buf: bytes,
    width: int,
    bbox: tuple[int, int, int, int],
    cell: int,
) -> Canvas:
    bx, by, bw, bh = bbox
    longest = max(bw, bh)
    scale = FRAME_FILL / longest
    dw, dh = max(1, round(bw * scale)), max(1, round(bh * scale))
    ox, oy = (cell - dw) // 2, (cell - dh) // 2
    canvas = Canvas(cell, cell)
    for dy in range(dh):
        sy0 = int(dy / scale)
        sy1 = min(bh, int((dy + 1) / scale))
        for dx in range(dw):
            sx0 = int(dx / scale)
            sx1 = min(bw, int((dx + 1) / scale))
            r = g = b = a = n = 0
            for sy in range(sy0, max(sy1, sy0 + 1)):
                for sx in range(sx0, max(sx1, sx0 + 1)):
                    o = ((by + sy) * width + (bx + sx)) * 4
                    # Premultiply so transparent fringes do not halo.
                    pa = buf[o + 3]
                    r += buf[o] * pa
                    g += buf[o + 1] * pa
                    b += buf[o + 2] * pa
                    a += pa
                    n += 1
            if a > 0:
                canvas.pixel(
                    ox + dx, oy + dy,
                    (r // a, g // a, b // a, a // n),
                )
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("drop", type=Path)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--cell", type=int, default=64)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    width, height, buf = read_png(args.drop)
    cw, ch = width // args.cols, height // args.rows
    print(f"drop {width}x{height}, grid {args.rows}x{args.cols}, cell {cw}x{ch}")
    frames: list[Canvas] = []
    sizes: list[int] = []
    failed = False
    for index in range(args.rows * args.cols):
        r, c = divmod(index, args.cols)
        x0, y0 = c * cw, r * ch
        bbox = cell_bbox(buf, width, x0, y0, cw, ch)
        if bbox is None:
            print(f"  frame {index}: EMPTY — reject this drop")
            failed = True
            continue
        _, _, bw, bh = bbox
        touches = (
            bbox[0] == x0 or bbox[1] == y0
            or bbox[0] + bw == x0 + cw or bbox[1] + bh == y0 + ch
        )
        if touches:
            print(f"  frame {index}: WARN touches cell edge (bleed?)")
        sizes.append(max(bw, bh))
        frames.append(fit_cell(buf, width, bbox, args.cell))
    if failed:
        return 1
    median = sorted(sizes)[len(sizes) // 2]
    for i, s in enumerate(sizes):
        if abs(s - median) > median * 0.3:
            print(f"  frame {i}: WARN size {s} vs median {median}")
    strip = Canvas(args.cell * len(frames), args.cell)
    for i, frame in enumerate(frames):
        strip.blit(frame, i * args.cell, 0)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(args.out)
    print(f"wrote {args.out} ({strip.width}x{strip.height})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
