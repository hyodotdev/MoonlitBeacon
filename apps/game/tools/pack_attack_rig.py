#!/usr/bin/env python3
"""Cut the painted attack rig: armless torsos plus two-bone arm patches.

Each hero's idle row-0 cell holds its arms as baked paint. This bakes, per
hero and facing, an armless torso strip (the vacated arm paint inpainted with
its nearest surviving neighbor) and capsule-cut upper/forearm patches with
recorded shoulder/elbow/wrist joints, so the runtime can articulate the real
painted arm over the real painted body with no duplicate limb.

Calibration (SPEC below) was read off the idle cells on a 12px grid and is
verified two ways: the two-bone IK at the rest wrist must reproduce the
calibrated elbow within 1px (pole check), and `--check` byte-verifies every
output. Regenerate deterministically; never hand-edit outputs.

    node scripts/python.mjs -B apps/game/tools/pack_attack_rig.py --check
    node scripts/python.mjs -B apps/game/tools/pack_attack_rig.py
    node scripts/python.mjs -B apps/game/tools/pack_attack_rig.py --preview /tmp/attackrig-preview

Outputs per hero under `assets/custom/actors/heroes/<hero>/rig/`:
`torso_<facing>.png`, `arm_<facing>_<side>_{upper,fore}.png`, `rig.json`.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import sys
from collections import deque
from pathlib import Path

from PIL import Image, ImageDraw

GAME = Path(__file__).resolve().parent.parent
HEROES = ["warden", "dancer", "keeper", "knight", "eclipse", "sage"]
FACINGS = ["down", "up", "left", "right"]
CELL_W, CELL_H = 144, 192
OVERLAP = 8

# SPEC[hero][facing] = {"cutline": y, "arms": {side: {
#   "S": shoulder, "E": elbow, "W": wrist (cell px), "w1": upper width,
#   "w2": fore width, "pole": elbow-bow direction}}}
# Sides are viewer-left/right for down/up, near/far for left/right.
# Side joints are read off the donor-based standing idle (brief 186); right
# mirrors left exactly (x' = 143 - x) because the idle right column is the
# left mirror.
SPEC = {
    "warden": {
        "cutline": 160,
        "arms": {
            "down": {"right": {"S": (96, 134), "E": (98, 143), "W": (99, 152),
                               "w1": 9, "w2": 8, "pole": (1.0, 0.35)}},
            "up": {"right": {"S": (84, 138), "E": (88, 148), "W": (90, 157),
                             "w1": 9, "w2": 8, "pole": (1.0, 0.35)}},
            "left": {"near": {"S": (60, 132), "E": (56, 142), "W": (52, 151),
                              "w1": 9, "w2": 8, "pole": (1.0, 0.35)}},
            "right": {"near": {"S": (83, 132), "E": (87, 142), "W": (91, 151),
                               "w1": 9, "w2": 8, "pole": (-1.0, 0.35)}},
        },
    },
    "dancer": {
        "cutline": 158,
        "arms": {
            "down": {
                "right": {"S": (90, 130), "E": (93, 141), "W": (95, 152),
                          "w1": 10, "w2": 9, "pole": (1.0, 0.35)},
                "left": {"S": (52, 130), "E": (50, 141), "W": (48, 152),
                         "w1": 10, "w2": 9, "pole": (-1.0, 0.35)},
            },
            "up": {
                "right": {"S": (92, 130), "E": (94, 141), "W": (96, 152),
                          "w1": 10, "w2": 9, "pole": (1.0, 0.35)},
                "left": {"S": (50, 130), "E": (48, 141), "W": (46, 152),
                         "w1": 10, "w2": 9, "pole": (-1.0, 0.35)},
            },
            "left": {
                "near": {"S": (58, 130), "E": (54, 140), "W": (50, 150),
                         "w1": 10, "w2": 9, "pole": (1.0, 0.35)},
            },
            "right": {
                "near": {"S": (85, 130), "E": (89, 140), "W": (93, 150),
                         "w1": 10, "w2": 9, "pole": (-1.0, 0.35)},
            },
        },
    },
    "keeper": {
        "cutline": 164,
        "arms": {
            "down": {"right": {"S": (102, 128), "E": (106, 143),
                               "W": (104, 158),
                               "w1": 13, "w2": 11, "pole": (1.0, 0.35)}},
            "up": {"right": {"S": (100, 128), "E": (104, 143), "W": (102, 158),
                             "w1": 13, "w2": 11, "pole": (1.0, 0.35)}},
            "left": {"near": {"S": (52, 128), "E": (45, 140), "W": (40, 150),
                              "w1": 13, "w2": 11, "pole": (1.0, 0.35)}},
            "right": {"near": {"S": (91, 128), "E": (98, 140), "W": (103, 150),
                               "w1": 13, "w2": 11, "pole": (-1.0, 0.35)}},
        },
    },
    "knight": {
        "cutline": 158,
        "arms": {
            "down": {"right": {"S": (94, 132), "E": (96, 143), "W": (97, 154),
                               "w1": 9, "w2": 8, "pole": (1.0, 0.35)}},
            "up": {"right": {"S": (80, 140), "E": (82, 150), "W": (83, 159),
                             "w1": 8, "w2": 7, "pole": (1.0, 0.35)}},
            "left": {"near": {"S": (68, 125), "E": (62, 142), "W": (58, 152),
                              "w1": 9, "w2": 8, "pole": (1.0, 0.35)}},
            "right": {"near": {"S": (75, 125), "E": (81, 142), "W": (85, 152),
                               "w1": 9, "w2": 8, "pole": (-1.0, 0.35)}},
        },
    },
    "eclipse": {
        "cutline": 160,
        "arms": {
            "down": {
                "right": {"S": (94, 132), "E": (96, 143), "W": (97, 154),
                          "w1": 9, "w2": 8, "pole": (1.0, 0.35)},
                "left": {"S": (50, 132), "E": (48, 143), "W": (47, 154),
                         "w1": 9, "w2": 8, "pole": (-1.0, 0.35)},
            },
            "up": {
                "right": {"S": (98, 140), "E": (101, 148), "W": (103, 156),
                          "w1": 7, "w2": 7, "pole": (1.0, 0.35)},
                "left": {"S": (46, 140), "E": (43, 148), "W": (41, 156),
                         "w1": 7, "w2": 7, "pole": (-1.0, 0.35)},
            },
            "left": {
                "near": {"S": (62, 132), "E": (62, 142), "W": (60, 152),
                         "w1": 9, "w2": 8, "pole": (1.0, 0.35)},
            },
            "right": {
                "near": {"S": (81, 132), "E": (81, 142), "W": (83, 152),
                         "w1": 9, "w2": 8, "pole": (-1.0, 0.35)},
            },
        },
    },
    "sage": {
        "cutline": 160,
        "arms": {
            "down": {"right": {"S": (92, 130), "E": (94, 142), "W": (96, 154),
                               "w1": 10, "w2": 9, "pole": (1.0, 0.35)}},
            "up": {"right": {"S": (92, 130), "E": (94, 142), "W": (96, 154),
                             "w1": 10, "w2": 9, "pole": (1.0, 0.35)}},
            "left": {"near": {"S": (62, 130), "E": (59, 142), "W": (56, 152),
                              "w1": 10, "w2": 9, "pole": (1.0, 0.35)}},
            "right": {"near": {"S": (81, 130), "E": (84, 142), "W": (87, 152),
                               "w1": 10, "w2": 9, "pole": (-1.0, 0.35)}},
        },
    },
}


# Static grips: hands that hold a bracing weapon without moving
# (torso space). The torso bake keeps their paint; the runtime seats the fang
# exactly on them, so hand and grip can never separate. In the donor side
# profile the far hand hides behind the dress, so the grip seats the brace
# fang on the dress hip where that hand holds it low; right mirrors left.
STATIC_GRIPS = {
    "dancer": {"left": {"far": (75, 158)}, "right": {"far": (68, 158)}},
}

# Mask-only erasures: (x, y, radius) paint removed from the torso bake with
# no patches cut. The turnaround side profile showed Eclipse's far hand at
# its hip, which the bake used to clear for the haft; the donor side profile
# hides that hand, so nothing is erased and the stacked nub rides the main
# grip alone.
ERASE: dict = {}


def dist(a, b) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def clamp_to_reach(s, w, l1, l2):
    """Clamp a wrist target into the honest reach annulus (safety net)."""
    d = dist(s, w)
    lo, hi = abs(l1 - l2) + 1.0, l1 + l2
    if d < 1e-6:
        return (s[0] + lo, s[1])
    if d < lo or d > hi:
        c = min(max(d, lo), hi) / d
        return (s[0] + (w[0] - s[0]) * c, s[1] + (w[1] - s[1]) * c)
    return w


def solve_elbow(s, w, l1, l2, pole):
    """Two-bone IK elbow: the solution bowing toward `pole` (or None)."""
    d = dist(s, w)
    if d < 1e-6 or d > l1 + l2 + 1e-6:
        return None
    d = min(max(d, abs(l1 - l2) + 1e-6), l1 + l2)
    ux, uy = (w[0] - s[0]) / dist(s, w), (w[1] - s[1]) / dist(s, w)
    a = (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
    h2 = max(l1 * l1 - a * a, 0.0)
    h = math.sqrt(h2)
    mx, my = s[0] + ux * a, s[1] + uy * a
    px, py = -uy, ux
    e1 = (mx + px * h, my + py * h)
    e2 = (mx - px * h, my - py * h)
    s1 = (e1[0] - s[0]) * pole[0] + (e1[1] - s[1]) * pole[1]
    s2 = (e2[0] - s[0]) * pole[0] + (e2[1] - s[1]) * pole[1]
    return e1 if s1 >= s2 else e2


def capsule_mask(w, h, a, b, radius):
    """Boolean mask of the capsule around segment a-b."""
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    d.line([a, b], fill=255, width=int(radius * 2))
    d.ellipse([a[0] - radius, a[1] - radius, a[0] + radius, a[1] + radius],
              fill=255)
    d.ellipse([b[0] - radius, b[1] - radius, b[0] + radius, b[1] + radius],
              fill=255)
    return img


def check_spec() -> list:
    """Pole/reach self-check: IK at the rest wrist must find the elbow."""
    errors = []
    for hero in HEROES:
        for facing, arms in SPEC[hero]["arms"].items():
            for side, arm in arms.items():
                s, e, wv = arm["S"], arm["E"], arm["W"]
                l1, l2 = dist(s, e), dist(e, wv)
                if dist(s, wv) > l1 + l2 + 1e-6:
                    errors.append(f"{hero}/{facing}/{side}: rest overextended")
                    continue
                got = solve_elbow(s, wv, l1, l2, arm["pole"])
                if got is None or dist(got, e) > 1.0:
                    errors.append(
                        f"{hero}/{facing}/{side}: pole misses elbow "
                        f"(want {e}, got {got})")
    return errors


def inpaint_nearest(cell: Image.Image, mask: Image.Image) -> Image.Image:
    """Fill masked opaque paint with its nearest surviving neighbor (RGBA).

    Multi-source BFS from every unmasked pixel; each masked pixel takes the
    full RGBA of the nearest unmasked pixel, so paint continues and silhouette
    edges stay transparent instead of bloating.
    """
    w, h = cell.size
    src = cell.load()
    msk = mask.load()
    out = cell.copy()
    dst = out.load()
    owner_x = [[-1] * w for _ in range(h)]
    owner_y = [[-1] * w for _ in range(h)]
    queue: deque = deque()
    for y in range(h):
        for x in range(w):
            if msk[x, y] == 0:
                owner_x[y][x] = x
                owner_y[y][x] = y
                queue.append((x, y))
    while queue:
        x, y = queue.popleft()
        ox, oy = owner_x[y][x], owner_y[y][x]
        if msk[x, y] != 0 and src[x, y][3] > 8:
            dst[x, y] = src[ox, oy]
        if msk[x, y] != 0:
            pass
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h and owner_x[ny][nx] < 0:
                owner_x[ny][nx] = ox
                owner_y[ny][nx] = oy
                queue.append((nx, ny))
    return out


def feather(patch: Image.Image) -> Image.Image:
    """Soften cut edges by one pixel; the painted outer silhouette keeps."""
    from PIL import ImageFilter

    alpha = patch.getchannel("A").filter(ImageFilter.GaussianBlur(1.0))
    out = patch.copy()
    out.putalpha(alpha)
    return out


def cut_patch(cell: Image.Image, mask: Image.Image):
    """Tight RGBA crop of the masked paint plus its top-left bbox origin."""
    bbox = mask.getbbox()
    if bbox is None:
        raise ValueError("empty arm patch")
    patch = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    patch.paste(cell, (0, 0), mask)
    return feather(patch.crop(bbox)), bbox


def hand_color(cell: Image.Image, w) -> tuple:
    """Median opaque color in a 3px radius around the wrist for tests."""
    px = cell.load()
    samples = []
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            x, y = w[0] + dx, w[1] + dy
            if 0 <= x < CELL_W and 0 <= y < CELL_H and px[x, y][3] > 8:
                samples.append(px[x, y][:3])
    if not samples:
        return (0, 0, 0)
    samples.sort()
    return samples[len(samples) // 2]


def png_bytes(img: Image.Image) -> bytes:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return buf.getvalue()


def bake_hero(hero: str):
    """Bake one hero: torso strips, arm patches, and rig geometry."""
    idle = Image.open(
        GAME / f"assets/custom/actors/heroes/{hero}/idle.png").convert("RGBA")
    outputs: dict = {}
    rig = {"cutline": SPEC[hero]["cutline"], "overlap": OVERLAP, "facings": {}}
    for col, facing in enumerate(FACINGS):
        cell = idle.crop((col * CELL_W, 0, col * CELL_W + CELL_W, CELL_H))
        arms = SPEC[hero]["arms"][facing]
        union = Image.new("L", (CELL_W, CELL_H), 0)
        upper_masks, fore_masks = {}, {}
        for side, arm in arms.items():
            s, e, wv = arm["S"], arm["E"], arm["W"]
            upper = capsule_mask(CELL_W, CELL_H, s, e, arm["w1"] / 2.0 + 1.0)
            fore = capsule_mask(CELL_W, CELL_H, e, wv, arm["w2"] / 2.0 + 1.0)
            upper_masks[side] = upper
            fore_masks[side] = fore
            for m in (upper, fore):
                union = Image.frombytes(
                    "L", union.size,
                    bytes(a | b for a, b in zip(union.tobytes(),
                                                m.tobytes())))
        torso_full = inpaint_nearest(cell, union)
        cutline = SPEC[hero]["cutline"]
        torso = torso_full.crop((0, 0, CELL_W, cutline + OVERLAP))
        outputs[f"torso_{facing}.png"] = png_bytes(torso)
        entry = {"torso": f"torso_{facing}.png", "arms": {}}
        patches = {}
        for side, arm in arms.items():
            s, e, wv = arm["S"], arm["E"], arm["W"]
            upper_patch, upper_bbox = cut_patch(cell, upper_masks[side])
            fore_patch, fore_bbox = cut_patch(cell, fore_masks[side])
            upper_name = f"arm_{facing}_{side}_upper.png"
            fore_name = f"arm_{facing}_{side}_fore.png"
            outputs[upper_name] = png_bytes(upper_patch)
            outputs[fore_name] = png_bytes(fore_patch)
            patches[side] = (upper_patch, fore_patch)
            entry["arms"][side] = {
                "S": list(s), "E": list(e), "W": list(wv),
                "L1": dist(s, e), "L2": dist(e, wv),
                "pole": list(arm["pole"]),
                "upper": {"file": upper_name, "bbox": list(upper_bbox),
                          "pivot": [s[0] - upper_bbox[0], s[1] - upper_bbox[1]]},
                "fore": {"file": fore_name, "bbox": list(fore_bbox),
                         "pivot": [e[0] - fore_bbox[0], e[1] - fore_bbox[1]]},
                "hand": list(hand_color(cell, wv)),
            }
        for (ex, ey, er) in ERASE.get(hero, {}).get(facing, []):
            disc = Image.new("L", (CELL_W, CELL_H), 0)
            ImageDraw.Draw(disc).ellipse([ex - er, ey - er, ex + er, ey + er],
                                         fill=255)
            union = Image.frombytes(
                "L", union.size,
                bytes(a | b for a, b in zip(union.tobytes(), disc.tobytes())))
            torso_full = inpaint_nearest(cell, union)
            torso = torso_full.crop((0, 0, CELL_W, cutline + OVERLAP))
            outputs[f"torso_{facing}.png"] = png_bytes(torso)
        if hero == "dancer" and facing in ("left", "right"):
            # The far hand is real paint holding the bracing fang low. The
            # torso keeps it; the grip below seats the fang exactly on it.
            entry["static_grips"] = {
                name: list(pt)
                for name, pt in STATIC_GRIPS[hero][facing].items()
            }
        if hero == "eclipse" and facing in ("left", "right"):
            near = arms["near"]
            upper_patch = patches["near"][0]
            cuff = median_color(upper_patch)
            mitt = hand_color(cell, near["W"])
            rim = darkest_color(upper_patch)
            # Off hand stacks on the main grip (the reaper's haft passes
            # through both). Runtime tracks the main wrist; no float. The
            # real far hand is erased above: it left the hip for the haft.
            nub = bake_nub("stacked", cuff, mitt, rim, mirror=False)
            name = f"nub_{facing}_off.png"
            outputs[name] = png_bytes(nub)
            entry["nub_off"] = {"file": name, "stack": [0, 3], "grip": [4, 1]}
        vacated = union.getbbox()
        entry["vacated"] = list(vacated) if vacated else [0, 0, 0, 0]
        rig["facings"][facing] = entry
    outputs["rig.json"] = (json.dumps(rig, indent="\t",
                                      sort_keys=True) + "\n").encode("utf-8")
    return outputs


def median_color(img: Image.Image):
    px = [p[:3] for p in img.getdata() if p[3] > 8]
    if not px:
        return (0, 0, 0)
    px.sort()
    return px[len(px) // 2]


def darkest_color(img: Image.Image):
    px = [p[:3] for p in img.getdata() if p[3] > 8]
    if not px:
        return (20, 16, 24)
    return min(px, key=lambda c: c[0] + c[1] + c[2])


def outline_shape(shape_mask: Image.Image, fill, outline):
    """Fill + 1px dark rim from a mask (deterministic authored pixels)."""
    from PIL import ImageFilter

    grown = shape_mask.filter(ImageFilter.MaxFilter(3))
    rim = Image.new("L", shape_mask.size, 0)
    rim.paste(grown, (0, 0), grown)
    # rim minus shape: use point ops for determinism
    rm = rim.load()
    sm = shape_mask.load()
    out = Image.new("RGBA", shape_mask.size, (0, 0, 0, 0))
    op = out.load()
    for y in range(shape_mask.height):
        for x in range(shape_mask.width):
            if sm[x, y] > 0:
                op[x, y] = fill + (255,)
            elif rm[x, y] > 0:
                op[x, y] = outline + (255,)
    return out


def bake_nub(kind: str, cuff: tuple, mitt: tuple, rim: tuple,
             mirror: bool) -> Image.Image:
    """Authored far/off-hand nub: mitt plus cuff toward the body.

    Side views show a single near arm, so the second hand is a small painted
    nub in colors sampled from that same hero's near arm: no primitive shapes
    reach the game, and the template is fixed so `--check` holds it stable.
    """
    canvas = Image.new("L", (8, 8), 0)
    d = ImageDraw.Draw(canvas)
    d.ellipse([1, 1, 7, 7], fill=255)
    return feather(outline_shape(canvas, mitt, rim))


def rig_dir(hero: str) -> Path:
    return GAME / f"assets/custom/actors/heroes/{hero}/rig"


# Preview-only mirror of the runtime pose math (ArmRig + attack timelines).
# Constants match the GDScript side; the runtime tests pin those values.
FACING_VEC = {"down": (0.0, 1.0), "up": (0.0, -1.0), "left": (-1.0, 0.0),
              "right": (1.0, 0.0)}
AIM_ANGLE = {"down": math.pi / 2, "up": -math.pi / 2, "left": math.pi,
             "right": 0.0}
ARM_SWING = {"warden": 35.0, "dancer": 30.0, "eclipse": 35.0}
BLADE_TRAVEL = {"warden": 100.0, "dancer": 75.0, "eclipse": 135.0}
GUN_SLIDE_WORLD = {"keeper": 2.0, "knight": 2.5, "sage": 1.8}
GUN_PITCH = {"keeper": -0.14, "knight": -0.21, "sage": 0.07}
TORSO_LUNGE = 3.0
TORSO_KICK = 4.0
BODY_SCALE = 0.255
# Frozen WeaponRig logical geometry (preview coupling; runtime tests pin it).
WEAPON_PIVOT = {"warden": (4.0, 2.0), "dancer": (1.0, 4.0),
                "keeper": (4.0, 2.0), "knight": (4.0, 2.0),
                "eclipse": (2.0, 6.0), "sage": (4.0, 2.0)}
WEAPON_TIP = {"warden": (16.0, 2.0), "dancer": (13.0, 4.0),
              "keeper": (13.0, 2.0), "knight": (13.0, 2.0),
              "eclipse": (15.0, 5.0), "sage": (20.0, 2.0)}
DANCER_HALF = {"upper": {"rect": (0, 0, 60, 19), "pivot": (1.0, 2.5)},
               "lower": {"rect": (0, 17, 60, 19), "pivot": (1.0, 5.5)}}


def _smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def _env(p, peak):
    if p <= 0.0 or p >= 1.0:
        return 0.0
    return min(_smoothstep(0.0, peak, p), 1.0 - _smoothstep(peak, 1.0, p))


def _rot(v, deg):
    r = math.radians(deg)
    c, s = math.cos(r), math.sin(r)
    return (v[0] * c - v[1] * s, v[0] * s + v[1] * c)


def _pose_preview_actions(hero, facing):
    """(variant, sign, cutter-side, brace-side-or-None) per preview row."""
    if hero == "dancer":
        if facing in ("down", "up"):
            return [(0, 1.0, "right", "left"), (1, -1.0, "left", "right")]
        return [(0, 1.0, "near", "far"), (1, -1.0, "near", "far")]
    if hero == "eclipse" and facing in ("down", "up"):
        return [(0, 1.0, "right", "left")]
    if hero == "eclipse":
        return [(0, 1.0, "near", "off")]
    side = "right" if facing in ("down", "up") else "near"
    return [(0, 1.0, side, None)]


def _rotate_about(img, pivot, degrees):
    return img.rotate(-degrees, resample=Image.BICUBIC, center=tuple(pivot))


def _draw_weapon_preview(canvas, hero, wrist, aim_angle, extra_angle,
                         mirror_y, half=None):
    sheet = Image.open(
        GAME / f"assets/custom/items/weapons/{hero}.png").convert("RGBA")
    if half is not None:
        spec = DANCER_HALF[half]
        x0, y0, w, h = spec["rect"]
        sheet = sheet.crop((x0, y0, x0 + w, y0 + h))
        pivot = (spec["pivot"][0] * 4 - x0, spec["pivot"][1] * 4 - y0)
    else:
        pivot = (WEAPON_PIVOT[hero][0] * 4, WEAPON_PIVOT[hero][1] * 4)
    if mirror_y:
        sheet = sheet.transpose(Image.FLIP_TOP_BOTTOM)
        pivot = (pivot[0], sheet.height - pivot[1])
    sheet = _rotate_about(sheet, pivot, math.degrees(aim_angle + extra_angle))
    scale = 0.25 / BODY_SCALE
    sheet = sheet.resize((max(int(sheet.width * scale), 1),
                          max(int(sheet.height * scale), 1)), Image.BICUBIC)
    px = wrist[0] - pivot[0] * scale
    py = wrist[1] - pivot[1] * scale
    canvas.paste(sheet, (int(round(px)), int(round(py))), sheet)


def _composite_pose(hero, facing, progress, variant, sign, cutter, brace):
    """Full attack composite at one progress point (preview mirror)."""
    col = FACINGS.index(facing)
    idle = Image.open(
        GAME / f"assets/custom/actors/heroes/{hero}/idle.png").convert("RGBA")
    cell = idle.crop((col * CELL_W, 0, col * CELL_W + CELL_W, CELL_H))
    rig = json.loads((rig_dir(hero) / "rig.json").read_bytes())
    cutline = rig["cutline"]
    facing_entry = rig["facings"][facing]
    melee = hero in ("warden", "dancer", "eclipse")
    fv = FACING_VEC[facing]
    if melee:
        shift = (fv[0] * TORSO_LUNGE * _env(progress, 0.35),
                 fv[1] * TORSO_LUNGE * _env(progress, 0.35))
    else:
        shift = (-fv[0] * TORSO_KICK * _env(progress, 0.22),
                 -fv[1] * TORSO_KICK * _env(progress, 0.22))
    canvas = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    canvas.paste(cell.crop((0, cutline, CELL_W, CELL_H)), (0, cutline))
    if brace == "far" and "nub_far" in facing_entry:
        nub = Image.open(rig_dir(hero) / facing_entry["nub_far"]["file"])
        rest = facing_entry["nub_far"]["rest"]
        grip = facing_entry["nub_far"]["grip"]
        canvas.paste(nub, (int(rest[0] - grip[0]), int(rest[1] - grip[1])), nub)
    torso = Image.open(rig_dir(hero) / facing_entry["torso"])
    canvas.paste(torso, (int(round(shift[0])), int(round(shift[1]))), torso)
    wrists = {}

    def pose_arm(side, theta_deg=None, static=False, target=None):
        arm = facing_entry["arms"][side]
        s = tuple(arm["S"])
        w0 = tuple(arm["W"])
        if static or target is None:
            w = w0 if static else tuple(target)
        else:
            w = tuple(target)
        e = solve_elbow(s, w, arm["L1"], arm["L2"], tuple(arm["pole"]))
        upper = Image.open(rig_dir(hero) / arm["upper"]["file"])
        fore = Image.open(rig_dir(hero) / arm["fore"]["file"])
        upiv = tuple(arm["upper"]["pivot"])
        fpiv = tuple(arm["fore"]["pivot"])
        e0 = tuple(arm["E"])
        a0 = math.degrees(math.atan2(e0[1] - s[1], e0[0] - s[0]))
        a1 = math.degrees(math.atan2(e[1] - s[1], e[0] - s[0]))
        upper_r = _rotate_about(upper, upiv, a1 - a0)
        canvas.paste(upper_r,
                     (int(round(s[0] + shift[0] - upiv[0])),
                      int(round(s[1] + shift[1] - upiv[1]))), upper_r)
        b0 = math.degrees(math.atan2(w0[1] - e0[1], w0[0] - e0[0]))
        b1 = math.degrees(math.atan2(w[1] - e[1], w[0] - e[0]))
        fore_r = _rotate_about(fore, fpiv, b1 - b0)
        canvas.paste(fore_r,
                     (int(round(e[0] + shift[0] - fpiv[0])),
                      int(round(e[1] + shift[1] - fpiv[1]))), fore_r)
        wrists[side] = (w[0] + shift[0], w[1] + shift[1])
        return wrists[side]

    aim = AIM_ANGLE[facing]
    mirror = fv[0] < 0.0
    if melee:
        theta = ARM_SWING[hero] * _env(progress, 0.35) * sign
        blade = math.radians(BLADE_TRAVEL[hero]) * _env(progress, 0.40) * sign
        main = facing_entry["arms"][cutter]
        s = tuple(main["S"])
        w0 = tuple(main["W"])
        rel = (w0[0] - s[0], w0[1] - s[1])
        w = (s[0] + _rot(rel, theta)[0], s[1] + _rot(rel, theta)[1])
        main_wrist = pose_arm(cutter, target=w)
        if hero == "dancer":
            # The bracing fang rests pointing down (never hidden against the
            # torso), while the cutter sweeps along the aim.
            if brace == "far":
                grip = tuple(facing_entry["static_grips"]["far"])
                brace_wrist = (grip[0] + shift[0], grip[1] + shift[1])
                _draw_weapon_preview(canvas, hero, brace_wrist,
                                     math.pi / 2, 0.0, False, half="lower")
            else:
                brace_wrist = pose_arm(brace, static=True)
                brace_half = "lower" if cutter == "right" else "upper"
                _draw_weapon_preview(canvas, hero, brace_wrist,
                                     math.pi / 2, 0.0, False, half=brace_half)
            # Side views always sweep the upper fang; down/up sweep the
            # cutter's own fang (right=upper, left=lower).
            if facing in ("down", "up"):
                cut_half = "upper" if cutter == "right" else "lower"
            else:
                cut_half = "upper"
            _draw_weapon_preview(canvas, hero, main_wrist, aim, blade,
                                 mirror, half=cut_half)
        elif hero == "eclipse" and brace == "off":
            nub = Image.open(rig_dir(hero) / facing_entry["nub_off"]["file"])
            stack = facing_entry["nub_off"]["stack"]
            grip = facing_entry["nub_off"]["grip"]
            canvas.paste(nub,
                         (int(round(main_wrist[0] + stack[0] - grip[0])),
                          int(round(main_wrist[1] + stack[1] - grip[1]))), nub)
            _draw_weapon_preview(canvas, hero, main_wrist, aim, blade, mirror)
        else:
            if brace is not None:
                # Mirrored off-arm sweep shares the cutter timeline.
                off = facing_entry["arms"][brace]
                os_ = tuple(off["S"])
                ow0 = tuple(off["W"])
                orel = (ow0[0] - os_[0], ow0[1] - os_[1])
                ow = (os_[0] + _rot(orel, theta)[0],
                      os_[1] + _rot(orel, theta)[1])
                pose_arm(brace, target=ow)
            _draw_weapon_preview(canvas, hero, main_wrist, aim, blade, mirror)
    else:
        slide = GUN_SLIDE_WORLD[hero] / BODY_SCALE * _env(progress, 0.22)
        pitch = GUN_PITCH[hero] * _env(progress, 0.26)
        main = facing_entry["arms"][cutter]
        w0 = tuple(main["W"])
        s = tuple(main["S"])
        if facing == "up":
            # The arm hangs straight down, so a straight kick would extend
            # past the elbow: bow outward instead while the torso takes it.
            bow = (main["pole"][0] * 2.0, 0.5)
            e = _env(progress, 0.22)
            w = (w0[0] + bow[0] * e, w0[1] + bow[1] * e)
        else:
            w = (w0[0] - fv[0] * slide, w0[1] - fv[1] * slide)
        w = clamp_to_reach(s, w, main["L1"], main["L2"])
        main_wrist = pose_arm(cutter, target=w)
        _draw_weapon_preview(canvas, hero, main_wrist, aim, pitch, mirror)
    return canvas


def cmd_preview_pose(path: str) -> int:
    errors = check_spec()
    if errors:
        for line in errors:
            print("spec error:", line)
        return 1
    root = Path(path)
    root.mkdir(parents=True, exist_ok=True)
    for hero in HEROES:
        rows = []
        for facing in FACINGS:
            for (variant, sign, cutter, brace) in _pose_preview_actions(
                    hero, facing):
                contact = _composite_pose(hero, facing, 0.0, variant, sign,
                                          cutter, brace)
                peak = _composite_pose(hero, facing, 0.375, variant, sign,
                                       cutter, brace)
                rows.append((f"{facing} v{variant}", contact, peak))
        sheet = Image.new("RGBA", (CELL_W * 2 * 2 + 130, 0), (0, 0, 0, 0))
        rh = CELL_H * 2 + 16
        sheet = Image.new("RGBA", (CELL_W * 4 + 130, rh * len(rows) + 10),
                          (24, 24, 40, 255))
        d = ImageDraw.Draw(sheet)
        y = 5
        for label, contact, peak in rows:
            d.text((5, y), f"{hero} {label}: contact | peak",
                   fill=(255, 255, 255, 255))
            y += 14
            pair = Image.new("RGBA", (CELL_W * 2, CELL_H), (0, 0, 0, 0))
            pair.paste(contact, (0, 0), contact)
            pair.paste(peak, (CELL_W, 0), peak)
            sheet.paste(pair.resize((CELL_W * 4, CELL_H * 2), Image.NEAREST),
                        (120, y))
            y += CELL_H * 2 + 4
        sheet.save(root / f"{hero}_posed.png")
    print(f"posed previews in {root}")
    return 0


def cmd_check() -> int:
    errors = check_spec()
    if errors:
        for line in errors:
            print("spec error:", line)
        return 1
    failures = 0
    total = 0
    for hero in HEROES:
        want = bake_hero(hero)
        for name, data in sorted(want.items()):
            total += 1
            path = rig_dir(hero) / name
            if not path.exists() or path.read_bytes() != data:
                print(f"stale: {hero}/rig/{name}")
                failures += 1
    if failures:
        print(f"attack rig check failed — {failures}/{total} stale")
        return 1
    print(f"attack rig check passed — {total} outputs current (byte-verified)")
    return 0


def cmd_bake() -> int:
    errors = check_spec()
    if errors:
        for line in errors:
            print("spec error:", line)
        return 1
    total = 0
    for hero in HEROES:
        out = rig_dir(hero)
        out.mkdir(parents=True, exist_ok=True)
        for name, data in sorted(bake_hero(hero).items()):
            (out / name).write_bytes(data)
            total += 1
    print(f"attack rig baked: {total} outputs")
    return 0


def cmd_preview(path: str) -> int:
    """Calibration preview: markers, capsules, and inpaint per facing."""
    errors = check_spec()
    if errors:
        for line in errors:
            print("spec error:", line)
        return 1
    root = Path(path)
    root.mkdir(parents=True, exist_ok=True)
    for hero in HEROES:
        idle = Image.open(
            GAME / f"assets/custom/actors/heroes/{hero}/idle.png"
        ).convert("RGBA")
        sheet = Image.new("RGBA", (CELL_W * 2 * 4 + 40, CELL_H + 30),
                          (24, 24, 40, 255))
        d_all = ImageDraw.Draw(sheet)
        for col, facing in enumerate(FACINGS):
            cell = idle.crop(
                (col * CELL_W, 0, col * CELL_W + CELL_W, CELL_H)).copy()
            arms = SPEC[hero]["arms"][facing]
            union = Image.new("L", (CELL_W, CELL_H), 0)
            for side, arm in arms.items():
                s, e, wv = arm["S"], arm["E"], arm["W"]
                for m in (capsule_mask(CELL_W, CELL_H, s, e,
                                       arm["w1"] / 2.0 + 1.0),
                          capsule_mask(CELL_W, CELL_H, e, wv,
                                       arm["w2"] / 2.0 + 1.0)):
                    union = Image.frombytes(
                        "L", union.size,
                        bytes(a | b for a, b in zip(union.tobytes(),
                                                    m.tobytes())))
            inpainted = inpaint_nearest(cell, union)
            combo = Image.new("RGBA", (CELL_W * 2, CELL_H), (0, 0, 0, 0))
            combo.paste(cell, (0, 0), cell)
            combo.paste(inpainted, (CELL_W, 0), inpainted)
            d = ImageDraw.Draw(combo)
            for side, arm in arms.items():
                s, e, wv = arm["S"], arm["E"], arm["W"]
                for ox in (0, CELL_W):
                    for pt, color in ((s, (255, 0, 0)), (e, (0, 255, 0)),
                                      (wv, (255, 255, 0))):
                        d.ellipse([ox + pt[0] - 2, pt[1] - 2, ox + pt[0] + 2,
                                   pt[1] + 2], outline=color, width=1)
            sheet.paste(combo, (col * CELL_W * 2 + 30, 20), combo)
            d_all.text((col * CELL_W * 2 + 30, 4), f"{hero} {facing}",
                       fill=(255, 255, 255, 255))
        sheet.save(root / f"{hero}_cal.png")
    print(f"attack rig previews in {root}")
    return 0


def main(argv: list) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--preview", metavar="DIR", default=None)
    parser.add_argument("--preview-pose", metavar="DIR", default=None)
    args = parser.parse_args(argv)
    if args.preview is not None:
        return cmd_preview(args.preview)
    if getattr(args, "preview_pose") is not None:
        return cmd_preview_pose(getattr(args, "preview_pose"))
    if args.check:
        return cmd_check()
    return cmd_bake()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
