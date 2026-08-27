"""Deterministic tests for the shared musical event-map generator."""

from __future__ import annotations

import unittest

import numpy as np

from utils.chart_generation.chart import build_chart
from utils.chart_generation.models import (
    AudioAnalysis,
    DIFFICULTIES,
    StructuralSection,
    TempoRegion,
)
from utils.chart_generation.patterns import lane_for_phrase


class ChartGenerationTests(unittest.TestCase):
    def test_repeated_phrase_reuses_pattern(self) -> None:
        first = [lane_for_phrase(7, 3, slot) for slot in range(16)]
        repeated = [lane_for_phrase(7, 3, slot) for slot in range(16)]
        other = [lane_for_phrase(7, 4, slot) for slot in range(16)]
        self.assertEqual(first, repeated)
        self.assertNotEqual(first, other)

    def test_difficulties_share_events_and_emit_strict_schema(self) -> None:
        analysis = _synthetic_analysis()
        chart, quality = build_chart(
            analysis,
            list(DIFFICULTIES),
            DIFFICULTIES,
            "synthetic.ogg",
            seed=4,
        )
        self.assertEqual(chart["version"], 4)
        self.assertEqual(chart["generator"]["strategy"], "musical-event-map-v2")
        self.assertEqual(
            quality["difficulty_relationships"]["easy_retained_in_normal"],
            1.0,
        )
        self.assertEqual(
            quality["difficulty_relationships"]["normal_retained_in_hard"],
            1.0,
        )
        counts = []
        for difficulty_name in DIFFICULTIES:
            notes = chart["difficulties"][difficulty_name]["notes"]
            counts.append(len(notes))
            self.assertTrue(notes)
            self.assertEqual(
                quality["difficulties"][difficulty_name]["remaining_conflicts"],
                0,
            )
            for note in notes:
                self.assertFalse(any(key.startswith("_") for key in note))
                if note["type"] == "slide":
                    self.assertGreaterEqual(len(note["path"]), 2)
                    self.assertIn(note["interpolation"], {"linear", "smooth"})
                    self.assertIn("release_required", note)
                elif note["type"] == "hold":
                    self.assertIn("release_required", note)
        self.assertLessEqual(counts[0], counts[1])
        self.assertLessEqual(counts[1], counts[2])


def _synthetic_analysis() -> AudioAnalysis:
    duration = 24.0
    bpm = 120.0
    beat_times = np.arange(0.0, duration, 0.5, dtype=np.float64)
    measure_times = beat_times[::4]
    onset_times = np.arange(1.5, 23.0, 0.25, dtype=np.float64)
    count = onset_times.size
    indexes = np.arange(count)
    strengths = (0.45 + 0.55 * ((indexes % 8) == 0)).astype(np.float64)
    bands = np.zeros((count, 3), dtype=np.float64)
    bands[:, 1] = 0.75
    bands[indexes % 4 == 0, 0] = 1.0
    bands[indexes % 4 == 2, 2] = 0.92
    chroma = np.zeros((count, 12), dtype=np.float64)
    chroma[np.arange(count), indexes % 12] = 1.0
    sustain = np.where(indexes % 11 == 0, 0.82, 0.25).astype(np.float64)
    pitch_movement = np.where(indexes % 22 == 0, 0.72, 0.18).astype(np.float64)
    sections = (
        StructuralSection(0, 0.0, 12.0, "verse", 0.55, 0.62, 0.38),
        StructuralSection(1, 12.0, 24.0, "chorus", 0.88, 0.70, 0.30),
    )
    return AudioAnalysis(
        duration=duration,
        bpm=bpm,
        bpm_source="test",
        bpm_confidence=0.9,
        bpm_alternatives=(60.0, 240.0),
        time_signature=4,
        first_downbeat=0.0,
        beat_times=beat_times,
        measure_times=measure_times,
        tempo_regions=(TempoRegion(0.0, duration, bpm, 0.9),),
        silent_sections=((10.0, 10.4),),
        low_energy_sections=((0.0, 1.0),),
        sections=sections,
        onset_times=onset_times,
        onset_strengths=strengths,
        band_strengths=bands,
        onset_energy=np.full(count, 0.72, dtype=np.float64),
        onset_percussive_ratio=np.full(count, 0.62, dtype=np.float64),
        onset_chroma=chroma,
        onset_pitch_movement=pitch_movement,
        onset_pitch_direction=np.where(indexes % 2, -1.0, 1.0).astype(np.float64),
        onset_sustain=sustain,
        onset_sustain_durations=np.where(indexes % 11 == 0, 1.5, 0.2).astype(np.float64),
        onset_cutoff_strengths=np.where(indexes % 11 == 0, 0.8, 0.1).astype(np.float64),
        onset_section_ids=(onset_times >= 12.0).astype(np.int64),
        onset_phrase_ids=((indexes // 16) % 2).astype(np.int64),
    )


if __name__ == "__main__":
    unittest.main()
