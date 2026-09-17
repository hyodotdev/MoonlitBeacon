#!/usr/bin/env python3
"""Assemble Grok ghost sources into 192×192 spirit sheets.

Sources are tools/spirit_grok/<kind>.jpg (magenta bg, one front view). In survivor grammar
ghosts reuse one front art on all four facings — down/left as-is, right
is flipped, up is slightly darkened for a turned-back feel. Four frames are bob
as a y-offset bob.

The hero is 36px so ghosts go in smaller (18–28px by kind).
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter

TOOL_DIR = Path(__file__).resolve().parent
GAME_ROOT = TOOL_DIR.parent
SOURCE_ROOT = TOOL_DIR / "spirit_grok"
SPIRIT_ROOT = GAME_ROOT / "assets/custom/actors/spirits"

CELL = 48
DIRECTIONS = 4          # down, up, left, right — column order in spirit.tscn
FRAMES = 4

# Ghost height (px). Always smaller than the 36px hero. Swarm is pups, so smallest.
HEIGHTS = {
    "wisp": 22,
    "stalker": 24,
    "swarm": 15,
    "ember": 20,
    "drifter": 22,
    "weaver": 23,
    "caster": 24,
}

# Per-frame bob. Leave floor padding and float upward.
BOB = (0, -1, 0, 1)
# Foot gap — ghosts do not touch the ground.
FLOAT_GAP = 6


def _key_magenta(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    corners = [
        rgb.getpixel((2, 2)),
        rgb.getpixel((rgb.width - 3, 2)),
        rgb.getpixel((2, rgb.height - 3)),
        rgb.getpixel((rgb.width - 3, rgb.height - 3)),
    ]
    key = tuple(sum(channel) // 4 for channel in zip(*corners))
    import numpy as np

    arr = np.asarray(rgb, dtype=np.int16)
    dist = np.abs(arr - np.array(key, dtype=np.int16)).sum(axis=2)
    magenta = (
        (arr[:, :, 0] > 150)
        & (arr[:, :, 2] > 70)
        & (arr[:, :, 1] < 140)
        & (arr[:, :, 0] - arr[:, :, 1] > 35)
    )
    mask = np.where((dist < 70) | magenta, 0, 255).astype("uint8")
    alpha = Image.fromarray(mask).filter(ImageFilter.MedianFilter(3))
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def _ensure_rgba(source: Image.Image) -> Image.Image:
    # Sources with alpha (Ludo sprites) stay as-is; only magenta backgrounds are keyed.
    if source.mode in ("RGBA", "LA", "P"):
        rgba = source.convert("RGBA")
        low, _high = rgba.getchannel("A").getextrema()
        if low < 255:
            return rgba
    return _key_magenta(source)


def _fit(source: Image.Image, target_h: int) -> Image.Image:
    keyed = _ensure_rgba(source)
    box = keyed.getchannel("A").getbbox()
    if box is None:
        raise RuntimeError("no ghost remains after keying")
    crop = keyed.crop(box)
    scale = target_h / max(crop.height, 1)
    new_w = max(1, int(round(crop.width * scale)))
    work = crop
    if crop.width > new_w * 2 and crop.height > target_h * 2:
        work = crop.resize((new_w * 2, target_h * 2), Image.Resampling.BOX)
    fitted = work.resize((new_w, target_h), Image.Resampling.LANCZOS)
    fitted = fitted.filter(ImageFilter.UnsharpMask(radius=0.9, percent=130, threshold=2))
    if new_w > CELL - 4:
        cut = (new_w - (CELL - 4)) // 2
        fitted = fitted.crop((cut, 0, cut + CELL - 4, target_h))
        new_w = CELL - 4
    binary = Image.new("RGBA", fitted.size)
    src = fitted.load()
    dst = binary.load()
    for y in range(fitted.height):
        for x in range(fitted.width):
            red, green, blue, alpha = src[x, y]
            dst[x, y] = (red, green, blue, 255) if alpha >= 96 else (0, 0, 0, 0)
    return binary


def _cell_frame(art: Image.Image, frame: int) -> Image.Image:
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    x = (CELL - art.width) // 2
    y = CELL - FLOAT_GAP - art.height + BOB[frame % FRAMES]
    cell.alpha_composite(art, (x, max(0, y)))
    return cell


def _darken(art: Image.Image, amount: float) -> Image.Image:
    rgb = ImageEnhance.Brightness(art.convert("RGB")).enhance(amount)
    out = rgb.convert("RGBA")
    out.putalpha(art.getchannel("A"))
    return out


def _source_path(kind: str) -> Path | None:
    for ext in ("webp", "png", "jpg"):
        path = SOURCE_ROOT / f"{kind}.{ext}"
        if path.is_file():
            return path
    return None


def build_sheet(kind: str) -> Image.Image:
    source = Image.open(_source_path(kind))
    front = _fit(source, HEIGHTS[kind])
    # Up (back) only needs to feel like face detail is hidden. Darken 8%.
    back = _darken(front, 0.92)
    right = front.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    columns = (front, back, front, right)
    sheet = Image.new("RGBA", (CELL * DIRECTIONS, CELL * FRAMES), (0, 0, 0, 0))
    for direction, art in enumerate(columns):
        for frame in range(FRAMES):
            sheet.alpha_composite(
                _cell_frame(art, frame), (direction * CELL, frame * CELL)
            )
    return sheet


def _png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def pack_all(*, check: bool) -> None:
    missing = [k for k in HEIGHTS if _source_path(k) is None]
    targets = [k for k in HEIGHTS if k not in missing]
    if check and missing:
        # Kinds that still lack a source are allowed a transition where the procedural create remains.
        print(
            f"spirit_grok source missing (allowed during transition): "
            f"{', '.join(missing)}"
        )
    for kind in targets:
        sheet = build_sheet(kind)
        path = SPIRIT_ROOT / f"{kind}.png"
        if check:
            if not path.is_file():
                raise RuntimeError(f"production spirit PNG is missing: {path}")
            committed = Image.open(path).convert("RGBA")
            if committed.size != sheet.size \
                    or committed.tobytes() != sheet.convert("RGBA").tobytes():
                raise RuntimeError(
                    f"production spirit PNG differs from the Grok pack: {path}"
                )
        else:
            path.write_bytes(_png_bytes(sheet))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    pack_all(check=args.check)
    print("grok spirits packed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
