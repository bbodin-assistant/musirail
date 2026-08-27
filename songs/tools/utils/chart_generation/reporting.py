"""Human-readable JSON reports for chart authors and reviewers."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any

import numpy as np

from .models import AudioAnalysis, TimingOverrides


def build_analysis_report(
    analysis: AudioAnalysis,
    source_name: str,
    overrides: TimingOverrides,
) -> dict[str, Any]:
    """Serialize the evidence used to build the shared musical map."""

    onset_positions = _onset_grid_offsets(analysis)
    phrase_counts = Counter(int(value) for value in analysis.onset_phrase_ids)
    return {
        "version": 1,
        "source": source_name,
        "duration": round(analysis.duration, 6),
        "timing": {
            "bpm": round(analysis.bpm, 3),
            "source": analysis.bpm_source,
            "confidence": round(analysis.bpm_confidence, 4),
            "half_double_alternatives": list(analysis.bpm_alternatives),
            "first_downbeat": round(analysis.first_downbeat, 6),
            "time_signature": analysis.time_signature,
            "manual_overrides": {
                "bpm": overrides.bpm,
                "first_beat": overrides.first_beat,
                "time_signature": overrides.time_signature,
            },
            "tempo_regions": [
                {
                    "start": round(region.start, 6),
                    "end": round(region.end, 6),
                    "bpm": round(region.bpm, 3),
                    "confidence": round(region.confidence, 4),
                }
                for region in analysis.tempo_regions
            ],
        },
        "grid": {
            "beats": [round(float(value), 6) for value in analysis.beat_times],
            "measures": [round(float(value), 6) for value in analysis.measure_times],
        },
        "energy": {
            "silent_sections": [
                {"start": start, "end": end}
                for start, end in analysis.silent_sections
            ],
            "low_energy_sections": [
                {"start": start, "end": end}
                for start, end in analysis.low_energy_sections
            ],
        },
        "structure": {
            "sections": [
                {
                    "index": section.index,
                    "start": round(section.start, 6),
                    "end": round(section.end, 6),
                    "label": section.label,
                    "energy": round(section.energy, 4),
                    "percussive_activity": round(
                        section.percussive_activity,
                        4,
                    ),
                    "harmonic_activity": round(
                        section.harmonic_activity,
                        4,
                    ),
                }
                for section in analysis.sections
            ],
            "phrase_families": [
                {"id": phrase_id, "onset_count": count}
                for phrase_id, count in sorted(phrase_counts.items())
            ],
        },
        "onsets": {
            "count": int(analysis.onset_times.size),
            "mean_percussive_ratio": round(
                float(np.mean(analysis.onset_percussive_ratio))
                if analysis.onset_percussive_ratio.size
                else 0.0,
                4,
            ),
            "mean_pitch_movement": round(
                float(np.mean(analysis.onset_pitch_movement))
                if analysis.onset_pitch_movement.size
                else 0.0,
                4,
            ),
            "mean_sustain_evidence": round(
                float(np.mean(analysis.onset_sustain))
                if analysis.onset_sustain.size
                else 0.0,
                4,
            ),
            "raw_positions": onset_positions,
            "unsnapped": [
                value for value in onset_positions if not value["would_snap"]
            ],
        },
    }


def write_report(report: dict[str, Any], output_path: Path) -> None:
    """Atomically write a report."""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    try:
        temporary_path.write_text(
            json.dumps(report, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        temporary_path.replace(output_path)
    finally:
        temporary_path.unlink(missing_ok=True)


def _onset_grid_offsets(analysis: AudioAnalysis) -> list[dict[str, Any]]:
    if analysis.beat_times.size < 2:
        return [
            {
                "time": round(float(time), 6),
                "nearest_grid": round(float(time), 6),
                "offset_ms": 0.0,
            }
            for time in analysis.onset_times
        ]
    grid: list[float] = []
    for start, end in zip(
        analysis.beat_times[:-1],
        analysis.beat_times[1:],
        strict=True,
    ):
        step = (float(end) - float(start)) / 4.0
        grid.extend(float(start) + step * index for index in range(4))
    grid.append(float(analysis.beat_times[-1]))
    grid_values = np.asarray(grid)
    report: list[dict[str, float]] = []
    for time_value in analysis.onset_times:
        time = float(time_value)
        insertion = int(np.searchsorted(grid_values, time))
        nearby = grid_values[
            max(0, insertion - 1) : min(grid_values.size, insertion + 1)
        ]
        nearest = float(nearby[np.argmin(np.abs(nearby - time))])
        offset = time - nearest
        snap_limit = min(0.055, 60.0 / analysis.bpm * 0.10)
        report.append(
            {
                "time": round(time, 6),
                "nearest_grid": round(nearest, 6),
                "offset_ms": round(offset * 1000.0, 2),
                "would_snap": abs(offset) <= snap_limit,
            }
        )
    return report
