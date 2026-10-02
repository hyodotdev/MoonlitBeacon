#!/usr/bin/env python3
"""Build one seamless 96x96 ground tile per terrain.

Two of the original three floors were a single flat colour. ``floor.png`` is 352x417
and holds one **untextured** 80x16 strip that the camp repeated across a
1720x1000 play area, and the field cropped an equally flat 16x16 tile out of
its prop atlas. No tint fixes that — a uniform colour stretched over the whole
map reads as a void, which is exactly how the camp screen looked.

The forest is deliberately **not** here. ``forest_floor.png`` is already a real
256x256 tile with moss, grass blades and pebbles, so generating over it would
replace good art with less of it.

So generate real tiles. Each is low contrast on purpose: a dodge game needs the
spirits to be the highest-contrast thing on screen, so the ground carries
texture without competing. Style stays chunky and soft-edged to match the
chibi actors — speckle, not grit.

Every feature wraps across the tile edges, because ``Room``'s ``Ground`` sprite
uses ``texture_repeat``. A tile that does not wrap shows a grid of seams.

Stdlib only, like the other art tools.

The three later terrains (Frost Pass, Mirewood Marsh, Moonlit Ruins) have no
existing art to keep, so all three floors are generated here as well.

Output:

    assets/custom/world/terrain/ground_field.png
    assets/custom/world/terrain/ground_camp.png
    assets/custom/world/terrain/ground_frost.png
    assets/custom/world/terrain/ground_marsh.png
    assets/custom/world/terrain/ground_ruins.png
"""

from __future__ import annotations

import argparse
import hashlib
import math
import random
from pathlib import Path

from pixel_canvas import RGBA, Canvas

GAME_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = GAME_ROOT / "assets/custom/world/terrain"

## Two actor cells (2 x 48), so ground features share a beat with the sprites
## while the repeat stays far apart.
##
## 48 was tried first and the tile read as wallpaper: the play area is
## 1720x1000, so a 48px tile repeats about 36 x 21 times and the eye locks
## onto the blob pattern. At 96 the same features repeat a quarter as often.
SIZE = 96

## Fixed per terrain. The same tile must come out of every run, or the store
## capture fingerprint changes on a rebuild that drew identical pixels.
SEEDS = {
    "field": 0x42454143,
    "camp": 0x4F4E5321,
    "frost": 0x46524F53,
    "marsh": 0x4D415253,
    "ruins": 0x5255494E,
}


class WrapCanvas(Canvas):
    """Canvas whose writes wrap at the edges.

    ``disc``, ``ellipse``, ``line`` and ``polygon`` all draw through ``pixel``,
    so overriding this one method makes every shape tile seamlessly.
    """

    def pixel(self, x: int, y: int, color: RGBA) -> None:
        offset = ((y % self.height) * self.width + (x % self.width)) * 4
        self.pixels[offset : offset + 4] = bytes(color)


def _shade(base: RGBA, delta: int) -> RGBA:
    """Nudge luminance while keeping hue. Clamped to stay in gamut."""
    return (
        max(0, min(255, base[0] + delta)),
        max(0, min(255, base[1] + delta)),
        max(0, min(255, base[2] + delta)),
        base[3],
    )


def _speckle(canvas: WrapCanvas, rng: random.Random, base: RGBA,
             count: int, deltas: tuple[int, ...]) -> None:
    """Single-pixel grain. Breaks up flat fill without reading as noise."""
    for _ in range(count):
        canvas.pixel(
            rng.randrange(SIZE), rng.randrange(SIZE),
            _shade(base, rng.choice(deltas)))


def _patches(canvas: WrapCanvas, rng: random.Random, base: RGBA,
             count: int, radius: tuple[int, int], delta: int) -> None:
    """Soft blobs. Two passes so the edge is a shade weaker than the middle."""
    for _ in range(count):
        cx = rng.randrange(SIZE)
        cy = rng.randrange(SIZE)
        rx = rng.randint(*radius)
        ry = max(1, rx - rng.randint(0, 1))
        canvas.ellipse(cx, cy, rx, ry, _shade(base, delta // 2))
        if rx > 1:
            canvas.ellipse(cx, cy, rx - 1, max(1, ry - 1), _shade(base, delta))


def _blades(canvas: WrapCanvas, rng: random.Random, color: RGBA,
            count: int, height: tuple[int, int]) -> None:
    """Upright two-pixel tufts. Cheaper and cuter than a drawn grass sprite."""
    for _ in range(count):
        x = rng.randrange(SIZE)
        y = rng.randrange(SIZE)
        tall = rng.randint(*height)
        lean = rng.choice((-1, 0, 0, 1))
        for step in range(tall):
            canvas.pixel(x + (lean if step == tall - 1 else 0), y - step, color)


def build_field() -> Canvas:
    """Moonlit grass. Coolest tile, so the field reads as open and exposed."""
    base: RGBA = (40, 56, 63, 255)
    rng = random.Random(SEEDS["field"])
    canvas = WrapCanvas(SIZE, SIZE, base)
    _patches(canvas, rng, base, 46, (4, 12), 6)
    _blades(canvas, rng, (48, 72, 74, 255), 152, (3, 5))
    _blades(canvas, rng, (40, 60, 64, 255), 120, (2, 3))
    # Sparse pale buds. Three per tile — enough to notice, too few to pattern.
    # Kept dim: at full moonlight white they blew the floor's contrast budget
    # and started competing with the spirits for the eye.
    for _ in range(12):
        canvas.pixel(rng.randrange(SIZE), rng.randrange(SIZE),
                     (78, 92, 88, 255))
    _speckle(canvas, rng, base, 480, (-5, -2, 4, 6))
    return canvas


def build_camp() -> Canvas:
    """Trodden camp dirt. Warm-leaning but never brown-dominant at night.

    This is the tile that replaces the flat strip. It keeps a warm hue so the
    camp still reads as somewhere else, and gets its variety from scuffs and
    stones rather than from the room tint.
    """
    base: RGBA = (56, 53, 58, 255)
    rng = random.Random(SEEDS["camp"])
    canvas = WrapCanvas(SIZE, SIZE, base)
    _patches(canvas, rng, base, 62, (3, 12), 8)
    _patches(canvas, rng, base, 48, (2, 8), -7)
    # Cart scuffs. Shallow horizontal streaks, the trace of a camp being used.
    for _ in range(20):
        y = rng.randrange(SIZE)
        x = rng.randrange(SIZE)
        run = rng.randint(9, 26)
        tone = _shade(base, rng.choice((-7, 8)))
        for step in range(run):
            canvas.pixel(x + step, y + (1 if step > run // 2 else 0), tone)
    for _ in range(40):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        canvas.ellipse(cx, cy, 2, 1, (70, 68, 74, 255))
        canvas.pixel(cx, cy - 1, (90, 88, 96, 255))
    _speckle(canvas, rng, base, 680, (-7, -3, 5, 8))
    return canvas


def build_frost() -> Canvas:
    """Windblown snow. The brightest floor, kept a shade under the actors.

    Every streak leans the same way, so the whole pass looks like it is blowing one direction
    instead of being sprinkled with dashes.
    """
    base: RGBA = (66, 78, 100, 255)
    rng = random.Random(SEEDS["frost"])
    canvas = WrapCanvas(SIZE, SIZE, base)
    _patches(canvas, rng, base, 44, (5, 13), 5)
    _patches(canvas, rng, base, 38, (3, 9), -6)
    for _ in range(26):
        x, y = rng.randrange(SIZE), rng.randrange(SIZE)
        run = rng.randint(10, 28)
        tone = _shade(base, rng.choice((6, 8, -5)))
        for step in range(run):
            canvas.pixel(x + step, y + step // 9, tone)
    # Snow-capped pebbles: a dark stone with one pale pixel on top.
    for _ in range(16):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        canvas.ellipse(cx, cy, 2, 1, (52, 62, 84, 255))
        canvas.pixel(cx, cy - 1, (92, 108, 138, 255))
    # Ice glints: a pale pixel with a faint cross. Six a tile is enough to sparkle, too few to pattern.
    for _ in range(6):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        canvas.pixel(cx, cy, (104, 122, 152, 255))
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            canvas.pixel(cx + dx, cy + dy, (80, 96, 124, 255))
    _speckle(canvas, rng, base, 520, (-5, -3, 4, 6))
    return canvas


def build_marsh() -> Canvas:
    """Bog water and moss. Dark and slow, with green in the shadows so it never reads as mud."""
    base: RGBA = (34, 54, 58, 255)
    moss: RGBA = (40, 63, 56, 255)
    rng = random.Random(SEEDS["marsh"])
    canvas = WrapCanvas(SIZE, SIZE, base)
    _patches(canvas, rng, base, 56, (4, 12), -7)
    _patches(canvas, rng, moss, 34, (3, 10), 4)
    _blades(canvas, rng, (42, 72, 58, 255), 84, (3, 5))
    _blades(canvas, rng, (30, 50, 50, 255), 70, (2, 4))
    # Lily pads: a small green oval with a notch cut out of it and a pale rim on the near side.
    for _ in range(14):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        canvas.ellipse(cx, cy, 3, 2, (46, 80, 58, 255))
        canvas.pixel(cx + 3, cy, base)
        canvas.pixel(cx + 2, cy - 1, (58, 92, 64, 255))
    # Ripples: a broken pale ring. The gaps are what make it read as water and not a drawn circle.
    for _ in range(10):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        for step in range(14):
            if step % 5 == 4:
                continue
            angle = step * math.tau / 14.0
            canvas.pixel(
                cx + round(4.0 * math.cos(angle)), cy + round(2.0 * math.sin(angle)),
                (68, 98, 100, 255))
    for _ in range(8):
        canvas.pixel(rng.randrange(SIZE), rng.randrange(SIZE), (76, 108, 102, 255))
    _speckle(canvas, rng, base, 560, (-6, -3, 4, 6))
    return canvas


def _tone_slab(canvas: WrapCanvas, x0: int, y0: int, width: int, height: int,
               delta: int) -> None:
    """Shift a rectangle's luminance in place, wrapping across the tile edge."""
    for y in range(y0, y0 + height):
        for x in range(x0, x0 + width):
            wrapped_x, wrapped_y = x % SIZE, y % SIZE
            canvas.pixel(x, y, _shade(canvas.get(wrapped_x, wrapped_y), delta))


def build_ruins() -> Canvas:
    """Weathered flagstones in running bond, cracked, with moss in the corners.

    The joints are the pattern, so the slabs themselves stay quiet. Rows are staggered by
    half a slab, which also keeps the seams from lining up into a grid across repeats.
    """
    base: RGBA = (54, 52, 68, 255)
    joint: RGBA = (34, 32, 46, 255)
    rng = random.Random(SEEDS["ruins"])
    canvas = WrapCanvas(SIZE, SIZE, base)
    _patches(canvas, rng, base, 30, (4, 11), 3)
    _patches(canvas, rng, base, 26, (3, 8), -4)
    slab_width, slab_height = 32, 32
    for row in range(3):
        y0 = row * slab_height
        shift = 0 if row % 2 == 0 else slab_width // 2
        for column in range(3):
            x0 = column * slab_width + shift
            _tone_slab(canvas, x0, y0, slab_width, slab_height,
                       rng.choice((-5, -3, 0, 3, 5)))
            for x in range(x0, x0 + slab_width):
                canvas.pixel(x, y0, joint)
                canvas.pixel(x, y0 + 1, (66, 64, 84, 255))
            for y in range(y0, y0 + slab_height):
                canvas.pixel(x0, y, joint)
                canvas.pixel(x0 + 1, y, (62, 60, 78, 255))
            # A crack: a short random walk that starts at a joint and wanders inward.
            if rng.random() < 0.7:
                cx, cy = x0 + rng.choice((2, slab_width - 3)), y0 + 2
                for _ in range(rng.randint(6, 12)):
                    canvas.pixel(cx, cy, (40, 38, 52, 255))
                    cy += 1
                    cx += rng.choice((-1, 0, 0, 1))
            # Moss where the joints meet.
            for _ in range(rng.randint(0, 2)):
                mx, my = x0 + rng.randint(1, 5), y0 + rng.randint(1, 5)
                for offset in range(rng.randint(2, 4)):
                    canvas.pixel(mx + offset, my, (52, 74, 64, 255))
                    canvas.pixel(mx, my + offset, (46, 66, 58, 255))
    for _ in range(30):
        cx, cy = rng.randrange(SIZE), rng.randrange(SIZE)
        canvas.pixel(cx, cy, (74, 72, 92, 255))
    _speckle(canvas, rng, base, 420, (-5, -3, 3, 5))
    return canvas


BUILDERS = {
    "field": build_field,
    "camp": build_camp,
    "frost": build_frost,
    "marsh": build_marsh,
    "ruins": build_ruins,
}


def _validate(name: str, canvas: Canvas) -> None:
    """Guard the two properties that make a tile usable.

    Fully opaque, because a hole in a repeating floor shows the clear colour.
    And bounded contrast, so the ground cannot out-shout the actors standing on
    it — the readability floor in the 3.0.0 asset contract.
    """
    luminance: list[float] = []
    for index in range(0, len(canvas.pixels), 4):
        red, green, blue, alpha = canvas.pixels[index : index + 4]
        if alpha != 255:
            raise SystemExit(f"{name}: ground tile must be fully opaque")
        luminance.append(0.2126 * red + 0.7152 * green + 0.0722 * blue)
    spread = max(luminance) - min(luminance)
    if spread > 74.0:
        raise SystemExit(
            f"{name}: ground contrast spread {spread:.1f} is too loud "
            "for a floor (max 74)")
    if spread < 12.0:
        raise SystemExit(
            f"{name}: ground contrast spread {spread:.1f} is flat — "
            "that is the bug this tool exists to fix (min 12)")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check", action="store_true",
        help="fail if the tiles on disk differ from what this tool generates")
    args = parser.parse_args()

    problems: list[str] = []
    for name, builder in BUILDERS.items():
        canvas = builder()
        _validate(name, canvas)
        payload = canvas.to_png()
        digest = hashlib.sha256(payload).hexdigest()[:16]
        target = OUTPUT_DIR / f"ground_{name}.png"
        if args.check:
            if not target.exists():
                problems.append(f"missing {target.name}")
            elif target.read_bytes() != payload:
                problems.append(f"out of date {target.name}")
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        print(f"wrote {target.relative_to(GAME_ROOT)}  sha256:{digest}")
    if args.check:
        if problems:
            raise SystemExit(
                "ground tiles are not what build_ground_tiles.py generates:\n  "
                + "\n  ".join(problems)
                + "\nRun: node scripts/python.mjs -B apps/game/tools/build_ground_tiles.py")
        print("check: production ground tiles are deterministic")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
