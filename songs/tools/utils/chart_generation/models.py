"""Typed data shared by analysis, generation, validation, and reports."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from numpy.typing import NDArray


FloatArray = NDArray[np.float64]
IntArray = NDArray[np.int64]


@dataclass(frozen=True)
class TimingOverrides:
    """Optional author-provided timing values, expressed in song seconds."""

    bpm: float | None = None
    first_beat: float | None = None
    time_signature: int = 4


@dataclass(frozen=True)
class TempoRegion:
    """A contiguous region whose local beat intervals imply one tempo."""

    start: float
    end: float
    bpm: float
    confidence: float


@dataclass(frozen=True)
class StructuralSection:
    """A coarse musical section bounded on measure starts."""

    index: int
    start: float
    end: float
    label: str
    energy: float
    percussive_activity: float
    harmonic_activity: float


@dataclass(frozen=True)
class DifficultySettings:
    """Rules for deriving one difficulty from the shared musical event map."""

    label: str
    stars: int
    onset_percentile: float
    minimum_spacing: float
    maximum_notes_per_second: float
    beat_subdivisions: int
    note_width: float
    allow_chords: bool
    chord_evidence_threshold: float
    sustain_threshold: float
    slide_movement_threshold: float
    flick_accent_threshold: float
    special_cooldown: float
    flick_minimum_speed: float
    maximum_slide_segments: int
    allow_release: bool
    release_evidence_threshold: float
    maximum_movement_speed: float


DIFFICULTIES: dict[str, DifficultySettings] = {
    "easy": DifficultySettings(
        label="Easy",
        stars=1,
        onset_percentile=60.0,
        minimum_spacing=0.30,
        maximum_notes_per_second=0.9,
        beat_subdivisions=1,
        note_width=0.20,
        allow_chords=False,
        chord_evidence_threshold=1.1,
        sustain_threshold=0.70,
        slide_movement_threshold=1.1,
        flick_accent_threshold=0.76,
        special_cooldown=3.0,
        flick_minimum_speed=550.0,
        maximum_slide_segments=1,
        allow_release=False,
        release_evidence_threshold=1.1,
        maximum_movement_speed=1.25,
    ),
    "normal": DifficultySettings(
        label="Normal",
        stars=3,
        onset_percentile=38.0,
        minimum_spacing=0.18,
        maximum_notes_per_second=1.5,
        beat_subdivisions=2,
        note_width=0.18,
        allow_chords=True,
        chord_evidence_threshold=0.46,
        sustain_threshold=0.58,
        slide_movement_threshold=0.42,
        flick_accent_threshold=0.65,
        special_cooldown=1.8,
        flick_minimum_speed=650.0,
        maximum_slide_segments=2,
        allow_release=True,
        release_evidence_threshold=0.42,
        maximum_movement_speed=1.85,
    ),
    "hard": DifficultySettings(
        label="Hard",
        stars=5,
        onset_percentile=16.0,
        minimum_spacing=0.095,
        maximum_notes_per_second=2.4,
        beat_subdivisions=4,
        note_width=0.16,
        allow_chords=True,
        chord_evidence_threshold=0.36,
        sustain_threshold=0.48,
        slide_movement_threshold=0.28,
        flick_accent_threshold=0.56,
        special_cooldown=1.0,
        flick_minimum_speed=750.0,
        maximum_slide_segments=3,
        allow_release=True,
        release_evidence_threshold=0.32,
        maximum_movement_speed=2.60,
    ),
}


@dataclass(frozen=True)
class AudioAnalysis:
    """Rhythm, timbre, structure, and gesture evidence for one audio file."""

    duration: float
    bpm: float
    bpm_source: str
    bpm_confidence: float
    bpm_alternatives: tuple[float, ...]
    time_signature: int
    first_downbeat: float
    beat_times: FloatArray
    measure_times: FloatArray
    tempo_regions: tuple[TempoRegion, ...]
    silent_sections: tuple[tuple[float, float], ...]
    low_energy_sections: tuple[tuple[float, float], ...]
    sections: tuple[StructuralSection, ...]
    onset_times: FloatArray
    onset_strengths: FloatArray
    band_strengths: FloatArray
    onset_energy: FloatArray
    onset_percussive_ratio: FloatArray
    onset_chroma: FloatArray
    onset_pitch_movement: FloatArray
    onset_pitch_direction: FloatArray
    onset_sustain: FloatArray
    onset_sustain_durations: FloatArray
    onset_cutoff_strengths: FloatArray
    onset_section_ids: IntArray
    onset_phrase_ids: IntArray
