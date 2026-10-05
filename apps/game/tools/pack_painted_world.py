#!/usr/bin/env python3
"""Pack the 4.0.0 painted masters into high-resolution runtime art.

Sources are the original generated turnaround atlases in
``notes/workflow/muse/art/4-0-0/`` (tracked in git, read-only here): six
``<hero>-turnaround.png`` sheets (columns down/up/left/right, rows are four
walk frames), ``gait/<hero>-sidewalk-v2.png`` side-walk donor strips (four
left-facing cells: contact, recover, opposite contact, recover),
``spirit-turnarounds.png`` (seven species rows, four direction
columns), ``guardian-states.png`` (six species rows, idle/windup/charge/recover
columns), ``biome-props.png`` (six biome rows of four obstacle props) and
``biome-floors.png`` (six ground panels).

Every runtime sheet keeps its production path and layout, at 3x the legacy
pixelart pixel size, so ``visual_scale``/``art_zoom`` metadata in the resources
renders the same world footprint with smooth filtering:

    heroes    walk/idle 576x768 (144x192 cells, 4 dirs x 4 frames), portrait 96x96
    spirits   576x576 (144 cells, 4 dirs x 4 frames)
    guardians idle 1152x192 (6 frames), states 768x192 (4 frames), 192 cells
    obstacles <biome>_props.png 768x192 (4x 192 cells, feet at sheet y=150)
    scatter   <biome>_nature.png 1152x1008 (Room.KIND rects x3)
    props     field.png 240x720, camp.png 1104x432 (Room.PROP_KIND rects x3)
    floors    forest_floor + ground_<biome> 512x512 tileable panels

Single-pose sources (spirits, guardian states) get light feet-planted
breathing baked as frames; hero idle breathes through the torso band only,
so its head and soles never move. Nothing here mirrors a front view into
a back view. The swarm's side columns ship swapped in the master, so the pack
swaps them back (see SPECIES_SIDES).

    python3 apps/game/tools/pack_painted_world.py           # bake
    python3 apps/game/tools/pack_painted_world.py --check   # is current
    python3 apps/game/tools/pack_painted_world.py --report  # dims/bytes table

``--check`` byte-verifies against a fresh bake when the masters are present and
always validates the committed files structurally (sizes, grids, ink, padding).

Runtime layout contract (world units stay legacy; sheet pixels are x3):

    heroes    columns down/up/left/right, 4 walk-frame rows; solid soles
              planted on the cell bottom edge (y=192), as the legacy 64px
              cells. Walk side columns are donor-registered (left) and its
              exact mirror (right); portraits and down/up walk stay on the
              turnaround masters. Idle shares the walk head per facing:
              down/up rest on their walk row 0, sides on the donor contact
              with gathered standing legs (right mirrors left). Player and
              PlayerPreview read via Hero.cell/visual_scale
              (tests/test_hero_visuals.gd, test_hero_direction_capture.gd).
    spirits   columns down/up/left/right, 4 breath-frame rows; soles 18px
              above the cell foot. Spirit reads via SpiritKind.cell/
              visual_scale (tests/test_spirit_visuals.gd).
    guardians facing-less: idle 6 frames, windup/alt-windup/charge/recover 4.
              SpiritKind.guardian_*_sheet (tests/test_guardian_staging.gd).
    obstacles 4 cells of 192; feet at sheet y=150 (world y=50), collision from
              Room.OBSTACLE_RADII, never from the art.
    scatter   Room.KIND world rects x3; every tree above sheet row 384, rocks
              and stumps below (world_polish tree_rows_above).
    props     Room.PROP_KIND world rects x3; the camp beacon pit lives at camp
              sheet Rect2(576, 240, 96, 90) (scenes/objectives/beacon.tscn).
    floors    whole-texture tileable panels via RoomKind.floor_texture:
              atlas-cut edges healed, then symmetric linear-ramp matching
              (no crossfade bands; _check_floor_seams pins edges, seam-pair
              ranks and the four-edge-smoothing rule).

tests/test_painted_world.gd re-checks every rect above against the real
texture bounds, so a layout drift fails the suite, not just this tool.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageEnhance

from pack_attack_rig import SPEC as RIG_SPEC

TOOL_DIR = Path(__file__).resolve().parent
GAME_ROOT = TOOL_DIR.parent
REPO_ROOT = GAME_ROOT.parents[1]
SOURCE_ROOT = REPO_ROOT / "notes/workflow/muse/art/4-0-0"

HERO_ROOT = GAME_ROOT / "assets/custom/actors/heroes"
SPIRIT_ROOT = GAME_ROOT / "assets/custom/actors/spirits"
GUARDIAN_ROOT = GAME_ROOT / "assets/custom/actors/guardians"
TERRAIN_ROOT = GAME_ROOT / "assets/custom/world/terrain"

## Runtime pixels per legacy pixelart pixel. World footprints stay identical
## because resources carry visual_scale = 1/ZOOM (actors) or art_zoom = ZOOM.
ZOOM = 3

HEROES = ("warden", "dancer", "keeper", "knight", "eclipse", "sage")
## Source row order in spirit-turnarounds.png.
SPECIES = ("drifter", "ember", "caster", "weaver", "stalker", "swarm", "wisp")
## Source row order in guardian-states.png and biome-props.png.
BIOMES = ("forest", "field", "camp", "frost", "marsh", "ruins")
## Guardian idle/state columns in guardian-states.png.
STATES = ("idle", "windup", "charge", "recover")
## Variant of each base species: name suffix, grade key, breathing cycle offset.
VARIANTS: dict[str, tuple[str, str, int]] = {
    "forest": ("thorn", "thorn", 2),
    "field": ("storm", "storm", 3),
    "camp": ("siege", "siege", 1),
    "frost": ("rime", "rime", 4),
    "marsh": ("glow", "glow", 2),
    "ruins": ("halo", "halo", 5),
}
## Which state sheets each guardian file set carries (camp/ruins reuse windup
## for the charge slot, exactly like the legacy sheets).
GUARDIAN_FILES: dict[str, tuple[str, ...]] = {
    "forest": ("windup", "charge", "recover"),
    "forest_thorn": ("windup", "charge", "recover"),
    "field": ("windup_cross", "windup_radial", "recover"),
    "field_storm": ("windup_cross", "windup_radial", "recover"),
    "camp": ("windup", "recover"),
    "camp_siege": ("windup", "recover"),
    "frost": ("windup", "charge", "recover"),
    "frost_rime": ("windup", "charge", "recover"),
    "marsh": ("windup", "charge", "recover"),
    "marsh_glow": ("windup", "charge", "recover"),
    "ruins": ("windup", "recover"),
    "ruins_halo": ("windup", "recover"),
}

## Brief-131 side-walk donors: gait/<hero>-sidewalk-v2.png, each four
## LEFT-facing cells in contact / recover / opposite-contact / recover
## order. Runtime walk columns 2 (left) and 3 (right, exact mirror) come
## from these; idle, portraits and down/up walk columns stay on the
## turnaround masters.
GAIT_ROOT = SOURCE_ROOT / "gait"
GAIT_CELL_COUNT = 4
## Torso anchor: ink centroid-x of the top GAIT_TORSO_FRACTION of the
## solid mass (head, chest, hips; the striding legs excluded).
GAIT_TORSO_FRACTION = 0.40
## A boundary-crossing component this whole with its majority cell is one
## figure's boot tip or drapery, not two figures touching: keep it whole.
GAIT_WHOLE_SHARE = 0.90
## Core margin from a valley cut for the contact split (the 14px rule
## from _exact_cells, in one dimension).
GAIT_CORE_MARGIN = 14
## Crop bleed past a valley cut so wholly-assigned tips stay attached.
GAIT_BLEED = 32
## A detached blob this small, sitting past a cut in the bleed, is a
## severed neighbour tip rather than costume detail.
GAIT_FRAGMENT_SHARE = 0.02

HERO_CELL = (144, 192)
SPIRIT_CELL = 144
GUARDIAN_CELL = 192
OBSTACLE_CELL = 192
NATURE_SIZE = (1152, 1008)
FLOOR_SIZE = 512

## Alpha below this is gutter noise and is zeroed, so contract edge padding is
## exact and transparent gutters stay clean under linear filtering.
INK = 8
## Grid bleed kept around exact-grid crops so wingtips and flames that touch a
## master gridline are not clipped; intrusions from neighbours are erased by
## connectivity (see _erase_intrusions).
BLEED = 16
## A blob holding this share of a terrain cell's ink while sitting fully
## beside the figure (x-ranges disjoint) is a severed neighbour fragment, not
## detail: the confirmed intrusions hold 4.4-11% of their cells, specks stay
## far below and inside the figure's x-range.
SIDECAR_SHARE = 0.02

## Legacy world heights, times ZOOM. Heroes stood 36px tall in 64px cells with
## feet on the bottom edge; spirits used per-species heights with a 6px float
## gap; guardians fitted a 54px box with a 2px sole margin.
HERO_FIT_H = 36 * ZOOM
SPIRIT_FIT_H = {
    "wisp": 22 * ZOOM,
    "stalker": 24 * ZOOM,
    "swarm": 15 * ZOOM,
    "ember": 22 * ZOOM,
    "drifter": 22 * ZOOM,
    "weaver": 23 * ZOOM,
    "caster": 24 * ZOOM,
}
SPIRIT_SOLE = 6 * ZOOM
SPIRIT_BOB = (0, -3, 0, 3)
GUARDIAN_FIT = 54 * ZOOM
GUARDIAN_SOLE = 2 * ZOOM
GUARDIAN_IDLE_DY = (0, -3, -3, 0, 3, 3)
## Obstacle feet sit at world y=50 (sheet y=150); art above the feet fits a
## 150px-tall, 180px-wide box like the legacy footprint.
OBSTACLE_FEET = 50 * ZOOM
OBSTACLE_BOX = (60 * ZOOM, 50 * ZOOM)
## Hero idle breathing: the torso band alone scales vertically about the
## hips, so the head and the planted feet stay byte-identical across frames.
## Whole-body rescale is banned here: it enlarged the face every breath and
## popped the head at every walk→stop. Necks are the head-bottom rows read
## off the idle cells (chin/hood/hair end, face safely above); hips reuse the
## attack rig's own cutlines, the same anatomical line the torso strips use.
HERO_IDLE_NECK = {
    "warden": 130, "dancer": 130, "keeper": 128,
    "knight": 120, "eclipse": 126, "sage": 118,
}
HERO_IDLE_HIPS = {hero: RIG_SPEC[hero]["cutline"] for hero in HEROES}
HERO_IDLE_BREATH = (1.0, 1.02, 1.035, 1.02)
## Standing-stance surgery for the side idle (brief 186): the idle base is
## the walk donor's own contact frame, and the two planted legs rotate about
## near-cut pivots until the feet stand adjacent under the body. Cut rows sit
## just below the crotch while clearing every hand (keeper's glove hangs to
## y155, hence 157); the head and upper stay byte-identical to the walk
## frame, so stopping never changes the face. Right mirrors left exactly,
## like the walk columns.
HERO_STANCE_CUT = {
    "warden": 150, "dancer": 150, "keeper": 157,
    "knight": 150, "eclipse": 150, "sage": 150,
}
## Standing-stance targets: both legs hang vertically beneath the hips,
## with the feet landing overlapped in profile like real standing feet: the
## near boot slightly forward of the far boot, both under the torso. Each
## leg articulates in two rigid segments about its hip: the shin rotates to
## vertical while the boot below the ankle translates flat, so soles plant
## level instead of tilting onto their corners. STANCE_HALF is the foot
## center offset from the fitted cell middle (the stride torso anchor); the
## upper overlaps the hip joint by STANCE_OVERLAP rows, and shin and boot
## overlap across the ankle, so both joints hide inside the paint.
HERO_STANCE_CENTER = 72
HERO_STANCE_HALF = 5
HERO_STANCE_PIVOT_UP = 8
HERO_STANCE_OVERLAP = 6
HERO_STANCE_ANKLE = 181
## Front/back standing construction (brief 188): each down/up idle is built
## from its own walk row-0 leg, mirrored into a symmetric standing pair that
## descends from the hips with both boots planted. HERO_FRONT_HEM is the cut
## row per hero and facing (0 down, 1 up): below the garment hem, so the
## cloak/dress/coat stays intact above while the legs rebuild below. The leg
## is the planted boot column plus a small margin; everything planted outside
## the stance band (robe panels, cloak sides) and every lifted prop (hands,
## tassels, tabard and dress tips) stays where painted. HERO_FRONT_DISCARD
## names the only paint ever removed: inspected trailing-limb rectangles,
## clamped to below the hems (a smear-free replacement, not an erasure: a
## full mirrored leg takes the hidden limb's place).
HERO_FRONT_HEM = {
    "warden": {0: 170, 1: 172},
    "dancer": {0: 160, 1: 160},
    "keeper": {0: 172, 1: 172},
    "knight": {0: 172, 1: 172},
    "eclipse": {0: 178, 1: 178},
    "sage": {0: 176, 1: 178},
}
HERO_FRONT_DISCARD = {
    ("warden", 0): [(81, 170, 87, 182)],
    ("keeper", 0): [(54, 172, 71, 190)],
    ("keeper", 1): [(54, 172, 67, 190)],
}
HERO_FRONT_BAND = (52, 92)
HERO_FRONT_GAP = 4
HERO_FRONT_OVERLAP = 3
## Stance middle per cell, defaulting to the fitted cell middle. Warden's
## back cloak masses left of middle with a fold notch at x80-82, so her
## boots plant at 67, under the garment instead of the notch. Knight's back
## legs mass left with the cape split right, so his boots plant at 66.
HERO_FRONT_CENTER = {("warden", 1): 67, ("knight", 1): 66}
SPIRIT_BREATHES = (1.0, 1.012, 1.02, 1.012)
GUARDIAN_IDLE_SCALES = (1.0, 1.008, 1.012, 1.008, 1.0, 0.996)
GUARDIAN_STATE_SCALES = {
    "windup": (1.0, 1.02, 1.04, 1.03),
    "charge": (1.02, 1.045, 1.05, 1.03),
    "recover": (1.0, 0.995, 0.99, 0.995),
}
GUARDIAN_STATE_DY = {
    "windup": (0, -2, -4, -2),
    "charge": (2, 1, 1, 2),
    "recover": (2, 3, 3, 1),
}
## Recover reads as the armour-open moment: settle plus a slight dimming.
GUARDIAN_STATE_TINT = {
    "windup": (1.0, 1.02, 1.05, 1.03),
    "charge": (1.03, 1.05, 1.05, 1.03),
    "recover": (0.97, 0.94, 0.92, 0.95),
}


def _load_master(name: str) -> Image.Image:
    path = SOURCE_ROOT / name
    if not path.is_file():
        raise RuntimeError(f"painted master is missing: {path}")
    return Image.open(path).convert("RGBA")


def _scrub_alpha(art: Image.Image) -> Image.Image:
    """Zero gutter noise; keep every other alpha level graded and smooth."""
    alpha = art.getchannel("A").point(lambda v: 0 if v < INK else v)
    out = art.copy()
    out.putalpha(alpha)
    return out


def _ink_bbox(art: Image.Image) -> tuple[int, int, int, int] | None:
    alpha = art.getchannel("A").point(lambda v: 255 if v >= INK else 0)
    return alpha.getbbox()


def _flat_bytes(art: Image.Image) -> bytes:
    """RGBA bytes with fully transparent pixels zeroed, for comparison.

    Resizes and composites leave arbitrary RGB under alpha 0 (invisible,
    but byte-real), so two identical-looking cells compare unequal. Zero
    the RGB where alpha is 0 first; every visible pixel still compares.
    """
    raw = bytearray(art.tobytes())
    for index in range(3, len(raw), 4):
        if raw[index] == 0:
            raw[index - 3] = raw[index - 2] = raw[index - 1] = 0
    return bytes(raw)


def _erase_border_fragments(
    kept: Image.Image, master: Image.Image, columns: int, rows: int
) -> Image.Image:
    """Erase broken-off neighbour fragments inside a cell.

    Component assignment keeps disconnected blobs that sit fully inside a
    cell — usually the figure's own floaters. A small blob near the cell's
    gridline while the master holds neighbour ink just across it is a tail
    tip or wingtip broken off across the line, so it goes. Blobs the figure
    connects to, large floaters, and floaters with empty neighbourhood, stay.
    """
    width, height = kept.size
    cell_w, cell_h = width // columns, height // rows
    kept_alpha = kept.getchannel("A").load()
    master_alpha = master.getchannel("A").load()
    out = kept.copy()
    rgb = out.load()
    seen = bytearray(width * height)

    def neighbours_hold(x0: int, y0: int, x1: int, y1: int) -> bool:
        for y in range(max(0, y0), min(height, y1)):
            for x in range(max(0, x0), min(width, x1)):
                if master_alpha[x, y] >= INK:
                    return True
        return False

    for row in range(rows):
        for column in range(columns):
            x0, y0 = column * cell_w, row * cell_h
            # Components of this cell's kept ink, 8-connectivity. The largest
            # is the figure; the rest are floaters or broken-off fragments.
            blobs: list[list[tuple[int, int]]] = []
            for sy in range(y0, y0 + cell_h):
                for sx in range(x0, x0 + cell_w):
                    if kept_alpha[sx, sy] < INK or seen[sy * width + sx]:
                        continue
                    blob: list[tuple[int, int]] = []
                    stack = [(sx, sy)]
                    seen[sy * width + sx] = 1
                    while stack:
                        x, y = stack.pop()
                        blob.append((x, y))
                        for dx in (-1, 0, 1):
                            for dy in (-1, 0, 1):
                                nx, ny = x + dx, y + dy
                                if nx < x0 or ny < y0 \
                                        or nx >= x0 + cell_w \
                                        or ny >= y0 + cell_h:
                                    continue
                                if kept_alpha[nx, ny] < INK \
                                        or seen[ny * width + nx]:
                                    continue
                                seen[ny * width + nx] = 1
                                stack.append((nx, ny))
                    blobs.append(blob)
            if not blobs:
                continue
            main = max(range(len(blobs)), key=lambda i: len(blobs[i]))
            cell_ink = sum(len(blob) for blob in blobs)
            for index, blob in enumerate(blobs):
                if index == main or len(blob) > cell_ink * 0.03:
                    continue
                near: dict[str, list[int]] = {}
                for x, y in blob:
                    if x - x0 < 24 and column > 0:
                        near.setdefault("left", []).append(y)
                    if x0 + cell_w - 1 - x < 24 and column < columns - 1:
                        near.setdefault("right", []).append(y)
                    if y - y0 < 24 and row > 0:
                        near.setdefault("top", []).append(x)
                    if y0 + cell_h - 1 - y < 24 and row < rows - 1:
                        near.setdefault("bottom", []).append(x)
                if not near:
                    continue
                across = False
                for side, span in near.items():
                    lo, hi = min(span) - 6, max(span) + 7
                    if side == "left":
                        across = neighbours_hold(x0 - 4, lo, x0, hi)
                    elif side == "right":
                        across = neighbours_hold(
                            x0 + cell_w, lo, x0 + cell_w + 4, hi)
                    elif side == "top":
                        across = neighbours_hold(lo, y0 - 4, hi, y0)
                    else:
                        across = neighbours_hold(
                            lo, y0 + cell_h, hi, y0 + cell_h + 4)
                    if across:
                        break
                if across:
                    for x, y in blob:
                        rgb[x, y] = (0, 0, 0, 0)
    return out


def _erase_edge_strips(
    kept: Image.Image,
    label,
    parent,
    columns: int,
    rows: int,
    cell_w: int,
    cell_h: int,
    strip: int,
) -> Image.Image:
    """Erase small blobs detached in a cell's top/bottom edge strip.

    Only for grounded-prop masters: figures there are planted, so a blob
    floating free in the strip is the neighbouring row's base or crown broken
    off, never the figure's own detail. The figure itself (the largest blob)
    is exempt wherever it reaches.
    """
    width, height = kept.size
    kept_alpha = kept.getchannel("A").load()
    out = kept.copy()
    rgb = out.load()
    seen = bytearray(width * height)
    for row in range(rows):
        for column in range(columns):
            x0, y0 = column * cell_w, row * cell_h
            own = row * columns + column
            blobs: list[list[tuple[int, int]]] = []
            for sy in range(y0, y0 + cell_h):
                for sx in range(x0, x0 + cell_w):
                    index = sy * width + sx
                    if kept_alpha[sx, sy] < INK or seen[index]:
                        continue
                    if parent[index] < 0 or label[index] != own:
                        continue
                    blob: list[tuple[int, int]] = []
                    stack = [(sx, sy)]
                    seen[index] = 1
                    while stack:
                        x, y = stack.pop()
                        blob.append((x, y))
                        for dx in (-1, 0, 1):
                            for dy in (-1, 0, 1):
                                nx, ny = x + dx, y + dy
                                if nx < x0 or ny < y0 \
                                        or nx >= x0 + cell_w \
                                        or ny >= y0 + cell_h:
                                    continue
                                other = ny * width + nx
                                if kept_alpha[nx, ny] < INK \
                                        or seen[other]:
                                    continue
                                if parent[other] < 0 or label[other] != own:
                                    continue
                                seen[other] = 1
                                stack.append((nx, ny))
                    blobs.append(blob)
            if not blobs:
                continue
            main = max(range(len(blobs)), key=lambda i: len(blobs[i]))
            for index, blob in enumerate(blobs):
                if index == main:
                    continue
                topmost = min(y for _x, y in blob)
                bottommost = max(y for _x, y in blob)
                if topmost < y0 + strip or bottommost >= y0 + cell_h - strip:
                    for x, y in blob:
                        rgb[x, y] = (0, 0, 0, 0)
    return out


def _erase_severed_neighbours(
    kept: Image.Image,
    label,
    parent,
    majority: dict[int, int],
    columns: int,
    rows: int,
    cell_w: int,
    cell_h: int,
) -> Image.Image:
    """Erase neighbour lobes the contact split stranded on this side.

    When two figures touch across a gridline, the contact split gives each
    side its own half — but a neighbour's crown lobe reaching more than 14px
    past the line grows a core on this side, so the split strands it here as
    a blob detached from this cell's own figure: the little foliage rectangle
    beside the pine. Such a blob always touches the gridline it was severed
    at, and its master ink component belongs to the neighbour by mass, so
    both facts together identify it exactly. The figure itself (the largest
    blob) is exempt wherever it reaches; interior floaters (mushrooms, ground
    detail) never touch a line; and the figure's own protrusions across a
    line belong to its own component by mass. Only for grounded-prop masters.
    """
    width, height = kept.size
    kept_alpha = kept.getchannel("A").load()
    out = kept.copy()
    rgb = out.load()
    seen = bytearray(width * height)

    def find(node: int) -> int:
        root = node
        while parent[root] != root:
            root = parent[root]
        while parent[node] != root:
            parent[node], node = root, parent[node]
        return root

    for row in range(rows):
        for column in range(columns):
            x0, y0 = column * cell_w, row * cell_h
            own = row * columns + column
            blobs: list[list[tuple[int, int]]] = []
            for sy in range(y0, y0 + cell_h):
                for sx in range(x0, x0 + cell_w):
                    index = sy * width + sx
                    if kept_alpha[sx, sy] < INK or seen[index]:
                        continue
                    if parent[index] < 0 or label[index] != own:
                        continue
                    blob: list[tuple[int, int]] = []
                    stack = [(sx, sy)]
                    seen[index] = 1
                    while stack:
                        x, y = stack.pop()
                        blob.append((x, y))
                        for dx in (-1, 0, 1):
                            for dy in (-1, 0, 1):
                                nx, ny = x + dx, y + dy
                                if nx < x0 or ny < y0 \
                                        or nx >= x0 + cell_w \
                                        or ny >= y0 + cell_h:
                                    continue
                                other = ny * width + nx
                                if kept_alpha[nx, ny] < INK \
                                        or seen[other]:
                                    continue
                                if parent[other] < 0 or label[other] != own:
                                    continue
                                seen[other] = 1
                                stack.append((nx, ny))
                    blobs.append(blob)
            if not blobs:
                continue
            main = max(range(len(blobs)), key=lambda i: len(blobs[i]))
            for index, blob in enumerate(blobs):
                if index == main:
                    continue
                touches = (
                    (min(x for x, _y in blob) == x0 and column > 0)
                    or (max(x for x, _y in blob) == x0 + cell_w - 1
                        and column < columns - 1)
                    or (min(y for _x, y in blob) == y0 and row > 0)
                    or (max(y for _x, y in blob) == y0 + cell_h - 1
                        and row < rows - 1)
                )
                if not touches:
                    continue
                # The blob is 8-connected kept ink, hence one master
                # component; its mass majority names its true figure.
                first = blob[0][1] * width + blob[0][0]
                if majority[find(first)] != own:
                    for x, y in blob:
                        rgb[x, y] = (0, 0, 0, 0)
    return out


def _exact_cells(
    art: Image.Image, columns: int, rows: int, edge_strips: int = 0,
    sever_split: bool = True,
) -> list[list[Image.Image]]:
    """Split a uniform master grid, assigning every ink pixel to one cell.

    Wings, flames and grass bases cross gridlines, and neighbours touch across
    them, so an exact crop would clip figures and mix neighbours. Connected
    ink components go to the cell holding nearly all of their mass (a crossing
    wingtip stays whole); components genuinely spanning a line — two figures
    touching — split at the contact, each side keeping its own half. When
    edge_strips is set, small blobs floating detached in the top/bottom strip
    are erased too: grounded props keep nothing legitimate up there. The
    severed-neighbour pass then erases neighbour lobes the contact split
    stranded on the wrong side (sever_split=False keeps them, for the focused
    regression's negative control only).
    """
    from array import array
    width, height = art.size
    cell_w, cell_h = width // columns, height // rows
    assert width % columns == 0 and height % rows == 0, art.size
    data = art.getchannel("A").tobytes()
    size = width * height
    is_ink = array("b", [1 if value >= INK else 0 for value in data])
    parent = array("i", [-1]) * size
    for index in range(size):
        if is_ink[index]:
            parent[index] = index

    def find(node: int) -> int:
        root = node
        while parent[root] != root:
            root = parent[root]
        while parent[node] != root:
            parent[node], node = root, parent[node]
        return root

    # Single raster pass, 8-connectivity against visited neighbours.
    for y in range(height):
        base = y * width
        for x in range(width):
            index = base + x
            if parent[index] < 0:
                continue
            if x > 0 and parent[index - 1] >= 0:
                parent[find(index)] = find(index - 1)
            if y > 0:
                if parent[index - width] >= 0:
                    parent[find(index)] = find(index - width)
                if x > 0 and parent[index - width - 1] >= 0:
                    parent[find(index)] = find(index - width - 1)
                if x < width - 1 and parent[index - width + 1] >= 0:
                    parent[find(index)] = find(index - width + 1)

    def cell_of(x: int, y: int) -> int:
        return min(y // cell_h, rows - 1) * columns + min(
            x // cell_w, columns - 1)

    # Mass of every component per cell.
    mass: dict[int, dict[int, int]] = {}
    members: dict[int, list[int]] = {}
    for y in range(height):
        base = y * width
        for x in range(width):
            index = base + x
            if parent[index] < 0:
                continue
            root = find(index)
            cell = cell_of(x, y)
            cells = mass.setdefault(root, {})
            cells[cell] = cells.get(cell, 0) + 1
            members.setdefault(root, []).append(index)

    # Contested pixels split by nearest core through the component's own ink.
    label = array("i", [-1]) * size
    for root, cells in mass.items():
        total = sum(cells.values())
        best = max(cells, key=lambda cell: cells[cell])
        if cells[best] / total >= 0.98:
            for index in members[root]:
                label[index] = best
            continue
        contested: list[int] = []
        queue: list[int] = []
        for index in members[root]:
            x, y = index % width, index // width
            near_x = x % cell_w
            near_y = y % cell_h
            if min(near_x, cell_w - 1 - near_x,
                   near_y, cell_h - 1 - near_y) >= 14:
                label[index] = cell_of(x, y)
                queue.append(index)
            else:
                contested.append(index)
        if not queue:
            for index in members[root]:
                label[index] = best
            continue
        member_set = set(members[root])
        head = 0
        while head < len(queue):
            current = queue[head]
            head += 1
            x, y = current % width, current // width
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= width or ny >= height:
                    continue
                other = ny * width + nx
                if other in member_set and label[other] < 0:
                    label[other] = label[current]
                    queue.append(other)
        for index in contested:
            if label[index] < 0:
                x, y = index % width, index // width
                label[index] = cell_of(x, y)

    kept = art.copy()
    rgb = kept.load()
    for y in range(height):
        base = y * width
        for x in range(width):
            index = base + x
            if parent[index] >= 0 and label[index] != cell_of(x, y):
                rgb[x, y] = (0, 0, 0, 0)
    kept = _scrub_alpha(_erase_border_fragments(kept, art, columns, rows))
    if edge_strips:
        kept = _erase_edge_strips(
            kept, label, parent, columns, rows,
            width // columns, height // rows, edge_strips)
    if edge_strips and sever_split:
        majority = {
            root: max(cells, key=lambda cell: cells[cell])
            for root, cells in mass.items()
        }
        kept = _erase_severed_neighbours(
            kept, label, parent, majority, columns, rows,
            width // columns, height // rows)
    # Crop each cell with bleed, keeping only pixels assigned to it: the bleed
    # preserves crossing wingtips and flames, while neighbour ink that shares
    # the overlap band stays with its own cell.
    cells_out: list[list[Image.Image]] = []
    for row in range(rows):
        band: list[Image.Image] = []
        for column in range(columns):
            x0, y0 = column * cell_w, row * cell_h
            left, top = max(0, x0 - BLEED), max(0, y0 - BLEED)
            right = min(width, x0 + cell_w + BLEED)
            bottom = min(height, y0 + cell_h + BLEED)
            crop = kept.crop((left, top, right, bottom))
            pixels = crop.load()
            for y in range(top, bottom):
                base = y * width
                for x in range(left, right):
                    index = base + x
                    if parent[index] >= 0 \
                            and label[index] != row * columns + column:
                        pixels[x - left, y - top] = (0, 0, 0, 0)
            # The fragment pass may have erased pixels the labels still claim;
            # re-scrub so zeroed alpha is exact.
            band.append(_scrub_alpha(crop))
        cells_out.append(band)
    return cells_out


def _hero_grid(art: Image.Image) -> list[list[Image.Image]]:
    """Split a hero turnaround at its alpha gutters into 4x4 direction rows."""
    width, height = art.size
    alpha = art.getchannel("A")
    pixels = alpha.load()
    columns = [sum(
        1 for y in range(0, height, 3) if pixels[x, y] >= INK
    ) for x in range(width)]
    rows = [sum(
        1 for x in range(0, width, 3) if pixels[x, y] >= INK
    ) for y in range(height)]

    def spans(counts: list[int]) -> list[tuple[int, int]]:
        gutters: list[tuple[int, int]] = []
        start: int | None = None
        for index, count in enumerate(counts):
            if count == 0 and start is None:
                start = index
            elif count > 0 and start is not None:
                if index - start >= 4:
                    gutters.append((start, index - 1))
                start = None
        if start is not None and len(counts) - start >= 4:
            gutters.append((start, len(counts) - 1))
        found: list[tuple[int, int]] = []
        edge = 0
        for gutter_start, gutter_end in gutters:
            if gutter_start > edge:
                found.append((edge, gutter_start - 1))
            edge = gutter_end + 1
        if edge < len(counts):
            found.append((edge, len(counts) - 1))
        return found

    col_spans = spans(columns)
    row_spans = spans(rows)
    if len(col_spans) != 4 or len(row_spans) != 4:
        raise RuntimeError(
            f"hero master grid is not 4x4: {len(col_spans)}x{len(row_spans)}")
    return [
        [
            _scrub_alpha(art.crop((x0, y0, x1 + 1, y1 + 1)))
            for x0, x1 in col_spans
        ]
        for y0, y1 in row_spans
    ]


def _sidewalk_valleys(art: Image.Image) -> list[int]:
    """Three lowest-ink x-columns near the strip quarters, deterministic.

    The donor strips are unevenly spaced, so an exact quarter grid would
    cut figures; the valleys are where the background shows through most.
    Ties break toward the lower x so the choice is stable.
    """
    width, height = art.size
    alpha = art.getchannel("A").load()
    counts = [0] * width
    for x in range(width):
        total = 0
        for y in range(height):
            if alpha[x, y] >= INK:
                total += 1
        counts[x] = total
    valleys = []
    for quarter in (0.25, 0.5, 0.75):
        center = int(width * quarter)
        lo = max(0, int(center - width * 0.06))
        hi = min(width, int(center + width * 0.06))
        valleys.append(min(range(lo, hi), key=lambda x: (counts[x], x)))
    if not valleys[0] < valleys[1] < valleys[2]:
        raise RuntimeError(f"sidewalk valleys not ordered: {valleys}")
    return valleys


def _sidewalk_cells(hero: str) -> list[Image.Image]:
    """Split one donor strip into four left-facing cells.

    Valleys first (content-aware), then component assignment: every ink
    component goes wholly to its majority cell unless two figures
    genuinely touch across a cut, in which case the contact splits there
    — the _exact_cells rule in one dimension. Crops keep a bleed past
    each cut so wholly-assigned boot tips stay attached.
    """
    from array import array
    path = GAIT_ROOT / f"{hero}-sidewalk-v2.png"
    if not path.is_file():
        raise RuntimeError(f"sidewalk donor is missing: {path}")
    art = _scrub_alpha(Image.open(path).convert("RGBA"))
    width, height = art.size
    valleys = _sidewalk_valleys(art)
    edges = [0, *valleys, width]

    def cell_of(x: int) -> int:
        for index in range(GAIT_CELL_COUNT):
            if x < edges[index + 1] or index == GAIT_CELL_COUNT - 1:
                return index
        return GAIT_CELL_COUNT - 1

    data = art.getchannel("A").tobytes()
    size = width * height
    parent = array("i", [-1]) * size
    for index, value in enumerate(data):
        if value >= INK:
            parent[index] = index

    def find(node: int) -> int:
        root = node
        while parent[root] != root:
            root = parent[root]
        while parent[node] != root:
            parent[node], node = root, parent[node]
        return root

    for y in range(height):
        base = y * width
        for x in range(width):
            index = base + x
            if parent[index] < 0:
                continue
            if x > 0 and parent[index - 1] >= 0:
                parent[find(index)] = find(index - 1)
            if y > 0:
                if parent[index - width] >= 0:
                    parent[find(index)] = find(index - width)
                if x > 0 and parent[index - width - 1] >= 0:
                    parent[find(index)] = find(index - width - 1)
                if x < width - 1 and parent[index - width + 1] >= 0:
                    parent[find(index)] = find(index - width + 1)

    mass: dict[int, dict[int, int]] = {}
    members: dict[int, list[int]] = {}
    for y in range(height):
        base = y * width
        for x in range(width):
            index = base + x
            if parent[index] < 0:
                continue
            root = find(index)
            cell = cell_of(x)
            cells = mass.setdefault(root, {})
            cells[cell] = cells.get(cell, 0) + 1
            members.setdefault(root, []).append(index)

    label = array("i", [-1]) * size
    for root, cells in mass.items():
        total = sum(cells.values())
        best = max(cells, key=lambda cell: (cells[cell], -cell))
        if cells[best] / total >= GAIT_WHOLE_SHARE:
            for index in members[root]:
                label[index] = best
            continue
        contested: list[int] = []
        queue: list[int] = []
        for index in members[root]:
            x = index % width
            near = min(abs(x - valley) for valley in valleys)
            if near >= GAIT_CORE_MARGIN:
                label[index] = cell_of(x)
                queue.append(index)
            else:
                contested.append(index)
        if not queue:
            for index in members[root]:
                label[index] = best
            continue
        member_set = set(members[root])
        head = 0
        while head < len(queue):
            current = queue[head]
            head += 1
            x, y = current % width, current // width
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= width or ny >= height:
                    continue
                other = ny * width + nx
                if other in member_set and label[other] < 0:
                    label[other] = label[current]
                    queue.append(other)
        for index in contested:
            if label[index] < 0:
                label[index] = cell_of(index % width)

    cells_out: list[Image.Image] = []
    for cell in range(GAIT_CELL_COUNT):
        span_left, span_right = edges[cell], edges[cell + 1]
        left = max(0, span_left - GAIT_BLEED if cell > 0 else 0)
        right = min(width, span_right + GAIT_BLEED
                    if cell < GAIT_CELL_COUNT - 1 else width)
        crop = art.crop((left, 0, right, height))
        pixels = crop.load()
        for y in range(height):
            base = y * width
            for x in range(left, right):
                index = base + x
                if parent[index] >= 0 and label[index] != cell:
                    pixels[x - left, y] = (0, 0, 0, 0)
        cleaned = _erase_gait_fragments(crop, span_left, span_right, left)
        if _ink_bbox(cleaned) is None:
            raise RuntimeError(f"sidewalk {hero} cell {cell} is empty")
        cells_out.append(cleaned)
    return cells_out


def _erase_gait_fragments(
    cell: Image.Image, span_left: int, span_right: int, crop_left: int,
) -> Image.Image:
    """Erase severed neighbour tips past a valley cut.

    Only blobs that are detached from the figure, hold less than
    GAIT_FRAGMENT_SHARE of the cell ink, and reach past the cell's own
    span into the bleed go: contact-split halves are large and stay, and
    interior costume detail never reaches the bleed.
    """
    width, height = cell.size
    alpha = cell.getchannel("A").load()
    seen = bytearray(width * height)
    blobs: list[list[tuple[int, int]]] = []
    for sy in range(height):
        for sx in range(width):
            if alpha[sx, sy] < INK or seen[sy * width + sx]:
                continue
            blob: list[tuple[int, int]] = []
            stack = [(sx, sy)]
            seen[sy * width + sx] = 1
            while stack:
                x, y = stack.pop()
                blob.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if nx < 0 or ny < 0 \
                                or nx >= width or ny >= height:
                            continue
                        if alpha[nx, ny] < INK \
                                or seen[ny * width + nx]:
                            continue
                        seen[ny * width + nx] = 1
                        stack.append((nx, ny))
            blobs.append(blob)
    if len(blobs) < 2:
        return cell
    total = sum(len(blob) for blob in blobs)
    main = max(range(len(blobs)), key=lambda i: len(blobs[i]))
    out = cell.copy()
    rgb = out.load()
    for index, blob in enumerate(blobs):
        if index == main or len(blob) >= total * GAIT_FRAGMENT_SHARE:
            continue
        gmin = min(crop_left + x for x, _y in blob)
        gmax = max(crop_left + x for x, _y in blob)
        if gmin < span_left or gmax >= span_right:
            for x, y in blob:
                rgb[x, y] = (0, 0, 0, 0)
    return _scrub_alpha(out)


def _gait_anchor(cell: Image.Image) -> tuple[float, tuple, tuple]:
    """Torso centroid-x plus the solid and 32-level bboxes of one cell."""
    solid = cell.getchannel("A").point(
        lambda v: 255 if v >= 64 else 0).getbbox()
    if solid is None:
        raise RuntimeError("stride cell has no solid ink")
    ground = cell.getchannel("A").point(
        lambda v: 255 if v >= 32 else 0).getbbox()
    assert ground is not None
    band_bottom = solid[1] + int(
        (solid[3] - solid[1]) * GAIT_TORSO_FRACTION)
    alpha = cell.getchannel("A").load()
    total = 0
    count = 0
    for y in range(solid[1], band_bottom):
        for x in range(solid[0], solid[2]):
            if alpha[x, y] >= 64:
                total += x
                count += 1
    if not count:
        raise RuntimeError("stride cell has no torso ink")
    return total / count, solid, ground


def _fit_stride(cells: list[Image.Image], hero: str) -> list[Image.Image]:
    """Place four left-facing stride cells with one scale, soles planted.

    The scale comes from the taller contact pose (cells 0 and 2) to
    HERO_FIT_H, so passing poses keep their true body size instead of
    being enlarged to contact height. Every cell centers its torso
    anchor on the cell middle and plants its 32-level soles on the
    bottom edge; one global shrink keeps the 4px side/top gutters the
    frame contract requires.
    """
    cell_w, cell_h = HERO_CELL
    anchors = [_gait_anchor(cell) for cell in cells]
    ref_h = max(anchors[0][1][3] - anchors[0][1][1],
                anchors[2][1][3] - anchors[2][1][1])
    scale = HERO_FIT_H / ref_h
    for _pass in range(4):
        shrunk = False
        for cell, (cx, _solid, ground) in zip(cells, anchors):
            full = _ink_bbox(cell)
            assert full is not None
            left_off = (cx - full[0]) * scale
            right_off = (full[2] - cx) * scale
            above = (ground[3] - full[1]) * scale
            for have, want in (
                (left_off, cell_w / 2.0 - 4.0),
                (right_off, cell_w / 2.0 - 4.0),
                (above, cell_h - 4.0),
            ):
                if have > want:
                    scale *= want / have
                    shrunk = True
        if not shrunk:
            break
    placed: list[Image.Image] = []
    for cell, (cx, _solid, ground) in zip(cells, anchors):
        full = _ink_bbox(cell)
        assert full is not None
        size = (max(1, round((full[2] - full[0]) * scale)),
                max(1, round((full[3] - full[1]) * scale)))
        art = cell.crop(full).resize(size, Image.Resampling.LANCZOS)
        at_x = round(cell_w / 2.0 - (cx - full[0]) * scale)
        at_y = round(cell_h - (ground[3] - full[1]) * scale)
        sheet = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
        sheet.alpha_composite(art, (at_x, at_y))
        sheet = _scrub_alpha(sheet)
        box = _ink_bbox(sheet)
        assert box is not None and box[0] >= 4 \
            and box[2] <= cell_w - 4 and box[1] >= 4, (hero, box)
        soles = sheet.getchannel("A").point(
            lambda v: 255 if v >= 32 else 0).getbbox()
        assert soles is not None and soles[3] == cell_h, (hero, soles)
        placed.append(sheet)
    return placed


def _solid_bbox(art: Image.Image) -> tuple[int, int, int, int] | None:
    """Bounding box of the figure's solid mass (alpha >= 64).

    Faint dust skirts and soft snow edges below the feet must not plant the
    figure: the soles are where the solid body ends, and the faint art settles
    onto the ground under them.
    """
    solid = art.getchannel("A").point(lambda v: 255 if v >= 64 else 0)
    return solid.getbbox()


def _natural_fit_scale(
    art: Image.Image,
    box_w: int,
    box_h: int,
    cell_w: int,
    cell_h: int,
    feet_y: int,
    fit_h: int | None = None,
) -> float:
    """The scale _fit_box would place this figure at, without placing it."""
    figure = _scrub_alpha(art)
    full = _ink_bbox(figure)
    if full is None:
        raise RuntimeError("empty figure")
    solid = _solid_bbox(figure) or full
    solid_h = solid[3] - solid[1]
    full_w, full_h = full[2] - full[0], full[3] - full[1]
    # Solid soles sit this far above the full-art bottom.
    soles_up = full[3] - solid[3]
    if fit_h is not None:
        scale = fit_h / solid_h
        if full_w * scale > box_w:
            scale = box_w / full_w
    else:
        scale = min(box_w / full_w, box_h / full_h)
    for _pass in range(3):
        placed_w = full_w * scale
        placed_top = feet_y - (full_h - soles_up) * scale
        placed_left = (cell_w - placed_w) / 2.0
        shrink = 1.0
        if placed_top < 4.0:
            shrink = min(shrink, (feet_y - 4.0) / (full_h - soles_up) / scale
                         if full_h > soles_up else 1.0)
        if placed_left < 2.0:
            shrink = min(shrink, (cell_w - 4.0) / full_w / scale)
        if shrink >= 1.0:
            break
        scale *= shrink
    return scale


def _fit_box(
    art: Image.Image,
    box_w: int,
    box_h: int,
    cell_w: int,
    cell_h: int,
    feet_y: int,
    fit_h: int | None = None,
    fixed_scale: float | None = None,
) -> Image.Image:
    """Fit a figure from its measured bounds, feet planted at feet_y.

    Scales the solid-mass box to fit_h tall (or the full art into box_w x
    box_h when fit_h is None), centers horizontally, and plants the solid
    soles on feet_y. Faint skirts below the soles settle onto the ground;
    anything above the head or past the sides shrinks the whole placement to
    fit instead of clipping. A fixed scale (one hero column sharing its row-0
    scale so walk frames differ by translation, never a rescale) is verified
    against the gutters instead: an overflow raises rather than shrinking
    one frame behind the others.
    """
    figure = _scrub_alpha(art)
    full = _ink_bbox(figure)
    if full is None:
        raise RuntimeError("empty figure")
    solid = _solid_bbox(figure) or full
    full_w, full_h = full[2] - full[0], full[3] - full[1]
    # Solid soles sit this far above the full-art bottom.
    soles_up = full[3] - solid[3]
    if fixed_scale is None:
        scale = _natural_fit_scale(
            art, box_w, box_h, cell_w, cell_h, feet_y, fit_h)
    else:
        scale = fixed_scale
        placed_w = full_w * scale
        placed_top = feet_y - (full_h - soles_up) * scale
        placed_left = (cell_w - placed_w) / 2.0
        if placed_top < 4.0 or placed_left < 2.0 \
                or placed_left + placed_w > cell_w - 2.0:
            raise RuntimeError(
                f"fixed-scale fit overflows gutters: top={placed_top:.1f} "
                f"left={placed_left:.1f} w={placed_w:.1f}")
    size = (max(1, round(full_w * scale)), max(1, round(full_h * scale)))
    art = figure.crop(full).resize(size, Image.Resampling.LANCZOS)
    soles = round((full_h - soles_up) * scale)
    cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
    cell.alpha_composite(art, ((cell_w - art.width) // 2, feet_y - soles))
    return _scrub_alpha(cell)


def _planted_scale(art: Image.Image, scale: float) -> Image.Image:
    """Scale about the bottom-center so the soles stay planted."""
    if scale == 1.0:
        return art
    width, height = art.size
    grown = art.resize((max(1, round(width * scale)),
                        max(1, round(height * scale))),
                       Image.Resampling.BICUBIC)
    cell = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    cell.alpha_composite(grown, (
        (width - grown.width) // 2, height - grown.height))
    return cell


def _sole_feet(
    cell: Image.Image, x_lo: int = 0, x_hi: int | None = None,
) -> list[tuple[int, int]]:
    """The two planted feet as x-ranges, from the sole rows.

    Columns inked in at least two of the bottom eight rows group into runs;
    the two widest runs at least 4px wide are the feet. A standing cell and
    a contact cell both qualify; a passing cell with one lifted foot fails
    loudly instead of gathering half a stance. The optional x window
    restricts the hunt to the stance band, past robe panels and cloak sides
    that plant outside it.
    """
    width, height = cell.size
    if x_hi is None:
        x_hi = width
    pixels = cell.load()
    covered = [0] * width
    for y in range(height - 8, height):
        for x in range(x_lo, min(x_hi, width)):
            if pixels[x, y][3] >= INK:
                covered[x] += 1
    feet: list[tuple[int, int]] = []
    start: int | None = None
    for x in range(x_lo, min(x_hi, width)):
        if covered[x] >= 2 and start is None:
            start = x
        elif covered[x] < 2 and start is not None:
            if x - start >= 4:
                feet.append((start, x - 1))
            start = None
    if start is not None and min(x_hi, width) - start >= 4:
        feet.append((start, min(x_hi, width) - 1))
    feet.sort(key=lambda span: -(span[1] - span[0]))
    return sorted(feet[:2])


def _stance_valley(
    cell: Image.Image, cut: int, left: tuple[int, int],
    right: tuple[int, int],
) -> int:
    """Background column between the feet: least ink, ties toward left."""
    pixels = cell.load()
    best = left[1]
    best_ink = None
    for x in range(left[1], right[0] + 1):
        ink = sum(
            1 for y in range(cut + 6, cell.height)
            if pixels[x, y][3] >= INK)
        if best_ink is None or ink < best_ink:
            best_ink = ink
            best = x
    return best


def _below_cut_blobs(
    cell: Image.Image, cut: int,
) -> list[dict]:
    """8-connected ink blobs strictly below the cut row, with extents."""
    width, height = cell.size
    pixels = cell.load()
    seen = bytearray(width * height)
    blobs: list[dict] = []
    for sy in range(cut, height):
        for sx in range(width):
            if pixels[sx, sy][3] < INK or seen[sy * width + sx]:
                continue
            points: list[tuple[int, int]] = []
            stack = [(sx, sy)]
            seen[sy * width + sx] = 1
            while stack:
                x, y = stack.pop()
                points.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if nx < 0 or ny < cut \
                                or nx >= width or ny >= height:
                            continue
                        if pixels[nx, ny][3] < INK \
                                or seen[ny * width + nx]:
                            continue
                        seen[ny * width + nx] = 1
                        stack.append((nx, ny))
            blobs.append({
                "points": points,
                "ymax": max(y for _x, y in points),
            })
    return blobs


def _gather_stance(
    base: Image.Image, cut: int, hero: str, neck: int,
    center: int = HERO_STANCE_CENTER, half: int = HERO_STANCE_HALF,
    overlap: int = HERO_STANCE_OVERLAP,
) -> Image.Image:
    """Stand a contact frame up: vertical shins, level overlapped boots.

    Each leg articulates about its hip: the shin rotates to vertical while
    the boot below the ankle translates flat to its footing, so the near
    boot lands slightly forward of the far boot with both soles level on
    the ground. Cloak tips and sashes (blobs ending above row 178) stay
    where the wind left them. Rows above the cut plus the overlap come from
    the base untouched; swung thigh paint never reaches the head rows,
    which the assert below pins byte-identical.
    """
    import math
    width, height = base.size
    ankle = HERO_STANCE_ANKLE
    feet = _sole_feet(base)
    if len(feet) != 2:
        raise RuntimeError(f"stance {hero}: want 2 planted feet, got {feet}")
    (front_lo, front_hi), (rear_lo, rear_hi) = feet
    valley = _stance_valley(base, cut, feet[0], feet[1])
    blobs = _below_cut_blobs(base, cut)
    kept = {point for blob in blobs if blob["ymax"] < 178
            for point in blob["points"]}
    front_shin = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    rear_shin = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    front_boot = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    rear_boot = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    still = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    fs_px, rs_px = front_shin.load(), rear_shin.load()
    fb_px, rb_px = front_boot.load(), rear_boot.load()
    still_px, base_px = still.load(), base.load()
    for blob in blobs:
        for x, y in blob["points"]:
            if (x, y) in kept:
                still_px[x, y] = base_px[x, y]
            elif x < valley:
                if y < ankle + 5:
                    fs_px[x, y] = base_px[x, y]
                if y >= ankle - 5:
                    fb_px[x, y] = base_px[x, y]
            else:
                if y < ankle + 5:
                    rs_px[x, y] = base_px[x, y]
                if y >= ankle - 5:
                    rb_px[x, y] = base_px[x, y]
    pivot_y = cut - HERO_STANCE_PIVOT_UP
    lever = float(height - 1 - pivot_y)
    front_cx = (front_lo + front_hi) / 2.0
    rear_cx = (rear_lo + rear_hi) / 2.0
    want_front_cx = float(center - half)
    want_rear_cx = float(center + half)
    front_turn = math.degrees(math.atan2(want_front_cx - front_cx, lever))
    rear_turn = math.degrees(math.atan2(want_rear_cx - rear_cx, lever))
    ## Swinging inward about the hips dives along the arc, so the rotation
    ## runs on a padded canvas (else the shins clip) and replants signed.
    pad = 8
    front_pad = Image.new("RGBA", (width, height + pad), (0, 0, 0, 0))
    rear_pad = Image.new("RGBA", (width, height + pad), (0, 0, 0, 0))
    front_pad.alpha_composite(front_shin, (0, 0))
    rear_pad.alpha_composite(rear_shin, (0, 0))
    front_pad = front_pad.rotate(
        front_turn, resample=Image.Resampling.BICUBIC,
        center=(want_front_cx, pivot_y))
    rear_pad = rear_pad.rotate(
        rear_turn, resample=Image.Resampling.BICUBIC,
        center=(want_rear_cx, pivot_y))
    ## The swing dives wide corners past the ankle, so clip the shins at a
    ## level ankle line: the flat boot tops continue beneath, and no shin
    ## corner ever reaches the soles.
    for layer in (front_pad, rear_pad):
        layer_px = layer.load()
        for y in range(ankle + 3, height + pad):
            for x in range(width):
                layer_px[x, y] = (0, 0, 0, 0)

    def solid_bottom(part: Image.Image, label: str) -> int:
        solid = part.getchannel("A").point(
            lambda v: 255 if v >= INK else 0).getbbox()
        if solid is None:
            raise RuntimeError(f"stance {hero}: {label} vanished")
        return solid[3] - 1

    def replanted(part: Image.Image, label: str) -> Image.Image:
        shift = (ankle + 5 - 1) - solid_bottom(part, label)
        if not 0 <= shift <= 6:
            raise RuntimeError(
                f"stance {hero}: {label} replants {shift}px, want 0..6")
        out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        out.alpha_composite(part, (0, shift))
        return out

    front_shin = replanted(front_pad, "front shin")
    rear_shin = replanted(rear_pad, "rear shin")

    def planted_boot(part: Image.Image, want_cx: float, label: str,
                     foot_cx: float) -> Image.Image:
        bottom = solid_bottom(part, label)
        if bottom < height - 3:
            raise RuntimeError(
                f"stance {hero}: {label} ends at {bottom}, want ~191")
        out = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        out.alpha_composite(
            part, (round(want_cx - foot_cx), (height - 1) - bottom))
        return out

    front_boot = planted_boot(front_boot, want_front_cx, "front boot",
                              front_cx)
    rear_boot = planted_boot(rear_boot, want_rear_cx, "rear boot", rear_cx)
    stood = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    stood.alpha_composite(still, (0, 0))
    stood.alpha_composite(rear_boot, (0, 0))
    stood.alpha_composite(front_boot, (0, 0))
    stood.alpha_composite(rear_shin, (0, 0))
    stood.alpha_composite(front_shin, (0, 0))
    stood.alpha_composite(base.crop((0, 0, width, cut + overlap)), (0, 0))
    stood = _scrub_alpha(stood)
    if _flat_bytes(stood.crop((0, 0, width, neck))) \
            != _flat_bytes(base.crop((0, 0, width, neck))):
        raise RuntimeError(f"stance {hero}: head changed above the neck")
    landed = _sole_feet(stood, 40, 104)
    if len(landed) == 2:
        if landed[1][0] - landed[0][1] > 8:
            raise RuntimeError(f"stance {hero}: boots split, not standing")
    elif len(landed) == 1:
        sole_w = landed[0][1] - landed[0][0]
        if not 18 <= sole_w <= 54:
            raise RuntimeError(
                f"stance {hero}: merged sole {sole_w}px, want 18..54")
    else:
        raise RuntimeError(f"stance {hero}: no planted boots found")
    return stood


def _stand_front(
    base: Image.Image, hero: str, facing: int, hem: int, neck: int,
    center: int = HERO_STANCE_CENTER, gap: int = HERO_FRONT_GAP,
    overlap: int = HERO_FRONT_OVERLAP,
) -> Image.Image:
    """Stand a front/back stride up: mirror the leg into a planted pair.

    The planted boot column (plus a small margin) is extracted from below
    the garment hem and seated twice, symmetric about the cell middle with
    `gap` between the inner boot edges: two relaxed legs descending from
    the hips, both boots on the soles. Trailing-limb rectangles go first
    (clamped below the hem); planted paint outside the stance band and all
    lifted props stay where painted; the upper overlaps the leg tops so the
    shins tuck under the garment. The head rows never change.
    """
    width, height = base.size
    band_lo, band_hi = HERO_FRONT_BAND
    work = base.copy()
    work_px = work.load()
    for x0, y0, x1, y1 in HERO_FRONT_DISCARD.get((hero, facing), []):
        for y in range(max(y0, hem), min(y1 + 1, height)):
            for x in range(max(x0, 0), min(x1 + 1, width)):
                work_px[x, y] = (0, 0, 0, 0)
    blobs = _below_cut_blobs(work, hem)
    soles = _sole_feet(work, band_lo, band_hi)
    planted = [b for b in blobs
               if any(y == height - 1 for _x, y in b["points"])]
    if not soles or not planted:
        raise RuntimeError(f"front stance {hero}/{facing}: no planted boot")
    main = max(soles, key=lambda span: span[1] - span[0])
    sole_lo, sole_hi = main
    win_lo = max(band_lo, sole_lo - 6)
    win_hi = min(band_hi, sole_hi + 6)
    host = None
    for blob in planted:
        if any(sole_lo <= x <= sole_hi and y == height - 1
               for x, y in blob["points"]):
            host = blob
            break
    if host is None:
        raise RuntimeError(f"front stance {hero}/{facing}: sole has no leg")
    leg = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    leg_px, work_px = leg.load(), work.load()
    for x, y in host["points"]:
        if win_lo <= x <= win_hi:
            leg_px[x, y] = work_px[x, y]
    leg_box = leg.getchannel("A").point(
        lambda v: 255 if v >= INK else 0).getbbox()
    if leg_box is None:
        raise RuntimeError(f"front stance {hero}/{facing}: leg window empty")
    want_left_hi = center - (gap // 2) - 1
    want_right_lo = center + (gap - gap // 2)
    sole_w = sole_hi - sole_lo
    left = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    right = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    left.alpha_composite(leg, (want_left_hi - sole_hi, 0))
    mirror = leg.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
    right.alpha_composite(mirror, (want_right_lo - (width - 1 - sole_hi), 0))
    kept = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    kept_px = kept.load()
    host_points = set(host["points"])
    for blob in blobs:
        for x, y in blob["points"]:
            if (x, y) in host_points and win_lo <= x <= win_hi:
                continue
            kept_px[x, y] = work_px[x, y]
    upper = work.crop((0, 0, width, hem + overlap))
    upper_px = upper.load()
    for y in range(overlap):
        for x in range(max(0, win_lo - 2), min(width, win_hi + 3)):
            upper_px[x, y + hem] = (0, 0, 0, 0)
    stood = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    stood.alpha_composite(kept, (0, 0))
    stood.alpha_composite(right, (0, 0))
    stood.alpha_composite(left, (0, 0))
    stood.alpha_composite(upper, (0, 0))
    stood = _scrub_alpha(stood)
    if _flat_bytes(stood.crop((0, 0, width, neck))) \
            != _flat_bytes(base.crop((0, 0, width, neck))):
        raise RuntimeError(f"front stance {hero}/{facing}: head changed")
    check = _sole_feet(stood, band_lo, band_hi)
    if len(check) != 2:
        raise RuntimeError(
            f"front stance {hero}/{facing}: stands on {len(check)}, want 2")
    if check[1][0] - check[0][1] > 8:
        raise RuntimeError(f"front stance {hero}/{facing}: boots split")
    mid = (check[0][0] + check[1][1]) / 2.0
    if abs(mid - center) > 6:
        raise RuntimeError(f"front stance {hero}/{facing}: off middle")
    stood_px = stood.load()
    for boot_lo, boot_hi in check:
        bottom = -1
        for y in range(height - 1, -1, -1):
            if stood_px[(boot_lo + boot_hi) // 2, y][3] >= INK:
                bottom = y
                break
        if bottom != height - 1:
            raise RuntimeError(
                f"front stance {hero}/{facing}: boot floats at {bottom}")
    tuck_px = base.load()
    for slot_cx in (want_left_hi - sole_w / 2.0,
                    want_right_lo + sole_w / 2.0):
        if tuck_px[int(slot_cx), hem - 1][3] < 64:
            raise RuntimeError(
                f"front stance {hero}/{facing}: leg top floats at {slot_cx}")
    return stood


def _idle_breath(
    base: Image.Image, neck: int, hips: int, scale: float,
) -> Image.Image:
    """One idle frame: the torso band breathes, head and feet never move.

    Rows [0, neck) and [hips, 192) come from the base untouched; the band
    between scales vertically about the hips, growing upward under the
    pasted-back head. Scale 1.0 returns the base itself, unresampled. The
    head and legs paste hard (exact bytes, not a blend), so anti-aliased
    chin and sole fringes never re-composite against the shifted band.
    """
    if scale == 1.0:
        return base
    width, height = base.size
    band = base.crop((0, neck, width, hips))
    grown_h = max(1, round((hips - neck) * scale))
    grown = band.resize((width, grown_h), Image.Resampling.BICUBIC)
    frame = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    frame.alpha_composite(grown, (0, hips - grown_h))
    frame.paste(base.crop((0, 0, width, neck)), (0, 0))
    frame.paste(base.crop((0, hips, width, height)), (0, hips))
    frame = _scrub_alpha(frame)
    if _flat_bytes(frame.crop((0, 0, width, neck))) \
            != _flat_bytes(base.crop((0, 0, width, neck))):
        raise RuntimeError("idle breath moved the head")
    if _flat_bytes(frame.crop((0, hips, width, height))) \
            != _flat_bytes(base.crop((0, hips, width, height))):
        raise RuntimeError("idle breath moved the planted feet")
    return frame


def _tint(art: Image.Image, amount: float) -> Image.Image:
    if amount == 1.0:
        return art
    rgb = ImageEnhance.Brightness(art.convert("RGB")).enhance(amount)
    out = rgb.convert("RGBA")
    out.putalpha(art.getchannel("A"))
    return out


def _shifted(cell: Image.Image, dx: int, dy: int) -> Image.Image:
    if dx == 0 and dy == 0:
        return cell
    out = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    out.alpha_composite(cell, (dx, dy))
    return out


def _grade(art: Image.Image, key: str) -> Image.Image:
    """Restrained variant material grade over the figure's own pixels.

    Channel curves plus saturation/brightness only; the silhouette and the
    painted detail stay the source's. Restricted to the ink box.
    """
    box = _ink_bbox(art)
    if box is None:
        return art
    # (red, green, blue) multipliers and (saturation, brightness, contrast).
    grades: dict[str, tuple[tuple[float, float, float],
                            tuple[float, float, float]]] = {
        "thorn": ((1.10, 0.90, 1.16), (1.12, 1.0, 1.02)),
        "storm": ((0.88, 1.0, 1.12), (1.05, 0.96, 1.06)),
        "siege": ((1.12, 0.94, 0.84), (1.06, 1.0, 1.03)),
        "rime": ((0.94, 1.02, 1.12), (0.98, 1.05, 1.0)),
        "glow": ((0.98, 1.12, 1.0), (1.22, 1.03, 1.02)),
        "halo": ((1.09, 1.02, 0.88), (1.06, 1.01, 1.02)),
    }
    (red, green, blue), (saturation, brightness, contrast) = grades[key]
    figure = art.crop(box)
    bands = list(figure.split())
    for index, amount in enumerate((red, green, blue)):
        table = [min(255, round(value * amount)) for value in range(256)]
        bands[index] = bands[index].point(table)
    figure = Image.merge("RGBA", bands)
    rgb = figure.convert("RGB")
    rgb = ImageEnhance.Color(rgb).enhance(saturation)
    rgb = ImageEnhance.Brightness(rgb).enhance(brightness)
    rgb = ImageEnhance.Contrast(rgb).enhance(contrast)
    figure = rgb.convert("RGBA")
    figure.putalpha(art.crop(box).getchannel("A"))
    out = art.copy()
    out.alpha_composite(figure, (box[0], box[1]))
    return out


def _warm_light(art: Image.Image) -> Image.Image:
    """The lit-crates variant: warm up what the flame would catch."""
    box = _ink_bbox(art)
    if box is None:
        return art
    figure = art.crop(box)
    bands = list(figure.split())
    for index, amount in enumerate((1.14, 1.0, 0.86)):
        table = [min(255, round(value * amount)) for value in range(256)]
        bands[index] = bands[index].point(table)
    figure = Image.merge("RGBA", bands)
    rgb = ImageEnhance.Brightness(figure.convert("RGB")).enhance(1.06)
    figure = rgb.convert("RGBA")
    figure.putalpha(art.crop(box).getchannel("A"))
    out = art.copy()
    out.alpha_composite(figure, (box[0], box[1]))
    return out


def _pair_means(pixels, size: int, horizontal: bool) -> list[float]:
    """Mean absolute channel step of every adjacent pair, rows or columns."""
    means = []
    for index in range(size - 1):
        total = 0
        for k in range(size):
            if horizontal:
                a, b = pixels[index, k], pixels[index + 1, k]
            else:
                a, b = pixels[k, index], pixels[k, index + 1]
            total += abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])
        means.append(total / (3.0 * size))
    return means


def _heal_cut_edges(panel: Image.Image) -> Image.Image:
    """Repair master atlas-cut damage at panel edges.

    Some panels touch a different biome in the master, and the cut leaves a
    1px darker/lighter edge (frost east/north, marsh east/west, forest
    south). An edge pair stepping harder than twice the panel median pair
    step is cut damage, not art: extrapolate the edge line from its two
    interior neighbours. Clean panels pass through pixel-identical.
    """
    import statistics
    rgb = panel.convert("RGB")
    size = rgb.width
    assert rgb.height == size
    pixels = rgb.load()
    for horizontal in (True, False):
        means = _pair_means(pixels, size, horizontal)
        median = statistics.median(means)
        for edge, inner, outer in ((0, 1, 2), (size - 1, size - 2, size - 3)):
            pair = 0 if edge == 0 else size - 2
            if means[pair] <= 2.0 * median:
                continue
            for k in range(size):
                if horizontal:
                    a, b = pixels[inner, k], pixels[outer, k]
                    healed = tuple(
                        min(255, max(0, round(2 * a[c] - b[c]))) for c in range(3))
                    pixels[edge, k] = healed
                else:
                    a, b = pixels[k, inner], pixels[k, outer]
                    healed = tuple(
                        min(255, max(0, round(2 * a[c] - b[c]))) for c in range(3))
                    pixels[k, edge] = healed
    return rgb


def _ramp_match(panel: Image.Image) -> Image.Image:
    """Make the panel repeat seamlessly with symmetric linear ramps.

    Each row is tilted so its ends meet at their mean, then each column of
    the result likewise; sequential matching is exact in both axes because
    the column pass preserves the already-matched rows. The injected slope
    never exceeds half a level per pixel, so there are no blend bands, no
    corner squares, and no coherent seam ridge — unlike midpoint
    crossfading, which fixed the seam step by injecting half the edge
    difference into the first interior column. One final rounding keeps
    edges within a single quantum.
    """
    rgb = panel.convert("RGB")
    size = rgb.width
    assert rgb.height == size
    flat: list[tuple[float, float, float]] = [
        (float(p[0]), float(p[1]), float(p[2])) for p in rgb.getdata()]
    mid = (size - 1) / 2.0
    span = float(size - 1)
    for y in range(size):
        base = y * size
        left = flat[base]
        right = flat[base + size - 1]
        drift = [right[c] - left[c] for c in range(3)]
        for x in range(size):
            t = (x - mid) / span
            r, g, b = flat[base + x]
            flat[base + x] = (
                r - t * drift[0], g - t * drift[1], b - t * drift[2])
    for x in range(size):
        top = flat[x]
        bottom = flat[(size - 1) * size + x]
        drift = [bottom[c] - top[c] for c in range(3)]
        for y in range(size):
            t = (y - mid) / span
            r, g, b = flat[y * size + x]
            flat[y * size + x] = (
                r - t * drift[0], g - t * drift[1], b - t * drift[2])
    out = Image.new("RGB", (size, size))
    out.putdata([
        tuple(min(255, max(0, round(v))) for v in pixel) for pixel in flat])
    return out


def _tileable(panel: Image.Image) -> Image.Image:
    """Heal atlas cuts, then ramp-match the edges in place.

    No circular shift: rolling would move the original edge discontinuity
    into the tile interior as a visible line. Instead the healed edges meet
    by a symmetric linear tilt spread over the whole panel — the least
    visible place for the difference to go. The tile keeps every painted
    detail; only sub-level drift and the healed cut lines differ.
    """
    return _ramp_match(_heal_cut_edges(panel)).convert("RGBA")


def _headed(
    frame: Image.Image, head: Image.Image, neck: int,
) -> Image.Image:
    """One walk frame wearing its column's canonical head, pixel-fixed.

    Rows [0, neck) come from the fitted row-0 head band byte-exact (a hard
    paste, not a blend, so chin and hair fringes never re-composite); rows
    below keep the frame's own torso, arms and striding legs. The skull,
    eyes and baseline never move between frames; the neck join is the
    frame's own collar meeting the canonical chin.
    """
    out = frame.copy()
    out.paste(head, (0, 0))
    if out.crop((0, 0, out.width, neck)).tobytes() != head.tobytes():
        raise RuntimeError("canonical head paste is not byte-exact")
    return out


def bake_heroes() -> dict[Path, Image.Image]:
    """Six walk/idle sheet pairs plus full-body portraits.

    Walk columns share one scale per facing: sides from the registered gait
    donors (left) and their exact mirrors (right) via _fit_stride, down/up
    from the turnaround masters fitted at their row-0 scale, so frames
    differ by translation, never a rescale. Every walk frame wears its
    fitted row-0 head band pixel-fixed, the same bytes idle shares, so one
    canonical skull, face and baseline holds through motion; legs, arms
    and hair below the neck keep their alternating paint. Idle shares the
    walk head per facing and
    stands on rebuilt lower bodies: down/up mirror their own walk row-0 leg
    into a symmetric planted pair, sides gather the donor contact's legs
    vertically under the hips with overlapped profile feet, right mirroring
    left. Idle frames breathe through the torso band only; head and planted
    feet stay byte-identical on every frame.
    """
    out: dict[Path, Image.Image] = {}
    cell_w, cell_h = HERO_CELL
    for hero in HEROES:
        master = _load_master(f"{hero}-turnaround.png")
        grid = _hero_grid(master)
        stride = _fit_stride(_sidewalk_cells(hero), hero)
        neck = HERO_IDLE_NECK[hero]
        side_head = stride[0].crop((0, 0, cell_w, neck))
        stride = [stride[0]] + [
            _headed(frame, side_head, neck) for frame in stride[1:]
        ]
        walk = Image.new("RGBA", (cell_w * 4, cell_h * 4), (0, 0, 0, 0))
        idle = Image.new("RGBA", (cell_w * 4, cell_h * 4), (0, 0, 0, 0))
        hips = HERO_IDLE_HIPS[hero]
        stood_left = _gather_stance(
            stride[0], HERO_STANCE_CUT[hero], hero, neck)
        for direction in range(4):
            col_scale: float | None = None
            front_head = None
            row0 = None
            if direction == 2:
                rest = stood_left
            elif direction == 3:
                rest = _mirrored(stood_left)
            else:
                front_cx = HERO_FRONT_CENTER.get(
                    (hero, direction), HERO_STANCE_CENTER)
                col_scale = _natural_fit_scale(
                    grid[0][direction], cell_w - 12, cell_h - 8,
                    cell_w, cell_h, cell_h, HERO_FIT_H)
                row0 = _fit_box(
                    grid[0][direction], cell_w - 12, cell_h - 8,
                    cell_w, cell_h, cell_h, HERO_FIT_H,
                    fixed_scale=col_scale)
                front_head = row0.crop((0, 0, cell_w, neck))
                rest = _stand_front(
                    row0, hero, direction,
                    HERO_FRONT_HEM[hero][direction], neck, center=front_cx)
            for frame in range(4):
                if direction == 2:
                    pose = stride[frame]
                elif direction == 3:
                    pose = _mirrored(stride[frame])
                else:
                    assert col_scale is not None
                    assert front_head is not None
                    assert row0 is not None
                    if frame == 0:
                        pose = row0
                    else:
                        try:
                            pose = _fit_box(
                                grid[frame][direction], cell_w - 12, cell_h - 8,
                                cell_w, cell_h, cell_h, HERO_FIT_H,
                                fixed_scale=col_scale)
                        except RuntimeError as exc:
                            raise RuntimeError(
                                f"walk {hero}/{direction}/{frame}: {exc}"
                            ) from exc
                        pose = _headed(pose, front_head, neck)
                walk.alpha_composite(pose, (direction * cell_w, frame * cell_h))
                breath = _idle_breath(rest, neck, hips, HERO_IDLE_BREATH[frame])
                idle.alpha_composite(
                    breath, (direction * cell_w, frame * cell_h))
        out[HERO_ROOT / hero / "walk.png"] = walk
        out[HERO_ROOT / hero / "idle.png"] = idle
        figure = _scrub_alpha(grid[0][0])
        box = _ink_bbox(figure)
        assert box is not None
        figure = figure.crop(box)
        scale = 88.0 / max(figure.width, figure.height)
        figure = figure.resize(
            (max(1, round(figure.width * scale)),
             max(1, round(figure.height * scale))),
            Image.Resampling.LANCZOS)
        portrait = Image.new("RGBA", (96, 96), (0, 0, 0, 0))
        portrait.alpha_composite(figure, (
            (96 - figure.width) // 2, (96 - figure.height) // 2))
        out[HERO_ROOT / hero / "portrait.png"] = _scrub_alpha(portrait)
    return out


def bake_spirits() -> dict[Path, Image.Image]:
    """Seven 4-direction sheets; the swarm's side columns ship swapped."""
    out: dict[Path, Image.Image] = {}
    master = _load_master("spirit-turnarounds.png")
    grid = _exact_cells(master, 4, 7)
    # Source column per runtime direction (down, up, left, right). Every row
    # reads front/back/left-facing/right-facing except the swarm, whose side
    # views face the opposite way in the master.
    side_columns: dict[str, tuple[int, int, int, int]] = {
        name: (0, 1, 2, 3) for name in SPECIES
    }
    side_columns["swarm"] = (0, 1, 3, 2)
    for row, name in enumerate(SPECIES):
        sheet = Image.new(
            "RGBA", (SPIRIT_CELL * 4, SPIRIT_CELL * 4), (0, 0, 0, 0))
        for direction, column in enumerate(side_columns[name]):
            pose = _fit_box(
                grid[row][column], SPIRIT_CELL - 12, SPIRIT_CELL - 12,
                SPIRIT_CELL, SPIRIT_CELL,
                SPIRIT_CELL - SPIRIT_SOLE, SPIRIT_FIT_H[name])
            for frame in range(4):
                cell = _planted_scale(pose, SPIRIT_BREATHES[frame])
                cell = _shifted(cell, 0, SPIRIT_BOB[frame])
                sheet.alpha_composite(
                    cell, (direction * SPIRIT_CELL, frame * SPIRIT_CELL))
        out[SPIRIT_ROOT / f"{name}.png"] = sheet
    return out


def _guardian_idle_frames(art: Image.Image, cycle: int) -> list[Image.Image]:
    dy = GUARDIAN_IDLE_DY
    scales = GUARDIAN_IDLE_SCALES
    frames: list[Image.Image] = []
    for frame in range(6):
        step = (frame + cycle) % 6
        cell = _planted_scale(art, scales[step])
        frames.append(_shifted(cell, 0, dy[step]))
    return frames


def _guardian_state_frames(
    art: Image.Image, state: str, cycle: int
) -> list[Image.Image]:
    scales = GUARDIAN_STATE_SCALES[state]
    dy = GUARDIAN_STATE_DY[state]
    tint = GUARDIAN_STATE_TINT[state]
    frames: list[Image.Image] = []
    for frame in range(4):
        step = (frame + cycle) % 4
        cell = _planted_scale(art, scales[step])
        cell = _shifted(cell, 0, dy[step])
        frames.append(_tint(cell, tint[step]))
    return frames


def bake_guardians() -> dict[Path, Image.Image]:
    """Twelve idle sheets plus every state sheet the resources reference."""
    out: dict[Path, Image.Image] = {}
    master = _load_master("guardian-states.png")
    grid = _exact_cells(master, 4, 6)
    for row, base in enumerate(BIOMES):
        # State frames grow to 1.05x about the soles; fit poses a growth
        # margin inside the cell so scaled frames keep their padding.
        poses = [
            _fit_box(
                grid[row][column], 172, GUARDIAN_CELL - 12,
                GUARDIAN_CELL, GUARDIAN_CELL,
                GUARDIAN_CELL - GUARDIAN_SOLE, GUARDIAN_FIT)
            for column in range(4)
        ]
        jobs: list[tuple[str, list[Image.Image], int]] = [(base, poses, 0)]
        suffix, grade_key, cycle = VARIANTS[base]
        jobs.append((
            f"{base}_{suffix}",
            [_grade(pose, grade_key) for pose in poses],
            cycle,
        ))
        for name, states, cycle in jobs:
            idle = Image.new(
                "RGBA", (GUARDIAN_CELL * 6, GUARDIAN_CELL), (0, 0, 0, 0))
            for index, frame in enumerate(
                    _guardian_idle_frames(states[0], cycle)):
                idle.alpha_composite(frame, (index * GUARDIAN_CELL, 0))
            out[GUARDIAN_ROOT / f"{name}.png"] = idle
            for key in GUARDIAN_FILES[name]:
                source = states[1] if "windup" in key else states[
                    2 if key == "charge" else 3]
                state = "windup" if "windup" in key else key
                sheet = Image.new(
                    "RGBA", (GUARDIAN_CELL * 4, GUARDIAN_CELL), (0, 0, 0, 0))
                frames = _guardian_state_frames(source, state, cycle)
                if key == "windup_radial":
                    # The facing-less second pattern reads the same pose
                    # mirrored with its beat reversed, so the two windups are
                    # visibly different figures, not one file twice.
                    frames = [frame.transpose(
                        Image.Transpose.FLIP_LEFT_RIGHT) for frame in frames]
                    frames.reverse()
                for index, frame in enumerate(frames):
                    sheet.alpha_composite(frame, (index * GUARDIAN_CELL, 0))
                out[GUARDIAN_ROOT / f"{name}_{key}.png"] = sheet
    return out


def _prop_row(*, sever_split: bool = True) -> list[list[Image.Image]]:
    master = _load_master("biome-props.png")
    return _exact_cells(master, 4, 6, edge_strips=16, sever_split=sever_split)


def _mirrored(art: Image.Image) -> Image.Image:
    return art.transpose(Image.Transpose.FLIP_LEFT_RIGHT)


## Room.KIND world rects (x, y, w, h). Sheet rects are these times ZOOM.
KIND_RECTS: dict[str, tuple[int, int, int, int]] = {
    "bigA": (0, 32, 64, 48), "bigB": (64, 32, 64, 48),
    "bigC": (256, 32, 64, 48), "bigD": (320, 32, 64, 48),
    "dead": (0, 80, 64, 48),
    "sm0": (0, 0, 32, 32), "sm1": (32, 0, 32, 32),
    "sm2": (64, 0, 32, 32), "sm3": (96, 0, 32, 32),
    "sm8": (256, 0, 32, 32), "sm9": (288, 0, 32, 32),
    "mid": (96, 128, 32, 32),
    "log": (0, 128, 32, 32), "stump": (32, 128, 32, 32),
    "stump2": (64, 128, 16, 16), "branch": (80, 128, 16, 16),
    "deadstub": (64, 144, 16, 16), "twig": (80, 144, 16, 16),
    "rockA": (208, 128, 32, 32), "rockB": (256, 128, 32, 32),
    "rockS": (240, 144, 16, 16), "rockS2": (288, 144, 16, 16),
    "bush": (192, 144, 16, 16),
}
## Legacy world figure heights per scatter kind, for matching footprints.
KIND_FIT_H: dict[str, int] = {
    "bigA": 39, "bigB": 39, "bigC": 39, "bigD": 39, "dead": 41,
    "sm0": 29, "sm1": 29, "sm2": 29, "sm3": 29, "sm8": 29, "sm9": 29,
    "mid": 23, "log": 19, "stump": 22, "rockA": 23, "rockB": 22,
    "stump2": 12, "branch": 12, "deadstub": 12, "twig": 12,
    "rockS": 11, "rockS2": 11, "bush": 13,
}
## Scatter cell content per biome: (prop index 0-3, mirror) into the biome's
## prop row. Every entry is a whole-figure fit or mini, never a blind crop.
NATURE_CELLS: dict[str, dict[str, tuple[int, bool]]] = {
    "forest": {
        "bigA": (0, False), "bigB": (1, False),
        "bigC": (0, True), "bigD": (1, True), "dead": (2, False),
        "sm0": (0, False), "sm1": (1, False),
        "sm2": (0, True), "sm3": (1, True),
        "sm8": (0, False), "sm9": (1, False),
        "mid": (2, False), "log": (2, False), "stump": (2, False),
        "rockA": (3, False), "rockB": (3, True),
        "bush": (0, False), "rockS": (3, False), "rockS2": (3, True),
        "stump2": (2, False), "branch": (2, True),
        "deadstub": (2, False), "twig": (3, False),
    },
    "field": {
        "bigA": (0, False), "bigB": (1, False),
        "bigC": (2, False), "bigD": (3, False), "dead": (0, True),
        "sm0": (0, False), "sm1": (1, False),
        "sm2": (2, False), "sm3": (3, False),
        "sm8": (0, True), "sm9": (1, True),
        "mid": (1, False), "log": (2, False), "stump": (2, True),
        "rockA": (2, False), "rockB": (3, False),
        "bush": (1, False), "rockS": (2, False), "rockS2": (3, False),
        "stump2": (2, True), "branch": (0, True),
        "deadstub": (0, False), "twig": (1, True),
    },
    "camp": {
        "bigA": (0, False), "bigB": (1, False),
        "bigC": (2, False), "bigD": (3, False), "dead": (2, False),
        "sm0": (0, False), "sm1": (1, False),
        "sm2": (2, False), "sm3": (3, False),
        "sm8": (0, True), "sm9": (1, True),
        "mid": (1, False), "log": (2, False), "stump": (1, True),
        "rockA": (1, False), "rockB": (1, True),
        "bush": (0, False), "rockS": (3, False), "rockS2": (1, False),
        "stump2": (1, False), "branch": (2, True),
        "deadstub": (1, True), "twig": (2, False),
    },
    "frost": {
        "bigA": (0, False), "bigB": (3, False),
        "bigC": (0, True), "bigD": (3, True), "dead": (3, False),
        "sm0": (0, False), "sm1": (1, False),
        "sm2": (3, False), "sm3": (0, True),
        "sm8": (3, True), "sm9": (1, True),
        "mid": (1, False), "log": (3, False), "stump": (1, True),
        "rockA": (1, False), "rockB": (1, True),
        "bush": (0, False), "rockS": (1, False), "rockS2": (1, True),
        "stump2": (1, False), "branch": (3, True),
        "deadstub": (3, False), "twig": (3, False),
    },
    "marsh": {
        "bigA": (0, False), "bigB": (2, False),
        "bigC": (0, True), "bigD": (2, True), "dead": (0, False),
        "sm0": (0, False), "sm1": (1, False),
        "sm2": (2, False), "sm3": (3, False),
        "sm8": (0, True), "sm9": (2, True),
        "mid": (1, False), "log": (0, True), "stump": (1, True),
        "rockA": (3, False), "rockB": (3, True),
        "bush": (0, True), "rockS": (3, False), "rockS2": (3, True),
        "stump2": (1, False), "branch": (2, True),
        "deadstub": (0, False), "twig": (2, False),
    },
    "ruins": {
        "bigA": (0, False), "bigB": (1, False),
        "bigC": (2, False), "bigD": (3, False), "dead": (2, True),
        "sm0": (0, False), "sm1": (1, False),
        "sm2": (2, False), "sm3": (3, False),
        "sm8": (1, True), "sm9": (3, True),
        "mid": (3, False), "log": (2, False), "stump": (2, True),
        "rockA": (2, False), "rockB": (2, True),
        "bush": (3, False), "rockS": (2, False), "rockS2": (0, False),
        "stump2": (2, True), "branch": (0, True),
        "deadstub": (0, False), "twig": (3, True),
    },
}


def bake_obstacles() -> dict[Path, Image.Image]:
    """Six single-row obstacle sheets, feet at sheet y=150."""
    out: dict[Path, Image.Image] = {}
    rows = _prop_row()
    box_w, box_h = OBSTACLE_BOX
    for row, biome in enumerate(BIOMES):
        sheet = Image.new(
            "RGBA", (OBSTACLE_CELL * 4, OBSTACLE_CELL), (0, 0, 0, 0))
        for variant in range(4):
            cell = Image.new(
                "RGBA", (OBSTACLE_CELL, OBSTACLE_CELL), (0, 0, 0, 0))
            figure = _scrub_alpha(rows[row][variant])
            box = _ink_bbox(figure)
            assert box is not None, (biome, variant)
            solid = _solid_bbox(figure) or box
            figure = figure.crop(box)
            scale = min(box_w / figure.width, box_h / figure.height)
            figure = figure.resize(
                (max(1, round(figure.width * scale)),
                 max(1, round(figure.height * scale))),
                Image.Resampling.LANCZOS)
            # Solid soles plant exactly on the ground line; faint snow and
            # grass below them settle onto the ground instead of lifting the
            # structure a pixel off it.
            soles_up = round((box[3] - solid[3]) * scale)
            cell.alpha_composite(figure, (
                (OBSTACLE_CELL - figure.width) // 2,
                OBSTACLE_FEET - figure.height + soles_up))
            sheet.alpha_composite(
                _scrub_alpha(cell), (variant * OBSTACLE_CELL, 0))
        out[TERRAIN_ROOT / f"{biome}_props.png"] = sheet
    return out


def bake_nature() -> dict[Path, Image.Image]:
    """Six per-biome scatter sheets in the Room.KIND layout times ZOOM."""
    out: dict[Path, Image.Image] = {}
    rows = _prop_row()
    names = {
        "forest": "nature.png",
        "field": "field_nature.png",
        "camp": "camp_nature.png",
        "frost": "frost_nature.png",
        "marsh": "marsh_nature.png",
        "ruins": "ruins_nature.png",
    }
    for row, biome in enumerate(BIOMES):
        sheet = Image.new("RGBA", NATURE_SIZE, (0, 0, 0, 0))
        for kind, rect in KIND_RECTS.items():
            x, y, w, h = (value * ZOOM for value in rect)
            prop, mirror = NATURE_CELLS[biome][kind]
            figure = rows[row][prop]
            if mirror:
                figure = _mirrored(figure)
            cell = _fit_box(
                figure, w - 6, h - 3, w, h, h, KIND_FIT_H[kind] * ZOOM)
            sheet.alpha_composite(cell, (x, y))
        # Title grass tufts g0..g10 at world (i*16, 160, 16, 16): ground-bit
        # minis cycling the biome's props, alternating mirrors for variety.
        for index in range(11):
            figure = rows[row][index % 4]
            if index % 2:
                figure = _mirrored(figure)
            cell = _fit_box(figure, 42, 45, 48, 48, 48, 12 * ZOOM)
            sheet.alpha_composite(cell, (index * 16 * ZOOM, 160 * ZOOM))
        out[TERRAIN_ROOT / names[biome]] = sheet
    return out


def _beacon_pit(rows: list[list[Image.Image]]) -> Image.Image:
    """The beacon fire pit at world (192, 80, 32, 30), times ZOOM.

    A composite of the camp row's own pixels: the lantern base's stones
    from both sides of its post as the ring, lifted out of their shadow
    since the pit sits in firelight, with the lantern glass's glow for the
    embers. The beacon's Scorch gradient and flame particles fill the middle.
    """
    # Cleaned prop cells carry 16px bleed; coords below are cell-local.
    lant = rows[2][3]
    ring = Image.new("RGBA", (96, 90), (0, 0, 0, 0))
    for crop, at in [((90, 215, 128, 270), (6, 35)),
                     ((150, 215, 200, 270), (44, 35))]:
        stones = lant.crop(crop)
        lifted = ImageEnhance.Brightness(
            stones.convert("RGB")).enhance(1.25)
        stones = lifted.convert("RGBA")
        stones.putalpha(lant.crop(crop).getchannel("A"))
        ring.alpha_composite(_warm_light(stones), at)
    glass = lant.crop((170, 85, 200, 115)).resize(
        (30, 26), Image.Resampling.LANCZOS)
    ring.alpha_composite(_warm_light(glass), (33, 20))
    return _scrub_alpha(ring)


def bake_field_camp_props() -> dict[Path, Image.Image]:
    """Field grass islands and camp clutter in the PROP_KIND layout x3."""
    out: dict[Path, Image.Image] = {}
    rows = _prop_row()
    field = Image.new("RGBA", (80 * ZOOM, 240 * ZOOM), (0, 0, 0, 0))
    grass = _fit_box(rows[1][1], 132, 100, 144, 144, 140, 31 * ZOOM)
    field.alpha_composite(grass, (0, 48 * ZOOM))
    dark = _fit_box(rows[1][1], 132, 100, 144, 144, 140, 32 * ZOOM)
    field.alpha_composite(_tint(dark, 0.9), (0, 96 * ZOOM))
    out[TERRAIN_ROOT / "field.png"] = field

    camp = Image.new("RGBA", (368 * ZOOM, 144 * ZOOM), (0, 0, 0, 0))
    tent, crates, cart = rows[2][0], rows[2][1], rows[2][2]

    def place(figure: Image.Image, rect: tuple[int, int, int, int],
              fit_h: int) -> None:
        x, y, w, h = (value * ZOOM for value in rect)
        camp.alpha_composite(
            _fit_box(figure, w - 6, h - 3, w, h, h - 2, fit_h), (x, y))

    # Tents: full, reframed, and closer on the opening; crates stack twice
    # into the narrow tall barrels cell, once lit warm for the flame variant.
    place(tent, (64, 0, 48, 48), 43 * ZOOM)
    place(tent, (112, 0, 48, 48), 40 * ZOOM)
    place(tent, (160, 0, 48, 48), 46 * ZOOM)
    stacked = Image.new("RGBA", (144, 144), (0, 0, 0, 0))
    half = _fit_box(crates, 44, 44, 48, 48, 48, 15 * ZOOM)
    stacked.alpha_composite(half, (0, 0))
    stacked.alpha_composite(half, (0, 48))
    camp.alpha_composite(_fit_box(
        stacked, 44, 92, 48, 96, 94, 24 * ZOOM), (48 * ZOOM, 16 * ZOOM))
    lit = _warm_light(stacked)
    camp.alpha_composite(_fit_box(
        lit, 44, 92, 48, 96, 94, 24 * ZOOM), (48 * ZOOM, 48 * ZOOM))
    place(crates, (64, 96, 32, 32), 25 * ZOOM)
    place(cart, (0, 112, 48, 16), 11 * ZOOM)
    place(crates, (48, 112, 16, 16), 13 * ZOOM)
    place(crates, (112, 128, 16, 16), 11 * ZOOM)
    camp.alpha_composite(_beacon_pit(rows), (192 * ZOOM, 80 * ZOOM))
    out[TERRAIN_ROOT / "camp.png"] = camp
    return out


def bake_floors() -> dict[Path, Image.Image]:
    """Six tileable opaque ground panels from the biome floor master."""
    out: dict[Path, Image.Image] = {}
    master = _load_master("biome-floors.png").convert("RGBA")
    panel = 512
    names = {
        (0, 0): "forest_floor.png",
        (1, 0): "ground_field.png",
        (2, 0): "ground_camp.png",
        (0, 1): "ground_frost.png",
        (1, 1): "ground_marsh.png",
        (2, 1): "ground_ruins.png",
    }
    for (column, row), name in names.items():
        panel_image = master.crop((
            column * panel, row * panel,
            (column + 1) * panel, (row + 1) * panel))
        out[TERRAIN_ROOT / name] = _tileable(panel_image)
    return out


def bake_all() -> dict[Path, Image.Image]:
    baked: dict[Path, Image.Image] = {}
    for group in (bake_heroes, bake_spirits, bake_guardians,
                  bake_obstacles, bake_nature, bake_field_camp_props,
                  bake_floors):
        baked.update(group())
    return baked


## Committed-file spec: path -> (width, height, alpha mode, grid checks).
## A grid check is (columns, rows, cell_w, cell_h, pad_l, pad_r, pad_t, pad_b):
## every frame must hold ink and keep the padding strips fully transparent.
def output_specs() -> dict[Path, tuple[int, int, str, list[tuple[int, ...]]]]:
    specs: dict[Path, tuple[int, int, str, list[tuple[int, ...]]]] = {}
    actor_pad = (4, 4, 4, 0)
    for hero in HEROES:
        for sheet in ("walk", "idle"):
            specs[HERO_ROOT / hero / f"{sheet}.png"] = (
                576, 768, "graded", [(4, 4, 144, 192, *actor_pad)])
        specs[HERO_ROOT / hero / "portrait.png"] = (
            96, 96, "graded", [(1, 1, 96, 96, 2, 2, 2, 2)])
    for name in SPECIES:
        specs[SPIRIT_ROOT / f"{name}.png"] = (
            576, 576, "graded", [(4, 4, 144, 144, *actor_pad)])
    for name, states in GUARDIAN_FILES.items():
        specs[GUARDIAN_ROOT / f"{name}.png"] = (
            1152, 192, "graded", [(6, 1, 192, 192, *actor_pad)])
        for key in states:
            specs[GUARDIAN_ROOT / f"{name}_{key}.png"] = (
                768, 192, "graded", [(4, 1, 192, 192, *actor_pad)])
    for biome in BIOMES:
        specs[TERRAIN_ROOT / f"{biome}_props.png"] = (
            768, 192, "graded", [(4, 1, 192, 192, 0, 0, 0, 0)])
    nature_names = ("nature.png", "field_nature.png", "camp_nature.png",
                    "frost_nature.png", "marsh_nature.png", "ruins_nature.png")
    for name in nature_names:
        specs[TERRAIN_ROOT / name] = (1152, 1008, "graded", [])
    specs[TERRAIN_ROOT / "field.png"] = (240, 720, "graded", [])
    specs[TERRAIN_ROOT / "camp.png"] = (1104, 432, "graded", [])
    floor_names = ("forest_floor.png", "ground_field.png", "ground_camp.png",
                   "ground_frost.png", "ground_marsh.png", "ground_ruins.png")
    for name in floor_names:
        specs[TERRAIN_ROOT / name] = (512, 512, "opaque", [])
    return specs


def _alpha_mode(image: Image.Image) -> str:
    alphas = set(image.getchannel("A").getdata())
    if alphas == {255}:
        return "opaque"
    if alphas <= {0, 255}:
        return "binary"
    return "graded"


def _frame_problems(image: Image.Image, grid: tuple[int, ...],
                    label: str) -> list[str]:
    columns, rows, cell_w, cell_h, pad_l, pad_r, pad_t, pad_b = grid
    problems: list[str] = []
    alpha = image.getchannel("A")
    pixels = alpha.load()
    for row in range(rows):
        for column in range(columns):
            x0, y0 = column * cell_w, row * cell_h
            ink = 0
            for y in range(y0, y0 + cell_h):
                for x in range(x0, x0 + cell_w):
                    if pixels[x, y] > 0:
                        ink += 1
                        break
                if ink:
                    break
            if not ink:
                problems.append(f"{label} frame ({column},{row}) is empty")
                continue
            for side, region in (
                ("left", (x0, y0, pad_l, cell_h)),
                ("right", (x0 + cell_w - pad_r, y0, pad_r, cell_h)),
                ("top", (x0, y0, cell_w, pad_t)),
                ("bottom", (x0, y0 + cell_h - pad_b, cell_w, pad_b)),
            ):
                rx, ry, rw, rh = region
                dirty = any(
                    pixels[x, y] > 0
                    for y in range(ry, ry + rh)
                    for x in range(rx, rx + rw)
                )
                if dirty:
                    problems.append(
                        f"{label} frame ({column},{row}) touches {side}")
    return problems


def check_committed(baked: dict[Path, Image.Image] | None = None) -> list[str]:
    """Validate committed runtime art; byte-compare when a bake is given."""
    problems: list[str] = []
    specs = output_specs()
    for path, (width, height, mode, grids) in specs.items():
        label = path.relative_to(GAME_ROOT).as_posix()
        if not path.is_file():
            problems.append(f"{label} is missing")
            continue
        try:
            committed = Image.open(path).convert("RGBA")
        except Exception as error:  # noqa: BLE001 - any decode failure is stale
            problems.append(f"{label} is unreadable ({error})")
            continue
        if committed.size != (width, height):
            problems.append(
                f"{label} is {committed.width}x{committed.height}, "
                f"want {width}x{height}")
            continue
        actual = _alpha_mode(committed)
        if actual != mode:
            problems.append(f"{label} alpha is {actual}, want {mode}")
        for grid in grids:
            problems.extend(_frame_problems(committed, grid, label))
        if baked is not None and path in baked:
            want = baked[path].convert("RGBA")
            if committed.size != want.size \
                    or committed.tobytes() != want.tobytes():
                problems.append(f"{label} differs from a fresh bake")
    problems.extend(_check_geometry())
    problems.extend(_check_hero_identity())
    problems.extend(_check_facing_distinctness())
    problems.extend(_check_variant_distinctness())
    problems.extend(_check_scatter_ink())
    problems.extend(_check_prop_intrusions())
    problems.extend(_check_floor_seams())
    return problems


def _cell_bottom(path: Path, frame: tuple[int, int, int, int]) -> int | None:
    # Any rendered pixel counts (alpha > 0): soft snow and dust edges ground
    # the figure even when they fall below the ink threshold. PIL boxes are
    # exclusive; the last ink row is box[3] - 1.
    image = Image.open(path).convert("RGBA").crop(frame)
    box = image.getchannel("A").getbbox()
    return None if box is None else box[3] - 1


def _check_geometry() -> list[str]:
    """Feet planted where the resources say the soles are."""
    problems: list[str] = []
    # Hero idle breathes about planted soles; walk steps may lift a foot.
    for hero in HEROES:
        idle = HERO_ROOT / hero / "idle.png"
        walk = HERO_ROOT / hero / "walk.png"
        if not idle.is_file() or not walk.is_file():
            continue
        for direction in range(4):
            for frame in range(4):
                region = (direction * 144, frame * 192, 144, 192)
                box = (region[0], region[1],
                       region[0] + region[2], region[1] + region[3])
                bottom = _cell_bottom(idle, box)
                if bottom != 191:
                    problems.append(
                        f"heroes/{hero}/idle.png ({direction},{frame}) "
                        f"soles at {bottom}, want 191")
                bottom = _cell_bottom(walk, box)
                if bottom is None or not 181 <= bottom <= 191:
                    problems.append(
                        f"heroes/{hero}/walk.png ({direction},{frame}) "
                        f"soles at {bottom}, want 181..191")
    # Spirits hover: soles rest 18px off the cell floor, plus the 3px bob.
    for name in SPECIES:
        path = SPIRIT_ROOT / f"{name}.png"
        if not path.is_file():
            continue
        for direction in range(4):
            for frame in range(4):
                box = (direction * 144, frame * 144,
                       direction * 144 + 144, frame * 144 + 144)
                bottom = _cell_bottom(path, box)
                if bottom is None or abs(bottom - 125) > 4:
                    problems.append(
                        f"spirits/{name}.png ({direction},{frame}) "
                        f"soles at {bottom}, want 121..129")
    # Guardians stand: soles 6px off the floor, plus state motion.
    for name in GUARDIAN_FILES:
        idle = GUARDIAN_ROOT / f"{name}.png"
        if idle.is_file():
            for frame in range(6):
                box = (frame * 192, 0, frame * 192 + 192, 192)
                bottom = _cell_bottom(idle, box)
                if bottom is None or abs(bottom - 185) > 5:
                    problems.append(
                        f"guardians/{name}.png idle f{frame} "
                        f"soles at {bottom}, want 180..190")
        for key in GUARDIAN_FILES[name]:
            path = GUARDIAN_ROOT / f"{name}_{key}.png"
            if not path.is_file():
                continue
            for frame in range(4):
                box = (frame * 192, 0, frame * 192 + 192, 192)
                bottom = _cell_bottom(path, box)
                if bottom is None or abs(bottom - 185) > 6:
                    problems.append(
                        f"guardians/{name}_{key}.png f{frame} "
                        f"soles at {bottom}, want 179..191")
    # Obstacles: solid soles plant on sheet y=150, so the last rendered row
    # is 149 or the faint snow/grass settling just under it.
    for biome in BIOMES:
        path = TERRAIN_ROOT / f"{biome}_props.png"
        if not path.is_file():
            continue
        for variant in range(4):
            box = (variant * 192, 0, variant * 192 + 192, 192)
            bottom = _cell_bottom(path, box)
            if bottom is None or not 149 <= bottom <= 170:
                problems.append(
                    f"{biome}_props.png variant {variant} "
                    f"feet at {bottom}, want 149..170")
    return problems


def _check_hero_identity() -> list[str]:
    """One head per hero and facing, standing sides, breathing torsos.

    Idle row 0 carries the walk row-0 head byte-identical (both side
    columns mirror the same way, so right compares directly); idle frames
    keep the head
    rows and the below-hips rows identical while the torso band visibly
    breathes; side idle stands on overlapped profile feet in a narrow
    stance extent and mirrors left to right exactly. The old mismatched
    side profile (a
    turnaround head much wider than the donor), the old whole-body breath
    (head and soles shifting every frame), and the frozen contact stride
    (feet split fore and aft) fail here, not silently.
    """
    problems: list[str] = []
    for hero in HEROES:
        idle_path = HERO_ROOT / hero / "idle.png"
        walk_path = HERO_ROOT / hero / "walk.png"
        if not idle_path.is_file() or not walk_path.is_file():
            continue
        idle = Image.open(idle_path).convert("RGBA")
        walk = Image.open(walk_path).convert("RGBA")
        neck = HERO_IDLE_NECK[hero]
        hips = HERO_IDLE_HIPS[hero]
        for direction in range(4):
            rest = idle.crop((direction * 144, 0,
                              direction * 144 + 144, 192))
            reference = walk.crop((direction * 144, 0,
                                   direction * 144 + 144, 192))
            if _flat_bytes(rest.crop((0, 0, 144, neck))) \
                    != _flat_bytes(reference.crop((0, 0, 144, neck))):
                problems.append(
                    f"heroes/{hero}/idle.png column {direction} head "
                    f"differs from its walk frame")
            for frame in (1, 2, 3):
                cell = idle.crop((direction * 144, frame * 192,
                                  direction * 144 + 144, frame * 192 + 192))
                if _flat_bytes(cell.crop((0, 0, 144, neck))) \
                        != _flat_bytes(rest.crop((0, 0, 144, neck))):
                    problems.append(
                        f"heroes/{hero}/idle.png column {direction} "
                        f"frame {frame} moves the head")
                if _flat_bytes(cell.crop((0, hips, 144, 192))) \
                        != _flat_bytes(rest.crop((0, hips, 144, 192))):
                    problems.append(
                        f"heroes/{hero}/idle.png column {direction} "
                        f"frame {frame} moves the planted feet")
            peak = idle.crop((direction * 144, 2 * 192,
                              direction * 144 + 144, 2 * 192 + 192))
            if _flat_bytes(peak.crop((0, neck, 144, hips))) \
                    == _flat_bytes(rest.crop((0, neck, 144, hips))):
                problems.append(
                    f"heroes/{hero}/idle.png column {direction} "
                    f"torso never breathes")
        for direction, label in ((2, "left"), (3, "right")):
            rest = idle.crop((direction * 144, 0,
                              direction * 144 + 144, 192))
            feet = _sole_feet(rest)
            if not feet:
                problems.append(
                    f"heroes/{hero}/idle.png {label} stands on 0 feet")
                continue
            extent = feet[-1][1] - feet[0][0] + 1
            # Profile feet overlap in x with a small near/far offset, so one
            # merged sole run is the honest shape; a split run pair with a
            # wide gap is the old contact stride. Contact donors span 56-68px
            # while gathered stances span 26-38px, so the stance extent must
            # sit between: narrow enough to reject the stride, wide enough
            # that a single narrow boot cannot pass (keeper's sparkle fringe
            # is the documented exception, guarded by the in-bake two-piece
            # placement asserts and 4x inspection instead).
            if extent > 46:
                problems.append(
                    f"heroes/{hero}/idle.png {label} stance extent "
                    f"{extent}px, want <= 46")
            if extent < 20:
                problems.append(
                    f"heroes/{hero}/idle.png {label} stance extent "
                    f"{extent}px, want >= 20")
            if len(feet) == 2 and feet[1][0] - feet[0][1] > 12:
                problems.append(
                    f"heroes/{hero}/idle.png {label} stance gap "
                    f"{feet[1][0] - feet[0][1]}px, want <= 12")
        left = idle.crop((2 * 144, 0, 3 * 144, 192 * 4))
        right = idle.crop((3 * 144, 0, 4 * 144, 192 * 4))
        mirror = left.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
        if mirror.tobytes() != right.tobytes():
            problems.append(
                f"heroes/{hero}/idle.png right is not the left mirror")
    return problems


def _check_facing_distinctness() -> list[str]:
    """No direction column may duplicate another: backs are drawn, not made."""
    problems: list[str] = []
    for hero in HEROES:
        for sheet in ("walk", "idle"):
            path = HERO_ROOT / hero / f"{sheet}.png"
            if not path.is_file():
                continue
            image = Image.open(path).convert("RGBA")
            columns = [
                image.crop((d * 144, 0, d * 144 + 144, 192)).tobytes()
                for d in range(4)
            ]
            for first in range(4):
                for second in range(first + 1, 4):
                    if columns[first] == columns[second]:
                        problems.append(
                            f"heroes/{hero}/{sheet}.png directions "
                            f"{first} and {second} are identical")
    for name in SPECIES:
        path = SPIRIT_ROOT / f"{name}.png"
        if not path.is_file():
            continue
        image = Image.open(path).convert("RGBA")
        columns = [
            image.crop((d * 144, 0, d * 144 + 144, 144)).tobytes()
            for d in range(4)
        ]
        for first in range(4):
            for second in range(first + 1, 4):
                if columns[first] == columns[second]:
                    problems.append(
                        f"spirits/{name}.png directions "
                        f"{first} and {second} are identical")
    return problems


def _check_variant_distinctness() -> list[str]:
    """Twelve boss idle sheets, all pixel-distinct from each other."""
    problems: list[str] = []
    seen: dict[bytes, str] = {}
    for name in GUARDIAN_FILES:
        path = GUARDIAN_ROOT / f"{name}.png"
        if not path.is_file():
            continue
        digest = Image.open(path).convert("RGBA").tobytes()
        if digest in seen:
            problems.append(
                f"guardians/{name}.png duplicates {seen[digest]}")
        else:
            seen[digest] = f"guardians/{name}.png"
    return problems


def _check_scatter_ink() -> list[str]:
    """Every KIND rect and every PROP rect the rooms read must hold ink."""
    problems: list[str] = []
    nature_names = {
        "forest": "nature.png", "field": "field_nature.png",
        "camp": "camp_nature.png", "frost": "frost_nature.png",
        "marsh": "marsh_nature.png", "ruins": "ruins_nature.png",
    }
    for biome, name in nature_names.items():
        path = TERRAIN_ROOT / name
        if not path.is_file():
            continue
        image = Image.open(path).convert("RGBA")
        for kind, rect in KIND_RECTS.items():
            x, y, w, h = (value * ZOOM for value in rect)
            if _ink_bbox(image.crop((x, y, x + w, y + h))) is None:
                problems.append(f"{name} scatter cell {kind} is empty")
        for index in range(11):
            x, w, h = index * 16 * ZOOM, 48, 48
            y = 160 * ZOOM
            if _ink_bbox(image.crop((x, y, x + w, y + h))) is None:
                problems.append(f"{name} title grass g{index} is empty")
    prop_rects: dict[str, list[tuple[int, int, int, int]]] = {
        "field.png": [(0, 48, 48, 48), (0, 96, 48, 48)],
        "camp.png": [(64, 0, 48, 48), (112, 0, 48, 48), (160, 0, 48, 48),
                     (48, 16, 16, 32), (48, 48, 16, 32), (64, 96, 32, 32),
                     (0, 112, 48, 16), (48, 112, 16, 16), (112, 128, 16, 16),
                     (192, 80, 32, 30)],
    }
    for name, rects in prop_rects.items():
        path = TERRAIN_ROOT / name
        if not path.is_file():
            continue
        image = Image.open(path).convert("RGBA")
        for rect in rects:
            x, y, w, h = (value * ZOOM for value in rect)
            if _ink_bbox(image.crop((x, y, x + w, y + h))) is None:
                problems.append(f"{name} prop cell {rect} is empty")
    return problems


def _cell_sidecars(cell: Image.Image, label: str) -> list[str]:
    """Detached blobs sitting fully beside the figure keep failing cells.

    A severed neighbour fragment survives the bake as a blob detached from
    the figure by a transparent gutter, off to one side. The figure is the
    largest blob; any other blob holding SIDECAR_SHARE of the cell's ink
    whose x-range is disjoint from the figure's is that fragment. Interior
    specks and stacked compositions overlap the figure's x-range, so they
    pass; grounded detail below the figure does too.
    """
    width, height = cell.size
    alpha = cell.getchannel("A").load()
    seen = bytearray(width * height)
    blobs: list[tuple[int, int, int, int, int]] = []
    for sy in range(height):
        for sx in range(width):
            if alpha[sx, sy] < INK or seen[sy * width + sx]:
                continue
            count, x0, y0, x1, y1 = 0, sx, sy, sx, sy
            stack = [(sx, sy)]
            seen[sy * width + sx] = 1
            while stack:
                x, y = stack.pop()
                count += 1
                x0, y0 = min(x0, x), min(y0, y)
                x1, y1 = max(x1, x), max(y1, y)
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        nx, ny = x + dx, y + dy
                        if nx < 0 or ny < 0 or nx >= width or ny >= height:
                            continue
                        if alpha[nx, ny] < INK or seen[ny * width + nx]:
                            continue
                        seen[ny * width + nx] = 1
                        stack.append((nx, ny))
            blobs.append((count, x0, y0, x1, y1))
    if len(blobs) < 2:
        return []
    total = sum(count for count, _x0, _y0, _x1, _y1 in blobs)
    blobs.sort(reverse=True)
    _main, mx0, _my0, mx1, _my1 = blobs[0]
    problems: list[str] = []
    for count, x0, _y0, x1, _y1 in blobs[1:]:
        if count < total * SIDECAR_SHARE:
            continue
        gap = max(x0 - mx1, mx0 - x1) - 1
        if gap < 1:
            continue
        side = "left of" if x1 < mx0 else "right of"
        problems.append(
            f"{label} keeps a detached blob {side} the figure "
            f"({count}px, {count / total:.1%} of cell ink)")
    return problems


def _check_prop_intrusions() -> list[str]:
    """No terrain cell keeps a detached neighbour-side blob.

    Reads the committed sheets only, so this guard runs even when the
    painted masters are absent; the byte comparison in check_committed is
    what needs the masters, never this.
    """
    problems: list[str] = []
    for biome in BIOMES:
        path = TERRAIN_ROOT / f"{biome}_props.png"
        if not path.is_file():
            continue
        sheet = Image.open(path).convert("RGBA")
        for variant in range(4):
            cell = sheet.crop((
                variant * OBSTACLE_CELL, 0,
                variant * OBSTACLE_CELL + OBSTACLE_CELL, OBSTACLE_CELL))
            problems.extend(_cell_sidecars(
                cell, f"{biome}_props.png variant {variant}"))
    nature_names = {
        "forest": "nature.png", "field": "field_nature.png",
        "camp": "camp_nature.png", "frost": "frost_nature.png",
        "marsh": "marsh_nature.png", "ruins": "ruins_nature.png",
    }
    for biome, name in nature_names.items():
        path = TERRAIN_ROOT / name
        if not path.is_file():
            continue
        image = Image.open(path).convert("RGBA")
        for kind, rect in KIND_RECTS.items():
            x, y, w, h = (value * ZOOM for value in rect)
            problems.extend(_cell_sidecars(
                image.crop((x, y, x + w, y + h)),
                f"{name} scatter cell {kind}"))
        for index in range(11):
            x, w, h = index * 16 * ZOOM, 48, 48
            y = 160 * ZOOM
            problems.extend(_cell_sidecars(
                image.crop((x, y, x + w, y + h)),
                f"{name} title grass g{index}"))
    prop_rects: dict[str, list[tuple[int, int, int, int]]] = {
        "field.png": [(0, 48, 48, 48), (0, 96, 48, 48)],
        "camp.png": [(64, 0, 48, 48), (112, 0, 48, 48), (160, 0, 48, 48),
                     (48, 16, 16, 32), (48, 48, 16, 32), (64, 96, 32, 32),
                     (0, 112, 48, 16), (48, 112, 16, 16), (112, 128, 16, 16),
                     (192, 80, 32, 30)],
    }
    for name, rects in prop_rects.items():
        path = TERRAIN_ROOT / name
        if not path.is_file():
            continue
        image = Image.open(path).convert("RGBA")
        for rect in rects:
            x, y, w, h = (value * ZOOM for value in rect)
            problems.extend(_cell_sidecars(
                image.crop((x, y, x + w, y + h)),
                f"{name} prop cell {rect}"))
    return problems


def _strip_energy(pixels, size: int, horizontal: bool) -> list[float]:
    """Mean step inside each of 8 strips across the tile (detail energy)."""
    import statistics
    strips = []
    for strip in range(8):
        vals = []
        for i in range(strip * 64, strip * 64 + 63):
            for k in range(0, size, 4):
                if horizontal:
                    a, b = pixels[i, k], pixels[i + 1, k]
                else:
                    a, b = pixels[k, i], pixels[k, i + 1]
                vals.append((abs(a[0] - b[0]) + abs(a[1] - b[1])
                             + abs(a[2] - b[2])) / 3.0)
        strips.append(statistics.mean(vals))
    return strips


def _check_floor_seams() -> list[str]:
    """Floor repeats must be invisible: matched edges, typical seam pairs."""
    problems: list[str] = []
    floor_names = ("forest_floor.png", "ground_field.png", "ground_camp.png",
                   "ground_frost.png", "ground_marsh.png", "ground_ruins.png")
    for name in floor_names:
        path = TERRAIN_ROOT / name
        if not path.is_file():
            continue
        image = Image.open(path).convert("RGB")
        size = image.width
        pixels = image.load()
        # Matched edges: opposite columns/rows meet within one quantum.
        worst = 0
        for y in range(size):
            for channel in range(3):
                worst = max(worst, abs(
                    pixels[0, y][channel] - pixels[size - 1, y][channel]))
        for x in range(size):
            for channel in range(3):
                worst = max(worst, abs(
                    pixels[x, 0][channel] - pixels[x, size - 1][channel]))
        if worst > 1:
            problems.append(f"{name} seam step is {worst}, want <= 1")
        # Typical seam pairs: the pairs beside the seam must not step harder
        # than every interior pair — a coherent ridge (crossfade's half edge
        # difference) fails; natural detail passes. Judged against the tile
        # itself, both axes.
        for horizontal, axis in ((True, "column"), (False, "row")):
            means = _pair_means(pixels, size, horizontal)
            inside = max(means[1:-1])
            if means[0] > inside or means[-1] > inside:
                problems.append(
                    f"{name} seam {axis} pair steps "
                    f"{means[0]:.2f}/{means[-1]:.2f}, interior max {inside:.2f}")
        # No four-edge smoothing: edge crossfading flattens all four sides,
        # while natural calm only ever quiets one axis (ruins south). Both
        # edge strips below every interior strip on both axes is the blend
        # signature, judged against the tile itself.
        smoothed = True
        for horizontal in (True, False):
            strips = _strip_energy(pixels, size, horizontal)
            if not (strips[0] < min(strips[1:-1])
                    and strips[7] < min(strips[1:-1])):
                smoothed = False
        if smoothed:
            problems.append(f"{name} edges are over-smoothed on both axes")
    return problems


def _png_bytes(image: Image.Image) -> bytes:
    from io import BytesIO
    buffer = BytesIO()
    image.convert("RGBA").save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


def bake_to_disk() -> list[Path]:
    written: list[Path] = []
    for path, image in bake_all().items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(_png_bytes(image))
        written.append(path)
    return written


def report_lines() -> list[str]:
    lines = ["painted-world runtime art:"]
    total_files = 0
    total_png = 0
    total_rgba = 0
    for path in sorted(output_specs()):
        if not path.is_file():
            lines.append(f"  MISSING {path.relative_to(GAME_ROOT)}")
            continue
        image = Image.open(path)
        png_bytes = path.stat().st_size
        rgba_bytes = image.width * image.height * 4
        total_files += 1
        total_png += png_bytes
        total_rgba += rgba_bytes
        lines.append(
            f"  {path.relative_to(GAME_ROOT)} "
            f"{image.width}x{image.height} "
            f"png={png_bytes} rgba={rgba_bytes}")
    lines.append(
        f"total: {total_files} files, "
        f"png={total_png} bytes, rgba={total_rgba} bytes")
    return lines


def check_current(*, byte_verify: bool = True) -> list[str]:
    """Problems with the committed runtime art, empty when current.

    With byte_verify (the default) a fresh bake from the masters is compared
    pixel by pixel; without it the committed files are validated structurally
    only. Retired builders delegate their --check here with byte_verify off:
    the full byte comparison is one manual command, not six slow repeats.
    """
    baked: dict[Path, Image.Image] | None = None
    if byte_verify and SOURCE_ROOT.is_dir():
        baked = bake_all()
    return check_committed(baked)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args()
    if args.report:
        print("\n".join(report_lines()))
        return 0
    if args.check:
        if not SOURCE_ROOT.is_dir():
            print("masters absent; structural check only")
        problems = check_current()
        if problems:
            for problem in problems:
                print(f"FAIL {problem}")
            return 1
        print(f"painted world packed: {len(output_specs())} outputs current"
              + (" (byte-verified)" if SOURCE_ROOT.is_dir() else ""))
        return 0
    written = bake_to_disk()
    print(f"baked {len(written)} painted-world sheets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
