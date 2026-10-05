#!/usr/bin/env python3
"""Focused regressions for the cross-facing head proportions (brief 196).

The side-walk donors painted the warden, knight and eclipse side heads
about 15% smaller than their frontal heads; the packer now grows those
three side heads to their frontal proportion
(pack_painted_world.HERO_SIDE_HEAD_CAL) while dancer, keeper and sage
keep their exact bytes. ``pack_painted_world._check_face_proportions``
pins the committed sheets against audited face/skull landmarks; the
negative controls below rebake the heroes with the calibration disabled
and prove the restored old side heads fail that check, even pasted
identically into every walk and idle frame.

    node scripts/python.mjs -B apps/game/tools/test_hero_face_checks.py
"""

from __future__ import annotations

import sys

from PIL import Image

import pack_painted_world as painted

## Audited old side-head measures (face height / skull width, cell px)
## the uncalibrated bake must reproduce, from the pre-196 sheets.
OLD_SIDE = {
    "warden": (16, 42),
    "knight": (9, 39),
    "eclipse": (12, 43),
}
CALIBRATED = tuple(OLD_SIDE)
UNTOUCHED = tuple(
    hero for hero in painted.HEROES if hero not in OLD_SIDE)


def _committed_sheets_pass() -> None:
    # The committed-output guard reads the shipped sheets only: no masters,
    # no bake, no silent skip when the sources are unavailable.
    problems = painted._check_face_proportions()
    assert not problems, f"committed heroes keep a shrunken side head: {problems}"


_UNCALIBRATED: dict | None = None


def _uncalibrated_bake() -> dict:
    # The exact old side heads: the same bake with the calibration table
    # emptied, baked once and shared by the controls below. Skips loudly
    # without the masters (the committed guard above still ran).
    global _UNCALIBRATED
    if _UNCALIBRATED is not None:
        return _UNCALIBRATED
    if not painted.SOURCE_ROOT.is_dir():
        print("SKIP: painted masters absent; "
              "old-head negative control not run (committed guard still ran)")
        return {}
    saved = painted.HERO_SIDE_HEAD_CAL
    painted.HERO_SIDE_HEAD_CAL = {}
    try:
        _UNCALIBRATED = painted.bake_heroes()
    finally:
        painted.HERO_SIDE_HEAD_CAL = saved
    return _UNCALIBRATED


def _old_side_heads_fail() -> None:
    # Negative control on the exact old bytes: each old side head, pasted
    # identically into every walk and idle frame, must fail the face and
    # skull bounds the calibrated heads pass.
    baked = _uncalibrated_bake()
    if not baked:
        return
    for hero in CALIBRATED:
        neck = painted.HERO_IDLE_NECK[hero]
        old_head = baked[painted.HERO_ROOT / hero / "walk.png"].crop(
            (2 * 144, 0, 3 * 144, neck))
        for sheet in ("walk", "idle"):
            path = painted.HERO_ROOT / hero / f"{sheet}.png"
            probe = Image.open(path).convert("RGBA")
            for frame in range(4):
                probe.paste(old_head, (2 * 144, frame * 192))
            problems = painted._face_problems_for(hero, sheet, probe)
            assert any("side face" in problem for problem in problems), (
                f"old {hero} {sheet} side head passed the face bound")
            assert any("side skull" in problem for problem in problems), (
                f"old {hero} {sheet} side head passed the skull bound")


def _probe_matches_the_audited_defect() -> None:
    # The probe above is only honest if it reproduces the audited old
    # measures, not some other small head.
    baked = _uncalibrated_bake()
    if not baked:
        return
    for hero, (want_face, want_skull) in OLD_SIDE.items():
        side = baked[painted.HERO_ROOT / hero / "walk.png"].crop(
            (2 * 144, 0, 3 * 144, 192))
        face = painted._face_height(side, hero, 2)
        skull = painted._skull_width(side, hero, 2)
        assert face == want_face, (
            f"old {hero} side face reads {face}px, audited {want_face}")
        assert skull == want_skull, (
            f"old {hero} side skull reads {skull}px, audited {want_skull}")


def _untouched_heroes_keep_their_bytes() -> None:
    # Dancer, keeper and sage have no calibration entry: the same bake
    # must reproduce their committed sheets byte-exact.
    baked = _uncalibrated_bake()
    if not baked:
        return
    for hero in UNTOUCHED:
        for sheet in ("walk", "idle", "portrait"):
            path = painted.HERO_ROOT / hero / f"{sheet}.png"
            committed = Image.open(path).convert("RGBA")
            assert baked[path].tobytes() == committed.tobytes(), (
                f"{hero}/{sheet}.png changed without a calibration entry")


CASES = [
    ("committed sheets keep cross-facing proportions",
     _committed_sheets_pass),
    ("restored old side heads fail in every state", _old_side_heads_fail),
    ("the probe reproduces the audited old measures",
     _probe_matches_the_audited_defect),
    ("heroes without calibration keep their bytes",
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
        print(f"{failures} hero-face check regression(s) failed")
        return 1
    print("check: hero-face check regressions pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
