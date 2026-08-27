#!/usr/bin/env python3
"""Build Musirail's deterministic, original CC0 demo song package."""

from __future__ import annotations

import argparse
from array import array
import json
import math
from pathlib import Path
import random
import wave
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


SAMPLE_RATE = 22_050
BPM = 128.0
BEAT = 60.0 / BPM
BEAT_COUNT = 64
DURATION = BEAT_COUNT * BEAT
TITLE = "First Light"
ARTIST = "Musirail Project"


def midi_frequency(note: int) -> float:
    return 440.0 * 2.0 ** ((note - 69) / 12.0)


def add_tone(
    samples: list[float],
    start: float,
    duration: float,
    note: int,
    amplitude: float,
    harmonics: tuple[float, ...] = (1.0, 0.25, 0.08),
) -> None:
    first = max(0, int(start * SAMPLE_RATE))
    count = min(int(duration * SAMPLE_RATE), len(samples) - first)
    frequency = midi_frequency(note)
    attack = min(0.025, duration * 0.2)
    release = min(0.12, duration * 0.35)
    for offset in range(count):
        time = offset / SAMPLE_RATE
        envelope = min(1.0, time / max(attack, 0.001))
        envelope *= min(1.0, (duration - time) / max(release, 0.001))
        tone = 0.0
        for harmonic, strength in enumerate(harmonics, start=1):
            tone += strength * math.sin(
                2.0 * math.pi * frequency * harmonic * time
            )
        samples[first + offset] += amplitude * envelope * tone


def add_kick(samples: list[float], start: float, amplitude: float = 0.42) -> None:
    first = int(start * SAMPLE_RATE)
    count = min(int(0.22 * SAMPLE_RATE), len(samples) - first)
    phase = 0.0
    for offset in range(count):
        time = offset / SAMPLE_RATE
        frequency = 145.0 * math.exp(-18.0 * time) + 42.0
        phase += 2.0 * math.pi * frequency / SAMPLE_RATE
        samples[first + offset] += amplitude * math.exp(-17.0 * time) * math.sin(phase)


def add_hat(
    samples: list[float], start: float, rng: random.Random, amplitude: float = 0.055
) -> None:
    first = int(start * SAMPLE_RATE)
    count = min(int(0.055 * SAMPLE_RATE), len(samples) - first)
    previous = 0.0
    for offset in range(count):
        time = offset / SAMPLE_RATE
        noise = rng.uniform(-1.0, 1.0)
        high_pass = noise - previous * 0.72
        previous = noise
        samples[first + offset] += amplitude * math.exp(-55.0 * time) * high_pass


def render_audio(path: Path) -> None:
    samples = [0.0] * int(DURATION * SAMPLE_RATE)
    rng = random.Random(20_260_827)
    chord_roots = (50, 57, 54, 59, 50, 55, 52, 57)
    melody = (
        74, 78, 81, 76, 79, 83, 78, 73,
        76, 81, 85, 83, 78, 80, 76, 71,
        74, 79, 81, 86, 83, 78, 76, 80,
        81, 76, 85, 80, 78, 83, 79, 74,
    )

    for measure in range(16):
        root = chord_roots[measure % len(chord_roots)]
        measure_start = measure * 4.0 * BEAT
        for chord_note in (root, root + 7, root + 11, root + 14):
            add_tone(samples, measure_start, 4.0 * BEAT, chord_note, 0.026)
        for beat_index in range(4):
            beat_start = measure_start + beat_index * BEAT
            add_kick(samples, beat_start, 0.40 if beat_index in (0, 2) else 0.25)
            add_tone(samples, beat_start, BEAT * 0.72, root - 12, 0.12)
            for subdivision in range(2):
                add_hat(samples, beat_start + subdivision * BEAT / 2.0, rng)
            arpeggio_note = (root, root + 7, root + 11, root + 14)[beat_index]
            add_tone(samples, beat_start, BEAT * 0.42, arpeggio_note + 12, 0.08)

    for index, note in enumerate(melody):
        start = (index * 2 + 0.5) * BEAT
        add_tone(samples, start, BEAT * 1.12, note, 0.115, (1.0, 0.16, 0.04))

    peak = max(abs(value) for value in samples) or 1.0
    fade_samples = int(0.7 * SAMPLE_RATE)
    pcm = array("h")
    for index, value in enumerate(samples):
        fade = 1.0
        if index < fade_samples:
            fade = index / fade_samples
        elif index >= len(samples) - fade_samples:
            fade = (len(samples) - index - 1) / fade_samples
        normalized = max(-1.0, min(1.0, value * fade * 0.88 / peak))
        pcm.append(int(normalized * 32_767))

    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(pcm.tobytes())


def tap(time: float, x: float, width: float) -> dict[str, object]:
    return {"time": round(time, 6), "x": x, "width": width, "type": "tap"}


def build_chart() -> dict[str, object]:
    lanes = (0.18, 0.39, 0.61, 0.82, 0.61, 0.39)
    easy = [tap((beat + 1) * BEAT, lanes[(beat // 2) % len(lanes)], 0.22)
            for beat in range(0, 60, 2)]
    normal = [tap((beat + 1) * BEAT, lanes[beat % len(lanes)], 0.19)
              for beat in range(60)]
    normal[14] = {
        "time": round(15 * BEAT, 6),
        "end_time": round(17 * BEAT, 6),
        "x": 0.39,
        "width": 0.19,
        "type": "hold",
        "release_required": False,
    }
    normal[38] = {
        "time": round(39 * BEAT, 6),
        "x": 0.61,
        "width": 0.19,
        "type": "flick",
        "direction": "up",
        "min_speed": 480.0,
    }
    hard: list[dict[str, object]] = []
    for half_beat in range(118):
        time = (half_beat + 2) * BEAT / 2.0
        hard.append(tap(time, lanes[half_beat % len(lanes)], 0.17))
    hard[28] = {
        "path": [
            {"time": round(15 * BEAT, 6), "x": 0.18},
            {"time": round(16 * BEAT, 6), "x": 0.50},
            {"time": round(17 * BEAT, 6), "x": 0.82},
        ],
        "width": 0.17,
        "type": "slide",
        "interpolation": "smooth",
        "release_required": False,
    }
    hard[76] = {
        "time": round(39 * BEAT, 6),
        "end_time": round(41 * BEAT, 6),
        "x": 0.61,
        "width": 0.17,
        "type": "hold",
        "release_required": True,
    }
    return {
        "version": 4,
        "duration": DURATION,
        "timing": {
            "bpm": BPM,
            "first_beat": 0.0,
            "time_signature": 4,
            "source": "original_composition",
        },
        "generator": {
            "name": "tools/build_demo_song.py",
            "source": "audio.wav",
        },
        "difficulties": {
            "easy": {"label": "Easy", "stars": 1, "notes": easy},
            "normal": {"label": "Normal", "stars": 3, "notes": normal},
            "hard": {"label": "Hard", "stars": 5, "notes": hard},
        },
    }


def json_bytes(value: object) -> bytes:
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def write_package_file(package: ZipFile, name: str, content: bytes) -> None:
    info = ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
    info.compress_type = ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    package.writestr(info, content, compresslevel=9)


def build_package(root: Path) -> Path:
    demo_directory = root / "demo"
    output_path = root / "assets" / "seed" / "first_light.musirail"
    audio_path = demo_directory / "audio.wav"
    cover_path = demo_directory / "cover.png"
    if not cover_path.is_file():
        raise FileNotFoundError(f"Missing generated cover: {cover_path}")
    render_audio(audio_path)
    metadata = {
        "title": TITLE,
        "artist": ARTIST,
        "audio": "audio.wav",
        "chart": "chart.json",
        "cover": "cover.png",
        "license": "CC0-1.0",
        "license_url": "https://creativecommons.org/publicdomain/zero/1.0/",
        "source": "https://github.com/bbodin/musirail",
    }
    manifest = {
        "format": "musirail-track",
        "version": 2,
        "metadata": "metadata.json",
        "chart": "chart.json",
        "audio": {"kind": "bundled", "file": "audio.wav"},
        "cover": {"kind": "bundled", "file": "cover.png"},
        "license": "LICENSE.txt",
    }
    license_text = (
        "First Light — audio, chart, metadata, and cover artwork\n"
        "Dedicated to the public domain under CC0 1.0 by bbodin.\n"
        "https://creativecommons.org/publicdomain/zero/1.0/\n"
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output_path, "w", ZIP_DEFLATED, compresslevel=9) as package:
        write_package_file(package, "manifest.json", json_bytes(manifest))
        write_package_file(package, "metadata.json", json_bytes(metadata))
        write_package_file(package, "chart.json", json_bytes(build_chart()))
        write_package_file(package, "audio.wav", audio_path.read_bytes())
        write_package_file(package, "cover.png", cover_path.read_bytes())
        write_package_file(package, "LICENSE.txt", license_text.encode())
    audio_path.unlink()
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
    )
    args = parser.parse_args()
    package = build_package(args.root.resolve())
    print(f"Built {package}")


if __name__ == "__main__":
    main()
