"""Command-line interface shared by song-local chart generators."""

from __future__ import annotations

import argparse
from collections import Counter
import json
from pathlib import Path
from typing import Sequence

from .analysis import analyze_audio
from .chart import build_chart, write_chart
from .models import DIFFICULTIES, TimingOverrides
from .reporting import build_analysis_report, write_report


def run(
    default_song_directory: Path | None = None,
    arguments: Sequence[str] | None = None,
) -> int:
    """Generate a chart for a selected song directory."""

    parser = _make_parser(default_song_directory)
    options = parser.parse_args(arguments)
    song_directory = options.song_directory.resolve()
    metadata = _read_metadata(song_directory / "metadata.json")
    audio_option = options.audio or Path(str(metadata.get("audio", "audio.ogg")))
    audio_path = _resolve_song_path(audio_option, song_directory)
    output_path = _resolve_song_path(options.output, song_directory)
    overrides = _timing_overrides(metadata, options)

    try:
        analysis = analyze_audio(audio_path, overrides)
        difficulty_names = _get_difficulty_names(options)
        chart, quality_report = build_chart(
            analysis=analysis,
            difficulty_names=difficulty_names,
            difficulty_settings=DIFFICULTIES,
            source_name=audio_path.name,
            seed=options.seed,
        )
        write_chart(chart, output_path)
        if not options.no_reports:
            write_report(
                build_analysis_report(analysis, audio_path.name, overrides),
                _resolve_song_path(options.analysis_report, song_directory),
            )
            write_report(
                quality_report,
                _resolve_song_path(options.quality_report, song_directory),
            )
    except (FileNotFoundError, OSError, TypeError, ValueError) as error:
        parser.error(str(error))

    for difficulty_name in difficulty_names:
        difficulty = chart["difficulties"][difficulty_name]
        notes = difficulty["notes"]
        type_counts = Counter(note["type"] for note in notes)
        mix = ", ".join(
            f"{note_type}={type_counts[note_type]}"
            for note_type in ("tap", "hold", "slide", "flick")
            if type_counts[note_type]
        )
        print(
            f"{difficulty['label']}: {len(notes)} notes "
            f"({mix or 'empty'})"
        )

    print(
        f"Generated {len(difficulty_names)} difficulties at "
        f"{chart['timing']['bpm']:.3f} BPM "
        f"(confidence {analysis.bpm_confidence:.0%}) -> {output_path}"
    )
    if not options.no_reports:
        print(
            "Reports -> "
            f"{_resolve_song_path(options.analysis_report, song_directory)}, "
            f"{_resolve_song_path(options.quality_report, song_directory)}"
        )
    return 0


def _make_parser(
    default_song_directory: Path | None,
) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate a Musirail chart from audio rhythm and onset data.",
    )
    song_directory_options: dict[str, object] = {
        "type": Path,
        "help": "song folder containing metadata.json and its audio file",
    }
    if default_song_directory is not None:
        song_directory_options.update({
            "nargs": "?",
            "default": default_song_directory,
        })
    parser.add_argument("song_directory", **song_directory_options)
    parser.add_argument(
        "--audio",
        type=Path,
        help="source audio relative to the song folder (default: metadata audio)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("chart.json"),
        help="output relative to the song folder (default: chart.json)",
    )
    difficulty_group = parser.add_mutually_exclusive_group()
    difficulty_group.add_argument(
        "--difficulty",
        choices=tuple(DIFFICULTIES),
        help="generate only one difficulty (default: generate all)",
    )
    difficulty_group.add_argument(
        "--difficulties",
        choices=tuple(DIFFICULTIES),
        nargs="+",
        help="difficulty list to generate (default: easy normal hard)",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=1,
        help="seed for repeatable lane choices (default: 1)",
    )
    parser.add_argument(
        "--bpm",
        type=float,
        help="override detected BPM",
    )
    parser.add_argument(
        "--first-beat",
        type=float,
        help="override first downbeat in seconds",
    )
    parser.add_argument(
        "--time-signature",
        type=int,
        help="override beats per measure (default: metadata timing or 4)",
    )
    parser.add_argument(
        "--analysis-report",
        type=Path,
        default=Path("analysis_report.json"),
        help="analysis report path relative to the song folder",
    )
    parser.add_argument(
        "--quality-report",
        type=Path,
        default=Path("quality_report.json"),
        help="quality report path relative to the song folder",
    )
    parser.add_argument(
        "--no-reports",
        action="store_true",
        help="do not write analysis_report.json or quality_report.json",
    )
    return parser


def _resolve_song_path(path: Path, song_directory: Path) -> Path:
    if path.is_absolute():
        return path.resolve()
    return (song_directory / path).resolve()


def _get_difficulty_names(options: argparse.Namespace) -> list[str]:
    if options.difficulty is not None:
        return [options.difficulty]
    if options.difficulties is not None:
        return list(dict.fromkeys(options.difficulties))
    return list(DIFFICULTIES)


def _read_metadata(path: Path) -> dict[str, object]:
    if not path.is_file():
        return {}
    parsed = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(parsed, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return parsed


def _timing_overrides(
    metadata: dict[str, object],
    options: argparse.Namespace,
) -> TimingOverrides:
    timing_value = metadata.get("timing", {})
    timing = timing_value if isinstance(timing_value, dict) else {}
    bpm_value = options.bpm if options.bpm is not None else timing.get("bpm")
    beat_value = (
        options.first_beat
        if options.first_beat is not None
        else timing.get("first_beat")
    )
    signature_value = (
        options.time_signature
        if options.time_signature is not None
        else timing.get("time_signature", 4)
    )
    return TimingOverrides(
        bpm=float(bpm_value) if bpm_value is not None else None,
        first_beat=float(beat_value) if beat_value is not None else None,
        time_signature=int(signature_value),
    )
