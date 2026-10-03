#!/usr/bin/env python3
"""Extract the six painted held weapons into supersampled runtime textures.

Source is ``notes/workflow/muse/art/4-0-0/painted-weapons.png`` (1536x1024
RGBA, 2 columns by 3 rows, right-facing weapons with generous alpha padding).
Row 1 holds the Warden sword and Dancer twin daggers, row 2 the Keeper lantern
pistol and Knight ring cannon, row 3 the Eclipse crescent reaper and Sage
needle rifle.

Each runtime sheet holds four texels per logical weapon pixel and is drawn at
0.25 world scale through per-item Linear filtering, so the painted lantern,
ring, blade, and rifle detail survives at real 2x/3x output instead of
collapsing into nearest-filtered blocks. Logical geometry (tips, grips, axis
rows, seats) is frozen from the round-1 calibration; texture metadata is
exactly four times logical, and the tool verifies both against the paint.

The atlas grid is only approximate: the reaper's curl crosses the row line and
two blades cross the middle column, so weapons are separated by connected
alpha components, not grid lines. Each weapon keeps its own soft fringe;
engineering crop and scale only, no repainting: the tool never draws.

Pipeline per weapon: label the alpha>=32 cores, assign each core to its weapon
across fixed cut lines, floor alpha<8 to zero (measured: 72k dust pixels live
there), scrub matte RGB out of fully transparent pixels, crop the core box
exactly, downscale to exactly four times the logical size, and expand a 4px
transparent margin so the border contract holds by construction. Warden,
dancer, and keeper downscale uniformly; knight pads one transparent row top
and bottom (its aspect rounds between grid lines); eclipse and sage scale
axes independently (logged ratio, asserted within 9%) to preserve the
accepted logical footprint instead of trimming crescent curls or sight bead.

``--check`` rebuilds every sheet in memory and fails when a committed PNG
differs.
"""

from __future__ import annotations

import argparse
import hashlib
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter

TOOL_DIR = Path(__file__).resolve().parent
GAME_ROOT = TOOL_DIR.parent
REPO_ROOT = GAME_ROOT.parent.parent
SOURCE = REPO_ROOT / "notes/workflow/muse/art/4-0-0/painted-weapons.png"
WEAPON_ROOT = GAME_ROOT / "assets/custom/items/weapons"

ORDER = ("warden", "dancer", "keeper", "knight", "eclipse", "sage")

# Texture texels per logical weapon pixel. The rig draws at 1/SUPERSAMPLE.
SUPERSAMPLE = 4
MARGIN_TEX = 4

# Frozen logical geometry from the round-1 calibration, in final logical
# coordinates (content plus the 1px logical margin). The tool re-derives these
# from the source every run and fails on any drift; texture metadata is
# exactly four times these values.
LOGICAL_CONTENT = {
    "warden": (15, 3),
    "dancer": (13, 7),
    "keeper": (13, 7),
    "knight": (13, 5),
    "eclipse": (15, 6),
    "sage": (20, 5),
}
LOGICAL_META = {
    "warden": {"tip_x": 15, "tip_y": 2, "grip_x": 1, "grip_y": 2},
    "dancer": {"tip_x": 13, "tip_y": 4, "grip_x": 1, "grip_y": 4,
               "upper_y": 2, "lower_y": 6, "tip_upper_y": 2, "tip_lower_y": 5},
    "keeper": {"tip_x": 13, "tip_y": 2, "axis_y": 2, "grip_x": 1, "grip_y": 5},
    "knight": {"tip_x": 13, "tip_y": 3, "axis_y": 3, "grip_x": 1, "grip_y": 4},
    "eclipse": {"tip_x": 15, "tip_y": 4, "grip_x": 1, "grip_y": 4},
    "sage": {"tip_x": 20, "tip_y": 3, "axis_y": 3, "grip_x": 1, "grip_y": 4},
}

# Core threshold (component labeling) and dust floor, both measured from the
# source histogram: alpha 1..7 holds 72k scattered dust pixels, 8..31 the soft
# fringe, 32+ solid paint.
CORE_THRESHOLD = 32
DUST_FLOOR = 8
# Cut lines where painted neighbors approach each other: keeper tassel ends at
# row 668 and the reaper curl starts at row 670 (row 669 keeps one keeper
# fringe pixel), warden ends at x=804 and the daggers start at x=902, the
# reaper ends at x=692 and the rifle starts at x=757.
CUT_KEEPER_BOTTOM = 670
CUT_WARDEN_RIGHT = 853
CUT_DANCER_LEFT = 854
CUT_ECLIPSE_RIGHT = 725
CUT_SAGE_LEFT = 726
# Largest tolerated axis-ratio deviation for anamorphic fits.
MAX_ANAMORPHIC = 1.09
MAX_FINAL = (96, 40)


def _label_cores(alpha: Image.Image) -> tuple[list[tuple[int, int, int, int, int]], list[list[int]]]:
    """4-connected components of alpha>=CORE_THRESHOLD. Returns (components,
    label grid): each component is (count, x0, y0, x1, y1) exclusive."""
    width, height = alpha.size
    raw = alpha.tobytes()
    foreground = bytearray(1 if value >= CORE_THRESHOLD else 0 for value in raw)
    labels = [[-1] * width for _ in range(height)]
    components: list[tuple[int, int, int, int, int]] = []
    for y in range(height):
        for x in range(width):
            if not foreground[y * width + x] or labels[y][x] >= 0:
                continue
            index = len(components)
            queue: deque[tuple[int, int]] = deque([(x, y)])
            labels[y][x] = index
            count = 0
            box = [x, y, x + 1, y + 1]
            while queue:
                jx, jy = queue.popleft()
                count += 1
                box[0] = min(box[0], jx)
                box[1] = min(box[1], jy)
                box[2] = max(box[2], jx + 1)
                box[3] = max(box[3], jy + 1)
                for nx, ny in ((jx + 1, jy), (jx - 1, jy), (jx, jy + 1), (jx, jy - 1)):
                    if 0 <= nx < width and 0 <= ny < height \
                            and foreground[ny * width + nx] and labels[ny][nx] < 0:
                        labels[ny][nx] = index
                        queue.append((nx, ny))
            components.append((count, box[0], box[1], box[2], box[3]))
    return components, labels


def _assign(components: list[tuple[int, int, int, int, int]]) -> dict[str, list[int]]:
    """Assign core components to weapons by their boxes. The dancer owns two
    (the twin daggers are disconnected); anything under 16px is logged dust."""
    assignment: dict[str, list[int]] = {name: [] for name in ORDER}
    for index, (count, x0, y0, x1, y1) in enumerate(components):
        if count < 16:
            print(f"  dust: {count}px at ({x0},{y0},{x1},{y1})")
            continue
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        if cy < 341:
            owner = "warden" if cx < CUT_WARDEN_RIGHT else "dancer"
            if owner == "warden" and x1 > CUT_WARDEN_RIGHT:
                raise RuntimeError(f"warden core crosses the dancer cut: {(x0, y0, x1, y1)}")
            if owner == "dancer" and x0 < CUT_DANCER_LEFT:
                raise RuntimeError(f"dancer core crosses the warden cut: {(x0, y0, x1, y1)}")
        elif cy < 682:
            if x0 < 768 and x1 > 768:
                raise RuntimeError(f"row-2 core spans the middle: {(x0, y0, x1, y1)}")
            owner = "keeper" if cx < 768 else "knight"
            if owner == "keeper" and y1 > CUT_KEEPER_BOTTOM:
                raise RuntimeError(f"keeper core crosses the reaper cut: {(x0, y0, x1, y1)}")
        else:
            if x0 < CUT_ECLIPSE_RIGHT and x1 > CUT_SAGE_LEFT:
                raise RuntimeError(f"row-3 core spans the middle cut: {(x0, y0, x1, y1)}")
            owner = "eclipse" if cx < CUT_ECLIPSE_RIGHT else "sage"
            if owner == "eclipse" and y0 < CUT_KEEPER_BOTTOM:
                raise RuntimeError(f"reaper core crosses the keeper cut: {(x0, y0, x1, y1)}")
        assignment[owner].append(index)
    for name in ORDER:
        want = 2 if name == "dancer" else 1
        if len(assignment[name]) != want:
            raise RuntimeError(f"{name}: want {want} core(s), found {len(assignment[name])}")
    return assignment


def _union_box(components: list[tuple[int, int, int, int, int]], indices: list[int]) -> tuple[int, int, int, int]:
    boxes = [components[i][1:] for i in indices]
    return (
        min(box[0] for box in boxes),
        min(box[1] for box in boxes),
        max(box[2] for box in boxes),
        max(box[3] for box in boxes),
    )


def _clean(image: Image.Image) -> Image.Image:
    """Floor dust alpha and scrub matte RGB from transparent pixels."""
    pixels = image.load()
    width, height = image.size
    for y in range(height):
        for x in range(width):
            _red, _green, _blue, alpha = pixels[x, y]
            if alpha < DUST_FLOOR:
                # Dust floor and matte scrub in one: anything under the floor
                # becomes transparent black, never tinted glass.
                pixels[x, y] = (0, 0, 0, 0)
    return image


def _crisp_resize(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    """Two-step downscale with the hero pack's sharpen pass."""
    width, height = size
    work = image
    if image.width > width * 2 and image.height > height * 2:
        work = image.resize((width * 2, height * 2), Image.Resampling.BOX)
    out = work.resize(size, Image.Resampling.LANCZOS)
    return out.filter(ImageFilter.UnsharpMask(radius=0.9, percent=130, threshold=2))


def _column_centroid(alpha: Image.Image, x0: int, x1: int, y0: int, y1: int) -> float:
    total = 0
    weighted = 0
    pixels = alpha.load()
    for y in range(y0, y1):
        for x in range(x0, x1):
            if pixels[x, y] >= CORE_THRESHOLD:
                total += 1
                weighted += y
    if total == 0:
        raise RuntimeError("empty calibration span")
    return weighted / total


def _calibrate(
    name: str, alpha: Image.Image, box: tuple[int, int, int, int],
) -> dict[str, float]:
    """Measure grip/tip/axis in source pixels from the core alpha."""
    x0, y0, x1, y1 = box
    width = x1 - x0
    tip_x = float(x1 - 1)
    if name in ("keeper", "knight", "sage"):
        # Barrel axis: opaque-row centroid of the rightmost 8% (bell lips and
        # ring aperture are symmetric about it, the needle ends on it).
        span = max(int(width * 0.08), 6)
        axis = _column_centroid(alpha, x1 - span, x1, y0, y1)
        grip_rows = _column_centroid(alpha, x0, x0 + max(int(width * 0.10), 6), y0, y1)
        return {"tip_x": tip_x, "tip_y": axis, "axis_y": axis, "grip_x": float(x0), "grip_y": grip_rows}
    if name == "dancer":
        # Twin handles left, blades right: the handle columns hold two vertical
        # paint masses, and the hand centers in the gap between them.
        pixels = alpha.load()
        span = max(int(width * 0.12), 8)
        rows = [
            y for y in range(y0, y1)
            if any(pixels[x, y] >= CORE_THRESHOLD for x in range(x0, x0 + span))
        ]
        masses: list[list[int]] = []
        for row in rows:
            if masses and row - masses[-1][-1] <= 8:
                masses[-1].append(row)
            else:
                masses.append([row])
        masses.sort(key=len, reverse=True)
        if len(masses) < 2:
            raise RuntimeError("dancer: want 2 handle masses, found fewer")
        first, second = sorted(masses[:2], key=lambda mass: mass[0])
        gap = (first[-1] + second[0]) / 2.0

        def _centroid(lo: int, hi: int) -> float:
            total = 0
            weighted = 0
            for y in range(lo, hi + 1):
                for x in range(x0, x0 + span):
                    if pixels[x, y] >= CORE_THRESHOLD:
                        total += 1
                        weighted += y
            return weighted / max(total, 1)

        upper = _centroid(first[0], first[-1])
        lower = _centroid(second[0], second[-1])
        grip_x_total = 0.0
        grip_n = 0
        for y in range(y0, y1):
            for x in range(x0, x0 + max(int(width * 0.06), 4)):
                if pixels[x, y] >= CORE_THRESHOLD:
                    grip_x_total += x
                    grip_n += 1
        # Twin tips: the two blades end side by side, so the rightmost paint
        # forms two row clusters and a plain centroid would land in the gap.
        # The pair's tip row is the midpoint the two blades straddle.
        pixels = alpha.load()
        edge = max(int(width * 0.03), 3)
        tip_rows = sorted({
            y for y in range(y0, y1)
            for x in range(x1 - edge, x1)
            if pixels[x, y] >= CORE_THRESHOLD
        })
        clusters: list[list[int]] = []
        for row in tip_rows:
            if clusters and row - clusters[-1][-1] <= 6:
                clusters[-1].append(row)
            else:
                clusters.append([row])
        if len(clusters) != 2:
            raise RuntimeError(f"dancer: want 2 tip clusters, found {len(clusters)}")
        tips = [sum(cluster) / len(cluster) for cluster in clusters]
        return {
            "tip_x": tip_x, "tip_y": sum(tips) / len(tips),
            "grip_x": grip_x_total / max(grip_n, 1), "grip_y": gap,
            "upper_y": upper, "lower_y": lower,
            "tip_upper_y": tips[0], "tip_lower_y": tips[1],
        }
    # Sword and reaper: leftmost handle centroid holds the hand, rightmost
    # paint ends the blade.
    grip_span = max(int(width * 0.06), 4)
    grip_total = 0
    grip_wx = 0.0
    grip_wy = 0.0
    pixels = alpha.load()
    for y in range(y0, y1):
        for x in range(x0, x0 + grip_span):
            if pixels[x, y] >= CORE_THRESHOLD:
                grip_total += 1
                grip_wx += x
                grip_wy += y
    if grip_total == 0:
        raise RuntimeError(f"{name}: no handle paint in the grip span")
    tip_span = max(int(width * 0.05), 4)
    tip_y = _column_centroid(alpha, x1 - tip_span, x1, y0, y1)
    return {
        "tip_x": tip_x, "tip_y": tip_y,
        "grip_x": grip_wx / grip_total, "grip_y": grip_wy / grip_total,
    }


def _to_logical(value: float, origin: int, scale: float) -> int:
    """Source pixel-center rule plus the 1px logical margin."""
    return int((value - origin + 0.5) * scale) + 1


def _fit_scales(
    name: str, box: tuple[int, int, int, int],
) -> tuple[float, float, str]:
    """Downscale factors hitting exactly SUPERSAMPLE times logical.

    Returns (sx, sy, strategy): a uniform scale from the overlap of the
    width/height rounding intervals when one exists, else the documented
    per-weapon fallback (knight pads, eclipse scales axes independently)."""
    x0, y0, x1, y1 = box
    core_w, core_h = x1 - x0, y1 - y0
    want_w, want_h = LOGICAL_CONTENT[name]
    target_w, target_h = want_w * SUPERSAMPLE, want_h * SUPERSAMPLE
    lo = max((target_w - 0.5) / core_w, (target_h - 0.5) / core_h)
    hi = min((target_w + 0.5) / core_w, (target_h + 0.5) / core_h)
    if lo < hi:
        scale = (lo + hi) / 2.0
        if round(core_w * scale) == target_w and round(core_h * scale) == target_h:
            return scale, scale, "uniform"
    if name == "knight":
        # 601x213 cannot hit 52x20 uniformly (width and height intervals are
        # disjoint), so scale for the exact width and pad one transparent row
        # top and bottom: zero art change, exact footprint.
        scale = target_w / core_w
        natural_h = round(core_h * scale)
        if natural_h != target_h - 2:
            raise RuntimeError(f"knight: natural height {natural_h}, want {target_h - 2}")
        return scale, scale, "pad-1t1b"
    if name in ("eclipse", "sage"):
        # 661x282 and 750x203 cannot hit their 4x targets uniformly either;
        # trimming would cut crescent curls or the sight bead, so scale axes
        # independently and assert the ratio.
        sx, sy = target_w / core_w, target_h / core_h
        ratio = sy / sx
        if not 1.0 / MAX_ANAMORPHIC <= ratio <= MAX_ANAMORPHIC:
            raise RuntimeError(f"{name}: anamorphic ratio {ratio} out of bounds")
        return sx, sy, f"anamorphic-{ratio:.4f}"
    raise RuntimeError(f"{name}: no uniform scale hits {target_w}x{target_h}")


def _verify_output(
    name: str, sheet: Image.Image, logical: dict[str, int],
) -> None:
    """Verify texture paint against exactly-4x logical metadata.

    A logical pixel maps to the texel band [4p, 4p+3]; the rig draws texels at
    0.25 world scale, so paint anywhere inside the band renders inside the
    logical pixel. Checks use bands, never single texels, with the margin ring
    still exact."""
    width, height = sheet.size
    want_w, want_h = LOGICAL_CONTENT[name]
    if (width, height) != ((want_w + 2) * SUPERSAMPLE, (want_h + 2) * SUPERSAMPLE):
        raise RuntimeError(f"{name}: sheet {sheet.size} is not 4x logical")
    alpha = sheet.getchannel("A")
    pixels = alpha.load()
    for x in range(width):
        for edge in range(MARGIN_TEX):
            if pixels[x, edge] != 0 or pixels[x, height - 1 - edge] != 0:
                raise RuntimeError(f"{name}: margin broken at x={x}")
    for y in range(height):
        for edge in range(MARGIN_TEX):
            if pixels[edge, y] != 0 or pixels[width - 1 - edge, y] != 0:
                raise RuntimeError(f"{name}: margin broken at y={y}")

    def band(point: int) -> tuple[int, int]:
        return point * SUPERSAMPLE, point * SUPERSAMPLE + SUPERSAMPLE - 1

    opaque_cols = [
        x for x in range(width)
        if any(pixels[x, y] >= CORE_THRESHOLD for y in range(height))
    ]
    if not opaque_cols:
        raise RuntimeError(f"{name}: no opaque paint survives")
    # The calibrated tip band holds the visual end of the paint.
    tip_lo, tip_hi = band(logical["tip_x"])
    rightmost = max(opaque_cols)
    if not tip_lo <= rightmost <= tip_hi:
        raise RuntimeError(
            f"{name}: paint ends at x={rightmost}, tip band is {tip_lo}..{tip_hi}")
    if name == "dancer":
        _verify_dancer_bands(name, pixels, width, height, logical, band)
        return
    if name in ("keeper", "knight", "sage"):
        axis_lo, axis_hi = band(logical["axis_y"])
        end_paint = sum(
            1 for x in range(max(rightmost - 7, 0), rightmost + 1)
            for y in range(axis_lo, axis_hi + 1)
            if pixels[x, y] >= CORE_THRESHOLD
        )
        if end_paint < 4:
            raise RuntimeError(f"{name}: muzzle paint misses the axis band")
    else:
        grip_lo_x, grip_hi_x = band(logical["grip_x"])
        grip_lo_y, grip_hi_y = band(logical["grip_y"])
        found = any(
            pixels[x, y] >= CORE_THRESHOLD
            for y in range(grip_lo_y, grip_hi_y + 1)
            for x in range(grip_lo_x, grip_hi_x + 1)
        )
        if not found:
            raise RuntimeError(f"{name}: grip band holds no paint")


def _verify_dancer_bands(
    name: str,
    pixels,
    width: int,
    height: int,
    logical: dict[str, int],
    band,
) -> None:
    tip_lo, tip_hi = band(logical["tip_x"])
    grip_lo, grip_hi = band(logical["grip_y"])
    # Both blades reach the end columns, straddling the tip band rows.
    end_rows = {
        y for y in range(height)
        for x in range(tip_lo, tip_hi + 1)
        if pixels[x, y] >= CORE_THRESHOLD
    }
    band_lo, band_hi = band(logical["tip_y"])
    if not any(y < band_lo for y in end_rows) \
            or not any(y > band_hi for y in end_rows):
        raise RuntimeError(f"{name}: twin tips do not straddle the tip band")
    # Both handles show in the handle columns, straddling the grip band rows.
    handle_rows = {
        y for y in range(height)
        for x in range(MARGIN_TEX, width // 3)
        if pixels[x, y] >= CORE_THRESHOLD
    }
    if not any(y < grip_lo for y in handle_rows) \
            or not any(y > grip_hi for y in handle_rows):
        raise RuntimeError(f"{name}: twin handles do not straddle the grip band")


def build_all() -> dict[str, tuple[Image.Image, dict[str, int], tuple[int, int, int, int], str]]:
    source = Image.open(SOURCE).convert("RGBA")
    if source.size != (1536, 1024):
        raise RuntimeError(f"unexpected source size: {source.size}")
    components, _labels = _label_cores(source.getchannel("A"))
    assignment = _assign(components)
    cleaned = _clean(source)
    alpha = cleaned.getchannel("A")
    results: dict[str, tuple[Image.Image, dict[str, int], tuple[int, int, int, int], str]] = {}
    for name in ORDER:
        box = _union_box(components, assignment[name])
        calibration = _calibrate(name, alpha, box)
        x0, y0, x1, y1 = box
        # The frozen logical metadata must still be exactly what the source
        # measures: any drift between rounds fails here, not in the game.
        logical_scale = LOGICAL_CONTENT[name][0] / (x1 - x0)
        logical = {
            key: _to_logical(value, (x0 if key.endswith("_x") else y0), logical_scale)
            for key, value in calibration.items()
        }
        for key in ("tip_x", "grip_x"):
            logical[key] = min(max(logical[key], 1), LOGICAL_CONTENT[name][0])
        for key in ("tip_y", "grip_y", "axis_y", "upper_y", "lower_y",
                     "tip_upper_y", "tip_lower_y"):
            if key in logical:
                logical[key] = min(max(logical[key], 1), LOGICAL_CONTENT[name][1])
        if logical != LOGICAL_META[name]:
            raise RuntimeError(
                f"{name}: logical drift — measured {logical}, frozen {LOGICAL_META[name]}")
        sx, sy, strategy = _fit_scales(name, box)
        want_w, want_h = LOGICAL_CONTENT[name]
        natural = (round((x1 - x0) * sx), round((y1 - y0) * sy))
        content = _crisp_resize(cleaned.crop(box), natural)
        target = (want_w * SUPERSAMPLE, want_h * SUPERSAMPLE)
        if strategy == "pad-1t1b":
            if natural != (target[0], target[1] - 2):
                raise RuntimeError(f"{name}: pad strategy but natural {natural}")
            padded = Image.new("RGBA", target, (0, 0, 0, 0))
            padded.alpha_composite(content, (0, 1))
            content = padded
        elif natural != target:
            raise RuntimeError(f"{name}: natural {natural} misses target {target}")
        sheet = Image.new(
            "RGBA", (target[0] + 2 * MARGIN_TEX, target[1] + 2 * MARGIN_TEX),
            (0, 0, 0, 0))
        sheet.alpha_composite(content, (MARGIN_TEX, MARGIN_TEX))
        if sheet.size[0] > MAX_FINAL[0] or sheet.size[1] > MAX_FINAL[1]:
            raise RuntimeError(f"{name}: output {sheet.size} exceeds {MAX_FINAL}")
        meta = {key: value * SUPERSAMPLE for key, value in LOGICAL_META[name].items()}
        _verify_output(name, sheet, LOGICAL_META[name])
        results[name] = (sheet, meta, box, strategy)
    return results


def _png_bytes(sheet: Image.Image) -> bytes:
    from io import BytesIO

    buffer = BytesIO()
    sheet.save(buffer, format="PNG")
    return buffer.getvalue()


def _report(results: dict[str, tuple[Image.Image, dict[str, int], tuple[int, int, int, int], str]]) -> None:
    print("painted weapons: 1536x1024 -> 4x supersampled runtime sheets")
    for name in ORDER:
        sheet, meta, box, strategy = results[name]
        digest = hashlib.sha256(_png_bytes(sheet)).hexdigest()[:16]
        print(
            f"  {name:<7} core=({box[0]},{box[1]},{box[2]},{box[3]}) "
            f"sheet={sheet.size[0]}x{sheet.size[1]} [{strategy}] "
            f"tex_meta={meta} sha={digest}"
        )
    print("Logical metadata is frozen (see LOGICAL_META); texture metadata is 4x logical.")


def pack_all(*, check: bool) -> None:
    results = build_all()
    for name in ORDER:
        sheet, _meta, _box, _strategy = results[name]
        path = WEAPON_ROOT / f"{name}.png"
        if check:
            if not path.is_file():
                raise RuntimeError(f"production weapon PNG is missing: {path}")
            committed = Image.open(path).convert("RGBA")
            if committed.size != sheet.size \
                    or committed.tobytes() != sheet.convert("RGBA").tobytes():
                raise RuntimeError(
                    f"production weapon PNG differs from the painted pack: {path}")
        else:
            WEAPON_ROOT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(_png_bytes(sheet))
    _report(results)
    print("painted weapons packed" if not check else "painted weapons check passed")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    pack_all(check=args.check)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
