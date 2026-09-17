#!/usr/bin/env python3
"""Assemble Maple-style chibi sources into 48×64 hero sheets.

Sources are tools/hero_maple/<id>/{front,back,left}.jpg. Strip magenta,
fit to the cell from the feet, then right is an exact flip of left.
"""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageEnhance, ImageFilter


TOOL_DIR = Path(__file__).resolve().parent
GAME_ROOT = TOOL_DIR.parent
SOURCE_ROOT = TOOL_DIR / "hero_maple"
HERO_ROOT = GAME_ROOT / "assets/custom/actors/heroes"
REVIEW_DIR = GAME_ROOT.parents[1] / "builds/art-review/a0-player"

CELL_W = 48
CELL_H = 64
DIRECTIONS = 4
FRAMES = 4
PORTRAIT = 96

HEROES = ("warden", "dancer", "keeper", "knight", "eclipse", "sage")


def _key_magenta(image: Image.Image) -> Image.Image:
    rgb = image.convert("RGB")
    corners = [
        rgb.getpixel((2, 2)),
        rgb.getpixel((rgb.width - 3, 2)),
        rgb.getpixel((2, rgb.height - 3)),
        rgb.getpixel((rgb.width - 3, rgb.height - 3)),
    ]
    key = tuple(sum(channel) // 4 for channel in zip(*corners))
    try:
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
        alpha = Image.fromarray(mask)
    except ImportError:
        pixels = rgb.load()
        alpha = Image.new("L", rgb.size, 0)
        dest = alpha.load()
        width, height = rgb.size
        for y in range(height):
            for x in range(width):
                red, green, blue = pixels[x, y]
                dist = abs(red - key[0]) + abs(green - key[1]) + abs(blue - key[2])
                magenta = red > 150 and blue > 70 and green < 140 and red - green > 35
                dest[x, y] = 0 if dist < 70 or magenta else 255
    alpha = alpha.filter(ImageFilter.MedianFilter(3))
    rgba = rgb.convert("RGBA")
    rgba.putalpha(alpha)
    return rgba


def _crisp_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    width, height = size
    work = image
    if image.width > width * 2 and image.height > height * 2:
        work = image.resize((width * 2, height * 2), Image.Resampling.BOX)
    out = work.resize(size, Image.Resampling.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=0.9, percent=130, threshold=2))


def _bbox(image: Image.Image) -> tuple[int, int, int, int]:
    alpha = image.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        raise RuntimeError("no character remains after keying")
    return box


def _ensure_rgba(source: Image.Image) -> Image.Image:
    # Use alpha PNGs (Ludo export) as-is; key only magenta-background JPGs.
    if source.mode in ("RGBA", "LA"):
        rgba = source.convert("RGBA")
        low, _high = rgba.getchannel("A").getextrema()
        if low < 255:
            return rgba
    return _key_magenta(source)


def _fit_cell(
    source: Image.Image, keep: str = "center", max_w: int = 36, target_h: int = 36
) -> Image.Image:
    keyed = _ensure_rgba(source)
    left, top, right, bottom = _bbox(keyed)
    crop = keyed.crop((left, top, right, bottom))
    # Fit height first. Scaling a wide side-step pose by width
    # the body vanishes and only a moonlight orb remains at the feet.
    scale = target_h / max(crop.height, 1)
    new_w = max(1, int(round(crop.width * scale)))
    new_h = target_h
    fitted = _crisp_resize(crop, (new_w, new_h))
    if new_w > max_w:
        extra = new_w - max_w
        if keep == "face-left":
            cut = 0
        elif keep == "face-right":
            cut = extra
        else:
            cut = extra // 2
        fitted = fitted.crop((cut, 0, cut + max_w, new_h))
        new_w = max_w
    binary = Image.new("RGBA", fitted.size)
    src = fitted.load()
    dst = binary.load()
    for y in range(fitted.height):
        for x in range(fitted.width):
            red, green, blue, alpha = src[x, y]
            dst[x, y] = (red, green, blue, 255) if alpha >= 96 else (0, 0, 0, 0)
    cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    origin_x = (CELL_W - new_w) // 2
    origin_y = CELL_H - new_h
    cell.alpha_composite(binary, (origin_x, origin_y))
    return cell


def _fit_cells_union(
    sources: list[Image.Image],
    max_w: int = 44,
    target_h: int = 36,
    center_each_x: bool = False,
) -> list[Image.Image]:
    """Fit one facing's walk frames into the cell with a shared bbox and shared scale.

    Fitting each frame alone makes the lifted-foot (shorter bbox) frame grow so
    the body bobs while walking. Ludo export already floor-aligns, so
    preserve relative motion between frames as-is.
    """
    keyed = [_ensure_rgba(source) for source in sources]
    boxes = [_bbox(image) for image in keyed]
    left = min(box[0] for box in boxes)
    top = min(box[1] for box in boxes)
    right = max(box[2] for box in boxes)
    bottom = max(box[3] for box in boxes)
    scale = target_h / max(bottom - top, 1)
    new_w = max(1, int(round((right - left) * scale)))
    new_h = target_h
    cells: list[Image.Image] = []
    for image in keyed:
        crop = image.crop((left, top, right, bottom))
        fitted = _crisp_resize(crop, (new_w, new_h))
        if new_w > max_w:
            cut = (new_w - max_w) // 2
            fitted = fitted.crop((cut, 0, cut + max_w, new_h))
        binary = Image.new("RGBA", fitted.size)
        src = fitted.load()
        dst = binary.load()
        for y in range(fitted.height):
            for x in range(fitted.width):
                red, green, blue, alpha = src[x, y]
                dst[x, y] = (red, green, blue, 255) if alpha >= 96 else (0, 0, 0, 0)
        cell = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        origin_x = (CELL_W - binary.width) // 2
        if center_each_x:
            # On a side-step the bbox center sways each time arms and legs extend. A shared
            # bbox alone, that sway remains and the walk **slides left and right in place**.
            # Center each frame's silhouette on the cell so only horizontal jitter is removed.
            # Center each frame's silhouette on the cell to remove only horizontal jitter (stride/height keep the shared scale).
            box = binary.getchannel("A").getbbox()
            if box is not None:
                origin_x = (CELL_W - (box[0] + box[2])) // 2
        cell.alpha_composite(binary, (origin_x, CELL_H - new_h))
        cells.append(cell)
    return cells


def _nudge(cell: Image.Image, dx: int, dy: int) -> Image.Image:
    # ImageChops.offset wraps pixels to the other side. If a foot goes above the head,
    # walking down looks like the torso is sliding left and right.
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    src_x = max(0, -dx)
    src_y = max(0, -dy)
    dest_x = max(0, dx)
    dest_y = max(0, dy)
    width = CELL_W - abs(dx)
    height = CELL_H - abs(dy)
    if width <= 0 or height <= 0:
        return cell
    piece = cell.crop((src_x, src_y, src_x + width, src_y + height))
    out.alpha_composite(piece, (dest_x, dest_y))
    return _pin_feet(out)


def _pin_feet(cell: Image.Image) -> Image.Image:
    alpha = cell.getchannel("A")
    box = alpha.getbbox()
    if box is None:
        return cell
    _left, _top, _right, bottom = box
    if bottom == CELL_H:
        return cell
    pinned = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    pinned.alpha_composite(cell, (0, CELL_H - bottom))
    return pinned


def _glow(cell: Image.Image, amount: float) -> Image.Image:
    rgb = cell.convert("RGB")
    boosted = ImageEnhance.Brightness(rgb).enhance(amount)
    out = boosted.convert("RGBA")
    out.putalpha(cell.getchannel("A"))
    return out


def _idle_frames(cell: Image.Image) -> list[Image.Image]:
    return [cell, _glow(cell, 1.06), cell, _glow(cell, 1.10)]


def _front_walk_frames(cell: Image.Image) -> list[Image.Image]:
    """Front and back freeze the torso and only shift the boots left/right.

    Flipping the whole lower body makes the moonlight orb and coat hem slide left/right so
    the torso sways when walking down.
    """
    box = cell.getchannel("A").getbbox()
    if box is None:
        return [cell] * FRAMES
    boot_split = min(CELL_H - 7, box[3] - 7)
    boot_split = max(boot_split, box[1] + 8)
    frames: list[Image.Image] = []
    for boot_dx in (-2, 0, 2, 0):
        out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
        body = cell.copy()
        body.paste((0, 0, 0, 0), (0, boot_split, CELL_W, CELL_H))
        boots = cell.crop((0, boot_split, CELL_W, CELL_H))
        out.alpha_composite(body, (0, 0))
        dest_x = max(0, boot_dx)
        src_x = max(0, -boot_dx)
        width = CELL_W - abs(boot_dx)
        if width > 0:
            out.alpha_composite(
                boots.crop((src_x, 0, src_x + width, boots.height)),
                (dest_x, boot_split),
            )
        frames.append(out)
    return frames


def _walk_frames(cell: Image.Image) -> list[Image.Image]:
    return _front_walk_frames(cell)


def _sheet(frames_by_dir: list[list[Image.Image]]) -> Image.Image:
    sheet = Image.new("RGBA", (CELL_W * DIRECTIONS, CELL_H * FRAMES), (0, 0, 0, 0))
    for frame, row in enumerate(zip(*frames_by_dir)):
        for direction, cell in enumerate(row):
            sheet.alpha_composite(cell, (direction * CELL_W, frame * CELL_H))
    return sheet


def _portrait(front: Image.Image) -> Image.Image:
    keyed = _ensure_rgba(front)
    left, top, right, bottom = _bbox(keyed)
    height = bottom - top
    head = keyed.crop((left, top, right, top + max(int(height * 0.62), 8)))
    scale = min((PORTRAIT - 4) / head.width, (PORTRAIT - 4) / head.height)
    new_w = max(1, int(round(head.width * scale)))
    new_h = max(1, int(round(head.height * scale)))
    resized = _crisp_resize(head, (new_w, new_h))
    binary = Image.new("RGBA", resized.size)
    src = resized.load()
    dst = binary.load()
    for y in range(resized.height):
        for x in range(resized.width):
            red, green, blue, alpha = src[x, y]
            dst[x, y] = (red, green, blue, 255) if alpha >= 96 else (0, 0, 0, 0)
    canvas = Image.new("RGBA", (PORTRAIT, PORTRAIT), (0, 0, 0, 0))
    canvas.alpha_composite(
        binary, ((PORTRAIT - new_w) // 2, (PORTRAIT - new_h) // 2)
    )
    return canvas


def _open_optional(path: Path) -> Image.Image | None:
    if not path.is_file():
        return None
    return Image.open(path)


def _open_view(folder: Path, view: str) -> Image.Image:
    # Ludo sources are alpha webp; Grok sources are magenta jpg. Search extensions in order.
    for ext in ("webp", "png", "jpg"):
        path = folder / f"{view}.{ext}"
        if path.is_file():
            return Image.open(path)
    raise FileNotFoundError(f"{folder}/{view}.(webp|png|jpg) source is missing")


def _load_views(name: str) -> dict[str, Image.Image]:
    folder = SOURCE_ROOT / name
    front = _open_view(folder, "front")
    back = _open_view(folder, "back")
    left = _open_view(folder, "left")
    return {
        "down": _fit_cell(front),
        "up": _fit_cell(back),
        "left": _fit_cell(left, "face-left"),
        "right": _fit_cell(left, "face-left").transpose(Image.Transpose.FLIP_LEFT_RIGHT),
        "front_src": front,
        "walk_down": _load_walk_row(folder, "front"),
        "walk_up": _load_walk_row(folder, "back"),
        "walk_left": _load_walk_row(folder, "left"),
    }


def _load_walk_row(folder: Path, facing: str) -> list[Image.Image] | None:
    sources: list[Image.Image] = []
    for index in range(FRAMES):
        image = _open_optional(folder / f"walk_{facing}_{index}.png")
        if image is None:
            image = _open_optional(folder / f"walk_{facing}_{index}.jpg")
        if image is None:
            break
        sources.append(image)
    if len(sources) == FRAMES:
        # Horizontal per-frame centering only on side-step. Front/back have a fixed torso so they do not need it.
        return _fit_cells_union(sources, center_each_x=(facing == "left"))
    frames = [_fit_cell(image, "center", max_w=44) for image in sources]
    if len(frames) >= 2:
        first, second = frames[0], frames[1]
        if _cells_too_similar(first, second):
            return _walk_frames(first)
        return [first, _nudge(first, 0, -1), second, _nudge(second, 0, -1)]
    if len(frames) == 1:
        return _walk_frames(frames[0])
    return None


def _cells_too_similar(first: Image.Image, second: Image.Image) -> bool:
    a = first.tobytes()
    b = second.tobytes()
    if len(a) != len(b) or not a:
        return True
    same = sum(1 for i in range(0, len(a), 16) if a[i:i + 4] == b[i:i + 4])
    return same / (len(a) / 16) > 0.92


def pack_hero(name: str) -> dict[str, Image.Image]:
    views = _load_views(name)
    order = ("down", "up", "left", "right")
    idle = _sheet([_idle_frames(views[direction]) for direction in order])
    walk_rows: list[list[Image.Image]] = []
    for direction in order:
        ready = views.get(f"walk_{direction}")
        if direction == "right" and views.get("walk_left") is not None:
            ready = [
                frame.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
                for frame in views["walk_left"]
            ]
        walk_rows.append(ready if ready is not None else _walk_frames(views[direction]))
    walk = _sheet(walk_rows)
    portrait = _portrait(views["front_src"])
    return {"idle": idle, "walk": walk, "portrait": portrait}


def _png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    image.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def pack_all(*, check: bool) -> None:
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    for name in HEROES:
        packed = pack_hero(name)
        dest = HERO_ROOT / name
        dest.mkdir(parents=True, exist_ok=True)
        for key, image in packed.items():
            path = dest / f"{key}.png"
            if check:
                # PNG encoding bytes differ by Pillow version. The check's point is
                # "is the committed output the same picture as the packed result", so compare pixels.
                if not path.is_file():
                    raise RuntimeError(f"production hero PNG is missing: {path}")
                committed = Image.open(path).convert("RGBA")
                if committed.size != image.size \
                        or committed.tobytes() != image.convert("RGBA").tobytes():
                    raise RuntimeError(
                        f"production hero PNG differs from the Maple sheet pack: {path}"
                    )
            else:
                path.write_bytes(_png_bytes(image))
        if not check:
            preview = Image.new("RGBA", (CELL_W * 4 * 3, CELL_H * 4 * 2 + PORTRAIT + 16))
            preview.paste(packed["idle"], (0, 0))
            preview.paste(packed["walk"], (0, CELL_H * 4 + 8))
            preview.paste(packed["portrait"], (8, CELL_H * 8 + 16))
            preview.save(REVIEW_DIR / f"{name}-maple-preview.png")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    pack_all(check=args.check)
    print("maple heroes packed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
