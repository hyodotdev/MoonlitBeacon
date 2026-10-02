#!/usr/bin/env python3
"""Bake original kinetic combat audio. Writes WAV with no external library.

A driving night-motif arena loop, an escalating guardian loop, six weapon
sounds, and impact/kill/growth/core/overcharge cues — all synthesized here, so
no license-notice target grows and no network fetch is ever needed. Same rule
as `build_dialogue_sfx.py`: bake it, do not fetch it.

    python3 apps/game/tools/build_combat_audio.py            # bake
    python3 apps/game/tools/build_combat_audio.py --check    # is output current
    python3 apps/game/tools/build_combat_audio.py --audition # montage + stats

Loops are musically exact (whole bars) with short raised-cosine edge fades so
the boundary is exact zero and cannot click. Noise comes from a fixed-seed LCG,
never `random`, so every bake is byte-identical.
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
MUSIC_DIR = REPO_ROOT / "apps/game/assets/custom/audio/music"
SFX_DIR = REPO_ROOT / "apps/game/assets/custom/audio/sfx"

SAMPLE_RATE = 22050

# Fixed-seed LCG for every noise source. Deterministic across runs/platforms.
_LCG_STATE = 0x12345678


def _reset_noise() -> None:
    global _LCG_STATE
    _LCG_STATE = 0x12345678


def _noise() -> float:
    global _LCG_STATE
    _LCG_STATE = (1103515245 * _LCG_STATE + 12345) & 0x7FFFFFFF
    return (_LCG_STATE / 1073741823.5) - 1.0


def _note_freq(semitones_from_a4: float) -> float:
    return 440.0 * (2.0 ** (semitones_from_a4 / 12.0))


def _adsr(
    length: int,
    attack: float = 0.005,
    decay: float = 0.05,
    sustain: float = 0.7,
    release: float = 0.08,
) -> list[float]:
    attack_n = max(int(length * attack), 1)
    decay_n = max(int(length * decay), 1)
    release_n = max(int(length * release), 1)
    sustain_n = max(length - attack_n - decay_n - release_n, 0)
    env: list[float] = []
    for i in range(attack_n):
        env.append(i / attack_n)
    for i in range(decay_n):
        env.append(1.0 - (1.0 - sustain) * (i / decay_n))
    env.extend([sustain] * sustain_n)
    for i in range(release_n):
        env.append(sustain * (1.0 - i / release_n))
    return (env + [0.0] * length)[:length]


def _tone(
    freq: float,
    seconds: float,
    overtone_mix: float = 0.25,
    attack: float = 0.005,
    decay: float = 0.1,
    sustain: float = 0.6,
    release: float = 0.15,
) -> list[float]:
    total = int(SAMPLE_RATE * seconds)
    env = _adsr(total, attack, decay, sustain, release)
    out: list[float] = []
    for i in range(total):
        t = i / SAMPLE_RATE
        value = math.sin(2.0 * math.pi * freq * t)
        value += overtone_mix * math.sin(2.0 * math.pi * freq * 2.0 * t)
        value += 0.08 * math.sin(2.0 * math.pi * freq * 3.0 * t)
        out.append(value * env[i] / 1.33)
    return out


def _mix_into(track: list[float], part: list[float], at: int, gain: float = 1.0) -> None:
    for i, sample in enumerate(part):
        pos = at + i
        if 0 <= pos < len(track):
            track[pos] += sample * gain


def _kick() -> list[float]:
    total = int(SAMPLE_RATE * 0.22)
    out: list[float] = []
    for i in range(total):
        t = i / SAMPLE_RATE
        freq = 45.0 + 110.0 * math.exp(-t * 30.0)
        angle = 2.0 * math.pi * (45.0 * t + 110.0 * (1.0 - math.exp(-t * 30.0)) / 30.0)
        body = math.sin(angle) * math.exp(-t * 14.0)
        click = _noise() * math.exp(-t * 220.0) * 0.5
        out.append(body * 0.9 + click)
    return out


def _snare() -> list[float]:
    total = int(SAMPLE_RATE * 0.16)
    out: list[float] = []
    for i in range(total):
        t = i / SAMPLE_RATE
        tone = math.sin(2.0 * math.pi * 185.0 * t) * math.exp(-t * 26.0)
        snap = _noise() * math.exp(-t * 40.0) * 0.7
        out.append(tone * 0.6 + snap)
    return out


def _hat(open: bool = False) -> list[float]:
    total = int(SAMPLE_RATE * (0.16 if open else 0.05))
    out: list[float] = []
    prev = 0.0
    for i in range(total):
        t = i / SAMPLE_RATE
        raw = _noise()
        high = raw - prev  # crude highpass: only the sizzle survives
        prev = raw
        out.append(high * math.exp(-t * (28.0 if open else 110.0)) * 0.5)
    return out


def _tom(freq: float) -> list[float]:
    total = int(SAMPLE_RATE * 0.24)
    out: list[float] = []
    for i in range(total):
        t = i / SAMPLE_RATE
        slide = freq * (0.55 + 0.45 * math.exp(-t * 18.0))
        out.append(math.sin(2.0 * math.pi * slide * t) * math.exp(-t * 13.0))
    return out


def _bass_note(freq: float, seconds: float) -> list[float]:
    total = int(SAMPLE_RATE * seconds)
    env = _adsr(total, 0.004, 0.05, 0.85, 0.1)
    out: list[float] = []
    for i in range(total):
        t = i / SAMPLE_RATE
        value = math.sin(2.0 * math.pi * freq * t)
        value += 0.35 * math.sin(2.0 * math.pi * freq * 2.0 * t)
        value += 0.12 * math.sin(2.0 * math.pi * freq * 0.5 * t)
        out.append(value * env[i] / 1.47)
    return out


# The lantern motif: A-minor pentatonic, semitones from A4. Both loops share it
# so the guardian escalation sounds like the same night turning dangerous.
MOTIF: list[float] = [0.0, 3.0, 5.0, 7.0, 10.0, 12.0, 10.0, 7.0]
# Am — F — C — G roots for the bass, semitones from A2 (110 Hz).
PROGRESSION: list[float] = [0.0, -4.0, 3.0, -2.0]


def _render_arena_loop() -> list[float]:
    _reset_noise()
    bpm = 132.0
    beat = 60.0 / bpm
    bars = 8
    total = int(SAMPLE_RATE * beat * 4 * bars)
    track = [0.0] * total
    kick = _kick()
    snare = _snare()
    hat = _hat()
    open_hat = _hat(open=True)
    for bar in range(bars):
        bar_at = int(bar * 4 * beat * SAMPLE_RATE)
        root = PROGRESSION[bar % len(PROGRESSION)]
        for pulse in range(4):
            at = bar_at + int(pulse * beat * SAMPLE_RATE)
            _mix_into(track, kick, at, 0.75)
            _mix_into(track, snare, at, 0.55 if pulse % 2 == 1 else 0.0)
            _mix_into(track, hat, at, 0.5)
            _mix_into(track, open_hat, at + int(beat * SAMPLE_RATE / 2), 0.35)
            bass = _bass_note(_note_freq(root - 24.0), beat * 0.9)
            _mix_into(track, bass, at, 0.6)
        # Motif lead on top, two notes per bar, answered in the second half.
        for slot in range(2):
            degree = MOTIF[(bar * 2 + slot) % len(MOTIF)]
            lead = _tone(_note_freq(degree), beat * 1.6, 0.3, 0.01, 0.2, 0.5, 0.3)
            _mix_into(track, lead, bar_at + int(slot * 2 * beat * SAMPLE_RATE), 0.42)
    return _loop_fade(track)


def _render_guardian_loop() -> list[float]:
    _reset_noise()
    bpm = 140.0
    beat = 60.0 / bpm
    bars = 10
    total = int(SAMPLE_RATE * beat * 4 * bars)
    track = [0.0] * total
    kick = _kick()
    snare = _snare()
    hat = _hat()
    for bar in range(bars):
        bar_at = int(bar * 4 * beat * SAMPLE_RATE)
        root = PROGRESSION[bar % len(PROGRESSION)]
        heat = bar / max(bars - 1, 1)  # escalation across the loop, still seamless
        for pulse in range(4):
            at = bar_at + int(pulse * beat * SAMPLE_RATE)
            _mix_into(track, kick, at, 0.8)
            _mix_into(track, kick, at + int(beat * SAMPLE_RATE * 0.75), 0.4 * heat)
            _mix_into(track, snare, at, 0.6 if pulse % 2 == 1 else 0.0)
            _mix_into(track, hat, at, 0.45)
            _mix_into(track, _tom(_note_freq(root - 12.0)), at, 0.35 * heat)
            bass = _bass_note(_note_freq(root - 24.0), beat * 0.85)
            _mix_into(track, bass, at, 0.62)
        # Motif in doubling rhythm as the loop heats: halves, then quarters.
        slots = 2 if bar < 5 else 4
        for slot in range(slots):
            degree = MOTIF[(bar * slots + slot) % len(MOTIF)] + 12.0
            lead = _tone(_note_freq(degree), beat * 0.9, 0.35, 0.008, 0.15, 0.5, 0.25)
            when = bar_at + int(slot * (4.0 / slots) * beat * SAMPLE_RATE)
            _mix_into(track, lead, when, 0.34 + 0.14 * heat)
    return _loop_fade(track)


def _render_arena_ember() -> list[float]:
    """Arena track 2: shuffling triplet hats at 126 BPM, motif answered in thirds."""
    _reset_noise()
    bpm = 126.0
    beat = 60.0 / bpm
    bars = 8
    total = int(SAMPLE_RATE * beat * 4 * bars)
    track = [0.0] * total
    kick = _kick()
    snare = _snare()
    hat = _hat()
    for bar in range(bars):
        bar_at = int(bar * 4 * beat * SAMPLE_RATE)
        root = PROGRESSION[bar % len(PROGRESSION)]
        for pulse in range(4):
            at = bar_at + int(pulse * beat * SAMPLE_RATE)
            _mix_into(track, kick, at, 0.75 if pulse % 2 == 0 else 0.0)
            _mix_into(track, snare, at, 0.55 if pulse % 2 == 1 else 0.0)
            for tick in range(3):  # shuffle triplet under the backbeat
                _mix_into(track, hat, at + int(tick * beat * SAMPLE_RATE / 3.0), 0.35)
            bass = _bass_note(_note_freq(root - 24.0 + (12.0 if pulse == 3 else 0.0)), beat * 0.8)
            _mix_into(track, bass, at, 0.6)
        for slot in range(2):
            degree = MOTIF[(bar * 2 + slot) % len(MOTIF)]
            when = bar_at + int(slot * 2 * beat * SAMPLE_RATE)
            _mix_into(track, _tone(_note_freq(degree), beat * 1.6, 0.3, 0.01, 0.2, 0.5, 0.3), when, 0.38)
            _mix_into(track, _tone(_note_freq(degree + 4.0), beat * 1.6, 0.3, 0.01, 0.2, 0.5, 0.3), when, 0.24)
    return _loop_fade(track)


def _render_arena_watch() -> list[float]:
    """Arena track 3: half-time watchfulness at 138 BPM, eighth-note arps over low toms."""
    _reset_noise()
    bpm = 138.0
    beat = 60.0 / bpm
    bars = 8
    total = int(SAMPLE_RATE * beat * 4 * bars)
    track = [0.0] * total
    kick = _kick()
    snare = _snare()
    hat = _hat()
    for bar in range(bars):
        bar_at = int(bar * 4 * beat * SAMPLE_RATE)
        root = PROGRESSION[bar % len(PROGRESSION)]
        for pulse in range(4):
            at = bar_at + int(pulse * beat * SAMPLE_RATE)
            _mix_into(track, kick, at, 0.7 if pulse in (0, 2) else 0.0)
            _mix_into(track, snare, at, 0.6 if pulse == 2 else 0.0)  # half-time: beat 3 only
            _mix_into(track, _tom(_note_freq(root - 12.0)), bar_at, 0.3 if pulse == 0 else 0.0)
            bass = _bass_note(_note_freq(root - 24.0), beat * 1.6)
            _mix_into(track, bass, at, 0.5 if pulse in (0, 2) else 0.0)
        for slot in range(8):  # eighth-note arpeggio walks the motif up the bar
            degree = MOTIF[slot % len(MOTIF)] + 12.0
            _mix_into(track, _tone(_note_freq(degree), beat * 0.4, 0.35, 0.005, 0.2, 0.4, 0.2),
                      bar_at + int(slot * beat * SAMPLE_RATE / 2.0), 0.26)
        for pulse in range(4):
            _mix_into(track, hat, bar_at + int(pulse * beat * SAMPLE_RATE), 0.3)
    return _loop_fade(track)


def _render_guardian_hunt() -> list[float]:
    """Guardian track 2: four-on-the-floor pursuit at 152 BPM, motif as brass stabs."""
    _reset_noise()
    bpm = 152.0
    beat = 60.0 / bpm
    bars = 8
    total = int(SAMPLE_RATE * beat * 4 * bars)
    track = [0.0] * total
    kick = _kick()
    snare = _snare()
    hat = _hat()
    for bar in range(bars):
        bar_at = int(bar * 4 * beat * SAMPLE_RATE)
        root = PROGRESSION[bar % len(PROGRESSION)]
        for pulse in range(4):
            at = bar_at + int(pulse * beat * SAMPLE_RATE)
            _mix_into(track, kick, at, 0.8)
            _mix_into(track, snare, at, 0.6 if pulse in (1, 3) else 0.0)
            _mix_into(track, hat, at, 0.45)
            _mix_into(track, hat, at + int(beat * SAMPLE_RATE / 2), 0.3)
            _mix_into(track, _tom(_note_freq(root - 12.0 + pulse * 2.0)), at, 0.3)
            bass = _bass_note(_note_freq(root - 24.0), beat * 0.7)
            _mix_into(track, bass, at, 0.62)
        for slot in range(4):  # short stabs, an octave up: the motif hunting you
            degree = MOTIF[(bar + slot * 2) % len(MOTIF)] + 12.0
            _mix_into(track, _tone(_note_freq(degree), beat * 0.5, 0.4, 0.004, 0.1, 0.6, 0.2),
                      bar_at + int(slot * beat * SAMPLE_RATE), 0.4)
    return _loop_fade(track)


def _render_guardian_storm() -> list[float]:
    """Guardian track 3: 160 BPM storm, double kicks and the motif in racing 8ths."""
    _reset_noise()
    bpm = 160.0
    beat = 60.0 / bpm
    bars = 10
    total = int(SAMPLE_RATE * beat * 4 * bars)
    track = [0.0] * total
    kick = _kick()
    snare = _snare()
    hat = _hat()
    for bar in range(bars):
        bar_at = int(bar * 4 * beat * SAMPLE_RATE)
        root = PROGRESSION[bar % len(PROGRESSION)] - (bar % 4)  # chromatic descent
        for pulse in range(4):
            at = bar_at + int(pulse * beat * SAMPLE_RATE)
            _mix_into(track, kick, at, 0.8)
            _mix_into(track, kick, at + int(beat * SAMPLE_RATE / 2), 0.55)  # double kick
            _mix_into(track, snare, at, 0.62 if pulse in (1, 3) else 0.0)
            for tick in range(4):  # 16th hats keep the storm moving
                _mix_into(track, hat, at + int(tick * beat * SAMPLE_RATE / 4.0), 0.3)
            bass = _bass_note(_note_freq(root - 24.0), beat * 0.6)
            _mix_into(track, bass, at, 0.62)
        for slot in range(8):
            degree = MOTIF[slot % len(MOTIF)] + 12.0
            _mix_into(track, _tone(_note_freq(degree), beat * 0.4, 0.38, 0.005, 0.15, 0.5, 0.2),
                      bar_at + int(slot * beat * SAMPLE_RATE / 2.0), 0.3)
    return _loop_fade(track)


# Music catalog: three arena tracks (pools 0) and three faster guardian tracks.
MUSIC_TRACKS: list[tuple[str, object, float]] = [
    ("arena_kinetic", _render_arena_loop, 0.62),
    ("arena_ember", _render_arena_ember, 0.62),
    ("arena_watch", _render_arena_watch, 0.62),
    ("guardian_assault", _render_guardian_loop, 0.62),
    ("guardian_hunt", _render_guardian_hunt, 0.62),
    ("guardian_storm", _render_guardian_storm, 0.62),
]


def _loop_fade(track: list[float]) -> list[float]:
    """Short raised-cosine fades at both edges so the loop boundary is exact zero.

    A tail-to-head crossfade only moves the step: the last sample must equal the
    first, and only a shared zero guarantees that for a dense mix. 4.4 ms dips
    once per ~15 s loop — inaudible under drums — and the boundary step is 0.
    """
    width = 96
    total = len(track)
    for i in range(width):
        gain = 0.5 - 0.5 * math.cos(math.pi * i / width)
        track[i] *= gain
        track[total - 1 - i] *= gain
    return track


def _sweep_noise(seconds: float, up: bool, brightness: float = 1.0) -> list[float]:
    total = int(SAMPLE_RATE * seconds)
    out: list[float] = []
    prev = 0.0
    for i in range(total):
        pos = i / total
        cutoff = pos if up else 1.0 - pos
        raw = _noise()
        # One-pole toward the sweep direction: darker one end, brighter the other.
        prev = prev + (0.04 + 0.5 * cutoff * brightness) * (raw - prev)
        edge = math.sin(math.pi * pos)  # zero at both ends: no click
        out.append(prev * edge * 1.6)
    return out


def _render_sfx() -> dict[str, list[float]]:
    _reset_noise()
    sfx: dict[str, list[float]] = {}
    # Sword: bright downward swipe plus a moon-metal ping.
    sword = _sweep_noise(0.18, up=False)
    _mix_into(sword, _tone(_note_freq(12.0), 0.18, 0.4, 0.002, 0.3, 0.2, 0.4), 0, 0.5)
    sfx["weapon_sword"] = sword
    # Twin blades: two staggered ticks, left-right-left in 140 ms.
    twin = [0.0] * int(SAMPLE_RATE * 0.16)
    _mix_into(twin, _tone(_note_freq(15.0), 0.07, 0.3), 0, 0.8)
    _mix_into(twin, _tone(_note_freq(19.0), 0.07, 0.3), int(SAMPLE_RATE * 0.055), 0.8)
    sfx["weapon_twin"] = twin
    # Rifle: restrained crack — snap first, small body, no tail.
    rifle = [0.0] * int(SAMPLE_RATE * 0.22)
    snap = _sweep_noise(0.05, up=True)
    _mix_into(rifle, snap, 0, 1.2)
    _mix_into(rifle, _tone(_note_freq(-24.0), 0.2, 0.2, 0.002, 0.4, 0.1, 0.5), 0, 0.7)
    sfx["weapon_rifle"] = rifle
    # Shotgun: broad close boom.
    scatter = _sweep_noise(0.3, up=False, brightness=0.6)
    _mix_into(scatter, _tone(_note_freq(-31.0), 0.3, 0.15, 0.002, 0.3, 0.2, 0.4), 0, 0.9)
    sfx["weapon_shotgun"] = scatter
    # Cannon: deep boom with a sub tail.
    cannon = [0.0] * int(SAMPLE_RATE * 0.5)
    _mix_into(cannon, _kick(), 0, 1.4)
    _mix_into(cannon, _tone(_note_freq(-36.0), 0.5, 0.1, 0.002, 0.2, 0.4, 0.5), 0, 0.8)
    sfx["weapon_cannon"] = cannon
    # Scythe: airy rising whoosh with shimmer.
    scythe = _sweep_noise(0.25, up=True)
    _mix_into(scythe, _tone(_note_freq(22.0), 0.25, 0.4, 0.05, 0.3, 0.3, 0.4), 0, 0.3)
    sfx["weapon_scythe"] = scythe
    # Impact knock: short and crisp, rate-limited in code, never a wall.
    impact = [0.0] * int(SAMPLE_RATE * 0.09)
    _mix_into(impact, _tone(_note_freq(-5.0), 0.09, 0.2, 0.001, 0.5, 0.1, 0.4), 0, 0.9)
    sfx["impact_hit"] = impact
    # Kill pop: pitch-up blip with sparkle — the dopamine tick.
    kill = [0.0] * int(SAMPLE_RATE * 0.16)
    total = len(kill)
    for i in range(total):
        t = i / SAMPLE_RATE
        freq = 400.0 + 900.0 * (t / 0.16)
        kill[i] = math.sin(2.0 * math.pi * freq * t) * math.sin(math.pi * i / total)
    _mix_into(kill, _tone(_note_freq(24.0), 0.1, 0.3), int(SAMPLE_RATE * 0.05), 0.4)
    sfx["kill_pop"] = kill
    # Level surge: rising arpeggio A–C–E–A.
    level = [0.0] * int(SAMPLE_RATE * 0.5)
    for slot, degree in enumerate([0.0, 3.0, 7.0, 12.0]):
        _mix_into(level, _tone(_note_freq(degree + 12.0), 0.22, 0.3), int(slot * 0.07 * SAMPLE_RATE), 0.7)
    sfx["level_up"] = level
    # Core chime: warm fifth.
    core = [0.0] * int(SAMPLE_RATE * 0.35)
    _mix_into(core, _tone(_note_freq(7.0), 0.35, 0.3, 0.004, 0.2, 0.4, 0.4), 0, 0.7)
    _mix_into(core, _tone(_note_freq(12.0), 0.3, 0.3, 0.004, 0.2, 0.4, 0.4), int(0.02 * SAMPLE_RATE), 0.5)
    sfx["core_pickup"] = core
    # Overcharge triumph: chord plus rise.
    win = [0.0] * int(SAMPLE_RATE * 0.8)
    for degree in [0.0, 4.0, 7.0, 12.0]:
        _mix_into(win, _tone(_note_freq(degree), 0.8, 0.25, 0.01, 0.2, 0.5, 0.4), 0, 0.4)
    rise = [0.0] * int(SAMPLE_RATE * 0.5)
    for i in range(len(rise)):
        t = i / SAMPLE_RATE
        freq = 220.0 + 660.0 * (t / 0.5)
        rise[i] = math.sin(2.0 * math.pi * freq * t) * math.sin(math.pi * i / len(rise)) * 0.4
    _mix_into(win, rise, int(0.25 * SAMPLE_RATE), 0.8)
    sfx["overcharge_win"] = win
    return sfx


def _normalize(track: list[float], peak: float) -> list[float]:
    loudest = max(max(track), -min(track), 1e-6)
    gain = peak / loudest
    out = [sample * gain for sample in track]
    # 32-sample fade-out insurance: every cue ends at exact zero, no stop click.
    for i in range(32):
        out[len(out) - 1 - i] *= i / 32.0
    return out


def _to_frames(track: list[float]) -> bytes:
    frames = bytearray()
    for sample in track:
        clamped = max(-1.0, min(1.0, sample))
        frames += struct.pack("<h", int(clamped * 32767.0))
    return bytes(frames)


def wav_bytes(frames: bytes) -> bytes:
    header = b"RIFF" + struct.pack("<I", 36 + len(frames)) + b"WAVE"
    header += b"fmt " + struct.pack("<IHHIIHH", 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16)
    header += b"data" + struct.pack("<I", len(frames))
    return header + frames


def _stats(track: list[float]) -> tuple[float, float, float]:
    peak = max(max(track), -min(track))
    mean_sq = sum(s * s for s in track) / max(len(track), 1)
    rms = math.sqrt(mean_sq)
    headroom_db = -20.0 * math.log10(max(peak, 1e-6))
    return peak, rms, headroom_db


def build_all() -> dict[Path, bytes]:
    outputs: dict[Path, bytes] = {}
    for name, render, peak in MUSIC_TRACKS:
        outputs[MUSIC_DIR / (name + ".wav")] = wav_bytes(_to_frames(_normalize(render(), peak)))
    for name, track in _render_sfx().items():
        peak_target = 0.80 if name.startswith("weapon_") or name in ("impact_hit", "kill_pop") else 0.72
        outputs[SFX_DIR / (name + ".wav")] = wav_bytes(_to_frames(_normalize(track, peak_target)))
    return outputs


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="do not rebake; only check outputs are current")
    parser.add_argument("--audition", nargs="?", const="",
                        help="write a montage WAV of every cue for listening (default: builds/audio/audition.wav)")
    args = parser.parse_args()

    if args.audition is not None:
        out = Path(args.audition) if args.audition else REPO_ROOT / "builds/audio/audition.wav"
        montage: list[float] = []
        gap = [0.0] * int(SAMPLE_RATE * 0.15)
        print(f"{'cue':>16} {'seconds':>8} {'peak':>6} {'rms':>6} {'headroom':>9}")
        for name, track in [
            (name, _normalize(render(), peak)) for name, render, peak in MUSIC_TRACKS
        ] + [(k, _normalize(v, 0.80 if k.startswith("weapon_") or k in ("impact_hit", "kill_pop") else 0.72))
             for k, v in _render_sfx().items()]:
            peak, rms, headroom = _stats(track)
            seconds = len(track) / SAMPLE_RATE
            print(f"{name:>16} {seconds:8.2f} {peak:6.3f} {rms:6.3f} {headroom:8.2f}dB")
            montage.extend(track)
            montage.extend(gap)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(wav_bytes(_to_frames(montage)))
        print(f"audition montage: {out} ({len(montage) / SAMPLE_RATE:.1f}s)")
        return 0

    outputs = build_all()
    if args.check:
        for path, payload in outputs.items():
            rel = path.relative_to(REPO_ROOT)
            if not path.exists():
                print(f"missing: {rel}", file=sys.stderr)
                return 1
            if path.read_bytes() != payload:
                print(f"stale: {rel}", file=sys.stderr)
                return 1
        print(f"combat audio current — {len(outputs)} files")
        return 0

    for path, payload in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(payload)
        print(f"baked {path.relative_to(REPO_ROOT)} ({len(payload)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
