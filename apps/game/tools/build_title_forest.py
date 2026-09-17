"""Build the night-forest placement the title screen instances.

Rewrite both `Details` and `Trees` blocks in `scenes/gameplay/night_forest.tscn` in full.
The title instances this scene, so there is no extra copy. Do not move by hand;
edit this script and rerun it.

    python apps/game/tools/build_title_forest.py

SEED is fixed, so the same input yields the same placement.

## What must be kept

- Every KIND region_rect is a
  "complete tile". When adding a new value, remeasure alpha so it is not cropped.
  check it. A large tree was once cropped to 48px so the canopy's right side
  was cropped off. The real width is 64.
- Place sprites from the foot (base anchor) and convert to Sprite2D
  top-left so y alignment is exact.
- W_MIN/W_MAX, Y_MIN/Y_MAX cover as wide/tall as stretch aspect=expand can get.
  On the 808x360 baseline, leftover width on each side
  the view widens by half that leftover, so the current values leave no empty band out to 4:1.
"""
import math, random, re
from pathlib import Path

SEED = 20260725
random.seed(SEED)

W_MIN, W_MAX = -300.0, 1110.0      # world x the scatter must cover
Y_MIN, Y_MAX = -130.0, 500.0       # world y (base anchor)

BEACON = (404.0, 250.0)
# Dirt blob measured from beacon_clearing.png: x 288..538, y 174..322.
DIRT_C = (413.0, 248.0)
DIRT_RX, DIRT_RY = 125.0, 74.0

# Tree line: an ellipse around the beacon that trees keep out of.
OPEN_C = (404.0, 258.0)
OPEN_RX, OPEN_RY = 196.0, 90.0

# name -> (region x, y, w, h)
KIND = {
    "bigA": (0, 32, 64, 48), "bigB": (64, 32, 64, 48),
    "bigC": (256, 32, 64, 48), "bigD": (320, 32, 64, 48),
    "dead": (0, 80, 64, 48),
    "sm0": (0, 0, 32, 32), "sm1": (32, 0, 32, 32), "sm2": (64, 0, 32, 32),
    "sm3": (96, 0, 32, 32), "sm8": (256, 0, 32, 32), "sm9": (288, 0, 32, 32),
    "mid": (96, 128, 32, 32),
    "log": (0, 128, 32, 32), "stump": (32, 128, 32, 32),
    "stump2": (64, 128, 16, 16), "branch": (80, 128, 16, 16),
    "deadstub": (64, 144, 16, 16), "twig": (80, 144, 16, 16),
    "rockA": (208, 128, 32, 32), "rockB": (256, 128, 32, 32),
    "rockS": (240, 144, 16, 16), "rockS2": (288, 144, 16, 16),
    "bush": (192, 144, 16, 16),
}
for i in range(11):
    KIND["g%d" % i] = (i * 16, 160, 16, 16)

GRASS = ["g0", "g1", "g2", "g3", "g4", "g5", "g6", "g7", "g8", "g9", "g10"]

# Aerial perspective. Far things are darker and bluer so the forest recedes
# and the title stays readable over the mid ground. Quantised so neighbouring
# rows share a value instead of every sprite having its own.
DEPTH_NEAR = 360.0
DEPTH_FAR = -130.0
DEPTH_MIN = 0.42
STEPS = 20.0


def tier_of(y):
    t = (y - DEPTH_FAR) / (DEPTH_NEAR - DEPTH_FAR)
    t = min(max(t, 0.0), 1.0)
    b = DEPTH_MIN + (1.0 - DEPTH_MIN) * pow(t, 0.85)
    b = round(b * STEPS) / STEPS
    f = 1.0 - t
    col = (min(b * (1.0 - 0.10 * f), 1.0),
           min(b * (1.0 - 0.05 * f), 1.0),
           min(b * (1.0 + 0.06 * f), 1.0))
    if col[0] >= 0.999 and col[1] >= 0.999 and col[2] >= 0.999:
        return None
    return (round(col[0], 3), round(col[1], 3), round(col[2], 3))


def open_field(x, y):
    """>1 outside the tree line, <1 inside. Edge is wobbled so it is not a
    drawn ellipse."""
    dx = (x - OPEN_C[0]) / OPEN_RX
    dy = (y - OPEN_C[1]) / OPEN_RY
    r = math.hypot(dx, dy)
    if r < 1e-4:
        return 0.0
    ang = math.atan2(dy, dx)
    wobble = (0.085 * math.sin(ang * 3.0 + 0.9)
              + 0.055 * math.sin(ang * 5.0 - 2.1)
              + 0.035 * math.sin(ang * 8.0 + 0.3))
    return r / (1.0 + wobble)


def dirt_field(x, y):
    return math.hypot((x - DIRT_C[0]) / DIRT_RX, (y - DIRT_C[1]) / DIRT_RY)


items = []          # (base_x, base_y, kind, flip, modulate|None, bucket)


def put(bx, by, kind, bucket, flip=None, mod="tier"):
    if flip is None:
        flip = random.random() < 0.5
    col = tier_of(by) if mod == "tier" else mod
    items.append((bx, by, kind, flip, col, bucket))


def scatter(y0, y1, cell_x, cell_y, weights, jitter=0.55, margin=0.0,
            keep=1.0, bucket="trees"):
    """Jittered grid scatter. `margin` is how far outside the tree line the
    foot has to sit, in units of the open-field radius."""
    names = list(weights.keys())
    wts = [weights[n] for n in names]
    y = y0
    while y < y1:
        x = W_MIN
        while x < W_MAX:
            if random.random() <= keep:
                bx = x + cell_x * (0.5 + jitter * (random.random() - 0.5) * 2.0)
                by = y + cell_y * (0.5 + jitter * (random.random() - 0.5) * 2.0)
                if open_field(bx, by) >= 1.0 + margin:
                    put(bx, by, random.choices(names, wts)[0], bucket)
            x += cell_x
        y += cell_y


# --- canopy: the dark band that closes the top of the frame -----------------
scatter(Y_MIN, 40.0, 38.0, 27.0, {
    "bigA": 26, "bigB": 8, "bigC": 10, "bigD": 8, "dead": 9,
    "sm0": 8, "sm1": 12, "sm2": 5, "sm3": 6, "sm8": 5, "sm9": 5, "mid": 6,
})

# --- mid ground: this is the band that used to be a bare green field --------
scatter(40.0, 180.0, 42.0, 30.0, {
    "bigA": 24, "bigB": 9, "bigC": 11, "bigD": 9, "dead": 11,
    "sm0": 7, "sm1": 9, "sm2": 5, "sm3": 6, "sm8": 5, "sm9": 5, "mid": 7,
}, margin=0.02)

# --- the ring that frames the clearing --------------------------------------
scatter(180.0, 362.0, 46.0, 34.0, {
    "bigA": 22, "bigB": 10, "bigC": 12, "bigD": 10, "dead": 10,
    "sm0": 7, "sm1": 8, "sm2": 4, "sm3": 6, "sm8": 5, "sm9": 5, "mid": 8,
}, margin=0.06)

# --- near band: biggest and brightest, some of it runs off the bottom -------
scatter(362.0, Y_MAX, 50.0, 36.0, {
    "bigA": 24, "bigB": 11, "bigC": 13, "bigD": 11, "dead": 8,
    "sm0": 6, "sm1": 7, "sm3": 5, "sm8": 5, "sm9": 5, "mid": 6,
})

# --- forest floor: undergrowth so the grass never reads as bare lawn --------
undergrowth = {k: 6 for k in GRASS}
undergrowth.update({"bush": 10, "rockS": 5, "rockS2": 5, "twig": 5,
                    "branch": 4, "stump2": 3, "deadstub": 4})
scatter(Y_MIN, Y_MAX, 34.0, 26.0, undergrowth, keep=0.5, margin=0.03)

# a few bigger ground pieces
scatter(Y_MIN, Y_MAX, 150.0, 105.0,
        {"log": 10, "stump": 9, "rockA": 8, "rockB": 8}, keep=0.55, margin=0.10)


# --- clearing rim: things that straddle the dirt edge so it sits in the ground
def rim_ring(count, r_lo, r_hi, weights, bucket="details"):
    names = list(weights.keys())
    wts = [weights[n] for n in names]
    for i in range(count):
        ang = (i + random.random() * 0.85) / count * math.tau
        r = r_lo + (r_hi - r_lo) * random.random()
        bx = DIRT_C[0] + math.cos(ang) * DIRT_RX * r
        by = DIRT_C[1] + math.sin(ang) * DIRT_RY * r
        put(bx, by, random.choices(names, wts)[0], bucket)


rim_ring(34, 0.95, 1.18, {k: 8 for k in GRASS} | {"bush": 11, "twig": 3})
# Only a few big pieces, and well clear of the fire so they do not read as a
# ring of stones placed around it.
rim_ring(6, 1.22, 1.44, {"log": 6, "stump": 5, "rockA": 5, "rockB": 5})

# --- pebbles and twigs on the dirt itself ----------------------------------
for _ in range(7):
    ang = random.random() * math.tau
    r = 0.40 + 0.48 * random.random()
    bx = DIRT_C[0] + math.cos(ang) * DIRT_RX * r
    by = DIRT_C[1] + math.sin(ang) * DIRT_RY * r
    if math.hypot(bx - BEACON[0], by - BEACON[1] + 6) < 44:
        continue
    put(bx, by, "twig", "details")


# --- emit -------------------------------------------------------------------
def emit(bucket, prefix, parent):
    rows = [it for it in items if it[5] == bucket]
    rows.sort(key=lambda it: (it[1], it[0]))
    out = []
    for i, (bx, by, kind, flip, col, _) in enumerate(rows):
        rx, ry, w, h = KIND[kind]
        px = int(round(bx - w * 0.5))
        py = int(round(by - h))
        s = ['[node name="%s%03d" type="Sprite2D" parent="%s"]' % (prefix, i, parent)]
        if col is not None:
            s.append("modulate = Color(%g, %g, %g, 1)" % col)
        s.append("position = Vector2(%d, %d)" % (px, py))
        s.append('texture = ExtResource("nature")')
        s.append("centered = false")
        s.append("region_enabled = true")
        s.append("region_rect = Rect2(%d, %d, %d, %d)" % (rx, ry, w, h))
        if flip:
            s.append("flip_h = true")
        out.append("\n".join(s))
    return len(rows), "\n\n".join(out)


n_det, det = emit("details", "D", "Details")
n_tree, tre = emit("trees", "T", "Trees")

block = ('[node name="Details" type="Node2D" parent="."]\n\n' + det +
         '\n\n[node name="Trees" type="Node2D" parent="."]\n\n' + tre + "\n\n")

# Find the project root from this script's location (apps/game/tools/).
# Hard-coding an absolute path would break other checkouts.
P = str(Path(__file__).resolve().parents[1] / "scenes" / "gameplay" / "night_forest.tscn")
src = open(P, encoding="utf-8").read()
start = src.index('[node name="Details" type="Node2D" parent="."]')
end = src.index('[node name="CanopyShade" type="Sprite2D" parent="."]')
open(P, "w", encoding="utf-8", newline="\n").write(src[:start] + block + src[end:])

xs = [it[0] for it in items]
print("details=%d trees=%d total=%d" % (n_det, n_tree, n_det + n_tree))
print("base x range %.0f..%.0f   base y range %.0f..%.0f"
      % (min(xs), max(xs), min(it[1] for it in items), max(it[1] for it in items)))
