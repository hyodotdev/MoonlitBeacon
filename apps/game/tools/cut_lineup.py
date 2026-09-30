#!/usr/bin/env python3
"""Cut a magenta-background lineup into one keyed source per creature.

The packers (`pack_grok_spirits.py`, `pack_ludo_guardians.py`, `pack_maple_heroes.py`) want
one image per creature or per pose, with a transparent background. An image generator is
much better at drawing several creatures that share one style in a single picture than at
drawing them separately, so a whole set is generated as one picture on flat magenta and cut
apart here.

    python3 tools/cut_lineup.py lineup.png tools/spirit_grok wisp drifter ember caster weaver stalker swarm
    python3 tools/cut_lineup.py --rows 2 --gap 1 grid.png tools/guardian_ludo forest field camp forest_thorn field_storm camp_siege
    python3 tools/cut_lineup.py --rows 6 --frames 4 walk.png out warden_0 warden_1 warden_2 warden_3 dancer_0 ...

The names are given left to right, and with `--rows N` top to bottom, row by row. With
`--frames N`, every N consecutive creatures are the frames of one animation: they are cut to
one shared canvas size, feet on the same baseline and each centred, so a walk cycle keeps
its stride and does not jitter from one frame to the next. Each
creature needs clear magenta between it and its neighbours (at least five columns, and five
rows between grid rows), and there must be exactly as many creatures as names: a different
count stops the run instead of guessing which one is which.

Pillow only, no numpy, so it runs on the Python that Xcode ships. Output is RGBA with
hard alpha, the colour of the rim's neighbours copied under the transparent pixels so a
later resize never bleeds black into an edge.
"""

from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image

# Closer than this (sum of channel differences) to the background is background.
KEY = 70
# Ignore this many pixels at the picture's edge: a screenshot has rounded corners.
MARGIN = 14
# Columns of clear background that separate two creatures. `--gap N` overrides it: a
# grid whose creatures nearly touch needs a smaller one, a creature with loose parts a bigger.
GAP = 5
PAD = 6


def _background(pix: object, width: int, height: int) -> tuple[int, int, int]:
    """Median colour of a patch in each corner, away from the edge."""
    patch = []
    for cx, cy in ((24, 24), (width - 25, 24), (24, height - 25), (width - 25, height - 25)):
        for dy in range(-4, 5):
            for dx in range(-4, 5):
                patch.append(pix[cx + dx, cy + dy])  # type: ignore[index]
    return tuple(sorted(c[i] for c in patch)[len(patch) // 2] for i in range(3))  # type: ignore[return-value]


def _magentaish(p: tuple[int, int, int]) -> bool:
    r, g, b = p
    return r > 110 and b > 110 and (r - g) > 55 and (b - g) > 55


def _runs(flags: list[bool], gap: int) -> list[tuple[int, int]]:
    """Runs of True separated by more than `gap` False values."""
    runs: list[tuple[int, int]] = []
    start = last = None
    for index, on in enumerate(flags):
        if not on:
            continue
        if start is None:
            start = index
        elif index - last > gap:
            runs.append((start, last))
            start = index
        last = index
    if start is not None:
        runs.append((start, last))
    return runs


def cut(
    source: Path, out_dir: Path, names: list[str], rows: int = 1, gap: int = GAP, frames: int = 1,
) -> None:
    image = Image.open(source).convert("RGB")
    width, height = image.size
    pix = image.load()
    bg = _background(pix, width, height)

    def dist(p: tuple[int, int, int]) -> int:
        return abs(p[0] - bg[0]) + abs(p[1] - bg[1]) + abs(p[2] - bg[2])

    # Bands of rows (one for a plain lineup), then the creatures inside each band.
    row_on = [False] * height
    for y in range(MARGIN, height - MARGIN):
        for x in range(MARGIN, width - MARGIN):
            if dist(pix[x, y]) > KEY:
                row_on[y] = True
                break
    bands = _runs(row_on, gap)
    if len(bands) != rows:
        raise SystemExit(f"expected {rows} rows, found {len(bands)}: {bands}")

    boxes: list[tuple[int, int, int, int]] = []
    for band_top, band_bottom in bands:
        column_on = [False] * width
        for x in range(MARGIN, width - MARGIN):
            for y in range(band_top, band_bottom + 1):
                if dist(pix[x, y]) > KEY:
                    column_on[x] = True
                    break
        for x0, x1 in _runs(column_on, gap):
            ys = [
                y for y in range(band_top, band_bottom + 1)
                if any(dist(pix[x, y]) > KEY for x in range(x0, x1 + 1))
            ]
            boxes.append((x0, min(ys), x1, max(ys)))
    if len(boxes) != len(names):
        raise SystemExit(f"expected {len(names)} creatures, found {len(boxes)}: {boxes}")

    out_dir.mkdir(parents=True, exist_ok=True)
    cut_images: list[tuple[str, Image.Image]] = []
    for name, (x0, y0, x1, y1) in zip(names, boxes):
        box = (
            max(0, x0 - PAD), max(0, y0 - PAD),
            min(width, x1 + PAD + 1), min(height, y1 + PAD + 1),
        )
        crop = image.crop(box)
        w, h = crop.size
        src = crop.load()
        rgba = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        dst = rgba.load()
        # Only the creature's own box is opaque. The pad around it is margin: a neighbour
        # that reaches into it (the boots of the row above, say) must not leak into this cut.
        for y in range(h):
            for x in range(w):
                if not (x0 <= box[0] + x <= x1 and y0 <= box[1] + y <= y1):
                    continue
                p = src[x, y]
                if dist(p) > KEY:
                    dst[x, y] = (p[0], p[1], p[2], 255)

        def neighbours(x: int, y: int) -> list[tuple[int, int]]:
            return [
                (x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1)
                if 0 <= x + dx < w and 0 <= y + dy < h
            ]

        # Drop the pink blend pixels that scaling left on the rim.
        for _ in range(2):
            drop = [
                (x, y) for y in range(h) for x in range(w)
                if dst[x, y][3] and _magentaish(dst[x, y][:3])
                and any(dst[nx, ny][3] == 0 for nx, ny in neighbours(x, y))
            ]
            for x, y in drop:
                dst[x, y] = (0, 0, 0, 0)

        # Transparent pixels take the colour of an opaque neighbour.
        for _ in range(3):
            fill = []
            for y in range(h):
                for x in range(w):
                    if dst[x, y][3] or dst[x, y][:3] != (0, 0, 0):
                        continue
                    for nx, ny in neighbours(x, y):
                        if dst[nx, ny][3] == 255:
                            fill.append((x, y, dst[nx, ny][:3]))
                            break
            for x, y, rgb in fill:
                dst[x, y] = (*rgb, 0)

        rgba = rgba.crop(rgba.getchannel("A").getbbox())
        cut_images.append((name, rgba))

    if frames > 1 and len(cut_images) % frames != 0:
        raise SystemExit(f"{len(cut_images)} creatures do not split into groups of {frames} frames")
    for start in range(0, len(cut_images), max(frames, 1)):
        group = cut_images[start:start + max(frames, 1)]
        if frames > 1:
            canvas_w = max(image.width for _name, image in group)
            canvas_h = max(image.height for _name, image in group)
            aligned = []
            for name, image in group:
                canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
                canvas.alpha_composite(image, ((canvas_w - image.width) // 2, canvas_h - image.height))
                aligned.append((name, canvas))
            group = aligned
        for name, image in group:
            image.save(out_dir / f"{name}.png")
            print(f"{name}: {image.width}x{image.height}")


def main() -> int:
    args = sys.argv[1:]
    rows = 1
    gap = GAP
    frames = 1
    while len(args) >= 2 and args[0] in ("--rows", "--gap", "--frames"):
        if args[0] == "--rows":
            rows = int(args[1])
        elif args[0] == "--gap":
            gap = int(args[1])
        else:
            frames = int(args[1])
        args = args[2:]
    if len(args) < 3:
        print(__doc__)
        return 2
    cut(Path(args[0]), Path(args[1]), args[2:], rows, gap, frames)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
