#!/usr/bin/env python3
"""Focused regressions for deterministic variant grading across CPUs.

``pack_painted_world._grade`` saturates each variant figure through a blend
of the form ``a + factor * (b - a)``. Pillow runs that blend in C binary32,
which rounds the multiply and the add once on fused-multiply-add builds
(the Mac the art was approved on) and twice elsewhere (Linux x86_64), so
boundary bytes differ by host: glow's saturation 1.22 disagrees at 179 of
the 65,536 byte pairs, e.g. (63, 13) bakes 1 fused and 2 separate, and the
four marsh_glow sheets fail the Linux freshness check. The generator blends
saturation in ``_stable_blend_byte`` with an explicit fused rounding
contract, and these checks pin it, the safety of the steps that stay
native, and the exact real-variant bake:

    node scripts/python.mjs -B apps/game/tools/test_grade_blend_checks.py
"""

from __future__ import annotations

import struct
import sys

from PIL import Image

import pack_painted_world as painted


def _f32(value: float) -> float:
    return struct.unpack("f", struct.pack("f", value))[0]


def _fused(a: int, b: int, factor: float) -> int:
    """Approved side: binary32 factor, exact double sum, one rounding."""
    exact = float(_f32(factor)) * (b - a) + a
    return min(255, max(0, int(_f32(exact))))


def _separate(a: int, b: int, factor: float) -> int:
    """The other native side: the multiply rounds, then the add rounds."""
    product = _f32(float(_f32(factor)) * (b - a))
    return min(255, max(0, int(_f32(product + a))))


## Mirror of the (saturation, brightness, contrast) triples in
## pack_painted_world._grade. The real-bake case below is the backstop if a
## factor here drifts from the generator; the sweeps pin each factor's side.
SATURATION_FACTORS = (1.12, 1.05, 1.06, 0.98, 1.22)
CONTRAST_FACTORS = (1.02, 1.06, 1.03, 1.0)
## Fused/separate disagreement counts over the whole byte square per
## saturation factor: pure binary32 math, the same on every host.
SATURATION_BOUNDARIES = {1.22: 179, 1.12: 89, 0.98: 171, 1.05: 0, 1.06: 0}


def _measured_boundary_pairs_bake_fused() -> None:
    # The brief's pair plus one real pose pair per affected variant: each
    # must bake the fused value, and each must actually sit on the
    # boundary (the separately rounded value differs), or the case is
    # vacuous and proves nothing about the rounding side.
    for a, b, factor, want in (
        (63, 13, 1.22, 1),
        (149, 49, 1.22, 26),
        (150, 0, 0.98, 2),
    ):
        got = painted._stable_blend_byte(a, b, factor)
        assert got == want, (
            f"({a}, {b}) @{factor} blends {got}, want fused {want}")
        other = _separate(a, b, factor)
        assert other != want, (
            f"({a}, {b}) @{factor} is off the boundary: separate is {other}")


def _saturation_matches_fused_on_every_pair() -> None:
    # Every saturation factor _grade uses, over all 65,536 byte pairs: the
    # generator follows the fused contract exactly, and the boundary counts
    # match the known math, so a factor edit re-proves its own side.
    for factor in SATURATION_FACTORS:
        boundaries = 0
        for a in range(256):
            for b in range(256):
                want = _fused(a, b, factor)
                got = painted._stable_blend_byte(a, b, factor)
                assert got == want, (
                    f"({a}, {b}) @{factor} blends {got}, want fused {want}")
                if _separate(a, b, factor) != want:
                    boundaries += 1
        assert boundaries == SATURATION_BOUNDARIES[factor], (
            f"@{factor} has {boundaries} boundary pairs, "
            f"want {SATURATION_BOUNDARIES[factor]}")


def _native_steps_stay_boundary_free() -> None:
    # Brightness blends from black (a == 0), where fused and separate
    # rounding are the same value for every factor; sweep the dense grid
    # so any future factor is covered too. Contrast keeps its four factors
    # only while they disagree nowhere on the byte square: a factor edit
    # that lands on the boundary fails here and must route through the
    # stable blend instead of staying native.
    factor = 0.90
    while factor <= 1.3001:
        for b in range(256):
            assert _fused(0, b, factor) == _separate(0, b, factor), (
                f"brightness @{factor:.2f} diverges at b={b}")
        factor = round(factor + 0.01, 2)
    for contrast in CONTRAST_FACTORS:
        for a in range(256):
            for b in range(256):
                assert _fused(a, b, contrast) == _separate(a, b, contrast), (
                    f"contrast @{contrast} diverges at ({a}, {b})")


def _grade_keeps_size_and_alpha() -> None:
    # No masters needed: an odd-sized synthetic figure keeps its shape and
    # every alpha level through the grade; only RGB may move.
    art = Image.new("RGBA", (12, 9), (0, 0, 0, 0))
    figure = Image.new("RGBA", (8, 6), (120, 40, 200, 255))
    art.alpha_composite(figure, (2, 2))
    soft = Image.new("RGBA", (2, 2), (10, 200, 90, 137))
    art.alpha_composite(soft, (5, 4))
    graded = painted._grade(art, "glow")
    assert graded.size == art.size, f"grade resized {graded.size}"
    assert graded.getchannel("A").tobytes() == art.getchannel("A").tobytes(), (
        "grade moved alpha")


def _guardian_bake_matches_committed_bytes() -> None:
    # The real variant bake: every guardian sheet, including the four
    # marsh_glow sheets Linux rejected, matches its committed RGBA pixels
    # exactly. A native blend restored on Linux fails here.
    if not painted.SOURCE_ROOT.is_dir():
        print("SKIP: painted masters absent; "
              "real-bake byte check not run (rounding sweeps still ran)")
        return
    baked = painted.bake_guardians()
    assert len(baked) == 44, f"guardian bake has {len(baked)} sheets, want 44"
    for path in sorted(baked, key=lambda p: p.name):
        label = path.relative_to(painted.GAME_ROOT).as_posix()
        assert path.is_file(), f"{label} is missing"
        committed = Image.open(path).convert("RGBA")
        fresh = baked[path].convert("RGBA")
        assert committed.size == fresh.size \
                and committed.tobytes() == fresh.tobytes(), (
            f"{label} differs from a fresh bake")


def _altered_channel_still_fails() -> None:
    # The production comparison rejects a single moved channel: flipping
    # one byte of one fresh sheet must surface that sheet, so no tolerance
    # can hide a rounding regression.
    if not painted.SOURCE_ROOT.is_dir():
        print("SKIP: painted masters absent; "
              "tamper check not run (rounding sweeps still ran)")
        return
    baked = painted.bake_guardians()
    assert not painted.check_committed(baked), (
        "fresh guardian bake already differs before tampering")
    victim = sorted(baked, key=lambda p: p.name)[0]
    tampered = baked[victim].convert("RGBA")
    raw = bytearray(tampered.tobytes())
    raw[len(raw) // 2] ^= 1
    altered = Image.frombytes("RGBA", tampered.size, bytes(raw))
    baked[victim] = altered
    problems = painted.check_committed(baked)
    label = victim.relative_to(painted.GAME_ROOT).as_posix()
    assert any(label in problem and "differs from a fresh bake" in problem
               for problem in problems), (
        f"one flipped channel in {label} passed: {problems}")


CASES = [
    ("measured boundary pairs bake the fused side",
     _measured_boundary_pairs_bake_fused),
    ("saturation matches fused rounding on every byte pair",
     _saturation_matches_fused_on_every_pair),
    ("native brightness/contrast steps stay boundary-free",
     _native_steps_stay_boundary_free),
    ("grade keeps size and alpha",
     _grade_keeps_size_and_alpha),
    ("guardian bake matches committed bytes",
     _guardian_bake_matches_committed_bytes),
    ("one altered channel still fails",
     _altered_channel_still_fails),
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
        print(f"{failures} grade-blend regression(s) failed")
        return 1
    print("check: grade-blend regressions pass")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
