#!/usr/bin/env python3
"""Fit the nine skill emblems to 48x48 relic-card icons.

Sources are `tools/skill_icons/<id>.png`, transparent PNGs that `tools/cut_lineup.py` cut out of one
ChatGPT grid (see `skill_icons/README.md`). The card wants a 48x48 emblem with a soft edge, like the
sixteen before it, so each source is scaled to fit a 44x44 box, centred, and resampled with a filter
that keeps the outline smooth. Alpha stays graded (the contract allows 256 levels).

    python3 apps/game/tools/build_skill_icons.py          # write
    python3 apps/game/tools/build_skill_icons.py --check  # is what is on disk what this would write
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

TOOL_DIR = Path(__file__).resolve().parent
SOURCE_ROOT = TOOL_DIR / "skill_icons"
OUT_ROOT = TOOL_DIR.parent / "assets/custom/ui/icons"

NAMES = (
    "lantern_familiar",
    "moon_ward",
    "comet_call",
    "star_magnet",
    "thorn_bloom",
    "second_light",
    "moon_burst",
    "winter_bell",
    "comet_trail",
)
SIZE = 48
## Empty border, so a glow or a spark never touches the card frame.
BOX = 44


def build(name: str) -> Image.Image:
    source = Image.open(SOURCE_ROOT / f"{name}.png").convert("RGBA")
    box = source.getchannel("A").getbbox()
    if box is None:
        raise SystemExit(f"{name}: the source is empty")
    crop = source.crop(box)
    scale = BOX / max(crop.width, crop.height)
    size = (max(1, round(crop.width * scale)), max(1, round(crop.height * scale)))
    # Half-way down first, then the last step: a single big reduction aliases fine sparks.
    if crop.width > size[0] * 2:
        crop = crop.resize((size[0] * 2, size[1] * 2), Image.Resampling.BOX)
    small = crop.resize(size, Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    canvas.alpha_composite(small, ((SIZE - size[0]) // 2, (SIZE - size[1]) // 2))
    return canvas


def png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    stale = []
    for name in NAMES:
        image = build(name)
        dest = OUT_ROOT / f"{name}.png"
        if args.check:
            if not dest.is_file() or Image.open(dest).convert("RGBA").tobytes() != image.tobytes():
                stale.append(name)
            continue
        dest.write_bytes(png_bytes(image))
    if args.check:
        if stale:
            print("skill icons out of date:", ", ".join(stale))
            return 1
        print("skill icons current")
        return 0
    print(f"wrote {len(NAMES)} skill icons")
    return 0


if __name__ == "__main__":
    sys.exit(main())
