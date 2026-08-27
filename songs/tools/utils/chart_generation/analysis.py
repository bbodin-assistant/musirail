"""Extract rhythm, timbre, structure, and gesture evidence from audio."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import librosa
import numpy as np
from mutagen import File as MutagenFile

from .models import (
    AudioAnalysis,
    StructuralSection,
    TempoRegion,
    TimingOverrides,
)


SAMPLE_RATE = 22_050
HOP_LENGTH = 512
FFT_SIZE = 2_048
FREQUENCY_BANDS = (
    (20.0, 220.0),
    (220.0, 2_200.0),
    (2_200.0, SAMPLE_RATE / 2.0),
)


def analyze_audio(
    audio_path: Path,
    overrides: TimingOverrides | None = None,
) -> AudioAnalysis:
    """Analyze *audio_path* once for every chart difficulty."""

    if not audio_path.is_file():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")
    overrides = overrides or TimingOverrides()
    if overrides.bpm is not None and not 30.0 <= overrides.bpm <= 300.0:
        raise ValueError("Manual BPM must be between 30 and 300.")
    if overrides.first_beat is not None and overrides.first_beat < 0.0:
        raise ValueError("Manual first_beat cannot be negative.")
    if not 2 <= overrides.time_signature <= 12:
        raise ValueError("time_signature must be between 2 and 12.")

    audio, sample_rate = librosa.load(audio_path, sr=SAMPLE_RATE, mono=True)
    sample_rate = int(sample_rate)
    if audio.size == 0:
        raise ValueError(f"Audio file is empty: {audio_path}")

    duration = float(librosa.get_duration(y=audio, sr=sample_rate))
    harmonic, percussive = librosa.effects.hpss(audio)
    onset_envelope = librosa.onset.onset_strength(
        y=percussive,
        sr=sample_rate,
        hop_length=HOP_LENGTH,
        aggregate=np.median,
    )
    tagged_bpm = _read_tagged_bpm(audio_path)
    tempo, detected_beat_frames = librosa.beat.beat_track(
        onset_envelope=onset_envelope,
        sr=sample_rate,
        hop_length=HOP_LENGTH,
        units="frames",
        bpm=overrides.bpm or tagged_bpm,
    )
    detected_beat_frames = np.asarray(detected_beat_frames, dtype=np.int64)
    detected_beat_times = librosa.frames_to_time(
        detected_beat_frames,
        sr=sample_rate,
        hop_length=HOP_LENGTH,
    ).astype(np.float64)
    estimated_bpm = (
        float(overrides.bpm)
        if overrides.bpm is not None
        else float(tagged_bpm)
        if tagged_bpm is not None
        else float(np.asarray(tempo).reshape(-1)[0])
        if np.size(tempo)
        else _bpm_from_beats(detected_beat_times)
    )
    if estimated_bpm <= 0.0:
        estimated_bpm = 120.0

    beat_times = detected_beat_times
    bpm_source = "estimated"
    if tagged_bpm is not None:
        bpm_source = "audio_metadata"
    if overrides.bpm is not None or overrides.first_beat is not None:
        anchor = (
            float(overrides.first_beat)
            if overrides.first_beat is not None
            else float(detected_beat_times[0])
            if detected_beat_times.size
            else 0.0
        )
        beat_times = np.arange(
            anchor,
            duration,
            60.0 / estimated_bpm,
            dtype=np.float64,
        )
        bpm_source = "manual_override"

    bpm_confidence = _bpm_confidence(
        onset_envelope,
        beat_times,
        estimated_bpm,
        sample_rate,
        tagged_bpm is not None or overrides.bpm is not None,
    )
    bpm_alternatives = tuple(
        round(value, 3)
        for value in (estimated_bpm / 2.0, estimated_bpm * 2.0)
        if 30.0 <= value <= 300.0
    )
    first_downbeat, downbeat_index = _find_first_downbeat(
        beat_times,
        onset_envelope,
        sample_rate,
        overrides.time_signature,
        overrides.first_beat,
    )
    measure_times = beat_times[
        downbeat_index :: overrides.time_signature
    ].astype(np.float64)
    tempo_regions = _detect_tempo_regions(
        beat_times,
        duration,
        estimated_bpm,
        bpm_confidence,
        bpm_source == "manual_override",
    )

    onset_frames = np.asarray(
        librosa.onset.onset_detect(
            onset_envelope=onset_envelope,
            sr=sample_rate,
            hop_length=HOP_LENGTH,
            units="frames",
            # Keep the actual energy peak. Backtracking is useful for slicing
            # audio, but measuring strength at the preceding minimum erases
            # the accent evidence needed by chart generation.
            backtrack=False,
            normalize=True,
        ),
        dtype=np.int64,
    )
    onset_times = librosa.frames_to_time(
        onset_frames,
        sr=sample_rate,
        hop_length=HOP_LENGTH,
    ).astype(np.float64)
    safe_onsets = np.clip(onset_frames, 0, max(0, onset_envelope.size - 1))
    onset_strengths = _normalize(onset_envelope[safe_onsets])
    band_strengths = _band_flux_at_onsets(
        percussive,
        sample_rate,
        onset_frames,
    )

    rms = librosa.feature.rms(
        y=audio,
        frame_length=FFT_SIZE,
        hop_length=HOP_LENGTH,
    )[0]
    harmonic_rms = librosa.feature.rms(
        y=harmonic,
        frame_length=FFT_SIZE,
        hop_length=HOP_LENGTH,
    )[0]
    percussive_rms = librosa.feature.rms(
        y=percussive,
        frame_length=FFT_SIZE,
        hop_length=HOP_LENGTH,
    )[0]
    normalized_rms = _normalize(rms, percentile=95.0)
    normalized_harmonic = _normalize(harmonic_rms, percentile=95.0)
    normalized_percussive = _normalize(percussive_rms, percentile=95.0)
    onset_energy = _sample_frames(normalized_rms, onset_frames)
    onset_harmonic = _sample_frames(normalized_harmonic, onset_frames)
    onset_percussive = _sample_frames(normalized_percussive, onset_frames)
    onset_percussive_ratio = np.divide(
        onset_percussive,
        onset_percussive + onset_harmonic + 1e-9,
    ).astype(np.float64)

    chroma = librosa.feature.chroma_stft(
        y=harmonic,
        sr=sample_rate,
        n_fft=FFT_SIZE,
        hop_length=HOP_LENGTH,
    )
    onset_chroma, pitch_movement, pitch_direction = _pitch_features(
        chroma,
        onset_frames,
        estimated_bpm,
        sample_rate,
    )
    sustain, sustain_durations, cutoff_strengths = _sustain_features(
        normalized_harmonic,
        onset_frames,
        estimated_bpm,
        sample_rate,
    )
    # A long tail is only meaningful when harmonic energy is actually present;
    # dense percussion can otherwise make nearly every onset look sustained.
    sustain = np.clip(
        sustain
        * (0.30 + 0.70 * onset_harmonic)
        * (1.0 - 0.58 * onset_percussive_ratio),
        0.0,
        1.0,
    ).astype(np.float64)
    silent_sections = _masked_intervals(
        librosa.amplitude_to_db(rms, ref=np.max) < -42.0,
        sample_rate,
        minimum_duration=0.35,
    )
    active_rms = normalized_rms[
        librosa.amplitude_to_db(rms, ref=np.max) >= -42.0
    ]
    low_threshold = (
        float(np.percentile(active_rms, 28.0))
        if active_rms.size
        else 0.0
    )
    low_energy_sections = _masked_intervals(
        (normalized_rms <= low_threshold)
        & (librosa.amplitude_to_db(rms, ref=np.max) >= -42.0),
        sample_rate,
        minimum_duration=max(0.75, 60.0 / estimated_bpm),
    )

    (
        sections,
        onset_section_ids,
        onset_phrase_ids,
    ) = _analyze_structure(
        duration=duration,
        measure_times=measure_times,
        onset_times=onset_times,
        onset_strengths=onset_strengths,
        onset_chroma=onset_chroma,
        onset_energy=onset_energy,
        onset_percussive_ratio=onset_percussive_ratio,
    )

    return AudioAnalysis(
        duration=duration,
        bpm=estimated_bpm,
        bpm_source=bpm_source,
        bpm_confidence=bpm_confidence,
        bpm_alternatives=bpm_alternatives,
        time_signature=overrides.time_signature,
        first_downbeat=first_downbeat,
        beat_times=beat_times,
        measure_times=measure_times,
        tempo_regions=tempo_regions,
        silent_sections=silent_sections,
        low_energy_sections=low_energy_sections,
        sections=sections,
        onset_times=onset_times,
        onset_strengths=onset_strengths,
        band_strengths=band_strengths,
        onset_energy=onset_energy,
        onset_percussive_ratio=onset_percussive_ratio,
        onset_chroma=onset_chroma,
        onset_pitch_movement=pitch_movement,
        onset_pitch_direction=pitch_direction,
        onset_sustain=sustain,
        onset_sustain_durations=sustain_durations,
        onset_cutoff_strengths=cutoff_strengths,
        onset_section_ids=onset_section_ids,
        onset_phrase_ids=onset_phrase_ids,
    )


def _read_tagged_bpm(audio_path: Path) -> float | None:
    try:
        metadata: Any = MutagenFile(audio_path)
    except (OSError, ValueError):
        return None
    if metadata is None or metadata.tags is None:
        return None
    for key, tagged_values in metadata.tags.items():
        if str(key).casefold().strip() not in {
            "bpm",
            "tbpm",
            "bpm (beats per minute)",
        }:
            continue
        raw_value = (
            tagged_values[0]
            if isinstance(tagged_values, list)
            else tagged_values
        )
        try:
            bpm = float(str(raw_value).strip())
        except ValueError:
            return None
        return bpm if 30.0 <= bpm <= 300.0 else None
    return None


def _bpm_from_beats(beat_times: np.ndarray) -> float:
    if beat_times.size < 2:
        return 0.0
    interval = float(np.median(np.diff(beat_times)))
    return 60.0 / interval if interval > 0.0 else 0.0


def _bpm_confidence(
    onset_envelope: np.ndarray,
    beat_times: np.ndarray,
    bpm: float,
    sample_rate: int,
    trusted_source: bool,
) -> float:
    if trusted_source:
        return 0.98
    if onset_envelope.size == 0 or beat_times.size < 3 or bpm <= 0.0:
        return 0.0
    autocorrelation = librosa.autocorrelate(onset_envelope)
    lag = int(round(60.0 / bpm * sample_rate / HOP_LENGTH))
    periodicity = (
        float(autocorrelation[lag] / max(autocorrelation[0], 1e-9))
        if 0 < lag < autocorrelation.size
        else 0.0
    )
    intervals = np.diff(beat_times)
    consistency = 1.0 - min(
        1.0,
        float(np.std(intervals) / max(np.median(intervals), 1e-9)),
    )
    return round(float(np.clip(0.55 * periodicity + 0.45 * consistency, 0, 1)), 4)


def _find_first_downbeat(
    beat_times: np.ndarray,
    onset_envelope: np.ndarray,
    sample_rate: int,
    time_signature: int,
    manual_first_beat: float | None,
) -> tuple[float, int]:
    if beat_times.size == 0:
        return (manual_first_beat or 0.0), 0
    if manual_first_beat is not None:
        return float(manual_first_beat), 0
    beat_frames = librosa.time_to_frames(
        beat_times,
        sr=sample_rate,
        hop_length=HOP_LENGTH,
    )
    beat_frames = np.clip(beat_frames, 0, max(0, onset_envelope.size - 1))
    strengths = onset_envelope[beat_frames]
    phase_scores = [
        float(np.mean(strengths[phase::time_signature]))
        if strengths[phase::time_signature].size
        else 0.0
        for phase in range(time_signature)
    ]
    phase = int(np.argmax(phase_scores))
    return float(beat_times[phase]), phase


def _detect_tempo_regions(
    beat_times: np.ndarray,
    duration: float,
    global_bpm: float,
    confidence: float,
    fixed_tempo: bool,
) -> tuple[TempoRegion, ...]:
    if fixed_tempo or beat_times.size < 10:
        return (TempoRegion(0.0, duration, global_bpm, confidence),)
    intervals = np.diff(beat_times)
    local_bpms = np.asarray(
        [
            60.0 / max(float(np.median(intervals[max(0, i - 4) : i + 4])), 1e-6)
            for i in range(intervals.size)
        ]
    )
    regions: list[TempoRegion] = []
    start_index = 0
    running = float(local_bpms[0])
    for index, value in enumerate(local_bpms[1:], start=1):
        if abs(float(value) - running) / max(running, 1e-6) < 0.065:
            running = 0.85 * running + 0.15 * float(value)
            continue
        if index - start_index >= 4:
            regions.append(
                TempoRegion(
                    start=(0.0 if not regions else float(beat_times[start_index])),
                    end=float(beat_times[index]),
                    bpm=float(np.median(local_bpms[start_index:index])),
                    confidence=confidence,
                )
            )
            start_index = index
        running = float(value)
    regions.append(
        TempoRegion(
            start=(0.0 if not regions else float(beat_times[start_index])),
            end=duration,
            bpm=float(np.median(local_bpms[start_index:])),
            confidence=confidence,
        )
    )
    minimum_region_duration = 8.0 * 60.0 / max(global_bpm, 1e-6)
    merged: list[TempoRegion] = []
    for region in regions:
        if merged and region.end - region.start < minimum_region_duration:
            previous = merged.pop()
            combined_duration = region.end - previous.start
            weighted_bpm = (
                previous.bpm * (previous.end - previous.start)
                + region.bpm * (region.end - region.start)
            ) / max(combined_duration, 1e-6)
            merged.append(
                TempoRegion(
                    previous.start,
                    region.end,
                    weighted_bpm,
                    min(previous.confidence, region.confidence),
                )
            )
        else:
            merged.append(region)
    return tuple(merged)


def _band_flux_at_onsets(
    audio: np.ndarray,
    sample_rate: int,
    onset_frames: np.ndarray,
) -> np.ndarray:
    spectrum = np.abs(
        librosa.stft(audio, n_fft=FFT_SIZE, hop_length=HOP_LENGTH)
    )
    spectral_flux = np.maximum(
        0.0,
        np.diff(spectrum, axis=1, prepend=spectrum[:, :1]),
    )
    frequencies = librosa.fft_frequencies(sr=sample_rate, n_fft=FFT_SIZE)
    band_flux = np.zeros((onset_frames.size, len(FREQUENCY_BANDS)))
    safe_frames = np.clip(onset_frames, 0, max(0, spectral_flux.shape[1] - 1))
    for band_index, (lower, upper) in enumerate(FREQUENCY_BANDS):
        bins = (frequencies >= lower) & (frequencies < upper)
        if np.any(bins):
            band_flux[:, band_index] = np.sum(
                spectral_flux[bins][:, safe_frames],
                axis=0,
            )
    row_peaks = np.max(band_flux, axis=1, keepdims=True)
    return np.divide(
        band_flux,
        row_peaks,
        out=np.zeros_like(band_flux),
        where=row_peaks > 0.0,
    ).astype(np.float64)


def _normalize(values: np.ndarray, percentile: float = 100.0) -> np.ndarray:
    values = np.asarray(values, dtype=np.float64)
    if values.size == 0:
        return values
    scale = float(np.percentile(values, percentile))
    if scale <= 0.0:
        return np.zeros_like(values, dtype=np.float64)
    return np.clip(values / scale, 0.0, 1.0).astype(np.float64)


def _sample_frames(values: np.ndarray, frames: np.ndarray) -> np.ndarray:
    safe_frames = np.clip(frames, 0, max(0, values.size - 1))
    return np.asarray(values[safe_frames], dtype=np.float64)


def _pitch_features(
    chroma: np.ndarray,
    onset_frames: np.ndarray,
    bpm: float,
    sample_rate: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    if onset_frames.size == 0:
        empty = np.zeros((0,), dtype=np.float64)
        return np.zeros((0, 12), dtype=np.float64), empty, empty
    safe = np.clip(onset_frames, 0, max(0, chroma.shape[1] - 1))
    lookahead = max(1, int(60.0 / bpm * sample_rate / HOP_LENGTH))
    future = np.clip(safe + lookahead, 0, max(0, chroma.shape[1] - 1))
    onset_chroma = chroma[:, safe].T.astype(np.float64)
    future_chroma = chroma[:, future].T.astype(np.float64)
    norms = np.linalg.norm(onset_chroma, axis=1) * np.linalg.norm(
        future_chroma,
        axis=1,
    )
    similarity = np.divide(
        np.sum(onset_chroma * future_chroma, axis=1),
        norms,
        out=np.ones(onset_frames.size),
        where=norms > 1e-9,
    )
    movement = np.clip(1.0 - similarity, 0.0, 1.0)
    start_pitch = np.argmax(onset_chroma, axis=1)
    end_pitch = np.argmax(future_chroma, axis=1)
    delta = ((end_pitch - start_pitch + 6) % 12) - 6
    direction = np.sign(delta).astype(np.float64)
    return onset_chroma, movement.astype(np.float64), direction


def _sustain_features(
    harmonic_rms: np.ndarray,
    onset_frames: np.ndarray,
    bpm: float,
    sample_rate: int,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    beat_frames = max(1, int(60.0 / bpm * sample_rate / HOP_LENGTH))
    max_frames = beat_frames * 8
    durations = np.zeros(onset_frames.size, dtype=np.float64)
    scores = np.zeros(onset_frames.size, dtype=np.float64)
    cutoffs = np.zeros(onset_frames.size, dtype=np.float64)
    seconds_per_frame = HOP_LENGTH / sample_rate
    for index, raw_frame in enumerate(onset_frames):
        frame = int(np.clip(raw_frame, 0, max(0, harmonic_rms.size - 1)))
        start_level = float(harmonic_rms[frame])
        threshold = max(0.055, start_level * 0.42)
        end_limit = min(harmonic_rms.size - 1, frame + max_frames)
        below = 0
        end_frame = frame
        for cursor in range(frame + 1, end_limit + 1):
            below = below + 1 if harmonic_rms[cursor] < threshold else 0
            if below >= 3:
                end_frame = cursor - 2
                break
            end_frame = cursor
        duration = max(0.0, (end_frame - frame) * seconds_per_frame)
        durations[index] = duration
        scores[index] = float(
            np.clip(
                0.65 * duration / max(2.0 * 60.0 / bpm, 1e-6)
                + 0.35 * start_level,
                0.0,
                1.0,
            )
        )
        before = float(np.mean(harmonic_rms[max(frame, end_frame - 3) : end_frame + 1]))
        after = float(
            np.mean(
                harmonic_rms[
                    end_frame + 1 : min(harmonic_rms.size, end_frame + 5)
                ]
            )
        ) if end_frame + 1 < harmonic_rms.size else 0.0
        cutoffs[index] = max(0.0, min(1.0, (before - after) / max(before, 1e-6)))
    return scores, durations, cutoffs


def _masked_intervals(
    mask: np.ndarray,
    sample_rate: int,
    minimum_duration: float,
) -> tuple[tuple[float, float], ...]:
    intervals: list[tuple[float, float]] = []
    start: int | None = None
    for index, enabled in enumerate(np.append(mask, False)):
        if enabled and start is None:
            start = index
        elif not enabled and start is not None:
            begin = start * HOP_LENGTH / sample_rate
            end = index * HOP_LENGTH / sample_rate
            if end - begin >= minimum_duration:
                intervals.append((round(begin, 6), round(end, 6)))
            start = None
    return tuple(intervals)


def _analyze_structure(
    duration: float,
    measure_times: np.ndarray,
    onset_times: np.ndarray,
    onset_strengths: np.ndarray,
    onset_chroma: np.ndarray,
    onset_energy: np.ndarray,
    onset_percussive_ratio: np.ndarray,
) -> tuple[tuple[StructuralSection, ...], np.ndarray, np.ndarray]:
    boundaries = sorted(
        {
            0.0,
            *(
                float(value)
                for value in measure_times
                if 0.0 < value < duration
            ),
            duration,
        }
    )
    if len(boundaries) < 3:
        boundaries = [0.0, duration]
    features: list[np.ndarray] = []
    for start, end in zip(boundaries[:-1], boundaries[1:], strict=True):
        indices = np.flatnonzero((onset_times >= start) & (onset_times < end))
        if indices.size:
            chroma_mean = np.mean(onset_chroma[indices], axis=0)
            feature = np.concatenate(
                [
                    chroma_mean,
                    np.asarray(
                        [
                            np.mean(onset_energy[indices]),
                            np.mean(onset_percussive_ratio[indices]),
                            np.mean(onset_strengths[indices]),
                            min(1.0, indices.size / 12.0),
                        ]
                    ),
                ]
            )
        else:
            feature = np.zeros(16, dtype=np.float64)
        norm = float(np.linalg.norm(feature))
        features.append(feature / norm if norm > 1e-9 else feature)
    feature_matrix = np.vstack(features)

    phrase_features = []
    for index in range(len(features)):
        following = features[min(index + 1, len(features) - 1)]
        phrase = np.concatenate([features[index], following])
        norm = float(np.linalg.norm(phrase))
        phrase_features.append(phrase / norm if norm > 1e-9 else phrase)
    phrase_ids: list[int] = []
    representatives: list[np.ndarray] = []
    for phrase in phrase_features:
        similarities = [float(np.dot(phrase, value)) for value in representatives]
        if similarities and max(similarities) >= 0.88:
            phrase_ids.append(int(np.argmax(similarities)))
        else:
            phrase_ids.append(len(representatives))
            representatives.append(phrase)

    desired_sections = max(1, min(10, round(duration / 24.0)))
    novelty = np.zeros(len(features), dtype=np.float64)
    for index in range(1, len(features)):
        novelty[index] = 1.0 - float(
            np.clip(np.dot(features[index - 1], features[index]), -1.0, 1.0)
        )
    section_measure_starts = [0]
    candidates = sorted(range(1, len(features)), key=novelty.__getitem__, reverse=True)
    for candidate in candidates:
        if len(section_measure_starts) >= desired_sections:
            break
        if all(abs(candidate - kept) >= 2 for kept in section_measure_starts):
            section_measure_starts.append(candidate)
    section_measure_starts.sort()
    section_measure_starts.append(len(features))

    section_rows: list[tuple[int, int, float, float]] = []
    for start_index, end_index in zip(
        section_measure_starts[:-1],
        section_measure_starts[1:],
        strict=True,
    ):
        block = feature_matrix[start_index:end_index]
        energy = float(np.mean(block[:, 12])) if block.size else 0.0
        percussion = float(np.mean(block[:, 13])) if block.size else 0.0
        section_rows.append((start_index, end_index, energy, percussion))
    energies = np.asarray([row[2] for row in section_rows])
    high_energy = float(np.percentile(energies, 70.0)) if energies.size else 1.0
    low_energy = float(np.percentile(energies, 30.0)) if energies.size else 0.0

    sections: list[StructuralSection] = []
    for index, (start_index, end_index, energy, percussion) in enumerate(section_rows):
        previous_energy = section_rows[index - 1][2] if index else energy
        if len(section_rows) == 1:
            label = "song"
        elif index == 0 and section_rows[index][1] < len(features) * 0.25:
            label = "intro"
        elif index == len(section_rows) - 1 and energy < low_energy:
            label = "outro"
        elif energy >= high_energy:
            label = (
                "final_chorus"
                if end_index >= len(features) * 0.82
                else "chorus"
            )
        elif energy - previous_energy > 0.16:
            label = "buildup"
        elif energy <= low_energy and index > 0:
            label = "break"
        else:
            label = "verse"
        sections.append(
            StructuralSection(
                index=index,
                start=float(boundaries[start_index]),
                end=float(boundaries[end_index]),
                label=label,
                energy=energy,
                percussive_activity=percussion,
                harmonic_activity=max(0.0, 1.0 - percussion),
            )
        )

    onset_section_ids = np.zeros(onset_times.size, dtype=np.int64)
    for section in sections:
        onset_section_ids[
            (onset_times >= section.start) & (onset_times < section.end)
        ] = section.index
    onset_phrase_ids = np.zeros(onset_times.size, dtype=np.int64)
    for onset_index, onset_time in enumerate(onset_times):
        measure_index = max(0, int(np.searchsorted(boundaries, onset_time) - 1))
        onset_phrase_ids[onset_index] = phrase_ids[
            min(measure_index, len(phrase_ids) - 1)
        ]
    return tuple(sections), onset_section_ids, onset_phrase_ids
