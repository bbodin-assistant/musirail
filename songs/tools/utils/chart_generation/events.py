"""Build one musical event map shared by all chart difficulties."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .models import AudioAnalysis
from .patterns import lane_for_phrase


MINIMUM_HIT_TIME = 1.50
SONG_END_MARGIN = 0.75
COMMON_SUBDIVISIONS = 4


@dataclass(frozen=True)
class MusicalEvent:
    """One interpreted musical onset before difficulty filtering."""

    event_id: int
    raw_time: float
    time: float
    snap_offset: float
    beat_index: int
    subdivision: int
    measure_index: int
    phrase_id: int
    phrase_slot: int
    section_id: int
    pattern_name: str
    lane: int
    strength: float
    importance: float
    energy: float
    bands: tuple[float, float, float]
    percussive_ratio: float
    pitch_movement: float
    pitch_direction: float
    sustain: float
    sustain_duration: float
    cutoff_strength: float
    chord_evidence: float
    accent: str
    is_downbeat: bool
    is_transition: bool


def build_event_map(analysis: AudioAnalysis, seed: int) -> list[MusicalEvent]:
    """Interpret onsets and assign reusable pattern lanes."""

    if analysis.onset_times.size == 0:
        return []
    grid = _make_grid(analysis.beat_times)
    if not grid:
        grid = [(float(time), index, 0) for index, time in enumerate(analysis.onset_times)]
    beat_duration = 60.0 / max(analysis.bpm, 1e-6)
    # Preserve expressive off-grid attacks. Only onsets already close to a
    # sixteenth-note grid are quantized.
    snap_limit = min(0.055, beat_duration * 0.10)
    section_starts = tuple(section.start for section in analysis.sections[1:])
    merged: dict[float, tuple[int, float, int, int]] = {}

    for index, raw_time_value in enumerate(analysis.onset_times):
        raw_time = float(raw_time_value)
        if not MINIMUM_HIT_TIME <= raw_time <= analysis.duration - SONG_END_MARGIN:
            continue
        grid_time, beat_index, subdivision = min(
            grid,
            key=lambda item: abs(item[0] - raw_time),
        )
        snap_offset = raw_time - grid_time
        chart_time = grid_time if abs(snap_offset) <= snap_limit else raw_time
        rounded_time = round(chart_time, 6)
        previous = merged.get(rounded_time)
        strength = float(analysis.onset_strengths[index])
        if previous is None or strength > previous[1]:
            merged[rounded_time] = (index, strength, beat_index, subdivision)

    events: list[MusicalEvent] = []
    for event_id, chart_time in enumerate(sorted(merged)):
        index, strength, beat_index, subdivision = merged[chart_time]
        raw_time = float(analysis.onset_times[index])
        bands_array = analysis.band_strengths[index]
        bands = tuple(float(value) for value in bands_array)
        energy = float(analysis.onset_energy[index])
        second_band = float(np.partition(bands_array, -2)[-2])
        chord_evidence = min(1.0, second_band * strength * (0.75 + 0.25 * energy))
        section_id = int(analysis.onset_section_ids[index])
        phrase_id = int(analysis.onset_phrase_ids[index])
        measure_index = max(
            0,
            int(np.searchsorted(analysis.measure_times, chart_time, side="right") - 1),
        ) if analysis.measure_times.size else 0
        phrase_slot = (
            (beat_index % max(1, analysis.time_signature * 2))
            * COMMON_SUBDIVISIONS
            + subdivision
        )
        lane, pattern_name = lane_for_phrase(seed, phrase_id, phrase_slot)
        is_downbeat = beat_index % analysis.time_signature == 0 and subdivision == 0
        is_transition = any(
            0.0 <= boundary - chart_time <= beat_duration * 0.55
            or 0.0 <= chart_time - boundary <= beat_duration * 0.30
            for boundary in section_starts
        )
        percussive_ratio = float(analysis.onset_percussive_ratio[index])
        importance = float(
            np.clip(
                0.37 * strength
                + 0.17 * energy
                + 0.16 * float(is_downbeat)
                + 0.12 * chord_evidence
                + 0.10 * float(is_transition)
                + 0.08 * percussive_ratio,
                0.0,
                1.0,
            )
        )
        dominant_band = int(np.argmax(bands_array))
        if is_transition and strength >= 0.58:
            accent = "transition"
        elif dominant_band == 0 and bands[0] >= 0.68:
            accent = "kick"
        elif dominant_band == 1 and bands[1] >= 0.68:
            accent = "snare"
        elif dominant_band == 2 and bands[2] >= 0.68:
            accent = "high"
        else:
            accent = "harmonic"
        events.append(
            MusicalEvent(
                event_id=event_id,
                raw_time=raw_time,
                time=chart_time,
                snap_offset=raw_time - chart_time,
                beat_index=beat_index,
                subdivision=subdivision,
                measure_index=measure_index,
                phrase_id=phrase_id,
                phrase_slot=phrase_slot,
                section_id=section_id,
                pattern_name=pattern_name,
                lane=lane,
                strength=strength,
                importance=importance,
                energy=energy,
                bands=bands,
                percussive_ratio=percussive_ratio,
                pitch_movement=float(analysis.onset_pitch_movement[index]),
                pitch_direction=float(analysis.onset_pitch_direction[index]),
                sustain=float(analysis.onset_sustain[index]),
                sustain_duration=float(analysis.onset_sustain_durations[index]),
                cutoff_strength=float(analysis.onset_cutoff_strengths[index]),
                chord_evidence=chord_evidence,
                accent=accent,
                is_downbeat=is_downbeat,
                is_transition=is_transition,
            )
        )
    return events


def _make_grid(beat_times: np.ndarray) -> list[tuple[float, int, int]]:
    if beat_times.size < 2:
        return []
    grid: list[tuple[float, int, int]] = []
    for beat_index, (start, end) in enumerate(
        zip(beat_times[:-1], beat_times[1:], strict=True)
    ):
        step = (float(end) - float(start)) / COMMON_SUBDIVISIONS
        for subdivision in range(COMMON_SUBDIVISIONS):
            grid.append(
                (
                    float(start) + subdivision * step,
                    beat_index,
                    subdivision,
                )
            )
    grid.append((float(beat_times[-1]), beat_times.size - 1, 0))
    return grid
