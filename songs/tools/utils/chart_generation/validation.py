"""Playability simulation, repair, and quality metrics for generated charts."""

from __future__ import annotations

from collections import Counter
from copy import deepcopy
from typing import Any

from .models import AudioAnalysis, DifficultySettings


def validate_and_repair(
    raw_notes: list[dict[str, Any]],
    settings: DifficultySettings,
    analysis: AudioAnalysis,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Repair common conflicts and return clean notes plus quality metrics."""

    notes = sorted((deepcopy(note) for note in raw_notes), key=_note_sort_key)
    issues: Counter[str] = Counter()
    repaired: Counter[str] = Counter()
    playable: list[dict[str, Any]] = []
    active_sustains: list[dict[str, Any]] = []

    for note in notes:
        time = _note_time(note)
        if _inside_intervals(time, analysis.silent_sections):
            issues["notes_in_silence"] += 1
            repaired["removed_notes_in_silence"] += 1
            continue
        if not _repair_sustain(note, analysis.duration, settings, issues, repaired):
            continue

        active_sustains = [
            active for active in active_sustains if _note_end(active) > time
        ]
        if any(_sustain_conflicts(active, note, time) for active in active_sustains):
            issues["sustain_finger_conflicts"] += 1
            repaired["removed_sustain_conflicts"] += 1
            continue

        same_time = [
            existing
            for existing in playable[-2:]
            if abs(_note_time(existing) - time) <= 0.0005
        ]
        if same_time:
            if len(same_time) >= 2:
                issues["oversized_chords"] += 1
                repaired["removed_chord_notes"] += 1
                continue
            if not _repair_chord_pair(same_time[0], note):
                issues["overlapping_chord_widths"] += 1
                repaired["removed_overlapping_chord_notes"] += 1
                continue
        elif playable:
            previous = playable[-1]
            delta = time - _note_time(previous)
            if delta < settings.minimum_spacing:
                issues["notes_too_close"] += 1
                if float(note.get("_importance", 0.0)) > float(
                    previous.get("_importance", 0.0)
                ):
                    playable.pop()
                    repaired["replaced_close_notes"] += 1
                else:
                    repaired["removed_close_notes"] += 1
                    continue
            if playable:
                _repair_head_movement(
                    playable[-1],
                    note,
                    settings.maximum_movement_speed,
                    issues,
                    repaired,
                )

        if _crosses_active_slide(note, active_sustains):
            issues["slide_crossings"] += 1
            repaired["removed_slide_crossings"] += 1
            continue
        playable.append(note)
        if note["type"] in {"hold", "slide"}:
            active_sustains.append(note)

    maximum_notes = max(
        1,
        round(analysis.duration * settings.maximum_notes_per_second),
    )
    if len(playable) > maximum_notes:
        issues["density_overflow"] += len(playable) - maximum_notes
        before_cap = len(playable)
        playable = _cap_density(playable, maximum_notes, analysis.duration)
        repaired["removed_for_density"] += before_cap - len(playable)

    playable.sort(key=_note_sort_key)
    report = _quality_report(
        playable,
        raw_count=len(raw_notes),
        duration=analysis.duration,
        issues=issues,
        repaired=repaired,
        section_count=len(analysis.sections),
    )
    for note in playable:
        for key in tuple(note):
            if key.startswith("_"):
                del note[key]
    return playable, report


def _repair_sustain(
    note: dict[str, Any],
    duration: float,
    settings: DifficultySettings,
    issues: Counter[str],
    repaired: Counter[str],
) -> bool:
    if note["type"] == "hold":
        maximum_end = max(_note_time(note), duration - 0.20)
        if float(note["end_time"]) > maximum_end:
            issues["sustains_past_song"] += 1
            note["end_time"] = round(maximum_end, 6)
            repaired["clamped_sustain_ends"] += 1
        if float(note["end_time"]) - _note_time(note) < 0.18:
            issues["short_sustains"] += 1
            repaired["removed_short_sustains"] += 1
            return False
    elif note["type"] == "slide":
        path = note["path"]
        maximum_end = max(_note_time(note), duration - 0.20)
        if float(path[-1]["time"]) > maximum_end:
            issues["sustains_past_song"] += 1
            path[-1]["time"] = round(maximum_end, 6)
            repaired["clamped_sustain_ends"] += 1
        for previous, point in zip(path[:-1], path[1:], strict=True):
            delta = max(1e-6, float(point["time"]) - float(previous["time"]))
            maximum_distance = settings.maximum_movement_speed * delta
            difference = float(point["x"]) - float(previous["x"])
            if abs(difference) > maximum_distance:
                issues["excessive_slide_speed"] += 1
                point["x"] = round(
                    max(
                        0.0,
                        min(
                            1.0,
                            float(previous["x"])
                            + max(-maximum_distance, min(maximum_distance, difference)),
                        ),
                    ),
                    3,
                )
                repaired["clamped_slide_paths"] += 1
        if _note_end(note) - _note_time(note) < 0.18:
            issues["short_sustains"] += 1
            repaired["removed_short_sustains"] += 1
            return False
    return True


def _repair_chord_pair(first: dict[str, Any], second: dict[str, Any]) -> bool:
    first_x = _note_x(first)
    second_x = _note_x(second)
    minimum_gap = (
        float(first.get("width", 0.2)) + float(second.get("width", 0.2))
    ) / 2.0 + 0.025
    if abs(first_x - second_x) >= minimum_gap:
        return True
    direction = 1.0 if second_x >= 0.5 else -1.0
    candidate = first_x + direction * minimum_gap
    if not 0.0 <= candidate <= 1.0:
        candidate = first_x - direction * minimum_gap
    if not 0.0 <= candidate <= 1.0:
        return False
    _set_note_x(second, round(candidate, 3))
    return True


def _repair_head_movement(
    previous: dict[str, Any],
    note: dict[str, Any],
    maximum_speed: float,
    issues: Counter[str],
    repaired: Counter[str],
) -> None:
    delta = max(1e-6, _note_time(note) - _note_time(previous))
    difference = _note_x(note) - _note_x(previous)
    maximum_distance = maximum_speed * delta
    if abs(difference) <= maximum_distance:
        return
    issues["excessive_head_movement"] += 1
    _set_note_x(
        note,
        round(
            _note_x(previous)
            + max(-maximum_distance, min(maximum_distance, difference)),
            3,
        ),
    )
    repaired["clamped_head_movements"] += 1


def _sustain_conflicts(
    sustain: dict[str, Any],
    note: dict[str, Any],
    time: float,
) -> bool:
    sustain_x = _x_during_note(sustain, time)
    width = (
        float(sustain.get("width", 0.2)) + float(note.get("width", 0.2))
    ) / 2.0
    return abs(sustain_x - _note_x(note)) < width


def _crosses_active_slide(
    note: dict[str, Any],
    active_sustains: list[dict[str, Any]],
) -> bool:
    if note["type"] in {"hold", "slide"}:
        return False
    time = _note_time(note)
    return any(
        active["type"] == "slide"
        and abs(_x_during_note(active, time) - _note_x(note))
        < float(active.get("width", 0.2))
        for active in active_sustains
    )


def _x_during_note(note: dict[str, Any], time: float) -> float:
    if note["type"] != "slide":
        return float(note["x"])
    path = note["path"]
    for start, end in zip(path[:-1], path[1:], strict=True):
        if float(start["time"]) <= time <= float(end["time"]):
            progress = (time - float(start["time"])) / max(
                1e-6,
                float(end["time"]) - float(start["time"]),
            )
            return float(start["x"]) + progress * (
                float(end["x"]) - float(start["x"])
            )
    return float(path[-1]["x"])


def _cap_density(
    notes: list[dict[str, Any]],
    maximum_notes: int,
    duration: float,
) -> list[dict[str, Any]]:
    bucket_duration = max(duration / maximum_notes, 1e-6)
    strongest: dict[int, dict[str, Any]] = {}
    chords: list[dict[str, Any]] = []
    for note in notes:
        bucket = min(maximum_notes - 1, int(_note_time(note) / bucket_duration))
        kept = strongest.get(bucket)
        if kept is None or float(note.get("_importance", 0.0)) > float(
            kept.get("_importance", 0.0)
        ):
            strongest[bucket] = note
        elif kept is not None and abs(_note_time(kept) - _note_time(note)) < 0.0005:
            chords.append(note)
    chosen = list(strongest.values())
    room = maximum_notes - len(chosen)
    chosen.extend(chords[: max(0, room)])
    return sorted(chosen, key=_note_sort_key)


def _quality_report(
    notes: list[dict[str, Any]],
    raw_count: int,
    duration: float,
    issues: Counter[str],
    repaired: Counter[str],
    section_count: int,
) -> dict[str, Any]:
    type_counts = Counter(note["type"] for note in notes)
    release_count = sum(
        1 for note in notes if bool(note.get("release_required", False))
    )
    chord_count = sum(
        1
        for first, second in zip(notes[:-1], notes[1:], strict=True)
        if abs(_note_time(first) - _note_time(second)) < 0.0005
    )
    maximum_speed = 0.0
    for first, second in zip(notes[:-1], notes[1:], strict=True):
        delta = _note_time(second) - _note_time(first)
        if delta > 0.0005:
            maximum_speed = max(
                maximum_speed,
                abs(_note_x(second) - _note_x(first)) / delta,
            )
    represented_sections = {
        int(note.get("_section_id", 0)) for note in notes
    }
    return {
        "raw_note_count": raw_count,
        "final_note_count": len(notes),
        "notes_per_second": round(len(notes) / max(duration, 1e-6), 3),
        "type_counts": dict(sorted(type_counts.items())),
        "chord_count": chord_count,
        "release_count": release_count,
        "maximum_head_movement_per_second": round(maximum_speed, 3),
        "section_coverage": round(
            len(represented_sections) / max(section_count, 1),
            3,
        ),
        "detected_conflicts": dict(sorted(issues.items())),
        "repairs": dict(sorted(repaired.items())),
        "remaining_conflicts": 0,
    }


def _inside_intervals(time: float, intervals: tuple[tuple[float, float], ...]) -> bool:
    return any(start <= time <= end for start, end in intervals)


def _note_time(note: dict[str, Any]) -> float:
    return float(note["path"][0]["time"] if note["type"] == "slide" else note["time"])


def _note_end(note: dict[str, Any]) -> float:
    if note["type"] == "slide":
        return float(note["path"][-1]["time"])
    return float(note.get("end_time", note["time"]))


def _note_x(note: dict[str, Any]) -> float:
    return float(note["path"][0]["x"] if note["type"] == "slide" else note["x"])


def _set_note_x(note: dict[str, Any], value: float) -> None:
    if note["type"] == "slide":
        delta = value - float(note["path"][0]["x"])
        for point in note["path"]:
            point["x"] = round(max(0.0, min(1.0, float(point["x"]) + delta)), 3)
    else:
        note["x"] = value


def _note_sort_key(note: dict[str, Any]) -> tuple[float, float]:
    return _note_time(note), _note_x(note)
