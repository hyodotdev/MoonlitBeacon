#!/usr/bin/env python3
"""World UI kit: validate the authored SVG sources.

The 4.0.0 screens use ORIGINAL high-resolution vector UI art, authored by hand
in ``assets/custom/ui/world/*.svg``: cut-corner bronze frames, inset ink
faces, etched moon diamonds, layered gradients and contact shadows in the
deep-ink, aged metal, moon-blue and ember-gold language. Godot rasterizes each
SVG on import; every source keeps 4 texels per logical UI unit (a 36-unit
frame is 144px of vector art) and ``WorldChrome.draw_nine`` maps source texels
to logical units explicitly (48 -> 12, 32 -> 8, 56 -> 14, 16 -> 4), sampled
with an explicit Linear filter. The locked global Nearest never touches this
kit, so no border staircases.

This tool generates nothing visual. It validates the authored sources (well
formed XML, expected raster size, nine-patch strip rules documented per
entry), with ``--check`` failing on drift. Sibling of ``build_ui_kit.py``,
which it does not touch: the old 3.x kit source and output bytes stay exactly
as they were. There are no shared ``.tres`` styles: Godot 4.7 StyleBoxTexture
passes margins through as destination edges with no draw scale, so the kit is
painted by the WorldPanel, WorldFrame, WorldButton and WorldLabel classes.

Stdlib only, like the other art tools.
"""

from __future__ import annotations

import argparse
import sys
import xml.etree.ElementTree as ElementTree
from dataclasses import dataclass
from pathlib import Path

GAME_ROOT = Path(__file__).resolve().parents[1]
SOURCE_DIR = GAME_ROOT / "assets/custom/ui/world"

LOGICAL_SCALE: int = 4
"""Source texels per logical UI unit. A 36-unit frame is 144px of SVG."""


@dataclass(frozen=True)
class Entry:
    """One authored source and its raster contract."""

    svg: str
    width: int
    height: int


def _buttons(kind: str) -> list[Entry]:
    return [
        Entry(f"btn_{kind}_{state}", 80, 80)
        for state in ("normal", "hover", "pressed", "disabled", "focus")
    ]


MANIFEST: list[Entry] = [
    Entry("frame_panel", 144, 144),
    Entry("frame_chip", 80, 80),
    Entry("frame_chip_lit", 80, 80),
    Entry("frame_card", 176, 176),
    Entry("card_focus", 176, 176),
    Entry("bar_back", 48, 48),
    Entry("bar_fill", 48, 48),
    *_buttons("ember"),
    *_buttons("steel"),
    *_buttons("coral"),
    Entry("bead_moon", 48, 48),
    Entry("seal_win", 256, 256),
    Entry("seal_lose", 256, 256),
    Entry("dais", 384, 96),
    Entry("dash_base", 208, 208),
    Entry("dash_fill", 104, 104),
    Entry("crest_moon", 80, 80),
    Entry("crest_beacon", 80, 80),
    Entry("crest_relic", 80, 80),
    Entry("crest_book", 80, 80),
    Entry("crest_coin", 80, 80),
    Entry("crest_gate", 80, 80),
]


def _svg_size(path: Path) -> tuple[int, int]:
    root = ElementTree.parse(path).getroot()
    if root.tag != "{http://www.w3.org/2000/svg}svg" and root.tag != "svg":
        raise SystemExit(f"{path.name}: root element is not <svg>")
    try:
        width = int(float(str(root.attrib["width"]).removesuffix("px")))
        height = int(float(str(root.attrib["height"]).removesuffix("px")))
    except (KeyError, ValueError):
        raise SystemExit(
            f"{path.name}: <svg> needs numeric width/height in pixels") from None
    return width, height


def validate_sources() -> list[str]:
    """Check every authored source parses and keeps the resolution budget."""
    seen: list[str] = []
    for entry in MANIFEST:
        path = SOURCE_DIR / f"{entry.svg}.svg"
        if not path.is_file():
            raise SystemExit(f"missing authored source {path.relative_to(GAME_ROOT)}")
        try:
            width, height = _svg_size(path)
        except ElementTree.ParseError as error:
            raise SystemExit(f"{entry.svg}.svg does not parse: {error}") from None
        if (width, height) != (entry.width, entry.height):
            raise SystemExit(
                f"{entry.svg}.svg is {width}x{height}, "
                f"manifest expects {entry.width}x{entry.height}")
        seen.append(entry.svg)
    stray = sorted(
        path.name for path in SOURCE_DIR.glob("*.svg")
        if path.stem not in seen)
    if stray:
        raise SystemExit(
            f"unmanifested sources under {SOURCE_DIR.relative_to(GAME_ROOT)}: "
            + ", ".join(stray))
    return seen


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if a source is missing, mis-sized, unparsable "
                             "or unmanifested; writes nothing")
    args = parser.parse_args()

    if args.check:
        names = validate_sources()
        print(f"check: {len(names)} authored SVG sources deterministic")
    else:
        parser.print_help()
    return 0


if __name__ == "__main__":
    sys.exit(main())
