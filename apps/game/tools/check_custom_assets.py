#!/usr/bin/env python3
"""Check machine-readable contracts for custom pixel assets.

Read PNG chunks and scanlines with no external image library. Default run
Default run compares finished files under ``assets/custom`` to the contract. Pass ``--id`` and
together, inspect one candidate PNG before copying it into the repo.
"""

from __future__ import annotations

import argparse
import json
import re
import struct
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any


PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
PNG_MAX_DIMENSION = 8192
PNG_MAX_PIXELS = 16_777_216
VALID_ALPHA_MODES = {"binary", "graded", "opaque"}
VALID_STATUSES = {"planned", "final", "required"}
ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9._-]*$")
FORBIDDEN_LEGACY_VISUAL_PATTERNS = (
    re.compile(r"res://assets/third_party/ninja_adventure/[^\s\"']+\.png"),
    re.compile(r"res://assets/derived/title/[^\s\"']+\.png"),
)
RUNTIME_TEXT_ROOTS = ("resources", "scenes", "scripts")
RUNTIME_TEXT_SUFFIXES = {".gd", ".tres", ".tscn"}

TOOL_DIR = Path(__file__).resolve().parent
DEFAULT_PROJECT_ROOT = TOOL_DIR.parent
DEFAULT_CONTRACTS = TOOL_DIR / "custom_asset_contracts.json"


class AssetCheckError(Exception):
    """A contract or PNG error that can be shown to the user as-is."""


@dataclass(frozen=True)
class PngImage:
    width: int
    height: int
    bit_depth: int
    color_type: int
    pixels: bytes

    @property
    def alpha_mode(self) -> str:
        alphas = self.pixels[3::4]
        if all(alpha == 255 for alpha in alphas):
            return "opaque"
        if any(0 < alpha < 255 for alpha in alphas):
            return "graded"
        return "binary"

    @property
    def visible_rgb_colors(self) -> int:
        colors = {
            (self.pixels[index], self.pixels[index + 1], self.pixels[index + 2])
            for index in range(0, len(self.pixels), 4)
            if self.pixels[index + 3] > 0
        }
        return len(colors)

    @property
    def alpha_levels(self) -> int:
        return len(set(self.pixels[3::4]))


def _paeth(left: int, above: int, upper_left: int) -> int:
    estimate = left + above - upper_left
    left_distance = abs(estimate - left)
    above_distance = abs(estimate - above)
    upper_left_distance = abs(estimate - upper_left)
    if left_distance <= above_distance and left_distance <= upper_left_distance:
        return left
    if above_distance <= upper_left_distance:
        return above
    return upper_left


def _unfilter_rgba(raw: bytes, width: int, height: int) -> bytes:
    bytes_per_pixel = 4
    stride = width * bytes_per_pixel
    expected = (stride + 1) * height
    if len(raw) != expected:
        raise AssetCheckError(
            f"IDAT decompressed size is {len(raw)} bytes "
            f"(expected {expected} bytes)"
        )

    pixels = bytearray(width * height * bytes_per_pixel)
    previous = bytearray(stride)
    source_offset = 0
    output_offset = 0

    for row_index in range(height):
        filter_type = raw[source_offset]
        source_offset += 1
        if filter_type > 4:
            raise AssetCheckError(
                f"scanline {row_index + 1} filter {filter_type} is invalid"
            )

        encoded = raw[source_offset : source_offset + stride]
        source_offset += stride
        current = bytearray(stride)
        for index, value in enumerate(encoded):
            left = current[index - bytes_per_pixel] if index >= bytes_per_pixel else 0
            above = previous[index]
            upper_left = (
                previous[index - bytes_per_pixel]
                if index >= bytes_per_pixel
                else 0
            )
            if filter_type == 0:
                predictor = 0
            elif filter_type == 1:
                predictor = left
            elif filter_type == 2:
                predictor = above
            elif filter_type == 3:
                predictor = (left + above) // 2
            else:
                predictor = _paeth(left, above, upper_left)
            current[index] = (value + predictor) & 0xFF

        pixels[output_offset : output_offset + stride] = current
        output_offset += stride
        previous = current

    return bytes(pixels)


def _decompress_idat(compressed: bytes, expected: int) -> bytes:
    """Stop on the first extra byte if decompressed output exceeds the expected scanlines."""
    decoder = zlib.decompressobj()
    output = bytearray()
    remaining = compressed
    try:
        while remaining:
            capacity = expected + 1 - len(output)
            if capacity <= 0:
                raise AssetCheckError(
                    f"IDAT decompressed size is larger than expected {expected} bytes"
                )
            before = len(remaining)
            output.extend(decoder.decompress(remaining, capacity))
            remaining = decoder.unconsumed_tail
            if remaining and len(remaining) == before and len(output) <= expected:
                raise AssetCheckError("IDAT decompression is not making progress")
        capacity = expected + 1 - len(output)
        if capacity <= 0:
            raise AssetCheckError(
                f"IDAT decompressed size is larger than expected {expected} bytes"
            )
        output.extend(decoder.flush(capacity))
    except zlib.error as error:
        raise AssetCheckError(f"cannot decompress IDAT: {error}") from error

    if len(output) > expected:
        raise AssetCheckError(
            f"IDAT decompressed size is larger than expected {expected} bytes"
        )
    if not decoder.eof:
        raise AssetCheckError("IDAT compressed stream did not end")
    if decoder.unused_data:
        raise AssetCheckError("trailing data after the IDAT compressed stream")
    return bytes(output)


def read_rgba_png(path: Path) -> PngImage:
    try:
        data = path.read_bytes()
    except OSError as error:
        raise AssetCheckError(f"cannot read file: {error}") from error

    if not data.startswith(PNG_SIGNATURE):
        raise AssetCheckError("missing PNG signature")

    offset = len(PNG_SIGNATURE)
    ihdr: tuple[int, int, int, int, int, int, int] | None = None
    idat_parts: list[bytes] = []
    saw_iend = False
    saw_idat = False
    idat_sequence_ended = False
    chunk_index = 0

    while offset < len(data):
        if offset + 12 > len(data):
            raise AssetCheckError("PNG chunk header is truncated")
        length = struct.unpack_from(">I", data, offset)[0]
        chunk_type = data[offset + 4 : offset + 8]
        chunk_end = offset + 12 + length
        if chunk_end > len(data):
            name = chunk_type.decode("ascii", "replace")
            raise AssetCheckError(f"{name} chunk data is truncated")

        payload = data[offset + 8 : offset + 8 + length]
        stored_crc = struct.unpack_from(">I", data, offset + 8 + length)[0]
        computed_crc = zlib.crc32(chunk_type)
        computed_crc = zlib.crc32(payload, computed_crc) & 0xFFFFFFFF
        if stored_crc != computed_crc:
            name = chunk_type.decode("ascii", "replace")
            raise AssetCheckError(f"{name} chunk CRC mismatch")

        if chunk_index == 0 and chunk_type != b"IHDR":
            raise AssetCheckError("first PNG chunk is not IHDR")
        if chunk_type == b"IHDR":
            if ihdr is not None:
                raise AssetCheckError("more than one IHDR chunk")
            if length != 13:
                raise AssetCheckError("IHDR chunk length is not 13 bytes")
            ihdr = struct.unpack(">IIBBBBB", payload)
        elif chunk_type == b"IDAT":
            if ihdr is None:
                raise AssetCheckError("IDAT appeared before IHDR")
            if idat_sequence_ended:
                raise AssetCheckError("IDAT chunks are not contiguous")
            idat_parts.append(payload)
            saw_idat = True
        elif chunk_type == b"PLTE":
            if saw_idat:
                raise AssetCheckError("PLTE chunk is after IDAT")
            if length == 0 or length > 768 or length % 3 != 0:
                raise AssetCheckError("PLTE chunk length is invalid")
        elif chunk_type == b"IEND":
            if length != 0:
                raise AssetCheckError("IEND chunk is not empty")
            saw_iend = True
            offset = chunk_end
            break
        elif chunk_type[:1].isupper():
            name = chunk_type.decode("ascii", "replace")
            raise AssetCheckError(f"unsupported critical PNG chunk: {name}")

        if saw_idat and chunk_type not in {b"IDAT", b"IEND"}:
            idat_sequence_ended = True
        chunk_index += 1
        offset = chunk_end

    if ihdr is None:
        raise AssetCheckError("missing IHDR chunk")
    if not idat_parts:
        raise AssetCheckError("missing IDAT chunk")
    if not saw_iend:
        raise AssetCheckError("missing IEND chunk")
    if offset != len(data):
        raise AssetCheckError("trailing data after IEND")

    width, height, bit_depth, color_type, compression, filtering, interlace = ihdr
    if width <= 0 or height <= 0:
        raise AssetCheckError("PNG width and height must be >= 1")
    if width > PNG_MAX_DIMENSION or height > PNG_MAX_DIMENSION:
        raise AssetCheckError(
            f"a PNG side may not exceed {PNG_MAX_DIMENSION}px"
        )
    if width * height > PNG_MAX_PIXELS:
        raise AssetCheckError(
            f"a PNG may not exceed {PNG_MAX_PIXELS:,} pixels"
        )
    if bit_depth != 8 or color_type != 6:
        raise AssetCheckError(
            "is not an RGBA 8-bit PNG "
            f"(bit depth={bit_depth}, color type={color_type})"
        )
    if compression != 0 or filtering != 0:
        raise AssetCheckError("unsupported PNG compression or filter method")
    if interlace != 0:
        raise AssetCheckError("interlaced PNG is not allowed")

    expected_raw_size = (width * 4 + 1) * height
    raw = _decompress_idat(b"".join(idat_parts), expected_raw_size)

    return PngImage(
        width=width,
        height=height,
        bit_depth=bit_depth,
        color_type=color_type,
        pixels=_unfilter_rgba(raw, width, height),
    )


def _positive_int(value: Any, field: str, asset_id: str, allow_zero: bool = False) -> int:
    minimum = 0 if allow_zero else 1
    if isinstance(value, bool) or not isinstance(value, int) or value < minimum:
        qualifier = ">= 0" if allow_zero else ">= 1"
        raise AssetCheckError(f"{asset_id}: {field} must be an integer {qualifier}")
    return value


def _normalize_padding(
    value: Any, asset_id: str
) -> dict[str, int]:
    sides = ("left", "right", "top", "bottom")
    if value is None:
        return {side: 0 for side in sides}
    if isinstance(value, int) and not isinstance(value, bool):
        amount = _positive_int(value, "frame_grid.edge_padding", asset_id, True)
        return {side: amount for side in sides}
    if not isinstance(value, dict):
        raise AssetCheckError(
            f"{asset_id}: frame_grid.edge_padding must be an int or per-side object"
        )
    unknown = sorted(set(value) - set(sides))
    if unknown:
        raise AssetCheckError(
            f"{asset_id}: unknown edge_padding side: {', '.join(unknown)}"
        )
    return {
        side: _positive_int(
            value.get(side, 0),
            f"frame_grid.edge_padding.{side}",
            asset_id,
            True,
        )
        for side in sides
    }


def load_contracts(path: Path) -> tuple[str, list[dict[str, Any]]]:
    try:
        document = json.loads(path.read_text(encoding="utf-8"))
    except OSError as error:
        raise AssetCheckError(f"cannot read contract file: {error}") from error
    except json.JSONDecodeError as error:
        raise AssetCheckError(
            f"contract JSON {error.lineno}:{error.colno}: {error.msg}"
        ) from error

    if not isinstance(document, dict) or document.get("version") != 1:
        raise AssetCheckError("contract top-level version must be 1")
    asset_root = document.get("asset_root")
    if not isinstance(asset_root, str) or not asset_root:
        raise AssetCheckError("contract top-level asset_root is required")
    root_parts = PurePosixPath(asset_root).parts
    if (
        PurePosixPath(asset_root).is_absolute()
        or "\\" in asset_root
        or ".." in root_parts
    ):
        raise AssetCheckError("asset_root must be an in-project POSIX path")

    defaults = document.get("defaults", {})
    entries = document.get("assets")
    if not isinstance(defaults, dict):
        raise AssetCheckError("defaults must be an object")
    if not isinstance(entries, list):
        raise AssetCheckError("assets must be an array")

    normalized: list[dict[str, Any]] = []
    seen_ids: set[str] = set()
    seen_paths: set[str] = set()
    for raw_entry in entries:
        if not isinstance(raw_entry, dict):
            raise AssetCheckError("each assets entry must be an object")
        entry = {**defaults, **raw_entry}
        asset_id = entry.get("id")
        relative_path = entry.get("path")
        if not isinstance(asset_id, str) or not ID_PATTERN.fullmatch(asset_id):
            raise AssetCheckError(f"invalid asset id: {asset_id!r}")
        if asset_id in seen_ids:
            raise AssetCheckError(f"duplicate asset id: {asset_id}")
        seen_ids.add(asset_id)

        if not isinstance(relative_path, str):
            raise AssetCheckError(f"{asset_id}: path is required")
        posix_path = PurePosixPath(relative_path)
        if (
            posix_path.is_absolute()
            or "\\" in relative_path
            or ".." in posix_path.parts
            or posix_path.suffix != ".png"
            or not (
                relative_path == asset_root
                or relative_path.startswith(asset_root.rstrip("/") + "/")
            )
        ):
            raise AssetCheckError(
                f"{asset_id}: path must be a lowercase .png under {asset_root}/"
            )
        normalized_path = posix_path.as_posix()
        if normalized_path in seen_paths:
            raise AssetCheckError(f"duplicate asset path: {normalized_path}")
        seen_paths.add(normalized_path)
        entry["path"] = normalized_path

        status = entry.get("status")
        if status not in VALID_STATUSES:
            raise AssetCheckError(
                f"{asset_id}: status must be planned, final, or required"
            )
        if entry.get("format") != "rgba8":
            raise AssetCheckError(f"{asset_id}: format must be rgba8")
        alpha_mode = entry.get("alpha_mode")
        if alpha_mode not in VALID_ALPHA_MODES:
            raise AssetCheckError(
                f"{asset_id}: alpha_mode must be binary, graded, or opaque"
            )

        width = _positive_int(entry.get("width"), "width", asset_id)
        height = _positive_int(entry.get("height"), "height", asset_id)
        max_colors = _positive_int(
            entry.get("max_visible_rgb_colors"),
            "max_visible_rgb_colors",
            asset_id,
        )
        max_alpha_levels = _positive_int(
            entry.get("max_alpha_levels"),
            "max_alpha_levels",
            asset_id,
        )
        if max_alpha_levels > 256:
            raise AssetCheckError(
                f"{asset_id}: max_alpha_levels must be <= 256"
            )
        entry["width"] = width
        entry["height"] = height
        entry["max_visible_rgb_colors"] = max_colors
        entry["max_alpha_levels"] = max_alpha_levels

        require_visible = entry.get("require_visible", True)
        if not isinstance(require_visible, bool):
            raise AssetCheckError(f"{asset_id}: require_visible must be boolean")
        entry["require_visible"] = require_visible

        frame_grid = entry.get("frame_grid")
        if frame_grid is not None:
            if not isinstance(frame_grid, dict):
                raise AssetCheckError(f"{asset_id}: frame_grid must be an object")
            columns = _positive_int(
                frame_grid.get("columns"), "frame_grid.columns", asset_id
            )
            rows = _positive_int(
                frame_grid.get("rows"), "frame_grid.rows", asset_id
            )
            cell_width = _positive_int(
                frame_grid.get("cell_width"), "frame_grid.cell_width", asset_id
            )
            cell_height = _positive_int(
                frame_grid.get("cell_height"), "frame_grid.cell_height", asset_id
            )
            if columns * cell_width != width or rows * cell_height != height:
                raise AssetCheckError(
                    f"{asset_id}: frame_grid does not exactly cover {width}x{height}"
                )
            allow_blank = frame_grid.get("allow_blank_frames", False)
            if not isinstance(allow_blank, bool):
                raise AssetCheckError(
                    f"{asset_id}: frame_grid.allow_blank_frames must be boolean"
                )
            required_rows = _positive_int(
                frame_grid.get("required_rows", 0),
                "frame_grid.required_rows",
                asset_id,
                allow_zero=True,
            )
            if required_rows > rows:
                raise AssetCheckError(
                    f"{asset_id}: frame_grid.required_rows must be <= rows"
                )
            padding = _normalize_padding(frame_grid.get("edge_padding"), asset_id)
            if padding["left"] + padding["right"] >= cell_width:
                raise AssetCheckError(
                    f"{asset_id}: left/right edge_padding is larger than cell width"
                )
            if padding["top"] + padding["bottom"] >= cell_height:
                raise AssetCheckError(
                    f"{asset_id}: top/bottom edge_padding is larger than cell height"
                )
            if alpha_mode == "opaque" and any(padding.values()):
                raise AssetCheckError(
                    f"{asset_id}: opaque assets cannot have transparent edge_padding"
                )
            entry["frame_grid"] = {
                "columns": columns,
                "rows": rows,
                "cell_width": cell_width,
                "cell_height": cell_height,
                "allow_blank_frames": allow_blank,
                "required_rows": required_rows,
                "edge_padding": padding,
            }

        normalized.append(entry)

    return PurePosixPath(asset_root).as_posix(), normalized


def _alpha_at(image: PngImage, x: int, y: int) -> int:
    return image.pixels[(y * image.width + x) * 4 + 3]


def _frame_has_visible_pixel(
    image: PngImage, x: int, y: int, width: int, height: int
) -> bool:
    for pixel_y in range(y, y + height):
        row_alpha_start = (pixel_y * image.width + x) * 4 + 3
        for pixel_x in range(width):
            if image.pixels[row_alpha_start + pixel_x * 4] > 0:
                return True
    return False


def _padding_violations(
    image: PngImage,
    x: int,
    y: int,
    width: int,
    height: int,
    padding: dict[str, int],
) -> list[str]:
    violations: list[str] = []
    strips = {
        "left": (x, y, padding["left"], height),
        "right": (
            x + width - padding["right"],
            y,
            padding["right"],
            height,
        ),
        "top": (x, y, width, padding["top"]),
        "bottom": (
            x,
            y + height - padding["bottom"],
            width,
            padding["bottom"],
        ),
    }
    labels = {"left": "left", "right": "right", "top": "top", "bottom": "bottom"}
    for side, (strip_x, strip_y, strip_width, strip_height) in strips.items():
        if strip_width <= 0 or strip_height <= 0:
            continue
        if _frame_has_visible_pixel(
            image, strip_x, strip_y, strip_width, strip_height
        ):
            violations.append(labels[side])
    return violations


def validate_asset(entry: dict[str, Any], path: Path) -> list[str]:
    errors: list[str] = []
    try:
        image = read_rgba_png(path)
    except AssetCheckError as error:
        return [str(error)]

    expected_width = entry["width"]
    expected_height = entry["height"]
    if image.width != expected_width or image.height != expected_height:
        errors.append(
            f"size is {image.width}x{image.height}px "
            f"(contract {expected_width}x{expected_height}px)"
        )

    actual_alpha = image.alpha_mode
    if actual_alpha != entry["alpha_mode"]:
        errors.append(
            f"alpha mode is {actual_alpha} "
            f"(contract {entry['alpha_mode']})"
        )

    visible_colors = image.visible_rgb_colors
    if visible_colors > entry["max_visible_rgb_colors"]:
        errors.append(
            f"visible RGB colors are {visible_colors} "
            f"(max {entry['max_visible_rgb_colors']})"
        )

    alpha_levels = image.alpha_levels
    if alpha_levels > entry["max_alpha_levels"]:
        errors.append(
            f"alpha levels are {alpha_levels} "
            f"(max {entry['max_alpha_levels']})"
        )

    visible_pixels = sum(
        1 for index in range(3, len(image.pixels), 4) if image.pixels[index] > 0
    )
    if entry["require_visible"] and visible_pixels == 0:
        errors.append("no visible pixels")

    frame_grid = entry.get("frame_grid")
    dimensions_match = (
        image.width == expected_width and image.height == expected_height
    )
    if frame_grid is not None and dimensions_match:
        columns = frame_grid["columns"]
        rows = frame_grid["rows"]
        cell_width = frame_grid["cell_width"]
        cell_height = frame_grid["cell_height"]
        padding = frame_grid["edge_padding"]
        for row in range(rows):
            for column in range(columns):
                frame_x = column * cell_width
                frame_y = row * cell_height
                requires_content = (
                    not frame_grid["allow_blank_frames"]
                    or row < frame_grid["required_rows"]
                )
                if (
                    requires_content
                    and not _frame_has_visible_pixel(
                        image, frame_x, frame_y, cell_width, cell_height
                    )
                ):
                    errors.append(
                        f"frame ({column + 1}, {row + 1}) is empty"
                    )
                violated_sides = _padding_violations(
                    image,
                    frame_x,
                    frame_y,
                    cell_width,
                    cell_height,
                    padding,
                )
                if violated_sides:
                    errors.append(
                        f"frame ({column + 1}, {row + 1}) "
                        f"has pixels in {', '.join(violated_sides)} edge padding"
                    )

    return errors


def _display_path(path: Path, project_root: Path) -> str:
    try:
        return path.resolve().relative_to(project_root.resolve()).as_posix()
    except ValueError:
        return str(path)


def _print_error(path: Path, message: str, project_root: Path) -> None:
    shown_path = _display_path(path, project_root)
    annotation = message.replace("\n", " ").replace("%", "%25")
    annotation = annotation.replace("\r", "%0D").replace("\n", "%0A")
    print(f"::error file={shown_path}::{annotation}")
    print(f"  FAIL {shown_path}: {message}")


def _find_undeclared_pngs(
    project_root: Path,
    asset_root: str,
    declared_paths: set[str],
) -> list[Path]:
    custom_root = project_root / PurePosixPath(asset_root)
    if not custom_root.exists():
        return []
    return sorted(
        (
            path
            for path in custom_root.rglob("*")
            if path.is_file()
            and path.suffix.lower() == ".png"
            and path.relative_to(project_root).as_posix() not in declared_paths
        ),
        key=lambda path: path.as_posix(),
    )


def _find_forbidden_legacy_visual_references(
    project_root: Path,
) -> list[tuple[Path, int, str]]:
    """Find leftover Ninja Adventure and derived PNG refs on the runtime path.

    Music and SFX are managed on a separate license/replace lane. This check only blocks the free pack's
    visual identity from remixing back onto custom assets.
    """
    references: list[tuple[Path, int, str]] = []
    for root_name in RUNTIME_TEXT_ROOTS:
        root = project_root / root_name
        if not root.is_dir():
            continue
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
            if not path.is_file() or path.suffix not in RUNTIME_TEXT_SUFFIXES:
                continue
            try:
                lines = path.read_text(encoding="utf-8-sig").splitlines()
            except (OSError, UnicodeError) as error:
                raise AssetCheckError(
                    f"cannot read runtime-ref file: {path}: {error}"
                ) from error
            for line_number, line in enumerate(lines, start=1):
                for pattern in FORBIDDEN_LEGACY_VISUAL_PATTERNS:
                    match = pattern.search(line)
                    if match is not None:
                        references.append((path, line_number, match.group(0)))
    return references


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="MoonlitBeacon custom RGBA pixel-asset contract check"
    )
    parser.add_argument(
        "--contracts",
        type=Path,
        default=DEFAULT_CONTRACTS,
        help="contract JSON path",
    )
    parser.add_argument(
        "--project-root",
        type=Path,
        default=DEFAULT_PROJECT_ROOT,
        help="Godot project root (default: apps/game)",
    )
    parser.add_argument(
        "--id",
        action="append",
        dest="asset_ids",
        metavar="ASSET_ID",
        help="contract id to check. May be passed more than once.",
    )
    parser.add_argument(
        "--candidate",
        type=Path,
        help="candidate PNG path before import, used with one --id",
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="list contract ids, status, and spec, then exit",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    project_root = args.project_root.resolve()
    contracts_path = args.contracts.resolve()
    try:
        asset_root, entries = load_contracts(contracts_path)
    except AssetCheckError as error:
        _print_error(contracts_path, str(error), project_root)
        return 2

    by_id = {entry["id"]: entry for entry in entries}
    requested_ids = args.asset_ids or []
    unknown_ids = [asset_id for asset_id in requested_ids if asset_id not in by_id]
    if unknown_ids:
        print(f"unknown contract id: {', '.join(unknown_ids)}", file=sys.stderr)
        return 2

    if args.list:
        for entry in entries:
            print(
                f"{entry['id']:<30} {entry['status']:<8} "
                f"{entry['width']}x{entry['height']}  {entry['path']}"
            )
        return 0

    selected = [by_id[asset_id] for asset_id in requested_ids] if requested_ids else entries
    if args.candidate is not None and len(selected) != 1:
        print("--candidate must be used with exactly one --id", file=sys.stderr)
        return 2

    failures = 0
    checked = 0
    skipped = 0
    for entry in selected:
        path = (
            args.candidate.resolve()
            if args.candidate is not None
            else project_root / PurePosixPath(entry["path"])
        )
        if not path.is_file():
            if args.candidate is None and entry["status"] == "planned":
                skipped += 1
                continue
            _print_error(path, f"{entry['id']}: required PNG is missing", project_root)
            failures += 1
            continue

        checked += 1
        errors = validate_asset(entry, path)
        if errors:
            for message in errors:
                _print_error(path, f"{entry['id']}: {message}", project_root)
            failures += len(errors)
        else:
            print(
                f"  OK   {entry['id']} "
                f"({entry['width']}x{entry['height']}, {entry['alpha_mode']})"
            )

    if args.candidate is None and not requested_ids:
        declared_paths = {entry["path"] for entry in entries}
        for path in _find_undeclared_pngs(
            project_root, asset_root, declared_paths
        ):
            _print_error(
                path,
                f"PNG under {asset_root} is not declared in the contract",
                project_root,
            )
            failures += 1

        try:
            forbidden_references = _find_forbidden_legacy_visual_references(
                project_root
            )
        except AssetCheckError as error:
            _print_error(project_root, str(error), project_root)
            failures += 1
        else:
            for path, line_number, reference in forbidden_references:
                _print_error(
                    path,
                    f"line {line_number} still has an unreplaced free or derived visual reference "
                    f": {reference}",
                    project_root,
                )
                failures += 1

    if failures:
        print(
            f"custom-asset check failed: inspected {checked} files, "
            f"{skipped} contracts planned, {failures} error(s)"
        )
        return 1

    print(
        f"{len(entries)} custom-asset contracts: "
        f"{checked} files passed, {skipped} planned"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
