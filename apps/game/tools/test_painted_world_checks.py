#!/usr/bin/env python3
"""Focused regressions for the painted-world neighbour-fragment guard.

The biome prop master holds figures that touch across gridlines; the contact
split used to strand neighbour crown lobes on the wrong side as detached
foliage rectangles beside the pines (forest/camp prop1, frost/ruins prop3).
``pack_painted_world._check_prop_intrusions`` pins the committed terrain
sheets against that pattern without needing the masters, and the severing
pass in ``_exact_cells`` removes the lobes at the source.

    node scripts/python.mjs -B apps/game/tools/test_painted_world_checks.py
"""

from __future__ import annotations

import sys

from PIL import Image

import pack_painted_world as painted


def _committed_guard_passes() -> None:
    # The committed-output guard reads the shipped sheets only: no masters,
    # no bake, no silent skip when the sources are unavailable.
    problems = painted._check_prop_intrusions()
    assert not problems, f"committed terrain keeps intrusions: {problems}"


def _original_cells_fail_without_severing() -> None:
    # Negative control on the exact original components: the same master
    # split with the severing pass disabled must keep the four confirmed
    # lobes, and the cell guard must flag each of them.
    if not painted.SOURCE_ROOT.is_dir():
        print("SKIP: painted masters absent; "
              "exact negative control not run (committed guard still ran)")
        return
    rows = painted._prop_row(sever_split=False)
    for row, column in ((0, 1), (2, 1), (3, 3), (5, 3)):
        label = f"{painted.BIOMES[row]} prop{column}"
        problems = painted._cell_sidecars(rows[row][column], label)
        assert problems, f"unsevered {label} passed the cell guard"
        assert any("detached blob" in problem for problem in problems), (
            f"unsevered {label} failed for the wrong reason: {problems}")
    fixed = painted._prop_row(sever_split=True)
    for row, column in ((0, 1), (2, 1), (3, 3), (5, 3)):
        label = f"{painted.BIOMES[row]} prop{column}"
        problems = painted._cell_sidecars(fixed[row][column], label)
        assert not problems, f"severed {label} still flagged: {problems}"


def _synthetic_sidecar_fails() -> None:
    # The rule itself, without masters or production art: a detached blob
    # beside the figure fails, interior and x-overlapping masses pass.
    cell = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    figure = Image.new("RGBA", (80, 120), (40, 90, 60, 255))
    cell.alpha_composite(figure, (80, 40))
    sidecar = Image.new("RGBA", (30, 60), (30, 60, 120, 255))
    cell.alpha_composite(sidecar, (20, 60))
    problems = painted._cell_sidecars(cell, "synthetic")
    assert len(problems) == 1 and "left of" in problems[0], (
        f"synthetic sidecar must fail left of the figure: {problems}")


def _synthetic_legitimate_passes() -> None:
    cell = Image.new("RGBA", (192, 192), (0, 0, 0, 0))
    figure = Image.new("RGBA", (80, 120), (40, 90, 60, 255))
    cell.alpha_composite(figure, (56, 40))
    # Ground detail below the figure, x-overlapping like the stacked crates.
    detail = Image.new("RGBA", (60, 20), (90, 70, 50, 255))
    cell.alpha_composite(detail, (66, 162))
    problems = painted._cell_sidecars(cell, "synthetic")
    assert not problems, f"legitimate ground detail must pass: {problems}"


CASES = [
    ("committed terrain passes the intrusion guard", _committed_guard_passes),
    ("unsevered master split keeps the original lobes",
     _original_cells_fail_without_severing),
    ("a synthetic detached sidecar fails", _synthetic_sidecar_fails),
    ("synthetic legitimate detail passes", _synthetic_legitimate_passes),
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
        print(f"{failures} painted-world check regression(s) failed")
        return 1
    print("check: painted-world check regressions pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
