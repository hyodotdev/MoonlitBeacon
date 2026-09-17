#!/usr/bin/env python3
"""Bake dialogue glyph ticks. Writes WAV with no external library.

The "tiririri" tick a visual novel makes as glyphs type. One very
short blip per glyph, and playback jitters pitch a little
so it does not sound mechanical.

**Bake it; do not fetch it.** Just as every picture in this repo is made by `build_*_assets.py`
deterministically, this sound follows the same rule. License-notice targets do not
grow, and at 1.5KB the file is no burden on the repo.

    python3 apps/game/tools/build_dialogue_sfx.py          # bake
    python3 apps/game/tools/build_dialogue_sfx.py --check  # is output current
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
OUTPUT = (
    REPO_ROOT / "apps/game/assets/custom/audio/sfx/dialogue_blip.wav"
)

SAMPLE_RATE = 22050
## 40ms. Longer than this cannot keep up with 42 glyphs/s, so ticks overlap and smear.
DURATION = 0.040
## Closer to a wooden xylophone than a voice. Fits Moonlit Beacon's night mood.
BASE_HZ = 1180.0
## Add one overtone so it is closer to a triangle wave. A pure tone is a beep that hurts.
OVERTONE_HZ = BASE_HZ * 2.0
OVERTONE_MIX = 0.22
## Open the start over 2ms to kill the click.
ATTACK = 0.002


def _envelope(position: float) -> float:
    """Amplitude to multiply along a 0→1 position. Open fast, close exponentially."""
    attack_ratio = ATTACK / DURATION
    if position < attack_ratio:
        return position / attack_ratio
    decay = (position - attack_ratio) / (1.0 - attack_ratio)
    return math.exp(-5.5 * decay)


def render() -> bytes:
    total = int(SAMPLE_RATE * DURATION)
    frames = bytearray()
    for index in range(total):
        seconds = index / SAMPLE_RATE
        position = index / total
        value = math.sin(2.0 * math.pi * BASE_HZ * seconds)
        value += OVERTONE_MIX * math.sin(2.0 * math.pi * OVERTONE_HZ * seconds)
        value *= _envelope(position) / (1.0 + OVERTONE_MIX)
        # Leave headroom. Dialogue ticks must not cover the music.
        sample = int(max(-1.0, min(1.0, value)) * 20000)
        frames += struct.pack("<h", sample)
    return bytes(frames)


def wav_bytes(frames: bytes) -> bytes:
    block_align = 2                                   # mono 16-bit
    header = b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVE"
    header += b"fmt " + struct.pack(
        "<IHHIIHH",
        16,                                           # fmt chunk length
        1,                                            # PCM
        1,                                            # channels
        SAMPLE_RATE,
        SAMPLE_RATE * block_align,
        block_align,
        16,                                           # bit depth
    )
    header += b"data" + struct.pack("<I", len(frames))
    return header + frames


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="do not rebake; only check that output is current")
    args = parser.parse_args()

    payload = wav_bytes(render())
    if args.check:
        if not OUTPUT.exists():
            print(f"missing: {OUTPUT.relative_to(REPO_ROOT)}", file=sys.stderr)
            return 1
        if OUTPUT.read_bytes() != payload:
            print(f"stale: {OUTPUT.relative_to(REPO_ROOT)}", file=sys.stderr)
            return 1
        print(f"dialogue sfx current — {OUTPUT.relative_to(REPO_ROOT)}")
        return 0

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_bytes(payload)
    print(f"baked {OUTPUT.relative_to(REPO_ROOT)} ({len(payload)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
