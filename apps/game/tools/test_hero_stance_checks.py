#!/usr/bin/env python3
"""Focused regressions for the standing cloak keep (briefs 197, 199).

Knight's trailing cloak tore at the stance cut because its below-cut
paint rotated away with the rear shin. The packer now keeps the audited
staircase bands static (pack_painted_world.HERO_STANCE_KEEP) on a cloth
layer over the gathered legs. ``pack_painted_world._check_cloak_continuity``
pins the kept cloth against the walk donor; the negative controls below
rebake the heroes with the keep emptied and prove the slit returns, even
though the brief-196 corrected head stays in place. Brief 199 splits the
lower staircase (HERO_STANCE_KEEP_SPLIT): the rear shin crosses it in
cool gray, so only the warm trim tip stays while the stale shin
articulates away, and the guard also pins cloth opacity.

    node scripts/python.mjs -B apps/game/tools/test_hero_stance_checks.py
"""

from __future__ import annotations

import sys

from PIL import Image

import pack_painted_world as painted

## Audited tear signature on the pre-197 sheets: opaque donor cloth pixels
## (alpha >= 200) in the keep bands that read far (RGB drift > 40) from
## the donor per idle frame. The unkept rebake must reproduce these.
OLD_FAR = (176, 148, 148, 148)
## Audited shin/garment split (brief 199): in the side donor the cloak
## underside ends at row 165 and the rear shin crosses rows 166-177 in
## cool gray, except the warm gold trim tip (red minus blue >= 18). The
## x88+ zone starts right of the gathered standing legs.
SHIN_SPLIT_ROW = 166
SHIN_WARM_BIAS = 18
SHIN_ZONE_X = range(88, 98)
UNTOUCHED = tuple(
    hero for hero in painted.HEROES if hero != "knight")

_UNKEPT: dict | None = None


def _unkept_bake() -> dict:
    # The exact old slit: the same bake with the keep table emptied. The
    # head calibration stays active, so the probe fails on the cloak with
    # the corrected brief-196 head in place. Skips loudly without the
    # masters (the committed guard still ran).
    global _UNKEPT
    if _UNKEPT is not None:
        return _UNKEPT
    if not painted.SOURCE_ROOT.is_dir():
        print("SKIP: painted masters absent; "
              "old-slit negative control not run (committed guard still ran)")
        return {}
    saved = painted.HERO_STANCE_KEEP
    painted.HERO_STANCE_KEEP = {}
    try:
        _UNKEPT = painted.bake_heroes()
    finally:
        painted.HERO_STANCE_KEEP = saved
    return _UNKEPT


def _far_counts(image: Image.Image, facing: int, oy: int, hips: int,
                walk: Image.Image) -> int:
    # Opaque donor cloth pixels reading far from the donor in one frame.
    donor = walk.load()
    stood = image.load()
    far = 0
    for lo, hi, edge in painted.HERO_STANCE_KEEP["knight"]:
        for y in range(lo, hi + 1):
            if y < hips and oy > 0:
                continue
            xs = range(edge, 131) if facing == 2 else \
                range(144 - 131, 144 - edge)
            for x in xs:
                want = donor[facing * 144 + x, y]
                if want[3] < 200:
                    continue
                got = stood[facing * 144 + x, oy + y]
                drift = max(abs(want[channel] - got[channel])
                            for channel in (0, 1, 2))
                if drift > 40:
                    far += 1
    return far


def _committed_cloak_holds() -> None:
    # The committed-output guard reads the shipped sheets only: no masters,
    # no bake, no silent skip when the sources are unavailable.
    problems = painted._check_cloak_continuity()
    assert not problems, f"committed knight idle keeps a cloak tear: {problems}"


def _old_slit_fails() -> None:
    # Negative control on the exact old bytes: the unkept rebake restores
    # the slit, and every idle frame fails the continuity check on both
    # mirrors while wearing the corrected head.
    baked = _unkept_bake()
    if not baked:
        return
    path = painted.HERO_ROOT / "knight" / "idle.png"
    probe = baked[path]
    walk = baked[painted.HERO_ROOT / "knight" / "walk.png"]
    hips = painted.HERO_IDLE_HIPS["knight"]
    neck = painted.HERO_IDLE_NECK["knight"]
    for facing in (2, 3):
        for frame in range(4):
            oy = frame * 192
            assert not painted._cloak_bands_match(walk, probe, facing, oy, hips), (
                f"unkept knight idle frame {frame} facing {facing} passed")
    head = probe.crop((2 * 144, 0, 3 * 144, neck))
    fixed = Image.open(path).convert("RGBA").crop((2 * 144, 0, 3 * 144, neck))
    assert painted._flat_bytes(head) == painted._flat_bytes(fixed), (
        "probe lost the corrected brief-196 head")


def _probe_matches_the_audited_slit() -> None:
    # The probe above is only honest if it reproduces the audited tear
    # signature, not some other displacement.
    baked = _unkept_bake()
    if not baked:
        return
    probe = baked[painted.HERO_ROOT / "knight" / "idle.png"]
    walk = baked[painted.HERO_ROOT / "knight" / "walk.png"]
    hips = painted.HERO_IDLE_HIPS["knight"]
    for frame in range(4):
        far = _far_counts(probe, 2, frame * 192, hips, walk)
        assert far == OLD_FAR[frame], (
            f"unkept frame {frame} reads {far} far pixels, "
            f"audited {OLD_FAR[frame]}")


def _transparent_cloth_fails() -> None:
    # The guard must pin opacity, not just RGB: zeroing the alpha of
    # every guard-covered cloth pixel while keeping its RGB hidden must
    # fail, even though no RGB drifted.
    walk = Image.open(painted.HERO_ROOT / "knight" / "walk.png")
    walk = walk.convert("RGBA")
    idle = Image.open(painted.HERO_ROOT / "knight" / "idle.png")
    idle = idle.convert("RGBA")
    donor = walk.load()
    mutant = idle.copy()
    holes = mutant.load()
    cleared = 0
    for lo, hi, edge in painted.HERO_STANCE_KEEP["knight"]:
        for y in range(lo, hi + 1):
            for x in range(edge, 131):
                want = donor[2 * 144 + x, y]
                if want[3] < 200:
                    continue
                if y >= SHIN_SPLIT_ROW \
                        and want[0] - want[2] < SHIN_WARM_BIAS:
                    continue
                red, green, blue, _alpha = holes[2 * 144 + x, y]
                holes[2 * 144 + x, y] = (red, green, blue, 0)
                cleared += 1
    assert cleared > 0, "transparent control covered no cloth pixels"
    hips = painted.HERO_IDLE_HIPS["knight"]
    assert not painted._cloak_bands_match(walk, mutant, 2, 0, hips), (
        f"guard accepted {cleared} transparent cloth pixels with kept RGB")


def _no_kept_shin_gray() -> None:
    # Below the split row the only static cloth is the warm trim tip:
    # opaque cool paint in the lower staircase is stale rear shin that
    # must articulate away, on every frame and mirror. The zone starts
    # right of the gathered legs, so standing shins never trip it.
    idle = Image.open(painted.HERO_ROOT / "knight" / "idle.png")
    idle = idle.convert("RGBA")
    stood = idle.load()
    checked = 0
    for facing, xs in ((2, SHIN_ZONE_X),
                       (3, range(144 - 98, 144 - 88))):
        for frame in range(4):
            oy = frame * 192
            for y in range(SHIN_SPLIT_ROW, 178):
                for x in xs:
                    red, _green, blue, alpha = \
                        stood[facing * 144 + x, oy + y]
                    if alpha < 200:
                        continue
                    checked += 1
                    assert red - blue >= SHIN_WARM_BIAS, (
                        f"knight idle facing {facing} frame {frame} "
                        f"keeps shin gray at ({x}, {y}): "
                        f"R-B reads {red - blue}, "
                        f"want >= {SHIN_WARM_BIAS}")
    assert checked > 0, "shin-gray zone covered no opaque pixels"


def _untouched_heroes_keep_their_bytes() -> None:
    # Only knight has a keep entry: the same bake must reproduce every
    # other hero's committed sheets byte-exact.
    baked = _unkept_bake()
    if not baked:
        return
    for hero in UNTOUCHED:
        for sheet in ("walk", "idle", "portrait"):
            path = painted.HERO_ROOT / hero / f"{sheet}.png"
            committed = Image.open(path).convert("RGBA")
            assert baked[path].tobytes() == committed.tobytes(), (
                f"{hero}/{sheet}.png changed without a keep entry")


CASES = [
    ("committed knight idle keeps cloak continuity",
     _committed_cloak_holds),
    ("restored old slit fails in every frame and mirror", _old_slit_fails),
    ("the probe reproduces the audited tear signature",
     _probe_matches_the_audited_slit),
    ("transparent cloth with kept RGB fails",
     _transparent_cloth_fails),
    ("no kept shin gray below the split row",
     _no_kept_shin_gray),
    ("heroes without a keep entry keep their bytes",
     _untouched_heroes_keep_their_bytes),
]


def main() -> int:
    failures = 0
    for name, case in CASES:
        try:
            case()
        except AssertionError as error:
            failures += 1
            print(f"FAIL: {name}: {error}")
        else:
            print(f"PASS: {name}")
    if failures:
        print(f"{failures} hero-stance check regression(s) failed")
        return 1
    print("check: hero-stance check regressions pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
