"""Derive coherent, playable difficulties from one musical interpretation."""

from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any, Mapping, Sequence

import numpy as np

from .events import MusicalEvent, build_event_map
from .models import AudioAnalysis, DifficultySettings
from .patterns import lane_for_phrase
from .validation import validate_and_repair


LANE_POSITIONS = (0.15, 0.30, 0.50, 0.70, 0.85)
SONG_END_MARGIN = 0.75


def build_chart(
    analysis: AudioAnalysis,
    difficulty_names: Sequence[str],
    difficulty_settings: Mapping[str, DifficultySettings],
    source_name: str,
    seed: int,
) -> tuple[dict[str, Any], dict[str, Any]]:
    """Build requested difficulties and a quality report from one event map."""

    event_map = build_event_map(analysis, seed)
    difficulties: dict[str, dict[str, Any]] = {}
    quality_difficulties: dict[str, dict[str, Any]] = {}
    selected_event_ids: dict[str, set[int]] = {}
    required_event_ids: set[int] = set()
    for difficulty_name in difficulty_names:
        settings = difficulty_settings[difficulty_name]
        difficulty, quality, event_ids = build_difficulty(
            analysis=analysis,
            events=event_map,
            settings=settings,
            seed=seed,
            required_event_ids=required_event_ids,
        )
        difficulties[difficulty_name] = difficulty
        quality_difficulties[difficulty_name] = quality
        selected_event_ids[difficulty_name] = event_ids
        required_event_ids = event_ids

    nesting: dict[str, float] = {}
    ordered = [name for name in difficulty_settings if name in selected_event_ids]
    for easier, harder in zip(ordered[:-1], ordered[1:], strict=True):
        easy_events = selected_event_ids[easier]
        nesting[f"{easier}_retained_in_{harder}"] = round(
            len(easy_events & selected_event_ids[harder]) / max(len(easy_events), 1),
            3,
        )
    chart = {
        "version": 4,
        "duration": round(analysis.duration, 6),
        "timing": {
            "bpm": round(analysis.bpm, 3),
            "first_beat": round(analysis.first_downbeat, 6),
            "time_signature": analysis.time_signature,
            "confidence": round(analysis.bpm_confidence, 4),
            "source": analysis.bpm_source,
        },
        "generator": {
            "name": "musirail-ogg2json",
            "strategy": "musical-event-map-v2",
            "seed": seed,
            "source": source_name,
            "difficulties": list(difficulty_names),
        },
        "difficulties": difficulties,
    }
    phrase_measures: dict[int, set[int]] = {}
    for event in event_map:
        phrase_measures.setdefault(event.phrase_id, set()).add(event.measure_index)
    repeated_phrase_ids = {
        phrase_id
        for phrase_id, measures in phrase_measures.items()
        if len(measures) > 1
    }
    quality_report = {
        "version": 1,
        "generator_strategy": "musical-event-map-v2",
        "source": source_name,
        "event_map": {
            "interpreted_event_count": len(event_map),
            "section_count": len(analysis.sections),
            "phrase_family_count": len({event.phrase_id for event in event_map}),
            "repeated_phrase_family_count": len(repeated_phrase_ids),
            "events_in_repeated_phrases": sum(
                1 for event in event_map if event.phrase_id in repeated_phrase_ids
            ),
            "pattern_usage": dict(
                sorted(Counter(event.pattern_name for event in event_map).items())
            ),
        },
        "difficulty_relationships": nesting,
        "difficulties": quality_difficulties,
    }
    return chart, quality_report


def build_difficulty(
    analysis: AudioAnalysis,
    events: list[MusicalEvent],
    settings: DifficultySettings,
    seed: int,
    required_event_ids: set[int] | None = None,
) -> tuple[dict[str, Any], dict[str, Any], set[int]]:
    """Select evidence-backed mechanics for one view of the event map."""

    selected = _select_events(
        analysis,
        events,
        settings,
        required_event_ids or set(),
    )
    beat_duration = 60.0 / max(analysis.bpm, 1e-6)
    notes: list[dict[str, Any]] = []
    selected_event_ids: set[int] = set()
    last_special_time = -float("inf")
    for event in selected:
        note_type = _choose_note_type(event, settings, beat_duration)
        if (
            note_type != "tap"
            and event.time - last_special_time < settings.special_cooldown
        ):
            note_type = "tap"
        note = _make_note(
            event,
            note_type,
            analysis,
            settings,
            beat_duration,
            seed,
        )
        notes.append(note)
        selected_event_ids.add(event.event_id)
        if note_type in {"hold", "slide"}:
            last_special_time = event.time
        elif note_type == "flick":
            last_special_time = event.time

        if (
            note_type == "tap"
            and settings.allow_chords
            and event.chord_evidence >= settings.chord_evidence_threshold
            and (event.is_downbeat or event.is_transition or event.strength >= 0.82)
        ):
            chord_lane = _chord_lane(event.lane, event.bands)
            notes.append(
                _with_internal_evidence(
                    _make_tap(event.time, chord_lane, settings.note_width),
                    event,
                    importance=event.importance * 0.92,
                )
            )

    playable, quality = validate_and_repair(notes, settings, analysis)
    quality["selected_musical_events"] = len(selected_event_ids)
    quality["selection_percentile"] = settings.onset_percentile
    return (
        {
            "label": settings.label,
            "stars": settings.stars,
            "notes": playable,
        },
        quality,
        selected_event_ids,
    )


def write_chart(chart: dict[str, Any], output_path: Path) -> None:
    """Atomically write a chart so a failed run cannot corrupt the old one."""

    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_path = output_path.with_suffix(output_path.suffix + ".tmp")
    try:
        temporary_path.write_text(
            json.dumps(chart, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        temporary_path.replace(output_path)
    finally:
        temporary_path.unlink(missing_ok=True)


def _select_events(
    analysis: AudioAnalysis,
    events: list[MusicalEvent],
    settings: DifficultySettings,
    required_event_ids: set[int],
) -> list[MusicalEvent]:
    if not events:
        return []
    allowed_step = max(1, 4 // settings.beat_subdivisions)
    grid_candidates = [
        event
        for event in events
        if event.subdivision % allowed_step == 0
        or (event.is_transition and event.strength >= 0.72)
    ]
    threshold = float(
        np.percentile(
            [event.importance for event in grid_candidates],
            settings.onset_percentile,
        )
    ) if grid_candidates else 1.0
    beat_duration = 60.0 / max(analysis.bpm, 1e-6)
    section_starts = tuple(section.start for section in analysis.sections[1:])
    candidates = []
    for event in grid_candidates:
        before_transition = any(
            beat_duration * 0.12 < boundary - event.time < beat_duration * 0.58
            for boundary in section_starts
        )
        if before_transition and not event.is_downbeat:
            continue
        if (
            event.importance >= threshold
            or event.is_downbeat and event.strength >= 0.34
            or event.is_transition and event.strength >= 0.55
        ):
            candidates.append(event)

    selected: list[MusicalEvent] = []
    candidate_ids = {event.event_id for event in candidates}
    candidates.extend(
        event
        for event in events
        if event.event_id in required_event_ids
        and event.event_id not in candidate_ids
    )
    for event in sorted(
        candidates,
        key=lambda value: (
            value.event_id in required_event_ids,
            value.importance,
        ),
        reverse=True,
    ):
        conflicting = next(
            (
                kept
                for kept in selected
                if abs(event.time - kept.time) < settings.minimum_spacing
            ),
            None,
        )
        if conflicting is None:
            selected.append(event)
    maximum_notes = max(
        1,
        round(analysis.duration * settings.maximum_notes_per_second),
    )
    if len(selected) > maximum_notes:
        selected = _cap_events_across_song(
            selected,
            analysis.duration,
            maximum_notes,
            required_event_ids,
        )
    return sorted(selected, key=lambda event: event.time)


def _cap_events_across_song(
    events: list[MusicalEvent],
    duration: float,
    maximum_notes: int,
    required_event_ids: set[int],
) -> list[MusicalEvent]:
    required = [
        event for event in events if event.event_id in required_event_ids
    ]
    if len(required) >= maximum_notes:
        return sorted(
            required,
            key=lambda event: event.importance,
            reverse=True,
        )[:maximum_notes]
    remaining_slots = maximum_notes - len(required)
    bucket_duration = max(duration / remaining_slots, 1e-6)
    strongest_by_bucket: dict[int, MusicalEvent] = {}
    for event in events:
        if event.event_id in required_event_ids:
            continue
        bucket = min(remaining_slots - 1, int(event.time / bucket_duration))
        kept = strongest_by_bucket.get(bucket)
        if kept is None or event.importance > kept.importance:
            strongest_by_bucket[bucket] = event
    chosen = required + list(strongest_by_bucket.values())
    if len(chosen) < maximum_notes:
        chosen_ids = {event.event_id for event in chosen}
        remaining = sorted(
            (event for event in events if event.event_id not in chosen_ids),
            key=lambda event: event.importance,
            reverse=True,
        )
        chosen.extend(remaining[: maximum_notes - len(chosen)])
    return chosen


def _choose_note_type(
    event: MusicalEvent,
    settings: DifficultySettings,
    beat_duration: float,
) -> str:
    if (
        event.sustain >= settings.sustain_threshold
        and event.sustain_duration >= beat_duration * 1.35
    ):
        if (
            settings.maximum_slide_segments > 0
            and event.pitch_movement >= settings.slide_movement_threshold
        ):
            return "slide"
        return "hold"
    accent_score = (
        0.60 * event.strength
        + 0.25 * event.bands[2]
        + 0.15 * float(event.is_transition)
    )
    if (
        accent_score >= settings.flick_accent_threshold
        and event.accent in {"high", "snare", "transition"}
        and event.sustain < settings.sustain_threshold
    ):
        return "flick"
    return "tap"


def _make_note(
    event: MusicalEvent,
    note_type: str,
    analysis: AudioAnalysis,
    settings: DifficultySettings,
    beat_duration: float,
    seed: int,
) -> dict[str, Any]:
    if note_type == "hold":
        end_time = _evidence_end_time(event, analysis.duration, beat_duration)
        note = {
            "time": round(event.time, 6),
            "end_time": end_time,
            "x": LANE_POSITIONS[event.lane],
            "width": settings.note_width,
            "type": "hold",
            "release_required": bool(
                settings.allow_release
                and event.cutoff_strength >= settings.release_evidence_threshold
            ),
        }
    elif note_type == "slide":
        end_time = _evidence_end_time(event, analysis.duration, beat_duration)
        path = _slide_path(event, end_time, settings, beat_duration, seed)
        note = {
            "path": path,
            "width": settings.note_width,
            "type": "slide",
            "interpolation": (
                "smooth" if event.percussive_ratio < 0.58 else "linear"
            ),
            "release_required": bool(
                settings.allow_release
                and event.cutoff_strength >= settings.release_evidence_threshold
            ),
        }
    elif note_type == "flick":
        note = {
            "time": round(event.time, 6),
            "x": LANE_POSITIONS[event.lane],
            "width": settings.note_width,
            "type": "flick",
            "direction": _flick_direction(event),
            "min_speed": settings.flick_minimum_speed,
        }
    else:
        note = _make_tap(event.time, event.lane, settings.note_width)
    return _with_internal_evidence(note, event, event.importance)


def _evidence_end_time(
    event: MusicalEvent,
    duration: float,
    beat_duration: float,
) -> float:
    sustain_beats = max(2, min(4, round(event.sustain_duration / beat_duration)))
    return round(
        min(event.time + sustain_beats * beat_duration, duration - SONG_END_MARGIN),
        6,
    )


def _slide_path(
    event: MusicalEvent,
    end_time: float,
    settings: DifficultySettings,
    beat_duration: float,
    seed: int,
) -> list[dict[str, float]]:
    duration = end_time - event.time
    segment_count = max(
        1,
        min(settings.maximum_slide_segments, round(duration / beat_duration)),
    )
    lanes = [event.lane]
    direction = 1 if event.pitch_direction >= 0.0 else -1
    for segment in range(1, segment_count + 1):
        motif_lane, _ = lane_for_phrase(
            seed,
            event.phrase_id,
            event.phrase_slot + segment * 2,
        )
        current = lanes[-1]
        if event.pitch_movement >= 0.58:
            candidate = current + direction * max(1, abs(motif_lane - current))
            direction *= -1
        else:
            candidate = motif_lane
        lanes.append(max(0, min(4, candidate)))
    return [
        {
            "time": round(event.time + duration * index / segment_count, 6),
            "x": LANE_POSITIONS[lane],
        }
        for index, lane in enumerate(lanes)
    ]


def _flick_direction(event: MusicalEvent) -> str:
    if event.accent == "transition" or event.lane == 2:
        return "up"
    if event.pitch_direction < 0.0 or event.lane <= 1:
        return "left"
    if event.pitch_direction > 0.0 or event.lane >= 3:
        return "right"
    return "up"


def _chord_lane(primary_lane: int, bands: tuple[float, float, float]) -> int:
    if bands[0] >= bands[2]:
        candidates = (0, 1)
    else:
        candidates = (3, 4)
    return max(candidates, key=lambda lane: abs(lane - primary_lane))


def _make_tap(time: float, lane: int, width: float) -> dict[str, Any]:
    return {
        "time": round(time, 6),
        "x": LANE_POSITIONS[lane],
        "width": width,
        "type": "tap",
    }


def _with_internal_evidence(
    note: dict[str, Any],
    event: MusicalEvent,
    importance: float,
) -> dict[str, Any]:
    note["_event_id"] = event.event_id
    note["_importance"] = importance
    note["_section_id"] = event.section_id
    return note
