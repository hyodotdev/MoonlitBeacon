#!/usr/bin/env python3
"""Compare one stored terrain sheet with the pixels its generator baked.

PNG encoders differ across machines, so two identical RGBA artworks can have
different bytes. The terrain generators therefore check the complete decoded
RGBA artwork and dimensions instead of the raw bytes, while still rejecting
missing, unreadable, corrupt, non-PNG, wrongly shaped or wrongly formatted
sheets.
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from check_custom_assets import read_rgba_png


def check_sheet(target: Path, baked: Image.Image) -> str | None:
    if not target.exists():
        return f"missing {target.name}"
    try:
        stored = read_rgba_png(target)
    except Exception as error:
        # Any decode failure is a stale sheet, not a crash: name it and fail.
        return f"unreadable {target.name} ({error})"
    want_w, want_h = baked.size
    if (stored.width, stored.height) != (want_w, want_h):
        return (f"out of date {target.name} "
                f"(is {stored.width}x{stored.height}, want {want_w}x{want_h})")
    if stored.pixels != baked.tobytes():
        return f"out of date {target.name} (decoded pixels differ from the bake)"
    return None
