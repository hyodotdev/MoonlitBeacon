#!/usr/bin/env python3
"""Slice a ChatGPT grid drop into aligned full-cell files.

Unlike slice_gpt_grid (bbox crop per frame), every cell is box-scaled
whole to the target size, so multi-state UI art stays pixel-aligned
across states. Stdlib only, like the other art tools.

Usage:
    python3 slice_gpt_cells.py <drop.png> --rows 2 --cols 2 \\
        --size 168x112 --prefix builds/cells/card --names normal,hover,pressed,disabled
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from pixel_canvas import Canvas
from slice_gpt_grid import cell_bbox, fit_cell, read_png


def scale_cell(
    buf: bytes,
    width: int,
    x0: int,
    y0: int,
    cw: int,
    ch: int,
    dw: int,
    dh: int,
) -> Canvas:
    canvas = Canvas(dw, dh)
    for dy in range(dh):
        sy0 = dy * ch // dh
        sy1 = max(sy0 + 1, (dy + 1) * ch // dh)
        for dx in range(dw):
            sx0 = dx * cw // dw
            sx1 = max(sx0 + 1, (dx + 1) * cw // dw)
            r = g = b = a = n = 0
            for sy in range(sy0, sy1):
                for sx in range(sx0, sx1):
                    o = ((y0 + sy) * width + (x0 + sx)) * 4
                    pa = buf[o + 3]
                    r += buf[o] * pa
                    g += buf[o + 1] * pa
                    b += buf[o + 2] * pa
                    a += pa
                    n += 1
            if a > 0:
                canvas.pixel(dx, dy, (r // a, g // a, b // a, a // n))
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("drop", type=Path)
    parser.add_argument("--rows", type=int, required=True)
    parser.add_argument("--cols", type=int, required=True)
    parser.add_argument("--size", required=True, help="WxH, e.g. 168x112")
    parser.add_argument("--prefix", type=Path, required=True)
    parser.add_argument("--names", default="",
                        help="comma list, one per cell, row-major")
    parser.add_argument("--fit", type=int, default=0,
                        help="bbox-crop and fit longest side to FILL px "
                             "(0 = scale whole cell)")
    args = parser.parse_args()

    dw, dh = (int(v) for v in args.size.lower().split("x"))
    names = [n for n in args.names.split(",") if n] or None
    total = args.rows * args.cols
    if names is not None and len(names) != total:
        print(f"need {total} names, got {len(names)}")
        return 1

    width, height, buf = read_png(args.drop)
    cw, ch = width // args.cols, height // args.rows
    print(f"drop {width}x{height}, grid {args.rows}x{args.cols}, cell {cw}x{ch}")
    args.prefix.parent.mkdir(parents=True, exist_ok=True)
    failed = False
    for index in range(total):
        r, c = divmod(index, args.cols)
        x0, y0 = c * cw, r * ch
        if args.fit > 0:
            if dw != dh:
                print("fit mode needs a square --size")
                return 1
            bbox = cell_bbox(buf, width, x0, y0, cw, ch)
            if bbox is None:
                print(f"  cell {index}: EMPTY — reject this drop")
                failed = True
                continue
            cell = fit_cell(buf, width, bbox, dw, args.fit)
        else:
            cell = scale_cell(buf, width, x0, y0, cw, ch, dw, dh)
        tag = names[index] if names else f"{index}"
        out = args.prefix.parent / f"{args.prefix.name}_{tag}.png"
        cell.save(out)
        print(f"wrote {out} ({dw}x{dh})")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
