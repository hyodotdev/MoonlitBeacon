#!/usr/bin/env python3
"""Deterministically build the Moonlit Beacon 3.0.0 pixel UI kit.

The 2.x UI was flat navy rectangles with a one-pixel teal edge, drawn per scene
with ``StyleBoxFlat`` overrides (the settings screen alone carried seventy). It
read as a prototype. This kit is the shared replacement: chunky, rounded,
warm-outlined "sticker" panels on deep indigo, in the same pixel scale as the
actors so a 3x canvas shows crisp nearest-neighbour edges.

Why textures and not rounded ``StyleBoxFlat``: with ``canvas_items`` stretch a
StyleBoxFlat is tessellated at the *device* resolution, so its corners come out
smooth-vector next to pixel-art sprites. A ``StyleBoxTexture`` is scaled with
nearest filtering and stays chunky.

Every sheet is a nine-patch. The centre band of each is a **solid colour** so a
stretched panel never shows stripes; all shading lives inside the fixed margins.

Style rule: cute and readable first. Corners are round, outlines are warm, and
nothing is gritty or metallic. See the art-direction note in ``notes/plans``.

Stdlib only, like the other art tools.

Output (all under ``assets/custom/ui/kit/``)::

    panel.png                 24x24  margin 8   modal / large surface
    chip.png                  16x16  margin 6   small HUD readout pill
    button_<variant>_<state>  16x16  margin 6   gold | lav | berry | ghost
    card_<state>.png          32x32  margin 12  relic card frame
    bar_back.png / bar_fill   12x10  margin 4   progress track and fill
    banner.png                40x24  margin 14  act-title ribbon
"""

from __future__ import annotations

import argparse
import hashlib
import math
import sys
from pathlib import Path

from pixel_canvas import RGBA, Canvas

Margin = tuple[int, int]

GAME_ROOT = Path(__file__).resolve().parents[1]
OUTPUT_DIR = GAME_ROOT / "assets/custom/ui/kit"


def _rgb(hex_value: str) -> RGBA:
    hex_value = hex_value.lstrip("#")
    return (int(hex_value[0:2], 16), int(hex_value[2:4], 16),
            int(hex_value[4:6], 16), 255)


# --- Palette ----------------------------------------------------------------
# Deep indigo surfaces, moon-cream and lantern-gold accents, one lavender and
# one berry for secondary and danger. Chosen against the night ground so a
# panel stands out from the world without shouting over the spirits.
OUTLINE = _rgb("#151837")
INK = _rgb("#0d1028")

CREAM = _rgb("#f6e9c8")
CREAM_LOW = _rgb("#c9b48a")
GOLD = _rgb("#ffcf66")
GOLD_LOW = _rgb("#d08d34")
GOLD_HI = _rgb("#fff1b8")
LAV = _rgb("#b9a8ff")
LAV_LOW = _rgb("#7a6cc4")
BERRY = _rgb("#ff8fb3")
BERRY_LOW = _rgb("#c14d7a")
MINT = _rgb("#8ff0d2")
MINT_LOW = _rgb("#3fae94")

FILL_HI = _rgb("#454c9a")
FILL = _rgb("#363c80")
FILL_LOW = _rgb("#2b3068")
SHADE = _rgb("#232858")

DIM_HI = _rgb("#2a2f66")
DIM = _rgb("#1f2352")
DIM_LOW = _rgb("#191c45")

GREY = _rgb("#7b7f9e")
GREY_LOW = _rgb("#4d5070")
GREY_FILL = _rgb("#2a2c45")
GREY_FILL_LOW = _rgb("#212339")


# --- Geometry ---------------------------------------------------------------
def depth(x: int, y: int, w: int, h: int, r: float) -> float:
    """How far inside a rounded rectangle a pixel centre sits.

    Positive is inside, negative is outside. Signed-distance rather than a
    hand-drawn corner, so one radius parameter gives every element the same
    curve and the kit stays consistent.
    """
    px, py = x + 0.5, y + 0.5
    qx = abs(px - w / 2) - (w / 2 - r)
    qy = abs(py - h / 2) - (h / 2 - r)
    outside = math.hypot(max(qx, 0.0), max(qy, 0.0))
    inside = min(max(qx, qy), 0.0)
    return -(outside + inside - r)


def rounded(w: int, h: int, r: float, paint) -> Canvas:
    """Paint a rounded rectangle. ``paint(x, y, d)`` returns a colour or None."""
    canvas = Canvas(w, h)
    for y in range(h):
        for x in range(w):
            d = depth(x, y, w, h, r)
            if d < 0.0:
                continue
            color = paint(x, y, d)
            if color is not None:
                canvas.pixel(x, y, color)
    return canvas


# --- Elements ---------------------------------------------------------------
def panel() -> Canvas:
    """Modal and large-surface frame. Cream sticker border on indigo."""
    w = h = 24

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return OUTLINE
        if d < 3.0:
            # Lit on the top and sides, a shade lower only in the fixed bottom
            # margin. Deciding it by a fraction of the height put the change in
            # the stretched band and drew a seam down every tall panel.
            return CREAM if y < h - 8 else CREAM_LOW
        if d < 4.0:
            return SHADE
        # Fill. A thin lighter band under the top border and a darker one above
        # the bottom border, both inside the fixed margins.
        if y < 5:
            return FILL_HI
        if y >= h - 6:
            return FILL_LOW
        return FILL

    canvas = rounded(w, h, 6.0, paint)
    # Lantern-gold rivet in each inner corner, inside the fixed 8px margin.
    for cx, cy in ((5, 5), (w - 6, 5), (5, h - 6), (w - 6, h - 6)):
        canvas.pixel(cx, cy, GOLD)
    canvas.pixel(5, 5, GOLD_HI)
    return canvas


def chip(tone: str = "lav") -> Canvas:
    """Small readout pill. Quieter than a panel: one soft one-pixel edge.

    ``lav`` is the resting row; ``gold`` marks the row the game wants you to look
    at (the selected hero, the next boon worth buying).
    """
    w = h = 16
    rim = {"lav": LAV_LOW, "gold": GOLD}[tone]

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return OUTLINE
        if d < 2.0:
            return rim
        if y < 4:
            return DIM_HI
        if y >= h - 4:
            return DIM_LOW
        return DIM

    return rounded(w, h, 5.0, paint)


# (rim, rim_low) per variant. Fills stay dark on purpose: every button label in
# the game was authored as light text on a dark box, and the colour of the rim
# is what says primary / secondary / danger.
VARIANTS: dict[str, tuple[RGBA, RGBA, RGBA]] = {
    "gold": (GOLD, GOLD_LOW, GOLD_HI),
    "lav": (LAV, LAV_LOW, CREAM),
    "berry": (BERRY, BERRY_LOW, CREAM),
    "ghost": (LAV_LOW, GREY_LOW, LAV),
}


def button(variant: str, state: str) -> Canvas:
    """Compact chunky button. Pressed loses its lip; disabled loses its colour.

    16x16 with a 6px margin, so it still has a centre in the shortest button in
    the game (a 14px `Buy` chip) and scales cleanly up to a 33px result button.
    An earlier 20px / 8px-margin version looked richer in a mockup and fell
    apart on the small controls, which share this one style set.
    """
    rim, rim_low, rim_hi = VARIANTS[variant]
    w = h = 16

    if state == "focus":
        # Focus is drawn over the resting state, so it is only a bright ring.
        def ring(x: int, y: int, d: float) -> RGBA | None:
            if d < 1.0 or d >= 2.0:
                return None
            return CREAM if variant != "ghost" else LAV

        return rounded(w, h, 5.0, ring)

    if state == "disabled":
        rim, rim_low, rim_hi = GREY, GREY_LOW, GREY

    fill_hi = {"normal": FILL_HI, "hover": FILL_HI, "pressed": SHADE,
               "disabled": GREY_FILL}[state]
    fill = {"normal": FILL, "hover": FILL_HI, "pressed": SHADE,
            "disabled": GREY_FILL}[state]
    fill_low = {"normal": FILL_LOW, "hover": FILL, "pressed": DIM_LOW,
                "disabled": GREY_FILL_LOW}[state]
    # A pressed button sits flush: no thick bottom lip.
    lip = state != "pressed"

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return OUTLINE
        # The lip is the pill's "thickness": the bottom rim row, a shade darker.
        if lip and y >= h - 2 and d < 2.0:
            return rim_low
        if d < 2.0:
            if state == "pressed":
                return rim_low
            return rim_hi if (y < 3 and state == "hover") else rim
        if d < 3.0:
            return SHADE if state != "disabled" else GREY_FILL_LOW
        if y < 5:
            return fill_hi
        if y >= h - 6:
            return fill_low
        return fill

    canvas = rounded(w, h, 5.0, paint)
    if state in ("normal", "hover"):
        # Two-pixel glint on the upper-left shoulder — the "shiny sticker" cue.
        canvas.pixel(3, 3, rim_hi)
        canvas.pixel(4, 3, rim_hi)
    return canvas


def card(state: str) -> Canvas:
    """Relic card frame. Taller radius and a gold rim so it reads as a prize."""
    w = h = 32
    if state == "focus":
        # Drawn over the resting state, so only a bright ring outside the rim.
        def ring(x: int, y: int, d: float) -> RGBA | None:
            return CREAM if 1.0 <= d < 2.0 else None

        return rounded(w, h, 8.0, ring)
    rim, rim_low, rim_hi = GOLD, GOLD_LOW, GOLD_HI
    fill, fill_hi, fill_low = FILL, FILL_HI, FILL_LOW
    if state == "hover":
        rim, rim_low, rim_hi = GOLD_HI, GOLD, CREAM
        fill, fill_hi, fill_low = FILL_HI, FILL_HI, FILL
    elif state == "pressed":
        rim, rim_low, rim_hi = GOLD_LOW, GOLD_LOW, GOLD
        fill, fill_hi, fill_low = SHADE, SHADE, DIM_LOW
    elif state == "disabled":
        rim, rim_low, rim_hi = GREY, GREY_LOW, GREY
        fill, fill_hi, fill_low = GREY_FILL, GREY_FILL, GREY_FILL_LOW

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return OUTLINE
        if d < 3.0:
            return rim if y < h - 12 else rim_low
        if d < 4.0:
            return SHADE if state != "disabled" else GREY_FILL_LOW
        if y < 6:
            return fill_hi
        if y >= h - 8:
            return fill_low
        return fill

    canvas = rounded(w, h, 8.0, paint)
    # A small moon-gem in each corner, tucked inside the 12px margin.
    for cx, cy in ((6, 6), (w - 7, 6), (6, h - 7), (w - 7, h - 7)):
        canvas.pixel(cx, cy, rim_hi)
        canvas.pixel(cx + 1, cy, rim)
        canvas.pixel(cx, cy + 1, rim)
    return canvas


def bar_back() -> Canvas:
    """Progress track. Dark, deep, softly lit at the bottom lip."""
    w, h = 12, 10

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return OUTLINE
        if d < 2.0:
            return LAV_LOW if y < h // 2 else GREY_LOW
        return DIM_LOW if y < h // 2 else DIM

    return rounded(w, h, 4.0, paint)


def bar_fill(color: RGBA, color_low: RGBA) -> Canvas:
    """Progress fill. Rounded on the ends, lit on the top row."""
    w, h = 12, 10

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return None
        if y < 4:
            return color
        return color_low

    return rounded(w, h, 4.0, paint)


def banner() -> Canvas:
    """Act-title ribbon: a wide gold-rimmed plate with notched ends."""
    w, h = 40, 24

    def paint(x: int, y: int, d: float) -> RGBA | None:
        if d < 1.0:
            return OUTLINE
        if d < 3.0:
            return GOLD if y < h - 9 else GOLD_LOW
        if d < 4.0:
            return SHADE
        if y < 5:
            return FILL_HI
        if y >= h - 7:
            return FILL_LOW
        return FILL

    canvas = rounded(w, h, 8.0, paint)
    # Studs sit in the four fixed corners. One on the vertical centre line would
    # be stretched into a bar on a taller banner.
    for cx, cy in ((6, 6), (w - 7, 6), (6, h - 7), (w - 7, h - 7)):
        canvas.pixel(cx, cy, GOLD_HI)
        canvas.pixel(cx + 1, cy, GOLD)
    return canvas


# --- Icons ------------------------------------------------------------------
# Small hand-drawn pixel icons. Written as text grids because at 12px every
# pixel is a decision, and a grid is reviewable in a diff where a sequence of
# draw calls is not.
ICON_PALETTE: dict[str, RGBA] = {
    "o": _rgb("#2b1a2e"),   # warm dark outline
    "r": _rgb("#ff7a3d"),   # flame red-orange
    "y": _rgb("#ffd45e"),   # flame yellow
    "w": _rgb("#fff3c4"),   # flame core
    "s": _rgb("#8a8fb5"),   # bowl light
    "d": _rgb("#5b6090"),   # bowl mid
    "k": _rgb("#3a3e68"),   # bowl dark
    "e": _rgb("#ff9a5a"),   # dying ember
    "g": _rgb("#6a6f9c"),   # unlit ash
}

ICONS: dict[str, list[str]] = {
    # A lit beacon: a little brazier with a fat teardrop flame. 16px so the
    # objective has real presence next to 11px text instead of reading as a dot.
    "icon_beacon_on": [
        ".......oo.......",
        "......oyyo......",
        "......oyyo......",
        ".....oyyyyo.....",
        "....oyyyyyyo....",
        "....oyywwyyo....",
        "...oyyywwyyyo...",
        "...oryywwyyro...",
        "...oryywyyyro...",
        "...orryyyyrro...",
        "....orrrrrro....",
        ".....oooooo.....",
        "..oooooooooooo..",
        "..osssssssssso..",
        "...oddddddddo...",
        "....oookkooo....",
    ],
    # The same brazier waiting to be lit: cold bowl, one dying ember.
    "icon_beacon_off": [
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        "................",
        ".......oo.......",
        "......oeeo......",
        ".....oooooo.....",
        "..oooooooooooo..",
        "..ogggggggggso..",
        "...okkkkkkkko...",
        "....oookkooo....",
    ],
}


def icon(name: str) -> Canvas:
    rows = ICONS[name]
    width = len(rows[0])
    for row in rows:
        if len(row) != width:
            raise SystemExit(f"{name}: icon rows must all be {width} wide")
    canvas = Canvas(width, len(rows))
    for y, row in enumerate(rows):
        for x, char in enumerate(row):
            if char == ".":
                continue
            if char not in ICON_PALETTE:
                raise SystemExit(f"{name}: unknown palette key {char!r}")
            canvas.pixel(x, y, ICON_PALETTE[char])
    return canvas


# --- Registry ---------------------------------------------------------------
# name -> (canvas, nine-patch margin as (horizontal, vertical)). Margins are what the Theme uses,
# so they live next to the art rather than in a second file that can drift.
def registry() -> dict[str, tuple[Canvas, Margin]]:
    items: dict[str, tuple[Canvas, Margin]] = {
        "panel": (panel(), (8, 8)),
        "chip": (chip(), (6, 6)),
        "chip_gold": (chip("gold"), (6, 6)),
        "bar_back": (bar_back(), (4, 4)),
        "bar_fill_mint": (bar_fill(MINT, MINT_LOW), (4, 4)),
        "bar_fill_gold": (bar_fill(GOLD, GOLD_LOW), (4, 4)),
        "bar_fill_berry": (bar_fill(BERRY, BERRY_LOW), (4, 4)),
        # Neutral fill for bars whose colour is set at runtime (`self_modulate`),
        # like the boss bar, which wears each guardian's accent.
        "bar_fill_white": (bar_fill(_rgb("#ffffff"), _rgb("#c9cce0")), (4, 4)),
        "banner": (banner(), (14, 9)),
    }
    for variant in VARIANTS:
        for state in ("normal", "hover", "pressed", "disabled", "focus"):
            items[f"button_{variant}_{state}"] = (button(variant, state), (6, 6))
    for state in ("normal", "hover", "pressed", "disabled", "focus"):
        items[f"card_{state}"] = (card(state), (12, 12))
    for name in ICONS:
        items[name] = (icon(name), (0, 0))
    return items


# --- Validation -------------------------------------------------------------
def visible_colors(canvas: Canvas) -> set[tuple[int, int, int]]:
    seen: set[tuple[int, int, int]] = set()
    for index in range(0, len(canvas.pixels), 4):
        r, g, b, a = canvas.pixels[index : index + 4]
        if a:
            seen.add((r, g, b))
    return seen


def check_strips(name: str, canvas: Canvas, margin: Margin,
                 horizontal_only: bool = False) -> None:
    """The edge strips are the stretched parts of a nine-patch.

    A top or bottom strip is stretched along x, so each of its rows must be one
    colour across the stretched columns; a left or right strip is stretched
    along y, so each of its columns must be one colour down the stretched rows.
    Otherwise a shading change that sits in the stretched band lands at a
    different place on every panel size — a hard seam on the border.
    """
    w, h = canvas.width, canvas.height
    mx, my = margin
    rows = list(range(0, h)) if horizontal_only \
        else list(range(0, my)) + list(range(h - my, h))
    for y in rows:
        if len({tuple(canvas.get(x, y)) for x in range(mx, w - mx)}) != 1:
            raise SystemExit(
                f"{name}: row {y} is not uniform across the stretched columns")
    if horizontal_only:
        return
    for x in list(range(0, mx)) + list(range(w - mx, w)):
        if len({tuple(canvas.get(x, y)) for y in range(my, h - my)}) != 1:
            raise SystemExit(
                f"{name}: column {x} is not uniform down the stretched rows "
                "(a colour change in a side border shows as a seam)")


def validate(name: str, canvas: Canvas, margin: Margin) -> None:
    """Guard the properties that make a nine-patch usable."""
    w, h = canvas.width, canvas.height
    mx, my = margin
    for index in range(0, len(canvas.pixels), 4):
        if canvas.pixels[index + 3] not in (0, 255):
            raise SystemExit(f"{name}: alpha must be binary (0 or 255)")
    if name.startswith("icon_"):
        return  # not a nine-patch: binary alpha is the only rule
    if mx * 2 >= w or my * 2 >= h:
        raise SystemExit(f"{name}: margin {margin} leaves no centre in {w}x{h}")
    if name.startswith("bar_"):
        # A progress bar only ever stretches horizontally, so vertical shading
        # is fine as long as every row is uniform across the stretched columns.
        check_strips(name, canvas, margin, horizontal_only=True)
        return
    check_strips(name, canvas, margin)
    if name.endswith("_focus"):
        return  # a ring overlay: its centre is deliberately transparent
    colors = {tuple(canvas.get(x, y))
              for x in range(mx, w - mx) for y in range(my, h - my)}
    if len(colors) != 1:
        raise SystemExit(
            f"{name}: nine-patch centre must be one solid colour "
            f"(found {len(colors)}) or a stretched panel will show stripes")
    if (0, 0, 0, 0) in colors:
        raise SystemExit(f"{name}: nine-patch centre must not be transparent")


# --- Preview ----------------------------------------------------------------
def stretch9(canvas: Canvas, margin: Margin, tw: int, th: int) -> Canvas:
    """Simulate Godot's nine-patch scaling with nearest filtering."""
    mx, my = margin
    out = Canvas(tw, th)
    sw, sh = canvas.width, canvas.height
    for y in range(th):
        for x in range(tw):
            if x < mx:
                sx = x
            elif x >= tw - mx:
                sx = sw - (tw - x)
            else:
                sx = mx + (x - mx) * (sw - 2 * mx) // max(tw - 2 * mx, 1)
            if y < my:
                sy = y
            elif y >= th - my:
                sy = sh - (th - y)
            else:
                sy = my + (y - my) * (sh - 2 * my) // max(th - 2 * my, 1)
            out.pixel(x, y, canvas.get(sx, sy))
    return out


def write_preview(path: Path, items: dict[str, tuple[Canvas, Margin]]) -> None:
    """Render every element stretched to three sizes on a night background."""
    zoom = 4
    sizes = ((36, 24), (96, 40), (168, 72))
    rows = [name for name in items
            if not name.endswith("_focus") and not name.startswith("icon_")]
    pad = 6
    row_h = max(s[1] for s in sizes) + pad
    width = sum(s[0] for s in sizes) + pad * (len(sizes) + 1)
    sheet = Canvas(width, row_h * len(rows) + pad, (24, 30, 56, 255))
    for row, name in enumerate(rows):
        canvas, margin = items[name]
        x = pad
        for tw, th in sizes:
            if name.startswith("bar_"):
                th = min(th, 12)
            if name == "banner":
                tw = max(tw, margin[0] * 2 + 8)
            stretched = stretch9(canvas, margin, tw, th)
            for yy in range(stretched.height):
                for xx in range(stretched.width):
                    color = stretched.get(xx, yy)
                    if color[3]:
                        sheet.pixel(x + xx, pad + row * row_h + yy, color)
            x += tw + pad
    big = Canvas(sheet.width * zoom, sheet.height * zoom)
    for y in range(sheet.height):
        for x in range(sheet.width):
            color = sheet.get(x, y)
            big.rect(x * zoom, y * zoom, x * zoom + zoom - 1,
                     y * zoom + zoom - 1, color)
    big.save(path)


# --- Style resources --------------------------------------------------------
STYLE_ROOT = GAME_ROOT / "resources/ui"

# Content margins are set explicitly and kept equal to what the 2.x styles
# resolved to (5px). A StyleBoxTexture with no content margin falls back to its
# *texture* margin, so the new 6px art margin would have grown every button by
# two pixels and shifted layouts that were tuned to the old size.
BUTTON_CONTENT = 5.0


def style_text(texture: str, margin: Margin, content: tuple[float, float, float, float],
               draw_center: bool = True, modulate: str | None = None) -> str:
    """One ``StyleBoxTexture`` resource, in Godot's own text layout."""
    mx, my = margin
    lines = [
        '[gd_resource type="StyleBoxTexture" load_steps=2 format=3]',
        "",
        f'[ext_resource type="Texture2D" path="res://assets/custom/ui/kit/{texture}.png" id="1_texture"]',
        "",
        "[resource]",
        'texture = ExtResource("1_texture")',
        f"texture_margin_left = {float(mx)}",
        f"texture_margin_top = {float(my)}",
        f"texture_margin_right = {float(mx)}",
        f"texture_margin_bottom = {float(my)}",
        f"content_margin_left = {content[0]}",
        f"content_margin_top = {content[1]}",
        f"content_margin_right = {content[2]}",
        f"content_margin_bottom = {content[3]}",
    ]
    if modulate:
        lines.append(f"modulate_color = {modulate}")
    if not draw_center:
        lines.append("draw_center = false")
    return "\n".join(lines) + "\n"


def style_files(items: dict[str, tuple[Canvas, Margin]]) -> dict[str, str]:
    """Every shared ``resources/ui`` style file, as ``{relative path: text}``.

    Scenes point at these by path, exactly as they did for the 2.x buttons, so
    changing the look is a change here and not seventeen scene edits. Pure, so the
    writer and ``--check`` cannot disagree about what the files should contain.
    """
    files: dict[str, str] = {}

    box = (BUTTON_CONTENT,) * 4
    # ``buttons`` keeps its 2.x path and gets the secondary (lavender) look, so
    # every existing scene picks the new art up without being edited.
    sets = {"buttons": "lav", "buttons_gold": "gold",
            "buttons_berry": "berry", "buttons_ghost": "ghost"}
    for folder, variant in sets.items():
        for state in ("normal", "hover", "pressed", "disabled", "focus"):
            name = f"button_{variant}_{state}"
            files[f"{folder}/{state}.tres"] = style_text(
                name, items[name][1], box, draw_center=state != "focus")

    files["panels/panel.tres"] = style_text(
        "panel", items["panel"][1], (10.0, 9.0, 10.0, 9.0))
    # Dense screens (shrine, shop) fill the whole safe height, so they get the
    # same art with less padding. The shrine test asserts the frame stays inside
    # the safe inset, and the roomy panel pushed it two pixels past.
    files["panels/panel_tight.tres"] = style_text(
        "panel", items["panel"][1], (8.0, 6.0, 8.0, 6.0))
    files["panels/chip.tres"] = style_text(
        "chip", items["chip"][1], (5.0, 3.0, 5.0, 3.0))
    files["panels/chip_gold.tres"] = style_text(
        "chip_gold", items["chip_gold"][1], (5.0, 3.0, 5.0, 3.0))
    files["panels/banner.tres"] = style_text(
        "banner", items["banner"][1], (16.0, 8.0, 16.0, 8.0))
    for state in ("normal", "hover", "pressed", "disabled", "focus"):
        name = f"card_{state}"
        files[f"cards/{state}.tres"] = style_text(
            name, items[name][1], (12.0, 12.0, 12.0, 12.0),
            draw_center=state != "focus")
    files["bars/back.tres"] = style_text(
        "bar_back", items["bar_back"][1], (4.0, 3.0, 4.0, 3.0))
    for tone in ("mint", "gold", "berry", "white"):
        name = f"bar_fill_{tone}"
        files[f"bars/fill_{tone}.tres"] = style_text(
            name, items[name][1], (4.0, 3.0, 4.0, 3.0))
    return files


def write_styles(items: dict[str, tuple[Canvas, Margin]]) -> None:
    files = style_files(items)
    for relative, text in files.items():
        target = STYLE_ROOT / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
    print(f"wrote {len(files)} style resources under resources/ui")


# --- Asset contract ---------------------------------------------------------
CONTRACT_PATH = GAME_ROOT / "tools/custom_asset_contracts.json"
CONTRACT_PREFIX = "ui.kit."


def contract_entries(items: dict[str, tuple[Canvas, Margin]]) -> list[dict]:
    """The ``ui.kit.*`` contract entries, in a stable order."""
    entries: list[dict] = []
    for name, (canvas, _margin) in sorted(items.items()):
        colors = len(visible_colors(canvas))
        entries.append({
            "id": f"{CONTRACT_PREFIX}{name}",
            "category": "ui",
            "status": "final",
            "path": f"assets/custom/ui/kit/{name}.png",
            "width": canvas.width,
            "height": canvas.height,
            "alpha_mode": "binary",
            "max_visible_rgb_colors": max(colors, 4),
            "max_alpha_levels": 2,
        })
    return entries


def render_contract(items: dict[str, tuple[Canvas, Margin]]) -> str:
    """The whole contract file as it should read with this kit's entries in it.

    The contract is the check that a PNG under ``assets/custom`` is declared and
    the right size. Regenerating the kit with a new size and forgetting the
    contract is the mistake this removes.

    Done through JSON rather than by splicing text: ``json.dumps`` with two-space
    indent reproduces this file's own layout exactly, and splicing broke the
    moment the kit's block became the last element (no trailing comma).
    """
    import json

    data = json.loads(CONTRACT_PATH.read_text())
    assets: list[dict] = data["assets"]
    first = next((i for i, a in enumerate(assets)
                  if a["id"].startswith(CONTRACT_PREFIX)), None)
    kept = [a for a in assets if not a["id"].startswith(CONTRACT_PREFIX)]
    if first is None:
        # First run: keep ui.* together, just ahead of the relic emblems.
        first = next((i for i, a in enumerate(kept)
                      if a["id"].startswith("ui.relic_icon_")), len(kept))
    data["assets"] = kept[:first] + contract_entries(items) + kept[first:]
    return json.dumps(data, indent=2, ensure_ascii=False) + "\n"


def sync_contract(items: dict[str, tuple[Canvas, Margin]]) -> None:
    CONTRACT_PATH.write_text(render_contract(items))
    print(f"synced {len(items)} {CONTRACT_PREFIX}* contract entries")


def check_outputs(items: dict[str, tuple[Canvas, Margin]]) -> None:
    """Fail if anything on disk differs from what the tool would generate.

    Same contract as the other art tools' ``--check``: the committed production
    files are exactly what the deterministic generator produces, so nobody can
    hand-edit a PNG (or a shared style, or a contract entry) and have it drift.
    """
    problems: list[str] = []
    for name, (canvas, _margin) in sorted(items.items()):
        target = OUTPUT_DIR / f"{name}.png"
        if not target.exists():
            problems.append(f"missing {target.relative_to(GAME_ROOT)}")
        elif target.read_bytes() != canvas.to_png():
            problems.append(f"out of date {target.relative_to(GAME_ROOT)}")
    for relative, text in style_files(items).items():
        target = STYLE_ROOT / relative
        if not target.exists():
            problems.append(f"missing resources/ui/{relative}")
        elif target.read_text() != text:
            problems.append(f"out of date resources/ui/{relative}")
    if CONTRACT_PATH.read_text() != render_contract(items):
        problems.append("out of date tools/custom_asset_contracts.json (ui.kit.*)")
    if problems:
        raise SystemExit(
            "UI kit is not what build_ui_kit.py generates:\n  "
            + "\n  ".join(problems)
            + "\nRun: node scripts/python.mjs -B apps/game/tools/build_ui_kit.py"
              " --styles --sync-contract")
    print("check: production UI kit is deterministic")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="fail if the PNGs, shared styles or contract entries "
                             "differ from what this tool generates; writes nothing")
    parser.add_argument("--preview", type=Path,
                        help="also write an upscaled stretch preview sheet")
    parser.add_argument("--sync-contract", action="store_true",
                        help="rewrite the ui.kit.* asset-contract entries")
    parser.add_argument("--styles", action="store_true",
                        help="write the shared resources/ui/*.tres style files")
    args = parser.parse_args()

    items = registry()
    for name, (canvas, margin) in items.items():
        validate(name, canvas, margin)

    if args.preview:
        write_preview(args.preview, items)
        print(f"preview {args.preview}")

    if args.sync_contract:
        sync_contract(items)
    if args.styles:
        write_styles(items)

    for name, (canvas, margin) in sorted(items.items()):
        payload = canvas.to_png()
        digest = hashlib.sha256(payload).hexdigest()[:12]
        colors = len(visible_colors(canvas))
        target = OUTPUT_DIR / f"{name}.png"
        line = (f"{name:24s} {canvas.width}x{canvas.height} "
                f"m{margin[0]},{margin[1]:<2d} c{colors:<2d} {digest}")
        if args.check:
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)
        print(line)
    if args.check:
        check_outputs(items)
    return 0


if __name__ == "__main__":
    sys.exit(main())
