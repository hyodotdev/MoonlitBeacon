#!/usr/bin/env python3
"""Pack the gate-lodge room plates and Lumi turnaround into runtime PNGs.

Reads the approved raw sources under notes/workflow/muse/art/gate-chamber/
(read-only; that tree is director-owned) and writes deterministic RGBA
runtime PNGs under assets/custom/. Every facing keeps its source
proportions: one common top/bottom crop line, one runtime scale, and a
shared foot anchor, instead of independently filling each bounding box.

Re-running on the same sources produces byte-identical outputs; --check
verifies that without writing.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image

from pixel_canvas import Canvas

TOOL_DIR = Path(__file__).resolve().parent
GAME_ROOT = TOOL_DIR.parent
REPO_ROOT = GAME_ROOT.parents[1]
SOURCE_ROOT = REPO_ROOT / "notes/workflow/muse/art/gate-chamber"
ROOM_ROOT = GAME_ROOT / "assets/custom/world/lodge"
LUMI_ROOT = GAME_ROOT / "assets/custom/actors/lumi"

# Measured Lumi figure boxes (x0, x1, top, bottom, inclusive) on the raw
# 1774x887 turnaround at alpha threshold 128, matching the director's
# alpha probe (visible heights 853/850/851/852, bottoms 867/866/866/867).
# Order on the sheet: front, rear, left, right.
LUMI_FIGURES = {
    "front": (67, 385, 14, 866),
    "rear": (514, 833, 16, 865),
    "left": (968, 1213, 15, 865),
    "right": (1418, 1648, 15, 866),
}
LUMI_ORDER = ("front", "rear", "left", "right")

# Transparent margin kept around each silhouette for filtering. The crop
# top/bottom are common to all facings so every packed frame shares one
# height and one foot line; widths stay per-facing so profiles are not
# stretched to the front silhouette.
CROP_PAD = 8
CROP_TOP = min(box[2] for box in LUMI_FIGURES.values()) - CROP_PAD
CROP_BOTTOM_EXCL = max(box[3] for box in LUMI_FIGURES.values()) + 1 + CROP_PAD

# Bust crop on the front column: head plus shoulders for the small name
# form portrait. Centered on the front figure's horizontal middle.
BUST_HALF_WIDTH = 130
BUST_HEIGHT = 320


def _canvas_from_rgba(image: Image.Image) -> Canvas:
    rgba = image.convert("RGBA")
    canvas = Canvas(rgba.width, rgba.height)
    canvas.pixels[:] = rgba.tobytes()
    return canvas


def _lumi_crop_box(name: str) -> tuple[int, int, int, int]:
    x0, x1, _top, _bottom = LUMI_FIGURES[name]
    return (x0 - CROP_PAD, CROP_TOP, x1 + 1 + CROP_PAD, CROP_BOTTOM_EXCL)


def _bust_crop_box() -> tuple[int, int, int, int]:
    x0, x1, _top, _bottom = LUMI_FIGURES["front"]
    center = (x0 + x1) // 2
    return (
        center - BUST_HALF_WIDTH,
        CROP_TOP,
        center + BUST_HALF_WIDTH,
        CROP_TOP + BUST_HEIGHT,
    )


def build_outputs() -> dict[Path, bytes]:
    """Pack every runtime PNG in memory. Pure: writes nothing."""
    missing = [
        name
        for name in (
            "gate-chamber-room.png",
            "gate-chamber-room-tablet.png",
            "lumi-turnaround.png",
        )
        if not (SOURCE_ROOT / name).exists()
    ]
    if missing:
        raise SystemExit(
            "lodge art sources missing under %s: %s"
            % (SOURCE_ROOT, ", ".join(missing))
        )
    outputs: dict[Path, bytes] = {}
    wide = Image.open(SOURCE_ROOT / "gate-chamber-room.png")
    outputs[ROOM_ROOT / "room_wide.png"] = _canvas_from_rgba(wide).to_png()
    tablet = Image.open(SOURCE_ROOT / "gate-chamber-room-tablet.png")
    outputs[ROOM_ROOT / "room_tablet.png"] = _canvas_from_rgba(tablet).to_png()
    sheet = Image.open(SOURCE_ROOT / "lumi-turnaround.png")
    for name in LUMI_ORDER:
        facing = sheet.crop(_lumi_crop_box(name))
        outputs[LUMI_ROOT / ("%s.png" % name)] = _canvas_from_rgba(
            facing
        ).to_png()
    bust = sheet.crop(_bust_crop_box())
    outputs[LUMI_ROOT / "bust.png"] = _canvas_from_rgba(bust).to_png()
    return outputs


def measure_sheet() -> dict[str, tuple[int, int]]:
    """Visible figure height and bottom row per facing at alpha >= 128."""
    sheet = Image.open(SOURCE_ROOT / "lumi-turnaround.png").convert("RGBA")
    width, height = sheet.size
    alpha = sheet.split()[3]
    loader = alpha.load()
    measured: dict[str, tuple[int, int]] = {}
    for name in LUMI_ORDER:
        x0, x1, _top, _bottom = LUMI_FIGURES[name]
        top, bottom = height, -1
        for y in range(height):
            found = 0
            for x in range(x0 - CROP_PAD, x1 + 1 + CROP_PAD):
                if 0 <= x < width and loader[x, y] >= 128:
                    found += 1
                    if found > 3:
                        break
            if found > 3:
                top = min(top, y)
                bottom = max(bottom, y)
        measured[name] = (bottom - top + 1, bottom)
    return measured


def pack_all(*, check: bool) -> None:
    outputs = build_outputs()
    measured = measure_sheet()
    heights = [size for size, _bottom in measured.values()]
    spread = (max(heights) - min(heights)) / float(min(heights))
    if spread >= 0.02:
        raise SystemExit(
            "lumi facing heights disagree: %s (spread %.3f)"
            % (measured, spread)
        )
    problems: list[str] = []
    for path, payload in outputs.items():
        if check:
            if not path.exists():
                problems.append("%s: missing" % path)
            elif path.read_bytes() != payload:
                problems.append("%s: bytes differ" % path)
        else:
            if path.exists() and path.read_bytes() == payload:
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(payload)
    for name in LUMI_ORDER:
        size, bottom = measured[name]
        print(
            "lumi %s: visible height %d bottom %d" % (name, size, bottom)
        )
    print(
        "lodge pack: %d outputs height-spread %.4f"
        % (len(outputs), spread)
    )
    if problems:
        raise SystemExit("\n".join(problems))
    print(
        "lodge assets %s" % ("check: outputs current" if check else "packed")
    )


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify packed outputs match the sources without writing",
    )
    args = parser.parse_args(argv)
    try:
        pack_all(check=args.check)
    except SystemExit as exit:
        message = str(exit)
        if message:
            print(message, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
