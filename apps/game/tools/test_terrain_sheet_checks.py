#!/usr/bin/env python3
"""Focused regressions for the two terrain sheet checks.

`pack_terrain_structures.py --check` and `build_terrain_tilesets.py --check`
must accept any PNG encoding of the exact baked RGBA pixels (encoders differ
across machines) while rejecting missing, unreadable, corrupt, non-PNG,
wrongly shaped or wrongly formatted sheets. Every case writes only to a
temporary directory; the committed sheets on disk are never touched.

    node scripts/python.mjs -B apps/game/tools/test_terrain_sheet_checks.py
"""

from __future__ import annotations

import io
import sys
from collections.abc import Callable
from contextlib import redirect_stdout
from dataclasses import dataclass
from pathlib import Path
from tempfile import TemporaryDirectory

from PIL import Image

import build_terrain_tilesets as tilesets
import pack_terrain_structures as structures
import terrain_sheet_check as sheets

Pixel = tuple[int, int, int, int]


@dataclass(frozen=True)
class Fixture:
    label: str
    sheet: str
    baked: Image.Image
    encode: Callable[[Image.Image], bytes]


def _pixel_where(baked: Image.Image, want: Callable[[Pixel], bool]) -> tuple[int, int]:
    pixels = baked.load()
    assert pixels is not None
    for y in range(baked.height):
        for x in range(baked.width):
            pixel = pixels[x, y]
            assert len(pixel) == 4
            if want((pixel[0], pixel[1], pixel[2], pixel[3])):
                return (x, y)
    raise AssertionError("test setup: no matching pixel in the baked sheet")


def _opaque_spot(baked: Image.Image) -> tuple[int, int]:
    return _pixel_where(baked, lambda pixel: pixel[3] == 255)


def _clear_spot(baked: Image.Image) -> tuple[int, int]:
    return _pixel_where(baked, lambda pixel: pixel[3] == 0)


def _save(image: Image.Image, path: Path, **options) -> None:
    image.save(path, format="PNG", **options)


def _expect_current(path: Path, baked: Image.Image) -> None:
    problem = sheets.check_sheet(path, baked)
    assert problem is None, f"expected current, got: {problem}"


def _expect_stale(path: Path, baked: Image.Image, sheet: str, *needles: str) -> None:
    problem = sheets.check_sheet(path, baked)
    assert problem is not None, "expected a problem, the sheet passed"
    assert sheet in problem, f"problem names no sheet: {problem}"
    for needle in needles:
        assert needle in problem, f"missing {needle!r} in: {problem}"


def _flip_one_pixel(path: Path) -> None:
    with Image.open(path) as stored:
        edited = stored.convert("RGBA")
    x, y = _opaque_spot(edited)
    pixels = edited.load()
    assert pixels is not None
    red, green, blue, alpha = pixels[x, y]
    pixels[x, y] = ((red + 1) % 256, green, blue, alpha)
    _save(edited, path)


def _alternative_encoding_passes(root: Path, fixture: Fixture) -> None:
    differed = False
    for level in (0, 1, 9):
        path = root / fixture.sheet
        _save(fixture.baked, path, compress_level=level)
        differed = differed or path.read_bytes() != fixture.encode(fixture.baked)
        _expect_current(path, fixture.baked)
    assert differed, "no candidate level produced an alternative encoding"


def _opaque_rgb_change_fails(root: Path, fixture: Fixture) -> None:
    x, y = _opaque_spot(fixture.baked)
    edited = fixture.baked.copy()
    pixels = edited.load()
    assert pixels is not None
    red, green, blue, alpha = pixels[x, y]
    pixels[x, y] = ((red + 1) % 256, green, blue, alpha)
    path = root / fixture.sheet
    _save(edited, path)
    _expect_stale(path, fixture.baked, fixture.sheet,
                  "out of date", "decoded pixels differ")


def _alpha_change_fails(root: Path, fixture: Fixture) -> None:
    x, y = _opaque_spot(fixture.baked)
    edited = fixture.baked.copy()
    pixels = edited.load()
    assert pixels is not None
    red, green, blue, _alpha = pixels[x, y]
    pixels[x, y] = (red, green, blue, 254)
    path = root / fixture.sheet
    _save(edited, path)
    _expect_stale(path, fixture.baked, fixture.sheet,
                  "out of date", "decoded pixels differ")


def _clear_rgb_change_fails(root: Path, fixture: Fixture) -> None:
    x, y = _clear_spot(fixture.baked)
    edited = fixture.baked.copy()
    pixels = edited.load()
    assert pixels is not None
    red, green, blue, _alpha = pixels[x, y]
    pixels[x, y] = ((red + 10) % 256, (green + 20) % 256, (blue + 30) % 256, 0)
    path = root / fixture.sheet
    _save(edited, path)
    _expect_stale(path, fixture.baked, fixture.sheet,
                  "out of date", "decoded pixels differ")


def _resized_shape_fails(root: Path, fixture: Fixture) -> None:
    path = root / fixture.sheet
    width, height = fixture.baked.size
    _save(fixture.baked.crop((0, 0, width - 1, height)), path)
    _expect_stale(path, fixture.baked, fixture.sheet,
                  "out of date", f"want {width}x{height}")


def _missing_sheet_fails(root: Path, fixture: Fixture) -> None:
    _expect_stale(root / fixture.sheet, fixture.baked, fixture.sheet, "missing")


def _garbage_bytes_fail(root: Path, fixture: Fixture) -> None:
    path = root / fixture.sheet
    path.write_bytes(b"this is not a png file")
    _expect_stale(path, fixture.baked, fixture.sheet,
                  "unreadable", "missing PNG signature")


def _truncated_png_fails(root: Path, fixture: Fixture) -> None:
    path = root / fixture.sheet
    payload = fixture.encode(fixture.baked)
    path.write_bytes(payload[: len(payload) // 2])
    _expect_stale(path, fixture.baked, fixture.sheet, "unreadable")


def _crc_corrupt_png_fails(root: Path, fixture: Fixture) -> None:
    payload = bytearray(fixture.encode(fixture.baked))
    marker = payload.find(b"IDAT", 8)
    assert marker != -1, "test setup: no IDAT chunk in the encoded sheet"
    at = marker + 4 + 20
    assert at < len(payload) - 12, "test setup: IDAT chunk too small to corrupt"
    payload[at] ^= 0xFF
    path = root / fixture.sheet
    path.write_bytes(bytes(payload))
    _expect_stale(path, fixture.baked, fixture.sheet, "unreadable", "CRC mismatch")


def _trailing_bytes_fail(root: Path, fixture: Fixture) -> None:
    path = root / fixture.sheet
    path.write_bytes(fixture.encode(fixture.baked) + b"trailing-junk")
    _expect_stale(path, fixture.baked, fixture.sheet,
                  "unreadable", "trailing data after IEND")


def _non_rgba_format_fails(root: Path, fixture: Fixture) -> None:
    rgb_path = root / fixture.sheet
    _save(fixture.baked.convert("RGB"), rgb_path)
    _expect_stale(rgb_path, fixture.baked, fixture.sheet, "unreadable", "RGBA 8-bit")
    pal_path = root / fixture.sheet
    _save(fixture.baked.convert("RGB").quantize(colors=64), pal_path)
    _expect_stale(pal_path, fixture.baked, fixture.sheet, "unreadable", "RGBA 8-bit")


MATRIX = [
    ("alternative PNG compression of identical pixels passes",
     _alternative_encoding_passes),
    ("one opaque RGB pixel change fails", _opaque_rgb_change_fails),
    ("one alpha value change fails", _alpha_change_fails),
    ("a clear pixel's RGB change fails", _clear_rgb_change_fails),
    ("changed dimensions fail", _resized_shape_fails),
    ("a missing sheet fails", _missing_sheet_fails),
    ("non-PNG bytes fail", _garbage_bytes_fail),
    ("a truncated PNG fails", _truncated_png_fails),
    ("a CRC-corrupt PNG fails", _crc_corrupt_png_fails),
    ("trailing bytes fail", _trailing_bytes_fail),
    ("a non-RGBA PNG fails", _non_rgba_format_fails),
]


def _run_main(module, out_attr: str, out_dir: Path, argv0: str) -> int:
    old_root, old_argv = getattr(module, out_attr), sys.argv
    setattr(module, out_attr, out_dir)
    sys.argv = [argv0, "--check"]
    try:
        with redirect_stdout(io.StringIO()):
            return module.main()
    finally:
        setattr(module, out_attr, old_root)
        sys.argv = old_argv


def _structures_cli(root: Path) -> None:
    def write_all(out_dir: Path, **options) -> None:
        for terrain, names in structures.SHEETS.items():
            _save(structures._bake(names), out_dir / f"{terrain}_props.png", **options)

    def differs(out_dir: Path) -> bool:
        return any(
            (out_dir / f"{terrain}_props.png").read_bytes()
            != structures._png(structures._bake(names))
            for terrain, names in structures.SHEETS.items()
        )

    def run(out_dir: Path) -> int:
        return _run_main(structures, "OUT_ROOT", out_dir, "pack_terrain_structures.py")

    current = root / "current"
    current.mkdir()
    write_all(current, compress_level=1)
    assert differs(current), "alternative encodings came out byte-identical"
    assert run(current) == 0, "identical pixels in another encoding must pass"

    stale = root / "stale"
    stale.mkdir()
    write_all(stale, compress_level=1)
    _flip_one_pixel(stale / "marsh_props.png")
    assert run(stale) == 1, "one changed pixel must fail the check"

    corrupt = root / "corrupt"
    corrupt.mkdir()
    write_all(corrupt, compress_level=1)
    (corrupt / "frost_props.png").write_bytes(b"this is not a png file")
    assert run(corrupt) == 1, "a corrupt sheet must fail the check, not crash it"

    missing = root / "missing"
    missing.mkdir()
    write_all(missing, compress_level=1)
    (missing / "ruins_props.png").unlink()
    assert run(missing) == 1, "a missing sheet must fail the check"


def _tilesets_cli(root: Path) -> None:
    with Image.open(tilesets.SOURCE) as source_file:
        source = source_file.convert("RGBA")

    def write_all(out_dir: Path, **options) -> None:
        for name, palette in tilesets.PALETTES.items():
            _save(tilesets._recolour(source, palette),
                  out_dir / f"{name}_nature.png", **options)

    def differs(out_dir: Path) -> bool:
        return any(
            (out_dir / f"{name}_nature.png").read_bytes()
            != tilesets._png(tilesets._recolour(source, palette))
            for name, palette in tilesets.PALETTES.items()
        )

    def run(out_dir: Path) -> int:
        return _run_main(tilesets, "TERRAIN_DIR", out_dir, "build_terrain_tilesets.py")

    current = root / "current"
    current.mkdir()
    write_all(current, compress_level=1)
    assert differs(current), "alternative encodings came out byte-identical"
    assert run(current) == 0, "identical pixels in another encoding must pass"

    stale = root / "stale"
    stale.mkdir()
    write_all(stale, compress_level=1)
    _flip_one_pixel(stale / "marsh_nature.png")
    assert run(stale) == 1, "one changed pixel must fail the check"

    corrupt = root / "corrupt"
    corrupt.mkdir()
    write_all(corrupt, compress_level=1)
    (corrupt / "frost_nature.png").write_bytes(b"this is not a png file")
    assert run(corrupt) == 1, "a corrupt sheet must fail the check, not crash it"

    missing = root / "missing"
    missing.mkdir()
    write_all(missing, compress_level=1)
    (missing / "ruins_nature.png").unlink()
    assert run(missing) == 1, "a missing sheet must fail the check"


def main() -> int:
    with Image.open(tilesets.SOURCE) as source_file:
        nature_source = source_file.convert("RGBA")
    fixtures = [
        Fixture("props", "frost_props.png",
                structures._bake(structures.SHEETS["frost"]), structures._png),
        Fixture("nature", "frost_nature.png",
                tilesets._recolour(nature_source, tilesets.PALETTES["frost"]),
                tilesets._png),
    ]
    failures = 0
    with TemporaryDirectory(prefix="terrain-sheet-checks-") as tmp:
        root = Path(tmp)
        index = 0
        for fixture in fixtures:
            for name, case in MATRIX:
                case_root = root / f"case-{index}"
                case_root.mkdir()
                index += 1
                try:
                    case(case_root, fixture)
                except AssertionError as error:
                    failures += 1
                    print(f"FAIL: {fixture.label}: {name}: {error}")
                else:
                    print(f"PASS: {fixture.label}: {name}")
        for label, cli in (("props", _structures_cli), ("nature", _tilesets_cli)):
            cli_root = root / f"cli-{label}"
            cli_root.mkdir()
            try:
                cli(cli_root)
            except AssertionError as error:
                failures += 1
                print(f"FAIL: {label}: check exit codes: {error}")
            else:
                print(f"PASS: {label}: check exit codes")
    if failures:
        print(f"{failures} terrain sheet check regression(s) failed")
        return 1
    print("check: terrain sheet check regressions pass")
    return 0


if __name__ == "__main__":
    sys.exit(main())
